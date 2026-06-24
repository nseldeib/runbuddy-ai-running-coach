import Foundation

// MARK: - Domain types
//
// Otterpace's Today dashboard renders a single `TodayState` snapshot. In a real
// build this is assembled from HealthKit (and optionally Strava); in the
// CodeYam preview it is injected at launch through the scenario's
// `deviceState.preferences` under the shared key `seedStateJSON` (a JSON-encoded
// `TodayState`). Production starts empty: no seed → `.empty` → the day-one
// "Connect Apple Health" hero.

public struct LatestWorkout: Codable, Equatable {
    public var type: String          // run | walk | ride
    public var distanceMiles: Double
    public var durationMinutes: Int
    public var pace: String          // e.g. "10:15/mi"
    public var date: String          // ISO date, e.g. "2026-06-21"
    public var source: String        // healthkit | strava

    public init(type: String, distanceMiles: Double, durationMinutes: Int, pace: String, date: String, source: String) {
        self.type = type
        self.distanceMiles = distanceMiles
        self.durationMinutes = durationMinutes
        self.pace = pace
        self.date = date
        self.source = source
    }
}

public struct WeeklyLoad: Codable, Equatable {
    public var weeklyMileage: Double
    public var daysRunThisWeek: Int
    public var longestRunMiles: Double
    public var restDaysThisWeek: Int
    public var loadTrend: String      // building | steady | spiking | recovering

    public init(weeklyMileage: Double, daysRunThisWeek: Int, longestRunMiles: Double, restDaysThisWeek: Int, loadTrend: String) {
        self.weeklyMileage = weeklyMileage
        self.daysRunThisWeek = daysRunThisWeek
        self.longestRunMiles = longestRunMiles
        self.restDaysThisWeek = restDaysThisWeek
        self.loadTrend = loadTrend
    }
}

public struct CoachRecommendation: Codable, Equatable {
    public var buddyMood: String        // resting|ready|jogging|cheering|concerned|celebrating|recovery
    public var headline: String
    public var body: String
    public var recommendationType: String // move|walk|run|rest|celebrate|caution
    public var safetyFlag: Bool

    public init(buddyMood: String, headline: String, body: String, recommendationType: String, safetyFlag: Bool = false) {
        self.buddyMood = buddyMood
        self.headline = headline
        self.body = body
        self.recommendationType = recommendationType
        self.safetyFlag = safetyFlag
    }
}

public struct TodayState: Codable, Equatable {
    public var healthKitConnected: Bool
    public var date: String
    public var steps: Int
    public var goalSteps: Int
    public var activeMinutes: Int
    public var distanceMiles: Double
    public var activeEnergyKcal: Int
    public var minutesSinceLastMovement: Int
    public var latestWorkout: LatestWorkout?
    public var weeklyLoad: WeeklyLoad?
    public var coach: CoachRecommendation?
    public var workouts: [LatestWorkout]   // recent history, newest-first; [] => day-one empty

    public init(
        healthKitConnected: Bool,
        date: String = "",
        steps: Int = 0,
        goalSteps: Int = 10000,
        activeMinutes: Int = 0,
        distanceMiles: Double = 0,
        activeEnergyKcal: Int = 0,
        minutesSinceLastMovement: Int = 0,
        latestWorkout: LatestWorkout? = nil,
        weeklyLoad: WeeklyLoad? = nil,
        coach: CoachRecommendation? = nil,
        workouts: [LatestWorkout] = []
    ) {
        self.healthKitConnected = healthKitConnected
        self.date = date
        self.steps = steps
        self.goalSteps = goalSteps
        self.activeMinutes = activeMinutes
        self.distanceMiles = distanceMiles
        self.activeEnergyKcal = activeEnergyKcal
        self.minutesSinceLastMovement = minutesSinceLastMovement
        self.latestWorkout = latestWorkout
        self.weeklyLoad = weeklyLoad
        self.coach = coach
        self.workouts = workouts
    }

    // Production default: nothing connected yet, blank day-one state.
    public static let empty = TodayState(healthKitConnected: false, goalSteps: 10000)
}

// MARK: - Observable model

public final class OtterpaceModel: ObservableObject {
    @Published public var today: TodayState
    /// Whether the app may read HealthKit. Drives the Connect hero vs. the
    /// "Health access is off" state. Seeded scenarios start `.authorized`.
    @Published public var healthAuth: HealthAuthState

    private let source: HealthDataSource

    public init(today: TodayState, source: HealthDataSource = SeededHealthDataSource()) {
        self.today = today
        self.source = source
        self.healthAuth = today.healthKitConnected ? .authorized : .notDetermined
    }

    /// Launch-time initializer used by the app. In a CodeYam scenario it builds the
    /// `TodayState` from the seeded `rb*` UserDefaults (previews unchanged). In
    /// production (no seed) it starts empty and reads live data from HealthKit once
    /// the user connects.
    public convenience init() {
        let defaults = UserDefaults.standard
        let source = HealthSource.make(defaults: defaults)
        if HealthSource.isScenarioSeeded(defaults) {
            self.init(today: OtterpaceModel.readState(defaults: defaults), source: source)
        } else {
            self.init(today: .empty, source: source)
            self.healthAuth = source.authorizationState()
        }
    }

    /// Read the snapshot from flat `rb*` UserDefaults keys. Each scenario writes
    /// these as primitive `preferences` values; the `rb` prefix keeps them from
    /// colliding with unrelated keys left on a shared simulator. A field group
    /// (workout / weekly load / coach) is present only when its anchor key is set.
    public static func readState(defaults d: UserDefaults = .standard) -> TodayState {
        let connected = d.bool(forKey: "rbConnected")
        var goal = d.integer(forKey: "rbGoalSteps")
        if goal == 0 { goal = 10000 }

        var workout: LatestWorkout? = nil
        if let type = d.string(forKey: "rbWorkoutType"), !type.isEmpty {
            workout = LatestWorkout(
                type: type,
                distanceMiles: d.double(forKey: "rbWorkoutDistanceMiles"),
                durationMinutes: d.integer(forKey: "rbWorkoutDurationMinutes"),
                pace: d.string(forKey: "rbWorkoutPace") ?? "",
                date: d.string(forKey: "rbWorkoutDate") ?? "",
                source: d.string(forKey: "rbWorkoutSource") ?? "healthkit"
            )
        }

        var load: WeeklyLoad? = nil
        if let trend = d.string(forKey: "rbLoadTrend"), !trend.isEmpty {
            load = WeeklyLoad(
                weeklyMileage: d.double(forKey: "rbWeeklyMileage"),
                daysRunThisWeek: d.integer(forKey: "rbDaysRunThisWeek"),
                longestRunMiles: d.double(forKey: "rbLongestRunMiles"),
                restDaysThisWeek: d.integer(forKey: "rbRestDaysThisWeek"),
                loadTrend: trend
            )
        }

        // Activity history: a JSON-encoded array of workouts under a single
        // preference key (the flat rb* primitives can't hold a list). Newest-first.
        var workouts: [LatestWorkout] = []
        if let json = d.string(forKey: "rbWorkoutsJSON"), !json.isEmpty,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([LatestWorkout].self, from: data) {
            workouts = decoded
        }

        var coach: CoachRecommendation? = nil
        if let headline = d.string(forKey: "rbCoachHeadline"), !headline.isEmpty {
            coach = CoachRecommendation(
                buddyMood: d.string(forKey: "rbBuddyMood") ?? "ready",
                headline: headline,
                body: d.string(forKey: "rbCoachBody") ?? "",
                recommendationType: d.string(forKey: "rbCoachType") ?? "move",
                safetyFlag: d.bool(forKey: "rbCoachSafety")
            )
        }

        return TodayState(
            healthKitConnected: connected,
            date: d.string(forKey: "rbDate") ?? "",
            steps: d.integer(forKey: "rbSteps"),
            goalSteps: goal,
            activeMinutes: d.integer(forKey: "rbActiveMinutes"),
            distanceMiles: d.double(forKey: "rbDistanceMiles"),
            activeEnergyKcal: d.integer(forKey: "rbActiveEnergyKcal"),
            minutesSinceLastMovement: d.integer(forKey: "rbMinutesSinceMovement"),
            latestWorkout: workout,
            weeklyLoad: load,
            coach: coach,
            workouts: workouts
        )
    }

    // MARK: Derived values

    /// Fraction of the daily step goal reached, clamped to 0...1.
    public var goalProgress: Double {
        guard today.goalSteps > 0 else { return 0 }
        return min(1.0, Double(today.steps) / Double(today.goalSteps))
    }

    /// Steps still needed to hit the goal (never negative).
    public var stepsRemaining: Int {
        max(0, today.goalSteps - today.steps)
    }

    public var goalReached: Bool {
        today.steps >= today.goalSteps && today.goalSteps > 0
    }

    /// True when the user has gone *past* the goal, not merely reached it — used
    /// to swap the ring's caption from "goal hit" to a celebratory "Goal crushed".
    public var goalExceeded: Bool {
        today.steps > today.goalSteps && today.goalSteps > 0
    }

    /// Connect Apple Health: request read authorization, then load today's data.
    /// Seeded scenarios "grant" immediately and load their seeded state; production
    /// drives the real HealthKit permission sheet. On denial the model exposes
    /// `.denied` so the UI can point the user to Settings.
    public func connect() {
        Task { @MainActor in
            let state = await source.requestAuthorization()
            healthAuth = state
            if state == .authorized {
                today = await source.loadToday()
            }
        }
    }

    /// Re-read today's data from the source (e.g. on foreground), if authorized.
    public func refresh() async {
        guard healthAuth == .authorized else { return }
        today = await source.loadToday()
    }

    /// Set the daily step goal: persist it and apply immediately to the dashboard.
    public func setGoalSteps(_ goal: Int) {
        UserPreferences.setGoalSteps(goal)
        today.goalSteps = goal
    }
}
