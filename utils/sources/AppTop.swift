import Foundation
import IOKit
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

enum ANSIEscapeSequence {
  static let enterAlternateScreen = "\u{1B}[?1049h"
  static let exitAlternateScreen = "\u{1B}[?1049l"
  static let hideCursor = "\u{1B}[?25l"
  static let showCursor = "\u{1B}[?25h"
  static let disableLineWrapping = "\u{1B}[?7l"
  static let enableLineWrapping = "\u{1B}[?7h"
  static let beginSynchronizedUpdate = "\u{1B}[?2026h"
  static let endSynchronizedUpdate = "\u{1B}[?2026l"
  static let moveCursorToHome = "\u{1B}[H"
  static let clearLine = "\u{1B}[2K"
  static let clearToEndOfScreen = "\u{1B}[J"
  static let bold = "\u{1B}[1m"
  static let faint = "\u{1B}[2m"
  static let normalIntensity = "\u{1B}[22m"
  static let underline = "\u{1B}[4m"
  static let noUnderline = "\u{1B}[24m"
  static let resetAttributes = "\u{1B}[0m"
}

enum TextEmphasis {
  case bold
  case underline
  case deemphasized

  func applied(to text: String) -> String {
    switch self {
    case .bold: ANSIEscapeSequence.bold + text + ANSIEscapeSequence.normalIntensity
    case .underline: ANSIEscapeSequence.underline + text + ANSIEscapeSequence.noUnderline
    case .deemphasized: ANSIEscapeSequence.faint + text + ANSIEscapeSequence.normalIntensity
    }
  }
}

extension Substring {
  func trimmingTrailingSpaces() -> Substring {
    var trimmedText = self

    while trimmedText.last == " " {
      trimmedText.removeLast()
    }

    return trimmedText
  }
}

extension String {
  private enum EscapeSequenceParsingState {
    case text
    case escapeSequence
    case controlSequence
  }

  var visibleCharacterCount: Int {
    guard utf8.contains(0x1B) else {
      return count
    }

    var characterCount = 0

    forEachVisibleCharacterIndex { _ in
      characterCount += 1
      return true
    }

    return characterCount
  }

  func truncated(toVisibleWidth width: Int) -> String? {
    guard width > 0, utf8.count > width else {
      return nil
    }

    var characterCount = 0
    var ellipsisIndex = startIndex

    forEachVisibleCharacterIndex { index in
      characterCount += 1

      if characterCount == width {
        ellipsisIndex = index
      }

      return characterCount <= width
    }

    guard characterCount > width else {
      return nil
    }

    let truncatedText = self[..<ellipsisIndex]
    let endsWithWhitespace = truncatedText.last == " "

    return String(truncatedText.trimmingTrailingSpaces()) + (endsWithWhitespace ? " …" : "…")
  }

  private func forEachVisibleCharacterIndex(_ body: (Index) -> Bool) {
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

        guard body(index) else {
          return
        }
      }
    }
  }
}

extension UnsignedInteger {
  func increment(since earlierValue: Self) -> Self {
    return self > earlierValue ? self - earlierValue : 0
  }
}

extension DispatchTimeInterval {
  init(_ duration: Duration) {
    let (seconds, attoseconds) = duration.components
    self = .nanoseconds(Int(seconds) * 1_000_000_000 + Int(attoseconds / 1_000_000_000))
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
}

extension FilePath {
  var applicationBundleName: String? {
    let trailingComponents = Array(components.suffix(4))

    guard
      trailingComponents.count == 4,
      trailingComponents[0].extension == "app",
      trailingComponents[1] == "Contents",
      trailingComponents[2] == "MacOS"
    else {
      return nil
    }

    return trailingComponents[0].string
  }
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
    let paddedFractionDigits = String(repeating: "0", count: fractionLength - fractionDigits.count) + fractionDigits

    return "\(scaledValue / multiplier).\(paddedFractionDigits)"
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

    while value >= 999.95, unitIndex < Self.units.count - 1 {
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
  var inbound: UInt64 = 0
  var outbound: UInt64 = 0

  static func += (lhs: inout TransferByteCounts, rhs: TransferByteCounts) {
    lhs.inbound += rhs.inbound
    lhs.outbound += rhs.outbound
  }

  func increment(since earlierByteCounts: TransferByteCounts) -> TransferByteCounts {
    return TransferByteCounts(
      inbound: inbound.increment(since: earlierByteCounts.inbound),
      outbound: outbound.increment(since: earlierByteCounts.outbound)
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
}

extension TransferRates {
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

extension host_cpu_load_info {
  var userTicks: UInt32 { cpu_ticks.0 &+ cpu_ticks.3 }
  var systemTicks: UInt32 { cpu_ticks.1 }
  var idleTicks: UInt32 { cpu_ticks.2 }
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
  let oneMinute: Double
  let fiveMinutes: Double
  let fifteenMinutes: Double

  static var current: LoadAverages {
    return withUnsafeTemporaryAllocation(of: Double.self, capacity: 3) { loadAverages in
      guard let baseAddress = loadAverages.baseAddress, getloadavg(baseAddress, 3) == 3 else {
        return LoadAverages(oneMinute: 0, fiveMinutes: 0, fifteenMinutes: 0)
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

    let applicationPageCount = UInt64(statistics.internal_page_count).increment(
      since: UInt64(statistics.purgeable_count)
    )
    let wiredBytes = UInt64(statistics.wire_count) * MachHost.pageSize
    let compressedBytes = UInt64(statistics.compressor_page_count) * MachHost.pageSize

    return MemoryUsage(
      usedBytes: applicationPageCount * MachHost.pageSize + wiredBytes + compressedBytes,
      wiredBytes: wiredBytes,
      compressedBytes: compressedBytes,
      totalBytes: totalBytes
    )
  }
}

enum BlockStorageStatistics {
  static func cumulativeByteCounts() -> TransferByteCounts {
    var iterator: io_iterator_t = 0

    guard
      IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator)
        == KERN_SUCCESS
    else {
      return TransferByteCounts()
    }

    defer {
      IOObjectRelease(iterator)
    }

    var byteCounts = TransferByteCounts()

    while case let service = IOIteratorNext(iterator), service != 0 {
      defer {
        IOObjectRelease(service)
      }

      guard
        let statistics = IORegistryEntryCreateCFProperty(
          service,
          "Statistics" as CFString,
          kCFAllocatorDefault,
          0
        )?.takeRetainedValue(),
        CFGetTypeID(statistics) == CFDictionaryGetTypeID()
      else {
        continue
      }

      let statisticsDictionary = unsafeDowncast(statistics, to: CFDictionary.self)

      byteCounts += TransferByteCounts(
        inbound: UInt64(clamping: statisticsDictionary.int64Value(forKey: "Bytes (Read)" as CFString) ?? 0),
        outbound: UInt64(clamping: statisticsDictionary.int64Value(forKey: "Bytes (Write)" as CFString) ?? 0)
      )
    }

    return byteCounts
  }
}

struct NetworkInterfaceStatistics {
  private struct InterfaceByteCounters {
    let inbound: UInt32
    let outbound: UInt32

    func increment(since earlierCounters: InterfaceByteCounters) -> TransferByteCounts {
      return TransferByteCounts(
        inbound: UInt64(inbound &- earlierCounters.inbound),
        outbound: UInt64(outbound &- earlierCounters.outbound)
      )
    }
  }

  private var interfaceListBuffer = [UInt8](repeating: 0, count: 4096)
  private var previousInterfaceByteCounters: [UInt16: InterfaceByteCounters] = [:]

  mutating func byteCountsSinceLastSample() -> TransferByteCounts {
    guard let interfaceListLength = readInterfaceList() else {
      return TransferByteCounts()
    }

    let interfaceListBuffer = interfaceListBuffer

    var byteCounts = TransferByteCounts()

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
            let interfaceByteCounters = InterfaceByteCounters(
              inbound: UInt32(truncatingIfNeeded: interfaceMessage.ifm_data.ifi_ibytes),
              outbound: UInt32(truncatingIfNeeded: interfaceMessage.ifm_data.ifi_obytes)
            )

            if let previousByteCounters = previousInterfaceByteCounters[interfaceMessage.ifm_index] {
              byteCounts += interfaceByteCounters.increment(since: previousByteCounters)
            }

            previousInterfaceByteCounters[interfaceMessage.ifm_index] = interfaceByteCounters
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
}

struct SystemResourceUsage {
  let cpu: CPUUsage
  let loadAverages: LoadAverages
  let memory: MemoryUsage
  let disk: TransferRates
  let network: TransferRates
}

struct SystemResourceSampler {
  private var networkInterfaceStatistics = NetworkInterfaceStatistics()
  private var previousCPULoadInfo: host_cpu_load_info?
  private var previousDiskByteCounts: TransferByteCounts?

  mutating func sample(elapsedSeconds: Double) -> SystemResourceUsage {
    let cpuLoadInfo = MachHost.cpuLoadInfo()
    let diskByteCounts = BlockStorageStatistics.cumulativeByteCounts()
    let networkByteCounts = networkInterfaceStatistics.byteCountsSinceLastSample()
    let cpuUsage: CPUUsage

    if let cpuLoadInfo, let previousCPULoadInfo {
      cpuUsage = CPUUsage(loadInfo: cpuLoadInfo, previousLoadInfo: previousCPULoadInfo)
    } else {
      cpuUsage = .zero
    }

    let diskByteCountIncrement =
      previousDiskByteCounts.map { diskByteCounts.increment(since: $0) } ?? TransferByteCounts()

    self.previousCPULoadInfo = cpuLoadInfo
    self.previousDiskByteCounts = diskByteCounts

    return SystemResourceUsage(
      cpu: cpuUsage,
      loadAverages: .current,
      memory: .current,
      disk: TransferRates(byteCounts: diskByteCountIncrement, elapsedSeconds: elapsedSeconds),
      network: TransferRates(byteCounts: networkByteCounts, elapsedSeconds: elapsedSeconds)
    )
  }
}

struct ProcessResourceUsage {
  let startTime: UInt64
  let cpuTime: UInt64
  let memoryFootprint: UInt64
  let disk: TransferByteCounts
}

struct RunningProcess {
  private typealias ResponsibilityGetPIDResponsibleForPID = @convention(c) (pid_t) -> pid_t

  private static let responsibilityGetPIDResponsibleForPID: ResponsibilityGetPIDResponsibleForPID? = {
    guard
      let responsibilityGetPIDResponsibleForPIDSymbol = dlsym(
        UnsafeMutableRawPointer(bitPattern: -1),
        "responsibility_get_pid_responsible_for_pid"
      )
    else {
      return nil
    }

    return unsafeBitCast(
      responsibilityGetPIDResponsibleForPIDSymbol,
      to: ResponsibilityGetPIDResponsibleForPID.self
    )
  }()

  let processIdentifier: pid_t

  var executablePath: FilePath? {
    return withUnsafeTemporaryAllocation(of: CChar.self, capacity: 4 * Int(MAXPATHLEN)) { buffer in
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
    guard let responsibilityGetPIDResponsibleForPID = Self.responsibilityGetPIDResponsibleForPID else {
      return nil
    }

    let responsibleProcessIdentifier = responsibilityGetPIDResponsibleForPID(processIdentifier)

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

  func resourceUsage() throws(Errno) -> ProcessResourceUsage {
    var resourceUsage = rusage_info_v4()

    let result = withUnsafeMutablePointer(to: &resourceUsage) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPointer in
        proc_pid_rusage(processIdentifier, RUSAGE_INFO_V4, reboundPointer)
      }
    }

    guard result == 0 else {
      throw Errno(rawValue: errno)
    }

    return ProcessResourceUsage(
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
  enum Kind: Hashable {
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

  var id: ID { ID(processIdentifier: processIdentifier, kind: kind) }
}

extension ProcessOwner {
  init?(of process: RunningProcess) {
    let executablePath = process.executablePath

    guard let processName = executablePath?.lastComponent?.string ?? process.commandName else {
      return nil
    }

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

struct NetworkStatisticsFramework: @unchecked Sendable {
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
    var byteCounts = TransferByteCounts()
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
          guard let source else {
            return
          }

          MainActor.assumeIsolated {
            self?.trackFlow(for: source)
          }
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
      let accountedByteCounts =
        flow.accountedByteCounts ?? (hasEstablishedBaseline ? TransferByteCounts() : flow.byteCounts)
      let byteCountIncrement = flow.byteCounts.increment(since: accountedByteCounts)

      if flow.processIdentifier > 0, byteCountIncrement.inbound > 0 || byteCountIncrement.outbound > 0 {
        byteCounts[flow.processIdentifier, default: TransferByteCounts()] += byteCountIncrement
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

      MainActor.assumeIsolated {
        flow.processIdentifier = processIdentifier
      }
    }

    framework.setSourceCountsHandler(source) { counts in
      let byteCounts = TransferByteCounts(
        inbound: UInt64(clamping: counts.int64Value(forKey: framework.receivedBytesKey) ?? 0),
        outbound: UInt64(clamping: counts.int64Value(forKey: framework.sentBytesKey) ?? 0)
      )

      MainActor.assumeIsolated {
        flow.byteCounts = byteCounts
      }
    }

    framework.setSourceRemovedHandler(source) {
      MainActor.assumeIsolated {
        flow.isRemoved = true
      }
    }

    framework.querySourceDescription(source)

    self.flows.append(flow)
  }
}

struct ResourceUsageEntry: Identifiable {
  let owner: ProcessOwner
  let cpuPercentage: Double
  let memoryFootprint: UInt64
  let disk: TransferRates
  let network: TransferRates

  var id: ProcessOwner.ID { owner.id }
}

struct ResourceUsageSnapshot {
  var entries: [ResourceUsageEntry]
  let system: SystemResourceUsage
  let applicationCount: Int
  let processCount: Int
  let restrictedProcessCount: Int
}

struct ResourceUsageAccumulator {
  let owner: ProcessOwner
  var cpuTime: UInt64 = 0
  var memoryFootprint: UInt64 = 0
  var disk = TransferByteCounts()
  var network = TransferByteCounts()

  mutating func addUsage(_ usage: ProcessResourceUsage, since previousUsage: ProcessResourceUsage?) {
    self.cpuTime += usage.cpuTime.increment(since: previousUsage?.cpuTime ?? 0)
    self.memoryFootprint += usage.memoryFootprint
    self.disk += usage.disk.increment(since: previousUsage?.disk ?? TransferByteCounts())
  }

  func entry(overElapsedAbsoluteTime elapsedAbsoluteTime: UInt64) -> ResourceUsageEntry {
    let elapsedSeconds = MachAbsoluteTime.seconds(from: elapsedAbsoluteTime)
    return ResourceUsageEntry(
      owner: owner,
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
    let owner: ProcessOwner
    let usage: ProcessResourceUsage
    let sampleGeneration: UInt64
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
    let networkByteCounts = await networkStatisticsMonitor.byteCountsSinceLastSample()
    let sampleTime = MachAbsoluteTime.now
    let isBaselineSample = previousSampleTime == nil
    let processIdentifierCount = RunningProcess.listAllProcessIdentifiers(into: &processIdentifierBuffer)
    var accumulators: [ProcessOwner.ID: ResourceUsageAccumulator] = [:]
    var processCount = 0
    var restrictedProcessCount = 0

    accumulators.reserveCapacity(previousOwnerCount)
    self.sampleGeneration &+= 1

    for processIdentifier in processIdentifierBuffer[..<processIdentifierCount] {
      let process = RunningProcess(processIdentifier: processIdentifier)
      let usage: ProcessResourceUsage

      do throws(Errno) {
        usage = try process.resourceUsage()
      } catch {
        if error == .notPermitted {
          restrictedProcessCount += 1
        }

        continue
      }

      let owner: ProcessOwner
      let previousUsage: ProcessResourceUsage?

      if let trackedProcess = trackedProcesses[processIdentifier], trackedProcess.usage.startTime == usage.startTime {
        owner = trackedProcess.owner
        previousUsage = trackedProcess.usage
      } else if let resolvedOwner = ProcessOwner(of: process) {
        owner = resolvedOwner
        previousUsage = isBaselineSample ? usage : nil
      } else {
        continue
      }

      trackedProcesses[processIdentifier] = TrackedProcess(
        owner: owner,
        usage: usage,
        sampleGeneration: sampleGeneration
      )
      accumulators[owner.id, default: ResourceUsageAccumulator(owner: owner)].addUsage(usage, since: previousUsage)
      processCount += 1
    }

    for (processIdentifier, byteCounts) in networkByteCounts {
      guard let owner = trackedProcesses[processIdentifier]?.owner else {
        continue
      }

      accumulators[owner.id, default: ResourceUsageAccumulator(owner: owner)].network += byteCounts
    }

    if trackedProcesses.count != processCount {
      self.trackedProcesses = trackedProcesses.filter { $0.value.sampleGeneration == sampleGeneration }
    }

    let elapsedAbsoluteTime = previousSampleTime.map { sampleTime - $0 } ?? 0
    let entries = accumulators.values.map { $0.entry(overElapsedAbsoluteTime: elapsedAbsoluteTime) }
    let systemResourceUsage = systemResourceSampler.sample(
      elapsedSeconds: MachAbsoluteTime.seconds(from: elapsedAbsoluteTime)
    )

    self.previousSampleTime = sampleTime
    self.previousOwnerCount = accumulators.count

    return ResourceUsageSnapshot(
      entries: entries,
      system: systemResourceUsage,
      applicationCount: entries.count { $0.owner.kind == .application },
      processCount: processCount,
      restrictedProcessCount: restrictedProcessCount
    )
  }
}

enum UsageColumn: String, CaseIterable {
  enum Alignment {
    case leading
    case trailing
  }

  case pid
  case name
  case cpu
  case memory
  case disk
  case network

  private static let transferRateValueWidth = 8
  private static let zeroFormattedValues: Set = [
    Double.zero.formatted(.fixedPoint(fractionLength: 1)),
    Double.zero.formatted(.abbreviatedByteCount)
  ]

  var title: String {
    switch self {
    case .pid: "PID"
    case .name: "NAME"
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

  var alignment: Alignment { self == .name ? .leading : .trailing }

  func formattedValue(for entry: ResourceUsageEntry) -> String {
    switch self {
    case .pid: String(entry.owner.processIdentifier)
    case .name: entry.owner.name
    case .cpu: Self.deemphasizedIfZero(entry.cpuPercentage.formatted(.fixedPoint(fractionLength: 1)))
    case .memory: Self.deemphasizedIfZero(Double(entry.memoryFootprint).formatted(.abbreviatedByteCount))
    case .disk: Self.formattedTransferRates(entry.disk)
    case .network: Self.formattedTransferRates(entry.network)
    }
  }

  func areInIncreasingOrder(_ lhs: ResourceUsageEntry, _ rhs: ResourceUsageEntry) -> Bool {
    switch self {
    case .pid: lhs.owner.processIdentifier < rhs.owner.processIdentifier
    case .name: Self.areInIncreasingOrderByName(lhs, rhs)
    case .cpu: Self.areInDecreasingOrder(lhs.cpuPercentage, rhs.cpuPercentage, lhs, rhs)
    case .memory: Self.areInDecreasingOrder(lhs.memoryFootprint, rhs.memoryFootprint, lhs, rhs)
    case .disk: Self.areInDecreasingOrder(lhs.disk.totalBytesPerSecond, rhs.disk.totalBytesPerSecond, lhs, rhs)
    case .network: Self.areInDecreasingOrder(lhs.network.totalBytesPerSecond, rhs.network.totalBytesPerSecond, lhs, rhs)
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

  private static func formattedTransferRate(_ bytesPerSecond: Double, symbol: String) -> String {
    let formattedValue = bytesPerSecond.formatted(.abbreviatedByteCount)
    let padding = String(repeating: " ", count: max(transferRateValueWidth - formattedValue.count, 0))

    return padding + deemphasizedIfZero(formattedValue, suffix: " \(symbol)")
  }

  private static func deemphasizedIfZero(_ formattedValue: String, suffix: String = "") -> String {
    let text = formattedValue + suffix
    return zeroFormattedValues.contains(formattedValue) ? TextEmphasis.deemphasized.applied(to: text) : text
  }

  private static func areInDecreasingOrder<Value: Comparable>(
    _ lhsValue: Value,
    _ rhsValue: Value,
    _ lhs: ResourceUsageEntry,
    _ rhs: ResourceUsageEntry
  ) -> Bool {
    guard lhsValue == rhsValue else {
      return lhsValue > rhsValue
    }

    return areInIncreasingOrderByName(lhs, rhs)
  }

  private static func areInIncreasingOrderByName(_ lhs: ResourceUsageEntry, _ rhs: ResourceUsageEntry) -> Bool {
    switch lhs.owner.name.localizedStandardCompare(rhs.owner.name) {
    case .orderedAscending: true
    case .orderedDescending: false
    case .orderedSame: lhs.owner.processIdentifier < rhs.owner.processIdentifier
    }
  }
}

struct ResourceUsageEntryOrdering {
  private var entryPositions: [ProcessOwner.ID: Int] = [:]

  mutating func arrange(_ entries: inout [ResourceUsageEntry], sortedBy column: UsageColumn, resorting: Bool) {
    if resorting {
      entries.sort(by: column.areInIncreasingOrder)
    } else {
      entries.sort { lhs, rhs in
        switch (entryPositions[lhs.id], entryPositions[rhs.id]) {
        case (let lhsPosition?, let rhsPosition?): lhsPosition < rhsPosition
        case (.some, .none): true
        case (.none, .some): false
        case (.none, .none): column.areInIncreasingOrder(lhs, rhs)
        }
      }
    }

    entryPositions.removeAll(keepingCapacity: true)

    for (position, entry) in entries.enumerated() {
      entryPositions[entry.id] = position
    }
  }
}

struct ResourceUsageTableRenderer {
  private struct SummaryField {
    let value: String
    let valueWidth: Int
    let label: String

    init(count: Int, label: String) {
      self.init(value: String(count), valueWidth: 5, label: label)
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
  private static let minimumNameColumnWidth = 8
  private static let fixedColumnsWidth =
    UsageColumn.allCases.compactMap(\.fixedWidth).reduce(0, +)
    + (UsageColumn.allCases.count - 1) * columnSeparator.count

  let sortColumn: UsageColumn

  func frame(for snapshot: ResourceUsageSnapshot, size: TerminalSession.Size) -> String {
    let nameColumnWidth = max(size.columns - Self.fixedColumnsWidth, Self.minimumNameColumnWidth)

    var lines = summaryLines(for: snapshot)

    lines.append("")
    lines.append(headerLine(nameColumnWidth: nameColumnWidth))

    for entry in snapshot.entries.prefix(max(size.rows - lines.count, 0)) {
      lines.append(row(for: entry, nameColumnWidth: nameColumnWidth))
    }

    let visibleLines = lines.prefix(size.rows)

    var frame =
      ANSIEscapeSequence.beginSynchronizedUpdate
      + ANSIEscapeSequence.moveCursorToHome
      + ANSIEscapeSequence.clearLine
      + visibleLines
      .map { fitted($0, toWidth: size.columns) }
      .joined(separator: "\n" + ANSIEscapeSequence.clearLine)

    if visibleLines.count < size.rows {
      frame += "\n" + ANSIEscapeSequence.clearToEndOfScreen
    }

    return frame + ANSIEscapeSequence.endSynchronizedUpdate
  }

  private func summaryLines(for snapshot: ResourceUsageSnapshot) -> [String] {
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
      let joinedFormattedFields = formattedFields.joined(separator: Self.columnSeparator)
      let formattedTrailingNote = row.trailingNote.map { Self.columnSeparator + $0 } ?? ""

      return "\(formattedTitle)\(Self.columnSeparator)\(joinedFormattedFields)\(formattedTrailingNote)"
    }
  }

  private func summaryRows(for snapshot: ResourceUsageSnapshot) -> [SummaryRow] {
    let system = snapshot.system

    var processFields = [
      SummaryField(count: snapshot.processCount, label: "accessible"),
      SummaryField(count: snapshot.applicationCount, label: "applications")
    ]

    if snapshot.restrictedProcessCount > 0 {
      processFields.append(SummaryField(count: snapshot.restrictedProcessCount, label: "restricted"))
    }

    return [
      SummaryRow(
        title: "Processes",
        fields: processFields,
        trailingNote: snapshot.restrictedProcessCount > 0 ? "(run with sudo to include)" : nil
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
          SummaryField(byteCount: system.memory.compressedBytes, label: "compressed"),
          SummaryField(byteCount: system.memory.totalBytes, label: "total"),
          SummaryField(byteCount: system.memory.wiredBytes, label: "wired")
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

  private func headerLine(nameColumnWidth: Int) -> String {
    let cells = UsageColumn.allCases.map { column in
      cell(
        column.title,
        width: column.fixedWidth ?? nameColumnWidth,
        alignment: column.alignment,
        emphasis: column == sortColumn ? .underline : nil
      )
    }

    return ANSIEscapeSequence.bold + cells.joined(separator: Self.columnSeparator) + ANSIEscapeSequence.resetAttributes
  }

  private func transferRateFields(
    for transferRates: TransferRates,
    inboundLabel: String,
    outboundLabel: String
  ) -> [SummaryField] {
    return [
      SummaryField(
        bytesPerSecond: transferRates.inboundBytesPerSecond,
        label: "\(TransferRates.inboundSymbol) \(inboundLabel)"
      ),
      SummaryField(
        bytesPerSecond: transferRates.outboundBytesPerSecond,
        label: "\(TransferRates.outboundSymbol) \(outboundLabel)"
      )
    ]
  }

  private func row(for entry: ResourceUsageEntry, nameColumnWidth: Int) -> String {
    return UsageColumn.allCases.map { column in
      cell(
        column.formattedValue(for: entry),
        width: column.fixedWidth ?? nameColumnWidth,
        alignment: column.alignment
      )
    }
    .joined(separator: Self.columnSeparator)
  }

  private func cell(
    _ text: String,
    width: Int,
    alignment: UsageColumn.Alignment,
    emphasis: TextEmphasis? = nil
  ) -> String {
    let visibleText = text.truncated(toVisibleWidth: width) ?? text
    let padding = String(repeating: " ", count: max(width - visibleText.visibleCharacterCount, 0))
    let styledText = emphasis?.applied(to: visibleText) ?? visibleText

    switch alignment {
    case .leading: return styledText + padding
    case .trailing: return padding + styledText
    }
  }

  private func fitted(_ line: String, toWidth width: Int) -> String {
    guard let truncatedLine = line.truncated(toVisibleWidth: width) else {
      return line
    }

    return truncatedLine + ANSIEscapeSequence.resetAttributes
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

    attributes.c_lflag &= ~tcflag_t(ICANON | ECHO)

    tcsetattr(FileDescriptor.standardInput.rawValue, TCSANOW, &attributes)
    write(
      ANSIEscapeSequence.enterAlternateScreen
        + ANSIEscapeSequence.hideCursor
        + ANSIEscapeSequence.disableLineWrapping
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
      ANSIEscapeSequence.enableLineWrapping
        + ANSIEscapeSequence.showCursor
        + ANSIEscapeSequence.exitAlternateScreen
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

enum MonitorEvent {
  case refresh
  case redraw
  case suspend
  case quit

  static func stream(refreshInterval: Duration, initialRefreshDelay: Duration) -> AsyncStream<MonitorEvent> {
    let (stream, continuation) = AsyncStream.makeStream(of: MonitorEvent.self)
    let processSignals = ProcessSignals.stream(for: SIGINT, SIGTERM, SIGHUP, SIGWINCH, SIGTSTP)
    let refreshTimerSource = DispatchSource.makeTimerSource(queue: .main)
    let keyboardInputSource = DispatchSource.makeReadSource(
      fileDescriptor: FileDescriptor.standardInput.rawValue,
      queue: .main
    )

    refreshTimerSource.setEventHandler {
      continuation.yield(.refresh)
    }

    refreshTimerSource.schedule(
      deadline: .now() + DispatchTimeInterval(initialRefreshDelay),
      repeating: DispatchTimeInterval(refreshInterval),
      leeway: DispatchTimeInterval(refreshInterval / 20)
    )

    keyboardInputSource.setEventHandler {
      withUnsafeTemporaryAllocation(byteCount: 64, alignment: 1) { buffer in
        guard let byteCount = try? FileDescriptor.standardInput.read(into: buffer) else {
          return
        }

        if byteCount == 0 || buffer.prefix(byteCount).contains(UInt8(ascii: "q")) {
          continuation.yield(.quit)
        }
      }
    }

    let processSignalsTask = Task {
      for await signal in processSignals {
        switch signal {
        case SIGWINCH: continuation.yield(.redraw)
        case SIGTSTP: continuation.yield(.suspend)
        default: continuation.yield(.quit)
        }
      }
    }

    continuation.onTermination = { _ in
      refreshTimerSource.cancel()
      keyboardInputSource.cancel()
      processSignalsTask.cancel()
    }

    refreshTimerSource.resume()
    keyboardInputSource.resume()

    return stream
  }
}

struct MonitorOptions {
  var refreshInterval: Duration = .seconds(1)
  var resortInterval: Duration?
  var sortColumn: UsageColumn = .cpu
  var showsApplicationsOnly = false
}

@MainActor
final class ResourceUsageMonitor {
  private static let maximumInitialRefreshDelay: Duration = .milliseconds(500)

  private let options: MonitorOptions
  private let minimumTimeBetweenResorts: Duration
  private let terminalSession: TerminalSession
  private let sampler: ResourceUsageSampler
  private let renderer: ResourceUsageTableRenderer
  private var entryOrdering = ResourceUsageEntryOrdering()
  private var lastResortInstant: ContinuousClock.Instant?
  private var latestSnapshot: ResourceUsageSnapshot?

  init(options: MonitorOptions) throws {
    self.options = options
    self.minimumTimeBetweenResorts =
      (options.resortInterval ?? options.refreshInterval) - options.refreshInterval / 2
    self.terminalSession = try TerminalSession()
    self.sampler = ResourceUsageSampler(networkStatisticsMonitor: try NetworkStatisticsMonitor())
    self.renderer = ResourceUsageTableRenderer(sortColumn: options.sortColumn)
  }

  func run() async {
    _ = await sampler.sample()

    terminalSession.activate()

    defer {
      terminalSession.deactivate()
    }

    let events = MonitorEvent.stream(
      refreshInterval: options.refreshInterval,
      initialRefreshDelay: min(options.refreshInterval, Self.maximumInitialRefreshDelay)
    )

    for await event in events {
      switch event {
      case .refresh: await refresh()
      case .redraw: draw()
      case .suspend: suspend()
      case .quit: return
      }
    }
  }

  private func refresh() async {
    var snapshot = await sampler.sample()

    if options.showsApplicationsOnly {
      snapshot.entries.removeAll { $0.owner.kind != .application }
    }

    let now = ContinuousClock.now
    let isResortDue = lastResortInstant.map { now - $0 >= minimumTimeBetweenResorts } ?? true

    entryOrdering.arrange(&snapshot.entries, sortedBy: options.sortColumn, resorting: isResortDue)

    if isResortDue {
      self.lastResortInstant = now
    }

    self.latestSnapshot = snapshot

    draw()
  }

  private func draw() {
    guard let latestSnapshot else {
      return
    }

    terminalSession.draw(renderer.frame(for: latestSnapshot, size: terminalSession.size))
  }

  private func suspend() {
    terminalSession.deactivate()
    kill(getpid(), SIGSTOP)
    terminalSession.activate()
    draw()
  }
}

func printUsageErrorAndExit(_ message: String) -> Never {
  Log.error("Error: \(message)\n\n\(usageDescription)")
  exit(EX_USAGE)
}

func duration(fromSecondsValue value: String?, for argument: String) -> Duration {
  guard let value else {
    printUsageErrorAndExit("Missing value for '\(argument)'.")
  }

  guard let seconds = Double(value), seconds.isFinite, seconds > 0 else {
    printUsageErrorAndExit("Invalid value '\(value)' for '\(argument)'. Expected a positive number of seconds.")
  }

  return .seconds(seconds)
}

let sortColumnNames = UsageColumn.allCases.map(\.rawValue).joined(separator: ", ")
let usageDescription = """
  Usage:
    \(ProcessInfo.processInfo.processName) [options]

  Options:
    -i, --interval <seconds>           Set refresh interval in seconds [default: 1]
    -r, --resort-interval <seconds>    Set resort interval in seconds, no less than the refresh interval [default: refresh interval]
    -s, --sort <column>                Set sort column (\(sortColumnNames)) [default: cpu]
    -a, --applications-only            Only show applications
    -h, --help                         Show this help message
  """

var options = MonitorOptions()
var arguments = CommandLine.arguments.dropFirst().makeIterator()

while let argument = arguments.next() {
  switch argument {
  case "-i", "--interval":
    options.refreshInterval = duration(fromSecondsValue: arguments.next(), for: argument)

  case "-r", "--resort-interval":
    options.resortInterval = duration(fromSecondsValue: arguments.next(), for: argument)

  case "-s", "--sort":
    guard let value = arguments.next() else {
      printUsageErrorAndExit("Missing value for '\(argument)'.")
    }

    guard let column = UsageColumn(rawValue: value.lowercased()) else {
      printUsageErrorAndExit("Invalid sort column '\(value)'. Expected one of: \(sortColumnNames).")
    }

    options.sortColumn = column

  case "-a", "--applications-only":
    options.showsApplicationsOnly = true

  case "-h", "--help":
    print(usageDescription)
    exit(EXIT_SUCCESS)

  default:
    printUsageErrorAndExit("Unknown argument: \(argument)")
  }
}

if let resortInterval = options.resortInterval, resortInterval < options.refreshInterval {
  printUsageErrorAndExit("Resort interval must be no less than the refresh interval.")
}

do {
  let resourceUsageMonitor = try ResourceUsageMonitor(options: options)
  await resourceUsageMonitor.run()
} catch {
  Log.error("Error: \(error.localizedDescription)")
  exit(EXIT_FAILURE)
}

exit(EXIT_SUCCESS)
