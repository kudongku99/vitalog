import CoreLocation
import Foundation
import HealthKit

enum HealthReaderError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "이 기기에서는 건강 데이터를 읽을 수 없습니다."
    }
}

struct SampleChanges {
    let added: [HKSample]
    let deleted: [UUID]
    let anchor: HKQueryAnchor
}

final class HealthReader {
    let store = HKHealthStore()
    private var medicationNames: [AnyHashable: String]?

    func requestAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthReaderError.unavailable
        }
        try await store.requestAuthorization(toShare: [], read: HealthCatalog.readTypes)
    }

    func requestPerObjectAccess() async throws {
        try await store.requestPerObjectReadAuthorization(for: HKObjectType.visionPrescriptionType(), predicate: nil)
        if #available(iOS 26.0, *) {
            try await store.requestPerObjectReadAuthorization(for: HKObjectType.userAnnotatedMedicationType(), predicate: nil)
            medicationNames = nil
        }
    }

    func earliestStart(of type: HKSampleType, before cutoff: Date) async throws -> Date? {
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: cutoff, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)],
            limit: 1
        )
        return try await descriptor.result(for: store).first?.startDate
    }

    func forEachPage(
        of type: HKSampleType,
        in interval: DateInterval,
        _ body: ([HKSample]) async throws -> Void
    ) async throws {
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: .strictStartDate
        )
        var anchor: HKQueryAnchor?
        while true {
            let descriptor = HKAnchoredObjectQueryDescriptor(
                predicates: [.sample(type: type, predicate: predicate)],
                anchor: anchor,
                limit: Uploader.batchSize
            )
            let result = try await descriptor.result(for: store)
            if !result.addedSamples.isEmpty {
                try await body(result.addedSamples)
            }
            anchor = result.newAnchor
            if result.addedSamples.count < Uploader.batchSize {
                return
            }
        }
    }

    func changes(of type: HKSampleType, after anchor: HKQueryAnchor?, limit: Int) async throws -> SampleChanges {
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.sample(type: type)],
            anchor: anchor,
            limit: limit
        )
        let result = try await descriptor.result(for: store)
        return SampleChanges(
            added: result.addedSamples,
            deleted: result.deletedObjects.map(\.uuid),
            anchor: result.newAnchor
        )
    }

    func dailyStatistics(for spec: QuantitySpec, in interval: DateInterval) async throws -> [HKStatistics] {
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: spec.type, predicate: predicate),
            options: spec.isCumulative ? .cumulativeSum : [.discreteAverage, .discreteMin, .discreteMax],
            anchorDate: Calendar.current.startOfDay(for: interval.start),
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)
        return collection.statistics().filter { $0.startDate >= interval.start && $0.startDate < interval.end }
    }

    func routes(for workout: HKWorkout) async throws -> [HKWorkoutRoute] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store)
    }

    func locations(of route: HKWorkoutRoute) async throws -> [CLLocation] {
        var locations: [CLLocation] = []
        for try await location in HKWorkoutRouteQueryDescriptor(route).results(for: store) {
            locations.append(location)
        }
        return locations
    }

    func activitySummaries(in interval: DateInterval) async throws -> [HKActivitySummary] {
        let calendar = Calendar.current
        var start = calendar.dateComponents([.era, .year, .month, .day], from: interval.start)
        start.calendar = calendar
        var end = calendar.dateComponents([.era, .year, .month, .day], from: interval.end.addingTimeInterval(-1))
        end.calendar = calendar
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: start, end: end)
        return try await HKActivitySummaryQueryDescriptor(predicate: predicate).result(for: store)
    }

    func characteristics() -> CharacteristicsRow {
        func name(_ value: Int?, in table: [Int: String]) -> String? {
            guard let value, value != 0 else { return nil }
            return HealthNames.name(value, in: table)
        }
        var dateOfBirth: String?
        if let components = try? store.dateOfBirthComponents(),
           let date = Calendar(identifier: .gregorian).date(from: components) {
            dateOfBirth = DailyStatRow.dayFormatter.string(from: date)
        }
        return CharacteristicsRow(
            biologicalSex: name((try? store.biologicalSex())?.biologicalSex.rawValue, in: HealthNames.biologicalSex),
            bloodType: name((try? store.bloodType())?.bloodType.rawValue, in: HealthNames.bloodType),
            dateOfBirth: dateOfBirth,
            fitzpatrickSkinType: name((try? store.fitzpatrickSkinType())?.skinType.rawValue, in: HealthNames.fitzpatrickSkinType),
            wheelchairUse: name((try? store.wheelchairUse())?.wheelchairUse.rawValue, in: HealthNames.wheelchairUse),
            activityMoveMode: name((try? store.activityMoveMode())?.activityMoveMode.rawValue, in: HealthNames.activityMoveMode)
        )
    }

    func voltages(of electrocardiogram: HKElectrocardiogram) async throws -> [Double] {
        let microvolts = HKUnit.voltUnit(with: .micro)
        var voltages: [Double] = []
        for try await measurement in HKElectrocardiogramQueryDescriptor(electrocardiogram).results(for: store) {
            voltages.append(measurement.quantity(for: .appleWatchSimilarToLeadI)?.doubleValue(for: microvolts) ?? .nan)
        }
        return voltages
    }

    func heartbeats(of series: HKHeartbeatSeriesSample) async throws -> [HKHeartbeatSeriesQueryDescriptor.Heartbeat] {
        var beats: [HKHeartbeatSeriesQueryDescriptor.Heartbeat] = []
        for try await beat in HKHeartbeatSeriesQueryDescriptor(series).results(for: store) {
            beats.append(beat)
        }
        return beats
    }

    @available(iOS 26.0, *)
    func medicationName(for identifier: HKHealthConceptIdentifier) async throws -> String? {
        if medicationNames == nil {
            let medications = try await HKUserAnnotatedMedicationQueryDescriptor().result(for: store)
            medicationNames = Dictionary(
                medications.map { (AnyHashable($0.medication.identifier), $0.nickname ?? $0.medication.displayText) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        return medicationNames?[AnyHashable(identifier)]
    }
}
