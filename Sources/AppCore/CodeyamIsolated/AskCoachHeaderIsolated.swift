import SwiftUI

// Isolation scaffold for AskCoachHeader — codeyam renders this View standalone on the
// booted iOS simulator. CODEYAM_ISOLATE_COMPONENT=AskCoachHeader selects this struct in
// CodeyamIsolationHost.swift; CODEYAM_ISOLATE_SCENARIO picks the scenario below.
//
// TODO: seed real props per scenario (closures are stubbed — isolated rendering
// is about appearance, not behavior), then register each scenario:
//   codeyam-editor editor register '{"name":"AskCoachHeader - Default","componentName":"AskCoachHeader","deviceState":{"launchEnv":{"CODEYAM_ISOLATE_COMPONENT":"AskCoachHeader","CODEYAM_ISOLATE_SCENARIO":"Default"}},"dimensions":["iPhone 16"]}'
struct AskCoachHeaderIsolated: View {
    let scenario: String

    var body: some View {
        switch scenario {
        case "Connected":
            // AI coach connected — subtitle reads "Buddy • AI coach", text-only header.
            AskCoachHeader(connected: true)
        default:
            AskCoachHeader(connected: true)
        }
    }
}
