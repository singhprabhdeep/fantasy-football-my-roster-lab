import SwiftUI
import RosterLabKit

struct RosterView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [String]
    /// Owned here, outside the List, so the sheet isn't torn down when List rows are rebuilt.
    @State private var showingLeague = UserDefaults.standard.bool(forKey: "uiLeagueTotals")

    init(initialPlayer: String? = nil) {
        _path = State(initialValue: initialPlayer.flatMap { $0.isEmpty ? nil : [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let dash = model.dashboard {
                    if let error = model.errorMessage {
                        Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                    }
                    StarterTotals(dashboard: dash) { showingLeague = true }
                    let advice = dash.projectionWeek == nil ? [:]
                        : LineupAdvisor.advise(starters: dash.starters, bench: dash.bench, slots: dash.lineupSlots)
                    let roster = Dictionary((dash.starters + dash.bench).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    let check: (PlayerReport) -> StatsCheck? = { player in
                        guard let a = advice[player.id], !a.unavailable, let id = a.versusId, let other = roster[id] else { return nil }
                        return a.favorsThisPlayer
                            ? StatsCheck.compare(pick: player, other: other, k: model.k)
                            : StatsCheck.compare(pick: other, other: player, k: model.k)
                    }
                    Section {
                        ForEach(dash.starters) { player in
                            NavigationLink(value: player.id) {
                                PlayerRow(player: player, rank: model.riskRank(player), projectionWeek: dash.projectionWeek,
                                          advice: advice[player.id], statsCheck: check(player))
                            }
                        }
                    } header: {
                        InfoHeader(title: "Starters",
                                   info: "\(dash.season) season through week \(dash.throughWeek). Risk-adj = avg − \(Fmt.number(model.k, digits: 2)) × downside deviation. Downside is measured against the league's average starter at each position, week by week. Proj is Sleeper's projection for this week, scored with your league's rules; in every season from 2022 to 2025 it was the best way to set a lineup. The start/bench calls build your best lineup from those projections (season avg breaks near-ties). The % is how often a call like it was right in 2022–25: Strong is 70% or more, Lean 60–70%, Toss-up under 60%. Single weeks are noisy, so even Strong calls miss. Under each call, the stats line (agree, split or disagree) compares the two players on avg, last-2-game avg, risk-adj avg and touches + targets over the last 2 games. It's there for context only: on close calls the projection's pick was right just as often when those stats disagreed. On big projection gaps (6+ points) a disagree mattered a little: the pick was right about 69% of the time instead of 79%. \(Reliability.title) means the player has beaten a typical starter at his position on average.")
                    }
                    Section("Bench") {
                        ForEach(dash.bench) { player in
                            NavigationLink(value: player.id) {
                                PlayerRow(player: player, rank: model.riskRank(player), projectionWeek: dash.projectionWeek,
                                          advice: advice[player.id], statsCheck: check(player))
                            }
                        }
                    }
                }
            }
            .overlay { LoadStateOverlay() }
            .navigationTitle(model.dashboard?.leagueName ?? "My Roster")
            .demoBadge()
            .navigationDestination(for: String.self) { id in
                if let player = model.dashboard.flatMap({ findPlayer(id, in: $0) }) {
                    PlayerDetailView(player: player)
                }
            }
            .refreshable { await model.load(refresh: true) }
        }
        .sheet(isPresented: $showingLeague) {
            if let dash = model.dashboard {
                LeagueTotalsSheet(dashboard: dash)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

func findPlayer(_ id: String, in dash: Dashboard) -> PlayerReport? {
    (dash.starters + dash.bench).first { $0.id == id }
        ?? dash.waivers.first { $0.player.id == id }?.player
}

/// Adds up the starting lineup: my starters' average points next to what league-average
/// starters at the same positions score (the sum of each starter's Sortino base).
/// Tapping it opens the same totals for every team in the league.
struct StarterTotals: View {
    let dashboard: Dashboard
    let onOpenLeague: () -> Void

    private var totals: LineupTotals { LineupTotals(starters: dashboard.starters) }
    private func myRank(_ order: LineupRanking) -> Int? {
        order.sorted(dashboard.teams).firstIndex(where: \.isMine).map { $0 + 1 }
    }

    var body: some View {
        Section {
            Button(action: onOpenLeague) {
                VStack(alignment: .leading, spacing: 8) {
                    LineupTotalsRow(totals: totals, large: true)
                    if let avgRank = myRank(.avg), let riskRank = myRank(.riskAdjusted) {
                        Label("#\(avgRank) of \(dashboard.teams.count) by avg total, #\(riskRank) by risk-adj total. Tap to see every team.",
                              systemImage: "list.number")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            let missing = totals.totalStarters - totals.countedStarters
            InfoHeader(title: "Lineup total", info: "Sum of your \(totals.countedStarters) starters' average points per game, against the sum of their Sortino bases (what a league-average starter at each spot scores). Risk-adj total adds up each starter's risk-adjusted avg (avg − k × downside deviation), a downside estimate for the lineup. SD is how much the lineup's weekly total swings: √(sum of each starter's SD²)."
                 + (missing > 0 ? " \(missing) starter\(missing == 1 ? " has" : "s have") no games yet and \(missing == 1 ? "isn't" : "aren't") counted." : ""))
        }
    }
}

struct LineupTotalsRow: View {
    let totals: LineupTotals
    var large = false

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                cell(label: "Starters avg total", value: Fmt.number(totals.startersAvgTotal), color: .primary)
                cell(label: "Risk-adj total", value: Fmt.number(totals.riskAdjustedTotal), color: .primary)
            }
            GridRow {
                cell(label: "Base total", value: Fmt.number(totals.baseTotal), color: .secondary)
                cell(label: "SD", value: Fmt.number(totals.standardDeviation), color: .primary)
            }
        }
    }

    private func cell(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font((large ? Font.title2 : Font.body).weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Which lineup total the league sheet ranks by.
enum LineupRanking: String, CaseIterable, Identifiable {
    case avg = "Starters avg total"
    case riskAdjusted = "Risk-adj total"

    var id: String { rawValue }

    func sorted(_ teams: [LeagueTeam]) -> [LeagueTeam] {
        switch self {
        case .avg: return teams.sorted { $0.totals.startersAvgTotal > $1.totals.startersAvgTotal }
        case .riskAdjusted: return teams.sorted { $0.totals.riskAdjustedTotal > $1.totals.riskAdjustedTotal }
        }
    }
}

/// Every team's lineup total, ranked by the chosen total.
struct LeagueTotalsSheet: View {
    let dashboard: Dashboard
    @AppStorage("leagueRanking") private var ranking: LineupRanking = .avg

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Rank by", selection: $ranking) {
                        ForEach(LineupRanking.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    ForEach(Array(ranking.sorted(dashboard.teams).enumerated()), id: \.element.id) { index, team in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline.monospacedDigit())
                                .frame(width: 24, alignment: .trailing)
                                .foregroundStyle(team.isMine ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(team.teamName).font(.body.weight(team.isMine ? .bold : .medium)).lineLimit(1)
                                    if team.isMine {
                                        Text("You").font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                if team.teamName != team.managerName {
                                    Text(team.managerName).font(.caption).foregroundStyle(.secondary)
                                }
                                LineupTotalsRow(totals: team.totals)
                                let missing = team.totals.totalStarters - team.totals.countedStarters
                                if missing > 0 {
                                    Text("\(missing) starter\(missing == 1 ? "" : "s") with no games left out")
                                        .font(.caption2).foregroundStyle(.orange)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(team.isMine ? Color.accentColor.opacity(0.08) : nil)
                    }
                } footer: {
                    Text("Each team's current starters, using their \(dashboard.season) averages through week \(dashboard.throughWeek). Risk-adj total is the sum of each starter's risk-adjusted avg. Base total is what league-average starters at the same spots score. Ranked by \(ranking.rawValue.lowercased()).")
                }
            }
            .navigationTitle("League lineup totals")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// A section heading with an ⓘ button that shows an explanation in a small popover.
struct InfoHeader: View {
    let title: String
    let info: String
    @State private var showing = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Button { showing = true } label: {
                Image(systemName: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About \(title)")
            .popover(isPresented: $showing) {
                Text(info)
                    .font(.footnote)
                    .textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320, alignment: .leading)
                    .padding()
                    .presentationCompactAdaptation(.popover)
            }
        }
    }
}
