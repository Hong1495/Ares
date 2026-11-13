import Foundation

public enum NetworkQuality {
    public struct Sample: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let date: Date
        public let milliseconds: Int?
        public let outcome: String
        public init(date: Date = Date(), milliseconds: Int?, outcome: String) {
            self.date = date; self.milliseconds = milliseconds.flatMap { $0 >= 0 ? $0 : nil }; self.outcome = outcome
        }
    }
    public struct Summary: Equatable, Sendable {
        public let attempts: Int
        public let successes: Int
        public let median: Int?
        public let p95: Int?
        /// Mean absolute difference between consecutive successful samples; failures break adjacency.
        public let variation: Int?
        public var successPercent: Double? { attempts == 0 ? nil : 100 * Double(successes) / Double(attempts) }
        public init(_ samples: [Sample]) {
            attempts = samples.count
            let values = samples.compactMap(\.milliseconds).sorted(); successes = values.count
            median = values.isEmpty ? nil : values[(values.count - 1) / 2]
            p95 = values.isEmpty ? nil : values[min(values.count - 1, Int(ceil(Double(values.count) * 0.95)) - 1)]
            let differences = zip(samples, samples.dropFirst()).compactMap { a, b -> Int? in
                guard let x = a.milliseconds, let y = b.milliseconds else { return nil }; return abs(y - x)
            }
            variation = differences.isEmpty ? nil : differences.reduce(0, +) / differences.count
        }
    }
    public struct Route: Equatable, Sendable {
        public let path: [String]
        public let pinned: Bool
        public let kind: String
        public init(path: [String], pinned: Bool, kind: String) { self.path = path; self.pinned = pinned; self.kind = kind }
    }
    public struct Event: Identifiable, Sendable {
        public let id = UUID()
        public let date: Date
        public let before: Route
        public let after: Route
        public let reason: String
    }
    public struct Window: Sendable {
        public private(set) var samples: [String: [Sample]] = [:]
        public private(set) var unavailable: [String: Int] = [:]
        public private(set) var events: [Event] = []
        public private(set) var route: Route?
        public init() {}
        public mutating func record(_ sample: Sample, target: String) {
            samples[target, default: []].append(sample)
            samples[target] = Array(samples[target, default: []].suffix(120))
        }
        public mutating func recordUnavailable(target: String) { unavailable[target, default: 0] += 1 }
        public mutating func observe(_ next: Route, date: Date = Date()) {
            defer { route = next }
            guard let previous = route, previous != next else { return }
            let reason: String
            if next.pinned { reason = "Manual selection observed" }
            else if previous.pinned { reason = "Automatic selection resumed" }
            else if next.kind == "Fallback" || next.kind == "URLTest" { reason = "Core automatic selection changed · trigger not exposed by API" }
            else { reason = "Route changed · trigger not exposed by API" }
            events.insert(Event(date: date, before: previous, after: next, reason: reason), at: 0)
            events = Array(events.prefix(100))
        }
    }
}
