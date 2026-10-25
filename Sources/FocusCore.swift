import Foundation

enum FocusCore {
    enum Constants {
        static let tickSeconds: TimeInterval = 15
        static let stableSeconds: TimeInterval = 20
        static let minCallGapSeconds: TimeInterval = 20
        static let cacheTTLSeconds: TimeInterval = 300
        static let inflightTimeoutSeconds: TimeInterval = 30
        static let idleSeconds: TimeInterval = 180
        static let onTaskClearSeconds: TimeInterval = 30
        static let confidenceThreshold = 0.7
        static let snoozeMinutes = 15
        static let errorBackoffSeconds: TimeInterval = 60
        static let pricePerMillionInput = 1.0
        static let pricePerMillionOutput = 5.0
    }

    static let browserBundleIDs: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "com.google.Chrome.canary", "com.brave.Browser",
        "com.microsoft.edgemac", "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.mozilla.firefox",
    ]

    static func normalizeURL(_ value: String?) -> String? {
        guard let value, !value.isEmpty,
              let parts = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host?.lowercased(), !host.isEmpty else { return nil }
        let displayHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        var path = parts.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        return String("\(scheme)://\(displayHost)\(path)".prefix(200))
    }

    static func host(of url: String?) -> String? {
        guard let url else { return nil }
        return URLComponents(string: url)?.host?.lowercased()
    }

    static func parseJudgement(_ text: String) -> Judgement {
        let fallback = Judgement(verdict: .unclear, confidence: 0, line: "")
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return fallback }
        let verdict = (object["verdict"] as? String).flatMap(Verdict.init(rawValue:)) ?? .unclear
        var confidence = 0.0
        if let number = object["confidence"] as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite {
            confidence = min(1, max(0, number.doubleValue))
        }
        let line = (object["line"] as? String) ?? ""
        return Judgement(verdict: verdict, confidence: confidence,
                         line: String(line.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)))
    }
}

struct FocusContext: Equatable {
    var appName: String
    var bundleID: String
    var windowTitle: String?
    var url: String?
    var key: String { "\(bundleID)|\(windowTitle ?? "")|\(url ?? "")" }
    var allowKey: String { "\(bundleID)|\(FocusCore.host(of: url) ?? "")" }
}

enum Verdict: String, Codable { case onTask = "on_task", offTask = "off_task", unclear }
struct Judgement: Equatable { var verdict: Verdict; var confidence: Double; var line: String }

enum Pause: Equatable {
    case disabled, noKey, noPermission, noTask, outsideHours, idle, locked
    case snoozed(until: Date)
    case apiError(String)
}
enum Alarm: Equatable { case none, soft, hard }

struct JudgeRequest: Equatable {
    var key: String
    var task: String
    var otherTasks: [String]
    var strict: Bool
    var context: FocusContext
    var minutesInContext: Int
}
enum FocusCommand: Equatable { case judge(JudgeRequest) }
enum UserAction: Equatable { case thisIsWork, snooze, toggle }

struct FocusSnapshot: Equatable {
    var pause: Pause?
    var context: FocusContext?
    var judgement: Judgement?
    var awaiting: Bool
    var alarm: Alarm
    var offTaskSince: Date?
    var callsToday: Int
    var inputTokens: Int
    var outputTokens: Int
}

struct FocusSettings {
    var enabled: Bool
    var strict: Bool
    var hours: (start: Int, end: Int)?
    var weekdaysOnly: Bool
    var offTaskMinutes: Int
    var hardAfterMinutes: Int
    var allowApps: [String]
    var ignoreApps: [String]
    var model: String

    init(enabled: Bool = true, strict: Bool = true, hours: String = "09:00-19:00",
         weekdaysOnly: Bool = true, offTaskMinutes: Int = 2, hardAfterMinutes: Int = 5,
         allowApps: [String] = [],
         ignoreApps: [String] = ["com.1password.1password", "com.apple.keychainaccess",
                                 "com.apple.Passwords"], model: String = "claude-haiku-4-5") {
        self.enabled = enabled
        self.strict = strict
        self.hours = Self.parseHours(hours)
        self.weekdaysOnly = weekdaysOnly
        self.offTaskMinutes = offTaskMinutes
        self.hardAfterMinutes = hardAfterMinutes
        self.allowApps = allowApps
        self.ignoreApps = ignoreApps
        self.model = model
    }

    static func parseHours(_ value: String) -> (start: Int, end: Int)? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        func minutes(_ part: Substring) -> Int? {
            let clock = part.split(separator: ":", omittingEmptySubsequences: false)
            guard clock.count == 2, clock[0].count == 2, clock[1].count == 2,
                  let hour = Int(clock[0]), let minute = Int(clock[1]),
                  (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            return hour * 60 + minute
        }
        guard let start = minutes(parts[0]), let end = minutes(parts[1]), start < end
        else { return nil }
        return (start, end)
    }

    static func isWeekend(_ date: Date, calendar: Calendar) -> Bool {
        [1, 7].contains(calendar.component(.weekday, from: date))
    }
}

final class FocusMachine {
    var settings: FocusSettings
    private(set) var snapshot = FocusSnapshot(
        pause: nil, context: nil, judgement: nil, awaiting: false, alarm: .none,
        offTaskSince: nil, callsToday: 0, inputTokens: 0, outputTokens: 0)

    private var currentKey: String?
    private var keySince: Date?
    private var cache: [String: (judgement: Judgement, at: Date)] = [:]
    private var inflight: (key: String, at: Date)?
    private var lastCallAt: Date?
    private var backoffUntil: Date?
    private var offTaskSince: Date?
    private var onTaskSince: Date?
    private var snoozeUntil: Date?
    private var dayAllow: Set<String> = []
    private var localDay: Date?
    private var errorPause: Pause?

    init(settings: FocusSettings) { self.settings = settings }

    func tick(now: Date, context: FocusContext?, idleSeconds: Double, locked: Bool,
              permitted: Bool, hasKey: Bool, firstTask: String?, otherTasks: [String]) -> FocusCommand? {
        resetDay(now: now)

        if !settings.enabled { return pause(.disabled) }
        if !hasKey { return pause(.noKey) }
        if !permitted { return pause(.noPermission) }
        guard let firstTask else { return pause(.noTask) }
        if let until = snoozeUntil {
            if until > now { return pause(.snoozed(until: until)) }
            snoozeUntil = nil
        }
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute], from: now)
        let minuteOfDay = (time.hour ?? 0) * 60 + (time.minute ?? 0)
        if (settings.weekdaysOnly && FocusSettings.isWeekend(now, calendar: calendar)) ||
           (settings.hours.map { !(($0.start)..<($0.end)).contains(minuteOfDay) } ?? false) {
            return pause(.outsideHours)
        }
        if locked { return pause(.locked) }
        if idleSeconds >= FocusCore.Constants.idleSeconds { return pause(.idle) }
        snapshot.pause = errorPause
        guard let context else { return nil }

        if context.key != currentKey {
            currentKey = context.key
            keySince = now
        }
        snapshot.context = context
        let minutes = Int(max(0, now.timeIntervalSince(keySince ?? now)) / 60)

        let judgement: Judgement?
        if settings.ignoreApps.contains(context.bundleID) {
            judgement = Judgement(verdict: .unclear, confidence: 0, line: "")
        } else if settings.allowApps.contains(context.bundleID) || dayAllow.contains(context.allowKey) {
            judgement = Judgement(verdict: .onTask, confidence: 1, line: "")
        } else if let hit = cache[context.key], now.timeIntervalSince(hit.at) < FocusCore.Constants.cacheTTLSeconds {
            judgement = hit.judgement
        } else {
            judgement = nil
        }
        snapshot.judgement = judgement

        if let inflight, now.timeIntervalSince(inflight.at) >= FocusCore.Constants.inflightTimeoutSeconds {
            self.inflight = nil
        }
        snapshot.awaiting = inflight?.key == context.key
        account(judgement, now: now)
        if judgement == nil,
           now.timeIntervalSince(keySince ?? now) >= FocusCore.Constants.stableSeconds,
           inflight == nil,
           lastCallAt.map({ now.timeIntervalSince($0) >= FocusCore.Constants.minCallGapSeconds }) ?? true,
           backoffUntil.map({ now >= $0 }) ?? true {
            self.inflight = (context.key, now)
            snapshot.awaiting = true
            return .judge(JudgeRequest(key: context.key, task: firstTask,
                                       otherTasks: Array(otherTasks.prefix(3)), strict: settings.strict,
                                       context: context, minutesInContext: minutes))
        }
        return nil
    }

    func judged(key: String, _ judgement: Judgement, inputTokens: Int, outputTokens: Int, now: Date) {
        guard inflight?.key == key else { return }
        resetDay(now: now)
        cache[key] = (judgement, now)
        inflight = nil
        lastCallAt = now
        errorPause = nil
        snapshot.pause = nil
        snapshot.callsToday += 1
        snapshot.inputTokens += inputTokens
        snapshot.outputTokens += outputTokens
        if currentKey == key {
            let effective = snapshot.context.map { context -> Judgement in
                if settings.ignoreApps.contains(context.bundleID) {
                    return Judgement(verdict: .unclear, confidence: 0, line: "")
                }
                if settings.allowApps.contains(context.bundleID) || dayAllow.contains(context.allowKey) {
                    return Judgement(verdict: .onTask, confidence: 1, line: "")
                }
                return judgement
            } ?? judgement
            snapshot.judgement = effective
            snapshot.awaiting = false
            account(effective, now: now)
        }
    }

    func judgeFailed(key: String, pause: Pause, backoffSeconds: TimeInterval, now: Date) {
        guard inflight?.key == key else { return }
        inflight = nil
        backoffUntil = now.addingTimeInterval(backoffSeconds)
        errorPause = pause
        snapshot.pause = pause
        snapshot.awaiting = false
    }

    func taskChanged(now: Date) {
        cache.removeAll()
        inflight = nil
        snapshot.awaiting = false
        snapshot.judgement = nil
        clearTimer()
    }

    func userAction(_ action: UserAction, now: Date) {
        resetDay(now: now)
        switch action {
        case .thisIsWork:
            if let context = snapshot.context {
                dayAllow.insert(context.allowKey)
                snapshot.judgement = Judgement(verdict: .onTask, confidence: 1, line: "")
                if inflight?.key == context.key { inflight = nil; snapshot.awaiting = false }
            }
        case .snooze:
            snoozeUntil = now.addingTimeInterval(Double(FocusCore.Constants.snoozeMinutes) * 60)
            snapshot.pause = .snoozed(until: snoozeUntil!)
        case .toggle:
            settings.enabled.toggle()
            snapshot.pause = settings.enabled ? nil : .disabled
        }
        clearTimer()
    }

    private func pause(_ reason: Pause) -> FocusCommand? {
        snapshot.pause = reason
        snapshot.awaiting = false
        clearTimer()
        return nil
    }

    private func clearTimer() {
        offTaskSince = nil
        onTaskSince = nil
        snapshot.offTaskSince = nil
        snapshot.alarm = .none
    }

    private func account(_ judgement: Judgement?, now: Date) {
        if judgement?.verdict == .offTask &&
           (judgement?.confidence ?? 0) >= FocusCore.Constants.confidenceThreshold {
            if offTaskSince == nil { offTaskSince = now }
            onTaskSince = nil
        } else {
            if onTaskSince == nil { onTaskSince = now }
            if let onTaskSince, now.timeIntervalSince(onTaskSince) >= FocusCore.Constants.onTaskClearSeconds {
                offTaskSince = nil
            }
        }
        snapshot.offTaskSince = offTaskSince
        if let offTaskSince {
            let elapsed = now.timeIntervalSince(offTaskSince)
            if elapsed >= Double(settings.hardAfterMinutes) * 60 { snapshot.alarm = .hard }
            else if elapsed >= Double(settings.offTaskMinutes) * 60 { snapshot.alarm = .soft }
            else { snapshot.alarm = .none }
        } else {
            snapshot.alarm = .none
        }
    }

    private func resetDay(now: Date) {
        let day = Calendar.current.startOfDay(for: now)
        if localDay != day {
            localDay = day
            dayAllow.removeAll()
            snapshot.callsToday = 0
            snapshot.inputTokens = 0
            snapshot.outputTokens = 0
        }
    }
}
