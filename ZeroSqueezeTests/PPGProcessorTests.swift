import XCTest
@testable import ZeroSqueeze

final class PPGProcessorTests: XCTestCase {

    /// 30 s of synthetic 1.2 Hz (72 bpm) sinusoid sampled at 30 fps should land
    /// the processor's heart-rate estimate within ±5 bpm of the true value.
    func testSyntheticHeartRate() {
        let processor = PPGProcessor()
        let fs: Double = 30
        let trueHz: Double = 1.2
        let duration: Double = 30
        let dc: Double = 200
        let amp: Double = 6
        let n = Int(duration * fs)
        for i in 0..<n {
            let t = Double(i) / fs
            let r = dc + amp * sin(2 * .pi * trueHz * t)
            let g = (dc * 0.6) + amp * 0.4 * sin(2 * .pi * trueHz * t)
            let b = (dc * 0.4) + amp * 0.2 * sin(2 * .pi * trueHz * t)
            processor.ingest(PPGSample(t: t, r: r, g: g, b: b))
        }
        let bpm = processor.heartRateBpm
        XCTAssertNotNil(bpm)
        if let bpm {
            XCTAssertEqual(Double(bpm), trueHz * 60, accuracy: 5)
        }
    }

    func testReturnsNilWhenSignalFlat() {
        let processor = PPGProcessor()
        for i in 0..<300 {
            let t = Double(i) / 30
            processor.ingest(PPGSample(t: t, r: 220, g: 100, b: 50))
        }
        XCTAssertNil(processor.heartRateBpm)
    }

    /// Below the noise floor (acRed < 3) the peak detector must stay silent —
    /// otherwise jitter on a covered-but-still finger fabricates a heart rate.
    func testNoiseFloorSuppressesFalsePeaks() {
        let processor = PPGProcessor()
        var rng = SystemRandomNumberGenerator()
        for i in 0..<600 {
            let t = Double(i) / 30
            let noise = (Double(rng.next() % 100) / 100.0 - 0.5) * 1.5
            processor.ingest(PPGSample(t: t, r: 230 + noise, g: 100, b: 50))
        }
        XCTAssertNil(processor.heartRateBpm,
                     "Sub-threshold noise should not produce IBIs")
    }

    /// Low-amplitude PPG calibration: amplitude ~0.8 (out of 0-255) at 1.1 Hz with the
    /// scg-tuned thresholds must still detect a heart rate. With the fingertip
    /// defaults (noiseFloor=3) this signal is silenced; the scg-tuned
    /// configuration must recover it. Locks in the fix for the scg-flow bug.
    func testFaceTunedProcessorDetectsLowAmplitudeSignal() {
        let processor = PPGProcessor(noiseFloor: 0.3, minPeakThreshold: 0.15)
        let fs: Double = 30
        let trueHz: Double = 1.1
        for i in 0..<Int(30 * fs) {
            let t = Double(i) / fs
            let r = 120 + 0.8 * sin(2 * .pi * trueHz * t)
            processor.ingest(PPGSample(t: t, r: r, g: 60, b: 30))
        }
        let bpm = processor.heartRateBpm
        XCTAssertNotNil(bpm, "Chest-tuned processor must detect low-amplitude pulse")
        if let bpm {
            XCTAssertEqual(Double(bpm), trueHz * 60, accuracy: 6)
        }
    }

    /// Fingertip defaults must still reject the same low-amplitude signal —
    /// otherwise the scg tuning would have just leaked the noise floor for
    /// every caller.
    func testFingertipDefaultsRejectLowAmplitudeSignal() {
        let processor = PPGProcessor()
        let fs: Double = 30
        let trueHz: Double = 1.1
        for i in 0..<Int(30 * fs) {
            let t = Double(i) / fs
            let r = 200 + 0.8 * sin(2 * .pi * trueHz * t)
            processor.ingest(PPGSample(t: t, r: r, g: 100, b: 50))
        }
        XCTAssertNil(processor.heartRateBpm,
                     "0.8-unit AC must not clear the fingertip noise floor of 3")
    }

    func testPerfusionIndexGrowsWithAmplitude() {
        func runWithAmplitude(_ amp: Double) -> Double {
            let p = PPGProcessor()
            for i in 0..<300 {
                let t = Double(i) / 30
                let r = 200 + amp * sin(2 * .pi * 1.2 * t)
                p.ingest(PPGSample(t: t, r: r, g: 100, b: 50))
            }
            return p.perfusionIndex
        }
        XCTAssertGreaterThan(runWithAmplitude(20), runWithAmplitude(2))
    }
}
