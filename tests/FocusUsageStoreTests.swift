import Foundation

@main
struct FocusUsageStoreTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("usage.json").path
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let next = Calendar.current.date(byAdding: .day, value: 1, to: first)!

        var store = FocusUsageStore(path: path)
        store.record(input: 200, output: 100, at: first)
        assert(!store.saveFailed)
        assert(store.current(at: first).todayCalls == 1)
        store = FocusUsageStore(path: path)
        assert(store.current(at: first).totalCalls == 1)
        assert(store.current(at: first).todayCost > 0)
        assert(store.current(at: next).todayCalls == 0)
        assert(store.current(at: next).totalCalls == 1)
        store.record(input: 300, output: 50, at: next)
        store = FocusUsageStore(path: path)
        assert(store.current(at: next).todayCalls == 1)
        assert(store.current(at: next).totalCalls == 2)
        print("PASS usage survives restart and day rollover")
    }
}
