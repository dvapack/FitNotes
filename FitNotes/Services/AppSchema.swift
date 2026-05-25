import Foundation
import SwiftData

enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version = .init(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            MuscleGroup.self,
            Exercise.self,
            Workout.self,
            WorkoutSet.self,
        ]
    }
}

enum AppSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version = .init(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            AppSettings.self,
            MuscleGroup.self,
            Exercise.self,
            Workout.self,
            WorkoutSet.self,
        ]
    }
}

enum AppSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version = .init(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            AppSettings.self,
            BodyMeasurementMetric.self,
            BodyMeasurementEntry.self,
            MuscleGroup.self,
            Exercise.self,
            Workout.self,
            WorkoutSet.self,
        ]
    }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AppSchemaV1.self, AppSchemaV2.self, AppSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: AppSchemaV1.self, toVersion: AppSchemaV2.self),
            .lightweight(fromVersion: AppSchemaV2.self, toVersion: AppSchemaV3.self),
        ]
    }
}
