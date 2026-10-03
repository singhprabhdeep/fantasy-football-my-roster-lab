import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    LabeledContent("League", value: model.dashboard?.leagueName ?? (model.isDemo ? "Demo League" : "—"))
                    if !model.isDemo {
                        LabeledContent("Sleeper username", value: model.username)
                    }
                    Button(model.isDemo ? "Use my own league" : "Change league") { model.changeLeague() }
                } header: {
                    Text("League")
                } footer: {
                    if model.isDemo {
                        Text("\(AppModel.demoCaption). A real 10-team half-PPR league with every manager anonymized. Injuries are rebuilt from who sat out that week.")
                    }
                }

                Section {
                    Toggle("Use finished games from this week", isOn: $model.useFinishedGames)
                        .onChange(of: model.useFinishedGames) { Task { await model.load(refresh: true) } }
                        .disabled(model.isDemo)
                } footer: {
                    Text("On: a player's game counts as soon as it's final (Thursday night onward), and the Sortino base for this week uses only the league starters whose games are final. Numbers, the base and rankings move as more games finish; cards show \"wk N in progress\". Off: only fully finished weeks count.")
                }

                Section {
                    Stepper(value: $model.k, in: 0...3, step: 0.25) {
                        LabeledContent("Risk penalty (k)", value: Fmt.number(model.k, digits: 2))
                    }
                    .onChange(of: model.k) { Task { await model.load() } }
                } footer: {
                    Text("Risk-adjusted average = average − k × downside deviation. A higher k punishes boom-or-bust players more.")
                }

                Section {
                    Button("Reload data") { Task { await model.load(refresh: true) } }
                        .disabled(model.isLoading)
                    Button("Clear saved data and reload", role: .destructive) {
                        Task { await model.clearCacheAndReload() }
                    }
                    .disabled(model.isLoading)
                } footer: {
                    if let loaded = model.dashboard?.loadedAt {
                        Text("Last loaded \(loaded.formatted(date: .abbreviated, time: .shortened)). Data comes from Sleeper's public API. Finished weeks are saved on your phone and only downloaded once.")
                    }
                }
            }
            .navigationTitle("Settings")
            .demoBadge()
        }
    }
}
