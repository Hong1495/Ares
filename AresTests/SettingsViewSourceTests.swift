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

    func testDashboardGridUsesAdaptiveColumns() throws {
        let source = try String(contentsOf: projectRoot.appendingPathComponent("Ares/UI/DashboardView.swift"))

        XCTAssertTrue(source.contains("GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 16)"))
        XCTAssertTrue(source.contains("GridItem(.adaptive(minimum: 180), spacing: 12)"))
        XCTAssertFalse(source.contains("[GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]"))
        XCTAssertFalse(source.contains("Divider().frame(height: 44)"))
    }

    func testAppRunsAsMenuBarAgent() throws {
        let projectSource = try String(contentsOf: projectRoot.appendingPathComponent("Ares.xcodeproj/project.pbxproj"))
        let appSource = try String(contentsOf: projectRoot.appendingPathComponent("Ares/AresApp.swift"))
        let setting = "INFOPLIST_KEY_LSUIElement = YES;"

        XCTAssertEqual(projectSource.components(separatedBy: setting).count - 1, 2)
        XCTAssertTrue(appSource.contains("ProcessInfo.processInfo.disableAutomaticTermination"))
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
}
