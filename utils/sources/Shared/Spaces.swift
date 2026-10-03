import AppKit

typealias CGSConnectionID = UInt32
typealias DisplayIdentifier = String
typealias SpaceID = UInt64

// swift-format-ignore: AlwaysUseLowerCamelCase
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

// swift-format-ignore: AlwaysUseLowerCamelCase
@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connectionID: CGSConnectionID, _ displayIdentifier: CFString?) -> Unmanaged<CFArray>?

extension NSScreen {
  var displayIdentifier: DisplayIdentifier? {
    guard
      let cgDirectDisplayID,
      let uuid = CGDisplayCreateUUIDFromDisplayID(cgDirectDisplayID)?.takeRetainedValue()
    else {
      return nil
    }

    return CFUUIDCreateString(nil, uuid) as DisplayIdentifier
  }

  var displaySpaces: DisplaySpaces? {
    guard let displayIdentifier else {
      return nil
    }

    return DisplaySpaces.all(displayIdentifier: displayIdentifier).first { $0.displayIdentifier == displayIdentifier }
  }
}

struct DisplaySpaces {
  let displayIdentifier: DisplayIdentifier
  let spaceIDs: [SpaceID]
  var currentSpaceID: SpaceID?

  var currentSpaceIndex: Int? { currentSpaceID.flatMap { spaceIDs.firstIndex(of: $0) } }

  static func all(
    connectionID: CGSConnectionID = CGSMainConnectionID(),
    displayIdentifier: DisplayIdentifier? = nil
  ) -> [DisplaySpaces] {
    guard
      let managedDisplaySpaces = CGSCopyManagedDisplaySpaces(
        connectionID,
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
}
