import AppKit
import SwiftUI
import ApplicationServices

enum MediaSource: String {
    case music = "Apple Music"
    case spotify = "Spotify"
    case youtube = "YouTube"

    var color: Color {
        switch self {
        case .music: return Color(red: 0.98, green: 0.24, blue: 0.36)
        case .spotify: return Color(red: 0.12, green: 0.84, blue: 0.38)
        case .youtube: return Color(red: 1.0, green: 0.15, blue: 0.15)
        }
    }

    var symbol: String {
        switch self {
        case .music: return "music.note"
        case .spotify: return "waveform"
        case .youtube: return "play.rectangle.fill"
        }
    }
}

enum MediaCommand { case toggle, next, previous }

struct MediaInfo: Equatable {
    var source: MediaSource
    var title: String
    var artist: String
    var isPlaying: Bool
    var artworkURL: URL?
    var browserID: String?          // for YouTube: which browser
    var pageURL: String?            // for YouTube: which tab
    var needsJSPermission = false   // browser blocks "JavaScript from Apple Events"
    var trackKey: String { "\(source.rawValue)|\(title)|\(artist)" }
}

/// Polls Music, Spotify and YouTube tabs (Chrome, Edge, Brave, Safari) via AppleScript.
/// (Apple locked the system-wide "Now Playing" API to its own apps in macOS 15.4,
/// so talking to each player directly is the reliable route.)
final class NowPlayingService: ObservableObject {
    @Published private(set) var info: MediaInfo?
    @Published private(set) var artwork: NSImage?

    private struct Browser { let id: String; let isSafari: Bool }
    private static let musicID = "com.apple.Music"
    private static let spotifyID = "com.spotify.client"
    private static let browsers = [
        Browser(id: "com.google.Chrome", isSafari: false),
        Browser(id: "com.microsoft.edgemac", isSafari: false),
        Browser(id: "com.brave.Browser", isSafari: false),
        Browser(id: "com.apple.Safari", isSafari: true),
    ]

    private let queue = DispatchQueue(label: "dynamicisland.nowplaying", qos: .utility)
    private var timer: Timer?
    private var lastArtKey = ""
    private var scriptCache: [String: NSAppleScript] = [:]   // only touched on `queue`

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
    }

    func poll() {
        guard Prefs.showMedia else {
            if info != nil { apply(nil) }
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            let found = self.fetchBest()
            DispatchQueue.main.async { self.apply(found) }
        }
    }

    // MARK: - Commands

    func send(_ cmd: MediaCommand) {
        guard let current = info else { return }
        if cmd == .toggle { info?.isPlaying.toggle() }   // optimistic UI
        queue.async { [weak self] in
            guard let self else { return }
            switch current.source {
            case .music, .spotify:
                let id = current.source == .music ? Self.musicID : Self.spotifyID
                let verb: String
                switch cmd {
                case .toggle: verb = "playpause"
                case .next: verb = "next track"
                case .previous: verb = "previous track"
                }
                _ = self.run("tell application id \"\(id)\" to \(verb)")
            case .youtube:
                let js: String
                switch cmd {
                case .toggle: js = Self.jsToggle
                case .next: js = Self.jsNext
                case .previous: js = Self.jsPrevious
                }
                let ok = self.runYouTube(js: js, info: current)
                if !ok { Self.postMediaKey(cmd) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.poll() }
        }
    }

    /// Brings the player app (or browser) to the front.
    func revealSource() {
        guard let info else { return }
        let id: String
        switch info.source {
        case .music: id = Self.musicID
        case .spotify: id = Self.spotifyID
        case .youtube: id = info.browserID ?? "com.google.Chrome"
        }
        NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.activate(options: [])
    }

    func openApp(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    // MARK: - Applying results

    private func apply(_ new: MediaInfo?) {
        if info != new { info = new }
        guard let new else {
            artwork = nil
            lastArtKey = ""
            return
        }
        if new.trackKey != lastArtKey {
            lastArtKey = new.trackKey
            artwork = nil
            loadArtwork(for: new)
        }
    }

    private func loadArtwork(for m: MediaInfo) {
        let key = m.trackKey
        if let url = m.artworkURL {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    if self?.lastArtKey == key { self?.artwork = img }
                }
            }.resume()
        } else if m.source == .music {
            queue.async { [weak self] in
                guard let self else { return }
                let data = self.run("tell application id \"\(Self.musicID)\" to get raw data of artwork 1 of current track")?.data
                let img = data.flatMap { NSImage(data: $0) }
                DispatchQueue.main.async { if self.lastArtKey == key { self.artwork = img } }
            }
        }
    }

    // MARK: - Fetching (runs on `queue`)

    private func isRunning(_ id: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    private func fetchBest() -> MediaInfo? {
        var candidates: [MediaInfo] = []
        if isRunning(Self.musicID), let m = fetchPlayer(id: Self.musicID, source: .music) { candidates.append(m) }
        if isRunning(Self.spotifyID), let s = fetchPlayer(id: Self.spotifyID, source: .spotify) { candidates.append(s) }
        for b in Self.browsers where isRunning(b.id) {
            if let y = fetchYouTube(b) { candidates.append(y) }
        }
        return candidates.first(where: { $0.isPlaying }) ?? candidates.first
    }

    private func fetchPlayer(id: String, source: MediaSource) -> MediaInfo? {
        let artLine = source == .spotify ? " & \"|~|\" & (artwork url of t)" : ""
        let script = """
        tell application id "\(id)"
            if player state is stopped then return ""
            set t to current track
            return (name of t) & "|~|" & (artist of t) & "|~|" & (player state as string)\(artLine)
        end tell
        """
        guard let out = run(script)?.stringValue, !out.isEmpty else { return nil }
        let p = out.components(separatedBy: "|~|")
        guard p.count >= 3 else { return nil }
        var artURL: URL?
        if p.count >= 4 { artURL = URL(string: p[3]) }
        return MediaInfo(source: source, title: p[0], artist: p[1], isPlaying: p[2] == "playing", artworkURL: artURL)
    }

    private static let jsState = "(function(){var v=document.querySelector('video');var s=v?(v.paused?'paused':'playing'):'none';var a='';var e=document.querySelector('ytmusic-player-bar .byline')||document.querySelector('#owner #channel-name a')||document.querySelector('ytd-channel-name a');if(e){a=e.textContent.trim().split('•')[0].trim();}return s+'^^'+a;})()"
    private static let jsToggle = "(function(){var v=document.querySelector('video');if(!v){return 'none';}if(v.paused){v.play();}else{v.pause();}return 'ok';})()"
    private static let jsNext = "(function(){var b=document.querySelector('ytmusic-player-bar .next-button')||document.querySelector('.ytp-next-button');if(b){b.click();return 'ok';}return 'none';})()"
    private static let jsPrevious = "(function(){var b=document.querySelector('ytmusic-player-bar .previous-button');if(b){b.click();return 'ok';}var v=document.querySelector('video');if(v){v.currentTime=0;return 'ok';}return 'none';})()"

    private static let ytMatch = "((u contains \"youtube.com/watch\") or (u contains \"music.youtube.com\") or (u contains \"youtube.com/shorts\"))"

    private func jsCall(_ js: String, tab: String, safari: Bool) -> String {
        safari ? "do JavaScript \"\(js)\" in \(tab)" : "execute \(tab) javascript \"\(js)\""
    }

    private func fetchYouTube(_ b: Browser) -> MediaInfo? {
        let titleProp = b.isSafari ? "name" : "title"
        let script = """
        tell application id "\(b.id)"
            set firstHit to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set u to ""
                    try
                        set u to URL of t
                    end try
                    if u is missing value then set u to ""
                    if \(Self.ytMatch) then
                        set st to "unknown"
                        try
                            set st to \(jsCall(Self.jsState, tab: "t", safari: b.isSafari))
                        end try
                        set hit to (\(titleProp) of t) & "|~|" & u & "|~|" & st
                        if st starts with "playing" then return hit
                        if firstHit is "" then set firstHit to hit
                    end if
                end repeat
            end repeat
            return firstHit
        end tell
        """
        guard let out = run(script)?.stringValue, !out.isEmpty else { return nil }
        let p = out.components(separatedBy: "|~|")
        guard p.count >= 3 else { return nil }

        var title = p[0]
        if let r = title.range(of: #"^\(\d+\)\s*"#, options: .regularExpression) { title.removeSubrange(r) }
        for suffix in [" - YouTube Music", " - YouTube"] where title.hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count))
        }

        let state = p[2]
        var isPlaying = false
        var artist = ""
        var needsJS = false
        if state == "unknown" {
            needsJS = true
        } else {
            let parts = state.components(separatedBy: "^^")
            isPlaying = parts.first == "playing"
            if parts.count > 1 { artist = parts[1] }
        }
        if artist.isEmpty { artist = "YouTube" }

        return MediaInfo(source: .youtube, title: title, artist: artist, isPlaying: isPlaying,
                         artworkURL: Self.youTubeThumbnail(p[1]), browserID: b.id, pageURL: p[1],
                         needsJSPermission: needsJS)
    }

    private func runYouTube(js: String, info: MediaInfo) -> Bool {
        guard let id = info.browserID else { return false }
        let safari = id == "com.apple.Safari"
        let page = (info.pageURL ?? "").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application id "\(id)"
            set target to missing value
            set exact to false
            repeat with w in windows
                repeat with t in tabs of w
                    set u to ""
                    try
                        set u to URL of t
                    end try
                    if u is missing value then set u to ""
                    if (not exact) and u is "\(page)" then
                        set target to t
                        set exact to true
                    else if target is missing value and \(Self.ytMatch) then
                        set target to t
                    end if
                end repeat
            end repeat
            if target is missing value then return "none"
            return \(jsCall(js, tab: "target", safari: safari))
        end tell
        """
        return run(script)?.stringValue == "ok"
    }

    private static func youTubeThumbnail(_ urlString: String) -> URL? {
        guard let comps = URLComponents(string: urlString) else { return nil }
        var vid = comps.queryItems?.first(where: { $0.name == "v" })?.value
        if vid == nil, comps.path.hasPrefix("/shorts/") {
            vid = comps.path.components(separatedBy: "/").last
        }
        guard let vid, !vid.isEmpty else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(vid)/hqdefault.jpg")
    }

    private func run(_ source: String) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if let cached = scriptCache[source] {
            script = cached
        } else {
            guard let s = NSAppleScript(source: source) else { return nil }
            if scriptCache.count > 64 { scriptCache.removeAll() }
            scriptCache[source] = s
            script = s
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        return error == nil ? result : nil
    }

    // MARK: - Media-key fallback (needs Accessibility permission)

    private static func postMediaKey(_ cmd: MediaCommand) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }
        let key: Int
        switch cmd {
        case .toggle: key = 16    // NX_KEYTYPE_PLAY
        case .next: key = 17      // NX_KEYTYPE_NEXT
        case .previous: key = 18  // NX_KEYTYPE_PREVIOUS
        }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = (key << 16) | ((down ? 0xA : 0xB) << 8)
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                           timestamp: 0, windowNumber: 0, context: nil,
                                           subtype: 8, data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
