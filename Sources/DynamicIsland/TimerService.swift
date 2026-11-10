import AppKit
import SwiftUI

/// Countdown timer with an optional Pomodoro (focus / break) cycle.
final class TimerService: ObservableObject {
    enum Mode: Equatable { case simple, focus, shortBreak }

    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var total: TimeInterval = 0
    @Published private(set) var mode: Mode = .simple
    @Published private(set) var completedFocus = 0
    @Published private(set) var now = Date()

    var onAlert: ((IslandAlert) -> Void)?
    private var ticker: Timer?

    var isActive: Bool { endDate != nil || pausedRemaining != nil }
    var isPaused: Bool { pausedRemaining != nil }

    var remaining: TimeInterval {
        if let p = pausedRemaining { return p }
        guard let end = endDate else { return 0 }
        return max(0, end.timeIntervalSince(now))
    }

    var progress: Double { total > 0 ? 1 - remaining / total : 0 }

    var label: String {
        switch mode {
        case .simple: return "Timer"
        case .focus: return "Focus"
        case .shortBreak: return "Break"
        }
    }

    var color: Color {
        switch mode {
        case .simple: return .orange
        case .focus: return .red
        case .shortBreak: return .green
        }
    }

    var remainingText: String {
        let s = Int(remaining.rounded(.up))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    // MARK: Control

    func start(minutes: Double, mode: Mode = .simple) {
        self.mode = mode
        total = minutes * 60
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(total)
        now = Date()
        startTicker()
    }

    func startPomodoro() {
        completedFocus = 0
        start(minutes: Double(Prefs.focusMinutes), mode: .focus)
    }

    func togglePause() {
        if let p = pausedRemaining {
            endDate = Date().addingTimeInterval(p)
            pausedRemaining = nil
            startTicker()
        } else if endDate != nil {
            pausedRemaining = remaining
            endDate = nil
            ticker?.invalidate()
        }
    }

    func add(minutes: Double) {
        guard isActive else { start(minutes: minutes); return }
        total += minutes * 60
        if let p = pausedRemaining { pausedRemaining = p + minutes * 60 }
        if let e = endDate { endDate = e.addingTimeInterval(minutes * 60) }
    }

    func cancel() {
        ticker?.invalidate()
        endDate = nil
        pausedRemaining = nil
        mode = .simple
    }

    // MARK: Ticking

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        now = Date()
        guard let end = endDate, now >= end else { return }
        finished()
    }

    private func finished() {
        let was = mode
        ticker?.invalidate()
        endDate = nil
        switch was {
        case .simple:
            mode = .simple
            onAlert?(IslandAlert(icon: .symbol("timer", .orange), title: "Timer", message: "Time's up!",
                                 detail: formatMinutes(Int(total / 60)) + " timer finished",
                                 duration: 10, sound: "Glass", tab: .timer))
        case .focus:
            completedFocus += 1
            onAlert?(IslandAlert(icon: .symbol("cup.and.saucer.fill", .green), title: "Focus done",
                                 message: "Take a \(Prefs.breakMinutes)-minute break",
                                 detail: "\(completedFocus) focus session\(completedFocus == 1 ? "" : "s") today",
                                 duration: 10, sound: "Glass", tab: .timer))
            start(minutes: Double(Prefs.breakMinutes), mode: .shortBreak)
        case .shortBreak:
            onAlert?(IslandAlert(icon: .symbol("brain.head.profile", .red), title: "Break over",
                                 message: "Back to focus", detail: "\(Prefs.focusMinutes) minutes",
                                 duration: 10, sound: "Glass", tab: .timer))
            start(minutes: Double(Prefs.focusMinutes), mode: .focus)
        }
    }
}
