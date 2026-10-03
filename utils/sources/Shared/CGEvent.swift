import AppKit

extension CGEventType {
  static let gesture = CGEventType(rawValue: 29)!
  static let dockControl = CGEventType(rawValue: 30)!
}

extension CGEventField {
  static let cgsEventType = CGEventField(rawValue: 55)!
  static let gestureHIDType = CGEventField(rawValue: 110)!
  static let gestureZoomValue = CGEventField(rawValue: 113)!
  static let gestureSwipeMotion = CGEventField(rawValue: 123)!
  static let gestureSwipeProgress = CGEventField(rawValue: 124)!
  static let gestureSwipeVelocityX = CGEventField(rawValue: 129)!
  static let gesturePhase = CGEventField(rawValue: 132)!
}

enum IOHIDEventType: UInt32 {
  case zoom = 8
  case velocity = 9
  case dockSwipe = 23
}

enum IOHIDGestureMotion: UInt16 {
  case horizontal = 1
}

extension CGEvent {
  var eventSourceUserData: Int64 {
    get { getIntegerValueField(.eventSourceUserData) }
    set { self.setIntegerValueField(.eventSourceUserData, value: newValue) }
  }

  var keyboardEventKeycode: CGKeyCode {
    get { CGKeyCode(getIntegerValueField(.keyboardEventKeycode)) }
    set { self.setIntegerValueField(.keyboardEventKeycode, value: Int64(newValue)) }
  }

  var keyboardEventAutorepeat: Bool {
    get { getIntegerValueField(.keyboardEventAutorepeat) != 0 }
    set { self.setIntegerValueField(.keyboardEventAutorepeat, value: newValue ? 1 : 0) }
  }

  var mouseEventSubtype: NSEvent.EventSubtype? {
    guard let mouseEventSubtypeRawValue = Int16(exactly: getIntegerValueField(.mouseEventSubtype)) else {
      return nil
    }

    return NSEvent.EventSubtype(rawValue: mouseEventSubtypeRawValue)
  }

  var scrollPhase: CGScrollPhase? {
    get {
      guard let scrollPhaseRawValue = UInt32(exactly: getIntegerValueField(.scrollWheelEventScrollPhase)) else {
        return nil
      }

      return CGScrollPhase(rawValue: scrollPhaseRawValue)
    }

    set {
      if let newValue {
        self.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(newValue.rawValue))
      }
    }
  }

  var scrollWheelEventPointDeltaAxis1: Int64 {
    get { getIntegerValueField(.scrollWheelEventPointDeltaAxis1) }
    set { self.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: newValue) }
  }

  var cgsEventType: CGEventType? {
    get {
      guard let rawValue = UInt32(exactly: getIntegerValueField(.cgsEventType)) else {
        return nil
      }

      return CGEventType(rawValue: rawValue)
    }

    set {
      if let newValue {
        self.setIntegerValueField(.cgsEventType, value: Int64(newValue.rawValue))
      }
    }
  }

  var gestureHIDType: IOHIDEventType? {
    get {
      guard let rawValue = UInt32(exactly: getIntegerValueField(.gestureHIDType)) else {
        return nil
      }

      return IOHIDEventType(rawValue: rawValue)
    }

    set {
      if let newValue {
        self.setIntegerValueField(.gestureHIDType, value: Int64(newValue.rawValue))
      }
    }
  }

  var gesturePhase: CGGesturePhase? {
    get {
      guard let rawValue = UInt32(exactly: getIntegerValueField(.gesturePhase)) else {
        return nil
      }

      return CGGesturePhase(rawValue: rawValue)
    }

    set {
      if let newValue {
        self.setIntegerValueField(.gesturePhase, value: Int64(newValue.rawValue))
      }
    }
  }

  var gestureZoomValue: Double {
    get { getDoubleValueField(.gestureZoomValue) }
    set { self.setDoubleValueField(.gestureZoomValue, value: newValue) }
  }

  var gestureSwipeMotion: IOHIDGestureMotion? {
    get {
      guard let rawValue = UInt16(exactly: getIntegerValueField(.gestureSwipeMotion)) else {
        return nil
      }

      return IOHIDGestureMotion(rawValue: rawValue)
    }

    set {
      if let newValue {
        self.setIntegerValueField(.gestureSwipeMotion, value: Int64(newValue.rawValue))
      }
    }
  }

  var gestureSwipeProgress: Double {
    get { getDoubleValueField(.gestureSwipeProgress) }
    set { self.setDoubleValueField(.gestureSwipeProgress, value: newValue) }
  }

  var gestureSwipeVelocityX: Double {
    get { getDoubleValueField(.gestureSwipeVelocityX) }
    set { self.setDoubleValueField(.gestureSwipeVelocityX, value: newValue) }
  }
}
