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
  let display: String
  let priority: EventPriority
  let sortDate: Date
}

let eventStore = EKEventStore()
let semaphore = DispatchSemaphore(value: 0)

eventStore.requestFullAccessToEvents { granted, _ in
  handleCalendarAccess(granted: granted)
}

private func formatDuration(_ minutes: Int, suffix: String = "") -> String {
  guard minutes >= 60 else { return "\(minutes)m\(suffix)" }
  return "\(minutes / 60)h \(minutes % 60)m\(suffix)"
}

func calculateEventStatus(event: EKEvent, now: Date) -> EventStatus {
  let minutesUntilStart = Int(ceil(event.startDate.timeIntervalSince(now) / 60))
  let minutesUntilEnd = Int(ceil(event.endDate.timeIntervalSince(now) / 60))
  let minutesSinceStart = Int(floor(now.timeIntervalSince(event.startDate) / 60))

  // Future events
  if minutesUntilStart >= 0 {
    if minutesUntilStart <= 1 {
      return EventStatus(display: "now", priority: .imminent, sortDate: event.startDate)
    }
    if minutesUntilStart <= 5 {
      return EventStatus(
        display: "in \(minutesUntilStart)m", priority: .upcoming, sortDate: event.startDate)
    }
    return EventStatus(
      display: "in \(formatDuration(minutesUntilStart))",
      priority: .future,
      sortDate: event.startDate
    )
  }

  // Past/ongoing events
  if minutesSinceStart <= 4 {
    return EventStatus(
      display: "\(minutesSinceStart)m ago",
      priority: .recent,
      sortDate: event.startDate
    )
  }
  if minutesUntilEnd > 0 {
    return EventStatus(
      display: formatDuration(minutesUntilEnd, suffix: " left"),
      priority: .ongoing,
      sortDate: event.startDate
    )
  }

  return EventStatus(display: "ended", priority: .ended, sortDate: event.startDate)
}

func getEventURL(event: EKEvent) -> URL? {
  if let location = event.location {
    if let url = URL(string: location) {
      return url
    }
  }
  if let url = event.url {
    return url
  }
  return nil
}

func handleCalendarAccess(granted: Bool) {
  guard granted else {
    print("Calendar access not granted")
    semaphore.signal()
    return
  }

  let now = Date()
  let calendar = Calendar.current
  let startOfDay = calendar.startOfDay(for: now)

  guard let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) else {
    semaphore.signal()
    return
  }

  let calendars = eventStore.calendars(for: .event)
  let predicate = eventStore.predicateForEvents(
    withStart: startOfDay,
    end: endOfDay,
    calendars: calendars
  )

  let relevantEvents = eventStore.events(matching: predicate)
    .filter { !$0.isAllDay && $0.endDate > now }
    .sorted { event1, event2 in
      let status1 = calculateEventStatus(event: event1, now: now)
      let status2 = calculateEventStatus(event: event2, now: now)

      if status1.priority != status2.priority {
        return status1.priority.rawValue < status2.priority.rawValue
      }

      return status1.priority == .ongoing
        ? event1.startDate > event2.startDate  // Most recent first for ongoing
        : event1.startDate < event2.startDate  // Earliest first for future
    }

  if let nextEvent = relevantEvents.first {
    let arguments = CommandLine.arguments
    if arguments.contains("--open-url") {
      if let eventURL = getEventURL(event: nextEvent) {
        NSWorkspace.shared.open(eventURL)
      } else {
        // Open schedule in Raycast as a fallback
        if let raycastURL = URL(string: "raycast://extensions/raycast/calendar/my-schedule") {
          NSWorkspace.shared.open(raycastURL)
        }
      }
    } else {
      let title = nextEvent.title.trimmingCharacters(in: .whitespacesAndNewlines)
      let displayTitle = title.isEmpty ? "Next meeting" : title
      let timeStatus = calculateEventStatus(event: nextEvent, now: now).display
      print("\(displayTitle) ∙ \(timeStatus)")
    }
  }

  semaphore.signal()
}

_ = semaphore.wait(timeout: .distantFuture)
