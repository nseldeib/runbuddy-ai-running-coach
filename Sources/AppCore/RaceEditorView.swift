import SwiftUI

// Lightweight add/edit editor for a single race, presented as a sheet from the
// Settings Races card. Distance uses the same preset-capsules + custom-stepper
// pattern as the daily step goal. Reuses the app theme so it feels native.
struct RaceEditorView: View {
    let existing: RaceGoal?
    var onSave: (RaceGoal) -> Void
    var onCancel: () -> Void

    @State private var name: String
    @State private var distance: RaceDistance
    @State private var customMiles: Double
    @State private var date: Date
    @State private var location: String
    @State private var notes: String

    init(existing: RaceGoal?, onSave: @escaping (RaceGoal) -> Void, onCancel: @escaping () -> Void) {
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        let miles = existing?.distanceMiles ?? RaceDistance.half.miles
        _name = State(initialValue: existing?.name ?? "")
        _distance = State(initialValue: RaceDistance.preset(forMiles: miles))
        _customMiles = State(initialValue: RaceDistance.clampMiles(miles))
        _date = State(initialValue: Self.parseISO(existing?.date) ?? Date())
        _location = State(initialValue: existing?.location ?? "")
        _notes = State(initialValue: existing?.notes ?? "")
    }

    private var resolvedMiles: Double {
        distance == .custom ? RaceDistance.clampMiles(customMiles) : distance.miles
    }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bgTop, Palette.bgBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().opacity(0.4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        field("Race name") {
                            TextField("e.g. October Trail Half", text: $name).textFieldStyle(.roundedBorder)
                        }
                        field("Distance") {
                            distanceCapsules
                            if distance == .custom {
                                Stepper(value: $customMiles, in: RaceDistance.minMiles...RaceDistance.maxMiles, step: 0.1) {
                                    Text(String(format: "%.1f miles", customMiles))
                                        .font(Typography.captionStrong).foregroundColor(Palette.ink)
                                }
                                .accessibilityLabel("Custom race distance")
                            }
                        }
                        field("Date") {
                            DatePicker("", selection: $date, displayedComponents: .date)
                                .labelsHidden()
                        }
                        field("Location") {
                            TextField("City or venue", text: $location).textFieldStyle(.roundedBorder)
                        }
                        field("Notes (optional)") {
                            TextField("Corral, goal time, start area…", text: $notes).textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .font(Typography.headline).foregroundColor(Palette.subtle)
            Spacer()
            Text(existing == nil ? "Add race" : "Edit race")
                .font(Typography.title3).foregroundColor(Palette.ink)
            Spacer()
            Button("Save") {
                onSave(RaceGoal(
                    id: existing?.id ?? UUID(),
                    name: name.trimmingCharacters(in: .whitespaces),
                    distanceMiles: resolvedMiles,
                    date: Self.isoString(date),
                    location: location.trimmingCharacters(in: .whitespaces),
                    notes: notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes
                ))
            }
            .font(Typography.headline)
            .foregroundColor(canSave ? Palette.brandDeep : Palette.subtle)
            .disabled(!canSave)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var distanceCapsules: some View {
        HStack(spacing: 8) {
            ForEach(RaceDistance.allCases, id: \.self) { d in
                Button { distance = d } label: {
                    Text(d.label)
                        .font(Typography.captionStrong)
                        .foregroundColor(distance == d ? .white : Palette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(distance == d ? Palette.brand : Palette.ink.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(d.label)
                .accessibilityAddTraits(distance == d ? [.isSelected] : [])
            }
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(Typography.caption2).foregroundColor(Palette.subtle)
            content()
        }
    }

    // ISO yyyy-MM-dd <-> Date, UTC, matching RaceGoal.date / LatestWorkout.date.
    private static func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        return isoFormatter.date(from: s)
    }
    private static func isoString(_ d: Date) -> String { isoFormatter.string(from: d) }
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
