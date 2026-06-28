import Foundation

enum AgeType: String, CaseIterable {
    case child
    case adult
    case senior

    var label: String {
        switch self {
        case .child: return "Child"
        case .adult: return "Adult"
        case .senior: return "Senior"
        }
    }
}
