import Foundation
import HealthKit
import Supabase

struct SourceKey: Hashable, Codable {
    let bundleId: String
    let name: String
    let productType: String
    let deviceModel: String

    init(sample: HKSample) {
        bundleId = sample.sourceRevision.source.bundleIdentifier
        name = sample.sourceRevision.source.name
        productType = sample.sourceRevision.productType ?? ""
        deviceModel = sample.device?.model ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case bundleId = "bundle_id"
        case name
        case productType = "product_type"
        case deviceModel = "device_model"
    }
}

struct SourceRecord: Decodable {
    let id: Int
    let bundleId: String
    let name: String
    let productType: String
    let deviceModel: String

    var key: SourceKey {
        SourceKey(bundleId: bundleId, name: name, productType: productType, deviceModel: deviceModel)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case bundleId = "bundle_id"
        case name
        case productType = "product_type"
        case deviceModel = "device_model"
    }
}

extension SourceKey {
    init(bundleId: String, name: String, productType: String, deviceModel: String) {
        self.bundleId = bundleId
        self.name = name
        self.productType = productType
        self.deviceModel = deviceModel
    }
}

struct QuantitySampleRow: Encodable {
    let uuid: UUID
    let type: String
    let value: Double
    let startAt: Date
    let endAt: Date
    let sourceId: Int?
    let metadata: AnyJSON?

    enum CodingKeys: String, CodingKey {
        case uuid, type, value, metadata
        case startAt = "start_at"
        case endAt = "end_at"
        case sourceId = "source_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(type, forKey: .type)
        try container.encode(value, forKey: .value)
        try container.encode(startAt, forKey: .startAt)
        try container.encode(endAt, forKey: .endAt)
        try container.encode(sourceId, forKey: .sourceId)
        try container.encode(metadata, forKey: .metadata)
    }
}

struct CategorySampleRow: Encodable {
    let uuid: UUID
    let type: String
    let value: String
    let startAt: Date
    let endAt: Date
    let sourceId: Int?
    let metadata: AnyJSON?

    enum CodingKeys: String, CodingKey {
        case uuid, type, value, metadata
        case startAt = "start_at"
        case endAt = "end_at"
        case sourceId = "source_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(type, forKey: .type)
        try container.encode(value, forKey: .value)
        try container.encode(startAt, forKey: .startAt)
        try container.encode(endAt, forKey: .endAt)
        try container.encode(sourceId, forKey: .sourceId)
        try container.encode(metadata, forKey: .metadata)
    }
}

struct SyncLogRow: Encodable {
    let mode: String
    let type: String?
    let inserted: Int
    let deleted: Int
    let error: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(type, forKey: .type)
        try container.encode(inserted, forKey: .inserted)
        try container.encode(deleted, forKey: .deleted)
        try container.encode(error, forKey: .error)
    }

    enum CodingKeys: String, CodingKey {
        case mode, type, inserted, deleted, error
    }
}

enum SampleMetadata {
    private static let keptKeys = [
        HKMetadataKeyWasUserEntered,
        HKMetadataKeyHeartRateMotionContext,
        HKMetadataKeyTimeZone,
    ]

    static func kept(from metadata: [String: Any]?) -> AnyJSON? {
        guard let metadata else { return nil }
        var object: JSONObject = [:]
        for key in keptKeys {
            if let value = metadata[key].flatMap(json) {
                object[key] = value
            }
        }
        return object.isEmpty ? nil : .object(object)
    }

    static func all(from metadata: [String: Any]?) -> AnyJSON? {
        guard let metadata else { return nil }
        let object = metadata.compactMapValues(json)
        return object.isEmpty ? nil : .object(object)
    }

    static func json(_ value: Any) -> AnyJSON? {
        switch value {
        case let string as String:
            return .string(string)
        case let date as Date:
            return .string(date.ISO8601Format())
        case let quantity as HKQuantity:
            return .string(quantity.description)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .double(number.doubleValue)
        default:
            return nil
        }
    }
}

struct DailyStatRow: Encodable {
    let day: String
    let type: String
    let sum: Double?
    let avg: Double?
    let min: Double?
    let max: Double?

    enum CodingKeys: String, CodingKey {
        case day, type, sum, avg, min, max
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(day, forKey: .day)
        try container.encode(type, forKey: .type)
        try container.encode(sum, forKey: .sum)
        try container.encode(avg, forKey: .avg)
        try container.encode(min, forKey: .min)
        try container.encode(max, forKey: .max)
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct WorkoutRow: Encodable {
    let uuid: UUID
    let activityType: String
    let startAt: Date
    let endAt: Date
    let durationS: Double
    let totalEnergyKcal: Double?
    let totalDistanceM: Double?
    let sourceId: Int?
    let statistics: AnyJSON?
    let activities: AnyJSON?
    let events: AnyJSON?
    let metadata: AnyJSON?

    enum CodingKeys: String, CodingKey {
        case uuid, statistics, activities, events, metadata
        case activityType = "activity_type"
        case startAt = "start_at"
        case endAt = "end_at"
        case durationS = "duration_s"
        case totalEnergyKcal = "total_energy_kcal"
        case totalDistanceM = "total_distance_m"
        case sourceId = "source_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(activityType, forKey: .activityType)
        try container.encode(startAt, forKey: .startAt)
        try container.encode(endAt, forKey: .endAt)
        try container.encode(durationS, forKey: .durationS)
        try container.encode(totalEnergyKcal, forKey: .totalEnergyKcal)
        try container.encode(totalDistanceM, forKey: .totalDistanceM)
        try container.encode(sourceId, forKey: .sourceId)
        try container.encode(statistics, forKey: .statistics)
        try container.encode(activities, forKey: .activities)
        try container.encode(events, forKey: .events)
        try container.encode(metadata, forKey: .metadata)
    }
}

struct WorkoutRouteRow: Encodable {
    let uuid: UUID
    let workoutUuid: UUID
    let startAt: Date
    let endAt: Date
    let sourceId: Int?
    let pointTimes: [Double]
    let latitudes: [Double]
    let longitudes: [Double]
    let altitudes: [Double]

    enum CodingKeys: String, CodingKey {
        case uuid, latitudes, longitudes, altitudes
        case workoutUuid = "workout_uuid"
        case startAt = "start_at"
        case endAt = "end_at"
        case sourceId = "source_id"
        case pointTimes = "point_times"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(workoutUuid, forKey: .workoutUuid)
        try container.encode(startAt, forKey: .startAt)
        try container.encode(endAt, forKey: .endAt)
        try container.encode(sourceId, forKey: .sourceId)
        try container.encode(pointTimes, forKey: .pointTimes)
        try container.encode(latitudes, forKey: .latitudes)
        try container.encode(longitudes, forKey: .longitudes)
        try container.encode(altitudes, forKey: .altitudes)
    }
}

struct ActivitySummaryRow: Encodable {
    let day: String
    let activeEnergyKcal: Double?
    let activeEnergyGoalKcal: Double?
    let moveTimeMin: Double?
    let moveTimeGoalMin: Double?
    let exerciseTimeMin: Double?
    let exerciseTimeGoalMin: Double?
    let standHours: Double?
    let standHoursGoal: Double?

    enum CodingKeys: String, CodingKey {
        case day
        case activeEnergyKcal = "active_energy_kcal"
        case activeEnergyGoalKcal = "active_energy_goal_kcal"
        case moveTimeMin = "move_time_min"
        case moveTimeGoalMin = "move_time_goal_min"
        case exerciseTimeMin = "exercise_time_min"
        case exerciseTimeGoalMin = "exercise_time_goal_min"
        case standHours = "stand_hours"
        case standHoursGoal = "stand_hours_goal"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(day, forKey: .day)
        try container.encode(activeEnergyKcal, forKey: .activeEnergyKcal)
        try container.encode(activeEnergyGoalKcal, forKey: .activeEnergyGoalKcal)
        try container.encode(moveTimeMin, forKey: .moveTimeMin)
        try container.encode(moveTimeGoalMin, forKey: .moveTimeGoalMin)
        try container.encode(exerciseTimeMin, forKey: .exerciseTimeMin)
        try container.encode(exerciseTimeGoalMin, forKey: .exerciseTimeGoalMin)
        try container.encode(standHours, forKey: .standHours)
        try container.encode(standHoursGoal, forKey: .standHoursGoal)
    }
}

struct CharacteristicsRow: Encodable {
    let biologicalSex: String?
    let bloodType: String?
    let dateOfBirth: String?
    let fitzpatrickSkinType: String?
    let wheelchairUse: String?
    let activityMoveMode: String?

    enum CodingKeys: String, CodingKey {
        case biologicalSex = "biological_sex"
        case bloodType = "blood_type"
        case dateOfBirth = "date_of_birth"
        case fitzpatrickSkinType = "fitzpatrick_skin_type"
        case wheelchairUse = "wheelchair_use"
        case activityMoveMode = "activity_move_mode"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(biologicalSex, forKey: .biologicalSex)
        try container.encode(bloodType, forKey: .bloodType)
        try container.encode(dateOfBirth, forKey: .dateOfBirth)
        try container.encode(fitzpatrickSkinType, forKey: .fitzpatrickSkinType)
        try container.encode(wheelchairUse, forKey: .wheelchairUse)
        try container.encode(activityMoveMode, forKey: .activityMoveMode)
    }
}

struct OtherSampleRow: Encodable {
    let uuid: UUID
    let type: String
    let startAt: Date
    let endAt: Date
    let sourceId: Int?
    let payload: AnyJSON
    let metadata: AnyJSON?

    enum CodingKeys: String, CodingKey {
        case uuid, type, payload, metadata
        case startAt = "start_at"
        case endAt = "end_at"
        case sourceId = "source_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(type, forKey: .type)
        try container.encode(startAt, forKey: .startAt)
        try container.encode(endAt, forKey: .endAt)
        try container.encode(sourceId, forKey: .sourceId)
        try container.encode(payload, forKey: .payload)
        try container.encode(metadata, forKey: .metadata)
    }
}

enum JSONValue {
    static func number(_ quantity: HKQuantity?, _ unit: HKUnit) -> AnyJSON {
        guard let quantity, quantity.is(compatibleWith: unit) else { return .null }
        return number(quantity.doubleValue(for: unit))
    }

    static func number(_ value: Double?) -> AnyJSON {
        guard let value, value.isFinite else { return .null }
        return .double(value)
    }

    static func date(_ date: Date?) -> AnyJSON {
        guard let date else { return .null }
        return .string(date.ISO8601Format())
    }

    static func statistics(_ statistics: [HKQuantityType: HKStatistics]) -> AnyJSON? {
        var object: JSONObject = [:]
        for (type, stats) in statistics {
            guard let spec = HealthCatalog.quantitySpec(for: type) else { continue }
            object[spec.name] = .object([
                "sum": number(stats.sumQuantity(), spec.unit),
                "avg": number(stats.averageQuantity(), spec.unit),
                "min": number(stats.minimumQuantity(), spec.unit),
                "max": number(stats.maximumQuantity(), spec.unit),
            ])
        }
        return object.isEmpty ? nil : .object(object)
    }
}
