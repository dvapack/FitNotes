import Foundation
import SwiftData

@Model
final class BodyMeasurementEntry {
    var recordedAt: Date
    var value: Double
    var noteRaw: String?

    var metric: BodyMeasurementMetric?

    var note: String {
        get { noteRaw ?? "" }
        set { noteRaw = newValue }
    }

    init(
        recordedAt: Date = .now,
        value: Double,
        note: String = "",
        metric: BodyMeasurementMetric? = nil
    ) {
        self.recordedAt = recordedAt
        self.value = value
        self.noteRaw = note
        self.metric = metric
    }
}
