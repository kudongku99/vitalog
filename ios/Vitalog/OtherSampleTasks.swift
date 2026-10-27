import Foundation
import HealthKit
import Supabase

enum OtherSampleTasks {
    private static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
    private static let diopter = HKUnit.diopter()
    private static let degrees = HKUnit.degreeAngle()
    private static let millimeters = HKUnit.meterUnit(with: .milli)

    static var all: [OtherSamplesTask] {
        var tasks = [
            OtherSamplesTask(name: "electrocardiogram", type: .electrocardiogramType(), batchSize: 1) { sample, reader in
                guard let ecg = sample as? HKElectrocardiogram else { return nil }
                let voltages = try await reader.voltages(of: ecg)
                return .object([
                    "classification": .string(HealthNames.name(ecg.classification.rawValue, in: HealthNames.ecgClassification)),
                    "symptoms_status": .string(HealthNames.name(ecg.symptomsStatus.rawValue, in: HealthNames.ecgSymptomsStatus)),
                    "average_heart_rate": JSONValue.number(ecg.averageHeartRate, beatsPerMinute),
                    "sampling_frequency_hz": JSONValue.number(ecg.samplingFrequency, .hertz()),
                    "voltages_uv": .array(voltages.map(JSONValue.number)),
                ])
            },
            OtherSamplesTask(name: "heartbeat_series", type: HKSeriesType.heartbeat(), batchSize: 100) { sample, reader in
                guard let series = sample as? HKHeartbeatSeriesSample else { return nil }
                let beats = try await reader.heartbeats(of: series)
                return .object([
                    "beat_times_s": .array(beats.map { JSONValue.number($0.timeIntervalSinceStart) }),
                    "gap_indices": .array(beats.indices.filter { beats[$0].precededByGap }.map { .integer($0) }),
                ])
            },
            OtherSamplesTask(name: "audiogram", type: .audiogramSampleType(), batchSize: 100) { sample, _ in
                guard let audiogram = sample as? HKAudiogramSample else { return nil }
                return .object(["points": .array(audiogram.sensitivityPoints.map(audiogramPoint))])
            },
            OtherSamplesTask(name: "vision_prescription", type: .visionPrescriptionType(), batchSize: 100) { sample, _ in
                guard let prescription = sample as? HKVisionPrescription else { return nil }
                return visionPrescription(prescription)
            },
        ]
        if #available(iOS 18.0, *) {
            tasks += [
                OtherSamplesTask(name: "state_of_mind", type: .stateOfMindType(), batchSize: 1000) { sample, _ in
                    guard let mind = sample as? HKStateOfMind else { return nil }
                    return .object([
                        "kind": .string(HealthNames.name(mind.kind.rawValue, in: HealthNames.stateOfMindKind)),
                        "valence": JSONValue.number(mind.valence),
                        "valence_classification": .string(HealthNames.name(
                            mind.valenceClassification.rawValue,
                            in: HealthNames.valenceClassification
                        )),
                        "labels": .array(mind.labels.map {
                            .string(HealthNames.name($0.rawValue, in: HealthNames.stateOfMindLabel))
                        }),
                        "associations": .array(mind.associations.map {
                            .string(HealthNames.name($0.rawValue, in: HealthNames.stateOfMindAssociation))
                        }),
                    ])
                },
                OtherSamplesTask(name: "gad7", type: HKScoredAssessmentType(.GAD7), batchSize: 1000) { sample, _ in
                    guard let assessment = sample as? HKGAD7Assessment else { return nil }
                    return .object([
                        "score": .integer(assessment.score),
                        "risk": .string(HealthNames.name(assessment.risk.rawValue, in: HealthNames.gad7Risk)),
                        "answers": .array(assessment.answers.map { .integer($0.rawValue) }),
                    ])
                },
                OtherSamplesTask(name: "phq9", type: HKScoredAssessmentType(.PHQ9), batchSize: 1000) { sample, _ in
                    guard let assessment = sample as? HKPHQ9Assessment else { return nil }
                    return .object([
                        "score": .integer(assessment.score),
                        "risk": .string(HealthNames.name(assessment.risk.rawValue, in: HealthNames.phq9Risk)),
                        "answers": .array(assessment.answers.map { .integer($0.rawValue) }),
                    ])
                },
            ]
        }
        if #available(iOS 26.0, *) {
            tasks.append(
                OtherSamplesTask(name: "medication_dose_event", type: .medicationDoseEventType(), batchSize: 1000) { sample, reader in
                    guard let dose = sample as? HKMedicationDoseEvent else { return nil }
                    let medication = try await reader.medicationName(for: dose.medicationConceptIdentifier)
                    return .object([
                        "medication": medication.map(AnyJSON.string) ?? .null,
                        "log_status": .string(HealthNames.name(dose.logStatus.rawValue, in: HealthNames.doseLogStatus)),
                        "schedule_type": .string(HealthNames.name(dose.scheduleType.rawValue, in: HealthNames.doseScheduleType)),
                        "scheduled_at": JSONValue.date(dose.scheduledDate),
                        "scheduled_dose_quantity": JSONValue.number(dose.scheduledDoseQuantity),
                        "dose_quantity": JSONValue.number(dose.doseQuantity),
                        "unit": .string(dose.unit.unitString),
                    ])
                }
            )
        }
        return tasks
    }

    private static func audiogramPoint(_ point: HKAudiogramSensitivityPoint) -> AnyJSON {
        let hearingLevel = HKUnit.decibelHearingLevel()
        var object: JSONObject = ["frequency_hz": JSONValue.number(point.frequency, .hertz())]
        if #available(iOS 18.1, *) {
            object["tests"] = .array(point.tests.map { test in
                .object([
                    "side": .string(test.side == .left ? "left" : "right"),
                    "conduction": .string(test.type == .air ? "air" : String(test.type.rawValue)),
                    "masked": .bool(test.masked),
                    "sensitivity_db_hl": JSONValue.number(test.sensitivity, hearingLevel),
                ])
            })
        } else {
            object["left_db_hl"] = JSONValue.number(point.leftEarSensitivity, hearingLevel)
            object["right_db_hl"] = JSONValue.number(point.rightEarSensitivity, hearingLevel)
        }
        return .object(object)
    }

    private static func visionPrescription(_ prescription: HKVisionPrescription) -> AnyJSON {
        var object: JSONObject = [
            "prescription_type": .string(HealthNames.name(
                Int(prescription.prescriptionType.rawValue),
                in: HealthNames.visionPrescriptionType
            )),
            "date_issued": JSONValue.date(prescription.dateIssued),
            "expiration_date": JSONValue.date(prescription.expirationDate),
        ]
        if let glasses = prescription as? HKGlassesPrescription {
            object["right_eye"] = lens(glasses.rightEye)
            object["left_eye"] = lens(glasses.leftEye)
        } else if let contacts = prescription as? HKContactsPrescription {
            object["brand"] = .string(contacts.brand)
            object["right_eye"] = lens(contacts.rightEye)
            object["left_eye"] = lens(contacts.leftEye)
        }
        return .object(object)
    }

    private static func lens(_ specification: HKLensSpecification?) -> AnyJSON {
        guard let specification else { return .null }
        var object: JSONObject = [
            "sphere": JSONValue.number(specification.sphere, diopter),
            "cylinder": JSONValue.number(specification.cylinder, diopter),
            "axis": JSONValue.number(specification.axis, degrees),
            "add_power": JSONValue.number(specification.addPower, diopter),
        ]
        if let contacts = specification as? HKContactsLensSpecification {
            object["base_curve_mm"] = JSONValue.number(contacts.baseCurve, millimeters)
            object["diameter_mm"] = JSONValue.number(contacts.diameter, millimeters)
        }
        return .object(object)
    }
}
