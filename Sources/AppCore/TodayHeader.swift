import SwiftUI

// The dashboard's top header: the "Today" title with the day, and the Otterpace
// wordmark.
struct TodayHeader: View {
    let date: String
    var onSettings: () -> Void = {}

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(Typography.largeTitle)
                    .foregroundColor(Palette.ink)
                Text(prettyDate(date))
                    .font(Typography.caption)
                    .foregroundColor(Palette.subtle)
            }
            Spacer()
            Text("Otterpace")
                .font(Typography.headline)
                .foregroundColor(Palette.brand)
            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Palette.subtle)
            }
            .padding(.leading, 10)
            .accessibilityLabel("Settings")
        }
    }
}
