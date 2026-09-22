import SwiftUI

struct WorkoutModeBadge: View {
    let mode: ExecutionMode
    var isProminent: Bool = false

    var body: some View {
        Label(mode.title, systemImage: mode.symbol)
            .font(isProminent ? .subheadline.bold() : .caption)
            .padding(.horizontal, isProminent ? 10 : 6)
            .padding(.vertical, isProminent ? 4 : 2)
            .background(Color.secondary.opacity(isProminent ? 0.15 : 0.1))
            .clipShape(Capsule())
    }
}
