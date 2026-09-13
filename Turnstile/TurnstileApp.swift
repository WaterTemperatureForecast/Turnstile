import SwiftUI

@main
struct TurnstileApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
            YesterdayView()
                .tabItem { Label("Yesterday", systemImage: "clock.arrow.circlepath") }
            LeaderboardView()
                .tabItem { Label("Board", systemImage: "list.number") }
            YouView()
                .tabItem { Label("You", systemImage: "person") }
        }
        .task {
            await model.refresh()
            await model.loadMe()
            await model.loadPromos()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await model.refresh() }
            }
        }
    }
}
