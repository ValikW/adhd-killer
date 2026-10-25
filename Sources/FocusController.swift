import AppKit

@MainActor
final class FocusController {
    private let machine: FocusMachine
    private let observer = FocusObserver()
    private let judge: FocusJudge?
    private let hasKey: Bool
    private var timer: Timer?
    private var taskVersion = 0
    private var usageStore = FocusUsageStore()

    var onChange: (FocusSnapshot) -> Void = { _ in }
    var snapshot: FocusSnapshot { machine.snapshot }
    var usage: FocusUsage { usageStore.current() }
    var usageSaveFailed: Bool { usageStore.saveFailed }
    var isEnabled: Bool { machine.settings.enabled }
    var task: String? {
        didSet {
            if oldValue != task {
                taskVersion += 1
                machine.taskChanged(now: Date())
            }
            tick()
        }
    }

    init(apiKey: String, workspaceID: String, settings: FocusSettings, task: String?) {
        machine = FocusMachine(settings: settings)
        self.task = task
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = Bundle.main.url(forResource: "focus_prompt", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        hasKey = !key.isEmpty && prompt != nil
        if let prompt, !key.isEmpty {
            judge = FocusJudge(apiKey: key, workspaceID: workspaceID,
                               model: settings.model, systemPrompt: prompt)
        } else {
            judge = nil
        }
    }

    func start() {
        guard hasKey else { tick(); return }
        observer.onActivate = { [weak self] in self?.tick() }
        if machine.settings.enabled { observer.promptForPermission() }
        let timer = Timer(timeInterval: FocusCore.Constants.tickSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common keeps ticking while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observer.onActivate = nil
    }

    func perform(_ action: UserAction) {
        machine.userAction(action, now: Date())
        if action == .toggle && machine.settings.enabled && hasKey {
            observer.promptForPermission()
        }
        tick()
    }

    private func tick() {
        if !hasKey || !machine.settings.enabled {
            _ = machine.tick(now: Date(), context: nil, idleSeconds: 0, locked: false,
                             permitted: false, hasKey: hasKey,
                             firstTask: task, otherTasks: [])
            onChange(machine.snapshot)
            return
        }
        let seen = observer.observe()
        let now = Date()
        let command = machine.tick(now: now, context: seen.context,
                                   idleSeconds: seen.idleSeconds, locked: seen.locked,
                                   permitted: seen.permitted, hasKey: hasKey,
                                   firstTask: task, otherTasks: [])
        onChange(machine.snapshot)
        guard case .judge(let request) = command, let judge else { return }
        let version = taskVersion
        judge.judge(request) { [weak self] result in
            MainActor.assumeIsolated {
                guard let self else { return }
                if case .success(let (_, input, output)) = result {
                    self.usageStore.record(input: input, output: output)
                }
                guard self.taskVersion == version else {
                    self.onChange(self.machine.snapshot)
                    return
                }
                switch result {
                case .success(let (judgement, input, output)):
                    self.machine.judged(key: request.key, judgement,
                                        inputTokens: input, outputTokens: output, now: Date())
                case .failure(.unauthorized):
                    self.machine.judgeFailed(key: request.key,
                                             pause: .apiError(L.t("ключ API отклонён", "API key rejected")),
                                             backoffSeconds: 100 * 365 * 24 * 3600, now: Date())
                case .failure(.retryLater(let seconds, let message)):
                    self.machine.judgeFailed(key: request.key, pause: .apiError(message),
                                             backoffSeconds: seconds, now: Date())
                case .failure(.failed(let detail)):
                    self.machine.judgeFailed(key: request.key,
                                             pause: .apiError(String(detail.prefix(120))),
                                             backoffSeconds: 3600, now: Date())
                }
                self.onChange(self.machine.snapshot)
            }
        }
    }
}

