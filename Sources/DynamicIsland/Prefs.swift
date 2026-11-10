import Foundation

/// User preferences (stored in UserDefaults). Views bind to the same keys with @AppStorage.
enum Prefs {
    enum Key {
        // Tabs
        static let showMedia = "showMedia"
        static let showCalendar = "showCalendar"
        static let showInbox = "showInbox"
        static let showShelf = "showShelf"
        static let showTimer = "showTimer"
        static let showSystem = "showSystem"
        static let showShortcuts = "showShortcuts"
        // Behaviour
        static let meetingPopup = "meetingPopup"
        static let messageAlerts = "messageAlerts"
        static let alertSound = "alertSound"
        static let mailDetails = "mailDetails"
        static let watchAllApps = "watchAllApps"
        static let mutedApps = "mutedApps"          // [String] bundle IDs
        static let followMouseScreen = "followMouseScreen"
        static let hoverToOpen = "hoverToOpen"
        static let hideInFullscreen = "hideInFullscreen"
        static let idleInfo = "idleInfo"
        static let islandStyle = "islandStyle"      // "pill" | "notch"
        static let islandSize = "islandSize"        // "small" | "medium" | "large"
        // Mac features
        static let batteryAlerts = "batteryAlerts"
        static let volumeHUD = "volumeHUD"
        static let capsLockHUD = "capsLockHUD"
        static let micIndicator = "micIndicator"
        static let deviceAlerts = "deviceAlerts"
        static let downloadAlerts = "downloadAlerts"
        static let clipboardHistory = "clipboardHistory"
        static let showWeather = "showWeather"
        static let focusMinutes = "focusMinutes"
        static let breakMinutes = "breakMinutes"
        // Integrations
        static let localAPI = "localAPI"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.showMedia: true,
            Key.showCalendar: true,
            Key.showInbox: true,
            Key.showShelf: true,
            Key.showTimer: true,
            Key.showSystem: true,
            Key.showShortcuts: true,
            Key.meetingPopup: true,
            Key.messageAlerts: true,
            Key.alertSound: true,
            Key.mailDetails: true,
            Key.watchAllApps: false,
            Key.mutedApps: [String](),
            Key.followMouseScreen: false,
            Key.hoverToOpen: true,
            Key.hideInFullscreen: true,
            Key.idleInfo: true,
            Key.islandStyle: "pill",
            Key.islandSize: "small",
            Key.batteryAlerts: true,
            Key.volumeHUD: true,
            Key.capsLockHUD: true,
            Key.micIndicator: true,
            Key.deviceAlerts: true,
            Key.downloadAlerts: true,
            Key.clipboardHistory: true,
            Key.showWeather: true,
            Key.focusMinutes: 25,
            Key.breakMinutes: 5,
            Key.localAPI: true,
        ])
    }

    private static var d: UserDefaults { .standard }

    static var showMedia: Bool { d.bool(forKey: Key.showMedia) }
    static var showCalendar: Bool { d.bool(forKey: Key.showCalendar) }
    static var showInbox: Bool { d.bool(forKey: Key.showInbox) }
    static var showShelf: Bool { d.bool(forKey: Key.showShelf) }
    static var showTimer: Bool { d.bool(forKey: Key.showTimer) }
    static var showSystem: Bool { d.bool(forKey: Key.showSystem) }
    static var showShortcuts: Bool { d.bool(forKey: Key.showShortcuts) }
    static var meetingPopup: Bool { d.bool(forKey: Key.meetingPopup) }
    static var messageAlerts: Bool { d.bool(forKey: Key.messageAlerts) }
    static var alertSound: Bool { d.bool(forKey: Key.alertSound) }
    static var mailDetails: Bool { d.bool(forKey: Key.mailDetails) }
    static var watchAllApps: Bool { d.bool(forKey: Key.watchAllApps) }
    static var followMouseScreen: Bool { d.bool(forKey: Key.followMouseScreen) }
    static var hoverToOpen: Bool { d.bool(forKey: Key.hoverToOpen) }
    static var hideInFullscreen: Bool { d.bool(forKey: Key.hideInFullscreen) }
    static var idleInfo: Bool { d.bool(forKey: Key.idleInfo) }
    static var islandStyle: String { d.string(forKey: Key.islandStyle) ?? "pill" }
    static var islandSize: String { d.string(forKey: Key.islandSize) ?? "small" }
    static var batteryAlerts: Bool { d.bool(forKey: Key.batteryAlerts) }
    static var volumeHUD: Bool { d.bool(forKey: Key.volumeHUD) }
    static var capsLockHUD: Bool { d.bool(forKey: Key.capsLockHUD) }
    static var micIndicator: Bool { d.bool(forKey: Key.micIndicator) }
    static var deviceAlerts: Bool { d.bool(forKey: Key.deviceAlerts) }
    static var downloadAlerts: Bool { d.bool(forKey: Key.downloadAlerts) }
    static var clipboardHistory: Bool { d.bool(forKey: Key.clipboardHistory) }
    static var showWeather: Bool { d.bool(forKey: Key.showWeather) }
    static var localAPI: Bool { d.bool(forKey: Key.localAPI) }
    static var focusMinutes: Int { max(d.integer(forKey: Key.focusMinutes), 1) }
    static var breakMinutes: Int { max(d.integer(forKey: Key.breakMinutes), 1) }

    static var mutedApps: Set<String> {
        get { Set(d.stringArray(forKey: Key.mutedApps) ?? []) }
        set { d.set(Array(newValue).sorted(), forKey: Key.mutedApps) }
    }
}
