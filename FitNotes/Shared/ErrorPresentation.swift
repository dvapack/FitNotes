import Foundation

extension Error {
    func userFacingMessage(fallback: String) -> String {
        if let localizedError = self as? LocalizedError,
           let description = localizedError.errorDescription,
           description.isEmpty == false {
            return description
        }

        return fallback
    }
}
