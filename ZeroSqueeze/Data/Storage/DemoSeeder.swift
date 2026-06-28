import Foundation

/// Seeds 14 days of plausible Hb + scg-scan history if both stores are
/// empty. Runs once on first launch. Real measurements stay untouched —
/// any existing data short-circuits the seed.
@MainActor
enum DemoSeeder {

    private static let seededFlagKey = "zerosqueeze.demo_seeded.v1"

    /// Resets the "already seeded" flag — used by tests and future
    /// reset-and-reseed UI affordances.
    static func resetSeededFlag(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: seededFlagKey)
    }

    static func seedIfEmpty(
        hbStore: MeasurementStore = .shared,
        scgStore: SCGMeasurementStore = .shared,
        checkInStore: CheckInStore = .shared,
        profile: UserProfile = .placeholder,
        defaults: UserDefaults = .standard
    ) {
        // One-shot per install. Without this flag, "Clear history" from the
        // profile menu would silently re-summon the demo data on next launch
        // — frustrating once the user has real captures of their own.
        if defaults.bool(forKey: seededFlagKey) { return }
        guard hbStore.measurements.isEmpty, scgStore.measurements.isEmpty else {
            defaults.set(true, forKey: seededFlagKey)
            return
        }
        // Stores prepend on `append()` (newest-first invariant). Replay
        // chronological order — oldest first — so the freshest reading
        // ends up at `measurements.first` and surfaces as "latest" on Home.
        for m in syntheticHb(profile: profile).reversed() {
            hbStore.append(m)
        }
        for m in syntheticSCG().reversed() {
            scgStore.append(m)
        }
        // A handful of journal entries so the Insights journal isn't empty on
        // a fresh install. `upsert` keys by day, so order doesn't matter.
        for c in syntheticCheckIns() {
            checkInStore.upsert(c)
        }
        defaults.set(true, forKey: seededFlagKey)
    }

    // ── Check-in (journal) history ───────────────────────────────────

    /// A few plausible daily check-ins across the last fortnight. Deterministic
    /// so screenshots reproduce across fresh installs.
    private static func syntheticCheckIns() -> [CheckIn] {
        let cal = Calendar.current
        // (daysAgo, mood, energy, symptoms, note)
        let script: [(Int, Int, Int, [String], String)] = [
            (0,  4, 4, [],                 "Felt sharp this morning."),
            (1,  3, 3, ["Tired"],          ""),
            (3,  2, 2, ["Poor sleep", "Headache"], "Rough night, low all day."),
            (5,  4, 3, [],                 "Back on track after a walk."),
            (8,  5, 5, [],                 "Great energy, slept well."),
            (11, 3, 2, ["Stressed"],       "Busy week catching up."),
        ]
        return script.map { (daysAgo, mood, energy, symptoms, note) in
            let day = cal.startOfDay(for: date(daysAgo: daysAgo, hour: 9, minute: 0))
            return CheckIn(
                day: day,
                timestamp: date(daysAgo: daysAgo, hour: 9, minute: 15),
                mood: mood,
                energy: energy,
                symptoms: symptoms,
                note: note
            )
        }
    }

    // ── Hb history ───────────────────────────────────────────────────

    /// 14 days, one reading most days, mild downward dip mid-window then
    /// recovery. Values centred on demographic baseline ± small jitter.
    private static func syntheticHb(profile: UserProfile) -> [HbMeasurement] {
        let baseline: Float = {
            switch profile.gender {
            case .male:   return 14.6
            case .female: return 13.4
            case .other:  return 14.0
            }
        }()

        // Deterministic jitter so the demo looks "real" but repeats the
        // same shape every fresh install — easier to screenshot.
        var seed = SeededRng(seed: 42)
        let dayOffsets: [Int] = [0, 1, 3, 4, 6, 7, 8, 10, 11, 13]
        let dipPattern: [Float] = [0.0, -0.1, -0.3, -0.5, -0.7, -0.4, -0.2, 0.0, 0.1, 0.2]

        return dayOffsets.enumerated().compactMap { (i, daysAgo) -> HbMeasurement? in
            let jitter = Float(seed.next() * 0.4 - 0.2)
            let point  = baseline + dipPattern[i] + jitter
            let band: Float = 0.9 + Float(seed.next()) * 0.4
            let hr = 64 + Int(seed.next() * 16)
            let pi = 1.6 + Float(seed.next()) * 1.8
            let quality = 0.6 + Float(seed.next()) * 0.35
            let hour = 8 + Int(seed.next() * 10)
            let minute = Int(seed.next() * 60)
            return HbMeasurement(
                id: UUID(),
                timestamp: date(daysAgo: daysAgo, hour: hour, minute: minute),
                heartRateBpm: hr,
                hemoglobinGPerDl: point,
                hemoglobinBand: band,
                perfusionIndex: pi,
                signalQuality: quality,
                anemia: AnemiaStatus.fromHemoglobin(point, gender: profile.gender)
            )
        }
    }

    // ── Chest scan history ────────────────────────────────────────────

    private static func syntheticSCG() -> [SCGMeasurement] {
        var seed = SeededRng(seed: 99)
        let dayOffsets: [Int] = [0, 2, 5, 7, 9, 12]
        return dayOffsets.map { daysAgo in
            let bpm = 62 + Int(seed.next() * 22)
            let hrv = 28.0 + seed.next() * 32.0
            let resp = 12.0 + seed.next() * 6.0
            let quality = 0.55 + Float(seed.next()) * 0.35
            let hour = 9 + Int(seed.next() * 8)
            let minute = Int(seed.next() * 60)
            // Rate-corrected ejection time around Weissler's expectation, with
            // small jitter — feeds the SCG-only BP model below.
            let lvet = BloodPressureEstimator.expectedLVET(hrBpm: Double(bpm)) + (seed.next() * 30 - 15)
            let ao = 12.0 + seed.next() * 14.0
            let bp = BloodPressureEstimator.estimate(
                lvetMs: lvet, hrBpm: bpm, signalQuality: Double(quality), beatCount: 10
            )
            return SCGMeasurement(
                id: UUID(),
                timestamp: date(daysAgo: daysAgo, hour: hour, minute: minute),
                heartRateBpm: bpm,
                hrvSdnnMs: hrv,
                respirationBpm: resp,
                lvetMs: lvet,
                aoAmplitudeMg: ao,
                estSystolicMmHg: bp?.systolicMmHg,
                estDiastolicMmHg: bp?.diastolicMmHg,
                signalQuality: quality
            )
        }
    }

    /// Fully seeded — no `Int.random` calls, so screenshots reproduce across
    /// installs. Minute is clamped because `bySettingHour` only accepts
    /// 0..59.
    private static func date(daysAgo: Int, hour: Int, minute: Int) -> Date {
        let cal = Calendar.current
        let base = cal.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return cal.date(bySettingHour: hour, minute: min(59, max(0, minute)), second: 0, of: base) ?? base
    }
}

/// Tiny linear-congruential RNG so the demo data is reproducible across
/// fresh installs without pulling in a heavier dependency. Returns values
/// in [0, 1).
private struct SeededRng {
    var state: UInt64
    init(seed: UInt64) { self.state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let bits = (state >> 33) & 0xFFFFFFFF
        return Double(bits) / Double(UInt32.max)
    }
}
