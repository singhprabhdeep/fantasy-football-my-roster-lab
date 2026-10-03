import SwiftUI
import RosterLabKit

/// First launch (and "Change league"): find the user's Sleeper leagues by username and pick one,
/// or open the bundled demo league. No sign-in: Sleeper's API is public and read-only.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @State private var username = ""
    @State private var leagues: [SleeperLeague]?
    @State private var searching = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image("SetupIcon")
                            .resizable()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        Text("Roster Lab").font(.largeTitle.bold())
                        Text("Grade your Sleeper fantasy football roster week to week, find waiver pickups and set FAAB bids. Every call shows how often it was right when replayed on four seasons of real league data.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)

                Section {
                    TextField("Sleeper username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .submitLabel(.search)
                        .focused($focused)
                        .onSubmit { Task { await search() } }
                    Button {
                        Task { await search() }
                    } label: {
                        HStack {
                            Text("Find my leagues")
                            if searching { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || searching)
                } header: {
                    Text("Your league")
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("Your username is in the Sleeper app under your profile. No password: Roster Lab only reads Sleeper's public data.")
                    }
                }

                if let leagues {
                    Section(leagues.isEmpty ? "No leagues found" : "Pick a league") {
                        if leagues.isEmpty {
                            Text("\(username) has no NFL leagues on Sleeper this season or last.").foregroundStyle(.secondary)
                        }
                        ForEach(leagues, id: \.leagueId) { league in
                            Button {
                                Task { await model.useLeague(league, username: username) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(league.name).foregroundStyle(.primary)
                                        Text(Self.summary(league)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Button {
                        Task { await model.startDemo() }
                    } label: {
                        Label("Try the demo league", systemImage: "play.circle")
                    }
                } footer: {
                    Text("A real 10-team half-PPR league, anonymized and frozen going into week 13 of 2025. No Sleeper account needed.")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            // `-uiSetupUser name` fills in and searches a username (for screenshots).
            .task {
                if let name = UserDefaults.standard.string(forKey: "uiSetupUser"), leagues == nil {
                    username = name
                    await search()
                }
            }
        }
    }

    private func search() async {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        focused = false
        searching = true
        defer { searching = false }
        do {
            let found = try await model.findLeagues(username: name)
            error = nil
            leagues = found
        } catch {
            self.error = error.localizedDescription
            leagues = nil
        }
    }

    /// "2025 · 12 teams · Half PPR"
    static func summary(_ league: SleeperLeague) -> String {
        let ppr: String
        switch league.scoringSettings["rec"] ?? 0 {
        case 1: ppr = "PPR"
        case 0.5: ppr = "Half PPR"
        case 0: ppr = "Standard"
        case let x: ppr = "\(Fmt.number(x, digits: 2)) PPR"
        }
        return "\(league.season) · \(league.totalRosters) teams · \(ppr)"
    }
}
