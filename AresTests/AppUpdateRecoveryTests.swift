import XCTest

final class AppUpdateRecoveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testFeedFailuresUseBoundedBackoffThenLeaveRegularScheduleAlone() {
        var recovery = AppUpdateRecovery()
        for delay in [60.0, 300, 900] {
            recovery.checkStarted(at: now)
            recovery.feedFailed(at: now)
            XCTAssertEqual(recovery.retryAt, now.addingTimeInterval(delay))
        }
        recovery.checkStarted(at: now)
        recovery.feedFailed(at: now)
        XCTAssertTrue(recovery.needsRecovery)
        XCTAssertNil(recovery.retryAt)
    }

    func testSuccessfulFeedOrDisablingAutomaticChecksCancelsRecoveryAndResetsBackoff() {
        var recovery = AppUpdateRecovery()
        recovery.feedFailed(at: now)
        recovery.feedFailed(at: now)
        recovery.reset()
        XCTAssertFalse(recovery.needsRecovery)
        XCTAssertNil(recovery.retryAt)
        recovery.networkRestored(at: now)
        XCTAssertNil(recovery.retryAt)
        recovery.feedFailed(at: now)
        XCTAssertEqual(recovery.retryAt, now.addingTimeInterval(60))
    }

    func testNetworkRecoveryDoesNotHammerFeedDuringVPNPathChanges() {
        var recovery = AppUpdateRecovery()
        recovery.checkStarted(at: now)
        recovery.feedFailed(at: now)
        for second in [1.0, 2, 5, 20] {
            recovery.networkRestored(at: now.addingTimeInterval(second))
            XCTAssertEqual(recovery.retryAt, now.addingTimeInterval(60))
        }
    }

    func testNetworkRestoredCanRecoverAfterBackoffIsExhausted() {
        var recovery = AppUpdateRecovery(retryDelays: [60])
        recovery.checkStarted(at: now)
        recovery.feedFailed(at: now)
        recovery.checkStarted(at: now.addingTimeInterval(60))
        recovery.feedFailed(at: now.addingTimeInterval(60))
        XCTAssertNil(recovery.retryAt)
        recovery.networkRestored(at: now.addingTimeInterval(180))
        XCTAssertEqual(recovery.retryAt, now.addingTimeInterval(180))
    }

    func testWakeAndFocusOnlyResumeOverdueRegularChecks() {
        let recovery = AppUpdateRecovery()
        XCTAssertTrue(recovery.regularCheckIsOverdue(lastCheck: nil, now: now))
        XCTAssertFalse(recovery.regularCheckIsOverdue(lastCheck: now, now: now.addingTimeInterval(3599)))
        XCTAssertTrue(recovery.regularCheckIsOverdue(lastCheck: now, now: now.addingTimeInterval(3600)))
        XCTAssertFalse(recovery.regularCheckIsOverdue(lastCheck: now.addingTimeInterval(60), now: now))
    }
}
