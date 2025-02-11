#!/usr/bin/swift

import AppKit
import EventKit
import Foundation

enum EventPriority: Int {
  case imminent = 1
  case upcoming = 2
  case recent = 3
  case ongoing = 4
  case future = 5
  case ended = 6
}

struct EventStatus {
  let priority: EventPriority
  let timeLabel: String
}

private func formatTimeLabel(prefix: String = "", _ minutes: Int, suffix: String = "") -> String {
  if minutes >= 60 {
    return "\(prefix) \(minutes / 60)h \(minutes % 60)m \(suffix)"
  }
  return "\(prefix) \(minutes)m \(suffix)"
}

func generateEventStatus(event: EKEvent, now: Date) -> EventStatus {
  let minutesUntilStart = Int(ceil(event.startDate.timeIntervalSince(now) / 60))
  let minutesUntilEnd = Int(ceil(event.endDate.timeIntervalSince(now) / 60))
  let minutesSinceStart = Int(floor(now.timeIntervalSince(event.startDate) / 60))

  // Future events
  if minutesUntilStart >= 0 {
    if minutesUntilStart <= 1 {
      return EventStatus(priority: .imminent, timeLabel: "now")
    }
    if minutesUntilStart <= 5 {
      return EventStatus(priority: .upcoming, timeLabel: formatTimeLabel(prefix: "in", minutesUntilStart))
    }
    return EventStatus(priority: .future, timeLabel: formatTimeLabel(prefix: "in", minutesUntilStart))
  }
  // Past/ongoing events
  if minutesSinceStart <= 4 {
    return EventStatus(priority: .recent, timeLabel: formatTimeLabel(minutesSinceStart, suffix: " ago"))
  }
  if minutesUntilEnd > 0 {
    return EventStatus(priority: .ongoing, timeLabel: formatTimeLabel(minutesUntilEnd, suffix: " left"))
  }
  // Fallback
  return EventStatus(priority: .ended, timeLabel: "ended")
}

private func extractURL(from text: String) -> URL? {
  guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
    return nil
  }
  if let match = detector.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
    return match.url
  }
  return nil
}

func openURL(for event: EKEvent) {
  let minutesUntilStart = Int(ceil(event.startDate.timeIntervalSince(Date()) / 60))
  let fallbackURL = URL(string: "ical://ekevent/\(event.calendarItemIdentifier)")!

  // Open calendar app if event is not imminent
  guard minutesUntilStart <= 5 else {
    NSWorkspace.shared.open(fallbackURL)
    return
  }

  // Try to extract a URL from various fields that might contain a valid link (first match wins)
  let candidateStrings: [String?] = [
    event.url?.absoluteString,
    event.location,
    event.notes,
  ]
  for candidate in candidateStrings.compactMap({ $0 }) {
    if let extractedURL = extractURL(from: candidate),
      let urlToOpen = extractedURL.scheme == nil
        ? URL(string: "https://\(extractedURL.absoluteString)")  // Assume https if no scheme is present
        : extractedURL
    {
      if NSWorkspace.shared.open(urlToOpen) {
        return
      }
    }
  }

  // Open calendar app as a fallback
  NSWorkspace.shared.open(fallbackURL)
}

let semaphore = DispatchSemaphore(value: 0)
let eventStore = EKEventStore()

eventStore.requestFullAccessToEvents { granted, _ in handleCalendarAccess(granted: granted) }

func handleCalendarAccess(granted: Bool) {
  guard granted else {
    print("Calendar access not granted")
    semaphore.signal()
    return
  }

  let now = Date()
  let today = Calendar.current.dateInterval(of: .day, for: now)!
  let calendars = eventStore.calendars(for: .event)
  let predicate = eventStore.predicateForEvents(withStart: today.start, end: today.end, calendars: calendars)
  let sortedEvents = eventStore.events(matching: predicate)
    .filter { !$0.isAllDay && $0.endDate > now }
    .map { event in (event, generateEventStatus(event: event, now: now)) }
    .sorted { lhs, rhs in
      let (event1, status1) = lhs
      let (event2, status2) = rhs

      if status1.priority != status2.priority {
        return status1.priority.rawValue < status2.priority.rawValue
      }
      return status1.priority == .ongoing
        ? event1.startDate > event2.startDate  // Latest first for prioritising between two ongoing events
        : event1.startDate < event2.startDate  // ...otherwise, earliest first
    }

  if let nextEvent = sortedEvents.first {
    let arguments = CommandLine.arguments
    if arguments.contains("--open-url") {
      openURL(for: nextEvent.0)
    } else {
      let eventTitle = nextEvent.0.title.trimmingCharacters(in: .whitespacesAndNewlines)
      let eventLabel = eventTitle.isEmpty ? "Next event" : eventTitle
      let timeLabel = nextEvent.1.timeLabel
      print("\(eventLabel) ∙ \(timeLabel)")
    }
  }

  semaphore.signal()
}

_ = semaphore.wait(timeout: .distantFuture)
