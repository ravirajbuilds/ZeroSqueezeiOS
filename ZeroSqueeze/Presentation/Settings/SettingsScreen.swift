import SwiftUI

/// Top-level Settings tab: edit profile (previously impossible after
/// onboarding), manage personal calibration, clear data, and read the
/// wellness disclaimer.
struct SettingsScreen: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: MeasurementStore
    @EnvironmentObject private var scgStore: SCGMeasurementStore
    @EnvironmentObject private var calibration: CalibrationStore
    @EnvironmentObject private var checkInStore: CheckInStore
    @Environment(\.zsPalette) private var palette

    @State private var showProfileEditor = false
    @State private var confirmClearHb = false
    @State private var confirmClearChest = false
    @State private var confirmClearJournal = false
    @State private var confirmClearCalibration = false
    @State private var confirmReset = false

    var body: some View {
        ZStack {
            palette.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: ZSSpacing.xl) {
                    profileCard
                    calibrationCard
                    dataCard
                    aboutCard
                }
                .padding(ZSSpacing.xl)
            }
        }
        .navigationTitle("Profile")
        .sheet(isPresented: $showProfileEditor) {
            // Fall back to a placeholder so the sheet is never empty if profile
            // is somehow nil (e.g. mid onboarding-reset).
            ProfileEditorSheet(profile: appState.profile ?? .placeholder) {
                appState.updateProfile($0)
            }
        }
    }

    // ── Profile ──────────────────────────────────────────────────────

    private var profileCard: some View {
        let profile = appState.profile ?? .placeholder
        return VStack(alignment: .leading, spacing: ZSSpacing.m) {
            Text("PROFILE").sectionLabel()
            row("Age", "\(profile.age)")
            row("Sex", profile.gender.label)
            row("Skin tone", profile.skinTone.map { "Monk \($0)" } ?? "Not set")
            Button {
                ZSHaptics.tap()
                showProfileEditor = true
            } label: {
                Text("Edit profile")
                    .font(ZSTypography.bodyEmphasized)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ZSSpacing.s)
            }
            .buttonStyle(.bordered)
            .tint(palette.accent)
            .padding(.top, ZSSpacing.xs)
        }
        .cardBackground(palette)
    }

    // ── Calibration ──────────────────────────────────────────────────

    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: ZSSpacing.m) {
            Text("HB CALIBRATION").sectionLabel()
            if calibration.points.isEmpty && !calibration.correction.isCalibrated {
                Text("Not calibrated. After a fingertip reading, enter a recent lab Hb value to anchor future estimates to you.")
                    .font(ZSTypography.caption)
                    .foregroundColor(palette.textSecondary)
            } else {
                let c = calibration.correction
                Text(String(format: "Correction: ×%.2f, %+.1f g/dL", c.slope, c.intercept))
                    .font(ZSTypography.body)
                    .foregroundColor(palette.textPrimary)
                Text("\(calibration.points.count) lab point\(calibration.points.count == 1 ? "" : "s") recorded.")
                    .font(ZSTypography.caption)
                    .foregroundColor(palette.textSecondary)
                ForEach(calibration.points) { p in
                    HStack {
                        Text(p.date.formatted(date: .abbreviated, time: .omitted))
                            .font(ZSTypography.caption)
                            .foregroundColor(palette.textSecondary)
                        Spacer()
                        Text(String(format: "lab %.1f · est %.1f", p.labHb, p.rawHb))
                            .font(ZSTypography.caption)
                            .foregroundColor(palette.textTertiary)
                    }
                }
                Button("Clear calibration", role: .destructive) { confirmClearCalibration = true }
                    .font(ZSTypography.body)
                    .padding(.top, ZSSpacing.xs)
            }
        }
        .cardBackground(palette)
        .confirmationDialog("Clear calibration?", isPresented: $confirmClearCalibration, titleVisibility: .visible) {
            Button("Clear calibration", role: .destructive) { calibration.clear() }
        } message: {
            Text("Future estimates revert to the population model.")
        }
    }

    // ── Data ─────────────────────────────────────────────────────────

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: ZSSpacing.m) {
            Text("DATA").sectionLabel()
            row("Hb readings", "\(store.measurements.count)")
            row("Chest scans", "\(scgStore.measurements.count)")
            row("Journal entries", "\(checkInStore.entries.count)")
            Button("Clear Hb history", role: .destructive) { confirmClearHb = true }
                .font(ZSTypography.body)
            Button("Clear chest history", role: .destructive) { confirmClearChest = true }
                .font(ZSTypography.body)
            Button("Clear journal", role: .destructive) { confirmClearJournal = true }
                .font(ZSTypography.body)
            Divider().background(palette.divider)
            Button("Restart onboarding", role: .destructive) { confirmReset = true }
                .font(ZSTypography.body)
        }
        .cardBackground(palette)
        .confirmationDialog("Clear Hb history?", isPresented: $confirmClearHb, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { store.clear() }
        }
        .confirmationDialog("Clear chest history?", isPresented: $confirmClearChest, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { scgStore.clear() }
        }
        .confirmationDialog("Clear journal?", isPresented: $confirmClearJournal, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { checkInStore.clear() }
        } message: {
            Text("Deletes all daily check-in entries.")
        }
        .confirmationDialog("Restart onboarding?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Restart", role: .destructive) { appState.resetProfile() }
        } message: {
            Text("Re-runs onboarding. Your saved readings and calibration are kept.")
        }
    }

    // ── About ────────────────────────────────────────────────────────

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: ZSSpacing.s) {
            Label("Wellness estimate, not a diagnosis", systemImage: "exclamationmark.triangle.fill")
                .font(ZSTypography.bodyEmphasized)
                .foregroundColor(palette.cautionYellow)
            Text("ZeroSqueeze estimates hemoglobin, heart rate, HRV and respiration from your phone's camera. All processing is on-device. Results are approximate — confirm anything concerning with a clinician.")
                .font(ZSTypography.caption)
                .foregroundColor(palette.textSecondary)
        }
        .cardBackground(palette, tinted: palette.cautionYellow)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(ZSTypography.body)
                .foregroundColor(palette.textSecondary)
            Spacer()
            Text(value)
                .font(ZSTypography.bodyEmphasized)
                .foregroundColor(palette.textPrimary)
        }
    }
}

private extension View {
    func cardBackground(_ palette: ZSPalette, tinted: Color? = nil) -> some View {
        self
            .padding(ZSSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((tinted ?? palette.surface).opacity(tinted == nil ? 1 : 0.08))
            .clipShape(ZSShapes.cardShape)
            .overlay(ZSShapes.cardShape.stroke((tinted ?? palette.border).opacity(tinted == nil ? 1 : 0.5), lineWidth: 0.5))
    }
}

/// Edit age / sex / skin tone after onboarding.
struct ProfileEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.zsPalette) private var palette

    @State private var age: Int
    @State private var gender: Gender
    @State private var skinTone: Int?
    let onSave: (UserProfile) -> Void

    init(profile: UserProfile, onSave: @escaping (UserProfile) -> Void) {
        _age = State(initialValue: profile.age)
        _gender = State(initialValue: profile.gender)
        _skinTone = State(initialValue: profile.skinTone)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: ZSSpacing.xl) {
                        VStack(alignment: .leading, spacing: ZSSpacing.s) {
                            Text("AGE").sectionLabel()
                            Stepper("\(age) years", value: $age, in: 5...110)
                                .tint(palette.accent)
                                .padding(ZSSpacing.standard)
                                .background(palette.surface)
                                .clipShape(ZSShapes.smallShape)
                        }
                        VStack(alignment: .leading, spacing: ZSSpacing.s) {
                            Text("SEX (FOR HB REFERENCE)").sectionLabel()
                            Picker("Sex", selection: $gender) {
                                ForEach(Gender.allCases, id: \.self) { g in
                                    Text(g.label).tag(g)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: ZSSpacing.s) {
                            Text("SKIN TONE").sectionLabel()
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ZSSpacing.s), count: 5), spacing: ZSSpacing.s) {
                                ForEach(MonkSkinTone.all, id: \.tone) { mst in
                                    Button {
                                        skinTone = (skinTone == mst.tone) ? nil : mst.tone
                                        ZSHaptics.selection()
                                    } label: {
                                        Circle()
                                            .fill(Color(hex: UInt32(mst.hex.dropFirst(), radix: 16) ?? 0))
                                            .frame(width: 40, height: 40)
                                            .overlay(
                                                Circle().stroke(
                                                    skinTone == mst.tone ? palette.accent : Color.clear,
                                                    lineWidth: 3
                                                )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Text(skinTone == nil ? "Not set — tap a tone, or leave unset." : "Tap the selected tone again to unset.")
                                .font(ZSTypography.captionTight)
                                .foregroundColor(palette.textTertiary)
                        }
                    }
                    .padding(ZSSpacing.xl)
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(UserProfile(age: age, gender: gender, skinTone: skinTone))
                        ZSHaptics.success()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
