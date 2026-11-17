import XCTest
import Combine

final class TrafficHistoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    @MainActor
    func testNavigationResubscriptionRetainsMeasuredHistoryWithoutInventingSamples() {
        let history = TrafficHistory()
        history.record(upload: 40, download: 200, at: start)
        var firstPage: TrafficHistoryBuffer?
        var subscription: AnyCancellable? = history.$snapshot.sink { firstPage = $0 }
        XCTAssertEqual(firstPage?.points.count, 1)
        subscription?.cancel()
        subscription = nil

        // The controller continues receiving rates while another page is open.
        history.record(upload: 80, download: 400, at: start.addingTimeInterval(1))
        var returningPage: TrafficHistoryBuffer?
        let returnedSubscription = history.$snapshot.sink { returningPage = $0 }
        XCTAssertEqual(returningPage?.points.count, 2)
        XCTAssertEqual(returningPage?.points.map(\.download), [200, 400])
        XCTAssertEqual(returningPage?.currentUpload, 80)
        XCTAssertEqual(history.snapshot.points.count, 2)
        withExtendedLifetime(returnedSubscription) {}
    }

    func testPauseRetainsSamplesAndSeparatesUnmeasuredTimeFromRealZero() {
        var history = TrafficHistoryBuffer()
        history.record(upload: 10, download: 20, at: start)
        history.pause()
        history.pause()
        XCTAssertEqual(history.points.count, 1)
        XCTAssertEqual(history.currentDownload, 0)
        history.record(upload: 0, download: 0, at: start.addingTimeInterval(1))
        XCTAssertEqual(history.points.count, 2)
        XCTAssertNotEqual(history.points[0].segment, history.points[1].segment)
        XCTAssertEqual(history.points[1].download, 0)
        history.record(upload: 30, download: 40, at: start.addingTimeInterval(2))
        XCTAssertEqual(history.points[1].segment, history.points[2].segment)
        history.record(upload: 50, download: 60, at: start.addingTimeInterval(10))
        XCTAssertNotEqual(history.points[2].segment, history.points[3].segment)
    }

    func testHistoryRetainsFullWindowAndOnePrecedingMeasurement() {
        var history = TrafficHistoryBuffer()
        for second in 0...120 {
            history.record(upload: Int64(second), download: Int64(second * 2), at: start.addingTimeInterval(Double(second)))
        }
        XCTAssertEqual(history.points.count, 62)
        XCTAssertEqual(history.points.first?.time, start.addingTimeInterval(59))
        XCTAssertEqual(history.points.last?.time, start.addingTimeInterval(120))
        history.record(upload: 1, download: 2, at: start.addingTimeInterval(600))
        XCTAssertEqual(history.points.count, 2)
        XCTAssertNotEqual(history.points[0].segment, history.points[1].segment)
    }

    func testOutOfOrderOrDuplicateMeasurementsCannotRewriteCurrentRate() {
        var history = TrafficHistoryBuffer()
        XCTAssertTrue(history.record(upload: 10, download: 20, at: start))
        XCTAssertFalse(history.record(upload: 99, download: 99, at: start))
        XCTAssertFalse(history.record(upload: 99, download: 99, at: start.addingTimeInterval(-1)))
        XCTAssertEqual(history.points.count, 1)
        XCTAssertEqual(history.currentDownload, 20)
    }

    func testUnexpectedHighFrequencyInputRemainsBounded() {
        var history = TrafficHistoryBuffer()
        for tick in 0..<1_000 {
            history.record(upload: 1, download: 2, at: start.addingTimeInterval(Double(tick) / 100))
        }
        XCTAssertEqual(history.points.count, 128)
        XCTAssertEqual(history.points.last?.time, start.addingTimeInterval(9.99))
    }
}
