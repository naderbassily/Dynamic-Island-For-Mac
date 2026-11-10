import AppKit
import SwiftUI
import Network

// MARK: - Apple Shortcuts

/// Lists and runs your Shortcuts (via the built-in `shortcuts` command).
final class ShortcutsService: ObservableObject {
    @Published private(set) var all: [String] = []
    @Published private(set) var running: String?
    @Published var pinned: [String] = UserDefaults.standard.stringArray(forKey: "pinnedShortcuts") ?? [] {
        didSet { UserDefaults.standard.set(pinned, forKey: "pinnedShortcuts") }
    }

    var onAlert: ((IslandAlert) -> Void)?
    private var loadedAt = Date.distantPast

    /// Pinned shortcuts first, then the rest alphabetically.
    var ordered: [String] {
        pinned.filter { all.contains($0) } + all.filter { !pinned.contains($0) }
    }

    func reloadIfStale() {
        guard Date().timeIntervalSince(loadedAt) > 60 else { return }
        loadedAt = Date()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let out = Self.exec(["list"]).output
            let names = out.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            DispatchQueue.main.async { self?.all = names }
        }
    }

    func togglePin(_ name: String) {
        if let i = pinned.firstIndex(of: name) { pinned.remove(at: i) } else { pinned.append(name) }
    }

    func run(_ name: String, input: String? = nil) {
        running = name
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var args = ["run", name]
            var tmp: URL?
            if let input {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("island-\(UUID().uuidString).txt")
                try? input.write(to: url, atomically: true, encoding: .utf8)
                args += ["--input-path", url.path]
                tmp = url
            }
            let result = Self.exec(args)
            if let tmp { try? FileManager.default.removeItem(at: tmp) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.running = nil
                let ok = result.status == 0
                self.onAlert?(IslandAlert(icon: .symbol(ok ? "checkmark.circle.fill" : "xmark.octagon.fill",
                                                        ok ? .green : .red),
                                          title: "Shortcuts", message: name,
                                          detail: ok ? "Done" : "Failed to run",
                                          duration: 2.5, sound: nil, compact: true))
            }
        }
    }

    private static func exec(_ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

// MARK: - Command router (URL scheme + local web API)

/// Commands other apps, scripts and Shortcuts can send to the island.
///
///   dynamicisland://notify?title=Build&body=Finished&icon=hammer.fill&color=34c759&sound=Glass
///   dynamicisland://timer?minutes=10        dynamicisland://timer?action=cancel|pause|pomodoro
///   dynamicisland://open?tab=calendar        dynamicisland://search?q=hello
///   dynamicisland://shelf?path=/Users/me/file.pdf
///   dynamicisland://shortcut?name=Morning
///   dynamicisland://media?action=toggle|next|previous
///
/// The same commands work over HTTP on this Mac only:  curl "http://127.0.0.1:7787/notify?title=Hi"
final class CommandRouter {
    weak var vm: IslandViewModel?
    var timer: TimerService?
    var shelf: ShelfService?
    var shortcuts: ShortcutsService?
    var media: NowPlayingService?

    @discardableResult
    func handle(command: String, params: [String: String]) -> Bool {
        guard let vm else { return false }
        switch command.lowercased() {
        case "notify", "notification", "alert":
            let title = params["title"] ?? "Notification"
            let body = params["body"] ?? params["message"] ?? ""
            let color = params["color"].flatMap { Color(hex: $0) } ?? .blue
            let icon: AlertIcon
            if let app = params["app"] { icon = .app(app) }
            else { icon = .symbol(params["icon"] ?? "bell.fill", color) }
            let duration = params["duration"].flatMap(Double.init) ?? 6
            let sound: String? = params["sound"] == "0" || params["sound"] == "none" ? nil : (params["sound"] ?? "Tink")
            var progress: Double?
            if let p = params["progress"].flatMap(Double.init) { progress = p > 1 ? p / 100 : p }
            vm.post(IslandAlert(icon: icon, title: title, message: body, detail: params["subtitle"] ?? params["detail"] ?? "",
                                progress: progress, tint: color, duration: min(max(duration, 1), 60), sound: sound,
                                kind: params["id"] ?? ""))
        case "timer":
            switch params["action"]?.lowercased() {
            case "cancel", "stop": timer?.cancel()
            case "pause", "resume": timer?.togglePause()
            case "pomodoro", "focus": timer?.startPomodoro()
            default:
                let minutes = params["minutes"].flatMap(Double.init)
                    ?? params["seconds"].flatMap(Double.init).map { $0 / 60 } ?? 5
                timer?.start(minutes: minutes)
            }
        case "open", "show":
            let tab = params["tab"].flatMap { IslandTab(rawValue: $0.lowercased()) }
            vm.expand(tab: tab)
            vm.holdUntil = Date().addingTimeInterval(5)
        case "search":
            vm.toggleSearch()
            if let q = params["q"] ?? params["query"] { vm.search.query = q }
        case "shelf":
            if let path = params["path"] {
                shelf?.add([URL(fileURLWithPath: (path as NSString).expandingTildeInPath)])
            }
        case "shortcut", "shortcuts":
            if let name = params["name"] { shortcuts?.run(name, input: params["input"]) }
        case "media":
            switch params["action"]?.lowercased() {
            case "next": media?.send(.next)
            case "previous", "prev": media?.send(.previous)
            default: media?.send(.toggle)
            }
        case "collapse", "close", "hide":
            vm.collapse()
        default:
            return false
        }
        return true
    }

    func handle(url: URL) {
        guard url.scheme?.lowercased() == "dynamicisland" else { return }
        let command = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        handle(command: command, params: Self.query(url))
    }

    static func query(_ url: URL) -> [String: String] {
        var out: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            out[item.name] = item.value ?? ""
        }
        return out
    }
}

// MARK: - Local web API (127.0.0.1 only)

/// Tiny HTTP server so Home Assistant, cron jobs, build scripts, AI agents… can talk to the island.
/// Accepts GET with query parameters or POST with a JSON body. Bound to this Mac only.
final class IntegrationServer {
    static let port: UInt16 = 7787
    private var listener: NWListener?
    private let router: CommandRouter
    private let queue = DispatchQueue(label: "dynamicisland.http")

    init(router: CommandRouter) { self.router = router }

    func start() {
        guard listener == nil, Prefs.localAPI, let port = NWEndpoint.Port(rawValue: Self.port) else { return }
        let params = NWParameters.tcp
        params.acceptLocalOnly = true
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params, on: port) else { return }
        l.newConnectionHandler = { [weak self] conn in self?.serve(conn) }
        l.stateUpdateHandler = { state in
            if case .failed(let err) = state { NSLog("Local API failed: \(err)") }
        }
        l.start(queue: queue)
        listener = l
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func serve(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self, let data, let text = String(data: data, encoding: .utf8) else { conn.cancel(); return }
            let (status, body) = self.process(text)
            let response = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\n"
                + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    private func process(_ request: String) -> (String, String) {
        let parts = request.components(separatedBy: "\r\n\r\n")
        let head = parts.first ?? ""
        let bodyText = parts.dropFirst().joined(separator: "\r\n\r\n")
        let requestLine = head.components(separatedBy: "\r\n").first ?? ""
        let tokens = requestLine.split(separator: " ")
        guard tokens.count >= 2 else { return ("400 Bad Request", #"{"ok":false}"#) }
        guard let url = URL(string: "http://localhost" + tokens[1]) else { return ("400 Bad Request", #"{"ok":false}"#) }

        var params = CommandRouter.query(url)
        if let json = try? JSONSerialization.jsonObject(with: Data(bodyText.utf8)) as? [String: Any] {
            for (k, v) in json { params[k] = "\(v)" }
        }
        let command = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if command.isEmpty || command == "ping" { return ("200 OK", #"{"ok":true,"app":"Dynamic Island"}"#) }

        var handled = false
        DispatchQueue.main.sync { handled = router.handle(command: command, params: params) }
        return handled ? ("200 OK", #"{"ok":true}"#) : ("404 Not Found", #"{"ok":false,"error":"unknown command"}"#)
    }
}
