import Foundation
import IOKit
import IOKit.storage
import Synchronization
import System

enum Log {
  enum Error: Swift.Error, LocalizedError {
    case outputAlreadyRedirected

    var errorDescription: String? {
      switch self {
      case .outputAlreadyRedirected: "Output has already been redirected."
      }
    }
  }

  private static let timestampStyle =
    isatty(FileDescriptor.standardOutput.rawValue) == 0
    ? Date.ISO8601FormatStyle(
      dateTimeSeparator: .space,
      includingFractionalSeconds: true,
      timeZone: .current
    ) : nil
  private static let isRedirected = Atomic(false)

  static func redirectOutput(to filePath: FilePath) throws {
    let (exchanged, _) = isRedirected.compareExchange(
      expected: false,
      desired: true,
      ordering: .acquiringAndReleasing
    )

    guard exchanged else {
      throw Error.outputAlreadyRedirected
    }

    do {
      let fileDescriptor = try FileDescriptor.open(
        filePath,
        .writeOnly,
        options: [.create, .truncate, .append],
        permissions: [.ownerReadWrite, .groupRead, .otherRead]
      )

      try fileDescriptor.closeAfter {
        _ = try fileDescriptor.duplicate(as: .standardOutput)
        _ = try fileDescriptor.duplicate(as: .standardError)
      }

      setvbuf(stdout, nil, _IONBF, 0)
      setvbuf(stderr, nil, _IONBF, 0)
    } catch {
      isRedirected.store(false, ordering: .releasing)
      throw error
    }
  }

  static func message(_ message: String) {
    write(message, to: .standardOutput)
  }

  static func error(_ message: String) {
    write(message, to: .standardError)
  }

  private static func write(_ message: String, to fileDescriptor: FileDescriptor) {
    _ = try? fileDescriptor.writeAll(line(for: message).utf8)
  }

  private static func line(for message: String) -> String {
    guard let timestampStyle else {
      return "\(message)\n"
    }

    return "[\(Date.now.formatted(timestampStyle))] \(message)\n"
  }
}

enum ProcessSignals {
  static func stream(for signals: Int32...) -> AsyncStream<Int32> {
    let (stream, continuation) = AsyncStream.makeStream(of: Int32.self)

    var sources: [any DispatchSourceSignal] = []
    sources.reserveCapacity(signals.count)

    for signal in signals {
      Darwin.signal(signal, SIG_IGN)

      let source = DispatchSource.makeSignalSource(signal: signal, queue: .main)

      source.setEventHandler {
        continuation.yield(signal)
      }

      source.setCancelHandler {
        Darwin.signal(signal, SIG_DFL)
      }

      source.resume()
      sources.append(source)
    }

    continuation.onTermination = { [sources] _ in
      for source in sources {
        source.cancel()
      }
    }

    return stream
  }
}

extension UnsignedInteger {
  func delta(since earlierValue: Self) -> Self {
    return self > earlierValue ? self - earlierValue : 0
  }
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
    return poll(&pollDescriptor, 1, Int32(timeout.attoseconds / 1_000_000_000_000_000)) > 0
  }
}

extension host_cpu_load_info {
  var userTicks: UInt32 { cpu_ticks.0 &+ cpu_ticks.3 }
  var systemTicks: UInt32 { cpu_ticks.1 }
  var idleTicks: UInt32 { cpu_ticks.2 }
}

enum MachAbsoluteTime {
  private static let timebase: mach_timebase_info_data_t = {
    var timebase = mach_timebase_info_data_t()

    mach_timebase_info(&timebase)

    return timebase
  }()

  static var now: UInt64 { mach_absolute_time() }

  static func seconds(from absoluteTime: UInt64) -> Double {
    return Double(absoluteTime) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
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
    var loadInfo = host_cpu_load_info()
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)

    let result = withUnsafeMutablePointer(to: &loadInfo) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
        host_statistics(port, HOST_CPU_LOAD_INFO, reboundPointer, &count)
      }
    }

    return result == KERN_SUCCESS ? loadInfo : nil
  }

  static func virtualMemoryStatistics() -> vm_statistics64? {
    var statistics = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)

    let result = withUnsafeMutablePointer(to: &statistics) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
        host_statistics64(port, HOST_VM_INFO64, reboundPointer, &count)
      }
    }

    return result == KERN_SUCCESS ? statistics : nil
  }
}

// swift-format-ignore: AlwaysUseLowerCamelCase
@_silgen_name("responsibility_get_pid_responsible_for_pid")
func responsibility_get_pid_responsible_for_pid(_ processIdentifier: pid_t) -> pid_t

struct NetworkStatisticsFramework {
  enum Error: Swift.Error, LocalizedError {
    case failedToLoadFramework
    case missingSymbol(name: String)

    var errorDescription: String? {
      switch self {
      case .failedToLoadFramework: "Failed to load the NetworkStatistics framework."
      case .missingSymbol(let name): "Missing NetworkStatistics symbol: \(name)"
      }
    }
  }

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
    guard
      let frameworkHandle = dlopen(
        "/System/Library/PrivateFrameworks/NetworkStatistics.framework/NetworkStatistics",
        RTLD_LAZY
      )
    else {
      throw Error.failedToLoadFramework
    }

    func symbol<Symbol>(named name: String) throws -> Symbol {
      guard let symbol = dlsym(frameworkHandle, name) else {
        throw Error.missingSymbol(name: name)
      }

      return unsafeBitCast(symbol, to: Symbol.self)
    }

    func constant(named name: String) throws -> CFString {
      guard let symbol = dlsym(frameworkHandle, name) else {
        throw Error.missingSymbol(name: name)
      }

      return symbol.load(as: CFString.self)
    }

    self.createManager = try symbol(named: "NStatManagerCreate")
    self.destroyManager = try symbol(named: "NStatManagerDestroy")
    self.addAllTCPSources = try symbol(named: "NStatManagerAddAllTCP")
    self.addAllUDPSources = try symbol(named: "NStatManagerAddAllUDP")
    self.queryAllSources = try symbol(named: "NStatManagerQueryAllSources")
    self.querySourceDescription = try symbol(named: "NStatSourceQueryDescription")
    self.setSourceDescriptionHandler = try symbol(named: "NStatSourceSetDescriptionBlock")
    self.setSourceCountsHandler = try symbol(named: "NStatSourceSetCountsBlock")
    self.setSourceRemovedHandler = try symbol(named: "NStatSourceSetRemovedBlock")
    self.processIdentifierKey = try constant(named: "kNStatSrcKeyPID")
    self.receivedBytesKey = try constant(named: "kNStatSrcKeyRxBytes")
    self.sentBytesKey = try constant(named: "kNStatSrcKeyTxBytes")
  }
}

struct FixedPointFormatStyle: FormatStyle {
  typealias FormatInput = Double
  typealias FormatOutput = String

  var fractionLength: Int

  func format(_ value: Double) -> String {
    var multiplier = 1

    for _ in 0..<fractionLength {
      multiplier *= 10
    }

    let scaledValue = Int((value * Double(multiplier)).rounded())

    guard fractionLength > 0 else {
      return String(scaledValue)
    }

    let fractionDigits = String(scaledValue % multiplier)
    let fractionPadding = String(repeating: "0", count: fractionLength - fractionDigits.count)

    return "\(scaledValue / multiplier).\(fractionPadding)\(fractionDigits)"
  }
}

extension FormatStyle where Self == FixedPointFormatStyle {
  static func fixedPoint(fractionLength: Int) -> FixedPointFormatStyle {
    return FixedPointFormatStyle(fractionLength: fractionLength)
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
  static let inboundSymbol = "↓"
  static let outboundSymbol = "↑"
  static let zero = TransferRates(inboundBytesPerSecond: 0, outboundBytesPerSecond: 0)

  let inboundBytesPerSecond: Double
  let outboundBytesPerSecond: Double

  var totalBytesPerSecond: Double { inboundBytesPerSecond + outboundBytesPerSecond }

  init(inboundBytesPerSecond: Double, outboundBytesPerSecond: Double) {
    self.inboundBytesPerSecond = inboundBytesPerSecond
    self.outboundBytesPerSecond = outboundBytesPerSecond
  }

  init(byteCounts: TransferByteCounts, elapsedSeconds: Double) {
    guard elapsedSeconds > 0 else {
      self = .zero
      return
    }

    self.init(
      inboundBytesPerSecond: Double(byteCounts.inbound) / elapsedSeconds,
      outboundBytesPerSecond: Double(byteCounts.outbound) / elapsedSeconds
    )
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

    guard totalTicks > 0 else {
      self = .zero
      return
    }

    self.init(
      userPercentage: userTicks / totalTicks * 100,
      systemPercentage: systemTicks / totalTicks * 100,
      idlePercentage: idleTicks / totalTicks * 100
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
      return MemoryUsage(usedBytes: 0,  wiredBytes: 0,compressedBytes: 0,  totalBytes: totalBytes)
    }

    let internalPageCount = UInt64(statistics.internal_page_count)
    let purgeablePageCount = min(UInt64(statistics.purgeable_count), internalPageCount)
    let compressedBytes = UInt64(statistics.compressor_page_count) * MachHost.pageSize
    let wiredBytes = UInt64(statistics.wire_count) * MachHost.pageSize

    return MemoryUsage(
      usedBytes: (internalPageCount - purgeablePageCount) * MachHost.pageSize + wiredBytes + compressedBytes,
      wiredBytes: wiredBytes,
      compressedBytes: compressedBytes,
      totalBytes: totalBytes
    )
  }
}

struct BlockStorageStatistics {
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
      IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator)
        == KERN_SUCCESS
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

struct NetworkInterfaceStatistics {
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
        sysctl(&managementInformationBase, UInt32(managementInformationBase.count), buffer.baseAddress, &length, nil, 0)
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

struct SystemResourceUsage {
  let cpu: CPUUsage
  let loadAverages: LoadAverages
  let memory: MemoryUsage
  let disk: TransferRates
  let network: TransferRates
}

struct SystemResourceSampler {
  private var previousCPULoadInfo: host_cpu_load_info?
  private var blockStorageStatistics = BlockStorageStatistics()
  private var networkInterfaceStatistics = NetworkInterfaceStatistics()

  mutating func sample(elapsedSeconds: Double) -> SystemResourceUsage {
    let cpuLoadInfo = MachHost.cpuLoadInfo()
    let diskByteCounts = blockStorageStatistics.byteCountsSinceLastSample()
    let networkByteCounts = networkInterfaceStatistics.byteCountsSinceLastSample()

    let cpuUsage: CPUUsage

    if let cpuLoadInfo, let previousCPULoadInfo {
      cpuUsage = CPUUsage(loadInfo: cpuLoadInfo, previousLoadInfo: previousCPULoadInfo)
    } else {
      cpuUsage = .zero
    }

    self.previousCPULoadInfo = cpuLoadInfo

    return SystemResourceUsage(
      cpu: cpuUsage,
      loadAverages: .current,
      memory: .current,
      disk: TransferRates(byteCounts: diskByteCounts, elapsedSeconds: elapsedSeconds),
      network: TransferRates(byteCounts: networkByteCounts, elapsedSeconds: elapsedSeconds)
    )
  }
}

struct ProcessResourceUsageSample {
  let startTime: UInt64
  let cpuTime: UInt64
  let memoryFootprint: UInt64
  let disk: TransferByteCounts
}

struct RunningProcess {
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

  var commandName: String? {
    guard let shortInfo else {
      return nil
    }

    return withUnsafeBytes(of: shortInfo.pbsi_comm) { bytes in
      String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
  }

  var parentProcess: RunningProcess? {
    guard let shortInfo, pid_t(shortInfo.pbsi_ppid) != processIdentifier else {
      return nil
    }

    return RunningProcess(processIdentifier: pid_t(shortInfo.pbsi_ppid))
  }

  var responsibleProcess: RunningProcess? {
    let responsibleProcessIdentifier = responsibility_get_pid_responsible_for_pid(processIdentifier)

    guard responsibleProcessIdentifier > 0, responsibleProcessIdentifier != processIdentifier else {
      return nil
    }

    return RunningProcess(processIdentifier: responsibleProcessIdentifier)
  }

  private var shortInfo: proc_bsdshortinfo? {
    var shortInfo = proc_bsdshortinfo()

    let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)

    guard proc_pidinfo(processIdentifier, PROC_PIDT_SHORTBSDINFO, 0, &shortInfo, size) == size else {
      return nil
    }

    return shortInfo
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

  func resourceUsage() throws(Errno) -> ProcessResourceUsageSample {
    var resourceUsage = rusage_info_v4()

    let result = withUnsafeMutablePointer(to: &resourceUsage) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPointer in
        proc_pid_rusage(processIdentifier, RUSAGE_INFO_V4, reboundPointer)
      }
    }

    guard result == 0 else {
      throw Errno(rawValue: errno)
    }

    return ProcessResourceUsageSample(
      startTime: resourceUsage.ri_proc_start_abstime,
      cpuTime: resourceUsage.ri_user_time + resourceUsage.ri_system_time,
      memoryFootprint: resourceUsage.ri_phys_footprint,
      disk: TransferByteCounts(
        inbound: resourceUsage.ri_diskio_bytesread,
        outbound: resourceUsage.ri_diskio_byteswritten
      )
    )
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
  let sortKey: String

  var id: ID { ID(processIdentifier: processIdentifier, kind: kind) }

  init(processIdentifier: pid_t, kind: Kind, name: String) {
    self.processIdentifier = processIdentifier
    self.kind = kind
    self.name = name
    self.sortKey = name.lowercased()
  }

  init(of process: RunningProcess, executablePath: FilePath?, processName: String) {
    if let responsibleProcess = process.responsibleProcess,
      let application = Self.application(running: responsibleProcess, executablePath: responsibleProcess.executablePath)
    {
      self = application
    } else if let application = Self.application(running: process, executablePath: executablePath) {
      self = application
    } else if let application = Self.application(runningAncestorOf: process) {
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

  private static func application(runningAncestorOf process: RunningProcess) -> ProcessOwner? {
    var visitedProcessIdentifiers: Set<pid_t> = [process.processIdentifier]
    var ancestorProcess = process.parentProcess

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
  let owner: ProcessOwner

  init?(of process: RunningProcess) {
    let executablePath = process.executablePath

    guard let name = executablePath?.lastComponent?.string ?? process.commandName else {
      return nil
    }

    self.processIdentifier = process.processIdentifier
    self.name = name
    self.parentProcessIdentifier = process.parentProcess?.processIdentifier
    self.owner = ProcessOwner(of: process, executablePath: executablePath, processName: name)
  }
}

@MainActor
final class NetworkStatisticsMonitor {
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

struct ResourceUsage {
  let cpuPercentage: Double
  let memoryFootprint: UInt64
  let disk: TransferRates
  let network: TransferRates
}

struct ProcessOwnerResourceUsage: Identifiable {
  let owner: ProcessOwner
  let usage: ResourceUsage

  var id: ProcessOwner.ID { owner.id }
}

struct ProcessResourceUsage {
  let metadata: ProcessMetadata
  let usage: ResourceUsage
}

struct ResourceUsageSnapshot {
  var owners: [ProcessOwnerResourceUsage]
  let processes: [ProcessResourceUsage]
  let system: SystemResourceUsage
  let applicationCount: Int
  let restrictedProcessCount: Int
}

struct ResourceUsageAccumulator {
  var cpuTime: UInt64 = 0
  var memoryFootprint: UInt64 = 0
  var disk = TransferByteCounts.zero
  var network = TransferByteCounts.zero

  static func += (lhs: inout ResourceUsageAccumulator, rhs: ResourceUsageAccumulator) {
    lhs.cpuTime += rhs.cpuTime
    lhs.memoryFootprint += rhs.memoryFootprint
    lhs.disk += rhs.disk
    lhs.network += rhs.network
  }

  mutating func addUsage(_ usage: ProcessResourceUsageSample, since previousUsage: ProcessResourceUsageSample?) {
    self.cpuTime += usage.cpuTime.delta(since: previousUsage?.cpuTime ?? 0)
    self.memoryFootprint += usage.memoryFootprint
    self.disk += usage.disk.delta(since: previousUsage?.disk ?? .zero)
  }

  func resourceUsage(elapsedAbsoluteTime: UInt64) -> ResourceUsage {
    let elapsedSeconds = MachAbsoluteTime.seconds(from: elapsedAbsoluteTime)
    return ResourceUsage(
      cpuPercentage: elapsedAbsoluteTime > 0 ? Double(cpuTime) / Double(elapsedAbsoluteTime) * 100 : 0,
      memoryFootprint: memoryFootprint,
      disk: TransferRates(byteCounts: disk, elapsedSeconds: elapsedSeconds),
      network: TransferRates(byteCounts: network, elapsedSeconds: elapsedSeconds)
    )
  }
}

@MainActor
final class ResourceUsageSampler {
  private struct TrackedProcess {
    let metadata: ProcessMetadata
    let usage: ProcessResourceUsageSample
    let sampleGeneration: UInt64
  }

  private struct OwnerResourceUsageAccumulator {
    let owner: ProcessOwner
    var accumulator = ResourceUsageAccumulator()
  }

  private let networkStatisticsMonitor: NetworkStatisticsMonitor
  private var systemResourceSampler = SystemResourceSampler()
  private var trackedProcesses: [pid_t: TrackedProcess] = [:]
  private var processIdentifierBuffer = [pid_t](repeating: 0, count: 1024)
  private var sampleGeneration: UInt64 = 0
  private var previousSampleTime: UInt64?
  private var previousOwnerCount = 0

  init(networkStatisticsMonitor: NetworkStatisticsMonitor) {
    self.networkStatisticsMonitor = networkStatisticsMonitor
  }

  func sample() async -> ResourceUsageSnapshot {
    var networkByteCounts = await networkStatisticsMonitor.byteCountsSinceLastSample()

    let sampleTime = MachAbsoluteTime.now
    let isBaselineSample = previousSampleTime == nil
    let elapsedAbsoluteTime = previousSampleTime.map { sampleTime - $0 } ?? 0
    let processIdentifierCount = RunningProcess.listAllProcessIdentifiers(into: &processIdentifierBuffer)

    var ownerResourceUsageAccumulators: [ProcessOwner.ID: OwnerResourceUsageAccumulator] = [:]
    ownerResourceUsageAccumulators.reserveCapacity(previousOwnerCount)

    var processes: [ProcessResourceUsage] = []
    processes.reserveCapacity(trackedProcesses.count)

    var restrictedProcessCount = 0

    self.sampleGeneration &+= 1

    for processIdentifier in processIdentifierBuffer[..<processIdentifierCount] {
      let process = RunningProcess(processIdentifier: processIdentifier)
      let usage: ProcessResourceUsageSample

      do throws(Errno) {
        usage = try process.resourceUsage()
      } catch {
        if error == .notPermitted {
          restrictedProcessCount += 1
        }

        continue
      }

      let metadata: ProcessMetadata
      let previousUsage: ProcessResourceUsageSample?

      if let trackedProcess = trackedProcesses[processIdentifier], trackedProcess.usage.startTime == usage.startTime {
        metadata = trackedProcess.metadata
        previousUsage = trackedProcess.usage
      } else if let resolvedMetadata = ProcessMetadata(of: process) {
        metadata = resolvedMetadata
        previousUsage = isBaselineSample ? usage : nil
      } else {
        continue
      }

      var processResourceUsageAccumulator = ResourceUsageAccumulator()

      processResourceUsageAccumulator.addUsage(usage, since: previousUsage)

      if let processNetworkByteCounts = networkByteCounts.removeValue(forKey: processIdentifier) {
        processResourceUsageAccumulator.network += processNetworkByteCounts
      }

      self.trackedProcesses[processIdentifier] = TrackedProcess(
        metadata: metadata,
        usage: usage,
        sampleGeneration: sampleGeneration
      )

      ownerResourceUsageAccumulators[
        metadata.owner.id,
        default: OwnerResourceUsageAccumulator(owner: metadata.owner)
      ].accumulator += processResourceUsageAccumulator
      processes.append(
        ProcessResourceUsage(
          metadata: metadata,
          usage: processResourceUsageAccumulator.resourceUsage(elapsedAbsoluteTime: elapsedAbsoluteTime)
        )
      )
    }

    for (processIdentifier, byteCounts) in networkByteCounts {
      guard let owner = trackedProcesses[processIdentifier]?.metadata.owner else {
        continue
      }

      ownerResourceUsageAccumulators[
        owner.id,
        default: OwnerResourceUsageAccumulator(owner: owner)
      ].accumulator.network += byteCounts
    }

    if trackedProcesses.count != processes.count {
      self.trackedProcesses = trackedProcesses.filter { $0.value.sampleGeneration == sampleGeneration }
    }

    let owners = ownerResourceUsageAccumulators.values.map { ownerResourceUsageAccumulator in
      ProcessOwnerResourceUsage(
        owner: ownerResourceUsageAccumulator.owner,
        usage: ownerResourceUsageAccumulator.accumulator.resourceUsage(elapsedAbsoluteTime: elapsedAbsoluteTime)
      )
    }
    let systemResourceUsage = self.systemResourceSampler.sample(
      elapsedSeconds: MachAbsoluteTime.seconds(from: elapsedAbsoluteTime)
    )

    self.previousSampleTime = sampleTime
    self.previousOwnerCount = ownerResourceUsageAccumulators.count

    return ResourceUsageSnapshot(
      owners: owners,
      processes: processes,
      system: systemResourceUsage,
      applicationCount: owners.count { $0.owner.kind == .application },
      restrictedProcessCount: restrictedProcessCount
    )
  }
}

enum ANSIEscapeSequence {
  static let enterAlternateScreen = "\u{1B}[?1049h"
  static let exitAlternateScreen = "\u{1B}[?1049l"
  static let hideCursor = "\u{1B}[?25l"
  static let showCursor = "\u{1B}[?25h"
  static let disableLineWrapping = "\u{1B}[?7l"
  static let enableLineWrapping = "\u{1B}[?7h"
  static let enableGraphemeClustering = "\u{1B}[?2027h"
  static let disableGraphemeClustering = "\u{1B}[?2027l"
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
  case bold
  case underline
  case deemphasized
  case inverse

  func applied(to text: String) -> String {
    switch self {
    case .bold: return "\(ANSIEscapeSequence.bold)\(text)\(ANSIEscapeSequence.normalIntensity)"
    case .underline: return "\(ANSIEscapeSequence.underline)\(text)\(ANSIEscapeSequence.noUnderline)"
    case .deemphasized: return "\(ANSIEscapeSequence.faint)\(text)\(ANSIEscapeSequence.normalIntensity)"
    case .inverse: return "\(ANSIEscapeSequence.reverseVideo)\(text)\(ANSIEscapeSequence.noReverseVideo)"
    }
  }
}

enum TextAlignment {
  case leading
  case trailing
}

extension Character {
  var terminalColumnWidth: Int {
    guard let scalar = unicodeScalars.first, !scalar.isASCII else {
      return 1
    }

    if scalar.properties.isEmojiPresentation || unicodeScalars.contains("\u{FE0F}") {
      return 2
    }

    return max(Int(wcwidth(wchar_t(scalar.value))), 0)
  }
}

extension String {
  private enum EscapeSequenceParsingState {
    case text
    case escapeSequence
    case controlSequence
  }

  var visibleWidth: Int {
    guard utf8.contains(where: { $0 >= 0x80 || $0 == 0x1B }) else {
      return utf8.count
    }

    var width = 0

    forEachVisibleCharacter { _, character in
      width += character.terminalColumnWidth
      return true
    }

    return width
  }

  func truncated(toVisibleWidth width: Int, trimsWhitespaceBeforeEllipsis: Bool = false) -> String {
    guard width > 0, utf8.count > width else {
      return self
    }

    var columnCount = 0
    var ellipsisIndex: Index?

    forEachVisibleCharacter { index, character in
      let characterWidth = character.terminalColumnWidth

      if ellipsisIndex == nil, columnCount + characterWidth >= width {
        ellipsisIndex = index
      }

      columnCount += characterWidth

      return columnCount <= width
    }

    guard let ellipsisIndex, columnCount > width else {
      return self
    }

    var visiblePrefix = self[..<ellipsisIndex]

    if trimsWhitespaceBeforeEllipsis {
      while visiblePrefix.last?.isWhitespace == true {
        visiblePrefix.removeLast()
      }
    }

    return "\(visiblePrefix)…"
  }

  private func forEachVisibleCharacter(_ body: (Index, Character) -> Bool) {
    var parsingState = EscapeSequenceParsingState.text

    for (index, character) in zip(indices, self) {
      switch parsingState {
      case .escapeSequence:
        parsingState = character == "[" ? .controlSequence : .text

      case .controlSequence:
        if let asciiValue = character.asciiValue, (0x40...0x7E).contains(asciiValue) {
          parsingState = .text
        }

      case .text:
        guard character != "\u{1B}" else {
          parsingState = .escapeSequence
          continue
        }

        guard body(index, character) else {
          return
        }
      }
    }
  }
}

enum ResourceUsageColumn: String, CaseIterable {
  case pid
  case name
  case cpu
  case memory
  case disk
  case network

  private static let transferRateValueWidth = 8

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
    case .disk, .network: (Self.transferRateValueWidth + 1 + TransferRates.inboundSymbol.count) * 2 + 1
    }
  }

  var alignment: TextAlignment { self == .name ? .leading : .trailing }

  func formattedValue(processIdentifier: pid_t?, name: String, usage: ResourceUsage) -> String {
    switch self {
    case .pid:
      return processIdentifier.map { String($0) } ?? ""

    case .name:
      return name

    case .cpu:
      return Self.deemphasized(
        usage.cpuPercentage.formatted(.fixedPoint(fractionLength: 1)),
        if: (usage.cpuPercentage * 10).rounded() == 0
      )

    case .memory:
      return Self.deemphasized(
        Double(usage.memoryFootprint).formatted(.abbreviatedByteCount),
        if: usage.memoryFootprint == 0
      )

    case .disk:
      return Self.formattedTransferRates(usage.disk)

    case .network:
      return Self.formattedTransferRates(usage.network)
    }
  }

  func precedes(_ lhs: ProcessOwnerResourceUsage, _ rhs: ProcessOwnerResourceUsage) -> Bool {
    switch self {
    case .pid: return lhs.owner.processIdentifier < rhs.owner.processIdentifier
    case .name: return Self.precedesByName(lhs, rhs)
    case .cpu: return Self.precedes(lhs, rhs, descendingBy: \.usage.cpuPercentage)
    case .memory: return Self.precedes(lhs, rhs, descendingBy: \.usage.memoryFootprint)
    case .disk: return Self.precedes(lhs, rhs, descendingBy: \.usage.disk.totalBytesPerSecond)
    case .network: return Self.precedes(lhs, rhs, descendingBy: \.usage.network.totalBytesPerSecond)
    }
  }

  private static func formattedTransferRates(_ transferRates: TransferRates) -> String {
    let formattedInboundTransferRate = formattedTransferRate(
      transferRates.inboundBytesPerSecond,
      symbol: TransferRates.inboundSymbol
    )
    let formattedOutboundTransferRate = formattedTransferRate(
      transferRates.outboundBytesPerSecond,
      symbol: TransferRates.outboundSymbol
    )

    return "\(formattedInboundTransferRate) \(formattedOutboundTransferRate)"
  }

  private static func precedes<Value: Comparable>(
    _ lhs: ProcessOwnerResourceUsage,
    _ rhs: ProcessOwnerResourceUsage,
    descendingBy keyPath: KeyPath<ProcessOwnerResourceUsage, Value>
  ) -> Bool {
    let lhsValue = lhs[keyPath: keyPath]
    let rhsValue = rhs[keyPath: keyPath]

    guard lhsValue == rhsValue else {
      return lhsValue > rhsValue
    }

    return precedesByName(lhs, rhs)
  }

  private static func precedesByName(_ lhs: ProcessOwnerResourceUsage, _ rhs: ProcessOwnerResourceUsage) -> Bool {
    guard lhs.owner.sortKey != rhs.owner.sortKey else {
      return lhs.owner.processIdentifier < rhs.owner.processIdentifier
    }

    return lhs.owner.sortKey < rhs.owner.sortKey
  }

  private static func formattedTransferRate(_ bytesPerSecond: Double, symbol: String) -> String {
    let formattedValue = bytesPerSecond.formatted(.abbreviatedByteCount)
    let padding = String(repeating: " ", count: max(transferRateValueWidth - formattedValue.count, 0))
    let styledValue = deemphasized("\(formattedValue) \(symbol)", if: bytesPerSecond.rounded() == 0)

    return "\(padding)\(styledValue)"
  }

  private static func deemphasized(_ text: String, if condition: Bool) -> String {
    return condition ? TextEmphasis.deemphasized.applied(to: text) : text
  }
}

struct ProcessOwnerResourceUsageOrdering {
  private var ownerPositions: [ProcessOwner.ID: Int] = [:]

  mutating func arrange(
    _ owners: inout [ProcessOwnerResourceUsage],
    sortedBy column: ResourceUsageColumn,
    shouldReSort: Bool
  ) {
    if shouldReSort {
      owners.sort(by: column.precedes)
    } else {
      owners.sort { lhs, rhs in
        switch (ownerPositions[lhs.id], ownerPositions[rhs.id]) {
        case (let lhsPosition?, let rhsPosition?): return lhsPosition < rhsPosition
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): return column.precedes(lhs, rhs)
        }
      }
    }

    self.ownerPositions.removeAll(keepingCapacity: true)

    for (position, owner) in owners.enumerated() {
      self.ownerPositions[owner.id] = position
    }
  }
}

struct ResourceUsageTableRow: Identifiable {
  enum ID: Hashable {
    case owner(ProcessOwner.ID)
    case process(pid_t)
  }

  let id: ID
  let processIdentifier: pid_t
  let name: String
  let usage: ResourceUsage

  init(processIdentifier: pid_t, name: String, usage: ResourceUsage) {
    self.id = .process(processIdentifier)
    self.processIdentifier = processIdentifier
    self.name = name
    self.usage = usage
  }

  init(ownerResourceUsage: ProcessOwnerResourceUsage) {
    self.id = .owner(ownerResourceUsage.id)
    self.processIdentifier = ownerResourceUsage.owner.processIdentifier
    self.name = ownerResourceUsage.owner.name
    self.usage = ownerResourceUsage.usage
  }
}

struct ResourceUsageTable {
  let nameColumnTitle: String
  let sortColumn: ResourceUsageColumn?
  let caption: String?
  let rows: [ResourceUsageTableRow]
  let totalUsage: ResourceUsage?
}

struct TableSelection {
  enum Destination {
    case previous
    case next
    case first
    case last
  }

  private(set) var selectedRowID: ResourceUsageTableRow.ID?
  private(set) var scrollOffset = 0
  private var rowIndex = 0

  var selectedRowIndex: Int? { selectedRowID == nil ? nil : rowIndex }

  mutating func reconcile(with rows: [ResourceUsageTableRow], visibleRowCount: Int) {
    if let selectedRowID {
      if let matchingRowIndex = rows.firstIndex(where: { $0.id == selectedRowID }) {
        self.rowIndex = matchingRowIndex
      } else if rows.isEmpty {
        self.selectedRowID = nil
      } else {
        self.rowIndex = min(rowIndex, rows.count - 1)
        self.selectedRowID = rows[rowIndex].id
      }
    }

    scrollToSelection(rowCount: rows.count, visibleRowCount: visibleRowCount)
  }

  mutating func move(to destination: Destination, in rows: [ResourceUsageTableRow], visibleRowCount: Int) {
    guard !rows.isEmpty else {
      return
    }

    reconcile(with: rows, visibleRowCount: visibleRowCount)

    switch destination {
    case .first:
      self.rowIndex = 0

    case .last:
      self.rowIndex = rows.count - 1

    case .previous where selectedRowID == nil, .next where selectedRowID == nil:
      self.rowIndex = min(scrollOffset, rows.count - 1)

    case .previous:
      self.rowIndex = max(rowIndex - 1, 0)

    case .next:
      self.rowIndex = min(rowIndex + 1, rows.count - 1)
    }

    self.selectedRowID = rows[rowIndex].id

    scrollToSelection(rowCount: rows.count, visibleRowCount: visibleRowCount)
  }

  mutating func clear() {
    self.selectedRowID = nil
    self.rowIndex = 0
    self.scrollOffset = 0
  }

  private mutating func scrollToSelection(rowCount: Int, visibleRowCount: Int) {
    if selectedRowID != nil, visibleRowCount > 0 {
      if rowIndex < scrollOffset {
        self.scrollOffset = rowIndex
      } else if rowIndex >= scrollOffset + visibleRowCount {
        self.scrollOffset = rowIndex - visibleRowCount + 1
      }
    }

    self.scrollOffset = min(scrollOffset, max(rowCount - visibleRowCount, 0))
  }
}

enum ProcessTree {
  private static let branchPrefix = "├─ "
  private static let lastBranchPrefix = "└─ "
  private static let continuationPrefix = "│  "
  private static let emptyPrefix = "   "

  static func rows(for processes: [ProcessResourceUsage], ownedBy owner: ProcessOwner) -> [ResourceUsageTableRow] {
    let processIdentifiers = Set(processes.map(\.metadata.processIdentifier))

    var childProcessesByParentIdentifier: [pid_t: [ProcessResourceUsage]] = [:]
    var rootProcesses: [ProcessResourceUsage] = []

    for process in processes {
      if let parentProcessIdentifier = process.metadata.parentProcessIdentifier,
        processIdentifiers.contains(parentProcessIdentifier)
      {
        childProcessesByParentIdentifier[parentProcessIdentifier, default: []].append(process)
      } else {
        rootProcesses.append(process)
      }
    }

    var rows: [ResourceUsageTableRow] = []
    rows.reserveCapacity(processes.count)

    func appendRows(for process: ProcessResourceUsage, namePrefix: String, descendantPrefix: String) {
      rows.append(
        ResourceUsageTableRow(
          processIdentifier: process.metadata.processIdentifier,
          name: "\(namePrefix)\(process.metadata.name)",
          usage: process.usage
        )
      )

      let childProcesses = childProcessesByParentIdentifier[
        process.metadata.processIdentifier,
        default: []
      ].sorted { $0.metadata.processIdentifier < $1.metadata.processIdentifier }

      for (index, childProcess) in childProcesses.enumerated() {
        let isLastChildProcess = index == childProcesses.count - 1
        appendRows(
          for: childProcess,
          namePrefix: "\(descendantPrefix)\(isLastChildProcess ? lastBranchPrefix : branchPrefix)",
          descendantPrefix: "\(descendantPrefix)\(isLastChildProcess ? emptyPrefix : continuationPrefix)"
        )
      }
    }

    let sortedRootProcesses = rootProcesses.sorted { lhs, rhs in
      let lhsIsOwnerProcess = lhs.metadata.processIdentifier == owner.processIdentifier
      let rhsIsOwnerProcess = rhs.metadata.processIdentifier == owner.processIdentifier

      guard lhsIsOwnerProcess == rhsIsOwnerProcess else {
        return lhsIsOwnerProcess
      }

      return lhs.metadata.processIdentifier < rhs.metadata.processIdentifier
    }

    for rootProcess in sortedRootProcesses {
      appendRows(for: rootProcess, namePrefix: "", descendantPrefix: "")
    }

    return rows
  }
}

enum ResourceUsageTableRenderer {
  private struct SummaryField {
    let value: String
    let valueWidth: Int
    let label: String

    init(count: Int, label: String) {
      self.init(value: String(count), valueWidth: 5, label: label)
    }

    init(count: Int, of totalCount: Int, label: String) {
      self.init(value: "\(count)/\(totalCount)", valueWidth: 9, label: label)
    }

    init(percentage: Double, label: String) {
      self.init(value: "\(percentage.formatted(.fixedPoint(fractionLength: 1)))%", valueWidth: 6, label: label)
    }

    init(loadAverage: Double, label: String) {
      self.init(value: loadAverage.formatted(.fixedPoint(fractionLength: 2)), valueWidth: 5, label: label)
    }

    init(byteCount: UInt64, label: String) {
      self.init(value: Double(byteCount).formatted(.abbreviatedByteCount), valueWidth: 8, label: label)
    }

    init(bytesPerSecond: Double, label: String) {
      self.init(value: bytesPerSecond.formatted(.abbreviatedByteRate), valueWidth: 10, label: label)
    }

    private init(value: String, valueWidth: Int, label: String) {
      self.value = value
      self.valueWidth = valueWidth
      self.label = label
    }
  }

  private struct SummaryRow {
    let title: String
    let fields: [SummaryField]
    var trailingNote: String?
  }

  private static let columnSeparator = "  "
  private static let minimumNameColumnWidth = 6
  private static let scrollbarThumbCell = " │"
  private static let scrollbarColumnWidth = scrollbarThumbCell.count
  private static let fixedColumnsWidth =
    ResourceUsageColumn.allCases.compactMap(\.fixedWidth).reduce(0, +)
    + (ResourceUsageColumn.allCases.count - 1) * columnSeparator.count
  private static let minimumTableWidth = fixedColumnsWidth + minimumNameColumnWidth + scrollbarColumnWidth
  private static let tableLeadingLineCount = 3
  private static let estimatedEscapeSequenceBytesPerLine = 64

  static func visibleRowCount(
    for table: ResourceUsageTable,
    summaryLineCount: Int,
    size: TerminalSession.Size
  ) -> Int {
    let trailingLineCount = table.totalUsage == nil ? 0 : 1
    return max(size.rows - summaryLineCount - tableLeadingLineCount - trailingLineCount, 0)
  }

  static func frame(
    summaryLines: [String],
    table: ResourceUsageTable,
    selection: TableSelection,
    size: TerminalSession.Size
  ) -> String {
    let nameColumnWidth = max(size.columns - fixedColumnsWidth - scrollbarColumnWidth, minimumNameColumnWidth)
    let rowCapacity = visibleRowCount(for: table, summaryLineCount: summaryLines.count, size: size)
    let visibleRows = table.rows.dropFirst(selection.scrollOffset).prefix(rowCapacity)
    let thumbRange = scrollbarThumbRange(
      rowCount: table.rows.count,
      rowCapacity: rowCapacity,
      scrollOffset: selection.scrollOffset
    )
    let truncatesTableLines = size.columns < minimumTableWidth

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
      frame += truncates ? line.truncated(toVisibleWidth: size.columns) : line
      frame += ANSIEscapeSequence.resetAttributes
      lineCount += 1
    }

    for summaryLine in summaryLines {
      appendLine(summaryLine)
    }

    appendLine("")
    appendLine(table.caption ?? "")
    appendLine(headerLine(for: table, nameColumnWidth: nameColumnWidth), truncates: truncatesTableLines)

    for (rowIndex, row) in zip(visibleRows.indices, visibleRows) {
      let line = rowLine(for: row, nameColumnWidth: nameColumnWidth, isSelected: rowIndex == selection.selectedRowIndex)
      let isScrollbarThumbRow = thumbRange?.contains(rowIndex - selection.scrollOffset) ?? false

      appendLine(isScrollbarThumbRow ? "\(line)\(scrollbarThumbCell)" : line, truncates: truncatesTableLines)
    }

    if let totalUsage = table.totalUsage {
      appendLine(totalLine(for: totalUsage, nameColumnWidth: nameColumnWidth), truncates: truncatesTableLines)
    }

    if lineCount < size.rows {
      frame += "\n\(ANSIEscapeSequence.clearToEndOfScreen)"
    }

    frame += ANSIEscapeSequence.endSynchronizedUpdate

    return frame
  }

  static func summaryLines(for snapshot: ResourceUsageSnapshot) -> [String] {
    let rows = summaryRows(for: snapshot)
    let titleWidth = rows.map(\.title.count).max() ?? 0
    let fieldCount = rows.map(\.fields.count).max() ?? 0

    let valueWidths = (0..<fieldCount).map { index in
      rows.compactMap { $0.fields.indices.contains(index) ? $0.fields[index].valueWidth : nil }.max() ?? 0
    }

    let labelWidths = (0..<fieldCount).map { index in
      rows.compactMap { $0.fields.indices.contains(index) ? $0.fields[index].label.count : nil }.max() ?? 0
    }

    return rows.map { row in
      let formattedFields = row.fields.enumerated().map { index, field in
        let formattedValue = cell(
          field.value,
          width: max(valueWidths[index], field.value.count),
          alignment: .trailing,
          emphasis: .bold
        )
        let formattedLabel =
          index == row.fields.count - 1
          ? field.label
          : cell(field.label, width: labelWidths[index], alignment: .leading)

        return "\(formattedValue) \(formattedLabel)"
      }

      let formattedTitle = cell(row.title, width: titleWidth, alignment: .leading, emphasis: .bold)
      let joinedFormattedFields = formattedFields.joined(separator: columnSeparator)
      let formattedTrailingNote =
        row.trailingNote.map { "\(columnSeparator)\(TextEmphasis.deemphasized.applied(to: $0))" } ?? ""

      return "\(formattedTitle)\(columnSeparator)\(joinedFormattedFields)\(formattedTrailingNote)"
    }
  }

  private static func summaryRows(for snapshot: ResourceUsageSnapshot) -> [SummaryRow] {
    let system = snapshot.system
    let hasRestrictedProcesses = snapshot.restrictedProcessCount > 0
    let processCountField =
      hasRestrictedProcesses
      ? SummaryField(
        count: snapshot.processes.count,
        of: snapshot.processes.count + snapshot.restrictedProcessCount,
        label: "visible"
      )
      : SummaryField(count: snapshot.processes.count, label: "total")

    return [
      SummaryRow(
        title: "Processes",
        fields: [processCountField, SummaryField(count: snapshot.applicationCount, label: "applications")],
        trailingNote: hasRestrictedProcesses ? "(run with sudo to show all)" : nil
      ),
      SummaryRow(
        title: "CPU",
        fields: [
          SummaryField(percentage: system.cpu.userPercentage, label: "user"),
          SummaryField(percentage: system.cpu.systemPercentage, label: "system"),
          SummaryField(percentage: system.cpu.idlePercentage, label: "idle")
        ]
      ),
      SummaryRow(
        title: "Load Avg",
        fields: [
          SummaryField(loadAverage: system.loadAverages.oneMinute, label: "1 min"),
          SummaryField(loadAverage: system.loadAverages.fiveMinutes, label: "5 min"),
          SummaryField(loadAverage: system.loadAverages.fifteenMinutes, label: "15 min")
        ]
      ),
      SummaryRow(
        title: "Memory",
        fields: [
          SummaryField(byteCount: system.memory.usedBytes, label: "used"),
          SummaryField(byteCount: system.memory.wiredBytes, label: "wired"),
          SummaryField(byteCount: system.memory.compressedBytes, label: "compressed"),
          SummaryField(byteCount: system.memory.totalBytes, label: "total")
        ]
      ),
      SummaryRow(
        title: "Disk",
        fields: transferRateFields(for: system.disk, inboundLabel: "read", outboundLabel: "written")
      ),
      SummaryRow(
        title: "Network",
        fields: transferRateFields(for: system.network, inboundLabel: "received", outboundLabel: "sent")
      )
    ]
  }

  private static func transferRateFields(
    for transferRates: TransferRates,
    inboundLabel: String,
    outboundLabel: String
  ) -> [SummaryField] {
    return [
      SummaryField(bytesPerSecond: transferRates.inboundBytesPerSecond, label: inboundLabel),
      SummaryField(bytesPerSecond: transferRates.outboundBytesPerSecond, label: outboundLabel)
    ]
  }

  private static func tableLine(
    nameColumnWidth: Int,
    content: (ResourceUsageColumn) -> (text: String, emphasis: TextEmphasis?)
  ) -> String {
    return ResourceUsageColumn.allCases.map { column in
      let (text, emphasis) = content(column)
      return cell(text, width: column.fixedWidth ?? nameColumnWidth, alignment: column.alignment, emphasis: emphasis)
    }
    .joined(separator: columnSeparator)
  }

  private static func headerLine(for table: ResourceUsageTable, nameColumnWidth: Int) -> String {
    let line = tableLine(nameColumnWidth: nameColumnWidth) { column in
      (column == .name ? table.nameColumnTitle : column.title, column == table.sortColumn ? .underline : nil)
    }
    return TextEmphasis.bold.applied(to: line)
  }

  private static func rowLine(for row: ResourceUsageTableRow, nameColumnWidth: Int, isSelected: Bool) -> String {
    let line = tableLine(nameColumnWidth: nameColumnWidth) { column in
      (column.formattedValue(processIdentifier: row.processIdentifier, name: row.name, usage: row.usage), nil)
    }
    return isSelected ? TextEmphasis.inverse.applied(to: line) : line
  }

  private static func totalLine(for usage: ResourceUsage, nameColumnWidth: Int) -> String {
    return tableLine(nameColumnWidth: nameColumnWidth) { column in
      (column.formattedValue(processIdentifier: nil, name: "Total", usage: usage), column == .name ? .bold : nil)
    }
  }

  private static func cell(
    _ text: String,
    width: Int,
    alignment: TextAlignment,
    emphasis: TextEmphasis? = nil
  ) -> String {
    var visibleText = text
    var visibleWidth = text.visibleWidth

    if visibleWidth > width {
      visibleText = text.truncated(toVisibleWidth: width, trimsWhitespaceBeforeEllipsis: true)
      visibleWidth = visibleText.visibleWidth
    }

    let padding = String(repeating: " ", count: max(width - visibleWidth, 0))
    let styledText = emphasis?.applied(to: visibleText) ?? visibleText

    switch alignment {
    case .leading: return "\(styledText)\(padding)"
    case .trailing: return "\(padding)\(styledText)"
    }
  }

  private static func scrollbarThumbRange(rowCount: Int, rowCapacity: Int, scrollOffset: Int) -> Range<Int>? {
    guard rowCapacity > 0, rowCount > rowCapacity else {
      return nil
    }

    let thumbLength = max(Int((Double(rowCapacity * rowCapacity) / Double(rowCount)).rounded()), 1)
    let maximumScrollOffset = rowCount - rowCapacity
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

  private let originalAttributes: termios
  private var isActive = false

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

  private func write(_ string: String) {
    _ = try? FileDescriptor.standardOutput.writeAll(string.utf8)
  }
}

enum KeyboardCommand: Equatable {
  case moveSelection(to: TableSelection.Destination)
  case openSelection
  case goBack
  case quit

  private static let escape: UInt8 = 0x1B
  private static let introducerBytes: [UInt8] = [UInt8(ascii: "["), UInt8(ascii: "O")]
  private static let finalByteRange: ClosedRange<UInt8> = 0x40...0x7E
  private static let escapeSequenceTimeout: Duration = .milliseconds(25)

  static func readCommands(from fileDescriptor: FileDescriptor) -> [KeyboardCommand]? {
    var input: [UInt8] = []

    repeat {
      let byteCount = withUnsafeTemporaryAllocation(byteCount: 256, alignment: 1) { buffer in
        let bytesRead = (try? fileDescriptor.read(into: buffer)) ?? 0

        input.append(contentsOf: buffer[..<bytesRead])

        return bytesRead
      }

      guard byteCount > 0 else {
        return input.isEmpty ? nil : commands(in: input)
      }
    } while endsWithIncompleteEscapeSequence(input) && fileDescriptor.waitUntilReadable(timeout: escapeSequenceTimeout)

    return commands(in: input)
  }

  static func commands(in input: [UInt8]) -> [KeyboardCommand] {
    var commands: [KeyboardCommand] = []
    var index = input.startIndex

    while index < input.endIndex {
      let byte = input[index]

      index += 1

      switch byte {
      case escape:
        guard index < input.endIndex, introducerBytes.contains(input[index]) else {
          commands.append(.goBack)
          continue
        }

        let parametersStartIndex = index + 1

        guard
          let finalByteIndex = input[parametersStartIndex...].firstIndex(where: { finalByteRange.contains($0) })
        else {
          index = input.endIndex
          continue
        }

        let isModified = modifierValue(in: input[parametersStartIndex..<finalByteIndex]) > 1

        index = finalByteIndex + 1

        switch input[finalByteIndex] {
        case UInt8(ascii: "A"): commands.append(.moveSelection(to: isModified ? .first : .previous))
        case UInt8(ascii: "B"): commands.append(.moveSelection(to: isModified ? .last : .next))
        default: break
        }

      case UInt8(ascii: "k"): commands.append(.moveSelection(to: .previous))
      case UInt8(ascii: "j"): commands.append(.moveSelection(to: .next))
      case UInt8(ascii: "K"): commands.append(.moveSelection(to: .first))
      case UInt8(ascii: "J"): commands.append(.moveSelection(to: .last))
      case UInt8(ascii: " "), UInt8(ascii: "\r"), UInt8(ascii: "\n"): commands.append(.openSelection)
      case UInt8(ascii: "q"): commands.append(.quit)
      default: break
      }
    }

    return commands
  }

  private static func modifierValue(in parameters: ArraySlice<UInt8>) -> Int {
    let parameterValues = parameters.split(separator: UInt8(ascii: ";"))

    guard
      parameterValues.count > 1,
      let modifierValue = Int(String(decoding: parameterValues[1], as: UTF8.self))
    else {
      return 1
    }

    return modifierValue
  }

  private static func endsWithIncompleteEscapeSequence(_ input: [UInt8]) -> Bool {
    guard let escapeIndex = input.lastIndex(of: escape) else {
      return false
    }

    let sequence = input[(escapeIndex + 1)...]

    guard let introducer = sequence.first else {
      return true
    }

    return introducerBytes.contains(introducer) && !sequence.dropFirst().contains { finalByteRange.contains($0) }
  }
}

@MainActor
final class ResourceUsageMonitor {
  struct Options {
    private static let intervalSecondsRange = 0.5...86_400.0
    private static let sortColumnNames = ResourceUsageColumn.allCases.map(\.rawValue).joined(separator: ", ")
    private static let usageDescription = """
      Usage:
        \(ProcessInfo.processInfo.processName) [options]

      Options:
        -i, --interval <seconds>           Set refresh interval in seconds [default: 2]
        -r, --re-sort-interval <seconds>   Set re-sort interval in seconds (≥ refresh interval) [default: refresh interval]
        -s, --sort <column>                Set sort column (\(sortColumnNames)) [default: cpu]
        -a, --applications-only            Only show applications
        -h, --help                         Show this help message

      Keys:
        ↑/↓, k/j                           Move the selection
        shift + ↑/↓, K/J                   Move the selection to the top or bottom
        return, space                      Show the process tree of the selected application
        esc                                Clear the selection or return to the application list
        q                                  Quit
      """

    var refreshInterval: Duration = .seconds(2)
    var reSortInterval: Duration?
    var sortColumn: ResourceUsageColumn = .cpu
    var showsApplicationsOnly = false

    init(arguments: some Sequence<String>) {
      var arguments = arguments.makeIterator()

      while let argument = arguments.next() {
        switch argument {
        case "-i", "--interval":
          self.refreshInterval = Self.duration(fromSecondsValue: arguments.next(), for: argument)

        case "-r", "--re-sort-interval":
          self.reSortInterval = Self.duration(fromSecondsValue: arguments.next(), for: argument)

        case "-s", "--sort":
          guard let value = arguments.next() else {
            Self.printUsageErrorAndExit("Missing value for '\(argument)'.")
          }

          guard let column = ResourceUsageColumn(rawValue: value.lowercased()) else {
            Self.printUsageErrorAndExit("Invalid sort column '\(value)'. Expected one of: \(Self.sortColumnNames).")
          }

          self.sortColumn = column

        case "-a", "--applications-only":
          self.showsApplicationsOnly = true

        case "-h", "--help":
          print(Self.usageDescription)
          exit(EXIT_SUCCESS)

        default:
          Self.printUsageErrorAndExit("Unknown argument: \(argument)")
        }
      }

      if let reSortInterval, reSortInterval < refreshInterval {
        Self.printUsageErrorAndExit("Re-sort interval must be greater than or equal to the refresh interval.")
      }
    }

    private static func duration(fromSecondsValue value: String?, for argument: String) -> Duration {
      guard let value else {
        printUsageErrorAndExit("Missing value for '\(argument)'.")
      }

      guard let seconds = Double(value), intervalSecondsRange.contains(seconds) else {
        printUsageErrorAndExit(
          "Invalid value '\(value)' for '\(argument)'. Expected \(intervalSecondsRange.lowerBound) to \(Int(intervalSecondsRange.upperBound)) seconds."
        )
      }

      return .seconds(seconds)
    }

    private static func printUsageErrorAndExit(_ message: String) -> Never {
      Log.error("Error: \(message)\n\n\(usageDescription)")
      exit(EX_USAGE)
    }
  }

  private enum Event {
    case redraw
    case suspend
    case keyboardCommands([KeyboardCommand])
    case quit

    static func stream() -> AsyncStream<Event> {
      let (stream, continuation) = AsyncStream.makeStream(of: Event.self)

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

  private enum Screen {
    case processOwners
    case processTree(owner: ProcessOwner)
  }

  private static let maximumInitialRefreshDelay: Duration = .milliseconds(500)
  private static let maximumRefreshTolerance: Duration = .milliseconds(100)

  private let options: Options
  private let minimumReSortInterval: Duration
  private let terminalSession: TerminalSession
  private let sampler: ResourceUsageSampler
  private var latestSnapshot: ResourceUsageSnapshot?
  private var lastReSortInstant: ContinuousClock.Instant?
  private var summaryLines: [String] = []
  private var screen = Screen.processOwners
  private var table: ResourceUsageTable?
  private var ownerOrdering = ProcessOwnerResourceUsageOrdering()
  private var tableSelection = TableSelection()
  private var processOwnersSelection = TableSelection()

  init(options: Options) throws {
    self.options = options
    self.minimumReSortInterval =
      (options.reSortInterval ?? options.refreshInterval) - options.refreshInterval / 2
    self.terminalSession = try TerminalSession()
    self.sampler = ResourceUsageSampler(networkStatisticsMonitor: try NetworkStatisticsMonitor())
  }

  func run() async {
    _ = await sampler.sample()

    terminalSession.activate()

    defer {
      terminalSession.deactivate()
    }

    let refreshTask = Task {
      await refreshPeriodically()
    }

    defer {
      refreshTask.cancel()
    }

    for await event in Event.stream() {
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
      case .moveSelection(let destination): moveSelection(to: destination)
      case .openSelection: openSelection()
      case .goBack: goBack()
      case .quit: break
      }
    }

    draw()
  }

  private func refreshPeriodically() async {
    let clock = ContinuousClock()
    let tolerance = min(options.refreshInterval / 20, Self.maximumRefreshTolerance)
    var deadline = clock.now + min(options.refreshInterval, Self.maximumInitialRefreshDelay)

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
    var snapshot = await sampler.sample()

    if options.showsApplicationsOnly {
      snapshot.owners.removeAll { $0.owner.kind != .application }
    }

    let now = ContinuousClock.now
    let isReSortDue = lastReSortInstant.map { now - $0 >= minimumReSortInterval } ?? true

    ownerOrdering.arrange(&snapshot.owners, sortedBy: options.sortColumn, shouldReSort: isReSortDue)

    if isReSortDue {
      self.lastReSortInstant = now
    }

    self.latestSnapshot = snapshot
    self.summaryLines = ResourceUsageTableRenderer.summaryLines(for: snapshot)

    updateTable()
    draw()
  }

  private func moveSelection(to destination: TableSelection.Destination) {
    guard let table else {
      return
    }

    let visibleRowCount = ResourceUsageTableRenderer.visibleRowCount(
      for: table,
      summaryLineCount: summaryLines.count,
      size: terminalSession.size
    )

    tableSelection.move(to: destination, in: table.rows, visibleRowCount: visibleRowCount)
  }

  private func openSelection() {
    guard
      case .processOwners = screen,
      case .owner(let selectedOwnerID) = tableSelection.selectedRowID,
      let selectedOwnerResourceUsage = latestSnapshot?.owners.first(where: { $0.id == selectedOwnerID })
    else {
      return
    }

    self.processOwnersSelection = tableSelection
    self.tableSelection = TableSelection()
    self.screen = .processTree(owner: selectedOwnerResourceUsage.owner)

    updateTable()
  }

  private func goBack() {
    if tableSelection.selectedRowID != nil {
      self.tableSelection.clear()
    } else if case .processTree = screen {
      showProcessOwners()
    }
  }

  private func showProcessOwners() {
    self.screen = .processOwners
    self.tableSelection = processOwnersSelection

    updateTable()
  }

  private func updateTable() {
    guard let latestSnapshot else {
      return
    }

    switch screen {
    case .processOwners:
      self.table = ResourceUsageTable(
        nameColumnTitle: ResourceUsageColumn.name.title,
        sortColumn: options.sortColumn,
        caption: nil,
        rows: latestSnapshot.owners.map(ResourceUsageTableRow.init(ownerResourceUsage:)),
        totalUsage: nil
      )

    case .processTree(let owner):
      let ownedProcesses = latestSnapshot.processes.filter { $0.metadata.owner.id == owner.id }

      guard !ownedProcesses.isEmpty else {
        showProcessOwners()
        return
      }

      let rows = ProcessTree.rows(for: ownedProcesses, ownedBy: owner)
      let processCountDescription = "\(rows.count) \(rows.count == 1 ? "process" : "processes")"
      let formattedOwnerName = TextEmphasis.bold.applied(to: owner.name)
      let formattedNavigationHint = TextEmphasis.deemphasized.applied(to: "(esc to go back)")

      self.table = ResourceUsageTable(
        nameColumnTitle: "PROCESS",
        sortColumn: nil,
        caption: "\(formattedOwnerName)  \(processCountDescription)  \(formattedNavigationHint)",
        rows: rows,
        totalUsage: latestSnapshot.owners.first { $0.id == owner.id }?.usage
      )
    }
  }

  private func draw() {
    guard let table else {
      return
    }

    let size = terminalSession.size
    let visibleRowCount = ResourceUsageTableRenderer.visibleRowCount(
      for: table,
      summaryLineCount: summaryLines.count,
      size: size
    )

    tableSelection.reconcile(with: table.rows, visibleRowCount: visibleRowCount)
    terminalSession.draw(
      ResourceUsageTableRenderer.frame(summaryLines: summaryLines, table: table, selection: tableSelection, size: size)
    )
  }

  private func suspend() {
    terminalSession.deactivate()
    kill(getpid(), SIGSTOP)
    terminalSession.activate()
    draw()
  }
}

let options = ResourceUsageMonitor.Options(arguments: CommandLine.arguments.dropFirst())

do {
  let resourceUsageMonitor = try ResourceUsageMonitor(options: options)
  await resourceUsageMonitor.run()
} catch {
  Log.error("Error: \(error.localizedDescription)")
  exit(EXIT_FAILURE)
}

exit(EXIT_SUCCESS)
