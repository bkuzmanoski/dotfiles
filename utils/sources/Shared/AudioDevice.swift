// Shared: Log OSStatus

import CoreAudio
import Foundation

struct AudioDevice {
  enum DefaultDeviceKind: CustomStringConvertible {
    case input
    case output
    case systemOutput

    var description: String {
      switch self {
      case .input: "Input"
      case .output: "Output"
      case .systemOutput: "System Output"
      }
    }

    fileprivate var selector: AudioObjectPropertySelector {
      switch self {
      case .input: kAudioHardwarePropertyDefaultInputDevice
      case .output: kAudioHardwarePropertyDefaultOutputDevice
      case .systemOutput: kAudioHardwarePropertyDefaultSystemOutputDevice
      }
    }
  }

  struct TransportType: RawRepresentable {
    static let unknown = TransportType(rawValue: kAudioDeviceTransportTypeUnknown)

    let rawValue: UInt32

    var isBluetooth: Bool {
      rawValue == kAudioDeviceTransportTypeBluetooth || rawValue == kAudioDeviceTransportTypeBluetoothLE
    }
  }

  enum Error: Swift.Error, LocalizedError {
    case failedToDetermineDefaultDevice(DefaultDeviceKind, status: OSStatus)
    case failedToReadProperty(String, deviceID: AudioDeviceID, status: OSStatus)
    case missingPropertyValue(String, deviceID: AudioDeviceID)
    case failedToObserveDefaultDeviceChanges(DefaultDeviceKind, status: OSStatus)

    var errorDescription: String? {
      switch self {
      case .failedToDetermineDefaultDevice(let defaultDeviceKind, let status):
        "Failed to determine the default \(defaultDeviceKind) device: \(status.statusDescription)"

      case .failedToReadProperty(let propertyName, let deviceID, let status):
        "Failed to read \(propertyName) for device '\(deviceID)': \(status.statusDescription)"

      case .missingPropertyValue(let propertyName, let deviceID):
        "Device '\(deviceID)' did not return a value for \(propertyName)."

      case .failedToObserveDefaultDeviceChanges(let defaultDeviceKind, let status):
        "Failed to observe default \(defaultDeviceKind) device changes: \(status.statusDescription)"
      }
    }
  }

  private static let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

  let id: AudioDeviceID

  var name: String {
    get throws(Error) {
      var name: Unmanaged<CFString>?

      let status = Self.readProperty(kAudioObjectPropertyName, of: id, into: &name)

      guard status == kAudioHardwareNoError else {
        throw Error.failedToReadProperty("name", deviceID: id, status: status)
      }

      guard let name else {
        throw Error.missingPropertyValue("name", deviceID: id)
      }

      return name.takeRetainedValue() as String
    }
  }

  var transportType: TransportType {
    get throws(Error) {
      guard Self.hasProperty(kAudioDevicePropertyTransportType, of: id) else {
        return .unknown
      }

      var rawValue = kAudioDeviceTransportTypeUnknown

      let status = Self.readProperty(kAudioDevicePropertyTransportType, of: id, into: &rawValue)

      guard status == kAudioHardwareNoError else {
        throw Error.failedToReadProperty("transport type", deviceID: id, status: status)
      }

      return TransportType(rawValue: rawValue)
    }
  }

  static func defaultDevice(_ kind: DefaultDeviceKind) throws(Error) -> AudioDevice? {
    var deviceID = kAudioDeviceUnknown

    let status = readProperty(kind.selector, of: systemObjectID, into: &deviceID)

    guard status == kAudioHardwareNoError else {
      throw Error.failedToDetermineDefaultDevice(kind, status: status)
    }

    return deviceID != kAudioDeviceUnknown ? AudioDevice(id: deviceID) : nil
  }

  static func defaultDeviceUpdates(
    for kind: DefaultDeviceKind,
    dispatchQueue: DispatchQueue = .main
  ) throws(Error) -> AsyncStream<AudioDevice?> {
    precondition(dispatchQueue is DispatchSerialQueue, "dispatchQueue must be a serial queue")

    let (stream, continuation) = AsyncStream.makeStream(
      of: AudioDevice?.self,
      bufferingPolicy: .bufferingNewest(1)
    )
    let listener: @Sendable @convention(block) (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void = { _, _ in
      continuation.yieldDefaultDevice(kind)
    }

    var address = propertyAddress(kind.selector)

    let status = AudioObjectAddPropertyListenerBlock(systemObjectID, &address, dispatchQueue, listener)

    guard status == kAudioHardwareNoError else {
      throw Error.failedToObserveDefaultDeviceChanges(kind, status: status)
    }

    continuation.onTermination = { [address] _ in
      var address = address

      let status = AudioObjectRemovePropertyListenerBlock(systemObjectID, &address, dispatchQueue, listener)

      if status != kAudioHardwareNoError {
        Log.error("Failed to remove property listener for default device changes: \(status.statusDescription)")
      }
    }

    dispatchQueue.async {
      continuation.yieldDefaultDevice(kind)
    }

    return stream
  }

  private static func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    return AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  private static func hasProperty(_ selector: AudioObjectPropertySelector, of objectID: AudioObjectID) -> Bool {
    var address = propertyAddress(selector)
    return AudioObjectHasProperty(objectID, &address)
  }

  private static func readProperty<Value: BitwiseCopyable>(
    _ selector: AudioObjectPropertySelector,
    of objectID: AudioObjectID,
    into value: inout Value
  ) -> OSStatus {
    var address = propertyAddress(selector)

    let expectedSize = UInt32(MemoryLayout<Value>.size)

    var size = expectedSize

    let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)

    guard status == kAudioHardwareNoError else {
      return status
    }

    return size == expectedSize ? kAudioHardwareNoError : kAudioHardwareBadPropertySizeError
  }
}

private extension AsyncStream<AudioDevice?>.Continuation {
  func yieldDefaultDevice(_ kind: AudioDevice.DefaultDeviceKind) {
    do {
      yield(try AudioDevice.defaultDevice(kind))
    } catch {
      Log.error(error.localizedDescription)
    }
  }
}
