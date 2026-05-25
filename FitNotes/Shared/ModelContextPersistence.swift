import SwiftData

enum ModelContextPersistence {
    static func perform(
        in context: ModelContext,
        update: () -> Void,
        revert: () -> Void = {},
        save: () throws -> Void
    ) throws {
        update()

        do {
            try save()
        } catch {
            context.rollback()
            revert()
            throw error
        }
    }
}
