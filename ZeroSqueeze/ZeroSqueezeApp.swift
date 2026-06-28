import SwiftUI

@main
struct ZeroSqueezeApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var store = MeasurementStore.shared
    @StateObject private var scgStore = SCGMeasurementStore.shared
    @StateObject private var calibrationStore = CalibrationStore.shared
    @StateObject private var checkInStore = CheckInStore.shared
    @StateObject private var heartCheckStore = HeartCheckStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(store)
                .environmentObject(scgStore)
                .environmentObject(calibrationStore)
                .environmentObject(checkInStore)
                .environmentObject(heartCheckStore)
                .zsTheme()
                .preferredColorScheme(.dark)
                // Cap only the upper bound at `.accessibility2` — the dark
                // gradient + 52pt hero number get cramped beyond that. Leave
                // the lower bound open so users on `.xSmall` / `.small` aren't
                // force-upsized; that violated their accessibility setting.
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var profile: UserProfile?

    private let profileStore: ProfileStore
    private let calibrationStore: CalibrationStore

    init(profileStore: ProfileStore = .shared, calibrationStore: CalibrationStore = .shared) {
        self.profileStore = profileStore
        self.calibrationStore = calibrationStore
        self.profile = profileStore.load()
        // v1 stored a single calibration offset on the profile; carry it
        // into the multi-point CalibrationStore so the anchor survives.
        // Clear the profile copy afterwards — leaving it would resurrect
        // the offset on next launch if the user clears their calibration.
        if let legacy = self.profile?.hbCalibrationOffset {
            calibrationStore.migrateLegacyOffset(legacy)
            self.profile?.hbCalibrationOffset = nil
            if let migrated = self.profile { profileStore.save(migrated) }
        }
        // Populate 14 days of plausible Hb + scg-scan history on a fresh
        // install so first-run users see a working History/Trend view
        // instead of an empty state. Idempotent — short-circuits if either
        // store already has data.
        DemoSeeder.seedIfEmpty(profile: self.profile ?? .placeholder)
    }

    var onboardingCompleted: Bool { profile != nil }

    func completeOnboarding(_ profile: UserProfile) {
        self.profile = profile
        profileStore.save(profile)
    }

    /// Persist an edited profile (Settings). Preserves any migrated legacy
    /// offset already cleared at launch — the multi-point store owns
    /// calibration now.
    func updateProfile(_ profile: UserProfile) {
        self.profile = profile
        profileStore.save(profile)
    }

    /// Record a lab-verified Hb against the *raw* (pre-correction) estimate
    /// and refit the personal correction line. Raw pairing means refits
    /// never compound earlier corrections.
    func calibrate(labHb: Float, rawEstimate: Float) {
        calibrationStore.add(labHb: labHb, rawHb: rawEstimate)
    }

    /// Re-run onboarding without discarding data. "Restart onboarding" keeps
    /// saved readings (see Settings copy), so it treats this as the same
    /// person re-onboarding on the same device — calibration and history both
    /// survive. (A true "new person / erase" is the separate Clear actions.)
    func resetProfile() {
        profile = nil
        profileStore.clear()
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if state.onboardingCompleted {
            RootTabView()
        } else {
            OnboardingScreen { profile in
                state.completeOnboarding(profile)
            }
        }
    }
}

/// Four-tab shell. Today (readiness + check-in + snapshot), Scan (capture
/// hub), Insights (trends + journal + report), Profile (settings).
struct RootTabView: View {
    @Environment(\.zsPalette) private var palette

    var body: some View {
        TabView {
            TodayScreen()
                .tabItem { Label("Today", systemImage: "house.fill") }
            NavigationStack { ScanScreen() }
                .tabItem { Label("Scan", systemImage: "camera.viewfinder") }
            NavigationStack { HistoryScreen() }
                .tabItem { Label("Insights", systemImage: "chart.xyaxis.line") }
            NavigationStack { SettingsScreen() }
                .tabItem { Label("Profile", systemImage: "person.fill") }
        }
        .tint(palette.accent)
    }
}
