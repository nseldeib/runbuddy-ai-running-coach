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

    public init(model: OtterpaceModel, onAskCoach: @escaping () -> Void = {}, onSettings: @escaping () -> Void = {}) {
        self.model = model
        self.onAskCoach = onAskCoach
        self.onSettings = onSettings
        _showHistory = State(initialValue: UserDefaults.standard.bool(forKey: "rbShowHistory"))
    }

    public var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 18) {
                    TodayHeader(date: model.today.date, onSettings: onSettings)
                    BuddySummaryCard(model: model)
                    StatsRow(today: model.today)
                    if let coach = model.today.coach {
                        CoachCard(coach: coach, onAskCoach: onAskCoach)
                    }
                    if let workout = model.today.latestWorkout {
                        WorkoutCard(workout: workout)
                    }
                    if let load = model.today.weeklyLoad {
                        WeeklyLoadCard(load: load)
                    }
                    ActivityHistoryButton(onTap: { showHistory = true })
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }

            if showHistory {
                ActivityHistoryView(model: model, onClose: { showHistory = false })
                    .zIndex(1)
            }
        }
    }
}
