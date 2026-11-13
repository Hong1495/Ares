import Foundation
@main struct Harness {
    @MainActor static func main() throws {
        let activity = ResourceActivity()
        let generation = UUID(), endpoint = "https://fixture.invalid"
        let id = try activity.begin(name: "A", kind: .nodes, action: .update, generation: generation, endpoint: endpoint)
        do { _ = try activity.begin(name: "A", kind: .nodes, action: .health, generation: generation, endpoint: endpoint); fatalError("Duplicate operation accepted") }
        catch { precondition((error as NSError).code == NSURLErrorResourceUnavailable) }
        activity.advance(id, to: .reading)
        activity.finish(id, error: NSError(domain: "secret-url", code: 503, userInfo: [NSLocalizedDescriptionKey: "secret token"]))
        precondition(activity.entries.first?.phase == .reading)
        precondition(activity.entries.first?.outcome == .failed)
        precondition(activity.entries.first?.detail.contains("may have completed") == true)
        precondition(activity.entries.first?.detail.contains("secret") == false)
        let retry = try activity.begin(name: "A", kind: .nodes, action: .update, generation: generation, endpoint: endpoint)
        activity.finish(retry)
        precondition(activity.entries.first?.outcome == .confirmed)
        precondition(activity.current(generation: UUID(), endpoint: endpoint).isEmpty)
        precondition(activity.current(generation: generation, endpoint: "other").isEmpty)
        let interrupted = try activity.begin(name: "B", kind: .rules, action: .update, generation: generation, endpoint: endpoint)
        activity.finish(interrupted, error: CancellationError())
        precondition(activity.entries.first?.outcome == .cancelled)
        precondition(activity.entries.first?.detail.contains("No mutation") == true)
        let running = try activity.begin(name: "Keep", kind: .nodes, action: .health, generation: generation, endpoint: endpoint)
        for n in 0..<110 {
            let attempt = try activity.begin(name: String(n), kind: .rules, action: .update, generation: generation, endpoint: endpoint)
            activity.finish(attempt)
        }
        precondition(activity.entries.count == 101 && activity.entries.contains { $0.id == running })
        activity.finish(running)
        precondition(activity.entries.count == 100)
        print("PASS: resource operation phases, duplicate protection, uncertain outcomes, privacy, runtime isolation and bounded history")
    }
}
