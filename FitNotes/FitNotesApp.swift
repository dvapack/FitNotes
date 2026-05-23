import SwiftUI
import SwiftData

@main
struct FitNotesApp: App {
    private let sharedModelContainer = ModelContainerFactory.makeSharedContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    let seeder = SeedDataService(context: sharedModelContainer.mainContext)
                    try? seeder.seedIfNeeded()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
