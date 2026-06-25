import SwiftUI

// Root of the Otterpace app. Reads the seeded `TodayState` at launch and shows
// either the day-one "Connect Apple Health" hero (production default) or the
// full Today dashboard once activity data is available.

public struct ContentView: View {
    @StateObject private var model = OtterpaceModel()
    @StateObject private var session = SessionStore()

    // Local movement reminders. Re-applied on scene-phase changes: foreground
    // (re)schedules the daily/goal reminders and clears the inactivity timer;
    // background arms it. No-ops unless the user enabled a reminder in Settings.
    @Environment(\.scenePhase) private var scenePhase
    private let reminderScheduler: MovementReminderScheduling = MovementReminderScheduler()

    // Scenario-only override: when a preview scenario seeds `rbPreviewMode`, the
    // app renders the Buddy style/loader showcase instead of the normal flow.
    private let previewMode = UserDefaults.standard.string(forKey: "rbPreviewMode") ?? ""

    // Which tab is selected at launch. Scenarios seed `rbStartTab="coach"` to land
    // directly on the Ask Coach chat; default (and production) opens on Today.
    @State private var tab: MainTab
    @State private var showSettings: Bool

    // Scenario-only override: a scenario can seed `rbContentSize` (e.g. "xxxl",
    // "accessibility3") to force a Dynamic Type size for the whole app, so the
    // large-text accessibility states render in a capture. Empty (production) =>
    // the system size is honored.
    private let contentSizeOverride = UserDefaults.standard.string(forKey: "rbContentSize") ?? ""

    public init() {
        let seeded = UserDefaults.standard.string(forKey: "rbStartTab") ?? ""
        _tab = State(initialValue: MainTab(raw: seeded))
        // Scenario hook: seed `rbShowSettings` to open Settings on the first frame.
        _showSettings = State(initialValue: UserDefaults.standard.bool(forKey: "rbShowSettings"))
    }

    /// Open the system Settings app so the user can grant Health access.
    private func openSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.bgTop, Palette.bgBottom],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            if !previewMode.isEmpty {
                BuddyPreviewHost(mode: previewMode)
            } else if session.state == .undecided {
                SignInView(session: session)
            } else if model.today.healthKitConnected {
                connectedTabs
            } else if model.healthAuth == .denied {
                HealthDeniedView(onOpenSettings: openSettings, onSettings: { showSettings = true })
            } else {
                ConnectHero(onConnect: { model.connect() }, onSettings: { showSettings = true })
            }

            // Settings presents as a full-cover overlay, reachable from the
            // dashboard and the Connect hero (so sign out / delete account is
            // always findable). Skipped on the Buddy preview host + sign-in screen.
            if showSettings && previewMode.isEmpty && session.state != .undecided {
                SettingsView(model: model, session: session, onClose: { showSettings = false })
                    .zIndex(2)
            }
        }
        .modifier(DynamicTypeOverride(raw: contentSizeOverride))
        // Light-only design: also pin the scheme here so SwiftUI previews and
        // isolated-component captures (which mount ContentView directly, not via
        // the App scene) render light too. The App scene sets this as well.
        .preferredColorScheme(.light)
        .onAppear { if previewMode.isEmpty { Analytics.shared.capture("app_opened") } }
        .onChange(of: scenePhase) { phase in
            // Never schedule during a preview/scenario capture.
            guard previewMode.isEmpty else { return }
            let settings = ReminderSettings.load()
            switch phase {
            case .active:     reminderScheduler.applyForeground(settings)
            case .background: reminderScheduler.applyBackground(settings)
            default:          break
            }
        }
    }

    // Today + Ask Coach behind a bottom tab bar. The Coach card on Today also
    // jumps here by flipping `tab` to `.coach`.
    private var connectedTabs: some View {
        TabView(selection: $tab) {
            TodayDashboard(model: model, onAskCoach: { tab = .coach }, onSettings: { showSettings = true })
                .tag(MainTab.today)
                .tabItem { Label("Today", systemImage: "sun.max.fill") }

            AskCoachView(model: model)
                .tag(MainTab.coach)
                .tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right.fill") }
        }
        .tint(Palette.brand)
    }
}

// Applies a scenario-seeded Dynamic Type size to the whole app when `rbContentSize`
// is set, so accessibility text-size states are capturable; a no-op otherwise.
struct DynamicTypeOverride: ViewModifier {
    let raw: String

    func body(content: Content) -> some View {
        if let size = dynamicTypeSize(forSeed: raw) { content.dynamicTypeSize(size) } else { content }
    }
}

/// Map a scenario-seeded `rbContentSize` string to a `DynamicTypeSize`. Pure and
/// case-insensitive; an empty or unrecognized value returns nil (honor the system
/// size). Kept free of view code so it's unit-testable.
public func dynamicTypeSize(forSeed raw: String) -> DynamicTypeSize? {
    switch raw.lowercased() {
    case "xs", "xsmall":         return .xSmall
    case "s", "small":           return .small
    case "m", "medium":          return .medium
    case "l", "large":           return .large
    case "xl", "xlarge":         return .xLarge
    case "xxl", "xxlarge":       return .xxLarge
    case "xxxl", "xxxlarge":     return .xxxLarge
    case "a1", "accessibility1": return .accessibility1
    case "a2", "accessibility2": return .accessibility2
    case "a3", "accessibility3": return .accessibility3
    case "a4", "accessibility4": return .accessibility4
    case "a5", "accessibility5": return .accessibility5
    default:                     return nil
    }
}

// The app's two top-level destinations.
public enum MainTab: String, Hashable {
    case today, coach

    public init(raw: String) {
        self = MainTab(rawValue: raw.lowercased()) ?? .today
    }
}
