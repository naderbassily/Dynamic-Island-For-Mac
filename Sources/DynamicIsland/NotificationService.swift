import AppKit
import SwiftUI
import ApplicationServices

/// A messaging app the island knows about out of the box.
struct KnownApp: Identifiable {
    let bundleIDs: [String]
    let name: String
    var id: String { bundleIDs[0] }

    static let all: [KnownApp] = [
        KnownApp(bundleIDs: ["com.apple.mail"], name: "Mail"),
        KnownApp(bundleIDs: ["com.microsoft.Outlook"], name: "Outlook"),
        KnownApp(bundleIDs: ["com.microsoft.teams2", "com.microsoft.teams"], name: "Microsoft Teams"),
        KnownApp(bundleIDs: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"], name: "WhatsApp"),
        KnownApp(bundleIDs: ["com.apple.MobileSMS"], name: "Messages"),
        KnownApp(bundleIDs: ["com.tinyspeck.slackmacgap"], name: "Slack"),
        KnownApp(bundleIDs: ["ru.keepcoder.Telegram", "org.telegram.desktop"], name: "Telegram"),
        KnownApp(bundleIDs: ["com.hnc.Discord"], name: "Discord"),
        KnownApp(bundleIDs: ["org.whispersystems.signal-desktop"], name: "Signal"),
        KnownApp(bundleIDs: ["com.readdle.smartemail-Mac", "com.readdle.SparkDesktop"], name: "Spark"),
        KnownApp(bundleIDs: ["com.google.Chrome.app.gmail"], name: "Gmail"),
    ]

    /// Maps every alias bundle ID to the app's main ID (used for mute settings).
    static let canonical: [String: String] = {
        var map: [String: String] = [:]
        for app in all { for b in app.bundleIDs { map[b] = app.id } }
        return map
    }()
}

/// An app with an unread badge on its Dock icon.
struct BadgeItem: Identifiable, Equatable {
    let id: String          // bundle ID
    let name: String
    let count: Int
    let label: String       // the raw badge text, e.g. "3", "99+", "•"
}

struct MailItem: Identifiable, Equatable {
    let id: Int
    let sender: String
    let subject: String
}

enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage {
        if let img = cache[bundleID] { return img }
        let img: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            img = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            img = NSImage(systemSymbolName: "app.badge", accessibilityDescription: nil) ?? NSImage()
        }
        cache[bundleID] = img
        return img
    }

    static func open(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Watches for new messages and emails.
///
/// macOS does not let apps read other apps' notifications, so the island uses two
/// public routes instead:
///  • Unread badges on Dock icons (Outlook, Teams, WhatsApp, Slack, Messages…), read with
///    the Accessibility API. Needs Accessibility permission.
///  • Apple Mail's AppleScript dictionary, which gives the sender and subject of new emails.
final class NotificationService: ObservableObject {
    @Published private(set) var badges: [BadgeItem] = []
    @Published private(set) var recentMail: [MailItem] = []
    @Published private(set) var mailUnread = 0
    @Published private(set) var axTrusted = AXIsProcessTrusted()

    /// Called on the main thread whenever something new arrives.
    var onAlert: ((IslandAlert) -> Void)?

    private let queue = DispatchQueue(label: "dynamicisland.notifications", qos: .utility)
    private var badgeTimer: Timer?
    private var mailTimer: Timer?
    private var lastCounts: [String: Int] = [:]
    private var badgesSeeded = false
    private var seenMail = Set<Int>()
    private var mailSeeded = false
    private var mailWorks = false

    var totalUnread: Int { badges.reduce(0) { $0 + $1.count } }

    func start() {
        guard badgeTimer == nil else { return }
        pollBadges()
        pollMail()
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.pollBadges() }
        mailTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.pollMail() }
    }

    /// Shows the system prompt and opens the Accessibility settings pane.
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func open(_ badge: BadgeItem) { AppIcons.open(bundleID: badge.id) }

    func open(_ mail: MailItem) {
        AppIcons.open(bundleID: "com.apple.mail")
        queue.async {
            let src = "tell application id \"com.apple.mail\" to open (first message of inbox whose id is \(mail.id))"
            var err: NSDictionary?
            NSAppleScript(source: src)?.executeAndReturnError(&err)
        }
    }

    // MARK: - Dock badges

    private func pollBadges() {
        let trusted = AXIsProcessTrusted()
        if trusted != axTrusted { axTrusted = trusted }
        guard trusted, Prefs.showInbox else {
            if !badges.isEmpty { badges = [] }
            return
        }
        let watchAll = Prefs.watchAllApps
        let muted = Prefs.mutedApps
        queue.async { [weak self] in
            let raw = Self.readDockBadges()
            let filtered = raw.filter { item in
                let canon = KnownApp.canonical[item.id] ?? item.id
                if muted.contains(canon) { return false }
                return watchAll || KnownApp.canonical[item.id] != nil
            }
            DispatchQueue.main.async { self?.applyBadges(filtered) }
        }
    }

    private func applyBadges(_ new: [BadgeItem]) {
        let sorted = new.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        if sorted != badges { badges = sorted }

        var counts: [String: Int] = [:]
        for b in sorted { counts[b.id] = b.count }
        defer { lastCounts = counts; badgesSeeded = true }
        guard badgesSeeded, Prefs.messageAlerts else { return }

        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        for b in sorted {
            let old = lastCounts[b.id] ?? 0
            guard b.count > old, b.id != frontmost else { continue }
            // Apple Mail gets a richer alert (sender + subject) from pollMail().
            if b.id == "com.apple.mail" && mailWorks && Prefs.mailDetails { continue }
            let diff = b.count - old
            let msg = diff == 1 ? "New message" : "\(diff) new messages"
            onAlert?(IslandAlert(icon: .app(b.id), title: b.name, message: msg,
                                 detail: "\(b.count) unread", tab: .inbox))
        }
    }

    private static func readDockBadges() -> [BadgeItem] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return [] }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        var out: [BadgeItem] = []
        for list in children(of: app) {
            for item in children(of: list) {
                guard let label = axString(item, "AXStatusLabel"), !label.isEmpty else { continue }
                guard let url = axURL(item, "AXURL"),
                      let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
                let name = axString(item, kAXTitleAttribute as String) ?? url.deletingPathExtension().lastPathComponent
                let digits = label.filter(\.isNumber)
                let count = max(Int(digits) ?? 1, 1)
                out.append(BadgeItem(id: bundleID, name: name, count: count, label: label))
            }
        }
        return out
    }

    private static func children(of el: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &value) == .success
        else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private static func axString(_ el: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func axURL(_ el: AXUIElement, _ attr: String) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return (value as? NSURL) as URL?
    }

    // MARK: - Apple Mail

    private static let mailScript = """
    tell application id "com.apple.mail"
        return {id, sender, subject} of (every message of inbox whose read status is false)
    end tell
    """

    private func pollMail() {
        guard Prefs.showInbox, Prefs.mailDetails,
              !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty
        else {
            if !recentMail.isEmpty { recentMail = [] }
            if mailUnread != 0 { mailUnread = 0 }
            return
        }
        queue.async { [weak self] in
            var err: NSDictionary?
            guard let result = NSAppleScript(source: Self.mailScript)?.executeAndReturnError(&err),
                  err == nil, result.numberOfItems >= 3,
                  let ids = result.atIndex(1), let senders = result.atIndex(2), let subjects = result.atIndex(3)
            else {
                DispatchQueue.main.async { self?.mailWorks = false }
                return
            }
            var items: [MailItem] = []
            let n = ids.numberOfItems
            if n > 0 {
                for i in 1...n {
                    let id = Int(ids.atIndex(i)?.int32Value ?? 0)
                    let sender = Self.cleanSender(senders.atIndex(i)?.stringValue ?? "")
                    let subject = subjects.atIndex(i)?.stringValue ?? ""
                    items.append(MailItem(id: id, sender: sender,
                                          subject: subject.isEmpty ? "(no subject)" : subject))
                }
            }
            items.sort { $0.id > $1.id }   // higher id ≈ newer
            DispatchQueue.main.async { self?.applyMail(items) }
        }
    }

    private func applyMail(_ items: [MailItem]) {
        mailWorks = true
        let top = Array(items.prefix(8))
        if top != recentMail { recentMail = top }
        if items.count != mailUnread { mailUnread = items.count }

        let ids = Set(items.map(\.id))
        let fresh = items.filter { !seenMail.contains($0.id) }
        seenMail.formUnion(ids)
        defer { mailSeeded = true }
        guard mailSeeded, Prefs.messageAlerts, let newest = fresh.first,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.mail" else { return }
        let title = fresh.count == 1 ? "Mail" : "Mail · \(fresh.count) new emails"
        onAlert?(IslandAlert(icon: .app("com.apple.mail"), title: title,
                             message: newest.sender, detail: newest.subject, tab: .inbox))
    }

    /// "Jane Doe <jane@x.com>" → "Jane Doe"
    private static func cleanSender(_ s: String) -> String {
        if let r = s.range(of: " <") {
            return String(s[..<r.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
    }
}
