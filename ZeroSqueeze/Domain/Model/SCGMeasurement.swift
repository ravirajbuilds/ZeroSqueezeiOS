import Foundation

/// A single chest seismocardiography (SCG) capture result.
///
/// SCG reads the micro-vibrations the beating heart transmits into the chest
/// wall. With the phone resting on the sternum, the accelerometer picks up the
/// cardiac wall-motion complex: the AO (aortic-valve opening) peak, the AC
/// (aortic-valve closing) peak, and the surrounding systolic/diastolic waves.
///
/// From the AO-to-AO interval we derive heart rate and beat-to-beat
/// variability; from the AO→AC span we derive left-ventricular ejection time
/// (LVET), a systolic time interval that tracks contractility and, combined
/// with heart rate, an SCG-only blood-pressure index.
struct SCGMeasurement: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date

    /// Heart rate, beats per minute. Nil if AO-peak detection failed.
    let heartRateBpm: Int?

    /// Heart-rate variability, SDNN in milliseconds. Nil if too few beats.
    let hrvSdnnMs: Double?

    /// Respiratory rate, breaths per minute. Estimated from the slow
    /// respiratory modulation of the SCG envelope. Nil when the trace was too
    /// short or aperiodic to fit.
    var respirationBpm: Double? = nil

    /// Left-ventricular ejection time, milliseconds — the AO→AC span averaged
    /// over beats. A systolic time interval; it shortens at higher heart rate
    /// and falls with reduced contractility. Nil when the AC peak couldn't be
    /// localised on enough beats.
    var lvetMs: Double? = nil

    /// AO-complex amplitude in milli-g — the strength of the systolic kick the
    /// heart delivers to the chest wall. A relative contractility proxy. Nil
    /// for records saved before SCG morphology shipped.
    var aoAmplitudeMg: Double? = nil

    /// SCG-only estimated systolic blood pressure, mmHg, derived from heart
    /// rate + LVET via the systolic-time-interval model. An index, not a cuff
    /// reading. Nil when LVET was unavailable.
    var estSystolicMmHg: Double? = nil

    /// SCG-only estimated diastolic blood pressure, mmHg. Nil when unavailable.
    var estDiastolicMmHg: Double? = nil

    /// Signal quality in [0, 1]. Anything below ~0.4 should be treated as suspect.
    let signalQuality: Float

    /// Which HR backend produced this ("classic-scg", "coreml-scg").
    /// Optional so records saved before the model router shipped decode.
    var modelSource: String? = nil

    static let placeholder = SCGMeasurement(
        id: UUID(),
        timestamp: Date(),
        heartRateBpm: 68,
        hrvSdnnMs: 42,
        respirationBpm: 14,
        lvetMs: 295,
        aoAmplitudeMg: 18,
        estSystolicMmHg: 118,
        estDiastolicMmHg: 76,
        signalQuality: 0.75
    )
}
