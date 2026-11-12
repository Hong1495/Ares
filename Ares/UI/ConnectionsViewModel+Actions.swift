import Foundation
import AppKit

extension ConnectionsViewModel {
    func killProcess(for session: AppSession) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleURL?.path == session.id || $0.executableURL?.path == session.id
        }), app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            actionError = "This process cannot be safely identified as a running application."
            return
        }
        if !app.forceTerminate() { actionError = "The application could not be terminated." }
    }

    func exportData(to url: URL, connections: [Connection]) async {
        do { try ActivityPresentation.csv(connections).write(to: url, atomically: true, encoding: .utf8) }
        catch { actionError = "Could not save the activity export. Check the destination and try again." }
    }
}
