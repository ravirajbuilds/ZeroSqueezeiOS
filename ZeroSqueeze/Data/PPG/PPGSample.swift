import Foundation

/// One frame's worth of PPG data: timestamp + mean R/G/B over the ROI.
struct PPGSample: Equatable, Sendable {
    let t: TimeInterval
    let r: Double
    let g: Double
    let b: Double
}
