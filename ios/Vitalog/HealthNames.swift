import Foundation

enum HealthNames {
    static func name(_ value: Int, in table: [Int: String]) -> String {
        table[value] ?? String(value)
    }

    static let workoutActivityType: [Int: String] = [
        1: "american_football",
        2: "archery",
        3: "australian_football",
        4: "badminton",
        5: "baseball",
        6: "basketball",
        7: "bowling",
        8: "boxing",
        9: "climbing",
        10: "cricket",
        11: "cross_training",
        12: "curling",
        13: "cycling",
        14: "dance",
        15: "dance_inspired_training",
        16: "elliptical",
        17: "equestrian_sports",
        18: "fencing",
        19: "fishing",
        20: "functional_strength_training",
        21: "golf",
        22: "gymnastics",
        23: "handball",
        24: "hiking",
        25: "hockey",
        26: "hunting",
        27: "lacrosse",
        28: "martial_arts",
        29: "mind_and_body",
        30: "mixed_metabolic_cardio_training",
        31: "paddle_sports",
        32: "play",
        33: "preparation_and_recovery",
        34: "racquetball",
        35: "rowing",
        36: "rugby",
        37: "running",
        38: "sailing",
        39: "skating_sports",
        40: "snow_sports",
        41: "soccer",
        42: "softball",
        43: "squash",
        44: "stair_climbing",
        45: "surfing_sports",
        46: "swimming",
        47: "table_tennis",
        48: "tennis",
        49: "track_and_field",
        50: "traditional_strength_training",
        51: "volleyball",
        52: "walking",
        53: "water_fitness",
        54: "water_polo",
        55: "water_sports",
        56: "wrestling",
        57: "yoga",
        58: "barre",
        59: "core_training",
        60: "cross_country_skiing",
        61: "downhill_skiing",
        62: "flexibility",
        63: "high_intensity_interval_training",
        64: "jump_rope",
        65: "kickboxing",
        66: "pilates",
        67: "snowboarding",
        68: "stairs",
        69: "step_training",
        70: "wheelchair_walk_pace",
        71: "wheelchair_run_pace",
        72: "tai_chi",
        73: "mixed_cardio",
        74: "hand_cycling",
        75: "disc_sports",
        76: "fitness_gaming",
        77: "cardio_dance",
        78: "social_dance",
        79: "pickleball",
        80: "cooldown",
        82: "swim_bike_run",
        83: "transition",
        84: "underwater_diving",
        2998: "rest",
        2999: "group",
        3000: "other",
    ]

    static let workoutEventType: [Int: String] = [
        1: "pause",
        2: "resume",
        3: "lap",
        4: "marker",
        5: "motion_paused",
        6: "motion_resumed",
        7: "segment",
        8: "pause_or_resume_request",
    ]

    static let stateOfMindKind: [Int: String] = [
        1: "momentary_emotion",
        2: "daily_mood",
    ]

    static let valenceClassification: [Int: String] = [
        1: "very_unpleasant",
        2: "unpleasant",
        3: "slightly_unpleasant",
        4: "neutral",
        5: "slightly_pleasant",
        6: "pleasant",
        7: "very_pleasant",
    ]

    static let stateOfMindLabel: [Int: String] = [
        1: "amazed",
        2: "amused",
        3: "angry",
        4: "anxious",
        5: "ashamed",
        6: "brave",
        7: "calm",
        8: "content",
        9: "disappointed",
        10: "discouraged",
        11: "disgusted",
        12: "embarrassed",
        13: "excited",
        14: "frustrated",
        15: "grateful",
        16: "guilty",
        17: "happy",
        18: "hopeless",
        19: "irritated",
        20: "jealous",
        21: "joyful",
        22: "lonely",
        23: "passionate",
        24: "peaceful",
        25: "proud",
        26: "relieved",
        27: "sad",
        28: "scared",
        29: "stressed",
        30: "surprised",
        31: "worried",
        32: "annoyed",
        33: "confident",
        34: "drained",
        35: "hopeful",
        36: "indifferent",
        37: "overwhelmed",
        38: "satisfied",
    ]

    static let stateOfMindAssociation: [Int: String] = [
        1: "community",
        2: "current_events",
        3: "dating",
        4: "education",
        5: "family",
        6: "fitness",
        7: "friends",
        8: "health",
        9: "hobbies",
        10: "identity",
        11: "money",
        12: "partner",
        13: "self_care",
        14: "spirituality",
        15: "tasks",
        16: "travel",
        17: "work",
        18: "weather",
    ]

    static let ecgClassification: [Int: String] = [
        0: "not_set",
        1: "sinus_rhythm",
        2: "atrial_fibrillation",
        3: "inconclusive_low_heart_rate",
        4: "inconclusive_high_heart_rate",
        5: "inconclusive_poor_reading",
        6: "inconclusive_other",
        100: "unrecognized",
    ]

    static let ecgSymptomsStatus: [Int: String] = [
        0: "not_set",
        1: "none",
        2: "present",
    ]

    static let biologicalSex: [Int: String] = [
        0: "not_set",
        1: "female",
        2: "male",
        3: "other",
    ]

    static let bloodType: [Int: String] = [
        0: "not_set",
        1: "a_positive",
        2: "a_negative",
        3: "b_positive",
        4: "b_negative",
        5: "ab_positive",
        6: "ab_negative",
        7: "o_positive",
        8: "o_negative",
    ]

    static let fitzpatrickSkinType: [Int: String] = [
        0: "not_set",
        1: "i",
        2: "ii",
        3: "iii",
        4: "iv",
        5: "v",
        6: "vi",
    ]

    static let wheelchairUse: [Int: String] = [
        0: "not_set",
        1: "no",
        2: "yes",
    ]

    static let activityMoveMode: [Int: String] = [
        1: "active_energy",
        2: "apple_move_time",
    ]

    static let gad7Risk: [Int: String] = [
        1: "none_to_minimal",
        2: "mild",
        3: "moderate",
        4: "severe",
    ]

    static let phq9Risk: [Int: String] = [
        1: "none_to_minimal",
        2: "mild",
        3: "moderate",
        4: "moderately_severe",
        5: "severe",
    ]

    static let doseLogStatus: [Int: String] = [
        1: "not_interacted",
        2: "notification_not_sent",
        3: "snoozed",
        4: "taken",
        5: "skipped",
        6: "not_logged",
    ]

    static let doseScheduleType: [Int: String] = [
        1: "as_needed",
        2: "schedule",
    ]

    static let visionPrescriptionType: [Int: String] = [
        1: "glasses",
        2: "contacts",
    ]
}
