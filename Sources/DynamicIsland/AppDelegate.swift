import AppKit
import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// The panel is always this big; only the black island inside it changes size.
    /// Mouse events outside the island pass straight through to the apps underneath.
    static let panelSize = NSSize(width: 660, height: 380)

    private var panel: IslandPanel!
    private var vm: IslandViewModel!
    private var services: IslandServices!
    private var router = CommandRouter()
    private var server: IntegrationServer?
    private var statusItem: NSStatusItem!
    private var loginItem: NSMenuItem!
    private var hotKey: HotKey?
    private var trackTimer: Timer?
    private var hoverStart: Date?
    private var leaveStart: Date?
    private var previousApp: NSRunningApplication?
    private var clickMonitor: Any?
    private var settingsWindow: NSWindow?
    private var currentScreenFrame: NSRect = .zero
    private var lastFullscreenCheck = Date.distantPast
    private var pendingURLs: [URL] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        let s = IslandServices()
        services = s
        vm = IslandViewModel(services: s)
        vm.onRequestKey = { [weak self] in self?.makePanelKey() }
        vm.onDismiss = { [weak self] in self?.restoreFocus() }

        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize))
        let root = IslandRootView()
            .environmentObject(vm)
            .environmentObject(s.nowPlaying)
            .environmentObject(s.calendar)
            .environmentObject(s.search)
            .environmentObject(s.notifications)
            .environmentObject(s.power)
            .environmentObject(s.audio)
            .environmentObject(s.devices)
            .environmentObject(s.timer)
            .environmentObject(s.shelf)
            .environmentObject(s.clipboard)
            .environmentObject(s.weather)
            .environmentObject(s.stats)
            .environmentObject(s.shortcuts)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: Self.panelSize)
        panel.contentView = host
        positionPanel()
        panel.orderFrontRegardless()

        s.nowPlaying.start()
        s.calendar.start()
        s.notifications.start()
        s.power.start()
        s.audio.start()
        s.devices.start()
        s.clipboard.start()
        s.shelf.startWatchingDownloads()
        s.weather.start()

        router.vm = vm
        router.timer = s.timer
        router.shelf = s.shelf
        router.shortcuts = s.shortcuts
        router.media = s.nowPlaying
        let server = IntegrationServer(router: router)
        server.start()
        self.server = server
        pendingURLs.forEach { router.handle(url: $0) }
        pendingURLs.removeAll()

        setupStatusItem()

        // ⌥ Space opens the search (⌘ Space stays with Spotlight).
        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak self] in
            self?.vm.toggleSearch()
        }

        let timer = Timer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        trackTimer = timer

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)

        // A click in any other app closes an open island.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.handleOutsideClick() }
        }
    }

    /// dynamicisland://… links (from Shortcuts, scripts, Raycast, Alfred, other apps).
    func application(_ application: NSApplication, open urls: [URL]) {
        guard vm != nil else { pendingURLs += urls; return }
        urls.forEach { router.handle(url: $0) }
    }

    func applicationDidResignActive(_ notification: Notification) {
        // The user clicked into another app: close, and don't steal focus back.
        if vm.pinned { previousApp = nil; vm.collapse() }
    }

    @objc private func settingsChanged() {
        // Start/stop optional services when their switches change.
        if Prefs.localAPI { server?.start() } else { server?.stop() }
        services.devices.start()
        services.shelf.startWatchingDownloads()
        services.weather.start()
    }

    // MARK: - Placement

    /// The primary display, or (if enabled in Settings) the display the mouse is on.
    private var targetScreen: NSScreen? {
        if Prefs.followMouseScreen {
            let mouse = NSEvent.mouseLocation
            if let s = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) { return s }
        }
        return NSScreen.screens.first ?? NSScreen.main
    }

    private func positionPanel() {
        guard let screen = targetScreen else { return }
        currentScreenFrame = screen.frame
        let notch = screen.notchSize
        if vm.notch != notch { vm.notch = notch }
        let bar = screen.frame.maxY - screen.visibleFrame.maxY
        let menuBar = bar > 10 ? bar : (NSStatusBar.system.thickness > 0 ? NSStatusBar.system.thickness : 24)
        if vm.menuBarHeight != menuBar { vm.menuBarHeight = menuBar }
        let s = Self.panelSize
        let frame = NSRect(x: screen.frame.midX - s.width / 2,
                           y: screen.frame.maxY - s.height,
                           width: s.width, height: s.height)
        panel.setFrame(frame, display: true)
    }

    @objc private func screensChanged() { positionPanel() }

    // MARK: - Hover tracking

    @objc private func tick() {
        guard let screen = targetScreen else { return }
        if screen.frame != currentScreenFrame && !vm.expanded { positionPanel() }
        vm.checkCapsLock()
        checkFullscreen()

        let size = vm.size
        let frame = currentScreenFrame
        let islandRect = NSRect(x: frame.midX - size.width / 2,
                                y: frame.maxY - vm.topGap - size.height,
                                width: size.width, height: size.height + vm.topGap).insetBy(dx: -6, dy: -6)
        let hidden = vm.hiddenForFullscreen && !vm.expanded && vm.alert == nil
        let inside = !hidden && islandRect.contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside

        let now = Date()
        let dragging = NSEvent.pressedMouseButtons & 1 != 0
        if inside {
            leaveStart = nil
            if !vm.expanded && (Prefs.hoverToOpen || dragging) {
                if let start = hoverStart {
                    if now.timeIntervalSince(start) > 0.15 {
                        // Dragging a file onto the island opens the shelf.
                        vm.expand(tab: dragging && Prefs.showShelf ? .shelf : nil)
                    }
                } else {
                    hoverStart = now
                }
            }
        } else {
            hoverStart = nil
            if vm.expanded && !vm.isHeld {
                if let start = leaveStart {
                    if now.timeIntervalSince(start) > 0.35 { vm.collapse(); leaveStart = nil }
                } else {
                    leaveStart = now
                }
            }
        }
    }

    /// Hides the idle pill while a full-screen app (video, game, slides) is in front.
    private func checkFullscreen() {
        let now = Date()
        guard now.timeIntervalSince(lastFullscreenCheck) > 1 else { return }
        lastFullscreenCheck = now
        guard Prefs.hideInFullscreen,
              let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            if vm.hiddenForFullscreen && !Prefs.hideInFullscreen { vm.hiddenForFullscreen = false }
            return
        }
        let screenSize = currentScreenFrame.size
        var full = false
        if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] {
            for w in list {
                guard (w[kCGWindowOwnerPID as String] as? Int32) == front.processIdentifier,
                      (w[kCGWindowLayer as String] as? Int) == 0,
                      let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
                if (b["Width"] ?? 0) >= screenSize.width && (b["Height"] ?? 0) >= screenSize.height {
                    full = true
                    break
                }
            }
        }
        if full != vm.hiddenForFullscreen { vm.hiddenForFullscreen = full }
    }

    private func handleOutsideClick() {
        if vm.expanded { previousApp = nil; vm.collapse() }
    }

    // MARK: - Keyboard focus (for search)

    private func makePanelKey() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func restoreFocus() {
        panel.orderFrontRegardless()
        if let app = previousApp {
            app.activate(options: [])
            previousApp = nil
        }
    }

    // MARK: - Menu bar item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Dynamic Island")

        let menu = NSMenu()
        menu.delegate = self
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let header = NSMenuItem(title: "Dynamic Island \(version)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Search…   ⌥Space", action: #selector(openSearch), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Start 25-min Focus", action: #selector(startFocus), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Refresh Calendar & Weather", action: #selector(refreshCalendar), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Dynamic Island", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView()
                .environmentObject(services.notifications)
                .environmentObject(services.power)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 640),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "Dynamic Island Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view)
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSearch() { vm.toggleSearch() }
    @objc private func startFocus() { services.timer.startPomodoro() }
    @objc private func refreshCalendar() {
        services.calendar.start()
        services.weather.refresh()
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Launch at login failed: \(error)")
        }
    }
}

// MARK: - Panel

final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovable = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3) // above the menu bar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // Allow the window to sit on top of the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// MARK: - Global hot key (Carbon – needs no Accessibility permission)

final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var installed = false
    private var ref: EventHotKeyRef?

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        let id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.handlers[id] = handler
        HotKey.installHandlerIfNeeded()
        let hkID = EventHotKeyID(signature: OSType(0x4459_4E49), id: id) // 'DYNI'
        RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
    }

    deinit { if let ref { UnregisterEventHotKey(ref) } }

    private static func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async { HotKey.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
