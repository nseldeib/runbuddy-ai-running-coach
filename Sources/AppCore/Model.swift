import Foundation

public class CounterModel: ObservableObject {
    @Published public var count: Int = 0

    public init() {}

    public func increment() {
        count += 1
    }

    public func decrement() {
        count -= 1
    }
}
