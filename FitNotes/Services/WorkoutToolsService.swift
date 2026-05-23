import Foundation

struct EstimatedOneRepMax {
    let epley: Double
    let brzycki: Double
    let lombardi: Double

    var recommended: Double {
        [epley, brzycki, lombardi].reduce(0, +) / 3
    }
}

struct WeightPlateBreakdown: Identifiable {
    let plate: Double
    let count: Int

    var id: Double { plate }
}

struct WorkoutToolsService {
    let availablePlates: [Double]

    init(availablePlates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]) {
        self.availablePlates = availablePlates.sorted(by: >)
    }

    func estimateOneRepMax(weight: Double, reps: Int) -> EstimatedOneRepMax? {
        guard weight > 0, reps > 0 else { return nil }

        let repsValue = Double(reps)
        let epley = weight * (1 + repsValue / 30)
        let brzycki = weight * (36 / max(37 - repsValue, 1))
        let lombardi = weight * pow(repsValue, 0.10)
        return EstimatedOneRepMax(epley: epley, brzycki: brzycki, lombardi: lombardi)
    }

    func projectedWorkingWeight(oneRepMax: Double, intensity: Double) -> Double? {
        guard oneRepMax > 0, intensity > 0, intensity <= 1 else { return nil }
        return oneRepMax * intensity
    }

    func volume(weight: Double, reps: Int, sets: Int) -> Double? {
        guard weight > 0, reps > 0, sets > 0 else { return nil }
        return weight * Double(reps * sets)
    }

    func plateBreakdown(totalWeight: Double, barbellWeight: Double = 20) -> [WeightPlateBreakdown] {
        guard totalWeight > barbellWeight else { return [] }

        var perSide = (totalWeight - barbellWeight) / 2
        var breakdown: [WeightPlateBreakdown] = []

        for plate in availablePlates {
            guard perSide >= plate else { continue }
            let count = Int(perSide / plate)
            if count > 0 {
                breakdown.append(WeightPlateBreakdown(plate: plate, count: count))
                perSide -= Double(count) * plate
            }
        }

        return breakdown
    }
}
