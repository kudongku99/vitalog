import Foundation
import HealthKit

enum QuantityRetention {
    case all
    case months(Int)
    case none

    private static let threeMonths: Set<String> = [
        "active_energy_burned", "basal_energy_burned", "distance_walking_running", "step_count",
        "physical_effort", "walking_speed", "walking_step_length", "walking_double_support_percentage",
        "walking_asymmetry_percentage", "headphone_audio_exposure", "environmental_audio_exposure",
        "respiratory_rate", "stair_ascent_speed", "stair_descent_speed", "environmental_sound_reduction",
        "flights_climbed", "distance_cycling",
    ]

    static func of(_ name: String) -> QuantityRetention {
        switch name {
        case "apple_exercise_time", "apple_stand_time": .none
        case "heart_rate": .months(6)
        case _ where threeMonths.contains(name): .months(3)
        default: .all
        }
    }

    func limit(from reference: Date) -> Date? {
        guard case .months(let count) = self else { return nil }
        return Calendar.current.date(byAdding: .month, value: -count, to: reference)
    }
}

struct QuantitySpec {
    let type: HKQuantityType
    let name: String
    let unit: HKUnit

    var isCumulative: Bool { type.aggregationStyle == .cumulative }
    var retention: QuantityRetention { .of(name) }
}

struct CategorySpec {
    let type: HKCategoryType
    let name: String
    let valueNames: [Int: String]

    func valueName(_ value: Int) -> String {
        valueNames[value] ?? String(value)
    }
}

enum HealthCatalog {
    static let quantities: [QuantitySpec] = quantityEntries.compactMap { identifier, unit in
        let id = HKQuantityTypeIdentifier(rawValue: "HKQuantityTypeIdentifier" + identifier)
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        return QuantitySpec(type: type, name: snakeCase(identifier), unit: HKUnit(from: unit))
    }

    static let categories: [CategorySpec] = categoryEntries.compactMap { identifier, values in
        let id = HKCategoryTypeIdentifier(rawValue: "HKCategoryTypeIdentifier" + identifier)
        guard let type = HKObjectType.categoryType(forIdentifier: id) else { return nil }
        return CategorySpec(type: type, name: snakeCase(identifier), valueNames: values)
    }

    private static let quantitiesByType = Dictionary(
        quantities.map { ($0.type, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    static func quantitySpec(for type: HKQuantityType) -> QuantitySpec? {
        quantitiesByType[type]
    }

    static let characteristics: [HKCharacteristicType] = [
        HKCharacteristicType(.biologicalSex),
        HKCharacteristicType(.bloodType),
        HKCharacteristicType(.dateOfBirth),
        HKCharacteristicType(.fitzpatrickSkinType),
        HKCharacteristicType(.wheelchairUse),
        HKCharacteristicType(.activityMoveMode),
    ]

    static var otherTypes: [HKObjectType] {
        var types: [HKObjectType] = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKSeriesType.heartbeat(),
            HKObjectType.activitySummaryType(),
            HKObjectType.audiogramSampleType(),
            HKObjectType.electrocardiogramType(),
        ]
        if #available(iOS 18.0, *) {
            types.append(HKObjectType.stateOfMindType())
            types.append(HKScoredAssessmentType(.GAD7))
            types.append(HKScoredAssessmentType(.PHQ9))
        }
        return types
    }

    static var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        quantities.forEach { types.insert($0.type) }
        categories.forEach { types.insert($0.type) }
        characteristics.forEach { types.insert($0) }
        otherTypes.forEach { types.insert($0) }
        return types
    }

    static func snakeCase(_ camel: String) -> String {
        let chars = Array(camel)
        var result = ""
        for (index, char) in chars.enumerated() {
            if char.isUppercase, index > 0 {
                let previous = chars[index - 1]
                let nextIsLower = index + 1 < chars.count && chars[index + 1].isLowercase
                if previous.isLowercase || previous.isNumber || (previous.isUppercase && nextIsLower) {
                    result.append("_")
                }
            }
            result.append(contentsOf: char.lowercased())
        }
        return result
    }

    private static let quantityEntries: [(String, String)] = [
        ("AppleSleepingWristTemperature", "degC"),
        ("BodyFatPercentage", "%"),
        ("BodyMass", "kg"),
        ("BodyMassIndex", "count"),
        ("ElectrodermalActivity", "S"),
        ("Height", "m"),
        ("LeanBodyMass", "kg"),
        ("WaistCircumference", "m"),
        ("ActiveEnergyBurned", "kcal"),
        ("AppleExerciseTime", "min"),
        ("AppleMoveTime", "min"),
        ("AppleStandTime", "min"),
        ("BasalEnergyBurned", "kcal"),
        ("CrossCountrySkiingSpeed", "m/s"),
        ("CyclingCadence", "count/min"),
        ("CyclingFunctionalThresholdPower", "W"),
        ("CyclingPower", "W"),
        ("CyclingSpeed", "m/s"),
        ("DistanceCrossCountrySkiing", "m"),
        ("DistanceCycling", "m"),
        ("DistanceDownhillSnowSports", "m"),
        ("DistancePaddleSports", "m"),
        ("DistanceRowing", "m"),
        ("DistanceSkatingSports", "m"),
        ("DistanceSwimming", "m"),
        ("DistanceWalkingRunning", "m"),
        ("DistanceWheelchair", "m"),
        ("EstimatedWorkoutEffortScore", "appleEffortScore"),
        ("FlightsClimbed", "count"),
        ("NikeFuel", "count"),
        ("PaddleSportsSpeed", "m/s"),
        ("PhysicalEffort", "kcal/hr·kg"),
        ("PushCount", "count"),
        ("RowingSpeed", "m/s"),
        ("RunningPower", "W"),
        ("RunningSpeed", "m/s"),
        ("StepCount", "count"),
        ("SwimmingStrokeCount", "count"),
        ("UnderwaterDepth", "m"),
        ("WorkoutEffortScore", "appleEffortScore"),
        ("EnvironmentalAudioExposure", "dBASPL"),
        ("EnvironmentalSoundReduction", "dBASPL"),
        ("HeadphoneAudioExposure", "dBASPL"),
        ("AtrialFibrillationBurden", "%"),
        ("HeartRate", "count/min"),
        ("HeartRateRecoveryOneMinute", "count/min"),
        ("HeartRateVariabilityRMSSD", "ms"),
        ("HeartRateVariabilitySDNN", "ms"),
        ("PeripheralPerfusionIndex", "%"),
        ("RestingHeartRate", "count/min"),
        ("VO2Max", "ml/kg·min"),
        ("WalkingHeartRateAverage", "count/min"),
        ("AppleWalkingSteadiness", "%"),
        ("RunningGroundContactTime", "ms"),
        ("RunningStrideLength", "m"),
        ("RunningVerticalOscillation", "cm"),
        ("SixMinuteWalkTestDistance", "m"),
        ("StairAscentSpeed", "m/s"),
        ("StairDescentSpeed", "m/s"),
        ("WalkingAsymmetryPercentage", "%"),
        ("WalkingDoubleSupportPercentage", "%"),
        ("WalkingSpeed", "m/s"),
        ("WalkingStepLength", "m"),
        ("DietaryBiotin", "g"),
        ("DietaryCaffeine", "g"),
        ("DietaryCalcium", "g"),
        ("DietaryCarbohydrates", "g"),
        ("DietaryChloride", "g"),
        ("DietaryCholesterol", "g"),
        ("DietaryChromium", "g"),
        ("DietaryCopper", "g"),
        ("DietaryEnergyConsumed", "kcal"),
        ("DietaryFatMonounsaturated", "g"),
        ("DietaryFatPolyunsaturated", "g"),
        ("DietaryFatSaturated", "g"),
        ("DietaryFatTotal", "g"),
        ("DietaryFiber", "g"),
        ("DietaryFolate", "g"),
        ("DietaryIodine", "g"),
        ("DietaryIron", "g"),
        ("DietaryMagnesium", "g"),
        ("DietaryManganese", "g"),
        ("DietaryMolybdenum", "g"),
        ("DietaryNiacin", "g"),
        ("DietaryPantothenicAcid", "g"),
        ("DietaryPhosphorus", "g"),
        ("DietaryPotassium", "g"),
        ("DietaryProtein", "g"),
        ("DietaryRiboflavin", "g"),
        ("DietarySelenium", "g"),
        ("DietarySodium", "g"),
        ("DietarySugar", "g"),
        ("DietaryThiamin", "g"),
        ("DietaryVitaminA", "g"),
        ("DietaryVitaminB12", "g"),
        ("DietaryVitaminB6", "g"),
        ("DietaryVitaminC", "g"),
        ("DietaryVitaminD", "g"),
        ("DietaryVitaminE", "g"),
        ("DietaryVitaminK", "g"),
        ("DietaryWater", "mL"),
        ("DietaryZinc", "g"),
        ("BloodAlcoholContent", "%"),
        ("BloodPressureDiastolic", "mmHg"),
        ("BloodPressureSystolic", "mmHg"),
        ("InsulinDelivery", "IU"),
        ("NumberOfAlcoholicBeverages", "count"),
        ("NumberOfTimesFallen", "count"),
        ("TimeInDaylight", "min"),
        ("UVExposure", "count"),
        ("WaterTemperature", "degC"),
        ("BasalBodyTemperature", "degC"),
        ("AppleSleepingBreathingDisturbances", "count"),
        ("ForcedExpiratoryVolume1", "L"),
        ("ForcedVitalCapacity", "L"),
        ("InhalerUsage", "count"),
        ("OxygenSaturation", "%"),
        ("PeakExpiratoryFlowRate", "L/min"),
        ("RespiratoryRate", "count/min"),
        ("BloodGlucose", "mg/dL"),
        ("BodyTemperature", "degC"),
    ]

    private static let notApplicable: [Int: String] = [0: "not_applicable"]
    private static let severity: [Int: String] = [
        0: "unspecified", 1: "not_present", 2: "mild", 3: "moderate", 4: "severe",
    ]
    private static let presence: [Int: String] = [0: "present", 1: "not_present"]
    private static let vaginalBleeding: [Int: String] = [
        1: "unspecified", 2: "light", 3: "medium", 4: "heavy", 5: "none",
    ]
    private static let testResult: [Int: String] = [
        1: "negative", 2: "positive", 3: "indeterminate",
    ]

    private static let categoryEntries: [(String, [Int: String])] = [
        ("SleepAnalysis", [
            0: "in_bed", 1: "asleep_unspecified", 2: "awake",
            3: "asleep_core", 4: "asleep_deep", 5: "asleep_rem",
        ]),
        ("AppleStandHour", [0: "stood", 1: "idle"]),
        ("EnvironmentalAudioExposureEvent", [1: "momentary_limit"]),
        ("HeadphoneAudioExposureEvent", [1: "seven_day_limit"]),
        ("HighHeartRateEvent", notApplicable),
        ("HypertensionEvent", notApplicable),
        ("IrregularHeartRhythmEvent", notApplicable),
        ("LowCardioFitnessEvent", [1: "low_fitness"]),
        ("LowHeartRateEvent", notApplicable),
        ("MindfulSession", notApplicable),
        ("AppleWalkingSteadinessEvent", [
            1: "initial_low", 2: "initial_very_low", 3: "repeat_low", 4: "repeat_very_low",
        ]),
        ("HandwashingEvent", notApplicable),
        ("ToothbrushingEvent", notApplicable),
        ("SleepApneaEvent", notApplicable),
        ("BleedingAfterMenopause", vaginalBleeding),
        ("BleedingAfterPregnancy", vaginalBleeding),
        ("BleedingDuringPregnancy", vaginalBleeding),
        ("CervicalMucusQuality", [
            1: "dry", 2: "sticky", 3: "creamy", 4: "watery", 5: "egg_white",
        ]),
        ("Contraceptive", [
            1: "unspecified", 2: "implant", 3: "injection", 4: "intrauterine_device",
            5: "intravaginal_ring", 6: "oral", 7: "patch",
        ]),
        ("InfrequentMenstrualCycles", notApplicable),
        ("IntermenstrualBleeding", notApplicable),
        ("IrregularMenstrualCycles", notApplicable),
        ("Lactation", notApplicable),
        ("MenopausalState", [1: "menopause", 2: "perimenopause", 3: "none"]),
        ("MenstrualFlow", vaginalBleeding),
        ("OvulationTestResult", [
            1: "negative", 2: "luteinizing_hormone_surge", 3: "indeterminate", 4: "estrogen_surge",
        ]),
        ("PersistentIntermenstrualBleeding", notApplicable),
        ("Pregnancy", notApplicable),
        ("PregnancyTestResult", testResult),
        ("ProgesteroneTestResult", testResult),
        ("ProlongedMenstrualPeriods", notApplicable),
        ("SexualActivity", notApplicable),
        ("AbdominalCramps", severity),
        ("Acne", severity),
        ("AppetiteChanges", [0: "unspecified", 1: "no_change", 2: "decreased", 3: "increased"]),
        ("BladderIncontinence", severity),
        ("Bloating", severity),
        ("BreastPain", severity),
        ("ChestTightnessOrPain", severity),
        ("Chills", severity),
        ("Constipation", severity),
        ("Coughing", severity),
        ("Diarrhea", severity),
        ("Dizziness", severity),
        ("DrySkin", severity),
        ("Fainting", severity),
        ("Fatigue", severity),
        ("Fever", severity),
        ("GeneralizedBodyAche", severity),
        ("HairLoss", severity),
        ("Headache", severity),
        ("Heartburn", severity),
        ("HotFlashes", severity),
        ("LossOfSmell", severity),
        ("LossOfTaste", severity),
        ("LowerBackPain", severity),
        ("MemoryLapse", severity),
        ("MoodChanges", presence),
        ("Nausea", severity),
        ("NightSweats", severity),
        ("PelvicPain", severity),
        ("RapidPoundingOrFlutteringHeartbeat", severity),
        ("RunnyNose", severity),
        ("ShortnessOfBreath", severity),
        ("SinusCongestion", severity),
        ("SkippedHeartbeat", severity),
        ("SleepChanges", presence),
        ("SoreThroat", severity),
        ("VaginalDryness", severity),
        ("Vomiting", severity),
        ("Wheezing", severity),
    ]
}
