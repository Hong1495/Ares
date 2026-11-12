import XCTest

final class NodeSelectionPlanTests: XCTestCase {
    func testOfflineChoiceSurvivesRelaunchAndIsProfileScoped() throws {
        let first = UUID(), second = UUID()
        var plan = NodeSelectionPlan()
        plan.select(profile: first, group: "Proxy", node: "Node B")
        plan.select(profile: second, group: "Proxy", node: "Node C")
        let restored = try JSONDecoder().decode(NodeSelectionPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(restored.choices(for: first)["Proxy"], "Node B")
        XCTAssertEqual(restored.choices(for: second)["Proxy"], "Node C")
    }
    func testStartupAndTUNRestartRestoreValidManualChoicesAndResetStaleAutomaticChoice() async throws {
        let groups = [ProxyGroup(name: "Proxy", type: "Selector", now: "A", all: ["A", "B"]), ProxyGroup(name: "Auto", type: "URLTest", now: "A", all: ["A", "B"]), ProxyGroup(name: "Fallback", type: "Fallback", now: "A", fixed: "A", all: ["A", "B"])]
        for _ in 0..<2 {
            var applied: [String] = [], reset: [String] = []
            try await NodeSelectionPlan.restore(["Proxy": "B", "Auto": "B", "Removed": "B"], groups: groups, reset: { reset.append($0) }) { group, node in applied.append("\(group):\(node)") }
            XCTAssertEqual(applied, ["Proxy:B", "Auto:B"])
            XCTAssertEqual(reset, ["Fallback"])
        }
    }

    func testSelectorAndAutoGroupManualSelectionSemantics() {
        let selector = ProxyGroup(name: "S", type: "Selector", now: "A", fixed: "B", all: ["A", "B"])
        let auto = ProxyGroup(name: "A", type: "URLTest", now: "A", fixed: "B", all: ["A", "B"])
        XCTAssertTrue(selector.confirmsSelection("A"))
        XCTAssertFalse(selector.confirmsSelection("B"))
        XCTAssertTrue(auto.confirmsSelection("B"))
        XCTAssertFalse(auto.confirmsSelection("A"))
        XCTAssertTrue(ProxyGroup(name: "L", type: "LoadBalance").supportsManualSelection == false)
    }

    func testClearChoiceRemovesOnlyThatGroup() {
        let profile = UUID()
        var plan = NodeSelectionPlan()
        plan.select(profile: profile, group: "A", node: "one")
        plan.select(profile: profile, group: "B", node: "two")
        plan.clear(profile: profile, group: "A")
        XCTAssertNil(plan.choices(for: profile)["A"])
        XCTAssertEqual(plan.choices(for: profile)["B"], "two")
    }
    func testFailedSelectionPreventsActivationSuccess() async {
        do {
            try await NodeSelectionPlan.restore(["Proxy": "B"], groups: [ProxyGroup(name: "Proxy", type: "Selector", all: ["B"])]) { _, _ in throw URLError(.cannotConnectToHost) }
            XCTFail("Activation must fail when a saved choice cannot be confirmed")
        } catch { }
    }
    func testColdTUNStartFailureStopsBeforeRestoringSettings() async {
        var steps: [String] = []
        let outcome = await RuntimeTransition.startStopped(
            activate: { steps.append("launch-failed"); return false },
            stopFailed: { steps.append("stop"); return true },
            restoreSettings: { steps.append("restore") })
        XCTAssertEqual(outcome, .restored)
        XCTAssertEqual(steps, ["launch-failed", "stop", "restore"])
    }
    func testColdTUNCleanupFailureDoesNotClaimRollback() async {
        let outcome = await RuntimeTransition.startStopped(
            activate: { false }, stopFailed: { false }, restoreSettings: { XCTFail() })
        XCTAssertEqual(outcome, .recoveryRequired)
    }

    func testRemovedNodesAreNotApplied() async throws {
        try await NodeSelectionPlan.restore(["Proxy": "Deleted"], groups: [ProxyGroup(name: "Proxy", type: "Selector", all: ["New"])]) { _, _ in XCTFail() }
    }
}
