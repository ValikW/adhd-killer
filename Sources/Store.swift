import Foundation

/// Two-language strings: Russian when the Mac is in Russian, English otherwise.
enum L {
    static let isRussian = Locale.preferredLanguages.first?.hasPrefix("ru") ?? false
    static func t(_ ru: String, _ en: String) -> String { isRussian ? ru : en }
}

/// Everything the app remembers, in one JSON file the user can open and edit.
struct AppSettings: Codable {
    var apiKey: String = ""
    var workspaceID: String = ""
    var task: String? = nil
    var enabled: Bool = true
    var softSound: String = "Funk"
    var hardSound: String = "Sosumi"
    var offTaskMinutes: Int = 1
    var hardAfterMinutes: Int = 2
    var hours: String = ""
    var weekdaysOnly: Bool = false
    var model: String = "claude-haiku-4-5"
    var allowApps: [String] = []
    var ignoreApps: [String] = ["com.1password.1password", "com.apple.keychainaccess",
                                "com.apple.Passwords"]

    init() {}

    // Missing fields fall back to defaults so old files keep working after updates.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? d.apiKey
        workspaceID = try c.decodeIfPresent(String.self, forKey: .workspaceID) ?? d.workspaceID
        task = try c.decodeIfPresent(String.self, forKey: .task)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        softSound = try c.decodeIfPresent(String.self, forKey: .softSound) ?? d.softSound
        hardSound = try c.decodeIfPresent(String.self, forKey: .hardSound) ?? d.hardSound
        offTaskMinutes = try c.decodeIfPresent(Int.self, forKey: .offTaskMinutes) ?? d.offTaskMinutes
        hardAfterMinutes = try c.decodeIfPresent(Int.self, forKey: .hardAfterMinutes) ?? d.hardAfterMinutes
        hours = try c.decodeIfPresent(String.self, forKey: .hours) ?? d.hours
        weekdaysOnly = try c.decodeIfPresent(Bool.self, forKey: .weekdaysOnly) ?? d.weekdaysOnly
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        allowApps = try c.decodeIfPresent([String].self, forKey: .allowApps) ?? d.allowApps
        ignoreApps = try c.decodeIfPresent([String].self, forKey: .ignoreApps) ?? d.ignoreApps
    }

    var focus: FocusSettings {
        FocusSettings(enabled: enabled, strict: true, hours: hours, weekdaysOnly: weekdaysOnly,
                      offTaskMinutes: offTaskMinutes, hardAfterMinutes: hardAfterMinutes,
                      allowApps: allowApps, ignoreApps: ignoreApps, model: model)
    }

    static let folder = URL(fileURLWithPath: ("~/Library/Application Support/ADHDKiller" as NSString)
        .expandingTildeInPath)
    static let file = folder.appendingPathComponent("settings.json")

    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: file),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try encoder.encode(self).write(to: Self.file, options: .atomic)
            // The file holds the API key: only this user may read it.
            try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                  ofItemAtPath: Self.file.path)
        } catch {
            NSLog("ADHDKiller: cannot save settings: \(error)")
        }
    }
}

/// Start at login through a per-user LaunchAgent: works without an Apple developer signature.
enum LoginItem {
    private static let label = "com.valikw.adhdkiller"
    private static let plist = URL(fileURLWithPath: ("~/Library/LaunchAgents/\(label).plist" as NSString)
        .expandingTildeInPath)

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plist.path) }

    static func set(_ enabled: Bool) {
        if !enabled {
            try? FileManager.default.removeItem(at: plist)
            return
        }
        let agent: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-g", Bundle.main.bundlePath],
            "RunAtLoad": true,
        ]
        do {
            try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: agent,
                                                          format: .xml, options: 0)
            try data.write(to: plist, options: .atomic)
        } catch {
            NSLog("ADHDKiller: cannot write login item: \(error)")
        }
    }
}
