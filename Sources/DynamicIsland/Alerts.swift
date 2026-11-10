import AppKit
import SwiftUI

/// What to draw on the left of a banner.
enum AlertIcon: Equatable {
    case app(String)                 // bundle ID → app icon
    case symbol(String, Color)       // SF Symbol name + colour
    case file(String)                // file path → Finder icon
}

/// A banner that drops down from the collapsed island (new message, charging, volume…).
struct IslandAlert: Identifiable, Equatable {
    let id = UUID()
    var icon: AlertIcon
    var title: String
    var message: String
    var detail: String = ""
    /// 0…1 shows a progress bar (battery, volume).
    var progress: Double? = nil
    var tint: Color = .white
    /// How long the banner stays up.
    var duration: TimeInterval = 6
    /// System sound name, or nil for silent.
    var sound: String? = "Tink"
    /// Tab to open if the user hovers the banner.
    var tab: IslandTab? = nil
    /// Banners with the same non-empty kind replace each other (e.g. volume HUD).
    var kind: String = ""
    /// Compact HUD style (shorter, no detail line).
    var compact: Bool = false
}

extension NSScreen {
    /// Size of the camera notch on MacBook displays, or .zero when there is none.
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return .zero }
        return CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top)
    }
}

extension Color {
    /// "#ff8800" / "ff8800" → Color
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

func formatMinutes(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes)m" }
    let h = minutes / 60, m = minutes % 60
    return m == 0 ? "\(h)h" : "\(h)h \(m)m"
}

func formatBytes(_ bytes: Double) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var v = bytes
    var i = 0
    while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
    return i == 0 ? "\(Int(v)) \(units[i])" : String(format: v < 10 ? "%.1f %@" : "%.0f %@", v, units[i])
}
