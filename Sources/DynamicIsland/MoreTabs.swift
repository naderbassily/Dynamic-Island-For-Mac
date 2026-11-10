import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Shelf (files + clipboard)

struct ShelfTabView: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var shelf: ShelfService
    @EnvironmentObject var clip: ClipboardService
    @State private var targeted = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Files
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("FILES").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.white.opacity(0.45))
                    Spacer()
                    if !shelf.items.isEmpty {
                        Button { shelf.airDrop(shelf.items) } label: { Image(systemName: "airplayaudio") }
                            .buttonStyle(.plain).help("AirDrop all")
                        Button { shelf.copy(shelf.items) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.plain).help("Copy all")
                        Button { shelf.clear() } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).help("Clear shelf")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.7))

                if shelf.items.isEmpty && shelf.recentDownloads.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 22))
                        Text("Drop files here to keep them handy.\nDrag them out, open or AirDrop later.")
                            .font(.system(size: 10))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Color.white.opacity(targeted ? 0.9 : 0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .foregroundStyle(Color.white.opacity(targeted ? 0.6 : 0.2)))
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(shelf.items, id: \.self) { url in
                                FileRow(url: url, onRemove: { shelf.remove(url) })
                            }
                            if !shelf.recentDownloads.isEmpty {
                                Text("RECENT DOWNLOADS")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.white.opacity(0.45))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                                ForEach(shelf.recentDownloads, id: \.self) { url in
                                    FileRow(url: url, onRemove: nil)
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: 230)
            .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
                for p in providers {
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        if let url { DispatchQueue.main.async { shelf.add([url]) } }
                    }
                }
                return true
            }

            // Clipboard
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("CLIPBOARD").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.white.opacity(0.45))
                    Spacer()
                    if !clip.items.isEmpty {
                        Button { clip.clear() } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.7)).help("Clear history")
                    }
                }
                if !Prefs.clipboardHistory {
                    Text("Clipboard history is off in Settings.")
                        .font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.45))
                } else if clip.items.isEmpty {
                    Text("Things you copy appear here.\nClick one to copy it again.")
                        .font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.45))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 3) {
                            ForEach(clip.items) { item in
                                ClipRow(item: item) {
                                    clip.copy(item)
                                    vm.post(IslandAlert(icon: .symbol("doc.on.clipboard.fill", .blue), title: "Copied",
                                                        message: "", duration: 1.2, sound: nil, kind: "copied",
                                                        compact: true))
                                    vm.collapse()
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct FileRow: View {
    @EnvironmentObject var shelf: ShelfService
    let url: URL
    let onRemove: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 22, height: 22)
            Text(url.lastPathComponent)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 2)
            if hovering {
                Button { shelf.airDrop([url]) } label: { Image(systemName: "airplayaudio") }
                    .buttonStyle(.plain).help("AirDrop")
                Button { shelf.reveal(url) } label: { Image(systemName: "folder") }
                    .buttonStyle(.plain).help("Show in Finder")
                if let onRemove {
                    Button(action: onRemove) { Image(systemName: "xmark") }
                        .buttonStyle(.plain).help("Remove")
                }
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(Color.white.opacity(0.9))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(hovering ? 0.12 : 0.06)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { shelf.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .help("Double-click to open · drag to move")
    }
}

struct ClipRow: View {
    let item: ClipItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(item.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(item.date.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.12 : 0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Timer

struct TimerTabView: View {
    @EnvironmentObject var timer: TimerService

    private let presets: [Double] = [1, 3, 5, 10, 15, 30, 45, 60]

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: timer.isActive ? 1 - timer.progress : 0)
                    .stroke(timer.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: timer.progress)
                VStack(spacing: 2) {
                    Text(timer.isActive ? timer.remainingText : "0:00")
                        .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    Text(timer.isActive ? (timer.isPaused ? "Paused" : timer.label) : "Ready")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            .frame(width: 130, height: 130)

            VStack(alignment: .leading, spacing: 10) {
                if timer.isActive {
                    HStack(spacing: 8) {
                        Button(timer.isPaused ? "Resume" : "Pause") { timer.togglePause() }
                            .buttonStyle(PillButtonStyle(color: .orange))
                        Button("+1 min") { timer.add(minutes: 1) }
                            .buttonStyle(PillButtonStyle(color: Color.white.opacity(0.18)))
                        Button("+5 min") { timer.add(minutes: 5) }
                            .buttonStyle(PillButtonStyle(color: Color.white.opacity(0.18)))
                        Button("Cancel") { timer.cancel() }
                            .buttonStyle(PillButtonStyle(color: .red.opacity(0.8)))
                    }
                    if timer.mode != .simple {
                        Text("Pomodoro · \(timer.completedFocus) focus session\(timer.completedFocus == 1 ? "" : "s") done")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                } else {
                    Text("QUICK TIMER").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.white.opacity(0.45))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                        ForEach(presets, id: \.self) { m in
                            Button(m >= 60 ? "\(Int(m / 60))h" : "\(Int(m))m") { timer.start(minutes: m) }
                                .buttonStyle(PillButtonStyle(color: Color.white.opacity(0.14)))
                        }
                    }
                    Button {
                        timer.startPomodoro()
                    } label: {
                        Label("Pomodoro  \(Prefs.focusMinutes) / \(Prefs.breakMinutes) min", systemImage: "brain.head.profile")
                    }
                    .buttonStyle(PillButtonStyle(color: .red.opacity(0.85)))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - System

struct SystemTabView: View {
    @EnvironmentObject var stats: SystemStatsService
    @EnvironmentObject var power: PowerService
    @EnvironmentObject var devices: DeviceService
    @EnvironmentObject var audio: AudioService

    var body: some View {
        let s = stats.stats
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                StatCard(title: "CPU", symbol: "cpu") {
                    StatGauge(value: s.cpu, color: .blue, text: "\(Int(s.cpu * 100))%")
                }
                StatCard(title: "Memory", symbol: "memorychip") {
                    StatGauge(value: s.memoryFraction, color: .purple,
                          text: "\(formatBytes(s.memoryUsed)) of \(formatBytes(s.memoryTotal))")
                }
                StatCard(title: "Disk", symbol: "internaldrive") {
                    StatGauge(value: s.diskUsedFraction, color: .teal, text: "\(formatBytes(s.diskFree)) free")
                }
                if let b = power.battery {
                    StatCard(title: "Battery", symbol: b.symbol) {
                        StatGauge(value: Double(b.percent) / 100, color: b.pluggedIn ? .green : (b.percent <= 20 ? .orange : .white),
                              text: "\(b.percent)% · \(b.statusText)")
                    }
                } else {
                    StatCard(title: "Uptime", symbol: "clock") {
                        Text(formatUptime(s.uptime)).font(.system(size: 15, weight: .semibold))
                        Text(power.thermal == .nominal || power.thermal == .fair ? "Running cool" : "Running hot")
                            .font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.5))
                    }
                }
            }
            .frame(height: 78)

            HStack(spacing: 8) {
                StatCard(title: "Network", symbol: "arrow.up.arrow.down") {
                    HStack(spacing: 10) {
                        Label(formatBytes(s.netDown) + "/s", systemImage: "arrow.down")
                        Label(formatBytes(s.netUp) + "/s", systemImage: "arrow.up")
                    }
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                }
                StatCard(title: "Devices", symbol: "dot.radiowaves.left.and.right") {
                    if devices.peripherals.isEmpty && devices.connected.isEmpty {
                        Text("No Bluetooth devices").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.5))
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(devices.peripherals) { p in
                                    Label("\(p.percent)%", systemImage: DeviceService.symbol(for: p.name))
                                        .help(p.name)
                                }
                                ForEach(devices.connected.filter { n in !devices.peripherals.contains { $0.name == n } },
                                        id: \.self) { n in
                                    Image(systemName: DeviceService.symbol(for: n)).help(n)
                                }
                            }
                            .font(.system(size: 11, weight: .medium))
                        }
                    }
                }
                StatCard(title: "Sound", symbol: audio.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                    Text(audio.muted ? "Muted" : "\(Int(audio.volume * 100))%")
                        .font(.system(size: 13, weight: .semibold))
                    Text(audio.outputName).font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1)
                }
            }
            .frame(height: 64)
        }
    }
}

struct StatGauge: View {
    let value: Double
    let color: Color
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ProgressBar(value: value, color: color).frame(height: 6)
            Text(text)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsTabView: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var shortcuts: ShortcutsService

    var body: some View {
        if shortcuts.all.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 24)).foregroundStyle(Color.white.opacity(0.4))
                Text("Your Shortcuts will appear here.\nMake some in the Shortcuts app.")
                    .font(.system(size: 11)).multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.6))
                Button("Open Shortcuts") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
                .buttonStyle(PillButtonStyle(color: .blue))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(shortcuts.ordered, id: \.self) { name in
                        ShortcutTile(name: name, pinned: shortcuts.pinned.contains(name),
                                     running: shortcuts.running == name) {
                            shortcuts.run(name)
                        } onPin: {
                            shortcuts.togglePin(name)
                        }
                    }
                }
            }
        }
    }
}

struct ShortcutTile: View {
    let name: String
    let pinned: Bool
    let running: Bool
    let action: () -> Void
    let onPin: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if running {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: pinned ? "star.fill" : "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(pinned ? Color.yellow : Color.white.opacity(0.6))
                }
                Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.14 : 0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button(pinned ? "Unpin" : "Pin to top", action: onPin)
        }
        .help("Click to run · right-click to pin")
    }
}
