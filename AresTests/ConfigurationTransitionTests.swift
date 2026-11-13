import XCTest

final class ConfigurationTransitionTests: XCTestCase {
    func testPreparationFailureNeverStopsAndRestoresPreferences() async {
        var events: [String] = []
        let outcome = await ConfigurationTransition.perform(
            prepare: { events.append("prepare"); throw URLError(.cannotParseResponse) },
            stop: { XCTFail(); return true }, activate: { XCTFail(); return true },
            stopFailed: { XCTFail(); return true }, restore: { XCTFail(); return true },
            undoPreparation: { events.append("undo"); return true })
        XCTAssertEqual(outcome, .preparationFailed)
        XCTAssertEqual(events, ["prepare", "undo"])
    }
    func testFailedStopNeverStartsAnotherCore() async {
        let outcome = await ConfigurationTransition.perform(prepare: {}, stop: { false },
            activate: { XCTFail(); return true }, stopFailed: { XCTFail(); return true },
            restore: { XCTFail(); return true }, undoPreparation: { true })
        XCTAssertEqual(outcome, .unchanged)
    }
    func testFailedActivationRecoversOnlyAfterConfirmedCleanup() async {
        for cleanup in [false, true] {
            var restored = false
            let outcome = await ConfigurationTransition.perform(prepare: {}, stop: { true },
                activate: { false }, stopFailed: { cleanup }, restore: { restored = true; return true },
                undoPreparation: { XCTFail(); return true })
            XCTAssertEqual(restored, cleanup)
            XCTAssertEqual(outcome, cleanup ? .restored : .recoveryRequired)
        }
    }
    func testRollbackAndPreparationRecoveryFailuresAreExplicit() async {
        let rollback = await ConfigurationTransition.perform(prepare: {}, stop: { true }, activate: { false },
            stopFailed: { true }, restore: { false }, undoPreparation: { true })
        XCTAssertEqual(rollback, .recoveryRequired)
        let preparation = await ConfigurationTransition.perform(prepare: { throw URLError(.timedOut) },
            stop: { XCTFail(); return true }, activate: { XCTFail(); return true },
            stopFailed: { XCTFail(); return true }, restore: { XCTFail(); return true }, undoPreparation: { false })
        XCTAssertEqual(preparation, .recoveryRequired)
    }
    func testSuccessOnlyStartsOnceAndDoesNotRestore() async {
        var events: [String] = []
        let result = await ConfigurationTransition.perform(prepare: { events.append("prepare") },
            stop: { events.append("stop"); return true }, activate: { events.append("activate"); return true },
            stopFailed: { XCTFail(); return true }, restore: { XCTFail(); return true }, undoPreparation: { XCTFail(); return true })
        XCTAssertEqual(result, .committed)
        XCTAssertEqual(events, ["prepare", "stop", "activate"])
    }
    func testCancellationAfterPreparationRestoresWithoutStoppingCore() async {
        let task = Task {
            await ConfigurationTransition.perform(prepare: { withUnsafeCurrentTask { $0?.cancel() } },
                stop: { XCTFail(); return true }, activate: { XCTFail(); return true },
                stopFailed: { XCTFail(); return true }, restore: { XCTFail(); return true }, undoPreparation: { true })
        }
        let outcome = await task.value
        XCTAssertEqual(outcome, .preparationFailed)
    }

}
