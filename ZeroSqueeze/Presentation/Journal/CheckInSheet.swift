import SwiftUI

/// Sheet for logging (or editing) today's wellbeing check-in: mood, energy,
/// optional symptoms and a note. Saves one entry per day via `CheckInStore`.
struct CheckInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.zsPalette) private var palette

    /// The day this entry describes (defaults to today).
    let day: Date
    let existing: CheckIn?
    let onSave: (CheckIn) -> Void

    @State private var mood: Int
    @State private var energy: Int
    @State private var symptoms: Set<String>
    @State private var note: String

    init(day: Date, existing: CheckIn?, onSave: @escaping (CheckIn) -> Void) {
        self.day = day
        self.existing = existing
        self.onSave = onSave
        _mood = State(initialValue: existing?.mood ?? 3)
        _energy = State(initialValue: existing?.energy ?? 3)
        _symptoms = State(initialValue: Set(existing?.symptoms ?? []))
        _note = State(initialValue: existing?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: ZSSpacing.xl) {
                        scale(
                            title: "MOOD",
                            value: $mood,
                            label: CheckIn.moodLabel(mood),
                            emoji: CheckIn.moodEmoji(mood),
                            tint: palette.accent
                        )
                        scale(
                            title: "ENERGY",
                            value: $energy,
                            label: CheckIn.energyLabel(energy),
                            emoji: nil,
                            tint: palette.hrvColor
                        )
                        symptomGrid
                        noteField
                    }
                    .padding(ZSSpacing.xl)
                }
            }
            .navigationTitle(existing == nil ? "Daily check-in" : "Edit check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func scale(title: String, value: Binding<Int>, label: String, emoji: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: ZSSpacing.s) {
            HStack {
                Text(title).sectionLabel()
                Spacer()
                Text("\(emoji.map { $0 + " " } ?? "")\(label)")
                    .font(ZSTypography.bodyEmphasized)
                    .foregroundColor(palette.textPrimary)
            }
            HStack(spacing: ZSSpacing.s) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        value.wrappedValue = i
                        ZSHaptics.selection()
                    } label: {
                        Circle()
                            .fill(i <= value.wrappedValue ? tint : palette.surface)
                            .overlay(Circle().stroke(palette.border, lineWidth: 0.5))
                            .frame(height: 40)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var symptomGrid: some View {
        VStack(alignment: .leading, spacing: ZSSpacing.s) {
            Text("ANYTHING TODAY?").sectionLabel()
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: ZSSpacing.s), count: 2),
                spacing: ZSSpacing.s
            ) {
                ForEach(CheckIn.symptomOptions, id: \.self) { s in
                    let on = symptoms.contains(s)
                    Button {
                        if on { symptoms.remove(s) } else { symptoms.insert(s) }
                        ZSHaptics.selection()
                    } label: {
                        Text(s)
                            .font(ZSTypography.caption)
                            .foregroundColor(on ? (palette.isDark ? .black : .white) : palette.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, ZSSpacing.s)
                            .background(on ? palette.accent : palette.surface)
                            .clipShape(ZSShapes.pill)
                            .overlay(ZSShapes.pill.stroke(palette.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: ZSSpacing.s) {
            Text("NOTE").sectionLabel()
            TextField("Optional — anything worth remembering", text: $note, axis: .vertical)
                .lineLimit(3...6)
                .font(ZSTypography.body)
                .foregroundColor(palette.textPrimary)
                .padding(ZSSpacing.standard)
                .background(palette.surface)
                .clipShape(ZSShapes.smallShape)
                .overlay(ZSShapes.smallShape.stroke(palette.border, lineWidth: 0.5))
        }
    }

    private func save() {
        let entry = CheckIn(
            id: existing?.id ?? UUID(),
            day: Calendar.current.startOfDay(for: day),
            timestamp: Date(),
            mood: mood,
            energy: energy,
            symptoms: CheckIn.symptomOptions.filter { symptoms.contains($0) },
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        onSave(entry)
        ZSHaptics.success()
        dismiss()
    }
}
