import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var settings = AppSettings.load()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let overlay = FocusOverlay()
    private let character = FocusCharacter()
    private var focus: FocusController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        statusItem.menu = menu
        character.onThisIsWork = { [weak self] in self?.focus.perform(.thisIsWork) }
        character.onSnooze = { [weak self] in self?.focus.perform(.snooze) }
        character.onCloseTask = { [weak self] in self?.taskDone() }
        character.onDisable = { [weak self] in self?.toggle() }
        restartFocus()

        if settings.apiKey.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.firstRun() }
        }
    }

    // MARK: - Focus

    private func restartFocus() {
        focus?.stop()
        focus = FocusController(apiKey: settings.apiKey, workspaceID: settings.workspaceID, settings: settings.focus, task: settings.task)
        focus.onChange = { [weak self] snapshot in self?.render(snapshot) }
        focus.start()
    }

    private func render(_ snapshot: FocusSnapshot) {
        overlay.show(snapshot.alarm)
        character.show(snapshot.alarm, line: snapshot.judgement?.line ?? "",
                       shortTask: Self.short(settings.task ?? "", 40))
        guard let button = statusItem.button else { return }
        let symbol: String
        switch (snapshot.alarm, snapshot.pause) {
        case (.hard, _): symbol = "flame.fill"
        case (.soft, _): symbol = "eye.fill"
        case (_, .some): symbol = "pause.circle"
        default: symbol = "scope"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ADHD Killer")
        button.imagePosition = .imageLeading
        button.title = settings.task.map { " " + Self.short($0, 24) } ?? ""
        button.contentTintColor = snapshot.alarm == .none ? nil : .systemRed
    }

    private func statusText(_ snapshot: FocusSnapshot) -> String {
        if snapshot.alarm == .hard { return L.t("🔥 Давно не по делу", "🔥 Off task for a while") }
        if snapshot.alarm == .soft { return L.t("👀 Кажется, отвлёкся", "👀 Looks like a distraction") }
        switch snapshot.pause {
        case .none:
            return snapshot.awaiting ? L.t("Смотрю, что на экране…", "Checking the screen…")
                                     : L.t("Слежу за задачей", "Watching your task")
        case .disabled: return L.t("Выключен", "Turned off")
        case .noKey: return L.t("Нужен ключ Anthropic API", "Anthropic API key needed")
        case .noPermission: return L.t("Нет доступа к окнам", "No access to windows")
        case .noTask: return L.t("Задача не указана", "No task set")
        case .outsideHours: return L.t("Нерабочее время", "Outside working hours")
        case .idle: return L.t("Тебя нет за компьютером", "You are away")
        case .locked: return L.t("Экран заблокирован", "Screen locked")
        case .snoozed(let until):
            let time = DateFormatter.localizedString(from: until, dateStyle: .none, timeStyle: .short)
            return L.t("Перерыв до \(time)", "Break until \(time)")
        case .apiError(let message): return L.t("Ошибка: \(message)", "Error: \(message)")
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let snapshot = focus.snapshot
        info(statusText(snapshot), to: menu)
        if let task = settings.task {
            info(L.t("Задача: ", "Task: ") + Self.short(task, 50), to: menu)
        }
        menu.addItem(.separator())

        add(settings.task == nil ? L.t("Указать задачу…", "Set task…") : L.t("Сменить задачу…", "Change task…"),
            #selector(changeTask), key: "n", to: menu)
        if settings.task != nil {
            add(L.t("Задача сделана ✓", "Task done ✓"), #selector(taskDoneAction), to: menu)
        }
        if snapshot.context != nil && focus.isEnabled {
            add(L.t("Это работа (до конца дня)", "This is work (until tomorrow)"), #selector(thisIsWork), to: menu)
        }
        add(L.t("Перерыв 15 минут", "Break for 15 minutes"), #selector(snooze), to: menu)
        add(L.t("Включён", "Enabled"), #selector(toggleAction), to: menu).state = focus.isEnabled ? .on : .off
        menu.addItem(.separator())

        let usage = focus.usage
        info(L.t("Сегодня: \(usage.todayCalls) проверок · $", "Today: \(usage.todayCalls) checks · $")
             + String(format: "%.3f", usage.todayCost), to: menu)
        add(L.t("Ключ Anthropic API…", "Anthropic API key…"), #selector(askKey), to: menu)
        if snapshot.pause == .noPermission {
            add(L.t("Разрешить доступ к окнам…", "Allow access to windows…"), #selector(openAccessibility), to: menu)
        }
        add(L.t("Запускать при входе", "Open at login"), #selector(toggleLogin), to: menu).state =
            LoginItem.isEnabled ? .on : .off
        add(L.t("Дополнительные настройки…", "Advanced settings…"), #selector(openSettingsFile), to: menu)
        add(L.t("Как это работает", "How it works"), #selector(openHelp), to: menu)
        menu.addItem(.separator())
        add(L.t("Выйти", "Quit"), #selector(quit), key: "q", to: menu)
    }

    private func info(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, key: String = "", to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: - Actions

    @objc private func changeTask() {
        guard let text = ask(title: L.t("Чем занимаешься сейчас?", "What are you working on?"),
                             message: L.t("Одна задача. Всё остальное будет считаться отвлечением.",
                                          "One task. Everything else counts as a distraction."),
                             value: settings.task ?? "",
                             placeholder: L.t("Например: написать пост про запуск", "E.g. write the launch post"))
        else { return }
        settings.task = text.isEmpty ? nil : text
        settings.save()
        focus.task = settings.task
    }

    @objc private func taskDoneAction() { taskDone() }

    private func taskDone() {
        settings.task = nil
        settings.save()
        focus.task = nil
        changeTask()
    }

    @objc private func thisIsWork() { focus.perform(.thisIsWork) }
    @objc private func snooze() { focus.perform(.snooze) }
    @objc private func toggleAction() { toggle() }

    private func toggle() {
        focus.perform(.toggle)
        settings.enabled = focus.isEnabled
        settings.save()
    }

    @objc private func askKey() {
        guard let key = ask(title: L.t("Ключ Anthropic API", "Anthropic API key"),
                            message: L.t("Ключ создаётся на console.anthropic.com → API keys. Он хранится только на этом Маке.",
                                         "Create one at console.anthropic.com → API keys. It stays on this Mac."),
                            value: "", placeholder: "sk-ant-…", secure: true),
              !key.isEmpty else { return }
        settings.apiKey = key
        settings.save()
        restartFocus()
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLogin() { LoginItem.set(!LoginItem.isEnabled) }

    @objc private func openSettingsFile() {
        settings.save()
        let alert = NSAlert()
        alert.messageText = L.t("Файл настроек", "Settings file")
        alert.informativeText = L.t(
            "Здесь можно поменять ID рабочего пространства Anthropic (\"workspaceID\", если ключ его требует), рабочие часы (\"hours\": \"09:00-19:00\"), минуты до предупреждения и модель. После правки нажми «Перезапустить».",
            "Change the Anthropic workspace ID (\"workspaceID\", if your key needs one), working hours (\"hours\": \"09:00-19:00\"), minutes before a warning and the model. Press Restart after editing.")
        alert.addButton(withTitle: L.t("Открыть", "Open"))
        alert.addButton(withTitle: L.t("Перезапустить", "Restart"))
        alert.addButton(withTitle: L.t("Отмена", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(AppSettings.file)
        case .alertSecondButtonReturn:
            settings = AppSettings.load()
            restartFocus()
        default: break
        }
    }

    @objc private func openHelp() {
        if let url = URL(string: "https://github.com/ValikW/adhd-killer#readme") { NSWorkspace.shared.open(url) }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func firstRun() {
        let alert = NSAlert()
        alert.messageText = L.t("Привет! Я СДВГ Киллер", "Hi! I’m ADHD Killer")
        alert.informativeText = L.t(
            "Ты пишешь, чем занимаешься. Я поглядываю, какое окно открыто, и если ты ушёл в сторону — краснею по краям экрана.\n\nНужно две вещи: ключ Anthropic API (за проверки платишь ты, обычно центы в день) и доступ к окнам в настройках Mac.\n\nНазвания окон и адреса сайтов отправляются в Anthropic для оценки. Пароли и менеджеры паролей не проверяются.",
            "You tell me what you’re working on. I glance at the active window, and if you drift off, the screen edges turn red.\n\nTwo things are needed: an Anthropic API key (you pay for checks, usually cents a day) and window access in macOS settings.\n\nWindow titles and site addresses are sent to Anthropic to be judged. Password managers are skipped.")
        alert.addButton(withTitle: L.t("Ввести ключ", "Enter key"))
        alert.addButton(withTitle: L.t("Позже", "Later"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        askKey()
        if !settings.apiKey.isEmpty && settings.task == nil { changeTask() }
        if !LoginItem.isEnabled { LoginItem.set(true) }
    }

    // MARK: - Helpers

    private func ask(title: String, message: String, value: String, placeholder: String,
                     secure: Bool = false) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field: NSTextField = secure ? NSSecureTextField() : NSTextField()
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        field.stringValue = value
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: L.t("Отмена", "Cancel"))
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func short(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }
}
