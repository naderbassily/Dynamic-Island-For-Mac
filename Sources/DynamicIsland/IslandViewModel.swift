import AppKit
import SwiftUI
import Combine

enum IslandTab: String, CaseIterable, Identifiable {
    case media, calendar, inbox, shelf, timer, system, shortcuts, search
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .media: return "music.note"
        case .calendar: return "calendar"
        case .inbox: return "bell.fill"
        case .shelf: return "tray.full.fill"
        case .timer: return "timer"
        case .system: return "gauge.with.dots.needle.50percent"
        case .shortcuts: return "square.stack.3d.up.fill"
        case .search: return "magnifyingglass"
        }
    }

    var title: String {
        switch self {
        case .media: return "Media"
        case .calendar: return "Calendar"
        case .inbox: return "Inbox"
        case .shelf: return "Shelf"
        case .timer: return "Timer"
        case .system: return "System"
        case .shortcuts: return "Shortcuts"
        case .search: return "Search"
        }
    }

    var isEnabled: Bool {
        switch self {
        case .media: return Prefs.showMedia
        case .calendar: return Prefs.showCalendar
        case .inbox: return Prefs.showInbox
        case .shelf: return Prefs.showShelf
        case .timer: return Prefs.showTimer
        case .system: return Prefs.showSystem
        case .shortcuts: return Prefs.showShortcuts
        case .search: return true
        }
    }
}

/// What the collapsed pill is showing right now (highest priority first).
enum CompactContent {
    case meeting(CalEvent)
    case timer
    case media(MediaInfo)
    case unread
    case idle
    case empty
}

/// Every service the island uses.
struct IslandServices {
    let nowPlaying = NowPlayingService()
    let calendar = CalendarService()
    let search = SearchService()
    let notifications = NotificationService()
    let power = PowerService()
    let audio = AudioService()
    let devices = DeviceService()
    let timer = TimerService()
    let shelf = ShelfService()
    let clipboard = ClipboardService()
    let weather = WeatherService()
    let stats = SystemStatsService()
    let shortcuts = ShortcutsService()
}

final class IslandViewModel: ObservableObject {
    @Published var expanded = false
    @Published var tab: IslandTab = .media
    /// Pinned = stays open even when the mouse leaves (search mode).
    @Published var pinned = false
    @Published var searchFocusToken = UUID()
    /// A banner shown in the collapsed island (new message, charging, volume…).
    @Published private(set) var alert: IslandAlert?
    /// Camera-notch size of the current display (zero on Mac mini / external displays).
    @Published var notch: CGSize = .zero
    /// True while a full-screen app is in front (the idle pill hides).
    @Published var hiddenForFullscreen = false
    /// Temporarily keeps the island open (meeting alerts, URL commands).
    var holdUntil: Date?

    let services: IslandServices
    var nowPlaying: NowPlayingService { services.nowPlaying }
    var calendar: CalendarService { services.calendar }
    var search: SearchService { services.search }
    var notifications: NotificationService { services.notifications }

    var onRequestKey: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var bag = Set<AnyCancellable>()
    private var alerted = Set<String>()
    private var meetingTimer: Timer?
    private var bannerWork: DispatchWorkItem?
    private var lastCapsLock: Bool?

    init(services: IslandServices) {
        self.services = services
        let s = services
        // Re-render the island whenever any service changes.
        let publishers: [ObservableObjectPublisher] = [
            s.nowPlaying.objectWillChange, s.calendar.objectWillChange, s.notifications.objectWillChange,
            s.power.objectWillChange, s.audio.objectWillChange, s.timer.objectWillChange,
            s.weather.objectWillChange,
        ]
        for p in publishers {
            p.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        }
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.settingsChanged() }
            .store(in: &bag)
        // Only sample CPU/memory while the System tab is visible.
        let stats = s.stats, shortcuts = s.shortcuts
        $expanded.combineLatest($tab)
            .sink { [weak stats, weak shortcuts] open, tab in
                stats?.setActive(open && tab == .system)
                if open && tab == .shortcuts { shortcuts?.reloadIfStale() }
            }
            .store(in: &bag)

        let post: (IslandAlert) -> Void = { [weak self] a in self?.post(a) }
        s.notifications.onAlert = post
        s.power.onAlert = post
        s.audio.onAlert = post
        s.devices.onAlert = post
        s.timer.onAlert = post
        s.shelf.onAlert = post
        s.shortcuts.onAlert = post

        meetingTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.checkMeetingAlerts()
        }
    }

    // MARK: Live content (respects settings)

    var soonEvent: CalEvent? { Prefs.showCalendar ? calendar.soonEvent : nil }
    var playing: MediaInfo? {
        guard Prefs.showMedia, let i = nowPlaying.info, i.isPlaying else { return nil }
        return i
    }
    var unreadBadges: [BadgeItem] { Prefs.showInbox ? notifications.badges : [] }
    var micInUse: Bool { Prefs.micIndicator && services.audio.micInUse }
    var visibleTabs: [IslandTab] { IslandTab.allCases.filter(\.isEnabled) }

    var compactContent: CompactContent {
        if let e = soonEvent { return .meeting(e) }
        if services.timer.isActive { return .timer }
        if let p = playing { return .media(p) }
        if !unreadBadges.isEmpty { return .unread }
        if Prefs.idleInfo && !hasNotch { return .idle }
        return .empty
    }

    // MARK: Layout

    var hasNotch: Bool { notch.width > 0 }
    var topInset: CGFloat { notch.height }
    static let notchSide: CGFloat = 78

    var isHeld: Bool { pinned || (holdUntil.map { $0 > Date() } ?? false) }

    /// The compact pill widens when there is something "live" to show.
    var compactWide: Bool {
        switch compactContent {
        case .empty, .idle: return micInUse
        default: return true
        }
    }

    /// Floating, fully rounded pill (like iPhone) vs. attached to the top edge.
    /// MacBook notch screens always hug the notch.
    var pillStyle: Bool { Prefs.islandStyle == "pill" && !hasNotch }
    /// Gap between the top of the screen and a floating pill.
    /// Height of the menu bar on the current display (used to centre the pill inside it).
    @Published var menuBarHeight: CGFloat = 24
    /// Gap above a floating pill so it sits vertically centred in the menu bar.
    var topGap: CGFloat { pillStyle ? max(1, ((menuBarHeight - scale.compactH) / 2).rounded()) : 0 }

    private var scale: (compactH: CGFloat, idleW: CGFloat, clockW: CGFloat, wideW: CGFloat,
                        openW: CGFloat, openH: CGFloat, searchW: CGFloat, searchH: CGFloat,
                        bannerW: CGFloat, hudW: CGFloat) {
        switch Prefs.islandSize {
        case "large":  return (34, 210, 240, 340, 580, 260, 600, 360, 420, 320)
        case "medium": return (30, 180, 210, 300, 540, 236, 580, 330, 400, 300)
        default:       return (22, 120, 150, 250, 520, 226, 560, 314, 360, 260)
        }
    }

    var compactHeight: CGFloat { hasNotch ? notch.height : scale.compactH }

    var size: CGSize {
        let s = scale
        if expanded {
            let w = tab == .search ? s.searchW : s.openW
            let h = tab == .search ? s.searchH : s.openH
            return CGSize(width: max(w, notch.width + 60), height: h + topInset)
        }
        if let a = alert {
            let w = a.compact ? s.hudW : s.bannerW
            let h: CGFloat = a.compact ? 44 : 64
            return CGSize(width: max(w, notch.width + 60), height: h + topInset)
        }
        if hasNotch {
            return CGSize(width: notch.width + (compactWide ? Self.notchSide * 2 : 0), height: notch.height)
        }
        if compactWide { return CGSize(width: s.wideW, height: s.compactH) }
        return CGSize(width: compactContent.isIdle ? s.clockW : s.idleW, height: s.compactH)
    }

    private var defaultTab: IslandTab {
        if let t = alert?.tab, t.isEnabled { return t }
        if soonEvent != nil { return .calendar }
        if services.timer.isActive && Prefs.showTimer { return .timer }
        if playing != nil { return .media }
        if (!unreadBadges.isEmpty || notifications.mailUnread > 0) && Prefs.showInbox { return .inbox }
        if Prefs.showMedia && nowPlaying.info != nil { return .media }
        return visibleTabs.first ?? .search
    }

    // MARK: Actions

    func expand(tab: IslandTab? = nil) {
        let t = tab ?? defaultTab
        self.tab = t.isEnabled ? t : (visibleTabs.first ?? .search)
        clearAlert()
        expanded = true
    }

    func collapse() {
        let wasPinned = pinned
        expanded = false
        pinned = false
        holdUntil = nil
        if !search.query.isEmpty { search.query = "" }
        if wasPinned { onDismiss?() }
    }

    func select(_ t: IslandTab) {
        tab = t
        if t == .search { focusSearch() }
    }

    func toggleSearch() {
        if expanded && tab == .search && pinned {
            collapse()
        } else {
            tab = .search
            clearAlert()
            expanded = true
            focusSearch()
        }
    }

    private func focusSearch() {
        pinned = true
        onRequestKey?()
        searchFocusToken = UUID()
    }

    private func settingsChanged() {
        if expanded && !tab.isEnabled { tab = visibleTabs.first ?? .search }
        objectWillChange.send()
    }

    // MARK: Banners

    func post(_ a: IslandAlert) {
        if Prefs.alertSound, let sound = a.sound { NSSound(named: NSSound.Name(sound))?.play() }
        guard !expanded else { return }   // already open: the tabs update live
        // Don't let a volume blip replace an important banner that is still showing.
        if let current = alert, current.compact == false, a.compact, current.kind != a.kind { return }
        alert = a
        bannerWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            if self?.alert?.id == a.id { self?.alert = nil }
        }
        bannerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + a.duration, execute: work)
    }

    func clearAlert() {
        bannerWork?.cancel()
        if alert != nil { alert = nil }
    }

    /// Called ~30×/s by the app delegate; shows a HUD when Caps Lock toggles.
    func checkCapsLock() {
        let on = NSEvent.modifierFlags.contains(.capsLock)
        defer { lastCapsLock = on }
        guard let last = lastCapsLock, last != on, Prefs.capsLockHUD else { return }
        post(IslandAlert(icon: .symbol(on ? "capslock.fill" : "capslock", on ? .green : .gray),
                         title: "Caps Lock", message: on ? "On" : "Off",
                         duration: 1.3, sound: nil, kind: "capslock", compact: true))
    }

    /// Pops the island open ~1 minute before a meeting starts (like a Live Activity).
    private func checkMeetingAlerts() {
        guard Prefs.showCalendar, Prefs.meetingPopup else { return }
        let now = Date()
        guard let e = calendar.events.first(where: {
            let d = $0.start.timeIntervalSince(now)
            return d > -30 && d <= 90
        }), !alerted.contains(e.id) else { return }
        alerted.insert(e.id)
        if !expanded {
            expand(tab: .calendar)
            holdUntil = now.addingTimeInterval(10)
            if Prefs.alertSound { NSSound(named: "Glass")?.play() }
        }
    }
}

extension CompactContent {
    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
}
