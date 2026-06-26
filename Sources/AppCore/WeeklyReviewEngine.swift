import Foundation

// MARK: - Weekly Review engine
//
// The mock generator behind the Weekly Review screen. Pure, deterministic logic:
// turn the week's `WeeklyLoad` (plus the latest workout) into a five-section
// recap — what went well, what changed, training risk, suggested next week, and
// one focus area. No network, no LLM: this is the same curated/templated approach
// as `CoachEngine`, so scenarios stay stable and the recap honors the coach's
// safety rules (conservative, never shame-based, escalate real warning signs).
// Milestone 3 can swap the body of `generate(from:)` for a real model while
// keeping this same shape.

/// A generated weekly recap. Five prose sections plus a Buddy mood and a single
/// highlighted focus area, all derived from the week's training load. When
/// `hasActivity` is false the week has no logged activity yet and the screen
/// shows the encouraging first-week prompt instead of the full five sections.
public struct WeeklyReview: Equatable {
    public var hasActivity: Bool
    public var buddyMood: BuddyMood
    public var headline: String
    public var wentWell: String
    public var whatChanged: String
    public var trainingRisk: String
    public var nextWeek: String
    public var focusArea: String
    public var safetyFlag: Bool   // true → the training-risk section reads as caution

    public init(
        hasActivity: Bool,
        buddyMood: BuddyMood,
        headline: String,
        wentWell: String,
        whatChanged: String,
        trainingRisk: String,
        nextWeek: String,
        focusArea: String,
        safetyFlag: Bool = false
    ) {
        self.hasActivity = hasActivity
        self.buddyMood = buddyMood
        self.headline = headline
        self.wentWell = wentWell
        self.whatChanged = whatChanged
        self.trainingRisk = trainingRisk
        self.nextWeek = nextWeek
        self.focusArea = focusArea
        self.safetyFlag = safetyFlag
    }
}

public enum WeeklyReviewEngine {
    /// Build the week's recap from the day's state. Pure and deterministic — the
    /// same context always yields the same review.
    public static func generate(from context: TodayState, asOf today: String = "") -> WeeklyReview {
        var review: WeeklyReview = {
            // No week to summarize yet → the friendly first-week prompt.
            guard let load = context.weeklyLoad, hasLoggedActivity(load) else {
                return emptyReview()
            }
            // Spiking load is the one safety-sensitive state — it wins regardless of
            // how many runs went in, mirroring the coach's injury-aware bias.
            if load.loadTrend == "spiking" {
                return spikingReview(load, context)
            }
            if isSparse(load) {
                return sparseReview(load, context)
            }
            return solidReview(load, context)
        }()

        applyRaceNote(&review, context: context, asOf: resolvedToday(today, context))
        return review
    }

    // MARK: Race awareness (additive; never overrides the spiking caution)

    /// Fold a race-phase note into the review when an upcoming race exists. The
    /// spiking (safety) review keeps precedence — the race note rides alongside as
    /// "even with the race coming up, ease off." Pure + deterministic on `asOf`.
    private static func applyRaceNote(_ review: inout WeeklyReview, context: TodayState, asOf today: String) {
        guard let race = RaceGoal.next(in: context.races, asOf: today),
              let days = RaceGoal.daysUntil(date: race.date, asOf: today), days >= 0 else { return }
        let nm = race.name
        if !review.hasActivity {
            review.nextWeek += " And you've got \(nm) on the calendar. We'll build toward it the moment activity shows up."
        } else if review.safetyFlag {
            review.nextWeek += " Even with \(nm) coming up, this is the week to ease off. Race fitness is protected by staying healthy."
        } else if days <= 7 {
            review.nextWeek += " And with \(nm) in \(days) day\(days == 1 ? "" : "s"), this is taper week: keep runs short and easy, and trust the work."
            review.focusArea = "Taper for \(nm). Less is more now. Fresh legs beat tired ones on race day."
        } else {
            review.nextWeek += " Keep building toward \(nm), \(days) days out, about 10% a week with most runs easy."
        }
    }

    private static func resolvedToday(_ asOf: String, _ c: TodayState) -> String {
        if !asOf.isEmpty { return asOf }
        if !c.date.isEmpty { return c.date }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }

    // MARK: Classification

    private static func hasLoggedActivity(_ l: WeeklyLoad) -> Bool {
        l.daysRunThisWeek > 0 || l.weeklyMileage > 0
    }

    /// A sparse week: at most one run, mostly rest. Gentle "ease back in" framing.
    private static func isSparse(_ l: WeeklyLoad) -> Bool {
        l.daysRunThisWeek <= 1
    }

    private static func miles(_ d: Double) -> String {
        d == d.rounded() ? "\(Int(d))" : String(format: "%.1f", d)
    }

    // MARK: Reviews

    private static func emptyReview() -> WeeklyReview {
        WeeklyReview(
            hasActivity: false,
            buddyMood: .ready,
            headline: "Your first week starts here",
            wentWell: "There's no run history to recap yet — and that's a perfectly good place to begin. Every consistent runner started with a single easy walk.",
            whatChanged: "",
            trainingRisk: "",
            nextWeek: "Aim for three short, easy movement sessions this week — a 15–20 minute walk counts. Buddy will start building your recap the moment activity shows up.",
            focusArea: "Take one relaxed walk today. That's the whole goal — momentum first, mileage later."
        )
    }

    private static func solidReview(_ l: WeeklyLoad, _ c: TodayState) -> WeeklyReview {
        let well = "A consistent week — \(l.daysRunThisWeek) runs for \(miles(l.weeklyMileage)) miles, topped by a \(miles(l.longestRunMiles))-mile long run. That kind of rhythm is exactly what builds durable fitness."
        let changed = l.loadTrend == "building"
            ? "Your load is trending up gently — more total miles than a typical week, but at a sustainable pace rather than a jump."
            : "Your load held steady, which is great: steady weeks are where the earlier work actually settles into fitness."
        let risk = "Low. With \(l.restDaysThisWeek) rest \(l.restDaysThisWeek == 1 ? "day" : "days") and runs kept honest, you're building the right way. Keep most runs conversational and you'll stay clear of the injury tax."
        let next = "Repeat the pattern with one small nudge: hold the run count, add no more than ~10% to total miles, and keep one true rest day. Sustainable beats heroic."
        let focus = "Protect the easy days. The temptation after a strong week is to push every run — resist it, and the long run will keep climbing safely."
        return WeeklyReview(
            hasActivity: true,
            buddyMood: .cheering,
            headline: "Strong, steady week 🎉",
            wentWell: well,
            whatChanged: changed,
            trainingRisk: risk,
            nextWeek: next,
            focusArea: focus
        )
    }

    private static func spikingReview(_ l: WeeklyLoad, _ c: TodayState) -> WeeklyReview {
        let well = "You showed up — \(l.daysRunThisWeek) runs and \(miles(l.weeklyMileage)) miles is real commitment, with a \(miles(l.longestRunMiles))-mile long run in the bank. The engine is clearly willing."
        let changed = "Your weekly load jumped sharply this week. Big week-over-week climbs are the single most common place running injuries start — it's the rate of change, not the mileage itself, that matters."
        let risk = "Elevated. \(l.restDaysThisWeek == 0 ? "No rest days this week and a" : "A") fast-rising load is a classic overtraining setup. This isn't a problem yet — it's a flag to ease off before it becomes one. Sharp or one-sided pain means stop and check in with a clinician."
        let next = "Pull total mileage back ~10–15% and make it an easy week. Keep the run count if you like, but cap the long run and keep every run conversational. Protect at least one full rest day."
        let focus = "Take an easy week. One deliberate down week now protects the next month of training — that's the highest-leverage move you can make."
        return WeeklyReview(
            hasActivity: true,
            buddyMood: .concerned,
            headline: "Big week — let's ease off",
            wentWell: well,
            whatChanged: changed,
            trainingRisk: risk,
            nextWeek: next,
            focusArea: focus,
            safetyFlag: true
        )
    }

    private static func sparseReview(_ l: WeeklyLoad, _ c: TodayState) -> WeeklyReview {
        let runWord = l.daysRunThisWeek == 1 ? "one run" : "no runs"
        let well = "Life happened this week — \(runWord) and \(l.restDaysThisWeek) rest \(l.restDaysThisWeek == 1 ? "day" : "days"). No guilt here: rest is part of training, and you're still showing up to check in. That counts."
        let changed = "Training volume dipped versus a fuller week. The upside is you're well-rested and at very low injury risk right now."
        let risk = "Minimal. The only real risk from here is trying to make up for it all at once. Fitness is patient — a gentle restart beats a heroic comeback every time."
        let next = "Ease back in with two or three short, easy sessions — a 20–30 minute walk or relaxed jog. Consistency over intensity is the whole game this week."
        let focus = "Get one easy session in early in the week. Breaking the seal is the hardest part; after that, momentum does the work."
        return WeeklyReview(
            hasActivity: true,
            buddyMood: .ready,
            headline: "A quiet week — that's okay",
            wentWell: well,
            whatChanged: changed,
            trainingRisk: risk,
            nextWeek: next,
            focusArea: focus
        )
    }
}
