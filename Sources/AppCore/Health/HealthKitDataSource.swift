import Foundation

// MARK: - HealthKit data source (real, iOS)
//
// Reads live activity from HealthKit on a real device: today's step count,
// walking/running distance, and active energy, plus recent workouts. Compiled
// only for iOS; on other platforms (the macOS test build) a stub reports
// `.unavailable` so the package still compiles. This is platform glue — its real
// behavior is verified on a signed device build, not in the CodeYam preview loop
// (which uses the seeded source).
//
// Requires: the HealthKit capability/entitlement and `NSHealthShareUsageDescription`
// in Info.plist (enabled in Xcode when signing — see docs/integrations-plan.md).

#if os(iOS)
import HealthKit

public final class HealthKitDataSource: HealthDataSource {
    private let store = HKHealthStore()

    public init() {}

    // The daily goal is read live from the user's persisted preference each load,
    // so changing it in Settings reflects immediately.
    private var goalSteps: Int { UserPreferences.goalSteps() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let dist = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) { types.insert(dist) }
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        return types
    }

    public func authorizationState() -> HealthAuthState {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        guard let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return .unavailable }
        // Note: read authorization is intentionally opaque in HealthKit — a
        // `.notDetermined`/`.sharingDenied` status here reflects whether we've asked,
        // not whether the user granted reads (Apple hides that for privacy). We treat
        // "asked" as authorized and rely on empty reads to surface a real denial.
        switch store.authorizationStatus(for: steps) {
        case .notDetermined: return .notDetermined
        case .sharingDenied: return .authorized   // may still allow reads; see note
        case .sharingAuthorized: return .authorized
        @unknown default: return .notDetermined
        }
    }

    public func requestAuthorization() async -> HealthAuthState {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        return await withCheckedContinuation { cont in
            store.requestAuthorization(toShare: [], read: readTypes) { ok, _ in
                cont.resume(returning: ok ? .authorized : .denied)
            }
        }
    }

    public func loadToday() async -> TodayState {
        async let steps = sumToday(.stepCount, unit: .count())
        async let distance = sumToday(.distanceWalkingRunning, unit: .mile())
        async let energy = sumToday(.activeEnergyBurned, unit: .kilocalorie())

        let isoDate = DateFormatter.iso.string(from: Date())
        return TodayState(
            healthKitConnected: true,
            date: isoDate,
            steps: Int(await steps),
            goalSteps: goalSteps,
            activeMinutes: 0,                       // derived later from workouts
            distanceMiles: await distance,
            activeEnergyKcal: Int(await energy),
            minutesSinceLastMovement: 0
        )
    }

    /// Sum a cumulative quantity from midnight to now.
    private func sumToday(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                      options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }
}

private extension DateFormatter {
    static let iso: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

#else

// Non-iOS (e.g. the macOS test build): HealthKit isn't used. Report unavailable so
// the package compiles and any production path falls back gracefully.
public final class HealthKitDataSource: HealthDataSource {
    public init(goalSteps: Int = 10000) {}
    public func authorizationState() -> HealthAuthState { .unavailable }
    public func requestAuthorization() async -> HealthAuthState { .unavailable }
    public func loadToday() async -> TodayState { .empty }
}

#endif
