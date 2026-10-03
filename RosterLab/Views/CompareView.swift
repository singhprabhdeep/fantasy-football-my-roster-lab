import SwiftUI
import RosterLabKit

/// A waiver pickup side by side with any of my players at the same position.
struct CompareView: View {
    @Environment(AppModel.self) private var model
    let candidate: WaiverCandidate
    /// Starts with every one of my players at the position selected.
    @State private var selected: Set<String>

    init(candidate: WaiverCandidate) {
        self.candidate = candidate
        _selected = State(initialValue: Set(candidate.myPlayers.map(\.id)))
    }

    private var pickup: PlayerReport { candidate.player }
    /// My players worst to best (lowest average first), in the table and the picker.
    private var myPlayers: [PlayerReport] { RosterLabService.worstToBest(candidate.myPlayers, metrics: model.waiverMetrics) }
    private var chosen: [PlayerReport] { myPlayers.filter { selected.contains($0.id) } }
    private var starterIds: Set<String> { Set(model.dashboard?.starters.map(\.id) ?? []) }

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    PositionBadge(position: pickup.position)
                    Text(pickup.team ?? "FA").foregroundStyle(.secondary)
                    Text(candidate.addsLabel)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let current = model.waiverMetrics(pickup) { GamesBadge(games: current.games, weeks: current.weeks) }
                }
                .font(.subheadline)
                if NewsLine.hasNews(pickup, showLead: true) { NewsLine(player: pickup, showLead: true) }
                if let bid = FAABAdvisor.advice(for: pickup, status: model.dashboard?.faab) { FAABBidLine(bid: bid) }
                GameWindowPicker()
                NavigationLink("All stats for \(pickup.fullLabel)", value: pickup.id)
                if pickup.isKickerOrDefense { NoisyPositionNote() }
            }

            Section {
                if model.waiverMetrics(pickup) == nil {
                    Text("\(pickup.fullLabel) hasn't played this season yet.").foregroundStyle(.secondary)
                } else {
                    CompareTable(pickup: pickup, mine: chosen, metrics: model.waiverMetrics,
                                 rank: { model.riskRank($0, windowed: true) })
                }
            } header: {
                Text("Side by side")
            } footer: {
                Text("Using each player's \(model.waiverWindowLabel). Your players go worst to best by average. Green marks the best value in each row. Swipe sideways to see more players. Sortino base is the league starter average for the weeks each player played, so it isn't ranked.")
            }
            Section {
                if candidate.myPlayers.isEmpty {
                    Text("You don't have a \(pickup.position) on your roster.").foregroundStyle(.secondary)
                }
                ForEach(myPlayers) { mine in
                    Button { toggle(mine.id) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selected.contains(mine.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(mine.id) ? Color.accentColor : Color.secondary)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                PlayerNameText(player: mine)
                                Text(starterIds.contains(mine.id) ? "Starter" : "Bench")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatCell(label: "Sortino ratio", value: Fmt.sortino(model.waiverMetrics(mine)))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Compare with your \(pickup.position)s")
            } footer: {
                if candidate.myPlayers.count > 1 {
                    HStack {
                        Button("Select all") { selected = Set(candidate.myPlayers.map(\.id)) }
                        Text("·")
                        Button("Clear") { selected = [] }
                    }
                    .font(.caption)
                }
            }

        }
        .navigationTitle("\(pickup.fullLabel) vs My Roster")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Two lines so the full "Name (#) TEAM vs My Roster" title fits.
            ToolbarItem(placement: .principal) {
                Text("\(pickup.fullLabel) vs My Roster")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}

struct CompareTable: View {
    let pickup: PlayerReport
    let mine: [PlayerReport]
    let metrics: (PlayerReport) -> SeasonMetrics?
    let rank: (PlayerReport) -> StarterRank?

    private var columns: [PlayerReport] { [pickup] + mine }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    ForEach(columns) { player in
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(player.id == pickup.id ? "Pickup" : "Yours")
                                .font(.caption2)
                                .foregroundStyle(player.id == pickup.id ? Color.accentColor : Color.secondary)
                            Text(shortName(player)).font(.caption.weight(.semibold)).lineLimit(1)
                            Text(player.tagline).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                GridRow {
                    Text("Games").font(.caption).foregroundStyle(.secondary)
                    ForEach(columns) { Text("\(metrics($0)?.games ?? 0)") }
                }
                ForEach(Metric.allCases) { metric in
                    GridRow {
                        Text(metric.rawValue).font(.caption).foregroundStyle(.secondary)
                        ForEach(columns) { player in
                            let best = isBest(metric, player)
                            Text(metric.text(metrics(player)))
                                .fontWeight(best ? .bold : .regular)
                                .foregroundStyle(best ? Color.green : Color.primary)
                        }
                    }
                }
                GridRow {
                    Text("Risk-adj rank").font(.caption).foregroundStyle(.secondary)
                    ForEach(columns) { Text(RankText.short(rank($0))) }
                }
            }
            .font(.subheadline.monospacedDigit())
            .padding(.vertical, 4)
        }
    }

    /// True when this player has the best value in the row and at least two players have a value.
    private func isBest(_ metric: Metric, _ player: PlayerReport) -> Bool {
        guard metric.isComparable, let value = metric.value(metrics(player)) else { return false }
        let values = columns.compactMap { metric.value(metrics($0)) }
        guard values.count > 1, let best = metric.higherIsBetter ? values.max() : values.min() else { return false }
        return value == best && Set(values).count > 1
    }
}
