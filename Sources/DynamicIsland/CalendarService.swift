import AppKit
import SwiftUI
import EventKit

enum MeetingProvider: String {
    case teams = "Teams", zoom = "Zoom", meet = "Google Meet", webex = "Webex"

    var color: Color {
        switch self {
        case .teams: return Color(red: 0.38, green: 0.39, blue: 0.84)
        case .zoom: return Color(red: 0.18, green: 0.55, blue: 1.0)
        case .meet: return Color(red: 0.0, green: 0.67, blue: 0.47)
        case .webex: return Color(red: 0.0, green: 0.62, blue: 0.86)
        }
    }
}

struct CalEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let color: Color
    let calendarName: String
    let meetingURL: URL?
    let provider: MeetingProvider?
}

/// Reads events from macOS Calendar (add your Outlook/Exchange account in
/// System Settings ▸ Internet Accounts so Teams meetings show up here).
final class CalendarService: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var events: [CalEvent] = []
    @Published private(set) var access: Access = .unknown
    @Published private(set) var now = Date()

    private let store = EKEventStore()
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var lastReload = Date.distantPast

    func start() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
            reload()
        case .notDetermined:
            requestAccess()
        default:
            access = .denied
        }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                self?.reload()
            }
        }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.now = Date()
                if self.now.timeIntervalSince(self.lastReload) > 300 { self.reload() }
                else { self.events = self.events.filter { $0.end > self.now } }
            }
        }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.access = granted ? .granted : .denied
                if granted { self?.reload() }
            }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func reload() {
        guard access == .granted else { return }
        lastReload = Date()
        now = Date()
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 2, to: startOfDay) else { return }
        let predicate = store.predicateForEvents(withStart: startOfDay, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(15)
            .map(Self.makeEvent)
    }

    // MARK: Derived

    /// The event the compact island should show: starting within 15 min or started < 10 min ago.
    var soonEvent: CalEvent? {
        events.first {
            let d = $0.start.timeIntervalSince(now)
            return d <= 15 * 60 && d > -10 * 60 && $0.end > now
        }
    }

    var upcomingToday: [CalEvent] {
        let cal = Calendar.current
        let today = events.filter { cal.isDateInToday($0.start) || $0.start <= now }
        return today.isEmpty ? Array(events.prefix(4)) : today
    }

    // MARK: Join

    func join(_ e: CalEvent) {
        guard let url = e.meetingURL else { return }
        // Open Teams links straight in the Teams app when it is installed.
        if e.provider == .teams,
           url.host?.contains("teams.microsoft.com") == true,
           let scheme = URL(string: "msteams:"),
           NSWorkspace.shared.urlForApplication(toOpen: scheme) != nil {
            var s = url.absoluteString
            if let r = s.range(of: #"^https?://teams\.microsoft\.com"#, options: .regularExpression) {
                s.replaceSubrange(r, with: "msteams:")
                if let deep = URL(string: s) {
                    NSWorkspace.shared.open(deep)
                    return
                }
            }
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: Parsing

    private static func makeEvent(_ ev: EKEvent) -> CalEvent {
        let meeting = findMeeting(ev)
        let base = ev.calendarItemIdentifier
        return CalEvent(
            id: "\(base)-\(Int(ev.startDate.timeIntervalSince1970))",
            title: (ev.title?.isEmpty == false ? ev.title : nil) ?? "Untitled event",
            start: ev.startDate,
            end: ev.endDate,
            color: Color(nsColor: ev.calendar?.color ?? .systemBlue),
            calendarName: ev.calendar?.title ?? "",
            meetingURL: meeting?.0,
            provider: meeting?.1
        )
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func findMeeting(_ ev: EKEvent) -> (URL, MeetingProvider)? {
        var texts: [String] = []
        if let u = ev.url { texts.append(u.absoluteString) }
        if let l = ev.location { texts.append(l) }
        if let n = ev.notes { texts.append(n) }
        for text in texts {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector?.matches(in: text, options: [], range: range) ?? [] {
                guard var url = match.url else { continue }
                url = unwrapSafeLink(url)
                if let p = provider(for: url) { return (url, p) }
            }
        }
        return nil
    }

    /// Outlook often wraps links as https://*.safelinks.protection.outlook.com/?url=<real link>
    private static func unwrapSafeLink(_ url: URL) -> URL {
        guard url.host?.contains("safelinks.protection.outlook.com") == true,
              let inner = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value,
              let real = URL(string: inner) else { return url }
        return real
    }

    private static func provider(for url: URL) -> MeetingProvider? {
        let host = url.host?.lowercased() ?? ""
        if host.contains("teams.microsoft.com") || host.contains("teams.live.com") { return .teams }
        if host.hasSuffix("zoom.us") { return .zoom }
        if host == "meet.google.com" { return .meet }
        if host.hasSuffix("webex.com") { return .webex }
        return nil
    }
}

// MARK: - Formatting helpers

func countdown(to date: Date, from now: Date) -> String {
    let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
    if minutes <= 0 { return "now" }
    if minutes < 60 { return "in \(minutes)m" }
    let h = minutes / 60, m = minutes % 60
    return m == 0 ? "in \(h)h" : "in \(h)h \(m)m"
}
