import SwiftUI
import AppCore

@main
struct SwiftUIApp: App {
    var body: some Scene {
        WindowGroup {
            // Otterpace is a light-only design (cream/coral Palette). Pin the
            // color scheme so system surfaces (TabView, SecureField, scroll
            // backgrounds, default Text) never flip dark on a Dark Mode device.
            ContentView()
                .preferredColorScheme(.light)
        }
    }
}
