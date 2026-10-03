import SwiftUI

@main
struct RosterLabApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .task { await model.load() }
        }
        // iOS keeps the app in memory, so reopening it doesn't relaunch it. Reload whenever it comes
        // back to the foreground so lineup changes made in Sleeper show up.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    // Launch arguments like `-uiTab 1 -uiPlayer 4046` open a screen directly (handy for screenshots).
    @State private var tab = UserDefaults.standard.integer(forKey: "uiTab")

    var body: some View {
        if model.isSetUp {
            tabs
        } else {
            SetupView()
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            RosterView(initialPlayer: UserDefaults.standard.string(forKey: "uiPlayer"))
                .tabItem { Label("My Roster", systemImage: "person.3") }
                .tag(0)
            WaiverView(initialCompare: UserDefaults.standard.string(forKey: "uiCompare"))
                .tabItem { Label("Waivers", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(1)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(2)
        }
    }
}

/// A "Demo" capsule in the navigation bar while the bundled demo league is showing.
struct DemoBadge: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.toolbar {
            if model.isDemo {
                ToolbarItem(placement: .topBarLeading) {
                    Text("DEMO").fixedSize()
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor, in: Capsule())
                        .accessibilityLabel(AppModel.demoCaption)
                }
            }
        }
    }
}

extension View {
    func demoBadge() -> some View { modifier(DemoBadge()) }
}
