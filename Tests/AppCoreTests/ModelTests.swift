import XCTest
@testable import AppCore

// XCTest, not swift-testing: the editor's runner parses the XCTest
// `--xunit-output` file, and swift-testing results do not reliably land there
// on Xcode 16.x / Swift 6.x. See README "## Testing" for the full rationale.
final class ModelTests: XCTestCase {
    // The production default is the empty, not-yet-connected day-one state, so a
    // fresh model with no seed shows the Connect hero rather than a zeroed dashboard.
    func testEmptyStateIsDisconnected() {
        let model = OtterpaceModel(today: .empty)
        XCTAssertFalse(model.today.healthKitConnected)
        XCTAssertEqual(model.today.goalSteps, 10000)
        XCTAssertEqual(model.goalProgress, 0)
    }

    // Goal progress is the steps/goal ratio, clamped to 1.0 even past the goal,
    // and `stepsRemaining` never goes negative — the ring and "to go" copy depend on this.
    func testGoalProgressClampsAndRemaining() {
        let partial = OtterpaceModel(today: TodayState(healthKitConnected: true, steps: 6420, goalSteps: 10000))
        XCTAssertEqual(partial.goalProgress, 0.642, accuracy: 0.0001)
        XCTAssertEqual(partial.stepsRemaining, 3580)
        XCTAssertFalse(partial.goalReached)

        let over = OtterpaceModel(today: TodayState(healthKitConnected: true, steps: 12500, goalSteps: 10000))
        XCTAssertEqual(over.goalProgress, 1.0)
        XCTAssertEqual(over.stepsRemaining, 0)
        XCTAssertTrue(over.goalReached)
    }

    // goalExceeded distinguishes "past the goal" from merely meeting it, so the
    // ring can swap "goal hit!" for the celebratory "Goal crushed!".
    func testGoalExceededOnlyWhenPastGoal() {
        // Below the goal: neither reached nor exceeded.
        let under = OtterpaceModel(today: TodayState(healthKitConnected: true, steps: 6420, goalSteps: 10000))
        XCTAssertFalse(under.goalReached)
        XCTAssertFalse(under.goalExceeded)

        // Exactly at the goal: reached but NOT exceeded.
        let exact = OtterpaceModel(today: TodayState(healthKitConnected: true, steps: 10000, goalSteps: 10000))
        XCTAssertTrue(exact.goalReached)
        XCTAssertFalse(exact.goalExceeded)

        // Past the goal: both reached and exceeded.
        let over = OtterpaceModel(today: TodayState(healthKitConnected: true, steps: 14200, goalSteps: 10000))
        XCTAssertTrue(over.goalReached)
        XCTAssertTrue(over.goalExceeded)

        // A zero goal can never be exceeded (guards against divide-by-zero framing).
        let zeroGoal = OtterpaceModel(today: TodayState(healthKitConnected: true, steps: 500, goalSteps: 0))
        XCTAssertFalse(zeroGoal.goalExceeded)
    }

    // The seed contract: flat `rb*` preference keys (what a scenario's deviceState
    // writes at launch) are read back into a fully-populated TodayState, including
    // the coach group anchored by `rbCoachHeadline`.
    func testReadStateFromFlatDefaults() {
        let defaults = UserDefaults(suiteName: "runbuddy.tests")!
        defaults.removePersistentDomain(forName: "runbuddy.tests")
        defaults.set(true, forKey: "rbConnected")
        defaults.set("2026-06-22", forKey: "rbDate")
        defaults.set(8200, forKey: "rbSteps")
        defaults.set(10000, forKey: "rbGoalSteps")
        defaults.set("cheering", forKey: "rbBuddyMood")
        defaults.set("Almost there", forKey: "rbCoachHeadline")
        defaults.set("A short walk seals the deal.", forKey: "rbCoachBody")
        defaults.set("walk", forKey: "rbCoachType")

        let state = OtterpaceModel.readState(defaults: defaults)
        XCTAssertTrue(state.healthKitConnected)
        XCTAssertEqual(state.steps, 8200)
        XCTAssertEqual(state.goalSteps, 10000)
        XCTAssertEqual(state.coach?.buddyMood, "cheering")
        XCTAssertEqual(state.coach?.headline, "Almost there")
        XCTAssertEqual(state.coach?.recommendationType, "walk")
        // No workout/load keys set => those groups stay absent.
        XCTAssertNil(state.latestWorkout)
        XCTAssertNil(state.weeklyLoad)
    }

    // With no keys seeded (production day one) the reader yields the empty,
    // disconnected state — goal defaults to 10k and the Connect hero shows.
    func testReadStateEmptyDefaultsToDisconnected() {
        let defaults = UserDefaults(suiteName: "runbuddy.tests.empty")!
        defaults.removePersistentDomain(forName: "runbuddy.tests.empty")
        let state = OtterpaceModel.readState(defaults: defaults)
        XCTAssertFalse(state.healthKitConnected)
        XCTAssertEqual(state.goalSteps, 10000)
        XCTAssertNil(state.coach)
    }

    // Connecting Apple Health from the day-one hero authorizes and loads the
    // dashboard. connect() requests authorization asynchronously (default seeded
    // source grants), so poll briefly for the state to settle.
    func testConnectFlipsState() async {
        let d = UserDefaults(suiteName: "ModelTests.\(UUID().uuidString)")!
        let model = await MainActor.run { OtterpaceModel(today: .empty, source: SeededHealthDataSource(defaults: d)) }
        await MainActor.run { model.connect() }
        for _ in 0..<50 {
            if await MainActor.run(body: { model.today.healthKitConnected }) { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let connected = await MainActor.run { model.today.healthKitConnected }
        XCTAssertTrue(connected)
    }

    // Setting the daily step goal applies it to the dashboard immediately.
    @MainActor func testSetGoalStepsApplies() {
        let model = OtterpaceModel(today: TodayState(healthKitConnected: true, steps: 5000, goalSteps: 10000))
        model.setGoalSteps(12000)
        XCTAssertEqual(model.today.goalSteps, 12000)
        XCTAssertEqual(UserPreferences.goalSteps(), 12000)
    }

    // UserPreferences falls back to the default goal when nothing is set.
    func testGoalDefaults() {
        let d = UserDefaults(suiteName: "ModelTests.goal.\(UUID().uuidString)")!
        XCTAssertEqual(UserPreferences.goalSteps(d), UserPreferences.defaultGoal)
        UserPreferences.setGoalSteps(8000, d)
        XCTAssertEqual(UserPreferences.goalSteps(d), 8000)
    }
}
