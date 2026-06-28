import Foundation

struct UserProfile: Codable, Equatable {
    var age: Int
    var gender: Gender
    var skinTone: Int?

    /// Legacy v1 calibration offset (g/dL). Superseded by
    /// `CalibrationStore` (multi-point linear fit); kept only so old
    /// profiles decode and migrate. Do not write.
    var hbCalibrationOffset: Float? = nil

    var ageType: AgeType {
        if age < 18 { return .child }
        if age >= 65 { return .senior }
        return .adult
    }

    var monkSkinTone: MonkSkinTone? {
        MonkSkinTone.fromTone(skinTone)
    }

    static let placeholder = UserProfile(age: 30, gender: .other, skinTone: nil)
}
