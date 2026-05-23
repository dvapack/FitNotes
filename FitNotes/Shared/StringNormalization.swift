import Foundation

extension String {
    var normalizedCatalogName: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    var normalizedExerciseName: String {
        normalizedCatalogName
    }
}
