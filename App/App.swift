import SwiftUI
import AppCore

@main
struct SwiftUIApp: App {
    var body: some Scene {
        WindowGroup {
            // Otterpace is a light-only design (cream/coral Palette). Pin the
            // color scheme so system surfaces (TabView, SecureField, scroll
            // backgrounds, default Text) never flip dark on a Dark Mode device.
            //
            // In component-isolation captures the launch env selects a single
            // view via CodeyamIsolationHost; otherwise the app boots normally.
            (CodeyamIsolationHost.root() ?? AnyView(ContentView()))
                .preferredColorScheme(.light)
        }
    }
}
