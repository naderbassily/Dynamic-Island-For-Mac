import SwiftUI
import AppKit

// MARK: - Media

struct MediaTabView: View {
    @EnvironmentObject var media: NowPlayingService

    var body: some View {
        if let info = media.info {
            HStack(alignment: .top, spacing: 16) {
                ArtworkView(image: media.artwork, source: info.source, size: 96, corner: 16)
                    .onTapGesture { media.revealSource() }
                    .help("Show in \(info.source.rawValue)")

                VStack(alignment: .leading, spacing: 4) {
                    Label(info.source.rawValue, systemImage: info.source.symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(info.source.color)
                    Text(info.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    Text(info.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                    if info.needsJSPermission {
                        Text("Tip: turn on “Allow JavaScript from Apple Events” in your browser to see play/pause state.")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 10) {
                        ControlButton(symbol: "backward.fill") { media.send(.previous) }
                        ControlButton(symbol: info.isPlaying ? "pause.fill" : "play.fill", size: 22) { media.send(.toggle) }
                        ControlButton(symbol: "forward.fill") { media.send(.next) }
                        Spacer()
                        WaveformView(playing: info.isPlaying, color: info.source.color)
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.white.opacity(0.4))
                Text("Nothing playing")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                HStack(spacing: 8) {
                    Button("Apple Music") { media.openApp(bundleID: "com.apple.Music") }
                        .buttonStyle(PillButtonStyle(color: MediaSource.music.color))
                    if media.isInstalled("com.spotify.client") {
                        Button("Spotify") { media.openApp(bundleID: "com.spotify.client") }
                            .buttonStyle(PillButtonStyle(color: MediaSource.spotify.color))
                    }
                    Button("YouTube") {
                        if let url = URL(string: "https://www.youtube.com") { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(PillButtonStyle(color: MediaSource.youtube.color))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Calendar

struct CalendarTabView: View {
    @EnvironmentObject var cal: CalendarService

    var body: some View {
        switch cal.access {
        case .granted:
            if cal.upcomingToday.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.green.opacity(0.8))
                    Text("No more events today")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(cal.upcomingToday) { event in
                            EventRow(event: event)
                        }
                    }
                }
            }
        case .denied:
            VStack(spacing: 10) {
                Text("Calendar access is turned off")
                    .font(.system(size: 13, weight: .medium))
                Button("Open Privacy Settings") { cal.openPrivacySettings() }
                    .buttonStyle(PillButtonStyle(color: .blue))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unknown:
            VStack(spacing: 10) {
                Text("See your meetings here and join Teams calls in one click")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.7))
                Button("Allow Calendar Access") { cal.requestAccess() }
                    .buttonStyle(PillButtonStyle(color: .blue))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct EventRow: View {
    @EnvironmentObject var cal: CalendarService
    let event: CalEvent

    private var isNow: Bool { event.start <= cal.now && event.end > cal.now }

    private var timeText: String {
        let t = event.start.formatted(date: .omitted, time: .shortened) + " – " + event.end.formatted(date: .omitted, time: .shortened)
        let prefix = Calendar.current.isDateInTomorrow(event.start) ? "Tomorrow · " : ""
        return prefix + t + (event.calendarName.isEmpty ? "" : " · " + event.calendarName)
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color)
                .frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(timeText)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(isNow ? "NOW" : countdown(to: event.start, from: cal.now))
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(isNow ? Color.green : Color.white.opacity(0.6))
            if let provider = event.provider {
                Button {
                    cal.join(event)
                } label: {
                    Label("Join \(provider.rawValue)", systemImage: "video.fill")
                }
                .buttonStyle(PillButtonStyle(color: provider.color))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(isNow ? 0.12 : 0.06)))
    }
}

// MARK: - Inbox (messages & email)

struct InboxTabView: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var notes: NotificationService

    var body: some View {
        if !notes.axTrusted && notes.recentMail.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.white.opacity(0.5))
                Text("To see new messages from Teams, Outlook, WhatsApp and more,\nallow Dynamic Island in Accessibility settings.")
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.7))
                Button("Turn On") { notes.requestAccessibility() }
                    .buttonStyle(PillButtonStyle(color: .blue))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if notes.badges.isEmpty && notes.recentMail.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.green.opacity(0.8))
                Text("You're all caught up")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    if !notes.badges.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(notes.badges) { badge in
                                    Button {
                                        notes.open(badge)
                                        vm.collapse()
                                    } label: {
                                        HStack(spacing: 8) {
                                            BadgedIcon(badge: badge, size: 26)
                                            Text(badge.name)
                                                .font(.system(size: 12, weight: .medium))
                                                .lineLimit(1)
                                        }
                                        .padding(.leading, 8)
                                        .padding(.trailing, 14)
                                        .padding(.vertical, 8)
                                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.white.opacity(0.08)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 6)
                            .padding(.trailing, 6)
                        }
                    }
                    if !notes.recentMail.isEmpty {
                        Text("UNREAD MAIL · \(notes.mailUnread)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.45))
                        ForEach(notes.recentMail) { mail in
                            Button {
                                notes.open(mail)
                                vm.collapse()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "envelope.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.blue)
                                    Text(mail.sender)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                        .frame(width: 130, alignment: .leading)
                                    Text(mail.subject)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.white.opacity(0.7))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.06)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !notes.axTrusted {
                        Button("Allow Accessibility to also see Teams, WhatsApp, Outlook…") {
                            notes.requestAccessibility()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.blue)
                    }
                }
            }
        }
    }
}

// MARK: - Search

struct SearchTabView: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var search: SearchService
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.white.opacity(0.5))
                TextField("Search apps, files and the web", text: $search.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($focused)
                    .onSubmit {
                        search.activateSelection()
                        vm.collapse()
                    }
                    .onKeyPress(.downArrow) { search.moveSelection(1); return .handled }
                    .onKeyPress(.upArrow) { search.moveSelection(-1); return .handled }
                    .onKeyPress(.escape) { vm.collapse(); return .handled }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))

            if search.results.isEmpty {
                Text("Type to search · ↑↓ to choose · Return to open · Esc to close")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 2) {
                            ForEach(Array(search.results.enumerated()), id: \.element.id) { index, result in
                                ResultRow(result: result, selected: index == search.selection)
                                    .id(result.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        search.selection = index
                                        search.activateSelection()
                                        vm.collapse()
                                    }
                            }
                        }
                    }
                    .onChange(of: search.selection) { _, newValue in
                        if search.results.indices.contains(newValue) {
                            proxy.scrollTo(search.results[newValue].id)
                        }
                    }
                }
            }
        }
        .onExitCommand { vm.collapse() }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
        .onChange(of: vm.searchFocusToken) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
    }
}

struct ResultRow: View {
    let result: SearchResult
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: result.icon)
                .renderingMode(result.icon.isTemplate ? .template : .original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundStyle(Color.white.opacity(0.8))
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(result.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if selected {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(0.55) : Color.clear))
    }
}
