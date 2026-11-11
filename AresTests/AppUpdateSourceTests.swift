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
