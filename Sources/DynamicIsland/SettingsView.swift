import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var notes: NotificationService
    @EnvironmentObject var power: PowerService

    // General
    @AppStorage(Prefs.Key.hoverToOpen) private var hoverToOpen = true
    @AppStorage(Prefs.Key.followMouseScreen) private var followMouseScreen = false
    @AppStorage(Prefs.Key.hideInFullscreen) private var hideInFullscreen = true
    @AppStorage(Prefs.Key.idleInfo) private var idleInfo = true
    @AppStorage(Prefs.Key.alertSound) private var alertSound = true
    @AppStorage(Prefs.Key.islandStyle) private var islandStyle = "pill"
    @AppStorage(Prefs.Key.islandSize) private var islandSize = "small"
    // Tabs
    @AppStorage(Prefs.Key.showMedia) private var showMedia = true
    @AppStorage(Prefs.Key.showCalendar) private var showCalendar = true
    @AppStorage(Prefs.Key.showInbox) private var showInbox = true
    @AppStorage(Prefs.Key.showShelf) private var showShelf = true
    @AppStorage(Prefs.Key.showTimer) private var showTimer = true
    @AppStorage(Prefs.Key.showSystem) private var showSystem = true
    @AppStorage(Prefs.Key.showShortcuts) private var showShortcuts = true
    // Alerts
    @AppStorage(Prefs.Key.meetingPopup) private var meetingPopup = true
    @AppStorage(Prefs.Key.messageAlerts) private var messageAlerts = true
    @AppStorage(Prefs.Key.mailDetails) private var mailDetails = true
    @AppStorage(Prefs.Key.watchAllApps) private var watchAllApps = false
    @AppStorage(Prefs.Key.batteryAlerts) private var batteryAlerts = true
    @AppStorage(Prefs.Key.volumeHUD) private var volumeHUD = true
    @AppStorage(Prefs.Key.capsLockHUD) private var capsLockHUD = true
    @AppStorage(Prefs.Key.micIndicator) private var micIndicator = true
    @AppStorage(Prefs.Key.deviceAlerts) private var deviceAlerts = true
    @AppStorage(Prefs.Key.downloadAlerts) private var downloadAlerts = true
    // Extras
    @AppStorage(Prefs.Key.clipboardHistory) private var clipboardHistory = true
    @AppStorage(Prefs.Key.showWeather) private var showWeather = true
    @AppStorage(Prefs.Key.focusMinutes) private var focusMinutes = 25
    @AppStorage(Prefs.Key.breakMinutes) private var breakMinutes = 5
    @AppStorage(Prefs.Key.localAPI) private var localAPI = true

    @State private var muted: Set<String> = Prefs.mutedApps
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section {
                Picker("Style", selection: $islandStyle) {
                    Text("Floating pill").tag("pill")
                    Text("Attached to top edge").tag("notch")
                }
                .pickerStyle(.segmented)
                Picker("Size", selection: $islandSize) {
                    Text("Small").tag("small")
                    Text("Medium").tag("medium")
                    Text("Large").tag("large")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Look")
            } footer: {
                Text("On a MacBook with a notch, the island always wraps around the notch.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                Toggle("Open when the mouse hovers over the island", isOn: $hoverToOpen)
                Toggle("Show on the display the mouse is on", isOn: $followMouseScreen)
                Toggle("Hide in full-screen apps", isOn: $hideInFullscreen)
                Toggle("Show clock & weather when idle (no notch)", isOn: $idleInfo)
                Toggle("Play sounds", isOn: $alertSound)
                LabeledContent("Search shortcut", value: "⌥ Space")
            }

            Section("Tabs") {
                Toggle("Media (Music, Spotify, YouTube)", isOn: $showMedia)
                Toggle("Calendar & meetings", isOn: $showCalendar)
                Toggle("Inbox (messages & email)", isOn: $showInbox)
                Toggle("Shelf (files & clipboard)", isOn: $showShelf)
                Toggle("Timer & Pomodoro", isOn: $showTimer)
                Toggle("System (CPU, memory, battery, devices)", isOn: $showSystem)
                Toggle("Shortcuts", isOn: $showShortcuts)
            }

            Section("Mac alerts") {
                Toggle(power.hasBattery ? "Charging, low battery & Low Power Mode" : "Low Power Mode & temperature",
                       isOn: $batteryAlerts)
                Toggle("Volume HUD", isOn: $volumeHUD)
                Toggle("Caps Lock HUD", isOn: $capsLockHUD)
                Toggle("Orange dot when the microphone is in use", isOn: $micIndicator)
                Toggle("Bluetooth devices (AirPods, keyboard…) and their battery", isOn: $deviceAlerts)
                Toggle("Finished downloads", isOn: $downloadAlerts)
                Toggle("Pop open 1 minute before a meeting", isOn: $meetingPopup)
            }

            Section {
                Toggle("Banner when a new message arrives", isOn: $messageAlerts)
                Toggle("Sender and subject for Apple Mail", isOn: $mailDetails)
                Toggle("Watch every app with a Dock badge", isOn: $watchAllApps)
                HStack {
                    Text("Accessibility permission")
                    Spacer()
                    if notes.axTrusted {
                        Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Turn On…") { notes.requestAccessibility() }
                    }
                }
                ForEach(KnownApp.all) { app in
                    Toggle(isOn: binding(for: app.id)) {
                        HStack(spacing: 8) {
                            Image(nsImage: AppIcons.icon(for: app.id)).resizable().frame(width: 18, height: 18)
                            Text(app.name)
                        }
                    }
                }
            } header: {
                Text("Messages & email")
            } footer: {
                Text("macOS doesn't let apps read other apps' notifications, so the island watches the unread badges on Dock icons (needs Accessibility). Keep your messaging apps in the Dock.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!showInbox)

            Section("Extras") {
                Toggle("Clipboard history (skips passwords)", isOn: $clipboardHistory)
                Toggle("Weather (uses your location, Open-Meteo)", isOn: $showWeather)
                Stepper("Focus length: \(focusMinutes) min", value: $focusMinutes, in: 5...120, step: 5)
                Stepper("Break length: \(breakMinutes) min", value: $breakMinutes, in: 1...30)
            }

            Section {
                Toggle("Local web API on port \(String(IntegrationServer.port)) (this Mac only)", isOn: $localAPI)
                IntegrationExample(title: "From Terminal or a script",
                                   code: "curl \"http://127.0.0.1:7787/notify?title=Build&body=Done&icon=hammer.fill\"")
                IntegrationExample(title: "From Shortcuts, Raycast, Alfred or any app",
                                   code: "open -g \"dynamicisland://notify?title=Hello&body=World\"")
                IntegrationExample(title: "Start a 10-minute timer",
                                   code: "open -g \"dynamicisland://timer?minutes=10\"")
                Button("Send a test notification") {
                    if let url = URL(string: "dynamicisland://notify?title=It%20works!&body=Integrations%20are%20ready&icon=sparkles&color=af52de") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } header: {
                Text("Integrations")
            } footer: {
                Text("Commands: notify, timer, open, search, shelf, shortcut, media, collapse. See the README for Home Assistant, cron, GitHub Actions and AI-agent recipes.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: version)
                Text("Teams meetings come from macOS Calendar. Add your work account in System Settings ▸ Internet Accounts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 640)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { !muted.contains(id) },
            set: { on in
                if on { muted.remove(id) } else { muted.insert(id) }
                Prefs.mutedApps = muted
            }
        )
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Launch at login failed: \(error)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct IntegrationExample: View {
    let title: String
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .help("Copy")
            }
        }
    }
}
