import Foundation

@main
struct FocusCoreTests {
    static var failures = 0
    static let start = Date(timeIntervalSince1970: 1_800_000_000)
    static let context = FocusContext(appName: "Chrome", bundleID: "com.google.Chrome",
                                      windowTitle: "Videos", url: "https://example.com/watch")

    static func settings() -> FocusSettings {
        FocusSettings(hours: "", weekdaysOnly: false, ignoreApps: [])
    }

    @discardableResult
    static func tick(_ machine: FocusMachine, _ seconds: TimeInterval,
                     context: FocusContext? = context, idle: Double = 0,
                     locked: Bool = false, permitted: Bool = true,
                     hasKey: Bool = true, task: String? = "Собрать мудборд") -> FocusCommand? {
        machine.tick(now: start.addingTimeInterval(seconds), context: context, idleSeconds: idle,
                     locked: locked, permitted: permitted, hasKey: hasKey,
                     firstTask: task, otherTasks: [])
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("  FAIL: \(message)")
        }
    }

    static func run(_ name: String, _ test: () -> Void) {
        let before = failures
        test()
        print("\(failures == before ? "PASS" : "FAIL") \(name)")
    }

    static func disabled() {
        let machine = FocusMachine(settings: FocusSettings(enabled: false, hours: "", weekdaysOnly: false))
        expect(tick(machine, 0) == nil, "disabled must not judge")
        expect(tick(machine, 30) == nil, "disabled remains silent")
        expect(machine.snapshot.pause == .disabled, "disabled pause")
    }

    static func stableAndInflight() {
        let machine = FocusMachine(settings: settings())
        expect(tick(machine, 0) == nil, "new context waits")
        expect(tick(machine, 19) == nil, "19 seconds is too early")
        expect(tick(machine, 20) != nil, "20 seconds sends request")
        expect(tick(machine, 25) == nil, "inflight blocks repeat")
        expect(machine.snapshot.awaiting, "inflight shown")
        expect(tick(machine, 50) != nil, "30-second timeout permits retry")
    }

    static func cacheTTL() {
        let machine = FocusMachine(settings: settings())
        _ = tick(machine, 0)
        _ = tick(machine, 20)
        machine.judged(key: context.key, Judgement(verdict: .onTask, confidence: 1, line: ""),
                       inputTokens: 10, outputTokens: 2, now: start.addingTimeInterval(21))
        expect(tick(machine, 320) == nil, "cache reused at 299 seconds")
        expect(tick(machine, 322) != nil, "cache expires at 301 seconds")
        expect(machine.snapshot.callsToday == 1, "call counter")
        expect(machine.snapshot.inputTokens == 10 && machine.snapshot.outputTokens == 2, "tokens")
    }

    static func alarmsAndClear() {
        let machine = FocusMachine(settings: settings())
        _ = tick(machine, 0)
        _ = tick(machine, 20)
        machine.judged(key: context.key, Judgement(verdict: .offTask, confidence: 0.9, line: "Нет"),
                       inputTokens: 0, outputTokens: 0, now: start.addingTimeInterval(21))
        _ = tick(machine, 140)
        expect(machine.snapshot.alarm == .none, "before two minutes")
        _ = tick(machine, 141)
        expect(machine.snapshot.alarm == .soft, "soft after two minutes")
        _ = tick(machine, 321)
        expect(machine.snapshot.alarm == .hard, "hard after five minutes")
        machine.judged(key: context.key, Judgement(verdict: .onTask, confidence: 0.9, line: ""),
                       inputTokens: 0, outputTokens: 0, now: start.addingTimeInterval(322))
        expect(machine.snapshot.alarm == .hard, "on-task requires 30 seconds")
        _ = tick(machine, 352)
        expect(machine.snapshot.alarm == .none && machine.snapshot.offTaskSince == nil,
               "on-task clears after 30 seconds")
    }

    static func lowConfidence() {
        let machine = FocusMachine(settings: settings())
        _ = tick(machine, 0)
        _ = tick(machine, 20)
        machine.judged(key: context.key, Judgement(verdict: .offTask, confidence: 0.6, line: ""),
                       inputTokens: 0, outputTokens: 0, now: start.addingTimeInterval(21))
        _ = tick(machine, 200)
        expect(machine.snapshot.alarm == .none, "low-confidence off-task never alarms")
    }

    static func unclear() {
        let machine = FocusMachine(settings: settings())
        _ = tick(machine, 0)
        _ = tick(machine, 20)
        machine.judged(key: context.key, Judgement(verdict: .unclear, confidence: 1, line: ""),
                       inputTokens: 0, outputTokens: 0, now: start.addingTimeInterval(21))
        _ = tick(machine, 200)
        expect(machine.snapshot.alarm == .none, "unclear never alarms")
    }

    static func idleAndLocked() {
        let machine = FocusMachine(settings: settings())
        _ = tick(machine, 0)
        _ = tick(machine, 20)
        machine.judged(key: context.key, Judgement(verdict: .offTask, confidence: 0.9, line: ""),
                       inputTokens: 0, outputTokens: 0, now: start.addingTimeInterval(21))
        _ = tick(machine, 141)
        expect(machine.snapshot.alarm == .soft, "alarm is active")
        _ = tick(machine, 142, idle: 180)
        expect(machine.snapshot.pause == .idle && machine.snapshot.alarm == .none,
               "idle clears alarm")
        expect(tick(machine, 143) == nil && machine.snapshot.judgement?.verdict == .offTask,
               "cache survives idle")
        _ = tick(machine, 263)
        expect(machine.snapshot.alarm == .soft, "alarm can restart")
        _ = tick(machine, 264, locked: true)
        expect(machine.snapshot.pause == .locked && machine.snapshot.alarm == .none,
               "lock clears alarm")
        expect(tick(machine, 265) == nil, "cache survives lock")
    }

    static func allowAndMidnight() {
        let allowed = FocusMachine(settings: FocusSettings(hours: "", weekdaysOnly: false,
                                                            allowApps: [context.bundleID], ignoreApps: []))
        _ = tick(allowed, 0)
        expect(tick(allowed, 20) == nil && allowed.snapshot.judgement?.verdict == .onTask,
               "allowed app skips API")

        let calendar = Calendar.current
        let beforeMidnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5,
                                                                  hour: 23, minute: 59))!
        let machine = FocusMachine(settings: settings())
        _ = machine.tick(now: beforeMidnight, context: context, idleSeconds: 0, locked: false,
                         permitted: true, hasKey: true, firstTask: "Задача", otherTasks: [])
        machine.userAction(.thisIsWork, now: beforeMidnight.addingTimeInterval(10))
        _ = machine.tick(now: beforeMidnight.addingTimeInterval(20), context: context,
                         idleSeconds: 0, locked: false, permitted: true, hasKey: true,
                         firstTask: "Задача", otherTasks: [])
        expect(machine.snapshot.judgement?.verdict == .onTask, "day allowance works")
        let afterMidnight = calendar.date(byAdding: .minute, value: 2, to: beforeMidnight)!
        let command = machine.tick(now: afterMidnight, context: context, idleSeconds: 0,
                                   locked: false, permitted: true, hasKey: true,
                                   firstTask: "Задача", otherTasks: [])
        expect(command != nil, "day allowance expires at midnight")
    }

    static func ignore() {
        let machine = FocusMachine(settings: FocusSettings(hours: "", weekdaysOnly: false,
                                                            ignoreApps: [context.bundleID]))
        _ = tick(machine, 0)
        expect(tick(machine, 30) == nil, "ignored app skips API")
        expect(machine.snapshot.judgement == Judgement(verdict: .unclear, confidence: 0, line: ""),
               "ignored app is unclear")
    }

    static func snooze() {
        let machine = FocusMachine(settings: settings())
        _ = tick(machine, 0)
        machine.userAction(.snooze, now: start.addingTimeInterval(10))
        expect(tick(machine, 20) == nil, "snooze blocks request")
        if case .snoozed = machine.snapshot.pause {} else { expect(false, "snooze shown") }
        expect(tick(machine, 909) == nil, "snooze lasts 15 minutes")
        expect(tick(machine, 910) != nil && machine.snapshot.pause == nil,
               "watching resumes after 15 minutes")
    }

    static func hoursAndWeekend() {
        expect(FocusSettings.parseHours("09:00-19:00")?.start == 540, "hours start")
        expect(FocusSettings.parseHours("09:00-19:00")?.end == 1140, "hours end")
        expect(FocusSettings.parseHours("19:00-09:00") == nil, "overnight invalid")
        expect(FocusSettings.parseHours("bad") == nil, "bad hours mean always")
        let utc = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3))!
        expect(FocusSettings.isWeekend(saturday, calendar: calendar), "Saturday is weekend")
        let local = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5,
                                                                hour: 8, minute: 30))!
        let machine = FocusMachine(settings: FocusSettings(weekdaysOnly: false, ignoreApps: []))
        _ = machine.tick(now: local, context: context, idleSeconds: 0, locked: false,
                         permitted: true, hasKey: true, firstTask: "Задача", otherTasks: [])
        expect(machine.snapshot.pause == .outsideHours, "before work hours pauses")
    }

    static func urlsAndKeys() {
        expect(FocusCore.normalizeURL("HTTPS://User:secret@EXAMPLE.COM:443/a/b/?x=1#frag") ==
               "https://example.com/a/b", "private URL parts removed")
        expect(FocusCore.normalizeURL("file:///tmp/secret") == nil, "non-http rejected")
        expect(FocusCore.normalizeURL("http://[2001:db8::1]:80/a/") ==
               "http://[2001:db8::1]/a", "IPv6 host normalized")
        expect(FocusCore.normalizeURL("https://éxample.com/é/") ==
               "https://éxample.com/%C3%A9", "Unicode path encoded")
        expect(FocusCore.normalizeURL("https://example.com/" + String(repeating: "x", count: 300))?.count == 200,
               "URL capped at 200")
        expect(context.key == "com.google.Chrome|Videos|https://example.com/watch", "context key")
        expect(context.allowKey == "com.google.Chrome|example.com", "allow key")
    }

    static func judgementParsing() {
        expect(FocusCore.parseJudgement("oops") == Judgement(verdict: .unclear, confidence: 0, line: ""),
               "invalid JSON")
        expect(FocusCore.parseJudgement("[]").verdict == .unclear, "nonobject JSON")
        let bad = FocusCore.parseJudgement("{\"verdict\":\"bad\",\"confidence\":2,\"line\":\"  привет  \"}")
        expect(bad == Judgement(verdict: .unclear, confidence: 1, line: "привет"),
               "bad verdict and clamp")
        let boolean = FocusCore.parseJudgement("{\"verdict\":\"off_task\",\"confidence\":true,\"line\":1}")
        expect(boolean == Judgement(verdict: .offTask, confidence: 0, line: ""),
               "wrong field types")
        let long = FocusCore.parseJudgement("{\"verdict\":\"off_task\",\"confidence\":-1,\"line\":\"" +
                                            String(repeating: "a", count: 90) + "\"}")
        expect(long.confidence == 0 && long.line.count == 80, "line capped at 80")
    }

    static func backoff() {
        let machine = FocusMachine(settings: settings())
        _ = tick(machine, 0)
        _ = tick(machine, 20)
        machine.judgeFailed(key: context.key, pause: .apiError("нет связи"),
                            backoffSeconds: 60, now: start.addingTimeInterval(21))
        expect(tick(machine, 80) == nil, "backoff blocks calls")
        expect(machine.snapshot.pause == .apiError("нет связи"), "error shown")
        expect(tick(machine, 81) != nil, "call resumes after backoff")
    }

    static func taskChange() {
        let machine = FocusMachine(settings: settings())
        _ = tick(machine, 0)
        _ = tick(machine, 20)
        machine.judged(key: context.key, Judgement(verdict: .offTask, confidence: 0.9, line: ""),
                       inputTokens: 0, outputTokens: 0, now: start.addingTimeInterval(21))
        _ = tick(machine, 141)
        expect(machine.snapshot.alarm == .soft, "alarm active")
        machine.taskChanged(now: start.addingTimeInterval(142))
        expect(machine.snapshot.alarm == .none && machine.snapshot.judgement == nil,
               "task change clears alarm and judgement")
        expect(tick(machine, 143) != nil, "task change clears cache")

        let pending = FocusMachine(settings: settings())
        _ = tick(pending, 0)
        _ = tick(pending, 20)
        pending.taskChanged(now: start.addingTimeInterval(21))
        pending.judged(key: context.key,
                       Judgement(verdict: .offTask, confidence: 1, line: "Старая задача"),
                       inputTokens: 10, outputTokens: 2, now: start.addingTimeInterval(22))
        pending.judgeFailed(key: context.key, pause: .apiError("нет связи"),
                            backoffSeconds: 60, now: start.addingTimeInterval(23))
        expect(pending.snapshot.judgement == nil && pending.snapshot.pause == nil &&
               pending.snapshot.callsToday == 0, "late answer after task change is ignored")
        expect(tick(pending, 24) != nil, "late answer does not block the new task")
    }

    static func minimumCallGap() {
        let machine = FocusMachine(settings: settings())
        _ = tick(machine, 0)
        _ = tick(machine, 20)
        machine.judged(key: context.key, Judgement(verdict: .onTask, confidence: 1, line: ""),
                       inputTokens: 0, outputTokens: 0, now: start.addingTimeInterval(21))
        let second = FocusContext(appName: "Safari", bundleID: "com.apple.Safari",
                                  windowTitle: "News", url: "https://example.org")
        expect(tick(machine, 22, context: second) == nil, "new key starts stability timer")
        expect(tick(machine, 40, context: second) == nil, "global call gap enforced")
        expect(tick(machine, 42, context: second) != nil, "new call allowed after gap")
    }

    static func main() {
        run("01 disabled", disabled)
        run("02 stable and inflight", stableAndInflight)
        run("03 cache TTL", cacheTTL)
        run("04 alarms and clear", alarmsAndClear)
        run("05 low confidence", lowConfidence)
        run("06 unclear", unclear)
        run("07 idle and locked", idleAndLocked)
        run("08 allow and midnight", allowAndMidnight)
        run("09 ignore", ignore)
        run("10 snooze", snooze)
        run("11 hours and weekend", hoursAndWeekend)
        run("12 URL and keys", urlsAndKeys)
        run("13 judgement parsing", judgementParsing)
        run("14 backoff", backoff)
        run("15 task change", taskChange)
        run("16 minimum call gap", minimumCallGap)
        if failures != 0 { exit(1) }
    }
}
