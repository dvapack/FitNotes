import Foundation
import SwiftData

enum FitNotesCSVImportError: LocalizedError {
    case unreadableFile
    case missingRequiredColumns([String])
    case noValidRows

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "The selected file could not be read as a CSV document."
        case .missingRequiredColumns(let columns):
            return "The CSV is missing required columns: \(columns.joined(separator: ", "))."
        case .noValidRows:
            return "The CSV did not contain any valid workout rows to import."
        }
    }
}

struct FitNotesImportPreview {
    let rows: [FitNotesImportRow]
    let workoutCount: Int
    let exerciseCount: Int
    let skippedRowCount: Int
}

struct FitNotesImportRow: Identifiable {
    let id = UUID()
    let date: Date
    let exerciseName: String
    let categoryName: String
    let weight: Double
    let reps: Int
}

struct FitNotesImportResult {
    let importedWorkoutCount: Int
    let importedSetCount: Int
    let skippedRowCount: Int
}

@MainActor
struct FitNotesCSVImporter {
    private let context: ModelContext
    private let exerciseStore: DefaultExerciseStore
    private let calendar = Calendar.current

    init(context: ModelContext) {
        self.context = context
        self.exerciseStore = DefaultExerciseStore(context: context)
    }

    func previewImport(from data: Data) throws -> FitNotesImportPreview {
        guard let csvString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw FitNotesCSVImportError.unreadableFile
        }

        let rows = CSVRowParser.parse(csvString)
        guard let headerRow = rows.first else {
            throw FitNotesCSVImportError.noValidRows
        }

        let headerIndex = Dictionary(uniqueKeysWithValues: headerRow.enumerated().map { index, header in
            (header.normalizedCatalogName, index)
        })

        let requiredHeaders = ["date", "exercise", "category", "weight", "weight unit", "reps"]
        let missingHeaders = requiredHeaders.filter { headerIndex[$0] == nil }
        guard missingHeaders.isEmpty else {
            throw FitNotesCSVImportError.missingRequiredColumns(missingHeaders.map(\.capitalized))
        }

        let dateParsers = FitNotesDateParser.makeParsers()
        var validRows: [FitNotesImportRow] = []
        var skippedRowCount = 0

        for row in rows.dropFirst() {
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                skippedRowCount += 1
                continue
            }

            guard
                let dateText = value(in: row, at: headerIndex["date"]),
                let exerciseName = value(in: row, at: headerIndex["exercise"]),
                let categoryName = value(in: row, at: headerIndex["category"]),
                let weightText = value(in: row, at: headerIndex["weight"]),
                let weightUnit = value(in: row, at: headerIndex["weight unit"]),
                let repsText = value(in: row, at: headerIndex["reps"])
            else {
                skippedRowCount += 1
                continue
            }

            guard
                let parsedDate = FitNotesDateParser.parse(dateText, using: dateParsers),
                !exerciseName.isEmpty,
                !categoryName.isEmpty,
                let weight = Double(weightText.replacingOccurrences(of: ",", with: ".")),
                weight > 0,
                let reps = Int(repsText),
                reps > 0
            else {
                skippedRowCount += 1
                continue
            }

            let normalizedUnit = weightUnit.normalizedCatalogName
            guard normalizedUnit == "kg" || normalizedUnit == "kgs" else {
                skippedRowCount += 1
                continue
            }

            validRows.append(
                FitNotesImportRow(
                    date: calendar.startOfDay(for: parsedDate),
                    exerciseName: exerciseName,
                    categoryName: categoryName,
                    weight: weight,
                    reps: reps
                )
            )
        }

        let sortedRows = validRows.sorted {
            if $0.date != $1.date {
                return $0.date < $1.date
            }

            if $0.categoryName.normalizedCatalogName != $1.categoryName.normalizedCatalogName {
                return $0.categoryName.localizedCaseInsensitiveCompare($1.categoryName) == .orderedAscending
            }

            return $0.exerciseName.localizedCaseInsensitiveCompare($1.exerciseName) == .orderedAscending
        }

        guard !sortedRows.isEmpty else {
            throw FitNotesCSVImportError.noValidRows
        }

        let workoutCount = Set(sortedRows.map(\.date)).count
        let exerciseKeys = Set(sortedRows.map { "\($0.categoryName.normalizedCatalogName)|\($0.exerciseName.normalizedCatalogName)" })

        return FitNotesImportPreview(
            rows: sortedRows,
            workoutCount: workoutCount,
            exerciseCount: exerciseKeys.count,
            skippedRowCount: skippedRowCount
        )
    }

    func importPreview(_ preview: FitNotesImportPreview) throws -> FitNotesImportResult {
        var workoutsByDate: [Date: Workout] = [:]
        var setOrderByDateAndExercise: [String: Int] = [:]

        for row in preview.rows {
            let workout = workoutsByDate[row.date] ?? makeImportedWorkout(for: row.date)
            workoutsByDate[row.date] = workout

            let muscleGroup = try exerciseStore.createMuscleGroup(name: row.categoryName)
            let exercise = try exerciseStore.createExercise(name: row.exerciseName, in: muscleGroup, isCustom: true)
            let setKey = "\(row.date.timeIntervalSinceReferenceDate)|\(exercise.persistentModelID)"
            let nextSetOrder = (setOrderByDateAndExercise[setKey] ?? 0) + 1
            let exerciseOrder = workoutsByDate[row.date]?.sets
                .filter { $0.exercise?.persistentModelID == exercise.persistentModelID }
                .first?.exerciseOrder ?? ((workoutsByDate[row.date]?.sets.map(\.exerciseOrder).max() ?? 0) + ((setOrderByDateAndExercise[setKey] == nil) ? 1 : 0))

            let workoutSet = WorkoutSet(
                exerciseOrder: exerciseOrder,
                setOrder: nextSetOrder,
                weight: row.weight,
                reps: row.reps,
                exerciseNameSnapshot: exercise.name,
                muscleGroupNameSnapshot: muscleGroup.name,
                workout: workout,
                exercise: exercise
            )
            context.insert(workoutSet)
            setOrderByDateAndExercise[setKey] = nextSetOrder
        }

        try context.save()

        return FitNotesImportResult(
            importedWorkoutCount: workoutsByDate.count,
            importedSetCount: preview.rows.count,
            skippedRowCount: preview.skippedRowCount
        )
    }

    private func makeImportedWorkout(for date: Date) -> Workout {
        let startedAt = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let workout = Workout(date: date, startedAt: startedAt, finishedAt: startedAt)
        context.insert(workout)
        return workout
    }

    private func value(in row: [String], at index: Int?) -> String? {
        guard let index, row.indices.contains(index) else {
            return nil
        }

        let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private enum FitNotesDateParser {
    static func makeParsers() -> [DateFormatter] {
        let formats = [
            "yyyy-MM-dd",
            "yyyy-MM-dd HH:mm:ss",
            "M/d/yyyy",
            "MM/dd/yyyy",
            "d/M/yyyy",
            "dd/MM/yyyy",
            "M/d/yyyy HH:mm",
            "MM/dd/yyyy HH:mm",
            "d/M/yyyy HH:mm",
            "dd/MM/yyyy HH:mm"
        ]

        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = format
            return formatter
        }
    }

    static func parse(_ value: String, using formatters: [DateFormatter]) -> Date? {
        for formatter in formatters {
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }
}

private enum CSVRowParser {
    static func parse(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentValue = ""
        var isInsideQuotes = false

        var index = csv.startIndex
        while index < csv.endIndex {
            let character = csv[index]

            if character == "\"" {
                let nextIndex = csv.index(after: index)
                if isInsideQuotes, nextIndex < csv.endIndex, csv[nextIndex] == "\"" {
                    currentValue.append("\"")
                    index = nextIndex
                } else {
                    isInsideQuotes.toggle()
                }
            } else if character == "," && !isInsideQuotes {
                currentRow.append(currentValue)
                currentValue = ""
            } else if (character == "\n" || character == "\r") && !isInsideQuotes {
                if character == "\r" {
                    let nextIndex = csv.index(after: index)
                    if nextIndex < csv.endIndex, csv[nextIndex] == "\n" {
                        index = nextIndex
                    }
                }

                currentRow.append(currentValue)
                rows.append(currentRow)
                currentRow = []
                currentValue = ""
            } else {
                currentValue.append(character)
            }

            index = csv.index(after: index)
        }

        if !currentValue.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentValue)
            rows.append(currentRow)
        }

        return rows
    }
}
