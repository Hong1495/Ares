import XCTest

extension CoreReleaseSelectorTests {
    static let allTests = [
        ("testParseDisplayVersionPrefersVersionToken", testParseDisplayVersionPrefersVersionToken),
        ("testParseDisplayVersionFallsBackToFirstLine", testParseDisplayVersionFallsBackToFirstLine),
        ("testVersionComparison", testVersionComparison),
        ("testAssetSelectionPrefersDefaultDarwinArm64Asset", testAssetSelectionPrefersDefaultDarwinArm64Asset),
    ]
}

extension PKCS12ImportTests {
    static let allTests = [
        ("testPKCS12ImportProducesIdentity", testPKCS12ImportProducesIdentity),
    ]
}

extension SubscriptionConverterTests {
    static let allTests = [
        ("testRealityPlaceholderIsNotEmitted", testRealityPlaceholderIsNotEmitted),
    ]
}

extension SettingsViewSourceTests {
    static let allTests = [
        ("testSettingsTUNToggleUsesRuntimeSwitch", testSettingsTUNToggleUsesRuntimeSwitch),
    ]
}

extension SystemProxyManagerSourceTests {
    static let allTests = [
        ("testAppleScriptFallbackUsesShellQuotedCommands", testAppleScriptFallbackUsesShellQuotedCommands),
    ]
}

extension AppleScriptEscaperTests {
    static let allTests = [
        ("testStringLiteralEscapesAppleScriptSensitiveCharacters", testStringLiteralEscapesAppleScriptSensitiveCharacters),
    ]
}

extension SystemProxyTerminationSourceTests {
    static let allTests = [
        ("testTerminationCleanupRestoresSnapshotBeforeDisabling", testTerminationCleanupRestoresSnapshotBeforeDisabling),
        ("testTerminationRefusesToStopCoreWhenProxyCleanupFails", testTerminationRefusesToStopCoreWhenProxyCleanupFails),
    ]
}

extension SudoersEscaperTests {
    static let allTests = [
        ("testCommandPathEscapesWhitespaceAndQuotes", testCommandPathEscapesWhitespaceAndQuotes),
        ("testGeneratedRuleWithEscapedCommandPathPassesVisudo", testGeneratedRuleWithEscapedCommandPathPassesVisudo),
        ("testEscapedPathMatchesGeneratedSudoersContent", testEscapedPathMatchesGeneratedSudoersContent),
    ]
}

extension CoreInstallVerifierTests {
    static let allTests = [
        ("testManagedCoreRequiresMatchingManifestHash", testManagedCoreRequiresMatchingManifestHash),
    ]
}
