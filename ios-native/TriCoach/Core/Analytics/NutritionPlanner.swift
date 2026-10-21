import Foundation

struct FuelingTarget: Hashable {
    var carbsPerHour: Double
    var fluidMlPerHour: Double
    var sodiumMgPerHour: Double
}

struct FuelingStep: Identifiable, Hashable {
    var id = UUID()
    let minute: Int
    let segment: Sport
    let item: FuelItem
}

/// Race-Day-Fueling nach gängigen Sporternährungs-Empfehlungen
/// (Richtwerte – individuell im Training testen!).
enum NutritionPlanner {
    static func target(duration: TimeInterval, temperatureC: Double, weightKg: Double) -> FuelingTarget {
        let hours = duration / 3600
        let carbs: Double
        switch hours {
        case ..<1.25: carbs = 30
        case ..<2.5: carbs = 60
        case ..<4: carbs = 75
        default: carbs = 90 // nur mit trainiertem Darm & Glukose:Fruktose-Mix
        }
        let fluid = min(1_000, max(400, 500 + (temperatureC - 15) * 20 + (weightKg - 70) * 3))
        let sodium = min(1_000, max(300, 400 + (temperatureC - 15) * 25))
        return FuelingTarget(carbsPerHour: carbs, fluidMlPerHour: fluid, sodiumMgPerHour: sodium)
    }

    /// Erstellt einen Zeitplan für Rad und Lauf (beim Schwimmen keine Zufuhr).
    static func plan(prediction: RaceSplitPrediction, temperatureC: Double, weightKg: Double) -> (FuelingTarget, [FuelingStep]) {
        let target = target(duration: prediction.total, temperatureC: temperatureC, weightKg: weightKg)
        var steps: [FuelingStep] = []
        let items = FuelItem.defaults
        let gel = items[0], caffeineGel = items[1], drink = items[2], bar = items[3]

        let bikeStart = Int((prediction.swim + prediction.t1) / 60)
        let bikeEnd = bikeStart + Int(prediction.bike / 60)
        let runStart = bikeEnd + Int(prediction.t2 / 60)
        let runEnd = runStart + Int(prediction.run / 60)

        // Rad: alle 20 min Kohlenhydrate, stündlich eine Iso-Flasche
        var minute = bikeStart + 15
        var counter = 0
        while minute < bikeEnd - 10 {
            let item: FuelItem
            if counter % 3 == 0 { item = drink }
            else if prediction.bike > 3 * 3600 && counter % 3 == 1 { item = bar }
            else { item = gel }
            steps.append(FuelingStep(minute: minute, segment: .bike, item: item))
            minute += 20
            counter += 1
        }
        // Laufen: Gel alle 25–30 min, letztes Drittel mit Koffein
        minute = runStart + 20
        while minute < runEnd - 10 {
            let late = Double(minute - runStart) > prediction.run / 60 * 0.6
            steps.append(FuelingStep(minute: minute, segment: .run, item: late ? caffeineGel : gel))
            minute += 28
        }
        return (target, steps)
    }

    static func totals(_ entries: [FuelLogEntry]) -> (carbs: Double, fluid: Double, sodium: Double, caffeine: Double) {
        var carbs = 0.0, fluid = 0.0, sodium = 0.0, caffeine = 0.0
        for e in entries {
            carbs += e.item.carbsG
            fluid += e.item.fluidMl
            sodium += e.item.sodiumMg
            caffeine += e.item.caffeineMg
        }
        return (carbs, fluid, sodium, caffeine)
    }
}
