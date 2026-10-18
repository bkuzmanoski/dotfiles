// Shared: CommandLineOptions Comparable FixedPointFormatStyle Log PrivateFramework ProcessSignals

import AppKit
import IOKit.storage
import System

extension FilePath {
  var applicationBundleName: String? {
    var reversedComponents = components.reversed().makeIterator()

    guard
      reversedComponents.next() != nil,
      reversedComponents.next() == "MacOS",
      reversedComponents.next() == "Contents",
      let bundleComponent = reversedComponents.next(),
      bundleComponent.extension == "app"
    else {
      return nil
    }

    return bundleComponent.string
  }
}

extension FileDescriptor {
  func waitUntilReadable(timeout: Duration) -> Bool {
    var pollDescriptor = pollfd(fd: rawValue, events: Int16(POLLIN), revents: 0)
    return poll(&pollDescriptor, 1, Int32((timeout / .milliseconds(1)).rounded(.up))) > 0
  }

  func read(appendingTo bytes: inout [UInt8]) -> Int {
    return withUnsafeTemporaryAllocation(byteCount: 256, alignment: 1) { buffer in
      let bytesRead = (try? read(into: buffer)) ?? 0

      bytes.append(contentsOf: buffer[..<bytesRead])

      return bytesRead
    }
  }
}

extension host_cpu_load_info {
  var userTicks: UInt32 { cpu_ticks.0 &+ cpu_ticks.3 }
  var systemTicks: UInt32 { cpu_ticks.1 }
  var idleTicks: UInt32 { cpu_ticks.2 }
}

extension CFDictionary {
  func int64Value(forKey key: CFString) -> Int64? {
    guard let rawValue = CFDictionaryGetValue(self, Unmanaged.passUnretained(key).toOpaque()) else {
      return nil
    }

    let value = Unmanaged<CFTypeRef>.fromOpaque(rawValue).takeUnretainedValue()
    var int64Value: Int64 = 0

    guard
      CFGetTypeID(value) == CFNumberGetTypeID(),
      CFNumberGetValue(unsafeDowncast(value, to: CFNumber.self), .sInt64Type, &int64Value)
    else {
      return nil
    }

    return int64Value
  }

  func byteCount(forKey key: CFString) -> UInt64 {
    return UInt64(clamping: int64Value(forKey: key) ?? 0)
  }
}

extension UnsignedInteger {
  func delta(since earlierValue: Self) -> Self {
    return self > earlierValue ? self - earlierValue : 0
  }
}

extension Double {
  func divided(by divisor: Double) -> Double? {
    return divisor > 0 ? self / divisor : nil
  }

  func percentage(of total: Double) -> Double? {
    return divided(by: total).map { $0 * 100 }
  }
}

extension String {
  init(nulTerminatedBytes bytes: UnsafeRawBufferPointer) {
    self.init(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
  }

  init<Value>(nulTerminatedBytesOf value: Value) {
    self = withUnsafeBytes(of: value) { String(nulTerminatedBytes: $0) }
  }

  var sanitizedForTerminal: String {
    guard utf8.contains(where: { $0 < 0x20 || $0 == 0x7F || $0 == 0xC2 }) else {
      return self
    }

    var scalars = UnicodeScalarView()

    for scalar in unicodeScalars {
      scalars.append(scalar.properties.generalCategory == .control ? "\u{FFFD}" : scalar)
    }

    return String(scalars)
  }
}

enum MachHost {
  private static let port = mach_host_self()

  static let pageSize: UInt64 = {
    var pageSize: vm_size_t = 0

    host_page_size(port, &pageSize)

    return UInt64(pageSize)
  }()

  static func cpuLoadInfo() -> host_cpu_load_info? {
    return hostInfo(host_cpu_load_info()) { host_statistics(port, HOST_CPU_LOAD_INFO, $0, &$1) }
  }

  static func virtualMemoryStatistics() -> vm_statistics64? {
    return hostInfo(vm_statistics64()) { host_statistics64(port, HOST_VM_INFO64, $0, &$1) }
  }

  private static func hostInfo<Info>(
    _ initialInfo: Info,
    _ query: (UnsafeMutablePointer<integer_t>, inout mach_msg_type_number_t) -> kern_return_t
  ) -> Info? {
    var info = initialInfo
    var count = mach_msg_type_number_t(MemoryLayout<Info>.stride / MemoryLayout<integer_t>.stride)

    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
        query(reboundPointer, &count)
      }
    }

    return result == KERN_SUCCESS ? info : nil
  }
}

enum MachTimebase {
  private static let nanosecondsPerTick: Double = {
    var timebase = mach_timebase_info_data_t()

    mach_timebase_info(&timebase)

    return Double(timebase.numer) / Double(timebase.denom)
  }()

  static func nanoseconds(fromTicks ticks: UInt64) -> Double {
    return Double(ticks) * nanosecondsPerTick
  }

  static func duration(fromTicks ticks: UInt64) -> Duration {
    return .seconds(nanoseconds(fromTicks: ticks) / 1_000_000_000)
  }
}

enum SystemControl {
  static func integer(named name: String) -> Int? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size

    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
      return nil
    }

    return Int(value)
  }

  static func string(named name: String) -> String? {
    var size = 0

    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
      return nil
    }

    return withUnsafeTemporaryAllocation(of: CChar.self, capacity: size) { buffer in
      guard let baseAddress = buffer.baseAddress, sysctlbyname(name, baseAddress, &size, nil, 0) == 0 else {
        return nil
      }

      return String(nulTerminatedBytes: UnsafeRawBufferPointer(buffer))
    }
  }
}

enum CoreType {
  case superCore
  case performanceCore
  case efficiencyCore
  case unknown

  static let performanceLevels: [CoreType] = {
    #if arch(arm64)
      guard let performanceLevelCount = SystemControl.integer(named: "hw.nperflevels") else {
        return []
      }

      return (0..<performanceLevelCount).map { performanceLevel in
        let name = SystemControl.string(named: "hw.perflevel\(performanceLevel).name") ?? ""

        if name.hasPrefix("Super") {
          return .superCore

        } else if name.hasPrefix("Performance") {
          return .performanceCore

        } else if name.hasPrefix("Efficiency") {
          return .efficiencyCore

        } else {
          return .unknown
        }
      }
    #else
      return []
    #endif
  }()

  static var isSupported: Bool { !performanceLevels.isEmpty }

  var title: String {
    switch self {
    case .superCore: "Super"
    case .performanceCore: "Performance"
    case .efficiencyCore: "Efficiency"
    case .unknown: "Unknown"
    }
  }
}

struct SampleClock {
  struct Interval {
    let startTime: UInt64
    let duration: Duration

    func percentage(ofNanoseconds nanoseconds: Double) -> Double {
      return nanoseconds.percentage(of: duration / .nanoseconds(1)) ?? 0
    }
  }

  private var previousSampleTime: UInt64?

  // The first sample only establishes a baseline, so it has no interval.
  mutating func nextInterval() -> Interval? {
    let sampleTime = mach_absolute_time()
    let interval = previousSampleTime.map { previousSampleTime in
      Interval(
        startTime: previousSampleTime,
        duration: MachTimebase.duration(fromTicks: sampleTime - previousSampleTime)
      )
    }

    self.previousSampleTime = sampleTime

    return interval
  }
}

struct CPUUsage {
  static let zero = CPUUsage(userPercentage: 0, systemPercentage: 0, idlePercentage: 0)

  let userPercentage: Double
  let systemPercentage: Double
  let idlePercentage: Double

  init(loadInfo: host_cpu_load_info, previousLoadInfo: host_cpu_load_info) {
    let userTicks = Double(loadInfo.userTicks &- previousLoadInfo.userTicks)
    let systemTicks = Double(loadInfo.systemTicks &- previousLoadInfo.systemTicks)
    let idleTicks = Double(loadInfo.idleTicks &- previousLoadInfo.idleTicks)
    let totalTicks = userTicks + systemTicks + idleTicks

    self.init(
      userPercentage: userTicks.percentage(of: totalTicks) ?? 0,
      systemPercentage: systemTicks.percentage(of: totalTicks) ?? 0,
      idlePercentage: idleTicks.percentage(of: totalTicks) ?? 0
    )
  }

  private init(userPercentage: Double, systemPercentage: Double, idlePercentage: Double) {
    self.userPercentage = userPercentage
    self.systemPercentage = systemPercentage
    self.idlePercentage = idlePercentage
  }
}

struct LoadAverages {
  static let zero = LoadAverages(oneMinute: 0, fiveMinutes: 0, fifteenMinutes: 0)

  let oneMinute: Double
  let fiveMinutes: Double
  let fifteenMinutes: Double

  static var current: LoadAverages {
    withUnsafeTemporaryAllocation(of: Double.self, capacity: 3) { loadAverages in
      guard let baseAddress = loadAverages.baseAddress, getloadavg(baseAddress, 3) == 3 else {
        return .zero
      }

      return LoadAverages(oneMinute: loadAverages[0], fiveMinutes: loadAverages[1], fifteenMinutes: loadAverages[2])
    }
  }
}

struct MemoryUsage {
  let usedBytes: UInt64
  let wiredBytes: UInt64
  let compressedBytes: UInt64
  let totalBytes: UInt64

  static var current: MemoryUsage {
    let totalBytes = ProcessInfo.processInfo.physicalMemory

    guard let statistics = MachHost.virtualMemoryStatistics() else {
      return MemoryUsage(usedBytes: 0, wiredBytes: 0, compressedBytes: 0, totalBytes: totalBytes)
    }

    let internalPageCount = UInt64(statistics.internal_page_count)
    let purgeablePageCount = min(UInt64(statistics.purgeable_count), internalPageCount)
    let wiredBytes = UInt64(statistics.wire_count) * MachHost.pageSize
    let compressedBytes = UInt64(statistics.compressor_page_count) * MachHost.pageSize

    return MemoryUsage(
      usedBytes: (internalPageCount - purgeablePageCount) * MachHost.pageSize + wiredBytes + compressedBytes,
      wiredBytes: wiredBytes,
      compressedBytes: compressedBytes,
      totalBytes: totalBytes
    )
  }
}

struct TransferByteCounts {
  static let zero = TransferByteCounts(inbound: 0, outbound: 0)

  var inbound: UInt64
  var outbound: UInt64

  static func += (lhs: inout TransferByteCounts, rhs: TransferByteCounts) {
    lhs.inbound += rhs.inbound
    lhs.outbound += rhs.outbound
  }

  func delta(since earlierByteCounts: TransferByteCounts) -> TransferByteCounts {
    return TransferByteCounts(
      inbound: inbound.delta(since: earlierByteCounts.inbound),
      outbound: outbound.delta(since: earlierByteCounts.outbound)
    )
  }
}

struct TransferRates {
  let inboundBytesPerSecond: Double
  let outboundBytesPerSecond: Double

  var totalBytesPerSecond: Double { inboundBytesPerSecond + outboundBytesPerSecond }

  init(inboundBytesPerSecond: Double, outboundBytesPerSecond: Double) {
    self.inboundBytesPerSecond = inboundBytesPerSecond
    self.outboundBytesPerSecond = outboundBytesPerSecond
  }

  init(byteCounts: TransferByteCounts, elapsed: Duration) {
    let elapsedSeconds = elapsed / .seconds(1)
    self.init(
      inboundBytesPerSecond: Double(byteCounts.inbound).divided(by: elapsedSeconds) ?? 0,
      outboundBytesPerSecond: Double(byteCounts.outbound).divided(by: elapsedSeconds) ?? 0
    )
  }
}

struct SystemUsage {
  struct Rates {
    let cpu: CPUUsage
    let disk: TransferRates
    let network: TransferRates
  }

  let loadAverages: LoadAverages
  let memory: MemoryUsage
  let rates: Rates?
}

struct SystemUsageSampler {
  private struct DiskSampler {
    private var previousDriveByteCounts: [UInt64: TransferByteCounts] = [:]

    mutating func byteCountsSinceLastSample() -> TransferByteCounts {
      let driveByteCounts = Self.driveByteCounts()

      var byteCounts = TransferByteCounts.zero

      for (driveID, currentByteCounts) in driveByteCounts {
        if let previousByteCounts = previousDriveByteCounts[driveID] {
          byteCounts += currentByteCounts.delta(since: previousByteCounts)
        }
      }

      self.previousDriveByteCounts = driveByteCounts

      return byteCounts
    }

    private static func driveByteCounts() -> [UInt64: TransferByteCounts] {
      var iterator: io_iterator_t = 0

      guard
        IOServiceGetMatchingServices(
          kIOMainPortDefault,
          IOServiceMatching("IOBlockStorageDriver"),
          &iterator
        ) == KERN_SUCCESS
      else {
        return [:]
      }

      defer {
        IOObjectRelease(iterator)
      }

      var driveByteCounts: [UInt64: TransferByteCounts] = [:]

      while case let service = IOIteratorNext(iterator), service != 0 {
        defer {
          IOObjectRelease(service)
        }

        var driveID: UInt64 = 0

        guard
          IORegistryEntryGetRegistryEntryID(service, &driveID) == KERN_SUCCESS,
          let statistics = IORegistryEntryCreateCFProperty(
            service,
            kIOBlockStorageDriverStatisticsKey as CFString,
            kCFAllocatorDefault,
            0
          )?.takeRetainedValue(),
          CFGetTypeID(statistics) == CFDictionaryGetTypeID()
        else {
          continue
        }

        let statisticsDictionary = unsafeDowncast(statistics, to: CFDictionary.self)

        driveByteCounts[driveID] = TransferByteCounts(
          inbound: statisticsDictionary.byteCount(forKey: kIOBlockStorageDriverStatisticsBytesReadKey as CFString),
          outbound: statisticsDictionary.byteCount(forKey: kIOBlockStorageDriverStatisticsBytesWrittenKey as CFString)
        )
      }

      return driveByteCounts
    }
  }

  private struct NetworkSampler {
    private var interfaceListBuffer = [UInt8](repeating: 0, count: 4096)
    private var previousInterfaceByteCounts: [UInt16: TransferByteCounts] = [:]

    mutating func byteCountsSinceLastSample() -> TransferByteCounts {
      guard let interfaceListLength = readInterfaceList() else {
        return .zero
      }

      let interfaceListBuffer = interfaceListBuffer

      var byteCounts = TransferByteCounts.zero

      interfaceListBuffer.withUnsafeBytes { bytes in
        var offset = 0

        while offset + MemoryLayout<if_msghdr>.size <= interfaceListLength {
          let messageHeader = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)

          guard messageHeader.ifm_msglen > 0 else {
            break
          }

          if Int32(messageHeader.ifm_type) == RTM_IFINFO2,
            offset + MemoryLayout<if_msghdr2>.size <= interfaceListLength
          {
            let interfaceMessage = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)

            if Int32(interfaceMessage.ifm_data.ifi_type) == IFT_ETHER {
              let interfaceByteCounts = TransferByteCounts(
                inbound: interfaceMessage.ifm_data.ifi_ibytes,
                outbound: interfaceMessage.ifm_data.ifi_obytes
              )

              if let previousByteCounts = previousInterfaceByteCounts[interfaceMessage.ifm_index] {
                byteCounts += TransferByteCounts(
                  inbound: Self.truncatedCounterDelta(interfaceByteCounts.inbound, since: previousByteCounts.inbound),
                  outbound: Self.truncatedCounterDelta(interfaceByteCounts.outbound, since: previousByteCounts.outbound)
                )
              }

              self.previousInterfaceByteCounts[interfaceMessage.ifm_index] = interfaceByteCounts
            }
          }

          offset += Int(messageHeader.ifm_msglen)
        }
      }

      return byteCounts
    }

    private mutating func readInterfaceList() -> Int? {
      var managementInformationBase: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]

      while true {
        var length = interfaceListBuffer.count

        let result = interfaceListBuffer.withUnsafeMutableBytes { buffer in
          sysctl(
            &managementInformationBase,
            UInt32(managementInformationBase.count),
            buffer.baseAddress,
            &length,
            nil,
            0
          )
        }

        if result == 0 {
          return length
        }

        guard errno == ENOMEM else {
          return nil
        }

        self.interfaceListBuffer = [UInt8](repeating: 0, count: interfaceListBuffer.count * 2)
      }
    }

    private static func truncatedCounterDelta(_ counter: UInt64, since previousCounter: UInt64) -> UInt64 {
      return UInt64(UInt32(truncatingIfNeeded: counter) &- UInt32(truncatingIfNeeded: previousCounter))
    }
  }

  private var sampleClock = SampleClock()
  private var previousCPULoadInfo: host_cpu_load_info?
  private var diskSampler = DiskSampler()
  private var networkSampler = NetworkSampler()

  mutating func sample() -> SystemUsage {
    let sampleInterval = sampleClock.nextInterval()
    let cpuLoadInfo = MachHost.cpuLoadInfo()
    let diskByteCounts = diskSampler.byteCountsSinceLastSample()
    let networkByteCounts = networkSampler.byteCountsSinceLastSample()

    let cpuUsage: CPUUsage

    if let cpuLoadInfo, let previousCPULoadInfo {
      cpuUsage = CPUUsage(loadInfo: cpuLoadInfo, previousLoadInfo: previousCPULoadInfo)
    } else {
      cpuUsage = CPUUsage.zero
    }

    self.previousCPULoadInfo = cpuLoadInfo

    return SystemUsage(
      loadAverages: .current,
      memory: .current,
      rates: sampleInterval.map { sampleInterval in
        SystemUsage.Rates(
          cpu: cpuUsage,
          disk: TransferRates(byteCounts: diskByteCounts, elapsed: sampleInterval.duration),
          network: TransferRates(byteCounts: networkByteCounts, elapsed: sampleInterval.duration)
        )
      }
    )
  }
}

// swift-format-ignore: AlwaysUseLowerCamelCase
@_silgen_name("responsibility_get_pid_responsible_for_pid")
func responsibility_get_pid_responsible_for_pid(_ processIdentifier: pid_t) -> pid_t

struct RunningProcess {
  struct BSDInfo: Equatable {
    let commandName: String
    let parentProcessIdentifier: pid_t?
  }

  struct UsageSample {
    let startTime: UInt64
    let cpuTicks: UInt64
    let memoryFootprint: UInt64
    let disk: TransferByteCounts
  }

  struct ThreadSample {
    let threadIdentifier: UInt64
    let name: String?
    let cpuNanoseconds: UInt64
  }

  private enum ThreadCounts {
    static let flavor: Int32 = 34
    static let headerWordCount = 1
    static let wordsPerPerformanceLevel = 5
    static let userTicksWordOffset = 2
    static let systemTicksWordOffset = 3
  }

  private static let listThreadIdentifiersFlavor: Int32 = 28

  let processIdentifier: pid_t

  var executablePath: FilePath? {
    withUnsafeTemporaryAllocation(of: CChar.self, capacity: 4 * Int(MAXPATHLEN)) { buffer in
      guard
        let baseAddress = buffer.baseAddress,
        proc_pidpath(processIdentifier, baseAddress, UInt32(buffer.count)) > 0
      else {
        return nil
      }

      return FilePath(platformString: baseAddress)
    }
  }

  var displayName: String? {
    guard
      let localizedName = NSRunningApplication(processIdentifier: processIdentifier)?.localizedName,
      !localizedName.isEmpty
    else {
      return nil
    }

    return localizedName
  }

  var bsdInfo: BSDInfo? {
    var shortInfo = proc_bsdshortinfo()

    let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)

    guard proc_pidinfo(processIdentifier, PROC_PIDT_SHORTBSDINFO, 0, &shortInfo, size) == size else {
      return nil
    }

    let commandName = String(nulTerminatedBytesOf: shortInfo.pbsi_comm)
    let parentProcessIdentifier = pid_t(shortInfo.pbsi_ppid)

    return BSDInfo(
      commandName: commandName,
      parentProcessIdentifier: parentProcessIdentifier == processIdentifier ? nil : parentProcessIdentifier
    )
  }

  var parentProcess: RunningProcess? { bsdInfo?.parentProcessIdentifier.map(RunningProcess.init(processIdentifier:)) }

  var responsibleProcess: RunningProcess? {
    let responsibleProcessIdentifier = responsibility_get_pid_responsible_for_pid(processIdentifier)

    guard responsibleProcessIdentifier > 0, responsibleProcessIdentifier != processIdentifier else {
      return nil
    }

    return RunningProcess(processIdentifier: responsibleProcessIdentifier)
  }

  static func listAllProcessIdentifiers(into buffer: inout [pid_t]) -> Int {
    while true {
      let count = Int(buffer.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) })

      guard count >= buffer.count else {
        return max(count, 0)
      }

      buffer = [pid_t](repeating: 0, count: buffer.count * 2)
    }
  }

  func usageSample() throws(Errno) -> UsageSample {
    var rusageInfo = rusage_info_v4()

    let result = withUnsafeMutablePointer(to: &rusageInfo) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPointer in
        proc_pid_rusage(processIdentifier, RUSAGE_INFO_V4, reboundPointer)
      }
    }

    guard result == 0 else {
      throw Errno(rawValue: errno)
    }

    return UsageSample(
      startTime: rusageInfo.ri_proc_start_abstime,
      cpuTicks: rusageInfo.ri_user_time + rusageInfo.ri_system_time,
      memoryFootprint: rusageInfo.ri_phys_footprint,
      disk: TransferByteCounts(
        inbound: rusageInfo.ri_diskio_bytesread,
        outbound: rusageInfo.ri_diskio_byteswritten
      )
    )
  }

  func listThreadIdentifiers(into buffer: inout [UInt64]) throws(Errno) -> Int {
    while true {
      let byteCount = buffer.withUnsafeMutableBytes { bytes in
        proc_pidinfo(processIdentifier, Self.listThreadIdentifiersFlavor, 0, bytes.baseAddress, Int32(bytes.count))
      }

      guard byteCount > 0 else {
        throw Errno(rawValue: errno)
      }

      let count = Int(byteCount) / MemoryLayout<UInt64>.stride

      guard count >= buffer.count else {
        return count
      }

      buffer = [UInt64](repeating: 0, count: buffer.count * 2)
    }
  }

  func threadSample(threadIdentifier: UInt64) -> ThreadSample? {
    var threadInfo = proc_threadinfo()

    let size = Int32(MemoryLayout<proc_threadinfo>.size)

    guard proc_pidinfo(processIdentifier, PROC_PIDTHREADID64INFO, threadIdentifier, &threadInfo, size) == size else {
      return nil
    }

    let name = String(nulTerminatedBytesOf: threadInfo.pth_name)

    return ThreadSample(
      threadIdentifier: threadIdentifier,
      name: name.isEmpty ? nil : name.sanitizedForTerminal,
      cpuNanoseconds: threadInfo.pth_user_time + threadInfo.pth_system_time
    )
  }

  func threadCPUTicksByPerformanceLevel(threadIdentifier: UInt64) -> [UInt64] {
    let performanceLevelCount = CoreType.performanceLevels.count

    guard performanceLevelCount > 0 else {
      return []
    }

    let wordCount = ThreadCounts.headerWordCount + performanceLevelCount * ThreadCounts.wordsPerPerformanceLevel

    return withUnsafeTemporaryAllocation(of: UInt64.self, capacity: wordCount) { words in
      let byteCount = proc_pidinfo(
        processIdentifier,
        ThreadCounts.flavor,
        threadIdentifier,
        words.baseAddress,
        Int32(wordCount * MemoryLayout<UInt64>.stride)
      )

      guard byteCount > 0 else {
        return []
      }

      let reportedPerformanceLevelCount = Int(UInt16(truncatingIfNeeded: words[0]))

      return (0..<min(reportedPerformanceLevelCount, performanceLevelCount)).map { performanceLevel in
        let offset = ThreadCounts.headerWordCount + performanceLevel * ThreadCounts.wordsPerPerformanceLevel
        return words[offset + ThreadCounts.userTicksWordOffset] + words[offset + ThreadCounts.systemTicksWordOffset]
      }
    }
  }
}

struct ProcessOwner: Identifiable {
  enum Kind {
    case application
    case process
  }

  struct ID: Hashable {
    let processIdentifier: pid_t
    let kind: Kind
  }

  let processIdentifier: pid_t
  let kind: Kind
  let name: String
  let normalizedName: String

  var id: ID { ID(processIdentifier: processIdentifier, kind: kind) }

  init(processIdentifier: pid_t, kind: Kind, name: String) {
    self.processIdentifier = processIdentifier
    self.kind = kind
    self.name = name.sanitizedForTerminal
    self.normalizedName = self.name.lowercased()
  }

  init(of process: RunningProcess, executablePath: FilePath?, parentProcess: RunningProcess?, processName: String) {
    if let responsibleProcess = process.responsibleProcess,
      let application = Self.application(running: responsibleProcess, executablePath: responsibleProcess.executablePath)
    {
      self = application

    } else if let application = Self.application(running: process, executablePath: executablePath) {
      self = application

    } else if let application = Self.application(runningAncestorOf: process, startingAt: parentProcess) {
      self = application

    } else {
      self = ProcessOwner(processIdentifier: process.processIdentifier, kind: .process, name: processName)
    }
  }

  private static func application(running process: RunningProcess, executablePath: FilePath?) -> ProcessOwner? {
    guard let applicationBundleName = executablePath?.applicationBundleName else {
      return nil
    }

    return ProcessOwner(processIdentifier: process.processIdentifier, kind: .application, name: applicationBundleName)
  }

  private static func application(
    runningAncestorOf process: RunningProcess,
    startingAt parentProcess: RunningProcess?
  ) -> ProcessOwner? {
    var visitedProcessIdentifiers: Set<pid_t> = [process.processIdentifier]
    var ancestorProcess = parentProcess

    while let currentProcess = ancestorProcess,
      currentProcess.processIdentifier > 1,
      visitedProcessIdentifiers.insert(currentProcess.processIdentifier).inserted
    {
      if let application = application(running: currentProcess, executablePath: currentProcess.executablePath) {
        return application
      }

      ancestorProcess = currentProcess.parentProcess
    }

    return nil
  }
}

struct ProcessMetadata {
  let processIdentifier: pid_t
  let name: String
  let parentProcessIdentifier: pid_t?
  let processOwner: ProcessOwner

  init?(of process: RunningProcess, bsdInfo: RunningProcess.BSDInfo?) {
    let executablePath = process.executablePath

    guard let name = process.displayName ?? executablePath?.lastComponent?.string ?? bsdInfo?.commandName else {
      return nil
    }

    self.processIdentifier = process.processIdentifier
    self.name = name.sanitizedForTerminal
    self.parentProcessIdentifier = bsdInfo?.parentProcessIdentifier
    self.processOwner = ProcessOwner(
      of: process,
      executablePath: executablePath,
      parentProcess: parentProcessIdentifier.map(RunningProcess.init(processIdentifier:)),
      processName: name
    )
  }
}

struct ResourceUsage {
  struct Rates {
    let cpuPercentage: Double
    let disk: TransferRates
    let network: TransferRates
  }

  let memoryFootprint: UInt64
  let rates: Rates?
}

struct ProcessOwnerUsage: Identifiable {
  let processOwner: ProcessOwner
  let usage: ResourceUsage

  var id: ProcessOwner.ID { processOwner.id }
}

struct ProcessUsage {
  let process: ProcessMetadata
  let usage: ResourceUsage
}

struct ProcessUsageSnapshot {
  var processOwners: [ProcessOwnerUsage]
  let processes: [ProcessUsage]
  let applicationCount: Int
  let restrictedProcessCount: Int
  let isBaseline: Bool
}

struct NetworkStatisticsFramework {
  typealias ManagerReference = OpaquePointer
  typealias SourceReference = OpaquePointer
  typealias SourceAddedHandler = @convention(block) (SourceReference?, UnsafeMutableRawPointer?) -> Void
  typealias SourcePropertiesHandler = @convention(block) (CFDictionary) -> Void
  typealias CompletionHandler = @convention(block) () -> Void
  typealias CreateManagerFunction =
    @convention(c) (CFAllocator?, DispatchQueue, @escaping SourceAddedHandler) -> ManagerReference?
  typealias ManagerFunction = @convention(c) (ManagerReference) -> Void
  typealias QueryAllSourcesFunction = @convention(c) (ManagerReference, @escaping CompletionHandler) -> Void
  typealias SourceFunction = @convention(c) (SourceReference) -> Void
  typealias SetSourcePropertiesHandlerFunction =
    @convention(c) (SourceReference, @escaping SourcePropertiesHandler) -> Void
  typealias SetSourceRemovedHandlerFunction = @convention(c) (SourceReference, @escaping CompletionHandler) -> Void

  let createManager: CreateManagerFunction
  let destroyManager: ManagerFunction
  let addAllTCPSources: ManagerFunction
  let addAllUDPSources: ManagerFunction
  let queryAllSources: QueryAllSourcesFunction
  let querySourceDescription: SourceFunction
  let setSourceDescriptionHandler: SetSourcePropertiesHandlerFunction
  let setSourceCountsHandler: SetSourcePropertiesHandlerFunction
  let setSourceRemovedHandler: SetSourceRemovedHandlerFunction
  let processIdentifierKey: CFString
  let receivedBytesKey: CFString
  let sentBytesKey: CFString

  init() throws {
    let framework = try PrivateFramework(named: "NetworkStatistics")

    self.createManager = try framework.symbol(named: "NStatManagerCreate")
    self.destroyManager = try framework.symbol(named: "NStatManagerDestroy")
    self.addAllTCPSources = try framework.symbol(named: "NStatManagerAddAllTCP")
    self.addAllUDPSources = try framework.symbol(named: "NStatManagerAddAllUDP")
    self.queryAllSources = try framework.symbol(named: "NStatManagerQueryAllSources")
    self.querySourceDescription = try framework.symbol(named: "NStatSourceQueryDescription")
    self.setSourceDescriptionHandler = try framework.symbol(named: "NStatSourceSetDescriptionBlock")
    self.setSourceCountsHandler = try framework.symbol(named: "NStatSourceSetCountsBlock")
    self.setSourceRemovedHandler = try framework.symbol(named: "NStatSourceSetRemovedBlock")
    self.processIdentifierKey = try framework.constant(named: "kNStatSrcKeyPID")
    self.receivedBytesKey = try framework.constant(named: "kNStatSrcKeyRxBytes")
    self.sentBytesKey = try framework.constant(named: "kNStatSrcKeyTxBytes")
  }
}

@MainActor
final class NetworkFlowMonitor {
  enum Error: Swift.Error, LocalizedError {
    case failedToCreateManager

    var errorDescription: String? {
      switch self {
      case .failedToCreateManager: "Failed to create network statistics manager."
      }
    }
  }

  @MainActor
  private final class Flow {
    var processIdentifier: pid_t = 0
    var byteCounts = TransferByteCounts.zero
    var accountedByteCounts: TransferByteCounts?
    var isRemoved = false
  }

  private let framework: NetworkStatisticsFramework
  private var manager: NetworkStatisticsFramework.ManagerReference?
  private var flows: [Flow] = []
  private var hasEstablishedBaseline = false

  init() throws {
    self.framework = try NetworkStatisticsFramework()

    guard
      let manager = framework.createManager(
        nil,
        .main,
        { [weak self] source, _ in
          guard let self, let source else {
            return
          }

          trackFlow(for: source)
        }
      )
    else {
      throw Error.failedToCreateManager
    }

    framework.addAllTCPSources(manager)
    framework.addAllUDPSources(manager)

    self.manager = manager
  }

  isolated deinit {
    if let manager {
      framework.destroyManager(manager)
    }
  }

  func byteCountsSinceLastSample() async -> [pid_t: TransferByteCounts] {
    guard let manager else {
      return [:]
    }

    await withCheckedContinuation { continuation in
      framework.queryAllSources(manager) {
        continuation.resume()
      }
    }

    var byteCounts: [pid_t: TransferByteCounts] = [:]

    for flow in flows {
      let accountedByteCounts = flow.accountedByteCounts ?? (hasEstablishedBaseline ? .zero : flow.byteCounts)
      let byteCountDelta = flow.byteCounts.delta(since: accountedByteCounts)

      if flow.processIdentifier > 0, byteCountDelta.inbound > 0 || byteCountDelta.outbound > 0 {
        byteCounts[flow.processIdentifier, default: .zero] += byteCountDelta
      }

      flow.accountedByteCounts = flow.byteCounts
    }

    self.flows.removeAll(where: \.isRemoved)
    self.hasEstablishedBaseline = true

    return byteCounts
  }

  private func trackFlow(for source: NetworkStatisticsFramework.SourceReference) {
    let flow = Flow()
    let framework = framework

    framework.setSourceDescriptionHandler(source) { description in
      let processIdentifier = pid_t(
        truncatingIfNeeded: description.int64Value(forKey: framework.processIdentifierKey) ?? 0
      )
      flow.processIdentifier = processIdentifier
    }

    framework.setSourceCountsHandler(source) { counts in
      let byteCounts = TransferByteCounts(
        inbound: counts.byteCount(forKey: framework.receivedBytesKey),
        outbound: counts.byteCount(forKey: framework.sentBytesKey)
      )
      flow.byteCounts = byteCounts
    }

    framework.setSourceRemovedHandler(source) {
      flow.isRemoved = true
    }

    framework.querySourceDescription(source)

    self.flows.append(flow)
  }
}

@MainActor
final class ProcessUsageSampler {
  private struct TrackedProcess {
    let metadata: ProcessMetadata
    let bsdInfo: RunningProcess.BSDInfo?
    let sample: RunningProcess.UsageSample
    let sampleGeneration: UInt64
  }

  private struct Accumulator {
    var cpuTicks: UInt64 = 0
    var memoryFootprint: UInt64 = 0
    var disk = TransferByteCounts.zero
    var network = TransferByteCounts.zero

    static func += (lhs: inout Accumulator, rhs: Accumulator) {
      lhs.cpuTicks += rhs.cpuTicks
      lhs.memoryFootprint += rhs.memoryFootprint
      lhs.disk += rhs.disk
      lhs.network += rhs.network
    }

    mutating func addSample(_ sample: RunningProcess.UsageSample, since previousSample: RunningProcess.UsageSample?) {
      self.cpuTicks += sample.cpuTicks.delta(since: previousSample?.cpuTicks ?? 0)
      self.memoryFootprint += sample.memoryFootprint
      self.disk += sample.disk.delta(since: previousSample?.disk ?? .zero)
    }

    func resourceUsage(over sampleInterval: SampleClock.Interval?) -> ResourceUsage {
      return ResourceUsage(
        memoryFootprint: memoryFootprint,
        rates: sampleInterval.map { sampleInterval in
          ResourceUsage.Rates(
            cpuPercentage: sampleInterval.percentage(ofNanoseconds: MachTimebase.nanoseconds(fromTicks: cpuTicks)),
            disk: TransferRates(byteCounts: disk, elapsed: sampleInterval.duration),
            network: TransferRates(byteCounts: network, elapsed: sampleInterval.duration)
          )
        }
      )
    }
  }

  private struct ProcessOwnerAccumulator {
    let processOwner: ProcessOwner
    var accumulator = Accumulator()

    func processOwnerUsage(over sampleInterval: SampleClock.Interval?) -> ProcessOwnerUsage {
      return ProcessOwnerUsage(processOwner: processOwner, usage: accumulator.resourceUsage(over: sampleInterval))
    }
  }

  private let networkFlowMonitor: NetworkFlowMonitor
  private var sampleClock = SampleClock()
  private var trackedProcesses: [pid_t: TrackedProcess] = [:]
  private var processIdentifierBuffer = [pid_t](repeating: 0, count: 1024)
  private var sampleGeneration: UInt64 = 0
  private var previousProcessOwnerCount = 0

  init(networkFlowMonitor: NetworkFlowMonitor) {
    self.networkFlowMonitor = networkFlowMonitor
  }

  func sample() async -> ProcessUsageSnapshot {
    var networkByteCounts = await networkFlowMonitor.byteCountsSinceLastSample()

    let sampleInterval = sampleClock.nextInterval()
    let processIdentifierCount = RunningProcess.listAllProcessIdentifiers(into: &processIdentifierBuffer)

    var processOwnerAccumulators: [ProcessOwner.ID: ProcessOwnerAccumulator] = [:]
    processOwnerAccumulators.reserveCapacity(previousProcessOwnerCount)

    var processes: [ProcessUsage] = []
    processes.reserveCapacity(trackedProcesses.count)

    var restrictedProcessCount = 0

    self.sampleGeneration &+= 1

    for processIdentifier in processIdentifierBuffer[..<processIdentifierCount] {
      let runningProcess = RunningProcess(processIdentifier: processIdentifier)
      let sample: RunningProcess.UsageSample

      do throws(Errno) {
        sample = try runningProcess.usageSample()
      } catch {
        if error == .notPermitted {
          restrictedProcessCount += 1
        }

        continue
      }

      let bsdInfo = runningProcess.bsdInfo
      let trackedProcess = trackedProcesses[processIdentifier].flatMap { trackedProcess in
        trackedProcess.sample.startTime == sample.startTime ? trackedProcess : nil
      }
      let metadata: ProcessMetadata

      // Because `exec` preserves the PID and start time, changed command or parent data invalidates cached metadata.
      if let trackedProcess, trackedProcess.bsdInfo == bsdInfo {
        metadata = trackedProcess.metadata

      } else if let resolvedMetadata = ProcessMetadata(of: runningProcess, bsdInfo: bsdInfo) {
        metadata = resolvedMetadata

      } else {
        continue
      }

      // An untracked process that predates the previous sample uses the current sample as its baseline,
      // so its lifetime usage is not attributed to a single interval.
      let hasStartedSincePreviousSample = sampleInterval.map { sample.startTime >= $0.startTime } ?? false
      let previousSample = trackedProcess?.sample ?? (hasStartedSincePreviousSample ? nil : sample)

      var accumulator = Accumulator()

      accumulator.addSample(sample, since: previousSample)

      if let processNetworkByteCounts = networkByteCounts.removeValue(forKey: processIdentifier) {
        accumulator.network += processNetworkByteCounts
      }

      self.trackedProcesses[processIdentifier] = TrackedProcess(
        metadata: metadata,
        bsdInfo: bsdInfo,
        sample: sample,
        sampleGeneration: sampleGeneration
      )

      processOwnerAccumulators[
        metadata.processOwner.id,
        default: ProcessOwnerAccumulator(processOwner: metadata.processOwner)
      ].accumulator += accumulator
      processes.append(ProcessUsage(process: metadata, usage: accumulator.resourceUsage(over: sampleInterval)))
    }

    for (processIdentifier, byteCounts) in networkByteCounts {
      guard let processOwner = trackedProcesses[processIdentifier]?.metadata.processOwner else {
        continue
      }

      processOwnerAccumulators[
        processOwner.id,
        default: ProcessOwnerAccumulator(processOwner: processOwner)
      ].accumulator.network += byteCounts
    }

    if trackedProcesses.count != processes.count {
      self.trackedProcesses = trackedProcesses.filter { $0.value.sampleGeneration == sampleGeneration }
    }

    let processOwners = processOwnerAccumulators.values.map { $0.processOwnerUsage(over: sampleInterval) }

    self.previousProcessOwnerCount = processOwnerAccumulators.count

    return ProcessUsageSnapshot(
      processOwners: processOwners,
      processes: processes,
      applicationCount: processOwners.count { $0.processOwner.kind == .application },
      restrictedProcessCount: restrictedProcessCount,
      isBaseline: sampleInterval == nil
    )
  }
}

struct ThreadUsage: Identifiable {
  struct CPU {
    let coreType: CoreType?
    let percentage: Double
    let sharePercentage: Double
  }

  let threadIdentifier: UInt64
  let name: String?
  let cpu: CPU?

  var id: UInt64 { threadIdentifier }

  static func precedesByCPUUsage(_ lhs: ThreadUsage, _ rhs: ThreadUsage) -> Bool {
    return (rhs.cpu?.percentage ?? 0, lhs.threadIdentifier) < (lhs.cpu?.percentage ?? 0, rhs.threadIdentifier)
  }
}

struct ThreadUsageSnapshot {
  var threads: [ThreadUsage]
  let cpuPercentage: Double?

  var isBaseline: Bool { cpuPercentage == nil }
}

struct ThreadUsageSampler {
  private struct ThreadCPUTimes {
    let totalNanoseconds: UInt64
    let ticksByPerformanceLevel: [UInt64]
  }

  private struct ThreadMeasurement {
    let sample: RunningProcess.ThreadSample
    let cpuNanosecondsDelta: UInt64
    let coreType: CoreType?

    func threadUsage(over sampleInterval: SampleClock.Interval?, totalCPUNanosecondsDelta: UInt64) -> ThreadUsage {
      return ThreadUsage(
        threadIdentifier: sample.threadIdentifier,
        name: sample.name,
        cpu: sampleInterval.map { sampleInterval in
          ThreadUsage.CPU(
            coreType: coreType,
            percentage: sampleInterval.percentage(ofNanoseconds: Double(cpuNanosecondsDelta)),
            sharePercentage: Double(cpuNanosecondsDelta).percentage(of: Double(totalCPUNanosecondsDelta)) ?? 0
          )
        }
      )
    }
  }

  private let process: RunningProcess
  private let processStartTime: UInt64
  private var threadIdentifierBuffer = [UInt64](repeating: 0, count: 256)
  private var previousThreadCPUTimes: [UInt64: ThreadCPUTimes] = [:]
  private var sampleClock = SampleClock()

  init(process: RunningProcess) throws(Errno) {
    self.process = process
    self.processStartTime = try process.usageSample().startTime
  }

  mutating func sample() throws(Errno) -> ThreadUsageSnapshot {
    guard try process.usageSample().startTime == processStartTime else {
      throw .noSuchProcess
    }

    let threadIdentifierCount = try process.listThreadIdentifiers(into: &threadIdentifierBuffer)
    let sampleInterval = sampleClock.nextInterval()

    var threadMeasurements: [ThreadMeasurement] = []
    threadMeasurements.reserveCapacity(threadIdentifierCount)

    var currentThreadCPUTimes: [UInt64: ThreadCPUTimes] = [:]
    currentThreadCPUTimes.reserveCapacity(threadIdentifierCount)

    var totalCPUNanosecondsDelta: UInt64 = 0

    for threadIdentifier in threadIdentifierBuffer[..<threadIdentifierCount] {
      guard let threadSample = process.threadSample(threadIdentifier: threadIdentifier) else {
        continue
      }

      let previousCPUTimes = previousThreadCPUTimes[threadIdentifier]
      let cpuNanosecondsDelta =
        sampleInterval == nil
        ? 0
        : threadSample.cpuNanoseconds.delta(since: previousCPUTimes?.totalNanoseconds ?? 0)
      let cpuTicksByPerformanceLevel =
        sampleInterval == nil || cpuNanosecondsDelta > 0
        ? process.threadCPUTicksByPerformanceLevel(threadIdentifier: threadIdentifier)
        : previousCPUTimes?.ticksByPerformanceLevel ?? []
      let coreType =
        cpuNanosecondsDelta > 0
        ? Self.predominantCoreType(
          cpuTicksByPerformanceLevel: cpuTicksByPerformanceLevel,
          since: previousCPUTimes?.ticksByPerformanceLevel ?? []
        )
        : nil

      threadMeasurements.append(
        ThreadMeasurement(sample: threadSample, cpuNanosecondsDelta: cpuNanosecondsDelta, coreType: coreType)
      )
      currentThreadCPUTimes[threadIdentifier] = ThreadCPUTimes(
        totalNanoseconds: threadSample.cpuNanoseconds,
        ticksByPerformanceLevel: cpuTicksByPerformanceLevel
      )
      totalCPUNanosecondsDelta += cpuNanosecondsDelta
    }

    self.previousThreadCPUTimes = currentThreadCPUTimes

    return ThreadUsageSnapshot(
      threads: threadMeasurements.map { measurement in
        measurement.threadUsage(over: sampleInterval, totalCPUNanosecondsDelta: totalCPUNanosecondsDelta)
      },
      cpuPercentage: sampleInterval.map { $0.percentage(ofNanoseconds: Double(totalCPUNanosecondsDelta)) }
    )
  }

  private static func predominantCoreType(
    cpuTicksByPerformanceLevel: [UInt64],
    since previousCPUTicksByPerformanceLevel: [UInt64]
  ) -> CoreType {
    var predominantPerformanceLevel: Int?
    var predominantCPUTicksDelta: UInt64 = 0

    for (performanceLevel, cpuTicks) in cpuTicksByPerformanceLevel.enumerated() {
      let previousCPUTicks =
        previousCPUTicksByPerformanceLevel.indices.contains(performanceLevel)
        ? previousCPUTicksByPerformanceLevel[performanceLevel] : 0
      let cpuTicksDelta = cpuTicks.delta(since: previousCPUTicks)

      if cpuTicksDelta > predominantCPUTicksDelta {
        predominantPerformanceLevel = performanceLevel
        predominantCPUTicksDelta = cpuTicksDelta
      }
    }

    guard
      let predominantPerformanceLevel,
      CoreType.performanceLevels.indices.contains(predominantPerformanceLevel)
    else {
      return .unknown
    }

    return CoreType.performanceLevels[predominantPerformanceLevel]
  }
}

struct StickyOrdering<Element: Identifiable> {
  private var positions: [Element.ID: Int] = [:]

  mutating func arrange(
    _ elements: inout [Element],
    by areInIncreasingOrder: (Element, Element) -> Bool,
    reorder shouldReorder: Bool
  ) {
    if shouldReorder {
      elements.sort(by: areInIncreasingOrder)
    } else {
      elements.sort { lhs, rhs in
        switch (positions[lhs.id], positions[rhs.id]) {
        case (let lhsPosition?, let rhsPosition?): return lhsPosition < rhsPosition
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): return areInIncreasingOrder(lhs, rhs)
        }
      }
    }

    self.positions.removeAll(keepingCapacity: true)

    for (position, element) in elements.enumerated() {
      self.positions[element.id] = position
    }
  }
}

@MainActor
final class ProcessUsageState {
  private(set) var systemUsage: SystemUsage
  private(set) var snapshot: ProcessUsageSnapshot

  private let options: CommandLineOptions
  private let processUsageSampler: ProcessUsageSampler
  private var systemUsageSampler: SystemUsageSampler
  private var ordering = StickyOrdering<ProcessOwnerUsage>()

  init(options: CommandLineOptions) async throws {
    let processUsageSampler = ProcessUsageSampler(networkFlowMonitor: try NetworkFlowMonitor())

    var systemUsageSampler = SystemUsageSampler()

    self.options = options
    self.systemUsage = systemUsageSampler.sample()
    self.snapshot = await processUsageSampler.sample()
    self.processUsageSampler = processUsageSampler
    self.systemUsageSampler = systemUsageSampler

    self.snapshot.processOwners.removeAll(where: isExcluded)
    self.ordering.arrange(&snapshot.processOwners, by: options.sortColumn.precedes, reorder: true)
  }

  func refresh(reorder shouldReorder: Bool) async {
    let systemUsage = systemUsageSampler.sample()

    var snapshot = await processUsageSampler.sample()

    snapshot.processOwners.removeAll(where: isExcluded)

    self.ordering.arrange(
      &snapshot.processOwners,
      by: options.sortColumn.precedes,
      reorder: shouldReorder || self.snapshot.isBaseline
    )

    self.systemUsage = systemUsage
    self.snapshot = snapshot
  }

  private func isExcluded(_ processOwnerUsage: ProcessOwnerUsage) -> Bool {
    return (options.showsApplicationsOnly && processOwnerUsage.processOwner.kind != .application)
      || options.nameFilter?.matches(processOwnerUsage.processOwner) == false
  }
}

@MainActor
final class ThreadUsageState {
  let process: ProcessMetadata
  private(set) var snapshot: ThreadUsageSnapshot

  private var sampler: ThreadUsageSampler
  private var ordering = StickyOrdering<ThreadUsage>()

  init(process: ProcessMetadata) throws(Errno) {
    var sampler = try ThreadUsageSampler(process: RunningProcess(processIdentifier: process.processIdentifier))

    self.process = process
    self.snapshot = try sampler.sample()
    self.sampler = sampler

    self.ordering.arrange(&snapshot.threads, by: ThreadUsage.precedesByCPUUsage, reorder: true)
  }

  func refresh(reorder shouldReorder: Bool) throws(Errno) {
    var snapshot = try sampler.sample()

    self.ordering.arrange(
      &snapshot.threads,
      by: ThreadUsage.precedesByCPUUsage,
      reorder: shouldReorder || self.snapshot.isBaseline
    )

    self.snapshot = snapshot
  }
}

enum ANSIEscapeSequence {
  enum Byte {
    static let escape: UInt8 = 0x1B
    static let controlSequenceIntroducer = UInt8(ascii: "[")
    static let finalByteRange: ClosedRange<UInt8> = 0x40...0x7E
  }

  struct Parser {
    private enum State {
      case text
      case escapeSequence
      case controlSequence
    }

    private var state = State.text

    mutating func isVisible(_ asciiValue: UInt8?) -> Bool {
      switch state {
      case .escapeSequence:
        self.state = asciiValue == Byte.controlSequenceIntroducer ? .controlSequence : .text

      case .controlSequence:
        if let asciiValue, Byte.finalByteRange.contains(asciiValue) {
          self.state = .text
        }

      case .text:
        guard asciiValue == Byte.escape else {
          return true
        }

        self.state = .escapeSequence
      }

      return false
    }
  }

  static let enterAlternateScreen = "\u{1B}[?1049h"
  static let exitAlternateScreen = "\u{1B}[?1049l"
  static let hideCursor = "\u{1B}[?25l"
  static let showCursor = "\u{1B}[?25h"
  static let disableLineWrapping = "\u{1B}[?7l"
  static let enableLineWrapping = "\u{1B}[?7h"
  static let enableGraphemeClustering = "\u{1B}[?2027h"
  static let disableGraphemeClustering = "\u{1B}[?2027l"
  static let requestGraphemeClusteringMode = "\u{1B}[?2027$p"
  static let requestPrimaryDeviceAttributes = "\u{1B}[c"
  static let enableApplicationCursorKeys = "\u{1B}[?1h"
  static let disableApplicationCursorKeys = "\u{1B}[?1l"
  static let beginSynchronizedUpdate = "\u{1B}[?2026h"
  static let endSynchronizedUpdate = "\u{1B}[?2026l"
  static let moveCursorToHome = "\u{1B}[H"
  static let clearEntireLine = "\u{1B}[2K"
  static let clearToEndOfScreen = "\u{1B}[J"
  static let bold = "\u{1B}[1m"
  static let faint = "\u{1B}[2m"
  static let normalIntensity = "\u{1B}[22m"
  static let underline = "\u{1B}[4m"
  static let noUnderline = "\u{1B}[24m"
  static let reverseVideo = "\u{1B}[7m"
  static let noReverseVideo = "\u{1B}[27m"
  static let resetAttributes = "\u{1B}[0m"
}

enum TextEmphasis {
  case normal
  case bold
  case underline
  case deemphasized
  case inverse
}

enum TextAlignment {
  case leading
  case trailing
}

enum CharacterWidthModel {
  case graphemeClusters
  case codePoints

  func columnWidth(of character: Character) -> Int {
    switch self {
    case .graphemeClusters: Self.graphemeClusterWidth(of: character)
    case .codePoints: character.unicodeScalars.reduce(0) { $0 + Self.codePointWidth(of: $1) }
    }
  }

  private static func graphemeClusterWidth(of character: Character) -> Int {
    let scalars = character.unicodeScalars

    if scalars.contains("\u{FE0F}") {
      return 2
    }

    guard let scalar = scalars.first, !scalar.isASCII else {
      return 1
    }

    if scalars.contains("\u{FE0E}") {
      return 1
    }

    if scalar.properties.isEmojiPresentation {
      return 2
    }

    return max(Int(wcwidth(wchar_t(scalar.value))), 0)
  }

  private static func codePointWidth(of scalar: Unicode.Scalar) -> Int {
    switch scalar {
    case "\u{200D}", "\u{20E3}": 1 // Terminal.app renders these scalars one column wide.
    default: max(Int(wcwidth(wchar_t(scalar.value))), 0)
    }
  }
}

extension String {
  private enum Composition {
    case plainASCII
    case asciiWithEscapeSequences
    case unicode
  }

  private var composition: Composition {
    var containsEscapeSequence = false

    for byte in utf8 {
      if byte >= 0x80 {
        return .unicode
      }

      if byte == ANSIEscapeSequence.Byte.escape {
        containsEscapeSequence = true
      }
    }

    return containsEscapeSequence ? .asciiWithEscapeSequences : .plainASCII
  }

  func truncated(toVisibleWidth width: Int, characterWidthModel: CharacterWidthModel) -> String {
    return truncatedReportingVisibleWidth(
      toVisibleWidth: width,
      trimsWhitespaceBeforeEllipsis: false,
      characterWidthModel: characterWidthModel
    ).text
  }

  func truncatedReportingVisibleWidth(
    toVisibleWidth width: Int,
    trimsWhitespaceBeforeEllipsis: Bool,
    characterWidthModel: CharacterWidthModel
  ) -> (text: String, visibleWidth: Int) {
    let composition = self.composition
    let maximumWidth = width > 0 ? width : .max

    if composition == .plainASCII, utf8.count <= maximumWidth {
      return (self, utf8.count)
    }

    var columnCount = 0
    var ellipsisIndex: Index?
    var ellipsisColumnCount = 0

    forEachVisibleCharacter(composition: composition, characterWidthModel: characterWidthModel) { index, width in
      if ellipsisIndex == nil, columnCount + width >= maximumWidth {
        ellipsisIndex = index
        ellipsisColumnCount = columnCount
      }

      columnCount += width

      return columnCount <= maximumWidth
    }

    guard let ellipsisIndex, columnCount > maximumWidth else {
      return (self, columnCount)
    }

    var visiblePrefix = self[..<ellipsisIndex]
    var visiblePrefixWidth = ellipsisColumnCount

    if trimsWhitespaceBeforeEllipsis {
      while let lastCharacter = visiblePrefix.last, lastCharacter.isWhitespace {
        visiblePrefix.removeLast()
        visiblePrefixWidth -= characterWidthModel.columnWidth(of: lastCharacter)
      }
    }

    return ("\(visiblePrefix)…", visiblePrefixWidth + 1)
  }

  func emphasized(_ emphasis: TextEmphasis) -> String {
    switch emphasis {
    case .normal: self
    case .bold: "\(ANSIEscapeSequence.bold)\(self)\(ANSIEscapeSequence.normalIntensity)"
    case .underline: "\(ANSIEscapeSequence.underline)\(self)\(ANSIEscapeSequence.noUnderline)"
    case .deemphasized: "\(ANSIEscapeSequence.faint)\(self)\(ANSIEscapeSequence.normalIntensity)"
    case .inverse: "\(ANSIEscapeSequence.reverseVideo)\(self)\(ANSIEscapeSequence.noReverseVideo)"
    }
  }

  private func forEachVisibleCharacter(
    composition: Composition,
    characterWidthModel: CharacterWidthModel,
    _ body: (Index, _ width: Int) -> Bool
  ) {
    var parser = ANSIEscapeSequence.Parser()

    switch composition {
    case .plainASCII, .asciiWithEscapeSequences:
      for index in utf8.indices where parser.isVisible(utf8[index]) {
        guard body(index, 1) else {
          return
        }
      }

    case .unicode:
      for (index, character) in zip(indices, self) where parser.isVisible(character.asciiValue) {
        guard body(index, characterWidthModel.columnWidth(of: character)) else {
          return
        }
      }
    }
  }
}

struct AbbreviatedByteCountFormatStyle: FormatStyle {
  typealias FormatInput = Double
  typealias FormatOutput = String

  private static let units = ["B", "KB", "MB", "GB", "TB"]

  var isRate: Bool

  func format(_ byteCount: Double) -> String {
    var value = byteCount
    var unitIndex = 0

    while unitIndex < Self.units.count - 1, value >= (unitIndex == 0 ? 999.5 : 999.95) {
      value /= 1024
      unitIndex += 1
    }

    let formattedValue = value.formatted(.fixedPoint(fractionLength: unitIndex == 0 ? 0 : 1))

    return "\(formattedValue) \(Self.units[unitIndex])\(isRate ? "/s" : "")"
  }
}

extension FormatStyle where Self == AbbreviatedByteCountFormatStyle {
  static var abbreviatedByteCount: AbbreviatedByteCountFormatStyle { AbbreviatedByteCountFormatStyle(isRate: false) }
  static var abbreviatedByteRate: AbbreviatedByteCountFormatStyle { AbbreviatedByteCountFormatStyle(isRate: true) }
}

struct TableColumn {
  let title: String
  let fixedWidth: Int?
  let alignment: TextAlignment
}

protocol TableColumnSet: CaseIterable, Hashable {
  static var visibleColumns: [Self] { get }

  var title: String { get }
  var fixedWidth: Int? { get }
  var alignment: TextAlignment { get }
}

extension TableColumnSet {
  static var visibleColumns: [Self] { Array(allCases) }

  static func tableColumns(titles: [Self: String] = [:]) -> [TableColumn] {
    return visibleColumns.map { column in
      TableColumn(title: titles[column] ?? column.title, fixedWidth: column.fixedWidth, alignment: column.alignment)
    }
  }

  static func columnIndex(of column: Self) -> Int? {
    return visibleColumns.firstIndex(of: column)
  }
}

struct TextCell {
  private enum Content {
    case text(String, emphasis: TextEmphasis)
    case transferRates(TransferRates)
  }

  private static let byteCountWidth = 8
  private static let inboundSymbol = "↓"
  private static let outboundSymbol = "↑"
  private static let transferRateWidth = byteCountWidth + 1 + inboundSymbol.count

  static let empty = TextCell("")
  static let transferRatesWidth = transferRateWidth * 2 + 1

  private let content: Content

  init(_ text: String, emphasis: TextEmphasis = .normal) {
    self.content = .text(text, emphasis: emphasis)
  }

  init(percentage: Double) {
    self.init(percentage.formatted(.fixedPoint(fractionLength: 1)), emphasis: percentage == 0 ? .deemphasized : .normal)
  }

  init(byteCount: UInt64, suffix: String = "") {
    self.init(byteCount: Double(byteCount), suffix: suffix)
  }

  init(byteCount: Double, suffix: String = "") {
    self.init(
      "\(byteCount.formatted(.abbreviatedByteCount))\(suffix)",
      emphasis: byteCount == 0 ? .deemphasized : .normal
    )
  }

  init(transferRates: TransferRates) {
    self.content = .transferRates(transferRates)
  }

  func rendered(width: Int, alignment: TextAlignment, characterWidthModel: CharacterWidthModel) -> String {
    switch content {
    case .text(let text, let emphasis):
      return Self.rendered(
        text,
        emphasis: emphasis,
        width: width,
        alignment: alignment,
        characterWidthModel: characterWidthModel
      )

    case .transferRates(let transferRates):
      let text = [
        TextCell(byteCount: transferRates.inboundBytesPerSecond, suffix: " \(Self.inboundSymbol)"),
        TextCell(byteCount: transferRates.outboundBytesPerSecond, suffix: " \(Self.outboundSymbol)")
      ]
      .map { cell in
        cell.rendered(width: Self.transferRateWidth, alignment: .trailing, characterWidthModel: characterWidthModel)
      }
      .joined(separator: " ")

      guard width >= Self.transferRatesWidth else {
        return Self.rendered(
          text,
          emphasis: .normal,
          width: width,
          alignment: alignment,
          characterWidthModel: characterWidthModel
        )
      }

      return Self.aligned(text, visibleWidth: Self.transferRatesWidth, toWidth: width, alignment: alignment)
    }
  }

  private static func rendered(
    _ text: String,
    emphasis: TextEmphasis,
    width: Int,
    alignment: TextAlignment,
    characterWidthModel: CharacterWidthModel
  ) -> String {
    let (truncatedText, visibleWidth) = text.truncatedReportingVisibleWidth(
      toVisibleWidth: width,
      trimsWhitespaceBeforeEllipsis: true,
      characterWidthModel: characterWidthModel
    )
    return aligned(truncatedText.emphasized(emphasis), visibleWidth: visibleWidth, toWidth: width, alignment: alignment)
  }

  private static func aligned(
    _ text: String,
    visibleWidth: Int,
    toWidth width: Int,
    alignment: TextAlignment
  ) -> String {
    let padding = String(repeating: " ", count: max(width - visibleWidth, 0))

    switch alignment {
    case .leading: return "\(text)\(padding)"
    case .trailing: return "\(padding)\(text)"
    }
  }
}

enum ProcessColumn: String, TableColumnSet {
  case pid
  case name
  case cpu
  case memory
  case disk
  case network

  static let processOwnerTableColumns = tableColumns()
  static let processTableColumns = tableColumns(titles: [.name: "PROCESS"])

  var title: String {
    switch self {
    case .pid: "PID"
    case .name: "APPLICATION"
    case .cpu: "CPU %"
    case .memory: "MEMORY"
    case .disk: "DISK /s"
    case .network: "NETWORK /s"
    }
  }

  var fixedWidth: Int? {
    switch self {
    case .pid: 5
    case .name: nil
    case .cpu: 6
    case .memory: 9
    case .disk, .network: TextCell.transferRatesWidth
    }
  }

  var alignment: TextAlignment { self == .name ? .leading : .trailing }

  static func cells(processIdentifier: pid_t?, nameCell: TextCell, resourceUsage: ResourceUsage) -> [TextCell] {
    return visibleColumns.map { column in
      switch column {
      case .pid:
        TextCell(processIdentifier.map { String($0) } ?? "")

      case .name:
        nameCell

      case .cpu:
        resourceUsage.rates.map { TextCell(percentage: $0.cpuPercentage) } ?? .empty

      case .memory:
        TextCell(byteCount: resourceUsage.memoryFootprint)

      case .disk:
        resourceUsage.rates.map { TextCell(transferRates: $0.disk) } ?? .empty

      case .network:
        resourceUsage.rates.map { TextCell(transferRates: $0.network) } ?? .empty
      }
    }
  }

  static func totalCells(resourceUsage: ResourceUsage) -> [TextCell] {
    return cells(processIdentifier: nil, nameCell: TextCell("Total", emphasis: .bold), resourceUsage: resourceUsage)
  }

  func precedes(_ lhs: ProcessOwnerUsage, _ rhs: ProcessOwnerUsage) -> Bool {
    switch self {
    case .pid: return lhs.processOwner.processIdentifier < rhs.processOwner.processIdentifier
    case .name: return Self.precedesByName(lhs, rhs)
    case .cpu: return Self.precedes(lhs, rhs, descendingBy: { $0.usage.rates?.cpuPercentage ?? 0 })
    case .memory: return Self.precedes(lhs, rhs, descendingBy: \.usage.memoryFootprint)
    case .disk: return Self.precedes(lhs, rhs, descendingBy: { $0.usage.rates?.disk.totalBytesPerSecond ?? 0 })
    case .network: return Self.precedes(lhs, rhs, descendingBy: { $0.usage.rates?.network.totalBytesPerSecond ?? 0 })
    }
  }

  private static func precedes<Value: Comparable>(
    _ lhs: ProcessOwnerUsage,
    _ rhs: ProcessOwnerUsage,
    descendingBy value: (ProcessOwnerUsage) -> Value
  ) -> Bool {
    let lhsValue = value(lhs)
    let rhsValue = value(rhs)

    guard lhsValue == rhsValue else {
      return lhsValue > rhsValue
    }

    return precedesByName(lhs, rhs)
  }

  private static func precedesByName(_ lhs: ProcessOwnerUsage, _ rhs: ProcessOwnerUsage) -> Bool {
    return (lhs.processOwner.normalizedName, lhs.processOwner.processIdentifier)
      < (rhs.processOwner.normalizedName, rhs.processOwner.processIdentifier)
  }
}

enum ThreadColumn: TableColumnSet {
  case identifier
  case name
  case core
  case share
  case cpu

  static let visibleColumns: [ThreadColumn] = CoreType.isSupported ? allCases : allCases.filter { $0 != .core }
  static let threadTableColumns = tableColumns()

  var title: String {
    switch self {
    case .identifier: "ID"
    case .name: "THREAD"
    case .core: "CORE"
    case .share: "SHARE %"
    case .cpu: "CPU %"
    }
  }

  var fixedWidth: Int? {
    switch self {
    case .identifier: 10
    case .name: nil
    case .core: 11
    case .share: 7
    case .cpu: 6
    }
  }

  var alignment: TextAlignment {
    switch self {
    case .identifier, .name, .core: .leading
    case .share, .cpu: .trailing
    }
  }

  static func cells(for thread: ThreadUsage) -> [TextCell] {
    return visibleColumns.map { column in
      switch column {
      case .identifier:
        TextCell("0x\(String(thread.threadIdentifier, radix: 16))")

      case .name:
        thread.name.map { TextCell($0) } ?? TextCell("Unnamed", emphasis: .deemphasized)

      case .core:
        thread.cpu.map { $0.coreType.map { TextCell($0.title) } ?? TextCell("N/A", emphasis: .deemphasized) } ?? .empty

      case .share:
        thread.cpu.map { TextCell(percentage: $0.sharePercentage) } ?? .empty

      case .cpu:
        thread.cpu.map { TextCell(percentage: $0.percentage) } ?? .empty
      }
    }
  }

  static func totalCells(cpuPercentage: Double?) -> [TextCell] {
    return visibleColumns.map { column in
      switch column {
      case .identifier, .core, .share: .empty
      case .name: TextCell("Total", emphasis: .bold)
      case .cpu: cpuPercentage.map { TextCell(percentage: $0) } ?? .empty
      }
    }
  }
}

struct Table {
  struct Row: Identifiable {
    enum ID: Hashable {
      case processOwner(ProcessOwner.ID)
      case process(pid_t)
      case thread(UInt64)
    }

    enum Content {
      case resourceUsage(processIdentifier: pid_t, name: String, usage: ResourceUsage)
      case thread(ThreadUsage)
    }

    let id: ID
    let content: Content

    var cells: [TextCell] {
      switch content {
      case .resourceUsage(let processIdentifier, let name, let usage):
        ProcessColumn.cells(processIdentifier: processIdentifier, nameCell: TextCell(name), resourceUsage: usage)

      case .thread(let thread):
        ThreadColumn.cells(for: thread)
      }
    }

    init(processOwnerUsage: ProcessOwnerUsage) {
      self.id = .processOwner(processOwnerUsage.id)
      self.content = .resourceUsage(
        processIdentifier: processOwnerUsage.processOwner.processIdentifier,
        name: processOwnerUsage.processOwner.name,
        usage: processOwnerUsage.usage
      )
    }

    init(processIdentifier: pid_t, name: String, resourceUsage: ResourceUsage) {
      self.id = .process(processIdentifier)
      self.content = .resourceUsage(processIdentifier: processIdentifier, name: name, usage: resourceUsage)
    }

    init(threadUsage: ThreadUsage) {
      self.id = .thread(threadUsage.threadIdentifier)
      self.content = .thread(threadUsage)
    }
  }

  private enum ProcessTree {
    private static let branchPrefix = "├─ "
    private static let lastBranchPrefix = "└─ "
    private static let continuationPrefix = "│  "
    private static let emptyPrefix = "   "

    static func rows(for processes: [ProcessUsage], ownedBy processOwner: ProcessOwner) -> [Row] {
      let processIdentifiers = Set(processes.map(\.process.processIdentifier))

      var childrenByParentIdentifier: [pid_t: [ProcessUsage]] = [:]
      var roots: [ProcessUsage] = []

      for processUsage in processes {
        if let parentProcessIdentifier = processUsage.process.parentProcessIdentifier,
          processIdentifiers.contains(parentProcessIdentifier)
        {
          childrenByParentIdentifier[parentProcessIdentifier, default: []].append(processUsage)
        } else {
          roots.append(processUsage)
        }
      }

      var rows: [Row] = []
      rows.reserveCapacity(processes.count)

      func appendRows(for processUsage: ProcessUsage, namePrefix: String, descendantPrefix: String) {
        rows.append(
          Row(
            processIdentifier: processUsage.process.processIdentifier,
            name: "\(namePrefix)\(processUsage.process.name)",
            resourceUsage: processUsage.usage
          )
        )

        let children = childrenByParentIdentifier[
          processUsage.process.processIdentifier,
          default: []
        ].sorted { $0.process.processIdentifier < $1.process.processIdentifier }

        for (index, child) in children.enumerated() {
          let isLastChild = index == children.count - 1
          appendRows(
            for: child,
            namePrefix: "\(descendantPrefix)\(isLastChild ? lastBranchPrefix : branchPrefix)",
            descendantPrefix: "\(descendantPrefix)\(isLastChild ? emptyPrefix : continuationPrefix)"
          )
        }
      }

      let sortedRoots = roots.sorted { lhs, rhs in
        let lhsIsOwnerProcess = lhs.process.processIdentifier == processOwner.processIdentifier
        let rhsIsOwnerProcess = rhs.process.processIdentifier == processOwner.processIdentifier

        guard lhsIsOwnerProcess == rhsIsOwnerProcess else {
          return lhsIsOwnerProcess
        }

        return lhs.process.processIdentifier < rhs.process.processIdentifier
      }

      for root in sortedRoots {
        appendRows(for: root, namePrefix: "", descendantPrefix: "")
      }

      return rows
    }
  }

  let columns: [TableColumn]
  let sortColumnIndex: Int?
  let caption: String?
  let rows: [Row]
  let totalCells: [TextCell]?

  static func processOwners(
    snapshot: ProcessUsageSnapshot,
    sortColumn: ProcessColumn,
    nameFilter: CommandLineOptions.NameFilter?
  ) -> Table {
    return Table(
      columns: ProcessColumn.processOwnerTableColumns,
      sortColumnIndex: ProcessColumn.columnIndex(of: sortColumn),
      caption: nameFilter.map { "Filter: \($0.text.emphasized(.bold))" },
      rows: snapshot.processOwners.map(Row.init(processOwnerUsage:)),
      totalCells: nil
    )
  }

  static func processTree(of processOwner: ProcessOwner, snapshot: ProcessUsageSnapshot) -> Table? {
    let ownedProcesses = snapshot.processes.filter { $0.process.processOwner.id == processOwner.id }

    guard !ownedProcesses.isEmpty else {
      return nil
    }

    let rows = ProcessTree.rows(for: ownedProcesses, ownedBy: processOwner)
    let processOwnerResourceUsage = snapshot.processOwners.first { $0.id == processOwner.id }?.usage

    return Table(
      columns: ProcessColumn.processTableColumns,
      sortColumnIndex: nil,
      caption: caption(title: processOwner.name, details: countDescription(rows.count, "process", "processes")),
      rows: rows,
      totalCells: processOwnerResourceUsage.map(ProcessColumn.totalCells(resourceUsage:))
    )
  }

  static func processThreads(of process: ProcessMetadata, snapshot: ThreadUsageSnapshot) -> Table {
    return Table(
      columns: ThreadColumn.threadTableColumns,
      sortColumnIndex: ThreadColumn.columnIndex(of: .cpu),
      caption: caption(
        title: process.name,
        details: "PID \(process.processIdentifier)",
        countDescription(snapshot.threads.count, "thread", "threads")
      ),
      rows: snapshot.threads.map(Row.init(threadUsage:)),
      totalCells: ThreadColumn.totalCells(cpuPercentage: snapshot.cpuPercentage)
    )
  }

  private static func caption(title: String, details: String...) -> String {
    return ([title.emphasized(.bold)] + details + ["(esc to go back)".emphasized(.deemphasized)])
      .joined(separator: "  ")
  }

  private static func countDescription(_ count: Int, _ singularNoun: String, _ pluralNoun: String) -> String {
    return "\(count) \(count == 1 ? singularNoun : pluralNoun)"
  }
}

struct TableViewport {
  enum Destination {
    case firstRow
    case lastRow
    case previousRow
    case nextRow
    case previousPage
    case nextPage
  }

  private(set) var selectedRowID: Table.Row.ID?
  private(set) var scrollOffset = 0
  private var rowIndex = 0

  var selectedRowIndex: Int? { selectedRowID == nil ? nil : rowIndex }

  mutating func reconcile(with rows: [Table.Row], rowCapacity: Int) {
    if let selectedRowID {
      if let matchingRowIndex = rows.firstIndex(where: { $0.id == selectedRowID }) {
        self.rowIndex = matchingRowIndex

      } else if rows.isEmpty {
        self.selectedRowID = nil

      } else {
        selectRow(at: rowIndex, in: rows)
      }
    }

    scrollToSelection(rowCount: rows.count, rowCapacity: rowCapacity)
  }

  mutating func navigate(to destination: Destination, in rows: [Table.Row], rowCapacity: Int) {
    guard !rows.isEmpty else {
      return
    }

    reconcile(with: rows, rowCapacity: rowCapacity)

    let pageLength = max(rowCapacity, 1)
    let (rowOffset, scrollsViewport): (Int, Bool) =
      switch destination {
      case .firstRow: (-rows.count, true)
      case .lastRow: (rows.count, true)
      case .previousRow: (-1, false)
      case .nextRow: (1, false)
      case .previousPage: (-pageLength, true)
      case .nextPage: (pageLength, true)
      }

    if scrollsViewport {
      self.scrollOffset = (scrollOffset + rowOffset).clamped(
        to: 0...Self.maximumScrollOffset(rowCount: rows.count, rowCapacity: rowCapacity)
      )
    }

    if selectedRowID != nil {
      selectRow(at: rowIndex + rowOffset, in: rows)
    } else if !scrollsViewport {
      selectRow(at: scrollOffset, in: rows)
    }

    scrollToSelection(rowCount: rows.count, rowCapacity: rowCapacity)
  }

  mutating func clearSelection() {
    self.selectedRowID = nil
    self.rowIndex = 0
  }

  static func maximumScrollOffset(rowCount: Int, rowCapacity: Int) -> Int {
    return max(rowCount - rowCapacity, 0)
  }

  private mutating func selectRow(at index: Int, in rows: [Table.Row]) {
    self.rowIndex = index.clamped(to: 0...(rows.count - 1))
    self.selectedRowID = rows[rowIndex].id
  }

  private mutating func scrollToSelection(rowCount: Int, rowCapacity: Int) {
    if selectedRowID != nil, rowCapacity > 0 {
      if rowIndex < scrollOffset {
        self.scrollOffset = rowIndex
      } else if rowIndex >= scrollOffset + rowCapacity {
        self.scrollOffset = rowIndex - rowCapacity + 1
      }
    }

    self.scrollOffset = min(scrollOffset, Self.maximumScrollOffset(rowCount: rowCount, rowCapacity: rowCapacity))
  }
}

enum SummaryRenderer {
  private struct Field {
    let value: String
    let valueWidth: Int
    let label: String

    init(count: Int, label: String) {
      self.init(value: String(count), valueWidth: 5, label: label)
    }

    init(count: Int, of totalCount: Int, label: String) {
      self.init(value: "\(count)/\(totalCount)", valueWidth: 9, label: label)
    }

    init(percentage: Double?, label: String) {
      self.init(
        value: percentage.map { "\($0.formatted(.fixedPoint(fractionLength: 1)))%" } ?? "",
        valueWidth: 6,
        label: label
      )
    }

    init(loadAverage: Double, label: String) {
      self.init(value: loadAverage.formatted(.fixedPoint(fractionLength: 2)), valueWidth: 5, label: label)
    }

    init(byteCount: UInt64, label: String) {
      self.init(value: Double(byteCount).formatted(.abbreviatedByteCount), valueWidth: 8, label: label)
    }

    init(bytesPerSecond: Double?, label: String) {
      self.init(value: bytesPerSecond.map { $0.formatted(.abbreviatedByteRate) } ?? "", valueWidth: 10, label: label)
    }

    private init(value: String, valueWidth: Int, label: String) {
      self.value = value
      self.valueWidth = valueWidth
      self.label = label
    }
  }

  private struct Row {
    let title: String
    let fields: [Field]
    var trailingNote: String?
  }

  private static let separator = "  "

  static func lines(
    for processSnapshot: ProcessUsageSnapshot,
    systemUsage: SystemUsage,
    characterWidthModel: CharacterWidthModel
  ) -> [String] {
    let rows = Self.rows(for: processSnapshot, systemUsage: systemUsage)
    let titleWidth = rows.map(\.title.count).max() ?? 0
    let valueWidths = maximumFieldWidths(in: rows, \.valueWidth)
    let labelWidths = maximumFieldWidths(in: rows, \.label.count)

    return rows.map { row in
      let formattedFields = row.fields.enumerated().map { index, field in
        let formattedValue = TextCell(field.value, emphasis: .bold).rendered(
          width: max(valueWidths[index], field.value.count),
          alignment: .trailing,
          characterWidthModel: characterWidthModel
        )
        let formattedLabel =
          index == row.fields.count - 1
          ? field.label
          : TextCell(field.label).rendered(
            width: labelWidths[index],
            alignment: .leading,
            characterWidthModel: characterWidthModel
          )

        return "\(formattedValue) \(formattedLabel)"
      }

      let formattedTitle = TextCell(row.title, emphasis: .bold).rendered(
        width: titleWidth,
        alignment: .leading,
        characterWidthModel: characterWidthModel
      )
      let joinedFormattedFields = formattedFields.joined(separator: separator)
      let formattedTrailingNote = row.trailingNote.map { "\(separator)\($0.emphasized(.deemphasized))" } ?? ""

      return "\(formattedTitle)\(separator)\(joinedFormattedFields)\(formattedTrailingNote)"
    }
  }

  private static func rows(for processSnapshot: ProcessUsageSnapshot, systemUsage: SystemUsage) -> [Row] {
    let hasRestrictedProcesses = processSnapshot.restrictedProcessCount > 0
    let processCountField =
      hasRestrictedProcesses
      ? Field(
        count: processSnapshot.processes.count,
        of: processSnapshot.processes.count + processSnapshot.restrictedProcessCount,
        label: "accessible"
      )
      : Field(count: processSnapshot.processes.count, label: "total")

    return [
      Row(
        title: "Processes",
        fields: [processCountField, Field(count: processSnapshot.applicationCount, label: "applications")],
        trailingNote: hasRestrictedProcesses ? "(run with sudo to show all)" : nil
      ),
      Row(
        title: "CPU",
        fields: [
          Field(percentage: systemUsage.rates?.cpu.userPercentage, label: "user"),
          Field(percentage: systemUsage.rates?.cpu.systemPercentage, label: "system"),
          Field(percentage: systemUsage.rates?.cpu.idlePercentage, label: "idle")
        ]
      ),
      Row(
        title: "Load Avg",
        fields: [
          Field(loadAverage: systemUsage.loadAverages.oneMinute, label: "1 min"),
          Field(loadAverage: systemUsage.loadAverages.fiveMinutes, label: "5 min"),
          Field(loadAverage: systemUsage.loadAverages.fifteenMinutes, label: "15 min")
        ]
      ),
      Row(
        title: "Memory",
        fields: [
          Field(byteCount: systemUsage.memory.usedBytes, label: "used"),
          Field(byteCount: systemUsage.memory.wiredBytes, label: "wired"),
          Field(byteCount: systemUsage.memory.compressedBytes, label: "compressed"),
          Field(byteCount: systemUsage.memory.totalBytes, label: "total")
        ]
      ),
      Row(
        title: "Disk",
        fields: transferRateFields(for: systemUsage.rates?.disk, inboundLabel: "read", outboundLabel: "written")
      ),
      Row(
        title: "Network",
        fields: transferRateFields(for: systemUsage.rates?.network, inboundLabel: "received", outboundLabel: "sent")
      )
    ]
  }

  private static func maximumFieldWidths(in rows: [Row], _ width: (Field) -> Int) -> [Int] {
    let fieldCount = rows.map(\.fields.count).max() ?? 0

    return (0..<fieldCount).map { index in
      rows.compactMap { $0.fields.indices.contains(index) ? width($0.fields[index]) : nil }.max() ?? 0
    }
  }

  private static func transferRateFields(
    for transferRates: TransferRates?,
    inboundLabel: String,
    outboundLabel: String
  ) -> [Field] {
    return [
      Field(bytesPerSecond: transferRates?.inboundBytesPerSecond, label: inboundLabel),
      Field(bytesPerSecond: transferRates?.outboundBytesPerSecond, label: outboundLabel)
    ]
  }
}

enum FrameRenderer {
  struct Layout {
    let size: TerminalSession.Size
    let characterWidthModel: CharacterWidthModel
    let rowCapacity: Int
    let flexibleColumnWidth: Int
    let truncatesTableLines: Bool
  }

  private static let columnSeparator = "  "
  private static let minimumFlexibleColumnWidth = 6
  private static let scrollbarThumbCell = " │"
  private static let scrollbarColumnWidth = scrollbarThumbCell.count
  private static let tableLeadingLineCount = 3
  private static let estimatedEscapeSequenceBytesPerLine = 64

  static func layout(
    for table: Table,
    summaryLineCount: Int,
    size: TerminalSession.Size,
    characterWidthModel: CharacterWidthModel
  ) -> Layout {
    let fixedColumnsWidth =
      table.columns.reduce(0) { $0 + ($1.fixedWidth ?? 0) } + (table.columns.count - 1) * columnSeparator.count
    let trailingLineCount = table.totalCells == nil ? 0 : 1

    return Layout(
      size: size,
      characterWidthModel: characterWidthModel,
      rowCapacity: max(size.rows - summaryLineCount - tableLeadingLineCount - trailingLineCount, 0),
      flexibleColumnWidth: max(size.columns - fixedColumnsWidth - scrollbarColumnWidth, minimumFlexibleColumnWidth),
      truncatesTableLines: size.columns < fixedColumnsWidth + minimumFlexibleColumnWidth + scrollbarColumnWidth
    )
  }

  static func frame(summaryLines: [String], table: Table, viewport: TableViewport, layout: Layout) -> String {
    let size = layout.size
    let characterWidthModel = layout.characterWidthModel
    let visibleRows = table.rows.dropFirst(viewport.scrollOffset).prefix(layout.rowCapacity)
    let thumbRange = scrollbarThumbRange(
      rowCount: table.rows.count,
      rowCapacity: layout.rowCapacity,
      scrollOffset: viewport.scrollOffset
    )

    var frame = "\(ANSIEscapeSequence.beginSynchronizedUpdate)\(ANSIEscapeSequence.moveCursorToHome)"
    frame.reserveCapacity(size.rows * (size.columns + estimatedEscapeSequenceBytesPerLine))

    var lineCount = 0

    func appendLine(_ line: String, truncates: Bool = true) {
      guard lineCount < size.rows else {
        return
      }

      if lineCount > 0 {
        frame += "\n"
      }

      frame += ANSIEscapeSequence.clearEntireLine
      frame += truncates ? line.truncated(toVisibleWidth: size.columns, characterWidthModel: characterWidthModel) : line
      frame += ANSIEscapeSequence.resetAttributes
      lineCount += 1
    }

    for summaryLine in summaryLines {
      appendLine(summaryLine)
    }

    appendLine("")
    appendLine(table.caption ?? "")
    appendLine(headerLine(for: table, layout: layout), truncates: layout.truncatesTableLines)

    for (rowIndex, row) in zip(visibleRows.indices, visibleRows) {
      let line = rowLine(
        for: row,
        columns: table.columns,
        layout: layout,
        isSelected: rowIndex == viewport.selectedRowIndex
      )
      let isScrollbarThumbRow = thumbRange?.contains(rowIndex - viewport.scrollOffset) ?? false

      appendLine(isScrollbarThumbRow ? "\(line)\(scrollbarThumbCell)" : line, truncates: layout.truncatesTableLines)
    }

    if let totalCells = table.totalCells {
      appendLine(
        tableLine(columns: table.columns, cells: totalCells, layout: layout),
        truncates: layout.truncatesTableLines
      )
    }

    if lineCount < size.rows {
      frame += "\n\(ANSIEscapeSequence.clearToEndOfScreen)"
    }

    frame += ANSIEscapeSequence.endSynchronizedUpdate

    return frame
  }

  private static func tableLine(columns: [TableColumn], cells: [TextCell], layout: Layout) -> String {
    return zip(columns, cells)
      .map { column, cell in
        cell.rendered(
          width: column.fixedWidth ?? layout.flexibleColumnWidth,
          alignment: column.alignment,
          characterWidthModel: layout.characterWidthModel
        )
      }
      .joined(separator: columnSeparator)
  }

  private static func headerLine(for table: Table, layout: Layout) -> String {
    let cells = table.columns.enumerated().map { index, column in
      TextCell(column.title, emphasis: index == table.sortColumnIndex ? .underline : .normal)
    }

    let line = tableLine(columns: table.columns, cells: cells, layout: layout)

    return line.emphasized(.bold)
  }

  private static func rowLine(for row: Table.Row, columns: [TableColumn], layout: Layout, isSelected: Bool) -> String {
    let line = tableLine(columns: columns, cells: row.cells, layout: layout)
    return isSelected ? line.emphasized(.inverse) : line
  }

  private static func scrollbarThumbRange(rowCount: Int, rowCapacity: Int, scrollOffset: Int) -> Range<Int>? {
    guard rowCapacity > 0, rowCount > rowCapacity else {
      return nil
    }

    let thumbLength = max(Int((Double(rowCapacity * rowCapacity) / Double(rowCount)).rounded()), 1)
    let maximumScrollOffset = TableViewport.maximumScrollOffset(rowCount: rowCount, rowCapacity: rowCapacity)
    let thumbOffset = Int((Double((rowCapacity - thumbLength) * scrollOffset) / Double(maximumScrollOffset)).rounded())

    return thumbOffset..<(thumbOffset + thumbLength)
  }
}

@MainActor
final class TerminalSession {
  enum Error: Swift.Error, LocalizedError {
    case notInteractive
    case failedToReadAttributes(underlyingError: Errno)

    var errorDescription: String? {
      switch self {
      case .notInteractive: "\(ProcessInfo.processInfo.processName) must be run in an interactive terminal."
      case .failedToReadAttributes(let underlyingError): "Failed to read terminal attributes: \(underlyingError)"
      }
    }
  }

  struct Size {
    let rows: Int
    let columns: Int
  }

  private static let fallbackSize = Size(rows: 24, columns: 80)
  private static let queryReplyTimeout: Duration = .milliseconds(250)

  private let originalAttributes: termios
  private var isActive = false
  private var detectedCharacterWidthModel: CharacterWidthModel?
  private var pendingInput: [UInt8] = []

  var characterWidthModel: CharacterWidthModel { detectedCharacterWidthModel ?? .graphemeClusters }

  var size: Size {
    var windowSize = winsize()

    guard
      ioctl(FileDescriptor.standardOutput.rawValue, TIOCGWINSZ, &windowSize) == 0,
      windowSize.ws_row > 0,
      windowSize.ws_col > 0
    else {
      return Self.fallbackSize
    }

    return Size(rows: Int(windowSize.ws_row), columns: Int(windowSize.ws_col))
  }

  init() throws {
    guard
      isatty(FileDescriptor.standardInput.rawValue) == 1,
      isatty(FileDescriptor.standardOutput.rawValue) == 1
    else {
      throw Error.notInteractive
    }

    setlocale(LC_CTYPE, "UTF-8")

    var attributes = termios()

    guard tcgetattr(FileDescriptor.standardInput.rawValue, &attributes) == 0 else {
      throw Error.failedToReadAttributes(underlyingError: Errno(rawValue: errno))
    }

    self.originalAttributes = attributes
  }

  isolated deinit {
    deactivate()
  }

  func activate() {
    guard !isActive else {
      return
    }

    var attributes = originalAttributes

    attributes.c_iflag &= ~tcflag_t(IXON)
    attributes.c_lflag &= ~tcflag_t(ICANON | ECHO | IEXTEN)

    tcsetattr(FileDescriptor.standardInput.rawValue, TCSANOW, &attributes)
    write(
      """
      \(ANSIEscapeSequence.enterAlternateScreen)\
      \(ANSIEscapeSequence.hideCursor)\
      \(ANSIEscapeSequence.disableLineWrapping)\
      \(ANSIEscapeSequence.enableGraphemeClustering)\
      \(ANSIEscapeSequence.enableApplicationCursorKeys)
      """
    )

    self.isActive = true

    if detectedCharacterWidthModel == nil {
      self.detectedCharacterWidthModel = queryCharacterWidthModel()
    }
  }

  func deactivate() {
    guard isActive else {
      return
    }

    var attributes = originalAttributes

    tcsetattr(FileDescriptor.standardInput.rawValue, TCSANOW, &attributes)
    write(
      """
      \(ANSIEscapeSequence.disableApplicationCursorKeys)\
      \(ANSIEscapeSequence.disableGraphemeClustering)\
      \(ANSIEscapeSequence.enableLineWrapping)\
      \(ANSIEscapeSequence.showCursor)\
      \(ANSIEscapeSequence.exitAlternateScreen)
      """
    )

    self.isActive = false
  }

  func draw(_ frame: String) {
    guard isActive else {
      return
    }

    write(frame)
  }

  func takePendingInput() -> [UInt8] {
    defer {
      self.pendingInput = []
    }

    return pendingInput
  }

  private func write(_ string: String) {
    _ = try? FileDescriptor.standardOutput.writeAll(string.utf8)
  }

  private func queryCharacterWidthModel() -> CharacterWidthModel {
    write("\(ANSIEscapeSequence.requestGraphemeClusteringMode)\(ANSIEscapeSequence.requestPrimaryDeviceAttributes)")

    let deadline = ContinuousClock.now + Self.queryReplyTimeout

    var reply: [UInt8] = []

    while !String(decoding: reply, as: UTF8.self).contains(/\x1B\[\?[\d;]*c/) {
      let remainingTime = deadline - .now

      guard remainingTime > .zero, FileDescriptor.standardInput.waitUntilReadable(timeout: remainingTime) else {
        break
      }

      guard FileDescriptor.standardInput.read(appendingTo: &reply) > 0 else {
        break
      }
    }

    var replyText = String(decoding: reply, as: UTF8.self)

    let isGraphemeClusteringEnabled = replyText.contains(/\x1B\[\?2027;[13]\$y/)

    replyText.replace(/\x1B\[\?2027;\d\$y|\x1B\[\?[\d;]*c/, with: "")

    self.pendingInput.append(contentsOf: replyText.utf8)

    return isGraphemeClusteringEnabled ? .graphemeClusters : .codePoints
  }
}

enum KeyboardCommand: Equatable {
  case navigate(to: TableViewport.Destination)
  case openSelection
  case goBack
  case quit

  private enum ControlCharacter {
    static let controlB: UInt8 = 0x02
    static let controlF: UInt8 = 0x06
  }

  private enum KeySequence {
    static let completionTimeout: Duration = .milliseconds(25)
    static let defaultParameterValue = 1

    static let introducers: [UInt8] = [ANSIEscapeSequence.Byte.controlSequenceIntroducer, UInt8(ascii: "O")]
    static let parameterSeparator = UInt8(ascii: ";")
  }

  static func readCommands(from fileDescriptor: FileDescriptor) -> [KeyboardCommand]? {
    var input: [UInt8] = []

    repeat {
      guard fileDescriptor.read(appendingTo: &input) > 0 else {
        return input.isEmpty ? nil : commands(in: input)
      }
    } while endsWithIncompleteEscapeSequence(input)
      && fileDescriptor.waitUntilReadable(timeout: KeySequence.completionTimeout)

    return commands(in: input)
  }

  static func commands(in input: [UInt8]) -> [KeyboardCommand] {
    var commands: [KeyboardCommand] = []
    var index = input.startIndex

    while index < input.endIndex {
      let byte = input[index]

      index += 1

      switch byte {
      case ANSIEscapeSequence.Byte.escape:
        guard index < input.endIndex, KeySequence.introducers.contains(input[index]) else {
          commands.append(.goBack)
          continue
        }

        let parametersStartIndex = index + 1

        guard
          let finalByteIndex = input[parametersStartIndex...].firstIndex(
            where: { ANSIEscapeSequence.Byte.finalByteRange.contains($0) }
          )
        else {
          index = input.endIndex
          continue
        }

        let parameterValues = parameterValues(in: input[parametersStartIndex..<finalByteIndex])
        let isModified = parameterValues.count > 1 && parameterValues[1] > KeySequence.defaultParameterValue

        index = finalByteIndex + 1

        switch (input[finalByteIndex], parameterValues[0]) {
        case (UInt8(ascii: "A"), _) where !isModified:
          commands.append(.navigate(to: .previousRow))

        case (UInt8(ascii: "B"), _) where !isModified:
          commands.append(.navigate(to: .nextRow))

        case (UInt8(ascii: "H"), _), (UInt8(ascii: "~"), 1), (UInt8(ascii: "~"), 7):
          commands.append(.navigate(to: .firstRow))

        case (UInt8(ascii: "F"), _), (UInt8(ascii: "~"), 4), (UInt8(ascii: "~"), 8):
          commands.append(.navigate(to: .lastRow))

        case (UInt8(ascii: "~"), 5):
          commands.append(.navigate(to: .previousPage))

        case (UInt8(ascii: "~"), 6):
          commands.append(.navigate(to: .nextPage))

        default:
          break
        }

      case UInt8(ascii: "k"):
        commands.append(.navigate(to: .previousRow))

      case UInt8(ascii: "j"):
        commands.append(.navigate(to: .nextRow))

      case UInt8(ascii: "g"):
        commands.append(.navigate(to: .firstRow))

      case UInt8(ascii: "G"):
        commands.append(.navigate(to: .lastRow))

      case ControlCharacter.controlB:
        commands.append(.navigate(to: .previousPage))

      case ControlCharacter.controlF:
        commands.append(.navigate(to: .nextPage))

      case UInt8(ascii: " "), UInt8(ascii: "\r"), UInt8(ascii: "\n"):
        commands.append(.openSelection)

      case UInt8(ascii: "q"):
        commands.append(.quit)

      default:
        break
      }
    }

    return commands
  }

  private static func parameterValues(in parameters: ArraySlice<UInt8>) -> [Int] {
    return
      parameters
      .split(separator: KeySequence.parameterSeparator, omittingEmptySubsequences: false)
      .map { Int(String(decoding: $0, as: UTF8.self)) ?? KeySequence.defaultParameterValue }
  }

  private static func endsWithIncompleteEscapeSequence(_ input: [UInt8]) -> Bool {
    guard let escapeIndex = input.lastIndex(of: ANSIEscapeSequence.Byte.escape) else {
      return false
    }

    let sequence = input[(escapeIndex + 1)...]

    guard let introducer = sequence.first else {
      return true
    }

    return KeySequence.introducers.contains(introducer)
      && !sequence.dropFirst().contains { ANSIEscapeSequence.Byte.finalByteRange.contains($0) }
  }
}

enum Screen {
  case processOwners
  case processTree(owner: ProcessOwner)
  case processThreads(ThreadUsageState)

  struct Stack {
    private struct Entry {
      let screen: Screen
      let viewport: TableViewport
    }

    private(set) var current = Screen.processOwners
    var viewport = TableViewport()

    private var history: [Entry] = []

    mutating func push(_ screen: Screen) {
      self.history.append(Entry(screen: current, viewport: viewport))
      self.current = screen
      self.viewport = TableViewport()
    }

    mutating func pop() -> Bool {
      guard let entry = history.popLast() else {
        return false
      }

      self.current = entry.screen
      self.viewport = entry.viewport

      return true
    }
  }

  @MainActor
  func table(for processSnapshot: ProcessUsageSnapshot, options: CommandLineOptions) -> Table? {
    switch self {
    case .processOwners:
      .processOwners(snapshot: processSnapshot, sortColumn: options.sortColumn, nameFilter: options.nameFilter)

    case .processTree(let processOwner):
      .processTree(of: processOwner, snapshot: processSnapshot)

    case .processThreads(let threadUsageState):
      .processThreads(of: threadUsageState.process, snapshot: threadUsageState.snapshot)
    }
  }
}

@MainActor
final class AppController {
  private enum Event {
    case redraw
    case suspend
    case keyboardCommands([KeyboardCommand])
    case quit

    static func stream(pendingInput: [UInt8]) -> AsyncStream<Event> {
      let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
      let pendingCommands = KeyboardCommand.commands(in: pendingInput)

      if !pendingCommands.isEmpty {
        continuation.yield(.keyboardCommands(pendingCommands))
      }

      let processSignals = ProcessSignals.stream(for: SIGINT, SIGTERM, SIGHUP, SIGWINCH, SIGTSTP)
      let processSignalsTask = Task {
        for await signal in processSignals {
          switch signal {
          case SIGWINCH: continuation.yield(.redraw)
          case SIGTSTP: continuation.yield(.suspend)
          default: continuation.yield(.quit)
          }
        }
      }

      let keyboardInputSource = DispatchSource.makeReadSource(
        fileDescriptor: FileDescriptor.standardInput.rawValue,
        queue: .main
      )

      keyboardInputSource.setEventHandler {
        guard let commands = KeyboardCommand.readCommands(from: .standardInput) else {
          continuation.yield(.quit)
          return
        }

        if !commands.isEmpty {
          continuation.yield(.keyboardCommands(commands))
        }
      }

      continuation.onTermination = { _ in
        processSignalsTask.cancel()
        keyboardInputSource.cancel()
      }

      keyboardInputSource.resume()

      return stream
    }
  }

  private static let maximumInitialRefreshDelay: Duration = .milliseconds(500)
  private static let maximumRefreshTolerance: Duration = .milliseconds(100)

  private let options: CommandLineOptions
  private let minimumReorderInterval: Duration
  private let initialRefreshDelay: Duration
  private let terminalSession: TerminalSession
  private let processUsageState: ProcessUsageState
  private var lastReorderInstant: ContinuousClock.Instant?
  private var screens = Screen.Stack()
  private var summaryLines: [String] = []
  private var table: Table?
  private var refreshTask: Task<Void, Never>?

  init(options: CommandLineOptions) async throws {
    self.options = options
    self.minimumReorderInterval = (options.reorderInterval ?? options.refreshInterval) - options.refreshInterval / 2
    self.initialRefreshDelay = min(options.refreshInterval, Self.maximumInitialRefreshDelay)
    self.terminalSession = try TerminalSession()
    self.processUsageState = try await ProcessUsageState(options: options)
  }

  func run() async {
    terminalSession.activate()

    defer {
      terminalSession.deactivate()
    }

    updateSummary()
    updateTable()
    draw()
    startRefreshing(after: initialRefreshDelay)

    defer {
      refreshTask?.cancel()
    }

    for await event in Event.stream(pendingInput: terminalSession.takePendingInput()) {
      switch event {
      case .redraw: draw()
      case .suspend: suspend()
      case .quit: return
      case .keyboardCommands(let commands) where commands.contains(.quit): return
      case .keyboardCommands(let commands): perform(commands)
      }
    }
  }

  private func perform(_ commands: [KeyboardCommand]) {
    for command in commands {
      switch command {
      case .navigate(let destination): navigate(to: destination)
      case .openSelection: openSelection()
      case .goBack: goBack()
      case .quit: break
      }
    }

    draw()
  }

  private func startRefreshing(after delay: Duration) {
    let previousRefreshTask = refreshTask

    previousRefreshTask?.cancel()

    self.refreshTask = Task {
      await previousRefreshTask?.value
      await refreshPeriodically(after: delay)
    }
  }

  private func refreshPeriodically(after delay: Duration) async {
    let clock = ContinuousClock()
    let tolerance = min(options.refreshInterval / 20, Self.maximumRefreshTolerance)

    var deadline = clock.now + delay

    while true {
      do {
        try await Task.sleep(until: deadline, tolerance: tolerance, clock: clock)
      } catch {
        return
      }

      await refresh()

      deadline += options.refreshInterval

      if deadline < clock.now {
        deadline = clock.now + options.refreshInterval
      }
    }
  }

  private func refresh() async {
    let now = ContinuousClock.now
    let shouldReorder = lastReorderInstant.map { now - $0 >= minimumReorderInterval } ?? true

    if shouldReorder {
      self.lastReorderInstant = now
    }

    // Sample threads before awaiting the process sample so input handled during the await cannot replace a newly opened
    // thread screen's baseline with a sample taken only milliseconds later.
    refreshThreads(reorder: shouldReorder)

    await processUsageState.refresh(reorder: shouldReorder)

    updateSummary()
    updateTable()
    draw()
  }

  private func refreshThreads(reorder shouldReorder: Bool) {
    guard case .processThreads(let threadUsageState) = screens.current else {
      return
    }

    do throws(Errno) {
      try threadUsageState.refresh(reorder: shouldReorder)
    } catch {
      popScreen()
    }
  }

  private func navigate(to destination: TableViewport.Destination) {
    guard let table else {
      return
    }

    screens.viewport.navigate(to: destination, in: table.rows, rowCapacity: tableLayout(for: table).rowCapacity)
  }

  private func openSelection() {
    switch (screens.current, screens.viewport.selectedRowID) {
    case (.processOwners, .processOwner(let selectedProcessOwnerID)?):
      guard
        let selectedProcessOwner = processUsageState.snapshot.processOwners.first(
          where: { $0.id == selectedProcessOwnerID }
        )?.processOwner
      else {
        return
      }

      if selectedProcessOwner.kind == .process {
        showThreads(ofProcessWithIdentifier: selectedProcessOwner.processIdentifier)
      } else {
        showProcessTree(of: selectedProcessOwner)
      }

    case (.processTree, .process(let selectedProcessIdentifier)?):
      showThreads(ofProcessWithIdentifier: selectedProcessIdentifier)

    default:
      break
    }
  }

  private func showProcessTree(of processOwner: ProcessOwner) {
    pushScreen(.processTree(owner: processOwner))
  }

  private func showThreads(ofProcessWithIdentifier processIdentifier: pid_t) {
    guard
      let processUsage = processUsageState.snapshot.processes.first(
        where: { $0.process.processIdentifier == processIdentifier }
      ),
      let threadUsageState = try? ThreadUsageState(process: processUsage.process)
    else {
      return
    }

    pushScreen(.processThreads(threadUsageState))
    startRefreshing(after: initialRefreshDelay)
  }

  private func goBack() {
    if screens.viewport.selectedRowID != nil {
      screens.viewport.clearSelection()
    } else {
      popScreen()
    }
  }

  private func pushScreen(_ screen: Screen) {
    screens.push(screen)
    updateTable()
  }

  private func popScreen() {
    guard screens.pop() else {
      return
    }

    updateTable()
  }

  private func updateSummary() {
    self.summaryLines = SummaryRenderer.lines(
      for: processUsageState.snapshot,
      systemUsage: processUsageState.systemUsage,
      characterWidthModel: terminalSession.characterWidthModel
    )
  }

  private func updateTable() {
    guard let table = screens.current.table(for: processUsageState.snapshot, options: options) else {
      popScreen()
      return
    }

    self.table = table
  }

  private func tableLayout(for table: Table) -> FrameRenderer.Layout {
    return FrameRenderer.layout(
      for: table,
      summaryLineCount: summaryLines.count,
      size: terminalSession.size,
      characterWidthModel: terminalSession.characterWidthModel
    )
  }

  private func draw() {
    guard let table else {
      return
    }

    let layout = tableLayout(for: table)

    screens.viewport.reconcile(with: table.rows, rowCapacity: layout.rowCapacity)
    terminalSession.draw(
      FrameRenderer.frame(summaryLines: summaryLines, table: table, viewport: screens.viewport, layout: layout)
    )
  }

  private func suspend() {
    terminalSession.deactivate()
    raise(SIGSTOP)
    terminalSession.activate()
    draw()
  }
}

struct CommandLineOptions: ParsableCommandLineOptions {
  struct NameFilter {
    let text: String
    private let normalizedText: String

    init(_ text: String) {
      self.text = text.sanitizedForTerminal
      self.normalizedText = self.text.lowercased()
    }

    func matches(_ processOwner: ProcessOwner) -> Bool {
      return processOwner.normalizedName.contains(normalizedText)
    }
  }

  private static let intervalSecondsRange = 0.5...86_400.0
  private static let sortColumnNames = ProcessColumn.allCases.map(\.rawValue).joined(separator: ", ")

  static let usageDescription = """
    Usage:
      \(ProcessInfo.processInfo.processName) [options]

    Options:
      -i, --interval <seconds>          Set refresh interval in seconds [default: 2]
      -r, --reorder-interval <seconds>  Set reorder interval in seconds (≥ refresh interval) [default: refresh interval]
      -s, --sort <column>               Set sort column (\(sortColumnNames)) [default: cpu]
      -f, --filter <text>               Only show applications and processes with names containing <text>
      -a, --applications-only           Only show applications
      -h, --help                        Show this help message

    Keys:
      ↑/↓, k/j                          Move the selection
      page up/down, ctrl + b/f          Move the selection or scroll by one page
      home/end, g/G                     Move the selection or scroll to the top or bottom
      return, space                     Show the processes or threads of the selection
      esc                               Clear the selection or return to the previous view
      q                                 Quit
    """

  private(set) var refreshInterval: Duration = .seconds(2)
  private(set) var reorderInterval: Duration?
  private(set) var sortColumn: ProcessColumn = .cpu
  private(set) var showsApplicationsOnly = false
  private(set) var nameFilter: NameFilter?

  init(arguments: some Sequence<String>) throws(CommandLineOptionsError) {
    var arguments = arguments.makeIterator()

    while let argument = arguments.next() {
      switch argument {
      case "-i", "--interval":
        self.refreshInterval = try Self.duration(fromSecondsValue: arguments.next(), for: argument)

      case "-r", "--reorder-interval":
        self.reorderInterval = try Self.duration(fromSecondsValue: arguments.next(), for: argument)

      case "-s", "--sort":
        guard let value = arguments.next() else {
          throw .invalidUsage("Missing value for '\(argument)'.")
        }

        guard let column = ProcessColumn(rawValue: value.lowercased()) else {
          throw .invalidUsage("Invalid sort column '\(value)'. Expected one of: \(Self.sortColumnNames).")
        }

        self.sortColumn = column

      case "-f", "--filter":
        guard let value = arguments.next(), !value.isEmpty else {
          throw .invalidUsage("Missing value for '\(argument)'.")
        }

        self.nameFilter = NameFilter(value)

      case "-a", "--applications-only":
        self.showsApplicationsOnly = true

      case "-h", "--help":
        throw .helpRequested

      default:
        throw .invalidUsage("Unknown argument: \(argument)")
      }
    }

    if let reorderInterval, reorderInterval < refreshInterval {
      throw .invalidUsage("Reorder interval must be greater than or equal to the refresh interval.")
    }
  }

  private static func duration(
    fromSecondsValue value: String?,
    for argument: String
  ) throws(CommandLineOptionsError) -> Duration {
    guard let value else {
      throw .invalidUsage("Missing value for '\(argument)'.")
    }

    guard let seconds = Double(value), intervalSecondsRange.contains(seconds) else {
      throw .invalidUsage(
        "Invalid value for '\(argument)': \(value). Expected \(intervalSecondsRange.lowerBound) to \(Int(intervalSecondsRange.upperBound)) seconds."
      )
    }

    return .seconds(seconds)
  }
}

@main
enum AppTop {
  static func main() async {
    let options = CommandLineOptions.parseOrExit()

    do {
      let appController = try await AppController(options: options)
      await appController.run()
    } catch {
      Log.error("Error: \(error.localizedDescription)")
      exit(EXIT_FAILURE)
    }
  }
}
