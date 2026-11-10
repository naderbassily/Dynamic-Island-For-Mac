import AppKit
import SwiftUI
import IOBluetooth
import IOKit

struct PeripheralBattery: Identifiable, Equatable {
    let id: String
    let name: String
    let percent: Int
}

/// Bluetooth connect/disconnect banners (AirPods, headphones, keyboards…) and the battery
/// level of Apple keyboards, mice and trackpads.
final class DeviceService: NSObject, ObservableObject {
    @Published private(set) var connected: [String] = []
    @Published private(set) var peripherals: [PeripheralBattery] = []

    var onAlert: ((IslandAlert) -> Void)?

    private var connectNote: IOBluetoothUserNotification?
    private var disconnectNotes: [String: IOBluetoothUserNotification] = [:]
    private var startedAt = Date()
    private var batteryTimer: Timer?
    private var warnedLow = Set<String>()

    func start() {
        guard Prefs.deviceAlerts, connectNote == nil else { return }
        startedAt = Date()
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self,
                                                 selector: #selector(deviceConnected(_:device:)))
        refreshPeripherals()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            self?.refreshPeripherals()
        }
    }

    // MARK: Bluetooth

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? "Bluetooth device"
        let key = device.addressString ?? name
        if disconnectNotes[key] == nil {
            disconnectNotes[key] = device.register(forDisconnectNotification: self,
                                                   selector: #selector(deviceDisconnected(_:device:)))
        }
        if !connected.contains(name) { connected.append(name) }
        // Connect notifications also fire for devices already connected at launch.
        guard Date().timeIntervalSince(startedAt) > 3, Prefs.deviceAlerts else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.refreshPeripherals() }
        onAlert?(IslandAlert(icon: .symbol(Self.symbol(for: name), .blue), title: "Connected",
                             message: name, duration: 3, sound: "Pop", kind: "bt-\(key)", compact: true))
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? "Bluetooth device"
        let key = device.addressString ?? name
        disconnectNotes[key]?.unregister()
        disconnectNotes[key] = nil
        connected.removeAll { $0 == name }
        guard Prefs.deviceAlerts else { return }
        onAlert?(IslandAlert(icon: .symbol(Self.symbol(for: name), .gray), title: "Disconnected",
                             message: name, duration: 2.5, sound: nil, kind: "bt-\(key)", compact: true))
    }

    static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") || n.contains("headphone") || n.contains("buds") || n.contains("wh-") { return "headphones" }
        if n.contains("keyboard") { return "keyboard" }
        if n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if n.contains("mouse") { return "computermouse" }
        if n.contains("speaker") || n.contains("homepod") || n.contains("jbl") || n.contains("sonos") { return "hifispeaker" }
        if n.contains("controller") || n.contains("xbox") || n.contains("dualsense") { return "gamecontroller" }
        if n.contains("iphone") { return "iphone" }
        if n.contains("ipad") { return "ipad" }
        if n.contains("watch") { return "applewatch" }
        return "dot.radiowaves.left.and.right"
    }

    // MARK: Keyboard / mouse / trackpad battery (IOKit)

    func refreshPeripherals() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = Self.readPeripheralBatteries()
            DispatchQueue.main.async { self?.applyPeripherals(found) }
        }
    }

    private func applyPeripherals(_ list: [PeripheralBattery]) {
        if list != peripherals { peripherals = list }
        guard Prefs.deviceAlerts else { return }
        for p in list where p.percent <= 15 && !warnedLow.contains(p.id) {
            warnedLow.insert(p.id)
            onAlert?(IslandAlert(icon: .symbol(Self.symbol(for: p.name), .orange), title: "Low battery",
                                 message: p.name, detail: "\(p.percent)% remaining", progress: Double(p.percent) / 100,
                                 tint: .orange, sound: "Funk", tab: .system))
        }
        for p in list where p.percent > 30 { warnedLow.remove(p.id) }
    }

    private static func readPeripheralBatteries() -> [PeripheralBattery] {
        var out: [PeripheralBattery] = []
        var seen = Set<String>()
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let pct = property(service, "BatteryPercent") as? Int,
               let name = property(service, "Product") as? String {
                let serial = property(service, "SerialNumber") as? String ?? name
                if seen.insert(serial).inserted {
                    out.append(PeripheralBattery(id: serial, name: name, percent: pct))
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return out.sorted { $0.name < $1.name }
    }

    private static func property(_ service: io_object_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
