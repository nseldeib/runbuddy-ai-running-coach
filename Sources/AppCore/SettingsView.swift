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
    var onReplayTour: () -> Void = {}

    @State private var confirmDelete = false

    // Optional account-backed sync (signed-in only). Two independent opt-ins:
    // settings, and (off by default, consent-gated) health/activity data.
    private let consent = SyncConsentStore()
    private let accountSync = AccountSyncService()
    private let accountSession = AccountSessionService()
    @State private var settingsSyncOn = false
    @State private var healthSyncOn = false
    @State private var showHealthConsent = false
    @State private var confirmHealthOff = false

    // BYO Anthropic key for the real AI coach (stored on-device via the Keychain).
    private let coachKeys = CoachKeyStore()
    @State private var coachConnected = false
    @State private var coachKeyDraft = ""

    // Local movement reminders.
    private let reminderScheduler: MovementReminderScheduling = MovementReminderScheduler()
    @State private var reminders = ReminderSettings()
    @State private var notifAuthorized = false

    // Optional Strava import.
    @StateObject private var strava = StravaService()

    // Custom (non-preset) step goal editor.
    @State private var customGoalExpanded = false
    @State private var customGoalDraft = UserPreferences.defaultGoal

    // Race goals add/edit editor (sheet). `editingRace == nil` => adding.
    @State private var showRaceEditor = false
    @State private var editingRace: RaceGoal?

    public init(model: OtterpaceModel, session: SessionStore, onClose: @escaping () -> Void = {},
                onReplayTour: @escaping () -> Void = {}) {
        self.model = model
        self.session = session
        self.onClose = onClose
        self.onReplayTour = onReplayTour
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
                        if strava.isConfigured { stravaCard }
                        coachCard
                        racesCard
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
            consent.applySeededPreviewIfPresent()
            settingsSyncOn = consent.settingsSyncEnabled
            healthSyncOn = consent.healthSyncEnabled
            // A returning custom-goal user lands with the editor already open.
            customGoalExpanded = !UserPreferences.isPreset(model.today.goalSteps)
            customGoalDraft = model.today.goalSteps
            Task { notifAuthorized = await reminderScheduler.isAuthorized() }
        }
        .alert("Delete account?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                // Delete synced data with the bearer still valid, THEN revoke it.
                Task {
                    await accountSync.purgeOnAccountDeletion(session: session.state)
                    await accountSession.revoke()
                }
                session.deleteAccount()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your sign-in from this device and deletes any data synced to your account. Health data is only ever synced if you turned it on.")
        }
        .sheet(isPresented: $showHealthConsent) { healthConsentSheet }
        .sheet(isPresented: $showRaceEditor) {
            RaceEditorView(
                existing: editingRace,
                onSave: { race in
                    if editingRace == nil { model.addRace(race) } else { model.updateRace(race) }
                    Analytics.shared.capture("race_added")
                    showRaceEditor = false
                },
                onCancel: { showRaceEditor = false }
            )
        }
        .confirmationDialog("Turn off health sync?", isPresented: $confirmHealthOff, titleVisibility: .visible) {
            Button("Turn off & delete synced data", role: .destructive) {
                healthSyncOn = false
                Task { await accountSync.disableHealthSync(deleteRemote: true, session: session.state) }
            }
            Button("Turn off, keep synced data") {
                healthSyncOn = false
                Task { await accountSync.disableHealthSync(deleteRemote: false, session: session.state) }
            }
            Button("Cancel", role: .cancel) { healthSyncOn = true }
        } message: {
            Text("Stop syncing your health & activity data to your account. You can also delete what's already been uploaded.")
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
                syncSection
                actionRow("Sign out", icon: "rectangle.portrait.and.arrow.right", tint: Palette.sky) {
                    Task { await accountSession.revoke() }   // drop the backend bearer too
                    session.signOut()
                }
                actionRow("Delete account", icon: "trash", tint: Palette.brandDeep, destructive: true) {
                    confirmDelete = true
                }
            case .guest, .undecided:
                row(icon: "person.crop.circle", tint: Palette.subtle, title: "Using Otterpace as a guest")
                Text("Sign in to sync your settings across devices. Health data stays on-device unless you turn it on.")
                    .font(Typography.caption).foregroundColor(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                actionRow("Sign in with Apple", icon: "applelogo", tint: Palette.ink) {
                    session.presentSignIn()
                }
            }
        }
    }

    // The two independent sync opt-ins, shown only when signed in. Settings sync
    // is a light toggle; health sync is off by default and routes through a
    // consent sheet on enable and a delete-or-keep choice on disable.
    @ViewBuilder private var syncSection: some View {
        Divider().opacity(0.3)
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: settingsSyncBinding) {
                Text("Sync my settings").font(Typography.body).foregroundColor(Palette.ink)
            }
            .tint(Palette.brand)
            Text(settingsSyncOn ? "On — your step goal & preferences sync to your account."
                                : "Off — settings stay on this device.")
                .font(Typography.caption).foregroundColor(Palette.subtle)
                .fixedSize(horizontal: false, vertical: true)
        }
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: healthSyncBinding) {
                Text("Sync my health & activity data").font(Typography.body).foregroundColor(Palette.ink)
            }
            .tint(Palette.brand)
            Text(healthSyncOn ? "On — your activity snapshot syncs to your account. You can turn this off and delete it anytime."
                              : "Off (private) — your health data stays on this device.")
                .font(Typography.caption).foregroundColor(healthSyncOn ? Palette.subtle : Palette.go)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var settingsSyncBinding: Binding<Bool> {
        Binding(get: { settingsSyncOn }, set: { on in
            settingsSyncOn = on
            consent.setSettingsSyncEnabled(on)
            if on {
                Task { await accountSync.pushPreferences(SyncablePreferences(goalSteps: model.today.goalSteps),
                                                         session: session.state) }
            }
        })
    }

    private var healthSyncBinding: Binding<Bool> {
        Binding(get: { healthSyncOn }, set: { on in
            if on {
                // Enabling requires the one-time consent moment first.
                if consent.healthConsentAcknowledged {
                    enableHealthSync()
                } else {
                    showHealthConsent = true   // sheet decides; toggle flips on accept
                }
            } else {
                confirmHealthOff = true        // dialog decides delete-or-keep
            }
        })
    }

    private func enableHealthSync() {
        consent.acknowledgeHealthConsent()
        consent.setHealthSyncEnabled(true)
        healthSyncOn = true
        let snapshot = SyncableHealthSnapshot(
            steps: model.today.steps,
            distanceMiles: model.today.distanceMiles,
            activeMinutes: model.today.activeMinutes,
            activeEnergyKcal: model.today.activeEnergyKcal
        )
        Task { await accountSync.pushHealth(snapshot, session: session.state) }
    }

    // One-time explainer shown before the first health upload: what's uploaded,
    // where it goes, and that it's reversible + deletable.
    @ViewBuilder private var healthConsentSheet: some View {
        ZStack {
            LinearGradient(colors: [Palette.bgTop, Palette.bgBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    PuffyBuddy(mood: .ready, size: 34)
                    Text("Sync health data?").font(Typography.title3).foregroundColor(Palette.ink)
                }
                Text("If you turn this on, a snapshot of your activity — steps, distance, active minutes and energy — is uploaded to your Otterpace account, tied to your Apple sign-in, so it follows you across devices.")
                    .font(Typography.callout).foregroundColor(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("It's stored privately on Otterpace's backend, never sold or sent to analytics, and you can turn it off and delete it at any time.")
                    .font(Typography.callout).foregroundColor(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                actionRow("Turn on & sync", icon: "checkmark.seal.fill", tint: Palette.brand) {
                    enableHealthSync()
                    showHealthConsent = false
                }
                actionRow("Not now", icon: "xmark", tint: Palette.subtle) {
                    healthSyncOn = false
                    showHealthConsent = false
                }
            }
            .padding(24)
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

    // MARK: Strava (optional import)

    @ViewBuilder private var stravaCard: some View {
        card("Strava") {
            if strava.isConnected {
                row(icon: "bolt.fill", tint: Palette.go, title: "Connected", detail: "Importing your activities")
                if strava.lastError != nil {
                    actionRow(strava.isWorking ? "Retrying…" : "Retry import", icon: "arrow.clockwise", tint: Palette.brand) {
                        Task { await retryStravaImport() }
                    }
                }
                actionRow("Disconnect", icon: "xmark.circle", tint: Palette.brandDeep, destructive: true) {
                    Task { await strava.disconnect() }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect Strava to import your runs and rides as an alternative to Apple Health.")
                        .font(Typography.callout).foregroundColor(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    actionRow(strava.isWorking ? "Connecting…" : "Connect Strava", icon: "bolt.fill", tint: Palette.brand) {
                        Task {
                            await strava.connect()
                            guard strava.isConnected else { return }
                            Analytics.shared.capture("strava_connected")
                            do {
                                model.ingestStravaWorkouts(try await strava.fetchActivities())
                            } catch {
                                // Connected, but the first import failed — surface it
                                // (with a Retry import action) instead of silently
                                // landing on an empty dashboard.
                                strava.lastError = "Connected to Strava, but importing your activities failed. Tap Retry import to try again."
                            }
                        }
                    }
                }
            }
            if let err = strava.lastError {
                Text(err).font(Typography.caption).foregroundColor(Palette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Retry a failed Strava import (shown only when connected with a lastError).
    private func retryStravaImport() async {
        strava.isWorking = true
        strava.lastError = nil
        defer { strava.isWorking = false }
        do {
            model.ingestStravaWorkouts(try await strava.fetchActivities())
        } catch {
            strava.lastError = "Importing your activities failed again. Please try again later."
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

    // MARK: Races (optional, feed the coach)

    @ViewBuilder private var racesCard: some View {
        card("Races") {
            if model.today.races.isEmpty {
                Text("Add a race and Buddy will tailor your coaching — building toward it, then easing off as it nears.")
                    .font(Typography.callout).foregroundColor(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                actionRow("Add a race", icon: "flag.checkered", tint: Palette.brand) {
                    editingRace = nil; showRaceEditor = true
                }
            } else {
                ForEach(model.today.races.sorted { $0.date < $1.date }) { race in
                    raceRow(race)
                }
                actionRow("Add a race", icon: "plus.circle", tint: Palette.brand) {
                    editingRace = nil; showRaceEditor = true
                }
            }
        }
    }

    private func raceRow(_ race: RaceGoal) -> some View {
        let past = race.date < todayISO
        let detail = "\(raceMiles(race.distanceMiles)) mi · \(prettyDate(race.date))"
            + (race.location.isEmpty ? "" : " · \(race.location)")
        return HStack(spacing: 12) {
            Image(systemName: "flag.checkered")
                .foregroundColor(past ? Palette.subtle : Palette.brand).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(race.name).font(Typography.body).foregroundColor(Palette.ink)
                Text(detail).font(Typography.caption).foregroundColor(Palette.subtle).lineLimit(1)
            }
            Spacer()
            Button { editingRace = race; showRaceEditor = true } label: {
                Image(systemName: "pencil").foregroundColor(Palette.sky).padding(6)
            }
            .accessibilityLabel("Edit \(race.name)")
            Button { model.removeRace(id: race.id) } label: {
                Image(systemName: "trash").foregroundColor(Palette.brandDeep).padding(6)
            }
            .accessibilityLabel("Delete \(race.name)")
        }
        .opacity(past ? 0.55 : 1)
    }

    private func raceMiles(_ d: Double) -> String {
        d == d.rounded() ? "\(Int(d))" : String(format: "%.1f", d)
    }

    private var todayISO: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
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
        let customActive = !UserPreferences.isPreset(model.today.goalSteps)
        card("Daily step goal") {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(UserPreferences.goalOptions, id: \.self) { goal in
                        goalCapsule(label: "\(goal / 1000)k",
                                    selected: model.today.goalSteps == goal,
                                    a11y: "\(goal) steps") {
                            customGoalExpanded = false
                            setGoal(goal)
                        }
                    }
                    goalCapsule(label: customActive ? "\(model.today.goalSteps / 1000)k" : "Custom",
                                selected: customActive,
                                a11y: "Custom step goal") {
                        customGoalDraft = UserPreferences.clampGoal(model.today.goalSteps)
                        customGoalExpanded.toggle()
                    }
                }
                if customGoalExpanded {
                    Stepper(value: $customGoalDraft,
                            in: UserPreferences.minGoal...UserPreferences.maxGoal,
                            step: UserPreferences.goalIncrement) {
                        Text("\(formatted(customGoalDraft)) steps")
                            .font(Typography.captionStrong)
                            .foregroundColor(Palette.ink)
                    }
                    .onChange(of: customGoalDraft) { newValue in
                        setGoal(UserPreferences.clampGoal(newValue))
                    }
                    .accessibilityLabel("Custom step goal")
                }
            }
        }
    }

    @ViewBuilder
    private func goalCapsule(label: String, selected: Bool, a11y: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Typography.captionStrong)
                .foregroundColor(selected ? .white : Palette.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Capsule().fill(selected ? Palette.brand : Palette.ink.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11y)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Apply a new step goal locally, then push it to the account if settings
    /// sync is on (a no-op for guests / sync-off — the local value is authoritative).
    private func setGoal(_ goal: Int) {
        model.setGoalSteps(goal)
        guard settingsSyncOn else { return }
        Task { await accountSync.pushPreferences(SyncablePreferences(goalSteps: goal), session: session.state) }
    }

    // MARK: Privacy

    @ViewBuilder private var privacyCard: some View {
        card("Privacy") {
            VStack(alignment: .leading, spacing: 8) {
                Text("What Buddy uses")
                    .font(Typography.captionStrong).foregroundColor(Palette.subtle)
                Text("Otterpace reads your steps, distance, and active energy from Apple Health, and uses them on your device to coach you. Your health data stays on your device by default — it's only synced to your account if you turn on health sync, and it's never sent to analytics.")
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
            actionRow("Show welcome tour again", icon: "sparkles", tint: Palette.sky) { onReplayTour() }
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
