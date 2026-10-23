import AppKit

typealias DisplayIdentifier = String
typealias SpaceID = UInt64

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
}

struct DisplaySpaces {
  let displayIdentifier: DisplayIdentifier
  let spaceIDs: [SpaceID]
  var currentSpaceID: SpaceID?

  var currentSpaceIndex: Int? { currentSpaceID.flatMap { spaceIDs.firstIndex(of: $0) } }
}
