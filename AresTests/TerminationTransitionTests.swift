import XCTest

final class TerminationTransitionTests: XCTestCase {
    @MainActor func testSuccessfulCleanupIsOrderedIdempotentAndKeepsGateUntilAbort() async {
        let transition = TerminationTransition()
        var events: [String] = []
        func run() async -> Bool {
            await transition.prepare(waitUntilIdle: { events.append("wait"); return true },
                restoreProxy: { events.append("proxy"); return true },
                stopCore: { events.append("core"); return true },
                stopDependents: { events.append("dependents") }, didPrepare: { events.append("done") })
        }
        let first = await run()
        let duplicate = await run()
        XCTAssertTrue(first && duplicate)
        XCTAssertEqual(events, ["wait", "proxy", "core", "dependents", "done"])
        XCTAssertTrue(transition.blocksOperations)
        transition.cancelHandoff()
        XCTAssertFalse(transition.blocksOperations)
        let retry = await run()
        XCTAssertTrue(retry)
        XCTAssertEqual(events.count, 10)
    }

    @MainActor func testEveryFailureStopsAtItsBoundaryAndAllowsRetry() async {
        for failedStep in 0..<3 {
            let transition = TerminationTransition()
            var visited: [Int] = []
            let result = await transition.prepare(
                waitUntilIdle: { visited.append(0); return failedStep != 0 },
                restoreProxy: { visited.append(1); return failedStep != 1 },
                stopCore: { visited.append(2); return failedStep != 2 },
                stopDependents: { XCTFail("Must not stop dependents") }, didPrepare: { XCTFail() })
            XCTAssertFalse(result)
            XCTAssertEqual(visited, Array(0...failedStep))
            XCTAssertFalse(transition.blocksOperations)
        }
    }

    @MainActor func testConcurrentRequestAndAbortCannotUnlockActiveCleanup() async {
        let transition = TerminationTransition()
        let result = await transition.prepare(waitUntilIdle: {
            XCTAssertTrue(transition.blocksOperations)
            transition.cancelHandoff()
            XCTAssertTrue(transition.blocksOperations)
            let second = await transition.prepare(waitUntilIdle: { XCTFail(); return true },
                restoreProxy: { XCTFail(); return true }, stopCore: { XCTFail(); return true },
                stopDependents: { XCTFail() }, didPrepare: { XCTFail() })
            XCTAssertFalse(second)
            return true
        }, restoreProxy: { true }, stopCore: { true }, stopDependents: {}, didPrepare: {})
        XCTAssertTrue(result)
        XCTAssertTrue(transition.blocksOperations)
    }

    @MainActor func testCancellationBeforeMutationReleasesGate() async {
        let transition = TerminationTransition()
        let task = Task { @MainActor in
            await transition.prepare(waitUntilIdle: {
                withUnsafeCurrentTask { $0?.cancel() }
                return true
            }, restoreProxy: { XCTFail(); return true }, stopCore: { XCTFail(); return true },
            stopDependents: { XCTFail() }, didPrepare: { XCTFail() })
        }
        let result = await task.value
        XCTAssertFalse(result)
        XCTAssertFalse(transition.blocksOperations)
    }
}
