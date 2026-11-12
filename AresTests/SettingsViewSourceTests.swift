import XCTest

final class SettingsViewSourceTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testSettingsTUNToggleUsesRuntimeSwitch() throws {
        let source = try String(contentsOf: projectRoot.appendingPathComponent("Ares/UI/SettingsView.swift"))

        XCTAssertTrue(source.contains("appState.toggleTUN()"))
        XCTAssertFalse(source.contains("@AppStorage(DefaultsKeys.tunEnabled)"))
    }

    func testDashboardUsesAdaptiveComposition() throws {
        let source = try String(contentsOf: projectRoot.appendingPathComponent("Ares/UI/DashboardView.swift"))

        // Cards must reflow with the window rather than using a hardcoded column count.
        let presentation = try String(contentsOf: projectRoot.appendingPathComponent("Ares/UI/DesignSystem/OverviewPresentation.swift"))
        XCTAssertTrue(source.contains("DashboardComposition {"))
        XCTAssertTrue(presentation.contains("geometry.size.width >= 850"))
        XCTAssertFalse(source.contains("showAdvanced"))
        XCTAssertFalse(source.contains("DisclosureGroup"))
        XCTAssertFalse(source.contains("[GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]"))
        XCTAssertFalse(source.contains("Divider().frame(height: 44)"))
    }

    func testDashboardCardsDoNotHardcodeHeights() throws {
        let components = projectRoot.appendingPathComponent("Ares/UI/Components")
        let cards = [
            "ConnectivityCard.swift"
        ]

        for card in cards {
            let source = try String(
                contentsOf: components.appendingPathComponent(card),
                encoding: .utf8
            )
            XCTAssertFalse(
                source.contains(".frame(height: 150)"),
                "\(card) must size to its content instead of a fixed 150pt height"
            )
            XCTAssertTrue(
                source.contains("DSCard"),
                "\(card) should use the shared card surface"
            )
        }
    }

    func testDesignSystemDefinesSemanticColors() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Ares/UI/DesignSystem/DesignSystem.swift")
        )

        XCTAssertTrue(source.contains("static let seriesDown"))
        XCTAssertTrue(source.contains("static let seriesUp"))
        XCTAssertTrue(source.contains("static func latency("))
        XCTAssertTrue(source.contains("static func adaptive("))
    }

    func testAppShowsNativeMenuAndRemainsRunningWhenWindowCloses() throws {
        let projectSource = try String(contentsOf: projectRoot.appendingPathComponent("Ares.xcodeproj/project.pbxproj"))
        let appSource = try String(contentsOf: projectRoot.appendingPathComponent("Ares/AresApp.swift"))
        let setting = "INFOPLIST_KEY_LSUIElement = NO;"

        XCTAssertEqual(projectSource.components(separatedBy: setting).count - 1, 2)
        XCTAssertTrue(appSource.contains("ProcessInfo.processInfo.disableAutomaticTermination"))
        XCTAssertFalse(projectSource.contains("INFOPLIST_KEY_LSUIElement = YES;"))
        XCTAssertTrue(appSource.contains("func applicationShouldTerminateAfterLastWindowClosed"))
        XCTAssertTrue(appSource.contains("WorkspaceCommands("))
    }

    func testAppSourcesDoNotUseConsolePrint() throws {
        let aresRoot = projectRoot.appendingPathComponent("Ares")
        let enumerator = FileManager.default.enumerator(
            at: aresRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var offenders: [String] = []
        while let file = enumerator?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            let source = try String(contentsOf: file)
            if source.range(of: #"\bprint\s*\("#, options: .regularExpression) != nil {
                offenders.append(file.path.replacingOccurrences(of: projectRoot.path + "/", with: ""))
            }
        }

        XCTAssertTrue(offenders.isEmpty, "Unexpected console print calls: \(offenders.joined(separator: ", "))")
    }

    func testProxyStartsCoreBeforeEnablingSystemProxy() throws {
        let source = try String(contentsOf: projectRoot.appendingPathComponent("Ares/Services/AppState+Proxy.swift"))
        let start = try XCTUnwrap(source.range(of: "await clashViewModel.start()"))
        let proxy = try XCTUnwrap(source.range(of: "setSystemProxy(enabled: newState"))
        XCTAssertLessThan(start.lowerBound, proxy.lowerBound)
        XCTAssertTrue(source.contains("systemProxyManager.lastError"))
        XCTAssertFalse(source.contains("previous network state was kept"))
    }

    func testConfigMutationsValidateHTTPStatus() throws {
        let source = try String(contentsOf: projectRoot.appendingPathComponent("Ares/Services/ClashController+Config.swift"))
        XCTAssertTrue(source.contains("validateMutationResponse"))
        XCTAssertTrue(source.contains("200...299"))
    }

    func testSettingsUseRuntimeMITMAndSharedDNSPreference() throws {
        let settings = try String(contentsOf: projectRoot.appendingPathComponent("Ares/UI/SettingsView.swift"))
        let config = try String(contentsOf: projectRoot.appendingPathComponent("Ares/Models/ClashConfig.swift"))
        XCTAssertTrue(settings.contains("DefaultsKeys.dnsServers"))
        XCTAssertFalse(settings.contains("@AppStorage(DefaultsKeys.mitmEnabled)"))
        XCTAssertTrue(config.contains("DefaultsKeys.dnsServers"))
    }

    func testDataPagesExposeEmptyStates() throws {
        let analysis = try String(contentsOf: projectRoot.appendingPathComponent("Ares/UI/AnalysisView.swift"))
        let logs = try String(contentsOf: projectRoot.appendingPathComponent("Ares/UI/LogsView.swift"))
        let activity = try String(contentsOf: projectRoot.appendingPathComponent("Ares/UI/ConnectionsView.swift"))
        XCTAssertTrue(analysis.contains("ContentUnavailableView"))
        XCTAssertTrue(logs.contains("ContentUnavailableView"))
        XCTAssertTrue(activity.contains("ContentUnavailableView"))
    }
}
