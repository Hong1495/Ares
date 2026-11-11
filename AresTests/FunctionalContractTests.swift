import XCTest

final class FunctionalContractTests: XCTestCase {
    private func response(_ status: Int = 200, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://subscription.invalid/test")!, statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    func testProxyCommitRequiresReadBack() async {
        var calls: [String] = []
        let outcome = await ProxyTransaction.apply(write: { calls.append("write"); return true }, verify: { calls.append("verify"); return true }, rollback: { XCTFail(); return true }, verifyRollback: { XCTFail(); return true })
        XCTAssertEqual(outcome, .committed)
        XCTAssertEqual(calls, ["write", "verify"])
    }

    func testProxyPartialWriteRollsBackAndVerifies() async {
        var calls: [String] = []
        let outcome = await ProxyTransaction.apply(write: { calls.append("partial"); return false }, verify: { XCTFail(); return true }, rollback: { calls.append("restore"); return true }, verifyRollback: { calls.append("read-back"); return true })
        XCTAssertEqual(outcome, .rolledBack)
        XCTAssertEqual(calls, ["partial", "restore", "read-back"])
    }

    func testProxyFailedRecoveryRemainsUncertain() async {
        let outcome = await ProxyTransaction.apply(write: { true }, verify: { false }, rollback: { true }, verifyRollback: { false })
        XCTAssertEqual(outcome, .recoveryRequired)
    }

    func testCoreStopFailureNeverStartsReplacement() async {
        let result = await RuntimeTransition.perform(stopCurrent: { false }, activateNew: { XCTFail(); return true }, stopNew: { XCTFail(); return true }, restorePrevious: { XCTFail(); return true })
        XCTAssertEqual(result, .unchanged)
    }

    func testReadinessTimeoutRestartsAndVerifiesPreviousRuntime() async {
        var calls: [String] = []
        let result = await RuntimeTransition.perform(stopCurrent: { calls.append("stop-old"); return true }, activateNew: { calls.append("timeout"); return false }, stopNew: { calls.append("stop-new"); return true }, restorePrevious: { calls.append("restart-and-verify-old"); return true })
        XCTAssertEqual(result, .restored)
        XCTAssertEqual(calls, ["stop-old", "timeout", "stop-new", "restart-and-verify-old"])
    }

    func testRollbackStopFailureNeverLaunchesSecondCore() async {
        let result = await RuntimeTransition.perform(stopCurrent: { true }, activateNew: { false }, stopNew: { false }, restorePrevious: { XCTFail(); return true })
        XCTAssertEqual(result, .recoveryRequired)
    }

    func testRollbackVerificationFailureIsNotSuccess() async {
        let result = await RuntimeTransition.perform(stopCurrent: { true }, activateNew: { false }, stopNew: { true }, restorePrevious: { false })
        XCTAssertEqual(result, .recoveryRequired)
    }

    func testCoreSuccessDoesNotRollback() async {
        let result = await RuntimeTransition.perform(stopCurrent: { true }, activateNew: { true }, stopNew: { XCTFail(); return true }, restorePrevious: { XCTFail(); return true })
        XCTAssertEqual(result, .committed)
    }

    func testHTTPFailuresThrow() throws {
        for code in [301, 401, 404, 500, 503] { XCTAssertThrowsError(try CoreAPIContract.requireSuccess(response(code))) }
        XCTAssertNoThrow(try CoreAPIContract.requireSuccess(response(204)))
    }

    func testProxyNamesAreSingleEncodedSegments() throws {
        let name = "香港 / 🐝 ?#%&"
        let url = try CoreAPIContract.proxyURL(base: "http://127.0.0.1:1", name: name)
        XCTAssertTrue(url.absoluteString.contains("%2F"))
        XCTAssertTrue(url.absoluteString.contains("%25"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertNil(components.query)
        XCTAssertNil(components.fragment)
        XCTAssertEqual(String(components.percentEncodedPath.dropFirst("/proxies/".count)).removingPercentEncoding, name)
    }

    func testDelayUsesQueryItems() throws {
        let url = try CoreAPIContract.proxyURL(base: "http://127.0.0.1:1", name: "a/b", delay: true, timeout: 1234)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first(where: { $0.name == "timeout" })?.value, "1234")
        XCTAssertEqual(items.first(where: { $0.name == "url" })?.value, "http://www.gstatic.com/generate_204")
    }

    func testTUNRequiresMatchingExplicitResponse() throws {
        XCTAssertNoThrow(try CoreAPIContract.verifyTUN(Data(#"{"tun":{"enable":true}}"#.utf8), expected: true))
        for json in [#"{"tun":{"enable":false}}"#, "{}", "invalid"] {
            XCTAssertThrowsError(try CoreAPIContract.verifyTUN(Data(json.utf8), expected: true))
        }
    }

    func testConnectionsDistinguishEmptyFromMalformed() throws {
        let empty = try CoreAPIContract.connections(Data(#"{"connections":[]}"#.utf8))
        XCTAssertEqual((empty["connections"] as? [[String: Any]])?.count, 0)
        let two = try CoreAPIContract.connections(Data(#"{"connections":[{"id":"a"},{"id":"b","process":"Ares"}]}"#.utf8))
        XCTAssertEqual((two["connections"] as? [[String: Any]])?.count, 2)
        XCTAssertThrowsError(try CoreAPIContract.connections(Data("{}".utf8)))
    }

    func testSubscriptionRejectsHTTPErrorBeforeValidation() async {
        do {
            _ = try await SubscriptionPayload.prepare(data: Data("proxies: []".utf8), response: response(403)) { _ in XCTFail(); return true }
            XCTFail("must throw")
        } catch { }
    }

    func testSubscriptionRejectsHTMLAndEmptyBodies() async {
        for body in ["", "  \n", "<html>error</html>"] {
            do {
                _ = try await SubscriptionPayload.prepare(data: Data(body.utf8), response: response()) { _ in XCTFail(); return true }
                XCTFail("must reject")
            } catch { }
        }
    }

    func testBase64ConversionWithQuotaHeader() async throws {
        let body = Data("trojan://password@example.com:443#Test".utf8).base64EncodedData()
        let content = try await SubscriptionPayload.prepare(data: body, response: response(headers: ["subscription-userinfo": "total=1000"])) { candidate in
            XCTAssertTrue(candidate.contains("proxies:"))
            XCTAssertTrue(candidate.contains("trojan"))
            return true
        }
        XCTAssertTrue(content.contains("example.com"))
    }

    func testFailedValidationCannotReplaceExistingFile() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("previous-config".utf8).write(to: file)
        do {
            let candidate = try await SubscriptionPayload.prepare(data: Data("bad: [yaml".utf8), response: response()) { _ in false }
            try candidate.write(to: file, atomically: true, encoding: .utf8)
            XCTFail("invalid payload must not commit")
        } catch { }
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "previous-config")
    }

    func testCancellationFromValidatorPropagates() async {
        do {
            _ = try await SubscriptionPayload.prepare(data: Data("proxies: []".utf8), response: response()) { _ in throw CancellationError() }
            XCTFail()
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testDeletedProfileRejectsPendingResponse() {
        var revisions = ProfileUpdateRevisions()
        let id = UUID(), token = revisions.begin(id)
        revisions.invalidate(id)
        XCTAssertFalse(revisions.isCurrent(token, for: id))
    }

    func testLatestRequestWinsRegardlessOfCompletionOrder() {
        var revisions = ProfileUpdateRevisions()
        let id = UUID()
        let old = revisions.begin(id), newer = revisions.begin(id)
        XCTAssertFalse(revisions.isCurrent(old, for: id))
        XCTAssertTrue(revisions.isCurrent(newer, for: id))
        XCTAssertFalse(revisions.isCurrent(newer, for: UUID()))
    }
    func testListenerStaysAliveWhenProxyMigrationFails() async {
        let migrated = await ListenerMigration.retire(migrateRoutes: { true }, migrateProxy: { false }, stopListener: { XCTFail("traffic may still reference the listener") })
        XCTAssertFalse(migrated)
    }

    func testListenerStaysAliveWhenRoutingMigrationFails() async {
        let migrated = await ListenerMigration.retire(migrateRoutes: { false }, migrateProxy: { XCTFail(); return true }, stopListener: { XCTFail() })
        XCTAssertFalse(migrated)
    }

    func testListenerStopsOnlyAfterBothPathsMigrate() async {
        var calls: [String] = []
        let migrated = await ListenerMigration.retire(migrateRoutes: { calls.append("routes"); return true }, migrateProxy: { calls.append("proxy"); return true }, stopListener: { calls.append("stop") })
        XCTAssertTrue(migrated)
        XCTAssertEqual(calls, ["routes", "proxy", "stop"])
    }

    func testInvalidURIConversionCannotBecomeEmptyConfig() async {
        do {
            _ = try await SubscriptionPayload.prepare(data: Data("vmess://invalid".utf8), response: response()) { _ in XCTFail("empty conversion must not reach validator"); return true }
            XCTFail()
        } catch { }
    }

}
