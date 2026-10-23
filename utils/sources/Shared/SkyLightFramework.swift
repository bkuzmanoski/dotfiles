// Shared: PrivateFramework Spaces

import AppKit

struct SLSWindowTags: OptionSet {
  let rawValue: UInt64

  static let document = SLSWindowTags(rawValue: 1 << 0)
  static let floating = SLSWindowTags(rawValue: 1 << 1)
  static let modal = SLSWindowTags(rawValue: 1 << 31)
}

struct SLSSpaceMask: OptionSet {
  let rawValue: CInt

  static let includesCurrent = SLSSpaceMask(rawValue: 1 << 0)
  static let includesOthers = SLSSpaceMask(rawValue: 1 << 1)
  static let includesUser = SLSSpaceMask(rawValue: 1 << 2)
  static let visible = SLSSpaceMask(rawValue: 1 << 16)

  static let currentSpace: SLSSpaceMask = [.includesUser, .includesCurrent]
  static let otherSpaces: SLSSpaceMask = [.includesOthers, .includesCurrent]
  static let allSpaces: SLSSpaceMask = [.includesUser, .includesOthers, .includesCurrent]
  static let allVisibleSpaces: SLSSpaceMask = [.visible, .allSpaces]
}

enum SLSEventType: UInt32 {
  case packagesStatusBarSpaceChanged = 1308
  case spaceWindowCreated = 1325
  case spaceWindowDestroyed = 1326
  case spaceCreated = 1327
  case spaceDestroyed = 1328
  case spaceCurrentChanged = 1329
}

struct CPSSetFrontProcessOptions: OptionSet {
  let rawValue: UInt32

  static let allWindows = CPSSetFrontProcessOptions(rawValue: 0x100)
  static let userGenerated = CPSSetFrontProcessOptions(rawValue: 0x200)
  static let noWindows = CPSSetFrontProcessOptions(rawValue: 0x400)
}

struct SLPSEventRecord {
  private static let size = 0xf8

  private enum Offset {
    static let recordLength = 0x04
    static let eventType = 0x08
    static let mask = 0x20
    static let activationFlag = 0x3a
    static let windowID = 0x3c
    static let focusTransitionType = 0x8a
  }

  enum EventType: UInt8 {
    case leftMouseDown = 0x01
    case leftMouseUp = 0x02
    case focusTransition = 0x0d
  }

  enum SimulatedClickType {
    case leftMouseDown
    case leftMouseUp

    var eventType: EventType {
      switch self {
      case .leftMouseDown: .leftMouseDown
      case .leftMouseUp: .leftMouseUp
      }
    }
  }

  enum FocusTransitionType: UInt8 {
    case becomeKey = 0x01
    case resignKey = 0x02

    var eventType: EventType { .focusTransition }
  }

  var bytes: [UInt8]

  private init() {
    self.bytes = [UInt8](repeating: 0, count: Self.size)
    self.bytes[Offset.recordLength] = UInt8(Self.size)
  }

  static func focusTransition(windowID: CGWindowID, type: FocusTransitionType) -> SLPSEventRecord {
    var eventRecord = SLPSEventRecord()
    eventRecord.bytes[Offset.eventType] = type.eventType.rawValue
    eventRecord.bytes[Offset.focusTransitionType] = type.rawValue
    eventRecord.setWindowID(windowID)

    return eventRecord
  }

  static func simulatedClick(windowID: CGWindowID, type: SimulatedClickType) -> SLPSEventRecord {
    var eventRecord = SLPSEventRecord()
    eventRecord.bytes[Offset.eventType] = type.eventType.rawValue

    for index in 0..<0x10 {
      eventRecord.bytes[Offset.mask + index] = 0xff
    }

    eventRecord.bytes[Offset.activationFlag] = 0x10
    eventRecord.setWindowID(windowID)

    return eventRecord
  }

  private mutating func setWindowID(_ windowID: CGWindowID) {
    var windowID = windowID

    withUnsafeBytes(of: &windowID) { idBytes in
      for index in 0..<4 {
        self.bytes[Offset.windowID + index] = idBytes[index]
      }
    }
  }
}

struct SkyLightFramework {
  typealias NotifyProc =
    @convention(c) (
      _ eventType: UInt32,
      _ data: UnsafeMutableRawPointer?,
      _ dataLength: UInt32,
      _ context: UnsafeMutableRawPointer?
    ) -> Void

  private typealias SLSConnectionID = UInt32
  private typealias SLSMainConnectionID = @convention(c) () -> SLSConnectionID
  private typealias SLSConnectionGetPID =
    @convention(c) (
      _ connectionID: SLSConnectionID,
      _ outPID: UnsafeMutablePointer<pid_t>
    ) -> CGError
  private typealias SLSFindWindowByGeometry =
    @convention(c) (
      _ connectionID: SLSConnectionID,
      _ filterWindowID: CGWindowID,
      _ flags: Int32,
      _ reserved: Int32,
      _ screenPoint: UnsafePointer<CGPoint>,
      _ outWindowPoint: UnsafeMutablePointer<CGPoint>,
      _ outWindowID: UnsafeMutablePointer<CGWindowID>,
      _ outWindowConnectionID: UnsafeMutablePointer<SLSConnectionID>
    ) -> CGError
  private typealias SLSGetWindowLevel =
    @convention(c) (
      _ connectionID: SLSConnectionID,
      _ windowID: CGWindowID,
      _ outLevel: UnsafeMutablePointer<CGWindowLevel>
    ) -> CGError
  private typealias SLSCopyAssociatedWindows =
    @convention(c) (
      _ connectionID: SLSConnectionID,
      _ windowID: CGWindowID
    ) -> Unmanaged<CFArray>?
  private typealias SLSWindowQueryWindows =
    @convention(c) (
      _ connectionID: SLSConnectionID,
      _ windowIDs: CFArray,
      _ windowCount: CInt
    ) -> Unmanaged<CFTypeRef>?
  private typealias SLSWindowQueryResultCopyWindows = @convention(c) (_ query: CFTypeRef) -> Unmanaged<CFTypeRef>?
  private typealias SLSWindowIteratorAdvance = @convention(c) (_ iterator: CFTypeRef) -> Bool
  private typealias SLSWindowIteratorGetWindowID = @convention(c) (_ iterator: CFTypeRef) -> CGWindowID
  private typealias SLSWindowIteratorGetTags = @convention(c) (_ iterator: CFTypeRef) -> UInt64
  private typealias SLSCopyManagedDisplaySpaces =
    @convention(c) (
      _ connectionID: SLSConnectionID,
      _ displayIdentifier: CFString?
    ) -> Unmanaged<CFArray>?
  private typealias SLSCopySpacesForWindows =
    @convention(c) (
      _ connectionID: SLSConnectionID,
      _ spaceMask: CInt,
      _ windowIDs: CFArray
    ) -> Unmanaged<CFArray>?
  private typealias SLSRegisterNotifyProc =
    @convention(c) (
      _ proc: NotifyProc,
      _ eventType: UInt32,
      _ context: UnsafeMutableRawPointer?
    ) -> CGError
  private typealias SLSRemoveNotifyProc =
    @convention(c) (
      _ proc: NotifyProc,
      _ eventType: UInt32,
      _ context: UnsafeMutableRawPointer?
    ) -> CGError
  // swift-format-ignore: NoLeadingUnderscores
  private typealias _SLPSGetFrontProcess = @convention(c) (_ psn: UnsafeMutableRawPointer) -> CGError
  // swift-format-ignore: NoLeadingUnderscores
  private typealias _SLPSSetFrontProcessWithOptions =
    @convention(c) (
      _ psn: UnsafeMutableRawPointer,
      _ windowID: CGWindowID,
      _ options: CPSSetFrontProcessOptions.RawValue
    ) -> CGError
  private typealias SLPSPostEventRecordTo =
    @convention(c) (
      _ psn: UnsafeMutableRawPointer,
      _ bytes: UnsafeMutablePointer<UInt8>
    ) -> CGError

  private let mainConnectionID: SLSConnectionID
  private let slsConnectionGetPID: SLSConnectionGetPID
  private let slsFindWindowByGeometry: SLSFindWindowByGeometry
  private let slsGetWindowLevel: SLSGetWindowLevel
  private let slsCopyAssociatedWindows: SLSCopyAssociatedWindows
  private let slsWindowQueryWindows: SLSWindowQueryWindows
  private let slsWindowQueryResultCopyWindows: SLSWindowQueryResultCopyWindows
  private let slsWindowIteratorAdvance: SLSWindowIteratorAdvance
  private let slsWindowIteratorGetWindowID: SLSWindowIteratorGetWindowID
  private let slsWindowIteratorGetTags: SLSWindowIteratorGetTags
  private let slsCopyManagedDisplaySpaces: SLSCopyManagedDisplaySpaces
  private let slsCopySpacesForWindows: SLSCopySpacesForWindows
  private let slsRegisterNotifyProc: SLSRegisterNotifyProc
  private let slsRemoveNotifyProc: SLSRemoveNotifyProc
  // swift-format-ignore: NoLeadingUnderscores
  private let _slpsGetFrontProcess: _SLPSGetFrontProcess
  // swift-format-ignore: NoLeadingUnderscores
  private let _slpsSetFrontProcessWithOptions: _SLPSSetFrontProcessWithOptions
  private let slpsPostEventRecordTo: SLPSPostEventRecordTo

  var frontProcess: ProcessSerialNumber? {
    var processSerialNumber = ProcessSerialNumber()
    return _slpsGetFrontProcess(&processSerialNumber) == .success ? processSerialNumber : nil
  }

  init() throws {
    let framework = try PrivateFramework(named: "SkyLight")
    let slsMainConnectionID: SLSMainConnectionID = try framework.symbol(named: "SLSMainConnectionID")

    self.mainConnectionID = slsMainConnectionID()
    self.slsConnectionGetPID = try framework.symbol(named: "SLSConnectionGetPID")
    self.slsFindWindowByGeometry = try framework.symbol(named: "SLSFindWindowByGeometry")
    self.slsGetWindowLevel = try framework.symbol(named: "SLSGetWindowLevel")
    self.slsCopyAssociatedWindows = try framework.symbol(named: "SLSCopyAssociatedWindows")
    self.slsWindowQueryWindows = try framework.symbol(named: "SLSWindowQueryWindows")
    self.slsWindowQueryResultCopyWindows = try framework.symbol(named: "SLSWindowQueryResultCopyWindows")
    self.slsWindowIteratorAdvance = try framework.symbol(named: "SLSWindowIteratorAdvance")
    self.slsWindowIteratorGetWindowID = try framework.symbol(named: "SLSWindowIteratorGetWindowID")
    self.slsWindowIteratorGetTags = try framework.symbol(named: "SLSWindowIteratorGetTags")
    self.slsCopyManagedDisplaySpaces = try framework.symbol(named: "SLSCopyManagedDisplaySpaces")
    self.slsCopySpacesForWindows = try framework.symbol(named: "SLSCopySpacesForWindows")
    self.slsRegisterNotifyProc = try framework.symbol(named: "SLSRegisterNotifyProc")
    self.slsRemoveNotifyProc = try framework.symbol(named: "SLSRemoveNotifyProc")
    self._slpsGetFrontProcess = try framework.symbol(named: "_SLPSGetFrontProcess")
    self._slpsSetFrontProcessWithOptions = try framework.symbol(named: "_SLPSSetFrontProcessWithOptions")
    self.slpsPostEventRecordTo = try framework.symbol(named: "SLPSPostEventRecordTo")
  }

  func findWindow(at point: CGPoint) -> (windowID: CGWindowID, ownerPID: pid_t)? {
    var screenPoint = point
    var windowPoint = CGPoint.zero
    var windowID: CGWindowID = 0
    var windowConnectionID: SLSConnectionID = 0
    var ownerPID: pid_t = 0

    return
      slsFindWindowByGeometry(
        mainConnectionID,
        0,
        1,
        0,
        &screenPoint,
        &windowPoint,
        &windowID,
        &windowConnectionID
      ) == .success
      && windowID != 0
      && slsConnectionGetPID(windowConnectionID, &ownerPID) == .success
      ? (windowID, ownerPID)
      : nil
  }

  func windowLevel(for windowID: CGWindowID) -> CGWindowLevel? {
    var level: CGWindowLevel = 0
    return slsGetWindowLevel(mainConnectionID, windowID, &level) == .success ? level : nil
  }

  func associatedWindows(for windowID: CGWindowID) -> [CGWindowID] {
    guard
      let windowIDs = slsCopyAssociatedWindows(mainConnectionID, windowID)?.takeRetainedValue() as? [CGWindowID]
    else {
      return []
    }

    return windowIDs.filter { $0 != windowID }
  }

  func windowTags(for windowIDs: [CGWindowID]) -> [CGWindowID: SLSWindowTags] {
    guard
      !windowIDs.isEmpty,
      let query = slsWindowQueryWindows(
        mainConnectionID,
        windowIDs as CFArray,
        CInt(windowIDs.count)
      )?.takeRetainedValue(),
      let iterator = slsWindowQueryResultCopyWindows(query)?.takeRetainedValue()
    else {
      return [:]
    }

    var tagsByWindowID: [CGWindowID: SLSWindowTags] = [:]

    while slsWindowIteratorAdvance(iterator) {
      let windowID = slsWindowIteratorGetWindowID(iterator)
      tagsByWindowID[windowID] = SLSWindowTags(rawValue: slsWindowIteratorGetTags(iterator))
    }

    return tagsByWindowID
  }

  func displaySpaces(forDisplay displayIdentifier: DisplayIdentifier? = nil) -> [DisplaySpaces] {
    guard
      let managedDisplaySpaces = slsCopyManagedDisplaySpaces(
        mainConnectionID,
        displayIdentifier as CFString?
      )?.takeRetainedValue() as? [[String: Any]]
    else {
      return []
    }

    return managedDisplaySpaces.compactMap { displayInfo in
      guard
        let displayIdentifier = displayInfo["Display Identifier"] as? DisplayIdentifier,
        let spacesInfo = displayInfo["Spaces"] as? [[String: Any]]
      else {
        return nil
      }

      let currentSpaceInfo = displayInfo["Current Space"] as? [String: Any]

      return DisplaySpaces(
        displayIdentifier: displayIdentifier,
        spaceIDs: spacesInfo.compactMap { $0["id64"] as? SpaceID },
        currentSpaceID: currentSpaceInfo?["id64"] as? SpaceID
      )
    }
  }

  func displaySpaces(for screen: NSScreen) -> DisplaySpaces? {
    guard let displayIdentifier = screen.displayIdentifier else {
      return nil
    }

    return displaySpaces(forDisplay: displayIdentifier).first { $0.displayIdentifier == displayIdentifier }
  }

  func spaceIDs(forWindow windowID: CGWindowID, mask: SLSSpaceMask) -> [SpaceID]? {
    return slsCopySpacesForWindows(
      mainConnectionID,
      mask.rawValue,
      [windowID] as CFArray
    )?.takeRetainedValue() as? [SpaceID]
  }

  @discardableResult
  func registerNotifyProc(
    _ notifyProc: NotifyProc,
    for eventType: SLSEventType,
    context: UnsafeMutableRawPointer?
  ) -> CGError {
    return slsRegisterNotifyProc(notifyProc, eventType.rawValue, context)
  }

  @discardableResult
  func removeNotifyProc(
    _ notifyProc: NotifyProc,
    for eventType: SLSEventType,
    context: UnsafeMutableRawPointer?
  ) -> CGError {
    return slsRemoveNotifyProc(notifyProc, eventType.rawValue, context)
  }

  @discardableResult
  func setFrontProcess(
    _ processSerialNumber: ProcessSerialNumber,
    windowID: CGWindowID,
    options: CPSSetFrontProcessOptions
  ) -> CGError {
    var processSerialNumber = processSerialNumber
    return _slpsSetFrontProcessWithOptions(&processSerialNumber, windowID, options.rawValue)
  }

  @discardableResult
  func postEvent(_ eventRecord: SLPSEventRecord, to processSerialNumber: ProcessSerialNumber) -> CGError {
    var eventRecord = eventRecord
    var processSerialNumber = processSerialNumber

    return eventRecord.bytes.withUnsafeMutableBufferPointer { buffer in
      slpsPostEventRecordTo(&processSerialNumber, buffer.baseAddress!)
    }
  }
}
