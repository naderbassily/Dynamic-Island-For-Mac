import AppKit
import SwiftUI

// MARK: - File shelf + finished downloads

/// Drag files onto the island to keep them handy, drag them out again, or AirDrop them.
/// Also watches ~/Downloads and announces finished downloads.
final class ShelfService: ObservableObject {
    @Published private(set) var items: [URL] = []
    @Published private(set) var recentDownloads: [URL] = []

    var onAlert: ((IslandAlert) -> Void)?

    private static let storeKey = "shelfItems"
    private var watcher: DispatchSourceFileSystemObject?
    private var known = Set<String>()
    private var pending = Set<String>()
    private let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.storeKey) ?? []
        items = saved.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: Shelf

    func add(_ urls: [URL]) {
        for u in urls where !items.contains(u) { items.append(u) }
        save()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func copy(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.path), forKey: Self.storeKey)
    }

    // MARK: Downloads watcher

    func startWatchingDownloads() {
        guard watcher == nil, Prefs.downloadAlerts else { return }
        known = Set(listDownloads())
        let fd = Darwin.open(downloads.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename],
                                                            queue: .main)
        src.setEventHandler { [weak self] in self?.downloadsChanged() }
        src.setCancelHandler { Darwin.close(fd) }
        src.resume()
        watcher = src
    }

    private func listDownloads() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: downloads.path)) ?? []
    }

    private static let partialSuffixes = [".crdownload", ".download", ".part", ".partial", ".tmp", ".opdownload"]

    private func downloadsChanged() {
        let now = listDownloads()
        let fresh = now.filter { !known.contains($0) }
        known = Set(now)
        for name in fresh {
            guard !name.hasPrefix("."), !Self.partialSuffixes.contains(where: { name.hasSuffix($0) }) else { continue }
            pending.insert(name)
            confirmWhenStable(name, lastSize: -1)
        }
    }

    /// Waits until the file size stops changing before announcing it.
    private func confirmWhenStable(_ name: String, lastSize: Int64, attempts: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let url = self.downloads.appendingPathComponent(name)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
                self.pending.remove(name); return
            }
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            if size != lastSize && attempts < 20 {
                self.confirmWhenStable(name, lastSize: size, attempts: attempts + 1)
                return
            }
            self.pending.remove(name)
            self.recentDownloads.removeAll { $0 == url }
            self.recentDownloads.insert(url, at: 0)
            if self.recentDownloads.count > 5 { self.recentDownloads.removeLast() }
            guard Prefs.downloadAlerts else { return }
            self.onAlert?(IslandAlert(icon: .file(url.path), title: "Download complete", message: name,
                                      detail: formatBytes(Double(size)), duration: 5, sound: "Pop", tab: .shelf))
        }
    }
}

// MARK: - Clipboard history

struct ClipItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let date: Date
}

/// Remembers the last 25 things you copied (text only). Skips passwords from password managers.
final class ClipboardService: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var ignoreNext = false

    private static let concealed: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("com.agilebits.onepassword"),
    ]

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.check() }
    }

    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        if ignoreNext { ignoreNext = false; return }
        guard Prefs.clipboardHistory else { return }
        if let types = pb.types, types.contains(where: { Self.concealed.contains($0) }) { return }
        guard let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count < 20_000 else { return }
        items.removeAll { $0.text == text }
        items.insert(ClipItem(text: text, date: Date()), at: 0)
        if items.count > 25 { items.removeLast(items.count - 25) }
    }

    func copy(_ item: ClipItem) {
        ignoreNext = true
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
        items.removeAll { $0 == item }
        items.insert(ClipItem(text: item.text, date: Date()), at: 0)
    }

    func clear() { items.removeAll() }
}
