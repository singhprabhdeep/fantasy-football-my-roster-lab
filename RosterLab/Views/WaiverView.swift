import SwiftUI
import RosterLabKit

enum PositionFilter: String, CaseIterable, Identifiable {
    case all = "All", qb = "QB", rb = "RB", wr = "WR", te = "TE", k = "K", def = "DEF"

    var id: String { rawValue }

    func matches(_ position: String) -> Bool { self == .all || rawValue == position }
}

/// Opens the side-by-side comparison for one waiver player.
struct CompareRoute: Hashable {
    let playerId: String
}

struct WaiverView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = PositionFilter(rawValue: UserDefaults.standard.string(forKey: "uiPosition") ?? "") ?? .all
    @State private var path = NavigationPath()
    @State private var showingWhy = UserDefaults.standard.bool(forKey: "uiWhy")
    /// Opened from the `-uiWhy` launch argument it starts full height (for screenshots).
    @State private var whyDetent: PresentationDetent = UserDefaults.standard.bool(forKey: "uiWhy") ? .large : .medium
    // v2: default moved to Touches + targets, the best waiver signal in the 2025 backtest.
    @AppStorage("waiverRankByV2") private var storedRankBy: WaiverRank = .touches
    /// The saved choice if this position offers it, otherwise the position's first option.
    private var rankBy: WaiverRank {
        let options = WaiverRank.options(for: filter)
        return options.contains(storedRankBy) ? storedRankBy : options[0]
    }
    /// True shows the best value first (highest avg, lowest SD, ...); false flips the list.
    @AppStorage("waiverBestFirst") private var bestFirst = true
    @AppStorage("waiverMode") private var mode: WaiverMode = .season
    /// Off hides Sleeper's trending adds and leaves only the best available non-trending players.
    @AppStorage("waiverTrendingOnly") private var trendingOnly = false
    /// On shows only RB/WR/TE backups whose team's lead is out (Likely lead or Committee).
    @AppStorage("waiverStarterOut") private var starterOutOnly = false

    private func passesToggles(_ candidate: WaiverCandidate) -> Bool {
        (!trendingOnly || candidate.trending) && (!starterOutOnly || candidate.player.role.map { $0.kind != .lead } == true)
    }

    init(initialCompare: String? = nil) {
        var path = NavigationPath()
        if let id = initialCompare, !id.isEmpty { path.append(CompareRoute(playerId: id)) }
        _path = State(initialValue: path)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let dash = model.dashboard, showingUpcoming {
                    UpcomingWeekSection(dashboard: dash, candidates: dash.waivers.filter { !trendingOnly || $0.trending })
                } else if let dash = model.dashboard {
                    let shown = ranked(dash.waivers.filter { filter.matches($0.player.position) && passesToggles($0) })
                    Section {
                        if shown.isEmpty {
                            Text(starterOutOnly
                                 ? "No available backups whose starter is out\(filter == .all ? "" : " at \(filter.rawValue)") right now. Only RB, WR and TE have these."
                                 : filter == .all
                                 ? "No available players to show right now."
                                 : "No available \(filter.rawValue)s to show right now.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(shown) { candidate in
                            NavigationLink(value: CompareRoute(playerId: candidate.player.id)) {
                                WaiverCard(candidate: candidate)
                            }
                        }
                    } footer: {
                        Text("Sleeper's most-added players in the last 24 hours that nobody in your league has (Sleeper shares at most 100), topped up to about 150 with the best available players who aren't trending, marked Not trending: RB/WR/TE by touches + targets over the last 2 games, QB/K/DEF by average over the last 2 games. Ranked by \(rankBy.rawValue) (\(orderLabel)). Players with no value for that stat go last. Every number uses each player's \(model.waiverWindowLabel). Each card shows your lowest-scoring player at the same position (by average points, bench included); tap a card to compare with any of your players there and see every stat. Usage (touches + targets, snap share) comes first: in a 2025 backtest it was the best early sign of a pickup about to produce, while hot scoring streaks on 1–3 games tended to cool off.")
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 6) {
                    Picker("Position", selection: $filter) {
                        ForEach(PositionFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    // Matchups only exist for defenses, so the switch lives under DEF.
                    if filter == .def {
                        Picker("View", selection: $mode) {
                            ForEach(WaiverMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    GameWindowPicker()
                    Toggle(isOn: $trendingOnly) {
                        Label("Show trending players only", systemImage: "flame").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .tint(Color.accentColor)
                    if !showingUpcoming {
                    Toggle(isOn: $starterOutOnly) {
                        Label("Starter out: show backups only", systemImage: "arrow.up.forward.circle").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .tint(Color.accentColor)
                    HStack {
                        Label("Rank by", systemImage: "arrow.up.arrow.down").font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize()
                        Spacer()
                        Picker("Rank by", selection: Binding(get: { rankBy }, set: { storedRankBy = $0 })) {
                            ForEach(WaiverRank.options(for: filter)) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                        // Icon only so the row fits; the footer spells out the current order.
                        Button { bestFirst.toggle() } label: {
                            Label(orderLabel, systemImage: orderLabel.hasPrefix("High") ? "arrow.down" : "arrow.up")
                                .labelStyle(.iconOnly)
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityHint("Flips the order")
                    }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .overlay { LoadStateOverlay() }
            .navigationTitle("Waiver check")
            .demoBadge()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingWhy = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("Why these stats")
                }
            }
            .sheet(isPresented: $showingWhy) {
                WaiverStatsInfo()
                    .presentationDetents([.medium, .large], selection: $whyDetent)
                    .presentationDragIndicator(.visible)
            }
            .navigationDestination(for: CompareRoute.self) { route in
                if let candidate = model.dashboard?.waivers.first(where: { $0.player.id == route.playerId }) {
                    CompareView(candidate: candidate)
                }
            }
            .navigationDestination(for: String.self) { id in
                if let player = model.dashboard.flatMap({ findPlayer(id, in: $0) }) {
                    PlayerDetailView(player: player)
                }
            }
            .refreshable { await model.load(refresh: true) }
        }
    }

    private var showingUpcoming: Bool { filter == .def && mode == .upcoming }

    /// "High → low" or "Low → high", phrased for whichever direction is showing.
    private var orderLabel: String {
        let highFirst = rankBy.higherIsBetter == bestFirst
        return highFirst ? "High → low" : "Low → high"
    }

    /// Sorts by the chosen stat over the Games used window. Best first by default (low for points
    /// allowed, high for everything else). Players without a value go last; ties go to higher average.
    private func ranked(_ candidates: [WaiverCandidate]) -> [WaiverCandidate] {
        let highFirst = rankBy.higherIsBetter == bestFirst
        return candidates.sorted { a, b in
            let ma = model.waiverMetrics(a.player), mb = model.waiverMetrics(b.player)
            switch (rankBy.value(ma), rankBy.value(mb)) {
            case let (x?, y?) where x != y: return highFirst ? x > y : x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return (ma?.mean ?? -.infinity) > (mb?.mean ?? -.infinity)
            }
        }
    }
}

/// Chooses how many recent games the Waivers numbers use.
struct GameWindowPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack {
            Label("Games used", systemImage: "calendar").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Picker("Games used", selection: $model.waiverGames) {
                ForEach(AppModel.gameWindows, id: \.self) { n in
                    Text(n == 0 ? "Whole season" : n == 1 ? "Last game" : "Last \(n) games").tag(n)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}

struct WaiverCard: View {
    @Environment(AppModel.self) private var model
    let candidate: WaiverCandidate

    private var player: PlayerReport { candidate.player }
    /// Touches + targets and snap share don't describe kickers or defenses.
    private var usesUsage: Bool { !player.isKickerOrDefense }

    /// My lowest-scoring player at the position (starters and bench), judged on the same game window.
    private var mine: PlayerReport? {
        RosterLabService.lowestScoring(candidate.myPlayers, metrics: model.waiverMetrics)
    }
    private var pickupStats: SeasonMetrics? { model.waiverMetrics(player) }
    /// Replace / Watch / Don't replace, judged the way the 2022–25 backtest did: against my lowest
    /// player at the position over his last 2 games, on this week's projection and touches + targets.
    private var adviceTarget: PlayerReport? {
        let k = model.k
        return RosterLabService.lowestScoring(candidate.myPlayers) { $0.current(lastGames: 2, k: k) }
    }
    private var advice: WaiverAdvice? {
        WaiverAdvisor.advise(pickup: player, mine: adviceTarget, k: model.k, throughWeek: model.dashboard?.throughWeek ?? 0)
    }
    private var mineStats: SeasonMetrics? { mine.flatMap(model.waiverMetrics) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PositionBadge(position: player.position)
                VStack(alignment: .leading, spacing: 2) {
                    PlayerNameText(player: player, weight: .semibold)
                    HStack(spacing: 6) {
                        Text(candidate.addsLabel)
                            .font(.caption).foregroundStyle(.secondary)
                        if let current = pickupStats { GamesBadge(games: current.games, weeks: current.weeks) }
                    }
                }
            }

            if NewsLine.hasNews(player) { NewsLine(player: player) }
            if let bid = FAABAdvisor.advice(for: player, status: model.dashboard?.faab) { FAABBidLine(bid: bid) }
            if let advice { WaiverAdviceBanner(advice: advice, target: adviceTarget) }

            if pickupStats == nil {
                Text("No games this season yet.").font(.caption).foregroundStyle(.secondary)
            } else {
                Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 4) {
                    GridRow {
                        Text("").gridColumnAlignment(.leading)
                        Text("Pickup").font(.caption2.weight(.semibold))
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("Your lowest").font(.caption2).foregroundStyle(.secondary)
                            Text(mine.map { shortName($0) } ?? "None").font(.caption2.weight(.semibold)).lineLimit(1)
                            if let mine { Text(mine.tagline).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                    ForEach(Self.cardMetrics.filter { usesUsage || !$0.isUsage }) { metric in
                        GridRow {
                            Text(metric.rawValue).font(.caption).foregroundStyle(.secondary)
                            Text(metric.text(pickupStats))
                                .fontWeight(isBetter(metric) ? .bold : .regular)
                                .foregroundStyle(isBetter(metric) ? Color.green : Color.primary)
                            Text(metric.text(mineStats)).foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        Text("Risk-adj rank").font(.caption).foregroundStyle(.secondary)
                        Text(RankText.short(model.riskRank(player, windowed: true)))
                        Text(RankText.short(mine.flatMap { model.riskRank($0, windowed: true) }))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Self.laterMetrics.filter { usesUsage || !$0.isUsage }) { metric in
                        GridRow {
                            Text(metric.rawValue).font(.caption).foregroundStyle(.secondary)
                            Text(metric.text(pickupStats))
                                .fontWeight(isBetter(metric) ? .bold : .regular)
                                .foregroundStyle(isBetter(metric) ? Color.green : Color.primary)
                            Text(metric.text(mineStats)).foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        Text(Reliability.title).font(.caption).foregroundStyle(.secondary)
                        let pickupReliable = Reliability.label(pickupStats)
                        Text(pickupReliable)
                            .fontWeight(pickupReliable == "Yes" && Reliability.label(mineStats) != "Yes" ? .bold : .regular)
                            .foregroundStyle(pickupReliable == "Yes" && Reliability.label(mineStats) != "Yes" ? Color.green : Color.primary)
                        Text(Reliability.label(mineStats)).foregroundStyle(.secondary)
                    }
                    if player.position == "DEF" {
                        GridRow {
                            Text("Per game").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .gridCellColumns(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                        ForEach(DefenseStat.allCases.filter { $0 != .fantasyPoints }) { stat in
                            let a = pickupStats?.defensePerGame.map(stat.value)
                            let b = mineStats?.defensePerGame.map(stat.value)
                            let better = stat.isBetter(a, than: b)
                            GridRow {
                                Text(stat.rawValue).font(.caption).foregroundStyle(.secondary)
                                Text(Fmt.number(a))
                                    .fontWeight(better ? .bold : .regular)
                                    .foregroundStyle(better ? Color.green : Color.primary)
                                Text(Fmt.number(b)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .font(.subheadline.monospacedDigit())
            }

            if candidate.myPlayers.count > 1 {
                Label("Compare with your \(candidate.myPlayers.count) \(player.position)s", systemImage: "rectangle.split.3x1")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }

            if player.isKickerOrDefense { NoisyPositionNote() }
        }
        .padding(.vertical, 4)
    }

    /// What the card shows, best waiver signals first (2025 backtest). The compare page has the rest.
    static let cardMetrics: [Metric] = [.touches, .mean, .ram]
    /// Shown after the risk-adj rank: its top picks rarely beat my players in either backtest season.
    static let laterMetrics: [Metric] = [.snaps]

    /// The pickup's number is highlighted when it beats my player's.
    private func isBetter(_ metric: Metric) -> Bool {
        guard metric.isComparable else { return false }
        guard let a = metric.value(pickupStats), let b = metric.value(mineStats), a != b else { return false }
        return metric.higherIsBetter ? a > b : a < b
    }

}

/// "M. Washington" for players, "49ers" for team defenses.
func shortName(_ player: PlayerReport) -> String {
    if player.position == "DEF" { return player.name.split(separator: " ").last.map(String.init) ?? player.name }
    return shortName(player.name)
}

func shortName(_ name: String) -> String {
    let parts = name.split(separator: " ")
    guard parts.count > 1, let first = parts.first?.first else { return name }
    return "\(first). \(parts.dropFirst().joined(separator: " "))"
}

struct WaiverAdviceBanner: View {
    let advice: WaiverAdvice
    let target: PlayerReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            if let rate = advice.pickupWinRate {
                Text(advice.thisWeekOnly
                     ? "Pickups like this outscored the player they replaced that week \(Int((rate * 100).rounded()))% of the time in 2022–25. A this-week call: holding for the season didn't reliably help."
                     : "Pickups like this beat the player they replaced \(Int((rate * 100).rounded()))% of the time in 2022–25")
                    .font(.caption).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(advice.reason).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var title: String {
        switch advice.action {
        case .replace:
            let who = target.map { " \(shortName($0))" } ?? ""
            let when = advice.thisWeekOnly ? " this week" : ""
            return (advice.strong ? "Replace\(who)\(when) (strong)" : "Replace\(who)\(when)")
        case .watch: return "Watch"
        case .keep: return "Don't replace"
        }
    }

    private var icon: String {
        switch advice.action {
        case .replace: return "arrow.triangle.swap"
        case .watch: return "eye"
        case .keep: return "xmark.circle"
        }
    }

    private var color: Color {
        switch advice.action {
        case .replace: return .green
        case .watch: return .orange
        case .keep: return .secondary
        }
    }
}

/// Per-game defense stats shown on DEF cards, in order of how much they drive a defense's score
/// in this league (2024–25 backtest).
enum DefenseStat: String, CaseIterable, Identifiable {
    /// Fantasy points in this league's scoring. Matchup view only: the season card's Avg already shows it.
    case fantasyPoints = "FPTS"
    case pointsAllowed = "Points allowed"
    case sacks = "Sacks"
    case interceptions = "Interceptions"
    case touchdowns = "TDs"
    case fumbleRecoveries = "Fumble recoveries"

    var id: String { rawValue }

    func value(_ d: DefenseLine) -> Double {
        switch self {
        case .fantasyPoints: return d.fantasyPoints
        case .pointsAllowed: return d.pointsAllowed
        case .sacks: return d.sacks
        case .interceptions: return d.interceptions
        case .touchdowns: return d.touchdowns
        case .fumbleRecoveries: return d.fumbleRecoveries
        }
    }

    /// Fewer points allowed is better; more of everything else is better.
    func isBetter(_ a: Double?, than b: Double?) -> Bool {
        guard let a, let b, a != b else { return false }
        return self == .pointsAllowed ? a < b : a > b
    }
}

enum WaiverMode: String, CaseIterable, Identifiable {
    case season = "Season"
    case upcoming = "Upcoming week"
    var id: String { rawValue }
}

/// Defenses only: for each available defense and for yours, the team it faces this week and what
/// defenses have averaged against that offense so far (over the Games used window).
struct UpcomingWeekSection: View {
    @Environment(AppModel.self) private var model
    let dashboard: Dashboard
    let candidates: [WaiverCandidate]

    private var lastGames: Int? { model.waiverGames == 0 ? nil : model.waiverGames }

    private func matchup(_ team: String) -> Matchup {
        guard let week = dashboard.upcomingWeek, let m = dashboard.matchups else { return .unavailable }
        guard let opponent = m.opponent(of: team, week: week) else { return .bye }
        guard let allowed = m.allowedBy(offense: opponent, lastGames: lastGames) else { return .noGames(opponent) }
        return .game(opponent: opponent, line: allowed.line, games: allowed.games)
    }

    var body: some View {
        let defenses = candidates.filter { $0.player.position == "DEF" }
        // Highest Expected FPTS first (the number the Replace / Watch call uses). Ties go to higher
        // matchup FPTS. Byes and defenses without enough games go last.
        let expected: (WaiverCandidate) -> Double? = { c in
            dashboard.upcomingWeek.flatMap { dashboard.matchups?.expectedFPTS(team: c.player.id, week: $0)?.value }
        }
        let sorted = defenses.sorted { a, b in
            switch (expected(a), expected(b)) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return (matchup(a.player.id).line?.fantasyPoints ?? -.infinity) > (matchup(b.player.id).line?.fantasyPoints ?? -.infinity)
            }
        }
        Section {
            if dashboard.upcomingWeek == nil || dashboard.matchups == nil {
                Text("Matchups show during the regular season, once Sleeper's schedule loads.").foregroundStyle(.secondary)
            } else if sorted.isEmpty {
                Text("No defenses to show right now. If Show trending players only is on, turn it off to see the rest.").foregroundStyle(.secondary)
            }
            ForEach(sorted) { candidate in
                NavigationLink(value: CompareRoute(playerId: candidate.player.id)) {
                    MatchupCard(candidate: candidate, week: dashboard.upcomingWeek ?? 0, matchup: matchup,
                                expected: { team in
                                    dashboard.upcomingWeek.flatMap { dashboard.matchups?.expectedFPTS(team: team, week: $0) }
                                })
                }
            }
        } header: {
            Text("Week \(dashboard.upcomingWeek.map(String.init) ?? "–") defense matchups")
        } footer: {
            Text("For each defense, the offense it faces this week, and what defenses have averaged per game against that offense over its \(model.waiverWindowLabel). FPTS is the fantasy points those defenses scored, with your league's scoring. The Replace / Watch / Don't replace call uses Expected FPTS (whole season, see ⓘ): 4+ higher than your defense is Replace, 4+ lower is Don't replace, in between is Watch. Fewer points allowed and more sacks, interceptions, TDs and fumble recoveries mean an easier matchup; the easier side is green. Sorted by Expected FPTS, highest first.")
        }
    }
}

enum Matchup {
    case game(opponent: String, line: DefenseLine, games: Int)
    case bye
    case noGames(String)
    case unavailable

    var line: DefenseLine? { if case let .game(_, line, _) = self { return line } else { return nil } }

    var heading: String {
        switch self {
        case let .game(opponent, _, _): return "vs \(opponent)"
        case .bye: return "Bye"
        case let .noGames(opponent): return "vs \(opponent)"
        case .unavailable: return "–"
        }
    }
}

struct MatchupCard: View {
    @Environment(AppModel.self) private var model
    let candidate: WaiverCandidate
    let week: Int
    let matchup: (String) -> Matchup
    let expected: (String) -> ExpectedFPTS?

    private var player: PlayerReport { candidate.player }
    private var mine: PlayerReport? {
        RosterLabService.lowestScoring(candidate.myPlayers, metrics: model.waiverMetrics)
    }
    /// Your own data only (no projections): compares Expected FPTS (defense + matchup).
    private func advice(_ theirs: Matchup, _ ours: Matchup?) -> WaiverAdvice? {
        func isBye(_ m: Matchup?) -> Bool { if case .bye = m { return true } else { return false } }
        return WaiverAdvisor.expectedAdvice(pickup: expected(player.id), mine: mine.flatMap { expected($0.id) },
                                            pickupOnBye: isBye(theirs), mineOnBye: isBye(ours),
                                            mineName: mine.map { shortName($0) } ?? "Your defense")
    }

    var body: some View {
        let theirs = matchup(player.id)
        let ours = mine.map { matchup($0.id) }
        let advice = advice(theirs, ours)
        let theirExpected = expected(player.id)
        let ourExpected = mine.flatMap { expected($0.id) }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PositionBadge(position: player.position)
                VStack(alignment: .leading, spacing: 2) {
                    PlayerNameText(player: player, weight: .semibold)
                    Text(candidate.addsLabel)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let advice { WaiverAdviceBanner(advice: advice, target: mine) }
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow {
                    Text("Week \(week)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .gridColumnAlignment(.leading)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Pickup").font(.caption2.weight(.semibold))
                        Text(theirs.heading).font(.caption2).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(mine.map { "Yours: \(shortName($0))" } ?? "Yours").font(.caption2.weight(.semibold)).lineLimit(1)
                        Text(ours?.heading ?? "–").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                // Expected FPTS: own avg + (opponent's allowed avg − league avg), whole season, smoothed.
                GridRow {
                    Text("Expected FPTS").font(.caption.weight(.semibold)).fixedSize()
                    let better = DefenseStat.fantasyPoints.isBetter(theirExpected?.value, than: ourExpected?.value)
                    Text(Fmt.number(theirExpected?.value))
                        .fontWeight(.bold)
                        .foregroundStyle(better ? Color.green : Color.primary)
                    Text(Fmt.number(ourExpected?.value)).fontWeight(.semibold).foregroundStyle(.secondary)
                }
                ForEach(DefenseStat.allCases) { stat in
                    let a = theirs.line.map(stat.value)
                    let b = ours?.line.map(stat.value)
                    let better = stat.isBetter(a, than: b)
                    GridRow {
                        Text(stat.rawValue).font(.caption).foregroundStyle(.secondary).fixedSize()
                        Text(Fmt.number(a))
                            .fontWeight(better ? .bold : .regular)
                            .foregroundStyle(better ? Color.green : Color.primary)
                        Text(Fmt.number(b)).foregroundStyle(.secondary)
                    }
                }
            }
            .font(.subheadline.monospacedDigit())
        }
        .padding(.vertical, 4)
    }
}

/// What the Waivers list can be ranked by. Only stats shown on that position's cards are offered.
/// Raw values match the old Metric names so saved choices carry over.
enum WaiverRank: String, CaseIterable, Identifiable {
    case touches = "Touches + targets"
    case mean = "Avg"
    case ram = "Risk-adj avg"
    case snaps = "Snap share"
    case sortino = "Sortino ratio"
    // Defense cards' per-game stats.
    case pointsAllowed = "Points allowed"
    case sacks = "Sacks"
    case interceptions = "Interceptions"
    case touchdowns = "TDs"
    case fumbleRecoveries = "Fumble recoveries"

    var id: String { rawValue }

    /// Options per position, in the order the cards show them.
    /// - QB: no touches + targets (carries + targets doesn't describe a QB).
    /// - K: no touches or snap share (Sleeper has neither for kickers).
    /// - DEF: the defense per-game stats instead of usage.
    /// - All: every player stat; players without a value go last.
    static func options(for filter: PositionFilter) -> [WaiverRank] {
        switch filter {
        case .rb, .wr, .te, .all: return [.touches, .mean, .ram, .snaps, .sortino]
        case .qb: return [.mean, .ram, .snaps, .sortino]
        case .k: return [.mean, .ram, .sortino]
        case .def: return [.mean, .ram, .sortino, .pointsAllowed, .sacks, .interceptions, .touchdowns, .fumbleRecoveries]
        }
    }

    var higherIsBetter: Bool { self != .pointsAllowed }

    func value(_ m: SeasonMetrics?) -> Double? {
        switch self {
        case .touches: return Metric.touches.value(m)
        case .mean: return Metric.mean.value(m)
        case .ram: return Metric.ram.value(m)
        case .snaps: return Metric.snaps.value(m)
        case .sortino: return Metric.sortino.value(m)
        case .pointsAllowed: return m?.defensePerGame?.pointsAllowed
        case .sacks: return m?.defensePerGame?.sacks
        case .interceptions: return m?.defensePerGame?.interceptions
        case .touchdowns: return m?.defensePerGame?.touchdowns
        case .fumbleRecoveries: return m?.defensePerGame?.fumbleRecoveries
        }
    }
}
