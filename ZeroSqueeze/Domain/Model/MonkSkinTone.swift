import Foundation

/// Monk Skin Tone Scale (MST-10). Tone index 1..10. Hex codes per
/// skintone.google research release.
enum MonkSkinTone: Int, CaseIterable {
    case mst1 = 1
    case mst2, mst3, mst4, mst5, mst6, mst7, mst8, mst9, mst10

    var tone: Int { rawValue }

    var hex: String {
        switch self {
        case .mst1:  return "#F6EDE4"
        case .mst2:  return "#F3E7DB"
        case .mst3:  return "#F7EAD0"
        case .mst4:  return "#EADABA"
        case .mst5:  return "#D7BD96"
        case .mst6:  return "#A07E56"
        case .mst7:  return "#825C43"
        case .mst8:  return "#604134"
        case .mst9:  return "#3A312A"
        case .mst10: return "#292420"
        }
    }

    static func fromTone(_ tone: Int?) -> MonkSkinTone? {
        guard let tone else { return nil }
        return MonkSkinTone(rawValue: tone)
    }

    static var all: [MonkSkinTone] { allCases.sorted { $0.tone < $1.tone } }
}
