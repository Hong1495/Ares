import SwiftUI

/// Native menu entries, shared with the isolated preview through injected actions.
struct WorkspaceCommands: Commands {
    let showSettings: () -> Void
    let showMainWindow: () -> Void

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…", action: showSettings)
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .windowArrangement) {
            Button("Show Main Window", action: showMainWindow)
                .keyboardShortcut("0", modifiers: .command)
        }
    }
}
