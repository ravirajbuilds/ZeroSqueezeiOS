import Foundation

/// A self-reported daily wellbeing entry that sits alongside the camera-derived
/// vitals. One per calendar day (logging again overwrites the day's entry).
///
/// `mood` and `energy` are 1…5 Likert values; `symptoms` is a free set drawn
/// from `CheckIn.symptomOptions`; `note` is optional free text.
struct CheckIn: Codable, Identifiable, Equatable {
    let id: UUID
    /// Start-of-day the entry describes — the dedup key.
    let day: Date
    /// When the entry was actually written.
    let timestamp: Date
    var mood: Int
    var energy: Int
    var symptoms: [String]
    var note: String

    init(
        id: UUID = UUID(),
        day: Date,
        timestamp: Date,
        mood: Int,
        energy: Int,
        symptoms: [String] = [],
        note: String = ""
    ) {
        self.id = id
        self.day = day
        self.timestamp = timestamp
        self.mood = mood
        self.energy = energy
        self.symptoms = symptoms
        self.note = note
    }

    /// Common, non-alarming symptoms a wellness user might track. Free text in
    /// `note` covers anything else.
    static let symptomOptions = [
        "Tired", "Headache", "Dizzy", "Stressed",
        "Poor sleep", "Cold/flu", "Sore", "Anxious"
    ]

    static func moodLabel(_ v: Int) -> String {
        switch v {
        case 1: return "Rough"
        case 2: return "Meh"
        case 3: return "Okay"
        case 4: return "Good"
        default: return "Great"
        }
    }

    static func moodEmoji(_ v: Int) -> String {
        switch v {
        case 1: return "😣"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "🙂"
        default: return "😄"
        }
    }

    static func energyLabel(_ v: Int) -> String {
        switch v {
        case 1: return "Drained"
        case 2: return "Low"
        case 3: return "Steady"
        case 4: return "Energetic"
        default: return "Buzzing"
        }
    }
}
