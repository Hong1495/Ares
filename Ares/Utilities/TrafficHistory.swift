import Foundation
import Combine

nonisolated struct TrafficDataPoint: Identifiable, Equatable, Sendable {
    var id: Date { time }
    let time: Date
    let upload: Int64
    let download: Int64
    let segment: UInt64
}

/// A bounded window of measured rates. Monitoring gaps never become zero samples.
nonisolated struct TrafficHistoryBuffer: Equatable, Sendable {
    private(set) var points: [TrafficDataPoint] = []
    private(set) var currentUpload: Int64 = 0
    private(set) var currentDownload: Int64 = 0
    private var segment: UInt64 = 0
    private var startsNewSegment = false

    @discardableResult
    mutating func record(upload: Int64, download: Int64, at time: Date) -> Bool {
        if let last = points.last {
            guard time > last.time else { return false }
            if startsNewSegment || time.timeIntervalSince(last.time) > 2.5 { segment &+= 1 }
        }
        startsNewSegment = false
        currentUpload = max(0, upload)
        currentDownload = max(0, download)
        points.append(.init(time: time, upload: currentUpload, download: currentDownload, segment: segment))
        let cutoff = time.addingTimeInterval(-60)
        // Keep one preceding measurement for interpolation at the left edge.
        if let first = points.firstIndex(where: { $0.time >= cutoff }), first > 1 {
            points.removeFirst(first - 1)
        }
        if points.count > 128 { points.removeFirst(points.count - 128) }
        return true
    }

    mutating func pause() {
        startsNewSegment = true
        currentUpload = 0
        currentDownload = 0
    }
}

/// Owned by the traffic controller, so navigation only changes the observing view.
@MainActor final class TrafficHistory: ObservableObject {
    @Published private(set) var snapshot = TrafficHistoryBuffer()

    func record(upload: Int64, download: Int64, at time: Date) {
        var next = snapshot
        if next.record(upload: upload, download: download, at: time) { snapshot = next }
    }

    func pause() {
        var next = snapshot
        next.pause()
        if next != snapshot { snapshot = next }
    }
}
