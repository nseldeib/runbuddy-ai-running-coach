import Foundation

// User-set preferences that persist locally (no account needed). Currently just
// the daily step goal, edited in Settings. Seeded scenarios still get their goal
// from `rbGoalSteps`; this is the production default + user override.
public enum UserPreferences {
    private static let goalKey = "otterpaceGoalSteps"
    public static let defaultGoal = 10000

    /// Preset goals offered in Settings.
    public static let goalOptions = [6000, 8000, 10000, 12000, 15000]

    public static func goalSteps(_ d: UserDefaults = .standard) -> Int {
        let v = d.integer(forKey: goalKey)
        return v > 0 ? v : defaultGoal
    }

    public static func setGoalSteps(_ value: Int, _ d: UserDefaults = .standard) {
        d.set(value, forKey: goalKey)
    }
}
