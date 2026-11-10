import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Root

struct IslandRootView: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var shelf: ShelfService

    var body: some View {
        let size = vm.size
        let open = vm.expanded || vm.alert != nil
        let pill = vm.pillStyle
        let radius: CGFloat = vm.expanded
            ? (pill ? 34 : 30)
            : (pill ? size.height / 2 : (vm.alert != nil ? 24 : (vm.hasNotch ? 10 : 14)))
        let top: CGFloat = pill ? radius : 0
        let shape = UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: radius,
                                           bottomTrailingRadius: radius, topTrailingRadius: top, style: .continuous)
        let hidden = vm.hiddenForFullscreen && !open

        ZStack(alignment: .top) {
            if vm.expanded {
                ExpandedIslandView()
                    .padding(.top, vm.topInset)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            } else if let alert = vm.alert {
                AlertBannerView(alert: alert)
                    .padding(.top, vm.topInset)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            } else {
                CompactIslandView()
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color.black)
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(pill ? 0.12 : 0), lineWidth: 0.5))
        .shadow(color: .black.opacity(open ? 0.45 : (pill ? 0.3 : 0)), radius: open ? 14 : 6, y: open ? 6 : 2)
        .contentShape(shape)
        .onTapGesture { if !vm.expanded { vm.expand() } }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            loadFiles(providers)
            return true
        }
        .opacity(hidden ? 0 : 1)
        .padding(.top, vm.topGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: vm.expanded)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: vm.tab)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: vm.compactWide)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: vm.alert)
        .animation(.easeInOut(duration: 0.25), value: hidden)
        .environment(\.colorScheme, .dark)
    }

    private func loadFiles(_ providers: [NSItemProvider]) {
        for p in providers {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    shelf.add([url])
                    if Prefs.showShelf { vm.expand(tab: .shelf) }
                }
            }
        }
    }
}

// MARK: - Compact pill

/// Content is split into a leading and trailing side so it never sits under a MacBook notch.
struct CompactIslandView: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var media: NowPlayingService
    @EnvironmentObject var cal: CalendarService
    @EnvironmentObject var timer: TimerService
    @EnvironmentObject var weather: WeatherService

    var body: some View {
        let content = vm.compactContent
        if content.isIdle && !vm.hasNotch {
            // Idle: clock and weather grouped in the middle of the pill.
            HStack(spacing: 8) {
                leading(content)
                trailing(content)
                if vm.micInUse { Circle().fill(Color.orange).frame(width: 6, height: 6) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: vm.compactHeight)
        } else {
            liveBody(content)
        }
    }

    @ViewBuilder
    private func liveBody(_ content: CompactContent) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) { leading(content) }
                .frame(maxWidth: .infinity, alignment: .leading)
            if vm.hasNotch { Color.clear.frame(width: vm.notch.width) }
            HStack(spacing: 7) {
                trailing(content)
                if vm.micInUse {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                        .help("Microphone in use")
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, vm.hasNotch ? 12 : (vm.pillStyle ? vm.compactHeight / 2 + 2 : 14))
        .frame(height: vm.compactHeight)
    }

    private var showText: Bool { !vm.hasNotch }

    @ViewBuilder
    private func leading(_ c: CompactContent) -> some View {
        switch c {
        case .meeting(let e):
            Image(systemName: e.provider != nil ? "video.fill" : "calendar")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(e.provider?.color ?? .orange)
            if showText {
                Text(e.title).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9)).lineLimit(1)
            }
        case .timer:
            Image(systemName: timer.mode == .simple ? "timer" : "brain.head.profile")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(timer.color)
            if showText {
                Text(timer.label).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
        case .media(let info):
            ArtworkView(image: media.artwork, source: info.source, size: min(22, vm.compactHeight - 6), corner: 4)
            if showText {
                Text(info.title).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8)).lineLimit(1)
            }
        case .unread:
            Image(systemName: "bell.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
        case .idle:
            TimelineView(.everyMinute) { ctx in
                Text(ctx.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        case .empty:
            EmptyView()
        }
    }

    @ViewBuilder
    private func trailing(_ c: CompactContent) -> some View {
        switch c {
        case .meeting(let e):
            Text(countdown(to: e.start, from: cal.now))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(e.provider?.color ?? .orange)
        case .timer:
            Text(timer.remainingText)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(timer.isPaused ? Color.white.opacity(0.5) : timer.color)
        case .media(let info):
            if !vm.unreadBadges.isEmpty { Circle().fill(Color.red).frame(width: 6, height: 6) }
            WaveformView(playing: true, color: info.source.color)
        case .unread:
            ForEach(Array(vm.unreadBadges.prefix(vm.hasNotch ? 3 : 5))) { badge in
                BadgedIcon(badge: badge, size: min(18, vm.compactHeight - 8))
            }
        case .idle:
            if let w = weather.weather {
                Image(systemName: w.symbol).symbolRenderingMode(.multicolor)
                    .font(.system(size: 11))
                Text("\(w.temp)°").font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.75))
            } else if let b = vm.services.power.battery {
                Image(systemName: b.symbol).foregroundStyle(b.color).font(.system(size: 12))
                Text("\(b.percent)%").font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        case .empty:
            EmptyView()
        }
    }
}

// MARK: - Expanded

struct ExpandedIslandView: View {
    @EnvironmentObject var vm: IslandViewModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(vm.visibleTabs) { tab in
                    TabChip(tab: tab, selected: vm.tab == tab) { vm.select(tab) }
                }
                Spacer(minLength: 6)
                HeaderStatus()
            }
            Group {
                switch vm.tab {
                case .media: MediaTabView()
                case .calendar: CalendarTabView()
                case .inbox: InboxTabView()
                case .shelf: ShelfTabView()
                case .timer: TimerTabView()
                case .system: SystemTabView()
                case .shortcuts: ShortcutsTabView()
                case .search: SearchTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .foregroundStyle(.white)
    }
}

/// Weather, battery and clock in the top-right corner of the open island.
struct HeaderStatus: View {
    @EnvironmentObject var weather: WeatherService
    @EnvironmentObject var power: PowerService

    var body: some View {
        HStack(spacing: 8) {
            if Prefs.showWeather, let w = weather.weather {
                HStack(spacing: 3) {
                    Image(systemName: w.symbol).symbolRenderingMode(.multicolor)
                    Text("\(w.temp)°")
                }
                .help("\(w.place.isEmpty ? "" : w.place + " · ")\(w.summary) · H \(w.high)° L \(w.low)° · Rain \(w.rainChance)%")
            }
            if let b = power.battery {
                HStack(spacing: 3) {
                    Image(systemName: b.symbol).foregroundStyle(b.color)
                    Text("\(b.percent)%")
                }
                .help(b.statusText)
            }
            ClockLabel()
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundStyle(Color.white.opacity(0.65))
    }
}

struct TabChip: View {
    let tab: IslandTab
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol)
                if selected { Text(tab.title) }
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, selected ? 10 : 7)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(selected ? 0.18 : (hovering ? 0.1 : 0))))
            .foregroundStyle(Color.white.opacity(selected ? 1 : 0.6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tab.title)
    }
}

struct ClockLabel: View {
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            Text(ctx.date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
        }
    }
}

// MARK: - Banner

struct AlertIconView: View {
    let icon: AlertIcon
    let size: CGFloat

    var body: some View {
        switch icon {
        case .app(let id):
            Image(nsImage: AppIcons.icon(for: id)).resizable().aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        case .file(let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        case .symbol(let name, let color):
            ZStack {
                Circle().fill(color.opacity(0.2))
                Image(systemName: name)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: size, height: size)
        }
    }
}

struct AlertBannerView: View {
    let alert: IslandAlert

    var body: some View {
        HStack(spacing: 12) {
            AlertIconView(icon: alert.icon, size: alert.compact ? 28 : 38)
            VStack(alignment: .leading, spacing: 2) {
                if alert.compact {
                    HStack {
                        Text(alert.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(alert.message)
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(1)
                    }
                } else {
                    Text(alert.title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                    Text(alert.message)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if !alert.detail.isEmpty {
                        Text(alert.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                if let p = alert.progress {
                    ProgressBar(value: p, color: alert.tint)
                        .frame(height: 4)
                        .padding(.top, 2)
                }
            }
            if !alert.compact {
                Spacer(minLength: 4)
                Text("now")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 16)
        .frame(height: alert.compact ? 46 : 66)
    }
}

struct ProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(color)
                    .frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
    }
}

struct BadgedIcon: View {
    let badge: BadgeItem
    let size: CGFloat

    var body: some View {
        Image(nsImage: AppIcons.icon(for: badge.id))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) {
                Text(badge.count > 99 ? "99+" : "\(badge.count)")
                    .font(.system(size: size * 0.38, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, size * 0.12)
                    .frame(minWidth: size * 0.5, minHeight: size * 0.5)
                    .background(Capsule().fill(Color.red))
                    .offset(x: size * 0.25, y: -size * 0.2)
            }
    }
}

// MARK: - Shared bits

struct ArtworkView: View {
    let image: NSImage?
    let source: MediaSource
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                source.color.opacity(0.25)
                Image(systemName: source.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(source.color)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct WaveformView: View {
    let playing: Bool
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let phase = t * (3.0 + Double(i) * 0.9) + Double(i) * 1.3
                    let h: CGFloat = playing ? 4 + 10 * CGFloat(abs(sin(phase))) : 3
                    Capsule().fill(color).frame(width: 3, height: h)
                }
            }
            .frame(height: 16)
        }
    }
}

struct ControlButton: View {
    let symbol: String
    var size: CGFloat = 16
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: size + 18, height: size + 18)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.14 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct PillButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(configuration.isPressed ? 0.7 : 1)))
            .foregroundStyle(.white)
    }
}

/// Small rounded card used on the System tab.
struct StatCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}
