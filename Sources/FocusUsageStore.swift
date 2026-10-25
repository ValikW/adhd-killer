import Foundation

struct FocusUsage: Codable {
    var day: String
    var todayCalls: Int = 0
    var todayInput: Int = 0
    var todayOutput: Int = 0
    var totalCalls: Int = 0
    var totalInput: Int = 0
    var totalOutput: Int = 0

    var todayCost: Double { Self.cost(input: todayInput, output: todayOutput) }
    var totalCost: Double { Self.cost(input: totalInput, output: totalOutput) }

    private static func cost(input: Int, output: Int) -> Double {
        (Double(input) * FocusCore.Constants.pricePerMillionInput +
         Double(output) * FocusCore.Constants.pricePerMillionOutput) / 1_000_000
    }
}

struct FocusUsageStore {
    private static let path = ("~/Library/Application Support/ADHDKiller/usage.json" as NSString)
        .expandingTildeInPath
    private let path: String
    private var usage: FocusUsage
    private(set) var saveFailed = false

    init(path: String = Self.path) {
        self.path = path
        let saved = FileManager.default.contents(atPath: path)
            .flatMap { try? JSONDecoder().decode(FocusUsage.self, from: $0) }
        usage = saved ?? FocusUsage(day: Self.day(Date()))
    }

    func current(at date: Date = Date()) -> FocusUsage {
        guard usage.day != Self.day(date) else { return usage }
        var result = usage
        result.day = Self.day(date)
        result.todayCalls = 0
        result.todayInput = 0
        result.todayOutput = 0
        return result
    }

    mutating func record(input: Int, output: Int, at date: Date = Date()) {
        usage = current(at: date)
        usage.todayCalls += 1
        usage.todayInput += max(0, input)
        usage.todayOutput += max(0, output)
        usage.totalCalls += 1
        usage.totalInput += max(0, input)
        usage.totalOutput += max(0, output)
        do {
            let folder = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: folder,
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(usage).write(to: URL(fileURLWithPath: path), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                  ofItemAtPath: path)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
