import Foundation

/// A single fused chest-SCG + finger-PPG "Heart Check" result — the capstone
/// reading that uses both sensors at once to recover pulse transit time and a
/// cuffless blood pressure, then synthesizes a heart-health score + heart age.
struct HeartCheckMeasurement: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date

    let heartRateBpm: Int?
    let hrvSdnnMs: Double?
    /// Pulse transit time (SCG AO → finger PPG), milliseconds.
    let pttMs: Double?
    let systolicMmHg: Double?
    let diastolicMmHg: Double?
    let lvetMs: Double?

    /// 0–100 cardiovascular wellness score.
    let heartHealthScore: Int
    /// Estimated heart age, years.
    let heartAge: Int

    /// Fused signal quality in [0, 1].
    let signalQuality: Float

    static let placeholder = HeartCheckMeasurement(
        id: UUID(), timestamp: Date(),
        heartRateBpm: 64, hrvSdnnMs: 52, pttMs: 240,
        systolicMmHg: 122, diastolicMmHg: 78, lvetMs: 298,
        heartHealthScore: 82, heartAge: 29, signalQuality: 0.8
    )
}
