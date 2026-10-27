import Foundation
import HealthKit
import Supabase

protocol BackfillTask {
    var id: String { get }
    var name: String { get }
    func earliestDate(reader: HealthReader, cutoff: Date) async throws -> Date?
    func run(in interval: DateInterval, reader: HealthReader, uploader: Uploader) async throws -> Int
}

protocol SampleSyncTask: BackfillTask {
    var sampleType: HKSampleType { get }
    var table: String { get }
    func upload(_ samples: [HKSample], reader: HealthReader, uploader: Uploader) async throws -> Int
}

extension SampleSyncTask {
    func earliestDate(reader: HealthReader, cutoff: Date) async throws -> Date? {
        try await reader.earliestStart(of: sampleType, before: cutoff)
    }

    func run(in interval: DateInterval, reader: HealthReader, uploader: Uploader) async throws -> Int {
        var count = 0
        try await reader.forEachPage(of: sampleType, in: interval) { samples in
            count += try await upload(samples, reader: reader, uploader: uploader)
        }
        return count
    }
}

struct QuantitySamplesTask: SampleSyncTask {
    let spec: QuantitySpec

    var id: String { "quantity:\(spec.name)" }
    var name: String { spec.name }
    var sampleType: HKSampleType { spec.type }
    var table: String { "quantity_samples" }

    func earliestDate(reader: HealthReader, cutoff: Date) async throws -> Date? {
        if case .none = spec.retention { return nil }
        guard let earliest = try await reader.earliestStart(of: sampleType, before: cutoff) else { return nil }
        return max(earliest, spec.retention.limit(from: cutoff) ?? earliest)
    }

    func run(in interval: DateInterval, reader: HealthReader, uploader: Uploader) async throws -> Int {
        let start = max(interval.start, spec.retention.limit(from: Date()) ?? interval.start)
        guard start < interval.end else { return 0 }
        var count = 0
        try await reader.forEachPage(of: sampleType, in: DateInterval(start: start, end: interval.end)) { samples in
            count += try await upload(samples, reader: reader, uploader: uploader)
        }
        return count
    }

    func upload(_ samples: [HKSample], reader: HealthReader, uploader: Uploader) async throws -> Int {
        if case .none = spec.retention { return 0 }
        let sourceIds = try await uploader.sourceIds(for: samples)
        let rows = samples.compactMap { $0 as? HKQuantitySample }.map { sample in
            QuantitySampleRow(
                uuid: sample.uuid,
                type: spec.name,
                value: sample.quantity.doubleValue(for: spec.unit),
                startAt: sample.startDate,
                endAt: sample.endDate,
                sourceId: sourceIds[SourceKey(sample: sample)],
                metadata: SampleMetadata.kept(from: sample.metadata)
            )
        }
        try await uploader.upsert(rows, into: table, onConflict: "uuid")
        return rows.count
    }
}

struct CategorySamplesTask: SampleSyncTask {
    let spec: CategorySpec

    var id: String { "category:\(spec.name)" }
    var name: String { spec.name }
    var sampleType: HKSampleType { spec.type }
    var table: String { "category_samples" }

    func upload(_ samples: [HKSample], reader: HealthReader, uploader: Uploader) async throws -> Int {
        let sourceIds = try await uploader.sourceIds(for: samples)
        let rows = samples.compactMap { $0 as? HKCategorySample }.map { sample in
            CategorySampleRow(
                uuid: sample.uuid,
                type: spec.name,
                value: spec.valueName(sample.value),
                startAt: sample.startDate,
                endAt: sample.endDate,
                sourceId: sourceIds[SourceKey(sample: sample)],
                metadata: SampleMetadata.kept(from: sample.metadata)
            )
        }
        try await uploader.upsert(rows, into: table, onConflict: "uuid")
        return rows.count
    }
}

struct DailyStatsTask: BackfillTask {
    let spec: QuantitySpec

    var id: String { "daily_stats:\(spec.name)" }
    var name: String { "\(spec.name) (일별)" }

    func earliestDate(reader: HealthReader, cutoff: Date) async throws -> Date? {
        try await reader.earliestStart(of: spec.type, before: cutoff)
    }

    func run(in interval: DateInterval, reader: HealthReader, uploader: Uploader) async throws -> Int {
        let rows = try await reader.dailyStatistics(for: spec, in: interval).compactMap { stats -> DailyStatRow? in
            let row = DailyStatRow(
                day: DailyStatRow.dayFormatter.string(from: stats.startDate),
                type: spec.name,
                sum: stats.sumQuantity()?.doubleValue(for: spec.unit),
                avg: stats.averageQuantity()?.doubleValue(for: spec.unit),
                min: stats.minimumQuantity()?.doubleValue(for: spec.unit),
                max: stats.maximumQuantity()?.doubleValue(for: spec.unit)
            )
            return row.sum == nil && row.avg == nil ? nil : row
        }
        try await uploader.upsert(rows, into: "daily_stats", onConflict: "user_id,type,day")
        return rows.count
    }
}

struct WorkoutsTask: SampleSyncTask {
    private static let distanceTypes = HealthCatalog.quantities.filter { $0.name.hasPrefix("distance_") }

    var id: String { "workouts" }
    var name: String { "workouts" }
    var sampleType: HKSampleType { .workoutType() }
    var table: String { "workouts" }

    func upload(_ samples: [HKSample], reader: HealthReader, uploader: Uploader) async throws -> Int {
        let workouts = samples.compactMap { $0 as? HKWorkout }
        let sourceIds = try await uploader.sourceIds(for: workouts)
        let rows = workouts.map { row(for: $0, sourceId: sourceIds[SourceKey(sample: $0)]) }
        try await uploader.upsert(rows, into: table, onConflict: "uuid")
        for workout in workouts {
            try await uploadRoutes(of: workout, reader: reader, uploader: uploader)
        }
        return rows.count
    }

    private func row(for workout: HKWorkout, sourceId: Int?) -> WorkoutRow {
        let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()
        let distance = Self.distanceTypes.lazy
            .compactMap { spec in workout.statistics(for: spec.type)?.sumQuantity()?.doubleValue(for: spec.unit) }
            .first
        let activities: [AnyJSON] = workout.workoutActivities.map { activity in
            .object([
                "activity_type": .string(HealthNames.name(
                    Int(activity.workoutConfiguration.activityType.rawValue),
                    in: HealthNames.workoutActivityType
                )),
                "start_at": JSONValue.date(activity.startDate),
                "end_at": JSONValue.date(activity.endDate),
                "duration_s": JSONValue.number(activity.duration),
                "statistics": JSONValue.statistics(activity.allStatistics) ?? .null,
            ])
        }
        let events: [AnyJSON] = (workout.workoutEvents ?? []).map { event in
            .object([
                "type": .string(HealthNames.name(event.type.rawValue, in: HealthNames.workoutEventType)),
                "start_at": JSONValue.date(event.dateInterval.start),
                "end_at": JSONValue.date(event.dateInterval.end),
                "metadata": SampleMetadata.all(from: event.metadata) ?? .null,
            ])
        }
        return WorkoutRow(
            uuid: workout.uuid,
            activityType: HealthNames.name(Int(workout.workoutActivityType.rawValue), in: HealthNames.workoutActivityType),
            startAt: workout.startDate,
            endAt: workout.endDate,
            durationS: workout.duration,
            totalEnergyKcal: energy?.doubleValue(for: .kilocalorie()),
            totalDistanceM: distance,
            sourceId: sourceId,
            statistics: JSONValue.statistics(workout.allStatistics),
            activities: activities.isEmpty ? nil : .array(activities),
            events: events.isEmpty ? nil : .array(events),
            metadata: SampleMetadata.all(from: workout.metadata)
        )
    }

    private func uploadRoutes(of workout: HKWorkout, reader: HealthReader, uploader: Uploader) async throws {
        let routes = try await reader.routes(for: workout)
        guard !routes.isEmpty else { return }
        let sourceIds = try await uploader.sourceIds(for: routes)
        for route in routes {
            let locations = try await reader.locations(of: route)
            guard !locations.isEmpty else { continue }
            let row = WorkoutRouteRow(
                uuid: route.uuid,
                workoutUuid: workout.uuid,
                startAt: route.startDate,
                endAt: route.endDate,
                sourceId: sourceIds[SourceKey(sample: route)],
                pointTimes: locations.map { $0.timestamp.timeIntervalSince1970 },
                latitudes: locations.map(\.coordinate.latitude),
                longitudes: locations.map(\.coordinate.longitude),
                altitudes: locations.map(\.altitude)
            )
            try await uploader.upsert([row], into: "workout_routes", onConflict: "uuid")
        }
    }
}

struct ActivitySummariesTask: BackfillTask {
    var id: String { "activity_summaries" }
    var name: String { "activity_summaries" }

    func earliestDate(reader: HealthReader, cutoff: Date) async throws -> Date? {
        try await reader.earliestStart(of: HKQuantityType(.activeEnergyBurned), before: cutoff)
    }

    func run(in interval: DateInterval, reader: HealthReader, uploader: Uploader) async throws -> Int {
        let calendar = Calendar.current
        let kcal = HKUnit.kilocalorie()
        let minutes = HKUnit.minute()
        let count = HKUnit.count()
        let rows = try await reader.activitySummaries(in: interval).compactMap { summary -> ActivitySummaryRow? in
            guard let date = calendar.date(from: summary.dateComponents(for: calendar)) else { return nil }
            return ActivitySummaryRow(
                day: DailyStatRow.dayFormatter.string(from: date),
                activeEnergyKcal: summary.activeEnergyBurned.doubleValue(for: kcal),
                activeEnergyGoalKcal: summary.activeEnergyBurnedGoal.doubleValue(for: kcal),
                moveTimeMin: summary.appleMoveTime.doubleValue(for: minutes),
                moveTimeGoalMin: summary.appleMoveTimeGoal.doubleValue(for: minutes),
                exerciseTimeMin: summary.appleExerciseTime.doubleValue(for: minutes),
                exerciseTimeGoalMin: summary.exerciseTimeGoal?.doubleValue(for: minutes),
                standHours: summary.appleStandHours.doubleValue(for: count),
                standHoursGoal: summary.standHoursGoal?.doubleValue(for: count)
            )
        }
        try await uploader.upsert(rows, into: "activity_summaries", onConflict: "user_id,day")
        return rows.count
    }
}

struct OtherSamplesTask: SampleSyncTask {
    let name: String
    let type: HKSampleType
    let batchSize: Int
    let payload: (HKSample, HealthReader) async throws -> AnyJSON?

    var id: String { "other:\(name)" }
    var sampleType: HKSampleType { type }
    var table: String { "other_samples" }

    func upload(_ samples: [HKSample], reader: HealthReader, uploader: Uploader) async throws -> Int {
        var count = 0
        let sourceIds = try await uploader.sourceIds(for: samples)
        var rows: [OtherSampleRow] = []
        for sample in samples {
            guard let payload = try await payload(sample, reader) else { continue }
            rows.append(OtherSampleRow(
                uuid: sample.uuid,
                type: name,
                startAt: sample.startDate,
                endAt: sample.endDate,
                sourceId: sourceIds[SourceKey(sample: sample)],
                payload: payload,
                metadata: SampleMetadata.kept(from: sample.metadata)
            ))
            if rows.count >= batchSize {
                try await uploader.upsert(rows, into: table, onConflict: "uuid")
                count += rows.count
                rows.removeAll()
            }
        }
        try await uploader.upsert(rows, into: table, onConflict: "uuid")
        return count + rows.count
    }
}
