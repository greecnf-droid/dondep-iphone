import Foundation
import EventKit

@MainActor
final class CalendarCleaner: ObservableObject {
    enum State { case idle, loading, denied, loaded }

    @Published var state: State = .idle
    @Published var events: [EKEvent] = []
    let store = EKEventStore()

    func load(monthsOld: Int) async {
        state = .loading
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        guard granted else {
            state = .denied
            return
        }
        let calendars = store.calendars(for: .event).filter { $0.allowsContentModifications }
        guard !calendars.isEmpty else {
            events = []
            state = .loaded
            return
        }
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .month, value: -monthsOld, to: Date()) ?? Date()
        var found: [String: EKEvent] = [:]
        var end = cutoff
        // Quét lùi 10 năm, mỗi lần 1 năm (EventKit giới hạn 4 năm/lần).
        for _ in 0..<10 {
            let start = cal.date(byAdding: .year, value: -1, to: end) ?? end
            let pred = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
            for e in store.events(matching: pred) where !e.hasRecurrenceRules && e.endDate <= cutoff {
                if let id = e.eventIdentifier { found[id] = e }
            }
            end = start
        }
        events = found.values.sorted { $0.startDate > $1.startDate }
        state = .loaded
    }

    func delete(_ ids: Set<String>) throws -> Int {
        var count = 0
        for e in events where ids.contains(e.eventIdentifier ?? "") {
            try store.remove(e, span: .thisEvent, commit: false)
            count += 1
        }
        try store.commit()
        events.removeAll { ids.contains($0.eventIdentifier ?? "") }
        return count
    }
}
