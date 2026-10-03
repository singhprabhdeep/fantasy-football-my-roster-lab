import SwiftUI
import Charts
import RosterLabKit

struct PlayerDetailView: View {
    @Environment(AppModel.self) private var model
    let player: PlayerReport
    @State private var selectedSeason: String

    init(player: PlayerReport) {
        self.player = player
        _selectedSeason = State(initialValue: player.seasons.first?.season ?? player.currentSeason)
    }

    private var selected: SeasonMetrics? { player.seasons.first { $0.season == selectedSeason } }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    PositionBadge(position: player.position)
                    Text(player.team ?? "Free agent").foregroundStyle(.secondary)
                    Spacer()
                    if let selected { GamesBadge(games: selected.games, weeks: selected.weeks) }
                }
                if NewsLine.hasNews(player, showLead: true) { NewsLine(player: player, showLead: true) }
                if player.isKickerOrDefense { NoisyPositionNote() }
            }

            if player.seasons.isEmpty {
                Section { Text("No games played in the seasons this app looks at.").foregroundStyle(.secondary) }
            } else {
                Section {
                    if player.seasons.count > 1 {
                        Picker("Season", selection: $selectedSeason) {
                            ForEach(player.seasons) { Text($0.season).tag($0.season) }
                        }
                        .pickerStyle(.segmented)
                    }
                    if let selected { WeeklyChart(metrics: selected, position: player.position) }
                } header: {
                    Text("Week by week")
                }

                if let selected, selected.weeks.contains(where: { $0.target != nil }) {
                    Section {
                        WeeklyBaseTable(metrics: selected)
                    } header: {
                        Text("Sortino base by week")
                    } footer: {
                        Text("Base = average points by every starting \(player.position) in your league that week. The Sortino ratio uses the difference in each week.")
                    }
                }

                Section {
                    SeasonTable(seasons: player.seasons)
                } header: {
                    Text("Every season")
                } footer: {
                    if let text = RankText.long(model.riskRank(player), position: player.position) {
                        Text("\(player.currentSeason) risk-adj avg: \(text) in your league.")
                    }
                }

                Section("What these mean") {
                    ForEach(Metric.allCases) { metric in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(metric.rawValue).font(.subheadline.weight(.semibold))
                            Text(metric.explanation).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(player.fullLabel)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WeeklyChart: View {
    let metrics: SeasonMetrics
    let position: String

    /// Pad half a week on each side so the first and last week labels aren't clipped.
    private var xDomain: ClosedRange<Double> {
        let weeks = metrics.weeks.map { Double($0.week) }
        return ((weeks.min() ?? 1) - 0.5)...((weeks.max() ?? 1) + 0.5)
    }

    var body: some View {
        Chart {
            ForEach(metrics.weeks) { week in
                if let target = week.target {
                    LineMark(x: .value("Week", week.week), y: .value("Points", target),
                             series: .value("Series", "Target"))
                        .foregroundStyle(by: .value("Series", "League \(position) starter avg"))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
                LineMark(x: .value("Week", week.week), y: .value("Points", week.points),
                         series: .value("Series", "Player"))
                    .foregroundStyle(by: .value("Series", "Points"))
                PointMark(x: .value("Week", week.week), y: .value("Points", week.points))
                    .foregroundStyle(week.target.map { week.points < $0 } == true ? .red : .accentColor)
            }
            RuleMark(y: .value("Avg", metrics.mean))
                .foregroundStyle(.secondary.opacity(0.4))
                .annotation(position: .top, alignment: .leading) {
                    Text("avg \(Fmt.number(metrics.mean))").font(.caption2).foregroundStyle(.secondary)
                }
        }
        .chartForegroundStyleScale([
            "Points": Color.accentColor,
            "League \(position) starter avg": Color.secondary,
        ])
        .chartXScale(domain: xDomain)
        .chartXAxis { AxisMarks(values: metrics.weeks.map(\.week)) }
        .chartXAxisLabel("Week")
        .frame(height: 220)
        .padding(.vertical, 6)
    }
}

struct SeasonTable: View {
    let seasons: [SeasonMetrics]

    /// Row labels stay put while the season columns scroll sideways (five seasons don't fit on a phone).
    private let rowHeight: CGFloat = 26
    private var rows: [(label: String, value: (SeasonMetrics) -> String)] {
        [("Games", { "\($0.games)" })] + Metric.allCases.map { metric in (metric.rawValue, { metric.text($0) }) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("").frame(height: rowHeight)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Text(row.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .frame(height: rowHeight, alignment: .leading)
                }
            }
            .fixedSize()
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(seasons) { season in
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(season.season).font(.caption.weight(.semibold)).frame(height: rowHeight)
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                Text(row.value(season)).monospacedDigit().frame(height: rowHeight)
                            }
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            .scrollIndicators(.visible)
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }
}

struct WeeklyBaseTable: View {
    let metrics: SeasonMetrics

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Text("Week").gridColumnAlignment(.leading)
                Text("Points")
                Text("Base")
                Text("Diff")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(metrics.weeks) { week in
                GridRow {
                    Text("\(week.week)").gridColumnAlignment(.leading)
                    Text(Fmt.number(week.points))
                    Text(Fmt.number(week.target))
                    Text(diff(week))
                        .foregroundStyle(week.target.map { week.points < $0 } == true ? Color.red : Color.green)
                }
            }
            Divider()
            GridRow {
                Text("Season").gridColumnAlignment(.leading).fontWeight(.semibold)
                Text(Fmt.number(metrics.mean)).fontWeight(.semibold)
                Text(Fmt.number(metrics.averageTarget)).fontWeight(.semibold)
                Text(metrics.averageExcess.map { ($0 >= 0 ? "+" : "") + Fmt.number($0) } ?? "–").fontWeight(.semibold)
            }
        }
        .font(.subheadline.monospacedDigit())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func diff(_ week: WeekResult) -> String {
        guard let target = week.target else { return "–" }
        let d = week.points - target
        return (d >= 0 ? "+" : "") + Fmt.number(d)
    }
}
