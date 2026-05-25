import Foundation
import SwiftData

@MainActor
struct AppSettingsStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchSettings() throws -> [AppSettings] {
        try context.fetch(FetchDescriptor<AppSettings>(
            sortBy: [SortDescriptor(\.createdAt)]
        ))
    }

    @discardableResult
    func fetchOrCreateSettings() throws -> AppSettings {
        if let existing = try fetchSettings().first {
            return existing
        }

        let settings = AppSettings()
        context.insert(settings)
        try context.save()
        return settings
    }
}
