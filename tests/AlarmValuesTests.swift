import Foundation

@main
struct AlarmValuesTests {
    @MainActor static func main() throws {
        let formatter = ISO8601DateFormatter()
        func date(_ text: String) -> Date { formatter.date(from: text)! }
        var assertions = 0
        func check(_ condition: Bool, _ message: String) { precondition(condition, message); assertions += 1 }
        let now = date("2026-11-21T00:00:00Z")
        check(try AlarmValues.next(["at_ms": Int64(now.timeIntervalSince1970 * 1000) + 12345], now: now) == now.addingTimeInterval(12.345), "Absolute time")
        check(try AlarmValues.next(["countdown_seconds": 1.5], now: now) == now.addingTimeInterval(1.5), "Fractional countdown")
        check(try AlarmValues.next(["hour": 7, "minute": 30, "weekdays": [1], "timezone": "UTC"], now: now) == date("2026-11-23T07:30:00Z"), "ISO Monday")
        check(try AlarmValues.next(["hour": 7, "minute": 30, "weekdays": [7], "timezone": "UTC"], now: now) == date("2026-11-22T07:30:00Z"), "ISO Sunday")
        check(try AlarmValues.next(["hour": 2, "minute": 30, "weekdays": [7], "timezone": "America/New_York"], now: date("2026-03-08T00:00:00Z")) == date("2026-03-08T07:30:00Z"), "DST gap")
        check(try AlarmValues.next(["hour": 1, "minute": 30, "weekdays": [7], "timezone": "America/New_York"], now: date("2026-11-01T00:00:00Z")) == date("2026-11-01T05:30:00Z"), "DST first occurrence")
        var alarm = try AlarmValues.parse("{\"label\":\"Exercise\",\"metadata\":{\"customerKey\":42},\"schedule\":{\"countdown_seconds\":60},\"challenge\":{\"kind\":\"pushups\",\"target\":10}}", now: now)
        check((alarm["metadata"] as? [String: Int])?["customerKey"] == 42, "Opaque metadata")
        check(try !AlarmValues.complete(alarm), "Challenge starts incomplete")
        var challenge = alarm["challenge"] as! [String: Any]; challenge["progress"] = 10; alarm["challenge"] = challenge
        check(try AlarmValues.complete(alarm), "Challenge target")
        let invalid = [
            "{\"schedule\":{\"countdown_seconds\":0}}", "{\"schedule\":{\"at_ms\":999999,\"countdown_seconds\":1}}",
            "{\"schedule\":{\"hour\":24,\"minute\":0}}", "{\"schedule\":{\"hour\":1.5,\"minute\":0}}",
            "{\"schedule\":{\"hour\":1,\"minute\":0,\"weekdays\":[0]}}", "{\"schedule\":{\"at_ms\":true}}",
            "{\"enabled\":\"true\",\"schedule\":{\"countdown_seconds\":1}}", "{\"id\":\"1-1-1-1-1\",\"schedule\":{\"countdown_seconds\":1}}",
            "{\"schedule\":{\"countdown_seconds\":1},\"challenge\":{\"kind\":\"any\",\"target\":10,\"progress\":11}}",
            "{\"schedule\":{\"countdown_seconds\":1,\"weekdays\":[1]}}",
            "{\"delivery\":true,\"schedule\":{\"countdown_seconds\":1}}", "{\"color\":42,\"schedule\":{\"countdown_seconds\":1}}",
            "{\"schedule\":{\"hour\":1,\"minute\":0,\"timezone\":42}}", "{\"snooze_label\":{},\"schedule\":{\"countdown_seconds\":1}}"
        ]
        for source in invalid {
            do { _ = try AlarmValues.parse(source, now: now); preconditionFailure("Accepted invalid alarm") }
            catch { assertions += 1 }
        }
        var fractional = try AlarmValues.parse("{\"schedule\":{\"countdown_seconds\":60},\"challenge\":{\"kind\":\"distance\",\"target\":0.5,\"configuration\":{\"unit\":\"km\"}}}", now: now)
        var fractionalChallenge = fractional["challenge"] as! [String: Any]
        fractionalChallenge["progress"] = try AlarmValues.checkedProgress(AlarmValues.progressText("5e-1"), target: 0.5)
        fractional["challenge"] = fractionalChallenge
        check(try AlarmValues.complete(fractional), "Fractional target completes")
        check((fractionalChallenge["configuration"] as? [String: String])?["unit"] == "km", "Custom challenge configuration preserved")
        for text in ["NaN", "nan", "Inf", "Infinity", "-Infinity", "1e309", "words", "", " 0.5", "0x1.0p0"] {
            do { _ = try AlarmValues.progressText(text); preconditionFailure("Accepted nonfinite progress") }
            catch { assertions += 1 }
        }
        for progress in [-0.1, 0.6, Double.nan, Double.infinity] {
            do { _ = try AlarmValues.checkedProgress(progress, target: 0.5); preconditionFailure("Accepted out of bounds") }
            catch { assertions += 1 }
        }
        let disabled: [String: Any] = ["id": "logical", "enabled": false, "delivery": "system"]
        check(AlarmValues.nativeHandles(disabled).isEmpty, "Disabled definition owns no native alarm")
        var pendingCleanup = disabled
        pendingCleanup["native_handles"] = [["id": "previous", "delivery": "system"]]
        check(AlarmValues.nativeHandles(pendingCleanup).count == 1, "Disabled replacement retains previous cleanup")
        pendingCleanup["native_handles"] = [[String: String]]()
        check(AlarmValues.nativeHandles(pendingCleanup).isEmpty, "Explicit empty ownership stays empty")
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ledger = try AlarmLedger(directory: directory)
        try ledger.put(alarm)
        let id = alarm["id"] as! String
        check(try ledger.get(id)["label"] as? String == "Exercise", "Stored alarm")
        let receipt = try ledger.event("saved", id: id)
        check(try !ledger.importEvent(receipt), "Duplicate imported receipt")
        let imported: [String: Any] = ["id": "open-receipt", "type": "opened", "alarm_id": id, "at_ms": 1, "details": [:]]
        check(try ledger.importEvent(imported), "Opened event imported")
        check(try !ledger.importEvent(imported), "Opened event is idempotent")
        let reloaded = try AlarmLedger(directory: directory)
        check(reloaded.list().count == 1, "Durable definition")
        check(reloaded.events().count == 2, "Durable events")
        check(try reloaded.acknowledge([receipt["id"] as! String]) == 1, "Event acknowledgement")
        check(try reloaded.acknowledge([receipt["id"] as! String]) == 0, "Duplicate acknowledgement")
        try reloaded.remove(id)
        check(reloaded.list().isEmpty, "Alarm deletion")
        print("Alarm values and persistence: \(assertions) assertions passed")
    }
}
