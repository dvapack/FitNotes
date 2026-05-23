import Foundation
import SwiftData

enum ExerciseType: String, Codable, CaseIterable, Identifiable {
    case weightReps
    case distanceTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weightReps:
            return "Weight + Reps"
        case .distanceTime:
            return "Distance + Time"
        }
    }
}

enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case kg
    case lb

    var id: String { rawValue }

    var title: String {
        rawValue.uppercased()
    }
}

enum ExerciseProgressionView: String, Codable, CaseIterable, Identifiable {
    case maxWeight
    case totalVolume
    case totalReps

    var id: String { rawValue }
}

@Model
final class Exercise {
    var name: String
    var normalizedName: String
    var isCustom: Bool
    var createdAt: Date
    var notesRaw: String?
    var isFavorite: Bool
    var exerciseTypeRaw: String?
    var preferredWeightUnitRaw: String?
    var defaultRestSeconds: Int
    var defaultProgressionViewRaw: String?

    var muscleGroup: MuscleGroup?

    @Relationship(deleteRule: .nullify, inverse: \WorkoutSet.exercise)
    var workoutSets: [WorkoutSet]

    var notes: String {
        get { notesRaw ?? "" }
        set { notesRaw = newValue }
    }

    var exerciseType: ExerciseType {
        get { ExerciseType(rawValue: exerciseTypeRaw ?? "") ?? .weightReps }
        set { exerciseTypeRaw = newValue.rawValue }
    }

    var preferredWeightUnit: WeightUnit {
        get { WeightUnit(rawValue: preferredWeightUnitRaw ?? "") ?? .kg }
        set { preferredWeightUnitRaw = newValue.rawValue }
    }

    var defaultProgressionView: ExerciseProgressionView {
        get { ExerciseProgressionView(rawValue: defaultProgressionViewRaw ?? "") ?? .maxWeight }
        set { defaultProgressionViewRaw = newValue.rawValue }
    }

    init(
        name: String,
        normalizedName: String,
        isCustom: Bool,
        createdAt: Date = .now,
        notes: String = "",
        isFavorite: Bool = false,
        exerciseType: ExerciseType = .weightReps,
        preferredWeightUnit: WeightUnit = .kg,
        defaultRestSeconds: Int = 90,
        defaultProgressionView: ExerciseProgressionView = .maxWeight,
        muscleGroup: MuscleGroup? = nil
    ) {
        self.name = name
        self.normalizedName = normalizedName
        self.isCustom = isCustom
        self.createdAt = createdAt
        self.notesRaw = notes
        self.isFavorite = isFavorite
        self.exerciseTypeRaw = exerciseType.rawValue
        self.preferredWeightUnitRaw = preferredWeightUnit.rawValue
        self.defaultRestSeconds = defaultRestSeconds
        self.defaultProgressionViewRaw = defaultProgressionView.rawValue
        self.muscleGroup = muscleGroup
        self.workoutSets = []
    }
}
