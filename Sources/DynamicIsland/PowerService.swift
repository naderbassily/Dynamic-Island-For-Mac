import AppKit
import SwiftUI
import IOKit.ps

struct BatteryState: Equatable {
    var percent: Int
    var pluggedIn: Bool
    var charging: Bool
    var charged: Bool
    /// Minutes until empty (on battery) or full (charging); nil while macOS is still estimating.
    var minutesLeft: Int?
    var adapterWatts: Int?

    var symbol: String {
        if pluggedIn { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var color: Color {
        if pluggedIn { return .green }
        if percent <= 10 { return .red }
        if percent <= 20 { return .orange }
        return .white
    }

    var statusText: String {
        if charged || (pluggedIn && percent >= 100) { return "Fully charged" }
        if charging {
            if let m = minutesLeft { return "Full in \(formatMinutes(m))" }
            return "Charging"
        }
        if pluggedIn { return "Plugged in, not charging" }
        if let m = minutesLeft { return "\(formatMinutes(m)) left" }
        return "On battery"
    }
}

/// Battery & charging (MacBook), Low Power Mode and thermal warnings (any Mac).
final class PowerService: ObservableObject {
    @Published private(set) var battery: BatteryState?
    @Published private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published private(set) var thermal = ProcessInfo.processInfo.thermalState

    var onAlert: ((IslandAlert) -> Void)?

    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var warned20 = false
    private var warned10 = false

    var hasBattery: Bool { battery != nil }

    func start() {
        battery = Self.read()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let me = Unmanaged<PowerService>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { me.refresh() }
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            source = src
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }

        let nc = NotificationCenter.default
        nc.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.lowPowerChanged()
        }
        nc.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.thermalChanged()
        }
    }

    // MARK: Changes

    private func refresh() {
        let old = battery
        let new = Self.read()
        if new != battery { battery = new }
        guard let new, let old, Prefs.batteryAlerts else { return }

        if new.pluggedIn && !old.pluggedIn {
            var detail = new.statusText
            if let w = new.adapterWatts { detail += " · \(w)W" }
            post(IslandAlert(icon: .symbol("bolt.fill", .green), title: "Charging", message: "\(new.percent)%",
                             detail: detail, progress: Double(new.percent) / 100, tint: .green,
                             duration: 3.5, sound: "Pop", kind: "power"))
            warned20 = false; warned10 = false
        } else if !new.pluggedIn && old.pluggedIn {
            post(IslandAlert(icon: .symbol(new.symbol, new.color), title: "On battery", message: "\(new.percent)%",
                             detail: new.statusText, progress: Double(new.percent) / 100, tint: new.color,
                             duration: 3.5, sound: nil, kind: "power"))
        } else if new.pluggedIn && (new.charged || new.percent >= 100) && !(old.charged || old.percent >= 100) {
            post(IslandAlert(icon: .symbol("battery.100percent.bolt", .green), title: "Battery", message: "Fully charged",
                             detail: "You can unplug your Mac", progress: 1, tint: .green, kind: "power"))
        }

        if !new.pluggedIn {
            if new.percent <= 10 && !warned10 {
                warned10 = true; warned20 = true
                post(IslandAlert(icon: .symbol("battery.0percent", .red), title: "Battery very low",
                                 message: "\(new.percent)% remaining", detail: "Plug in your Mac soon",
                                 progress: Double(new.percent) / 100, tint: .red, duration: 8, sound: "Basso",
                                 kind: "power"))
            } else if new.percent <= 20 && !warned20 {
                warned20 = true
                post(IslandAlert(icon: .symbol("battery.25percent", .orange), title: "Low battery",
                                 message: "\(new.percent)% remaining", detail: new.statusText,
                                 progress: Double(new.percent) / 100, tint: .orange, duration: 6, sound: "Funk",
                                 kind: "power"))
            }
        }
    }

    private func lowPowerChanged() {
        let on = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard on != lowPowerMode else { return }
        lowPowerMode = on
        guard Prefs.batteryAlerts else { return }
        post(IslandAlert(icon: .symbol("leaf.fill", on ? .yellow : .gray), title: "Low Power Mode",
                         message: on ? "On" : "Off", duration: 2.5, sound: nil, kind: "lowpower", compact: true))
    }

    private func thermalChanged() {
        let t = ProcessInfo.processInfo.thermalState
        let old = thermal
        thermal = t
        guard Prefs.batteryAlerts, t.rawValue > old.rawValue, t == .serious || t == .critical else { return }
        post(IslandAlert(icon: .symbol("thermometer.high", .red), title: "Your Mac is running hot",
                         message: t == .critical ? "Critical temperature" : "Performance may slow down",
                         detail: "Close heavy apps or give it some air", duration: 8, sound: "Funk"))
    }

    private func post(_ a: IslandAlert) { onAlert?(a) }

    // MARK: Reading IOKit power sources

    static func read() -> BatteryState? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  (desc["Type"] as? String) == "InternalBattery" else { continue }
            let current = desc["Current Capacity"] as? Int ?? 0
            let maxCap = desc["Max Capacity"] as? Int ?? 100
            let percent = maxCap > 0 ? Int((Double(current) / Double(maxCap) * 100).rounded()) : current
            let plugged = (desc["Power Source State"] as? String) == "AC Power"
            let charging = desc["Is Charging"] as? Bool ?? false
            let charged = desc["Is Charged"] as? Bool ?? false
            let key = charging ? "Time to Full Charge" : "Time to Empty"
            var minutes = desc[key] as? Int
            if let m = minutes, m <= 0 || m > 24 * 60 { minutes = nil }
            var watts: Int?
            if plugged, let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
                watts = details["Watts"] as? Int
            }
            return BatteryState(percent: min(max(percent, 0), 100), pluggedIn: plugged, charging: charging,
                                charged: charged, minutesLeft: (plugged && !charging) ? nil : minutes,
                                adapterWatts: watts)
        }
        return nil
    }
}
