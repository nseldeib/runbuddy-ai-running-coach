import XCTest
@testable import AppCore

// XCTest, not swift-testing: the editor's runner parses the XCTest
// `--xunit-output` file, and swift-testing results do not reliably land there
// on Xcode 16.x / Swift 6.x. See README "## Testing" for the full rationale.
final class ModelTests: XCTestCase {
    // Incrementing the counter raises its count by one from the initial zero —
    // proves the model's primary mutation works from a fresh instance.
    func testIncrement() {
        let model = CounterModel()
        XCTAssertEqual(model.count, 0)
        model.increment()
        XCTAssertEqual(model.count, 1)
    }

    // Decrementing the counter lowers its count by one below the initial zero —
    // proves the count is signed and the inverse mutation works from a fresh
    // instance, isolated from `testIncrement()` under parallel execution (each
    // test builds its own `CounterModel`, so there is no shared state to race).
    func testDecrement() {
        let model = CounterModel()
        XCTAssertEqual(model.count, 0)
        model.decrement()
        XCTAssertEqual(model.count, -1)
    }
}
