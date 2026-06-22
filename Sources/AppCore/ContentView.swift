import SwiftUI

public struct ContentView: View {
    @StateObject private var model = CounterModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            Text("CodeYam Swift Template")
                .font(.title)
                .bold()
            
            Text("Count: \(model.count)")
                .font(.largeTitle)
            
            HStack(spacing: 40) {
                Button(action: {
                    model.decrement()
                }) {
                    Text("-")
                        .font(.largeTitle)
                        .frame(width: 60, height: 60)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(30)
                }
                
                Button(action: {
                    model.increment()
                }) {
                    Text("+")
                        .font(.largeTitle)
                        .frame(width: 60, height: 60)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(30)
                }
            }
        }
        .padding()
    }
}
