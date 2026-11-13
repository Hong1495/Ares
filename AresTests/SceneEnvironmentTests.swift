import XCTest

final class SceneEnvironmentTests: XCTestCase {
    let profile = UUID()
    let wifi = SceneEnvironment(available: true, kind: "wifi", interface: "en0", expensive: false, constrained: false)
    func scene(priority: Int, profile: UUID? = nil, kind: String = "wifi") throws -> ManualScenario {
        var item = try ManualScenario(name: UUID().uuidString, profileID: profile ?? self.profile, sourceRevision: "r", settings: .init(localRules: nil, dns: nil, policy: nil, egress: nil))
        item.trigger = SceneTrigger(enabled: true, kind: kind, priority: priority)
        return item
    }
    func testPriorityConflictProfileIsolationAndUnavailable() throws {
        let first = try scene(priority: 10), second = try scene(priority: 20), third = try scene(priority: 20)
        XCTAssertEqual(SceneMatcher.evaluate([first, second], profile: profile, environment: wifi).winner, second.id)
        let conflict = SceneMatcher.evaluate([first, second, third], profile: profile, environment: wifi)
        XCTAssertNil(conflict.winner); XCTAssertTrue(conflict.conflict)
        XCTAssertNil(SceneMatcher.evaluate([first], profile: UUID(), environment: wifi).winner)
        XCTAssertNil(SceneMatcher.evaluate([first], profile: profile, environment: .unknown).winner)
        XCTAssertNil(SceneMatcher.evaluate([try scene(priority: 1, kind: "wired")], profile: profile, environment: wifi).winner)
    }
    func testAllConditionsAndInvalidCatchAll() throws {
        var trigger = SceneTrigger(enabled: true)
        XCTAssertThrowsError(try trigger.validate())
        trigger.interface = "en0"; trigger.cost = "no"; trigger.constrained = "no"
        XCTAssertNoThrow(try trigger.validate())
        XCTAssertNil(trigger.reason(environment: wifi))
        var changed = wifi; changed.expensive = true
        XCTAssertNotNil(trigger.reason(environment: changed))
        changed = wifi; changed.interface = ""
        XCTAssertNotNil(trigger.reason(environment: changed))
        trigger.priority = 101
        XCTAssertThrowsError(try trigger.validate())
    }
    func testDebounceFlappingCooldownAndBlockedReset() {
        var state = SceneDebounce()
        XCTAssertFalse(state.ready(key: "A", now: 0))
        XCTAssertFalse(state.ready(key: "A", now: 9))
        XCTAssertFalse(state.ready(key: "B", now: 10))
        XCTAssertFalse(state.ready(key: "A", now: 12))
        XCTAssertTrue(state.ready(key: "A", now: 22))
        state.attempted(now: 22)
        XCTAssertFalse(state.ready(key: "B", now: 23))
        XCTAssertFalse(state.ready(key: "B", now: 40))
        XCTAssertTrue(state.ready(key: "B", now: 52))
        XCTAssertFalse(state.ready(key: nil, now: 53))
        XCTAssertFalse(state.ready(key: "B", now: 54))
    }
    func testLegacySceneKeepsModeAndChoicesAndExplicitEmptyResets() {
        let legacy = ScenarioSettings(localRules: nil, dns: nil, policy: nil, egress: nil)
        var current = legacy; current.mode = "global"; current.selections = ["Select": "A"]
        XCTAssertEqual(legacy.resolvingRouting(from: current), current)
        var target = legacy; target.mode = "direct"; target.selections = [:]
        XCTAssertEqual(target.resolvingRouting(from: current).selections, [:])
        XCTAssertEqual(target.differences(from: current).count, 2)
    }
    func testStrictNodeChoicesRejectRemovedAndNonSelectableGroups() throws {
        let groups = [ProxyGroup(name: "Select", type: "Selector", all: ["A"]), ProxyGroup(name: "Balance", type: "LoadBalance", all: ["A"])]
        XCTAssertNoThrow(try NodeSelectionPlan.validate(["Select": "A"], groups: groups))
        for choices in [["Missing": "A"], ["Select": "Gone"], ["Balance": "A"]] {
            XCTAssertThrowsError(try NodeSelectionPlan.validate(choices, groups: groups))
        }
    }
}
