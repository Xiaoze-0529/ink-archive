import SwiftUI

@main
struct InkArchiveApp: App {
    @StateObject private var model = ArchiveAppModel()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(model)
                .tint(ArchiveTheme.forest)
                .task { await model.load() }
        }
    }
}
