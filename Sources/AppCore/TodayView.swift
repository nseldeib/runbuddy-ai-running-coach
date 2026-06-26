import SwiftUI

// MARK: - Today dashboard
//
// The full Today surface, composed purely from section components: header,
// Buddy + step ring, quick stats, and the AI coach / latest activity / weekly
// load cards. Each section lives in its own file; this view only arranges them.
public struct TodayDashboard: View {
    @ObservedObject var model: OtterpaceModel
    var onAskCoach: () -> Void
    var onSettings: () -> Void

    // Activity History presents as a full-cover overlay (cross-platform; a
    // SwiftUI `fullScreenCover` is unavailable on macOS). Initialized from the
    // scenario seed in `init` so a launch-seeded capture renders it on the first
    // frame, never mid-transition — same pattern as the Weekly Review overlay.
    @State private var showHistory: Bool
    @State private var racePromptDismissed: Bool

    // Scenario seed: force the "add a race" banner visible for capture even when a
    // scenario would otherwise hide it.
    private let forceRacePrompt = UserDefaults.standard.bool(forKey: "rbShowRacePrompt")

    public init(model: OtterpaceModel, onAskCoach: @escaping () -> Void = {}, onSettings: @escaping () -> Void = {}) {
        self.model = model
        self.onAskCoach = onAskCoach
        self.onSettings = onSettings
        _showHistory = State(initialValue: UserDefaults.standard.bool(forKey: "rbShowHistory"))
        _racePromptDismissed = State(initialValue: RacePromptState.isDismissed())
    }

    // Show the race prompt only when no races are set and it hasn't been dismissed
    // (or when a scenario forces it).
    private var showRacePrompt: Bool {
        forceRacePrompt || (model.today.races.isEmpty && !racePromptDismissed)
    }

    public var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: Layout.cardSpacing) {
                    TodayHeader(date: model.today.date, onSettings: onSettings)
                    BuddySummaryCard(model: model)
                    StatsRow(today: model.today)
                    if showRacePrompt {
                        RacePromptBanner(
                            onTap: onSettings,
                            onDismiss: {
                                RacePromptState.markDismissed()
                                Analytics.shared.capture("race_prompt_dismissed")
                                withAnimation(Motion.overlay) { racePromptDismissed = true }
                            }
                        )
                    }
                    if let coach = model.today.coach {
                        CoachCard(coach: coach, onAskCoach: onAskCoach)
                    }
                    if let workout = model.today.latestWorkout {
                        WorkoutCard(workout: workout)
                    }
                    if let load = model.today.weeklyLoad {
                        WeeklyLoadCard(load: load)
                    }
                    ActivityHistoryButton(onTap: { withAnimation(Motion.overlay) { showHistory = true } })
                }
                .screenScrollContent()
            }
            .refreshable { await model.refresh() }

            if showHistory {
                ActivityHistoryView(model: model, onClose: { withAnimation(Motion.overlay) { showHistory = false } })
                    .overlayTransition()
                    .zIndex(1)
            }
        }
    }
}
