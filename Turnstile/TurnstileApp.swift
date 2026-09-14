import SwiftUI

@main
struct TurnstileApp: App {
    @StateObject private var store = GameStore()

    var body: some Scene {
        WindowGroup {
            GateHomeView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Palette.brand)
        }
    }
}
