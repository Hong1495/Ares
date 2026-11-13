import Foundation
import Combine

/// Session-only metadata. Retains only the local control endpoint identity, names and operation metadata; no provider URLs or transport error messages.
@MainActor final class ResourceActivity: ObservableObject {
    static let shared = ResourceActivity()
    enum Kind: String { case nodes = "Nodes", rules = "Rules" }
    enum Action: String { case update = "Update", health = "Health check" }
    enum Phase: String { case preparing = "Preparing", requesting = "Request sent", reading = "Reading back", confirmed = "Confirmed" }
    enum Outcome: String { case running = "In progress", confirmed = "Confirmed", failed = "Unconfirmed", cancelled = "Interrupted" }
    struct Entry: Identifiable {
        let id: UUID
        let generation: UUID
        let endpoint: String
        let name: String
        let kind: Kind
        let action: Action
        let startedAt: Date
        var phase: Phase = .preparing
        var outcome: Outcome = .running
        var finishedAt: Date?
        var failure: String?
        var detail: String {
            if outcome == .confirmed { return "Request completed and metadata read back. This is not proof of node connectivity." }
            if outcome == .running { return phase.rawValue }
            let prefix = phase == .preparing ? "No mutation request sent." : "The core may have completed the request. Read current metadata before retrying."
            return prefix + (failure.map { " " + $0 } ?? "")
        }
    }
    @Published private(set) var entries: [Entry] = []
    func begin(name: String, kind: Kind, action: Action, generation: UUID, endpoint: String) throws -> UUID {
        guard !entries.contains(where: { $0.generation == generation && $0.endpoint == endpoint && $0.kind == kind && $0.name == name && $0.outcome == .running }) else {
            throw URLError(.resourceUnavailable)
        }
        let id = UUID()
        entries.insert(Entry(id: id, generation: generation, endpoint: endpoint, name: name, kind: kind, action: action, startedAt: Date()), at: 0)
        // Keep in-flight entries even when history reaches its limit.
        var completed = 0
        entries = entries.filter { entry in
            if entry.outcome == .running { return true }
            completed += 1; return completed <= 100
        }
        return id
    }
    func advance(_ id: UUID, to phase: Phase) {
        guard let index = entries.firstIndex(where: { $0.id == id && $0.outcome == .running }) else { return }
        entries[index].phase = phase
    }
    func finish(_ id: UUID, error: Error? = nil) {
        guard let index = entries.firstIndex(where: { $0.id == id && $0.outcome == .running }) else { return }
        entries[index].finishedAt = Date()
        if let error {
            let value = error as NSError
            entries[index].outcome = error is CancellationError || (value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled) ? .cancelled : .failed
            // Error domains/messages may contain subscription URLs. Retain only a numeric code.
            entries[index].failure = "Error code: \(value.code)."
        } else {
            entries[index].phase = .confirmed; entries[index].outcome = .confirmed
        }
        var completed = 0
        entries = entries.filter { entry in
            if entry.outcome == .running { return true }
            completed += 1; return completed <= 100
        }
    }
    func current(generation: UUID, endpoint: String, kind: Kind? = nil, name: String? = nil) -> [Entry] {
        entries.filter { $0.generation == generation && $0.endpoint == endpoint && (kind == nil || $0.kind == kind) && (name == nil || $0.name == name) }
    }
}
