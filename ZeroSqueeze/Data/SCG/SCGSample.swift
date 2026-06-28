import Foundation

/// One accelerometer frame of seismocardiography data: timestamp + the
/// three-axis user acceleration (gravity already removed by CoreMotion's
/// device-motion fusion), in g.
struct SCGSample: Equatable, Sendable {
    let t: TimeInterval
    let ax: Double
    let ay: Double
    let az: Double

    /// Dorso-ventral magnitude — the axis that carries most cardiac wall
    /// motion when the phone lies flat on the sternum. We keep the full
    /// vector magnitude so the signal survives small phone-orientation
    /// changes between users.
    var magnitude: Double { (ax * ax + ay * ay + az * az).squareRoot() }
}
