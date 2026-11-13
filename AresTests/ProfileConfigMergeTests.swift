import XCTest

final class ProfileConfigMergeTests: XCTestCase {
    func testRuntimeOwnershipIncludesTUNOffAndLeavesAdvancedPoliciesInherited() {
        XCTAssertTrue(ProfileConfigMerge.runtimePaths.contains(["tun", "enable"]))
        for path in [["dns"], ["tun"], ["sniffer"], ["unified-delay"], ["tcp-concurrent"], ["mptcp"]] {
            XCTAssertFalse(ProfileConfigMerge.runtimePaths.contains(path))
        }
    }

    func testExplicitPreferencesAndTUNMode() throws {
        let name = "AresMergeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(ProfileConfigMerge.overridePaths(defaults: defaults, tunEnabled: false), ProfileConfigMerge.runtimePaths)
        defaults.set("1.1.1.1", forKey: DefaultsKeys.dnsServers)
        defaults.set(false, forKey: DefaultsKeys.tunAutoRoute)
        let normal = ProfileConfigMerge.overridePaths(defaults: defaults, tunEnabled: false)
        XCTAssertTrue(normal.contains(["dns", "nameserver"]))
        XCTAssertFalse(normal.contains(["tun", "auto-route"]))
        let tun = ProfileConfigMerge.overridePaths(defaults: defaults, tunEnabled: true)
        XCTAssertTrue(tun.contains(["tun", "auto-route"]))
        XCTAssertTrue(tun.contains(["dns", "enable"]))
    }

    func testEditingOneSettingDoesNotCreateUnrelatedOverridesAndRollbackRestoresAbsence() throws {
        let name = "AresMergeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let displayed: [String: Any] = [DefaultsKeys.dnsServers: "223.5.5.5", DefaultsKeys.tunMTU: 1400]
        var proposed = displayed
        proposed[DefaultsKeys.tunMTU] = 1500
        let change = NetworkPreferenceChange(proposed: proposed, displayed: displayed, defaults: defaults)
        change.apply(to: defaults)
        XCTAssertEqual(defaults.integer(forKey: DefaultsKeys.tunMTU), 1500)
        XCTAssertNil(defaults.object(forKey: DefaultsKeys.dnsServers))
        change.restore(in: defaults)
        XCTAssertNil(defaults.object(forKey: DefaultsKeys.tunMTU))
        defaults.set(1300, forKey: DefaultsKeys.tunMTU)
        let second = NetworkPreferenceChange(proposed: proposed, displayed: displayed, defaults: defaults)
        second.apply(to: defaults)
        second.restore(in: defaults)
        XCTAssertEqual(defaults.integer(forKey: DefaultsKeys.tunMTU), 1300)
    }
    func testRestoringInheritanceRemovesLocalValueAndRollbackRecoversIt() throws {
        let name = "AresMergeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let key = DefaultsKeys.tunAutoRoute
        defaults.set(false, forKey: key)
        let change = NetworkPreferenceChange(proposed: [key: true], displayed: [key: false],
            defaults: defaults, removals: [key])
        change.apply(to: defaults)
        XCTAssertNil(defaults.object(forKey: key))
        XCTAssertFalse(ProfileConfigMerge.overridePaths(defaults: defaults, tunEnabled: true).contains(["tun", "auto-route"]))
        change.restore(in: defaults)
        XCTAssertEqual(defaults.object(forKey: key) as? Bool, false)
    }

    func testExplicitOverrideIsSavedEvenWhenValueEqualsDisplayedDefault() throws {
        let name = "AresMergeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let key = DefaultsKeys.tunMTU
        let change = NetworkPreferenceChange(proposed: [key: 1400], displayed: [key: 1400],
            defaults: defaults, forced: [key])
        change.apply(to: defaults)
        XCTAssertEqual(defaults.integer(forKey: key), 1400)
        change.restore(in: defaults)
        XCTAssertNil(defaults.object(forKey: key))
    }

}
