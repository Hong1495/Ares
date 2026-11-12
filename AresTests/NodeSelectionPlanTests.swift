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
    func testStartupAndTUNRestartRestoreOnlyValidManualChoices() async throws {
        let groups = [ProxyGroup(name: "Proxy", type: "Selector", now: "A", all: ["A", "B"]), ProxyGroup(name: "Auto", type: "URLTest", now: "A", all: ["A", "B"])]
        for _ in 0..<2 {
            var applied: [String] = []
            try await NodeSelectionPlan.restore(["Proxy": "B", "Auto": "B", "Removed": "B"], groups: groups) { group, node in applied.append("\(group):\(node)") }
            XCTAssertEqual(applied, ["Proxy:B"])
        }
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
