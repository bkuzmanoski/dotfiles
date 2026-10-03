import AppKit

extension NSStatusItem {
  var isVisiblePreservingPosition: Bool {
    get { isVisible }

    set {
      guard newValue != isVisible else {
        return
      }

      let preferredPositionKey = Self.preferredPositionKey(for: autosaveName)
      let preferredPosition = UserDefaults.standard.object(forKey: preferredPositionKey)

      defer {
        if let preferredPosition {
          UserDefaults.standard.set(preferredPosition, forKey: preferredPositionKey)
        }
      }

      self.isVisible = newValue
    }
  }

  static func preferredPositionKey(for autosaveName: AutosaveName) -> String {
    return "NSStatusItem Preferred Position \(autosaveName)"
  }
}
