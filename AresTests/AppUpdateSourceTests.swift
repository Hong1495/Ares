import XCTest

final class AppUpdateSourceTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(path), encoding: .utf8)
    }

    func testInstallationWaitsForNetworkCleanupAndKeepsRetry() throws {
        let text = try source("Ares/Services/AppUpdateService.swift")
        let cleanup = try XCTUnwrap(text.range(of: "guard await AppTerminationCoordinator.shared.prepareForTermination() else"))
        let install = try XCTUnwrap(text.range(of: "            install()"))
        XCTAssertLessThan(cleanup.lowerBound, install.lowerBound)
        XCTAssertTrue(text.contains("pendingInstall = installHandler"))
        XCTAssertTrue(text.contains("if pendingInstall != nil { resumeInstallation(); return }"))
        XCTAssertTrue(text.contains("updateShutdownPrepared = true"))
    }

    func testAutomaticChecksUseGentleReminderWithoutAutomaticInstall() throws {
        let text = try source("Ares/Services/AppUpdateService.swift")
        XCTAssertTrue(text.contains("supportsGentleScheduledUpdateReminders: Bool { true }"))
        XCTAssertTrue(text.contains("andInImmediateFocus immediateFocus: Bool) -> Bool { false }"))
        XCTAssertTrue(text.contains("automaticallyDownloadsUpdates = false"))
        XCTAssertTrue(text.contains("controller.updater.sessionInProgress"))
        XCTAssertTrue(text.contains("Data(base64Encoded: key)?.count == 32"))
    }

    func testStartupCheckRespectsPreferenceAndScheduledSessionsRemainOpenable() throws {
        let text = try source("Ares/Services/AppUpdateService.swift")
        XCTAssertTrue(text.contains("if automaticallyChecks {\n                controller.updater.checkForUpdatesInBackground()"))
        let method = try XCTUnwrap(text.range(of: "    func checkForUpdates()"))
        let session = try XCTUnwrap(text.range(of: "if controller.updater.sessionInProgress", range: method.lowerBound..<text.endIndex))
        let availability = try XCTUnwrap(text.range(of: "guard controller.updater.canCheckForUpdates", range: method.lowerBound..<text.endIndex))
        XCTAssertLessThan(session.lowerBound, availability.lowerBound)
    }

    func testUpdateExitDoesNotRepeatCompletedCleanup() throws {
        let text = try source("Ares/AresApp.swift")
        let method = try XCTUnwrap(text.range(of: "func applicationWillTerminate"))
        let skip = try XCTUnwrap(text.range(of: "if AppTerminationCoordinator.shared.updateShutdownPrepared { return }", range: method.lowerBound..<text.endIndex))
        let cleanup = try XCTUnwrap(text.range(of: "SystemProxyManager.shared.disableAllProxiesSync()", range: method.lowerBound..<text.endIndex))
        XCTAssertLessThan(skip.lowerBound, cleanup.lowerBound)
    }

    func testIndicatorUsesNativeGeometryAndNoProductionDependencies() throws {
        let text = try source("Ares/UI/DesignSystem/WindowUpdateIndicator.swift")
        XCTAssertTrue(text.contains("g.minX + (g.midX - y.midX)"))
        XCTAssertTrue(text.contains("version != nil"))
        XCTAssertTrue(text.contains("!window.styleMask.contains(.fullScreen)"))
        for dependency in ["import Sparkle", "AppState", "URLSession", "Process(", "UserDefaults"] {
            XCTAssertFalse(text.contains(dependency))
        }
    }

    func testSparkleKeysAreInBuiltPlistSource() throws {
        let text = try source("Configuration/Ares-Info.plist")
        XCTAssertTrue(text.contains("<key>SUEnableAutomaticChecks</key><true/>"))
        XCTAssertTrue(text.contains("<key>SUAutomaticallyUpdate</key><false/>"))
        XCTAssertTrue(text.contains("$(ARES_UPDATE_PUBLIC_KEY)"))
        XCTAssertTrue(text.contains("$(ARES_UPDATE_FEED_URL)"))
    }
}
