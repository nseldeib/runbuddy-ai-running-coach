import SwiftUI

// MARK: - Settings
//
// Reached via the gear on the Today dashboard and the Connect hero (so it's
// available signed-in-but-not-connected too). Sections: Account (sign out / delete
// account — the App Store-required account-deletion path), Health access, the
// editable daily step goal, a privacy explainer + policy link, and About.
public struct SettingsView: View {
    @ObservedObject var model: OtterpaceModel
    @ObservedObject var session: SessionStore
    var onClose: () -> Void

    @State private var confirmDelete = false

    // BYO Anthropic key for the real AI coach (stored on-device via the Keychain).
    private let coachKeys = CoachKeyStore()
    @State private var coachConnected = false
    @State private var coachKeyDraft = ""

    // Local movement reminders.
    private let reminderScheduler: MovementReminderScheduling = MovementReminderScheduler()
    @State private var reminders = ReminderSettings()
    @State private var notifAuthorized = false

    public init(model: OtterpaceModel, session: SessionStore, onClose: @escaping () -> Void = {}) {
        self.model = model
        self.session = session
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bgTop, Palette.bgBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().opacity(0.4)
                ScrollView {
                    VStack(spacing: 16) {
                        accountCard
                        healthCard
                        coachCard
                        remindersCard
                        goalCard
                        privacyCard
                        aboutCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
            }
        }
        .onAppear {
            coachConnected = coachKeys.isConnected
            reminders = ReminderSettings.load()
            Task { notifAuthorized = await reminderScheduler.isAuthorized() }
        }
        .alert("Delete account?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { session.deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your sign-in from this device. Your Health data is never stored by Otterpace, so nothing else is deleted.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            PuffyBuddy(mood: .ready, size: 34)
            Text("Settings")
                .font(Typography.title3)
                .foregroundColor(Palette.ink)
            Spacer()
            Button(action: onClose) {
                Text("Done").font(Typography.headline).foregroundColor(Palette.brandDeep)
            }
            .accessibilityLabel("Close settings")
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    // MARK: Account

    @ViewBuilder private var accountCard: some View {
        card("Account") {
            switch session.state {
            case .signedIn:
                row(icon: "applelogo", tint: Palette.ink, title: "Signed in with Apple")
                actionRow("Sign out", icon: "rectangle.portrait.and.arrow.right", tint: Palette.sky) {
                    session.signOut()
                }
                actionRow("Delete account", icon: "trash", tint: Palette.brandDeep, destructive: true) {
                    confirmDelete = true
                }
            case .guest, .undecided:
                row(icon: "person.crop.circle", tint: Palette.subtle, title: "Using Otterpace as a guest")
                actionRow("Sign in with Apple", icon: "applelogo", tint: Palette.ink) {
                    session.presentSignIn()
                }
            }
        }
    }

    // MARK: Health

    @ViewBuilder private var healthCard: some View {
        card("Apple Health") {
            switch model.healthAuth {
            case .authorized:
                row(icon: "heart.fill", tint: Palette.go, title: "Connected", detail: "Reading your steps on this device")
            case .denied:
                row(icon: "heart.slash", tint: Palette.amber, title: "Access is off")
                actionRow("Open Settings", icon: "gear", tint: Palette.brand) { openSystemSettings() }
            case .notDetermined, .unavailable:
                row(icon: "heart", tint: Palette.subtle, title: "Not connected")
                actionRow("Connect Apple Health", icon: "heart.fill", tint: Palette.brand) { model.connect() }
            }
        }
    }

    // MARK: AI Coach (BYO key)

    @ViewBuilder private var coachCard: some View {
        card("AI Coach") {
            if coachConnected {
                row(icon: "sparkles", tint: Palette.brand, title: "Connected",
                    detail: "Replies are generated by Claude, using your key")
                actionRow("Disconnect", icon: "xmark.circle", tint: Palette.brandDeep, destructive: true) {
                    coachKeys.clear()
                    coachConnected = false
                    coachKeyDraft = ""
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connect your own Anthropic API key for real AI coaching. Without one, Buddy still coaches you with built-in guidance. Your key is stored only on this device and sent over HTTPS to power replies — it's never saved on a server.")
                        .font(Typography.callout).foregroundColor(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    SecureField("sk-ant-…", text: $coachKeyDraft)
                        .textFieldStyle(.roundedBorder)
                    actionRow("Connect", icon: "sparkles", tint: Palette.brand) {
                        let key = coachKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !key.isEmpty else { return }
                        coachKeys.save(key)
                        coachConnected = true
                        coachKeyDraft = ""
                    }
                    if let url = URL(string: "https://console.anthropic.com/settings/keys") {
                        Link(destination: url) {
                            actionRowLabel("Get an API key", icon: "key", tint: Palette.sky, external: true)
                        }
                        .accessibilityLabel("Get an Anthropic API key")
                    }
                }
            }
        }
    }

    // MARK: Movement reminders

    @ViewBuilder private var remindersCard: some View {
        card("Reminders") {
            VStack(alignment: .leading, spacing: 12) {
                reminderToggle("Daily reminder", isOn: reminders.dailyEnabled) { on in
                    reminders.dailyEnabled = on; commitReminders(enabling: on)
                }
                if reminders.dailyEnabled {
                    DatePicker("Time", selection: dailyTimeBinding, displayedComponents: .hourAndMinute)
                        .font(Typography.callout)
                }
                Divider().opacity(0.3)
                reminderToggle("Evening goal nudge", isOn: reminders.goalEnabled) { on in
                    reminders.goalEnabled = on; commitReminders(enabling: on)
                }
                Divider().opacity(0.3)
                reminderToggle("Inactivity nudge", isOn: reminders.inactivityEnabled) { on in
                    reminders.inactivityEnabled = on; commitReminders(enabling: on)
                }
                if reminders.inactivityEnabled {
                    Picker("After", selection: inactivityHoursBinding) {
                        ForEach(ReminderSettings.inactivityOptions, id: \.self) { Text("\($0)h").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if reminders.anyEnabled && !notifAuthorized {
                    Text("Allow notifications in iOS Settings to receive these.")
                        .font(Typography.caption).foregroundColor(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func reminderToggle(_ title: String, isOn: Bool, _ change: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: change)) {
            Text(title).font(Typography.body).foregroundColor(Palette.ink)
        }
        .tint(Palette.brand)
    }

    private var dailyTimeBinding: Binding<Date> {
        Binding(
            get: {
                var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                c.hour = reminders.dailyHour; c.minute = reminders.dailyMinute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                reminders.dailyHour = c.hour ?? ReminderSettings.defaultDailyHour
                reminders.dailyMinute = c.minute ?? 0
                commitReminders(enabling: false)
            }
        )
    }

    private var inactivityHoursBinding: Binding<Int> {
        Binding(get: { reminders.inactivityHours },
                set: { reminders.inactivityHours = $0; commitReminders(enabling: false) })
    }

    /// Persist the reminder prefs and (re)apply them. When the user is turning a
    /// reminder ON and we don't yet have permission, ask for it first.
    private func commitReminders(enabling: Bool) {
        reminders.save()
        if enabling && !notifAuthorized {
            Task { @MainActor in
                notifAuthorized = await reminderScheduler.requestAuthorization()
                reminderScheduler.applyForeground(reminders)
            }
        } else {
            reminderScheduler.applyForeground(reminders)
        }
    }

    // MARK: Daily goal

    @ViewBuilder private var goalCard: some View {
        card("Daily step goal") {
            HStack(spacing: 8) {
                ForEach(UserPreferences.goalOptions, id: \.self) { goal in
                    let selected = model.today.goalSteps == goal
                    Button { model.setGoalSteps(goal) } label: {
                        Text("\(goal / 1000)k")
                            .font(Typography.captionStrong)
                            .foregroundColor(selected ? .white : Palette.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(selected ? Palette.brand : Palette.ink.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(goal) steps")
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
        }
    }

    // MARK: Privacy

    @ViewBuilder private var privacyCard: some View {
        card("Privacy") {
            VStack(alignment: .leading, spacing: 8) {
                Text("What Buddy uses")
                    .font(Typography.captionStrong).foregroundColor(Palette.subtle)
                Text("Otterpace reads your steps, distance, and active energy from Apple Health, and uses them on your device to coach you. Your health data never leaves your device and is never sent to a server.")
                    .font(Typography.callout).foregroundColor(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = URL(string: "https://otterpace.com/privacy") {
                Link(destination: url) {
                    actionRowLabel("Privacy policy", icon: "lock.shield", tint: Palette.sky, external: true)
                }
                .accessibilityLabel("Open the privacy policy")
            }
        }
    }

    // MARK: About

    @ViewBuilder private var aboutCard: some View {
        card("About") {
            row(icon: "pawprint.fill", tint: Palette.brand, title: "Otterpace", detail: "Version \(appVersion)")
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    // MARK: Building blocks

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(Typography.caption2).foregroundColor(Palette.subtle)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardStyle()
    }

    private func row(icon: String, tint: Color, title: String, detail: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typography.body).foregroundColor(Palette.ink)
                if let detail { Text(detail).font(Typography.caption).foregroundColor(Palette.subtle) }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func actionRow(_ title: String, icon: String, tint: Color, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionRowLabel(title, icon: icon, tint: tint, destructive: destructive) }
            .buttonStyle(.plain)
    }

    private func actionRowLabel(_ title: String, icon: String, tint: Color, destructive: Bool = false, external: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(tint).frame(width: 24)
            Text(title).font(Typography.headline).foregroundColor(destructive ? Palette.brandDeep : Palette.ink)
            Spacer()
            Image(systemName: external ? "arrow.up.right" : "chevron.right")
                .font(.system(size: 13, weight: .bold)).foregroundColor(Palette.subtle)
        }
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #endif
    }
}
