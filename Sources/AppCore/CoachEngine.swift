import Foundation

// MARK: - Ask Coach engine
//
// The mock AI coach behind the Ask Coach chat screen. Pure, deterministic logic:
// classify a free-text question into an intent, then build a curated, context-
// aware answer from the user's `TodayState`. No network, no LLM — this is
// Milestone 2's mock mode, which keeps scenarios stable and the coach honest
// about its safety rules. Milestone 3 swaps the body of `reply(to:context:)` for
// a real model while keeping this same shape.

/// What the user is really asking. Classification is keyword-based and
/// deliberately conservative: anything ambiguous falls through to `.general`.
public enum CoachIntent: String, CaseIterable {
    case runOrRest          // "can I run or should I rest?"
    case hit10K             // "how do I get to 10k steps?"
    case mileageTooFast     // "am I increasing mileage too fast?"
    case injuryPain         // "my knee hurts after my run"
    case postRunReflection  // "how did my run go?"
    case raceGoal           // "make me a plan for my October half"
    case general            // catch-all: "what should I do today?"

    /// Classify a free-text question. Injury/pain is checked first so a
    /// safety-sensitive question is never mis-routed to upbeat coaching.
    public static func classify(_ question: String) -> CoachIntent {
        let q = question.lowercased()
        func has(_ needles: [String]) -> Bool { needles.contains { q.contains($0) } }

        if has(["hurt", "pain", "sore", "ache", "injur", "knee", "shin", "tweak", "twinge", "strain"]) {
            return .injuryPain
        }
        if has(["too fast", "too much", "ramp", "increasing mileage", "mileage too", "overtrain", "overdo", "build too"]) {
            return .mileageTooFast
        }
        if has(["10k", "10,000", "10000", "step"]) {
            return .hit10K
        }
        if has(["rest", "run today", "should i run", "run or", "or rest", "easy day", "day off", "recover"]) {
            return .runOrRest
        }
        if has(["how was", "how did", "reflect", "run go", "rate my", "last run"]) {
            return .postRunReflection
        }
        // Race wording routes to dedicated race coaching. Kept AFTER injury/mileage
        // so safety routing is never overridden, and the keywords avoid the
        // step-goal terms ("10k"/"5k") that belong to .hit10K.
        if has(["marathon", "race", "taper", "goal race", "race plan", "race day"]) {
            return .raceGoal
        }
        return .general
    }
}

/// A single coach answer: the prose plus how Buddy should look while saying it.
public struct CoachReply: Equatable {
    public var intent: CoachIntent
    public var text: String
    public var mood: BuddyMood
    public var safetyFlag: Bool

    public init(intent: CoachIntent, text: String, mood: BuddyMood, safetyFlag: Bool = false) {
        self.intent = intent
        self.text = text
        self.mood = mood
        self.safetyFlag = safetyFlag
    }
}

public enum CoachEngine {
    /// Build a curated, context-aware reply to `question` given the day's state.
    /// Pure and deterministic — the same inputs always yield the same reply.
    public static func reply(to question: String, context: TodayState, asOf today: String = "") -> CoachReply {
        let day = resolvedToday(today, context)
        switch CoachIntent.classify(question) {
        case .injuryPain:        return injuryReply(context)
        case .mileageTooFast:    return mileageReply(context)
        case .hit10K:            return stepsReply(context)
        case .runOrRest:         return runOrRestReply(context)
        case .postRunReflection: return reflectionReply(context)
        case .raceGoal:          return raceReply(context, asOf: day)
        case .general:           return generalReply(context, asOf: day)
        }
    }

    /// The "today" date used for race math: an explicit override wins, else the
    /// context's own date, else the system date (only hit in production / when no
    /// race is set, so determinism for the no-race tests is preserved).
    private static func resolvedToday(_ asOf: String, _ c: TodayState) -> String {
        if !asOf.isEmpty { return asOf }
        if !c.date.isEmpty { return c.date }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }

    /// Race-aware coaching clause for the soonest upcoming race, or nil when none.
    /// Phase-based: race day, taper week (<=7d), sharpen (<=21d), build (>21d).
    private static func raceClause(_ c: TodayState, asOf today: String) -> String? {
        guard let race = RaceGoal.next(in: c.races, asOf: today),
              let days = RaceGoal.daysUntil(date: race.date, asOf: today) else { return nil }
        if days <= 0 {
            return "Race day for your \(race.name). Keep it calm, trust your training, and run your plan. You've done the work."
        }
        if days <= 7 {
            return "Your \(race.name) is in \(days) day\(days == 1 ? "" : "s"). This is taper time: keep runs short and easy, prioritize sleep, and trust the work you've banked."
        }
        if days <= 21 {
            return "Your \(race.name) is about \(days) days out. Sharpen gently now, but don't cram. A little quality, plenty of easy."
        }
        return "You've got \(miles(race.distanceMiles)) mi at \(race.name) in \(days) days. Plenty of runway: build gradually, about 10% a week, and keep most runs easy."
    }

    private static func raceReply(_ c: TodayState, asOf today: String) -> CoachReply {
        if let clause = raceClause(c, asOf: today) {
            return CoachReply(intent: .raceGoal, text: clause, mood: .ready)
        }
        let text = "Tell me about your race in Settings — the name, distance, and date — and I'll build your training toward it, then ease you off as it nears. What are you aiming at?"
        return CoachReply(intent: .raceGoal, text: text, mood: .ready)
    }

    // Use the data we have, but never push through warning signs. A recent hard
    // run or a spiking weekly load tilts every recommendation toward recovery.
    private static func ranHardRecently(_ c: TodayState) -> Bool {
        if let w = c.latestWorkout, w.type == "run", w.distanceMiles >= 5 { return true }
        if let l = c.weeklyLoad, l.loadTrend == "spiking" { return true }
        return false
    }

    // MARK: Intent replies

    private static func injuryReply(_ c: TodayState) -> CoachReply {
        let text = "I can't diagnose injuries, so let's play it safe. If the pain is sharp, persistent, or getting worse, please check in with a clinician. For now, skip hard running — rest, gentle walking, and light mobility are the right call until it settles. We'll ease back in once you're pain-free."
        return CoachReply(intent: .injuryPain, text: text, mood: .concerned, safetyFlag: true)
    }

    private static func mileageReply(_ c: TodayState) -> CoachReply {
        if let l = c.weeklyLoad, l.loadTrend == "spiking" {
            let text = "Your weekly load is climbing fast (about \(miles(l.weeklyMileage)) mi this week). That's where injury risk creeps in. Let's hold mileage steady or pull back ~10% next week, keep most runs easy, and protect your rest days. Sustainable beats heroic."
            return CoachReply(intent: .mileageTooFast, text: text, mood: .concerned, safetyFlag: true)
        }
        let text = "Good instinct to check. A safe rule of thumb is keeping weekly mileage growth under ~10%, with an easier week every few weeks. You're in a reasonable range right now — keep most runs conversational and you'll build fitness without the injury tax."
        return CoachReply(intent: .mileageTooFast, text: text, mood: .ready)
    }

    private static func stepsReply(_ c: TodayState) -> CoachReply {
        let remaining = max(0, c.goalSteps - c.steps)
        if remaining == 0 {
            let text = "You've already cleared \(formatted(c.goalSteps)) steps today — nice work! Anything more is a bonus. A gentle walk to loosen up is plenty."
            return CoachReply(intent: .hit10K, text: text, mood: .celebrating)
        }
        let minutes = max(8, Int((Double(remaining) / 110.0).rounded()))
        let text = "You're \(formatted(remaining)) steps from \(formatted(c.goalSteps)). A relaxed \(minutes)-minute walk gets you there without adding real training stress — podcast optional but encouraged. No need to rush it all at once."
        return CoachReply(intent: .hit10K, text: text, mood: .ready)
    }

    private static func runOrRestReply(_ c: TodayState) -> CoachReply {
        if ranHardRecently(c) {
            let text = "You put in a solid effort recently, so today leans toward recovery. An easy 20–40 minute walk or some light mobility will help that work settle into fitness. If you're itching to move, keep it gentle — save the hard stuff for when you're fresh."
            return CoachReply(intent: .runOrRest, text: text, mood: .recovery)
        }
        let text = "You look reasonably fresh, so an easy run is on the table — keep it conversational, nothing heroic. If your legs feel heavy or sleep was rough, a brisk walk is a perfectly good substitute. Listen to the body first."
        return CoachReply(intent: .runOrRest, text: text, mood: .ready)
    }

    private static func reflectionReply(_ c: TodayState) -> CoachReply {
        if let w = c.latestWorkout {
            let text = "Your last \(w.type) was \(miles(w.distanceMiles)) mi at \(w.pace) — a real effort in the bank. Notice how the legs feel today: a little tired is normal, sharp or one-sided pain is not. Recover well and the next one comes easier."
            return CoachReply(intent: .postRunReflection, text: text, mood: .cheering)
        }
        let text = "I don't see a recent run logged yet. Once you've got one in, ask me again and I'll help you reflect on how it went and what to do next."
        return CoachReply(intent: .postRunReflection, text: text, mood: .ready)
    }

    private static func generalReply(_ c: TodayState, asOf today: String) -> CoachReply {
        if ranHardRecently(c) {
            let text = "After that recent effort, today is an easy movement day. Buddy suggests 30–45 minutes of walking and some light mobility — that's how hard work turns into fitness instead of soreness."
            return CoachReply(intent: .general, text: text, mood: .recovery)
        }
        // A fresh user with a race on the calendar gets race-phase framing as their
        // "what should I do today" answer. Safety (recovery, above) still wins.
        if let clause = raceClause(c, asOf: today) {
            return CoachReply(intent: .general, text: clause, mood: .ready)
        }
        let remaining = max(0, c.goalSteps - c.steps)
        if remaining > 0 {
            let text = "Today's a great day for easy movement. You're \(formatted(remaining)) steps from your goal — a relaxed walk covers most of that. Keep it light and consistent; that's what builds the habit."
            return CoachReply(intent: .general, text: text, mood: .ready)
        }
        let text = "You're already on track today — goal met and moving well. Keep things easy, hydrate, and let's set up tomorrow to feel just as good."
        return CoachReply(intent: .general, text: text, mood: .cheering)
    }
}
