import Foundation

// MARK: - Race goals (optional, on-device)
//
// Lets a user tell Otterpace about upcoming races so Buddy's coaching becomes
// goal-aware (build early, taper near race day, calm race-day framing). Races are
// entirely optional and entirely on-device — stored as a JSON array in
// UserDefaults (same pattern as `rbWorkoutsJSON`) and carried on `TodayState` so
// they flow, with no new plumbing, into the on-device `CoachEngine`, the remote AI
// coach (`api/coach.ts`), and the `WeeklyReviewEngine`.

public struct RaceGoal: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var distanceMiles: Double
    public var date: String          // ISO yyyy-MM-dd, matching LatestWorkout.date
    public var location: String      // city / venue
    public var notes: String?        // optional: start area, corral, goal time

    public init(id: UUID = UUID(), name: String, distanceMiles: Double, date: String,
                location: String = "", notes: String? = nil) {
        self.id = id
        self.name = name
        self.distanceMiles = distanceMiles
        self.date = date
        self.location = location
        self.notes = notes
    }

    // MARK: Pure helpers (ISO date strings sort lexicographically, so plain string
    // comparison is correct for upcoming/sorting — dependency-free and testable).

    /// Races on or after `today`, soonest-first.
    public static func upcoming(in races: [RaceGoal], asOf today: String) -> [RaceGoal] {
        races.filter { $0.date >= today }.sorted { $0.date < $1.date }
    }

    /// The soonest upcoming race, if any.
    public static func next(in races: [RaceGoal], asOf today: String) -> RaceGoal? {
        upcoming(in: races, asOf: today).first
    }

    /// Whole days between two ISO `yyyy-MM-dd` dates (`today` → `date`). Negative
    /// when the date is in the past; nil on unparseable input.
    public static func daysUntil(date: String, asOf today: String) -> Int? {
        guard let from = isoParser.date(from: today), let to = isoParser.date(from: date) else { return nil }
        return utcCalendar.dateComponents([.day], from: from, to: to).day
    }

    private static let isoParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }()
}

// MARK: - Distance presets

/// Distance presets for the Settings editor, mirroring the daily-step-goal capsule
/// + custom stepper. `custom` carries an arbitrary mileage.
public enum RaceDistance: CaseIterable, Equatable {
    case fiveK, tenK, half, marathon, custom

    public static let minMiles = 1.0
    public static let maxMiles = 100.0

    /// Canonical mileage for a preset (custom returns 0; callers supply the value).
    public var miles: Double {
        switch self {
        case .fiveK:    return 3.1
        case .tenK:     return 6.2
        case .half:     return 13.1
        case .marathon: return 26.2
        case .custom:   return 0
        }
    }

    public var label: String {
        switch self {
        case .fiveK:    return "5K"
        case .tenK:     return "10K"
        case .half:     return "Half"
        case .marathon: return "Marathon"
        case .custom:   return "Custom"
        }
    }

    /// Round a stored mileage back to a preset selection (within a small epsilon),
    /// falling back to `.custom` so the editor reopens on the right capsule.
    public static func preset(forMiles miles: Double) -> RaceDistance {
        for d in [RaceDistance.fiveK, .tenK, .half, .marathon] where abs(d.miles - miles) < 0.05 {
            return d
        }
        return .custom
    }

    public static func clampMiles(_ m: Double) -> Double {
        min(maxMiles, max(minMiles, (m * 10).rounded() / 10))
    }
}

// MARK: - On-device store (JSON array under one key)

public enum RaceStore {
    static let key = "otterpaceRaces"

    public static func load(_ d: UserDefaults = .standard) -> [RaceGoal] {
        guard let json = d.string(forKey: key), !json.isEmpty,
              let data = json.data(using: .utf8),
              let races = try? JSONDecoder().decode([RaceGoal].self, from: data)
        else { return [] }
        return races
    }

    public static func save(_ races: [RaceGoal], _ d: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(races),
              let json = String(data: data, encoding: .utf8) else { return }
        d.set(json, forKey: key)
    }

    @discardableResult
    public static func add(_ race: RaceGoal, _ d: UserDefaults = .standard) -> [RaceGoal] {
        var races = load(d); races.append(race); save(races, d); return races
    }

    @discardableResult
    public static func update(_ race: RaceGoal, _ d: UserDefaults = .standard) -> [RaceGoal] {
        var races = load(d)
        if let i = races.firstIndex(where: { $0.id == race.id }) { races[i] = race } else { races.append(race) }
        save(races, d); return races
    }

    @discardableResult
    public static func remove(id: UUID, _ d: UserDefaults = .standard) -> [RaceGoal] {
        var races = load(d); races.removeAll { $0.id == id }; save(races, d); return races
    }
}

// MARK: - "Add a race" Today banner dismissal

/// Whether the user has dismissed the Today "add a race" prompt. Modeled on
/// `OnboardingState`: a single UserDefaults flag with injectable defaults.
public enum RacePromptState {
    static let dismissedKey = "otterpaceRacePromptDismissed"

    public static func isDismissed(_ d: UserDefaults = .standard) -> Bool {
        d.bool(forKey: dismissedKey)
    }
    public static func markDismissed(_ d: UserDefaults = .standard) {
        d.set(true, forKey: dismissedKey)
    }
}
