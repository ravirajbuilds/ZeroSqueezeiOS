import Foundation

enum Gender: String, CaseIterable, Codable {
    case male = "MALE"
    case female = "FEMALE"
    case other = "OTHER"

    /// Map an unknown raw value to `.other` rather than throwing, so a profile
    /// written by a newer build still decodes (and never forces a silent
    /// re-onboarding) on an older one.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Gender(rawValue: raw) ?? .other
    }

    var label: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .other: return "Other"
        }
    }

    var shortLabel: String {
        switch self {
        case .male: return "M"
        case .female: return "F"
        case .other: return "Other"
        }
    }
}
