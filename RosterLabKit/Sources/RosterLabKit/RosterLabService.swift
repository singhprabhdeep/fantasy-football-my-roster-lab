import Foundation

/// One season of league data: every completed week's NFL stats plus the league's
/// weekly starter average at each position.
public struct SeasonData: Sendable {
    public struct Week: Sendable {
        public let stats: WeeklyStats
        public let targets: [String: Double]
    }

    public let season: String
    public let scoring: [String: Double]
    public let weeks: [Int: Week]

    public init(season: String, scoring: [String: Double], weeks: [Int: Week]) {
        self.season = season
        self.scoring = scoring
        self.weeks = weeks
    }

    /// Weeks the player actually played, scored with this season's league rules.
    public func results(playerId: String, position: String) -> [WeekResult] {
        weeks.keys.sorted().compactMap { week in
            guard let data = weeks[week], let stats = data.stats[playerId], Scoring.played(stats) else { return nil }
            let usage = WeekResult.usage(stats: stats, position: position)
            return WeekResult(week: week,
                              points: Scoring.points(stats: stats, scoring: scoring),
                              target: data.targets[position],
                              opportunities: usage.opportunities,
                              snapShare: usage.snapShare,
                              defense: position == "DEF" ? DefenseLine(stats: stats, scoring: scoring) : nil)
        }
    }
}

public struct PlayerReport: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let position: String
    public let team: String?
    /// Jersey number; nil for team defenses and unsigned players.
    public let number: Int?
    /// Sleeper's projected points for the upcoming week, scored with the league's rules.
    /// Nil on a bye, for players Sleeper doesn't project, or outside the regular season.
    public let projection: Double?
    public let currentSeason: String
    /// Newest season first. Seasons with no games are left out.
    public let seasons: [SeasonMetrics]
    /// Sleeper's injury status, nil when healthy.
    public let injury: InjuryInfo?
    /// Lead / likely lead / committee on his team (RB, WR, TE).
    public let role: RoleInfo?

    public init(id: String, name: String, position: String, team: String?, number: Int? = nil,
                projection: Double? = nil, currentSeason: String, seasons: [SeasonMetrics],
                injury: InjuryInfo? = nil, role: RoleInfo? = nil) {
        self.id = id
        self.name = name
        self.position = position
        self.team = team
        self.number = number
        self.projection = projection
        self.currentSeason = currentSeason
        self.seasons = seasons
        self.injury = injury
        self.role = role
    }

    /// Out, IR, Doubtful, suspended...: treated as not playing this week.
    public var isUnavailable: Bool { injury?.isUnavailable ?? false }

    /// "(1) PHI". Defenses show just the team, free agents show "FA".
    public var tagline: String {
        [number.map { "(\($0))" }, team ?? "FA"].compactMap { $0 }.joined(separator: " ")
    }

    /// "Jalen Hurts (1) PHI"
    public var fullLabel: String { "\(name) \(tagline)" }

    public var current: SeasonMetrics? { seasons.first { $0.season == currentSeason } }

    /// Current-season metrics recomputed from only the player's most recent `lastGames` games.
    /// `nil` uses every game this season.
    public func current(lastGames: Int?, k: Double) -> SeasonMetrics? {
        guard let current else { return nil }
        guard let lastGames, lastGames < current.weeks.count else { return current }
        return MetricsCalculator.season(current.season, weeks: Array(current.weeks.suffix(lastGames)), k: k)
    }
    public var isKickerOrDefense: Bool { position == "K" || position == "DEF" }
}

public struct WaiverCandidate: Sendable, Identifiable {
    public var id: String { player.id }
    public let player: PlayerReport
    /// Sleeper adds in the last 24 hours.
    public let adds: Int
    /// My lowest-scoring player at the same position, to compare against.
    public let comparison: PlayerReport?
    /// Every player on my roster at the same position, starters first.
    public let myPlayers: [PlayerReport]
    /// False for players added to fill the list past Sleeper's 100 trending adds.
    public var trending: Bool = true
}

/// A starting lineup added up: the starters' season averages next to the sum of their
/// Sortino bases (what league-average starters at the same spots score).
public struct LineupTotals: Sendable {
    public let startersAvgTotal: Double
    public let baseTotal: Double
    /// Sum of the starters' risk-adjusted averages (avg − k × downside deviation): a downside
    /// estimate of what the lineup scores. A starter with no weeks against a base uses their avg.
    public let riskAdjustedTotal: Double
    /// How much the lineup's weekly total swings: √(sum of each starter's SD²), which treats
    /// starters' weeks as independent. Starters with one game (no SD yet) add nothing.
    public let standardDeviation: Double
    /// Starters with at least one game this season; the rest aren't in the totals.
    public let countedStarters: Int
    public let totalStarters: Int

    public var difference: Double { startersAvgTotal - baseTotal }

    public init(starters: [PlayerReport]) {
        let counted = starters.compactMap(\.current)
        startersAvgTotal = counted.reduce(0) { $0 + $1.mean }
        baseTotal = counted.compactMap(\.averageTarget).reduce(0, +)
        riskAdjustedTotal = counted.reduce(0) { $0 + ($1.riskAdjustedMean ?? $1.mean) }
        standardDeviation = counted.compactMap(\.standardDeviation).reduce(0) { $0 + $1 * $1 }.squareRoot()
        countedStarters = counted.count
        totalStarters = starters.count
    }
}

/// One team in the league, for the league-wide lineup ranking.
public struct LeagueTeam: Sendable, Identifiable {
    public var id: Int { rosterId }
    public let rosterId: Int
    public let teamName: String
    public let managerName: String
    public let isMine: Bool
    public let starters: [PlayerReport]
    public let totals: LineupTotals
}

/// Where a player's risk-adjusted avg falls among everyone currently in a league starting
/// lineup at the same position.
public struct StarterRank: Sendable, Equatable {
    /// 1 is best. For a player who isn't a starter, this is where he would slot in.
    public let rank: Int
    /// Starters at the position with a risk-adjusted avg.
    public let total: Int
    /// Whether the player is one of those starters.
    public let isStarter: Bool

    /// A non-starter worse than every starter.
    public var isBelowAll: Bool { !isStarter && rank > total }
}

public struct Dashboard: Sendable {
    public let leagueName: String
    public let season: String
    /// Last week included in the numbers (0 before week 1 finishes).
    public let throughWeek: Int
    public let starters: [PlayerReport]
    public let bench: [PlayerReport]
    public let waivers: [WaiverCandidate]
    /// Every team, highest starters avg total first.
    public let teams: [LeagueTeam]
    /// The week `PlayerReport.projection` is for, or nil when there are no projections.
    public let projectionWeek: Int?
    /// The league's starting lineup spots, e.g. QB, RB, RB, WR, WR, TE, FLEX, FLEX, K, DEF.
    public let lineupSlots: [String]
    /// The week being played or about to be played, for matchups. Nil outside the regular season.
    public let upcomingWeek: Int?
    /// Schedule plus every defense's stats so far this season.
    public let matchups: Matchups?
    /// The current week, when some of its finished games are counted (Settings toggle).
    public let inProgressWeek: Int?

    /// Everyone currently in a league starting lineup at this position (FLEX counts by real position).
    public func leagueStarters(at position: String) -> [PlayerReport] {
        teams.flatMap(\.starters).filter { $0.position == position }
    }
    public let loadedAt: Date
    /// My FAAB budget and waiver order, when the league uses FAAB.
    public var faab: FAABStatus? = nil
}

public struct RosterLabConfig: Sendable {
    public var leagueId: String
    public var username: String
    /// Risk-adjusted mean = mean − k × downside deviation.
    public var k: Double
    /// How many earlier seasons of this league to include.
    public var seasonsBack: Int
    /// Count games from the current week as soon as they're final: player numbers and the weekly
    /// Sortino base both use them, and move as more games finish.
    public var useFinishedGames: Bool

    public init(leagueId: String, username: String, k: Double, seasonsBack: Int = 4, useFinishedGames: Bool = false) {
        self.leagueId = leagueId
        self.username = username
        self.k = k
        self.seasonsBack = seasonsBack
        self.useFinishedGames = useFinishedGames
    }
}

public actor RosterLabService {
    static let positions: Set<String> = ["QB", "RB", "WR", "TE", "K", "DEF"]

    private let client: SleeperClient

    public init(client: SleeperClient = SleeperClient()) {
        self.client = client
    }

    public nonisolated func clearCache() { client.clearCache() }

    /// The user's NFL leagues for setup: this season's, or last season's if none exist yet
    /// (before a league renews for the new year). Throws `userNotFound` for an unknown username.
    public func leagues(username: String) async throws -> [SleeperLeague] {
        let user = try await client.user(username.trimmingCharacters(in: .whitespaces))
        let state = try await client.state(refresh: false)
        let current = try await client.leagues(userId: user.userId, season: state.season)
        if !current.isEmpty { return current }
        guard let year = Int(state.season) else { return [] }
        return try await client.leagues(userId: user.userId, season: String(year - 1))
    }

    public func loadDashboard(_ config: RosterLabConfig, refresh: Bool) async throws -> Dashboard {
        async let stateTask = client.state(refresh: refresh)
        async let leagueTask = client.league(config.leagueId, refresh: refresh)
        async let playersTask = client.players(refresh: refresh)
        async let userTask = client.user(config.username)
        async let rostersTask = client.rosters(leagueId: config.leagueId, refresh: refresh)
        async let trendingTask = client.trendingAdds(refresh: refresh)
        async let usersTask = client.users(leagueId: config.leagueId, refresh: refresh)

        let (state, league, players, user, rosters) =
            try await (stateTask, leagueTask, playersTask, userTask, rostersTask)
        let trending = (try? await trendingTask) ?? []
        // Projections for the week being played or about to be played. Best lineup-setter in the
        // 2022–2025 backtests. Missing projections just leave the column blank.
        let projectionWeek: Int? = state.seasonType == "regular" && state.season == league.season ? state.week : nil
        var projected: WeeklyStats = [:]
        if let projectionWeek {
            projected = (try? await client.projections(season: league.season, week: projectionWeek, refresh: refresh)) ?? [:]
        }
        let leagueUsers = (try? await usersTask) ?? []

        guard let mine = rosters.first(where: { $0.ownerId == user.userId }) else {
            throw RosterLabError.rosterNotFound(config.username)
        }

        // Follow the league back through earlier seasons.
        var leagues = [league]
        var previous = league.previousLeagueId
        while leagues.count <= config.seasonsBack, let id = previous, !id.isEmpty, id != "0" {
            guard let older = try? await client.league(id, refresh: false) else { break }
            leagues.append(older)
            previous = older.previousLeagueId
        }

        let positionOf: @Sendable (String) -> String? = { players[$0]?.fantasyPosition }
        let schedule = try? await client.schedule(season: league.season, refresh: refresh)

        // This week's games that are already final, when the setting is on.
        var liveWeek: Int?
        var finishedTeams: Set<String> = []
        if config.useFinishedGames, state.seasonType == "regular", state.season == league.season, let schedule {
            finishedTeams = Set(schedule.filter { $0.week == state.week && $0.isComplete }.flatMap { [$0.home, $0.away] })
            if !finishedTeams.isEmpty { liveWeek = state.week }
        }

        var seasons: [SeasonData] = []
        var throughWeek = 0
        for item in leagues {
            let weeks = Self.completedWeeks(season: item.season, state: state)
            var data = try await loadSeason(item, weeks: weeks, state: state, positionOf: positionOf)
            if item.leagueId == league.leagueId {
                throughWeek = data.weeks.keys.max() ?? 0
                if let liveWeek,
                   let partial = try await loadFinishedGames(item, week: liveWeek, finishedTeams: finishedTeams,
                                                             positionOf: positionOf,
                                                             teamOf: { id in players[id]?.team ?? (positionOf(id) == "DEF" ? id : nil) }) {
                    var weeks = data.weeks
                    weeks[liveWeek] = partial
                    data = SeasonData(season: data.season, scoring: data.scoring, weeks: weeks)
                }
            }
            seasons.append(data)
        }
        let inProgressWeek = seasons.first(where: { $0.season == league.season })?.weeks[liveWeek ?? -1] == nil ? nil : liveWeek

        // Roles: each team's lead RB/WR/TE by usage this season, and who steps up when he's out.
        var roles: [String: RoleInfo] = [:]
        if let current = seasons.first(where: { $0.season == league.season }) {
            let ids = Set(current.weeks.values.flatMap { $0.stats.keys })
            let usage: [RoleModel.Usage] = ids.compactMap { id in
                guard let info = players[id], let team = info.team, let position = info.fantasyPosition,
                      RoleModel.weight[position] != nil else { return nil }
                let weeks = current.results(playerId: id, position: position)
                let touches = weeks.compactMap(\.opportunities)
                guard weeks.count >= 2, !touches.isEmpty else { return nil }
                let recent = Array(weeks.suffix(2))
                let recentTouches = recent.compactMap(\.opportunities)
                let injury = InjuryInfo(status: info.injuryStatus, bodyPart: info.injuryBodyPart, notes: info.injuryNotes)
                return RoleModel.Usage(id: id, name: info.displayName, team: team, position: position, games: weeks.count,
                                       touchesPerGame: touches.reduce(0, +) / Double(touches.count),
                                       recentTouches: recentTouches.reduce(0, +) / Double(max(1, recentTouches.count)),
                                       recentPoints: recent.map(\.points).reduce(0, +) / Double(recent.count),
                                       unavailable: injury?.isUnavailable ?? false, injuryStatus: injury?.status)
            }
            roles = RoleModel.roles(usage)
        }

        func report(_ id: String) -> PlayerReport {
            let info = players[id]
            let position = info?.fantasyPosition ?? "?"
            let metrics = seasons.compactMap { season in
                MetricsCalculator.season(season.season,
                                         weeks: season.results(playerId: id, position: position),
                                         k: config.k)
            }
            let projection = projected[id].flatMap { stats -> Double? in
                // A projection with no games expected (bye, ruled out) isn't a projection of 0 points.
                (stats["gp"] ?? 1) > 0 ? Scoring.points(stats: stats, scoring: league.scoringSettings) : nil
            }
            return PlayerReport(id: id, name: info?.displayName ?? id, position: position,
                                team: info?.team, number: info?.number, projection: projection,
                                currentSeason: league.season, seasons: metrics,
                                injury: InjuryInfo(status: info?.injuryStatus, bodyPart: info?.injuryBodyPart, notes: info?.injuryNotes),
                                role: roles[id])
        }

        let starterIds = (mine.starters ?? []).filter { $0 != "0" }
        let benchIds = (mine.players ?? []).filter { !starterIds.contains($0) }
        let starters = starterIds.map(report)
        let bench = benchIds.map(report).sorted { Self.slotOrder($0.position) < Self.slotOrder($1.position) }

        let rostered = Set(rosters.flatMap { $0.players ?? [] })
        let mineAll = starters + bench
        func candidate(_ player: PlayerReport, adds: Int, trending: Bool) -> WaiverCandidate {
            let mine = mineAll.filter { $0.position == player.position }
            return WaiverCandidate(player: player, adds: adds, comparison: Self.lowestScoring(mine),
                                   myPlayers: mine, trending: trending)
        }
        var waiverList: [WaiverCandidate] = trending.compactMap { trend in
            guard !rostered.contains(trend.playerId),
                  let position = positionOf(trend.playerId), Self.positions.contains(position) else { return nil }
            return candidate(report(trend.playerId), adds: trend.count, trending: true)
        }

        // Sleeper returns at most 100 trending adds, so top the list up with the best available players
        // who played in the latest finished week.
        if let latest = seasons.first(where: { $0.season == league.season })?.weeks[throughWeek] {
            let listed = Set(waiverList.map(\.player.id))
            let pool = latest.stats
                .filter { Scoring.played($0.value) && !rostered.contains($0.key) && !listed.contains($0.key) }
                .compactMap { entry -> PlayerReport? in
                    guard let position = positionOf(entry.key), Self.positions.contains(position) else { return nil }
                    return report(entry.key)
                }
            waiverList += Self.topUp(existing: waiverList.map(\.player), pool: pool, k: config.k)
                .map { candidate($0, adds: 0, trending: false) }
        }
        // Every available backup whose lead is out, so the starter-out filter never misses one.
        let listedNow = Set(waiverList.map(\.player.id))
        waiverList += roles.filter { $0.value.kind != .lead && !rostered.contains($0.key) && !listedNow.contains($0.key) }
            .keys.sorted()
            .map { candidate(report($0), adds: 0, trending: false) }
        let waivers = Self.rankedBySortino(waiverList)

        // Defense matchups: the schedule plus every team defense's stats in this season's finished weeks.
        var matchups: Matchups?
        if let schedule,
           let current = seasons.first(where: { $0.season == league.season }) {
            var defenseWeeks: [Int: [String: DefenseLine]] = [:]
            for (week, data) in current.weeks {
                for (id, stats) in data.stats where positionOf(id) == "DEF" && Scoring.played(stats) {
                    defenseWeeks[week, default: [:]][id] = DefenseLine(stats: stats, scoring: current.scoring)
                }
            }
            matchups = Matchups(schedule: schedule, defenseWeeks: defenseWeeks)
        }

        let usersById = Dictionary(leagueUsers.map { ($0.userId, $0) }, uniquingKeysWith: { a, _ in a })
        let teams = Self.rankedByStartersAvg(rosters.map { roster in
            let owner = roster.ownerId.flatMap { usersById[$0] }
            let manager = owner?.displayName ?? "Team \(roster.rosterId)"
            let teamStarters = roster.rosterId == mine.rosterId
                ? starters
                : (roster.starters ?? []).filter { $0 != "0" }.map(report)
            return LeagueTeam(rosterId: roster.rosterId,
                              teamName: owner?.metadata?.teamName?.trimmingCharacters(in: .whitespaces)
                                .nilIfEmpty ?? manager,
                              managerName: manager,
                              isMine: roster.rosterId == mine.rosterId,
                              starters: teamStarters,
                              totals: LineupTotals(starters: teamStarters))
        })

        return Dashboard(leagueName: league.name.trimmingCharacters(in: .whitespaces),
                         season: league.season, throughWeek: throughWeek,
                         starters: starters, bench: bench, waivers: waivers, teams: teams,
                         projectionWeek: projected.isEmpty ? nil : projectionWeek,
                         lineupSlots: league.rosterPositions.filter { !["BN", "IR", "TAXI"].contains($0) },
                         upcomingWeek: projectionWeek,
                         matchups: matchups,
                         inProgressWeek: inProgressWeek,
                         loadedAt: Date(),
                         faab: (league.settings?.waiverBudget).flatMap { budget in
                             budget > 0 ? FAABStatus(budget: budget,
                                                     remaining: budget - (mine.settings?.waiverBudgetUsed ?? 0),
                                                     waiverPosition: mine.settings?.waiverPosition,
                                                     teams: rosters.count) : nil
                         })
    }

    /// Weeks whose games are over. During the season that is every week before the current one.
    static func completedWeeks(season: String, state: NFLState) -> [Int] {
        guard season == state.season else { return Array(1...18) }
        switch state.seasonType {
        case "regular": return state.week > 1 ? Array(1..<state.week) : []
        case "post": return Array(1...18)
        default: return []
        }
    }

    /// The current week's games that are already final: those players' stats, and a Sortino base
    /// from only the league starters whose games are final. Re-checked every few minutes.
    private func loadFinishedGames(_ league: SleeperLeague, week: Int, finishedTeams: Set<String>,
                                   positionOf: @escaping @Sendable (String) -> String?,
                                   teamOf: @escaping (String) -> String?) async throws -> SeasonData.Week? {
        let freshness = Freshness.maxAge(300)
        let matchups = try await client.matchups(leagueId: league.leagueId, week: week, freshness: freshness)
        let stats = try await client.stats(season: league.season, week: week, freshness: freshness)
        return Self.finishedGamesWeek(matchups: matchups, stats: stats, finishedTeams: finishedTeams,
                                      positionOf: positionOf, teamOf: teamOf)
    }

    /// Keeps only players whose team's game is final, for both their stats and the base.
    static func finishedGamesWeek(matchups: [SleeperMatchup], stats: WeeklyStats, finishedTeams: Set<String>,
                                  positionOf: (String) -> String?, teamOf: (String) -> String?) -> SeasonData.Week? {
        func isFinal(_ id: String) -> Bool { teamOf(id).map(finishedTeams.contains) ?? false }
        let finalStarters = matchups.map { m in
            let pairs = zip(m.starters ?? [], m.startersPoints ?? []).filter { isFinal($0.0) }
            return SleeperMatchup(rosterId: m.rosterId, starters: pairs.map(\.0), startersPoints: pairs.map(\.1))
        }
        let finalStats = stats.filter { isFinal($0.key) }
        guard !finalStats.isEmpty else { return nil }
        return SeasonData.Week(stats: finalStats, targets: WeeklyTargets.compute(matchups: finalStarters, positionOf: positionOf))
    }

    private func loadSeason(_ league: SleeperLeague, weeks: [Int], state: NFLState,
                            positionOf: @escaping @Sendable (String) -> String?) async throws -> SeasonData {
        let isCurrent = league.season == state.season
        let client = self.client
        let loaded = try await withThrowingTaskGroup(of: (Int, SeasonData.Week?).self) { group in
            for week in weeks {
                // The most recent week can still get stat corrections, so re-check it every few hours.
                let freshness: Freshness = isCurrent && week >= state.week - 1 ? .maxAge(6 * 3600) : .permanent
                group.addTask {
                    let matchups = try await client.matchups(leagueId: league.leagueId, week: week, freshness: freshness)
                    let targets = WeeklyTargets.compute(matchups: matchups, positionOf: positionOf)
                    guard !targets.isEmpty else { return (week, nil) }
                    let stats = try await client.stats(season: league.season, week: week, freshness: freshness)
                    return (week, SeasonData.Week(stats: stats, targets: targets))
                }
            }
            var result: [Int: SeasonData.Week] = [:]
            for try await (week, data) in group {
                if let data { result[week] = data }
            }
            return result
        }
        return SeasonData(season: league.season, scoring: league.scoringSettings, weeks: loaded)
    }

    /// The player to compare a waiver pickup against: whoever has the lowest average fantasy
    /// points, starters and bench alike. Players with no games in the window are skipped
    /// unless nobody at the position has played.
    public static func lowestScoring(_ players: [PlayerReport],
                                     metrics: (PlayerReport) -> SeasonMetrics? = { $0.current }) -> PlayerReport? {
        let played = players.filter { metrics($0) != nil }
        guard !played.isEmpty else { return players.first }
        return played.min { (metrics($0)?.mean ?? 0) < (metrics($1)?.mean ?? 0) }
    }

    /// Worst to best by average points (the same measure as `lowestScoring`, so the first player is
    /// the waiver card's "your lowest"). Players with no games in the window go last; ties keep roster order.
    public static func worstToBest(_ players: [PlayerReport],
                                   metrics: (PlayerReport) -> SeasonMetrics? = { $0.current }) -> [PlayerReport] {
        players.enumerated().sorted { a, b in
            switch (metrics(a.element)?.mean, metrics(b.element)?.mean) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    /// Highest current-season Sortino first. Players with no bad weeks yet (infinite Sortino)
    /// go on top; players with no games this season go last. Ties fall back to average points.
    public static func rankedBySortino(_ candidates: [WaiverCandidate],
                                       metrics: (PlayerReport) -> SeasonMetrics? = { $0.current }) -> [WaiverCandidate] {
        func key(_ c: WaiverCandidate) -> Double {
            guard let m = metrics(c.player) else { return -.infinity }
            if m.hasNoBadWeeks { return .infinity }
            return m.sortino ?? -.infinity
        }
        return candidates.sorted { a, b in
            let (ka, kb) = (key(a), key(b))
            if ka != kb { return ka > kb }
            return (metrics(a.player)?.mean ?? -.infinity) > (metrics(b.player)?.mean ?? -.infinity)
        }
    }

    /// Ranks a player's risk-adjusted avg against a pool of starters, using the same metrics
    /// function for everyone (so a "last 3 games" window applies to the pool too).
    public static func riskAdjustedRank(of player: PlayerReport, among pool: [PlayerReport],
                                        metrics: (PlayerReport) -> SeasonMetrics? = { $0.current }) -> StarterRank? {
        guard let value = metrics(player)?.riskAdjustedMean else { return nil }
        let isStarter = pool.contains { $0.id == player.id }
        let others = pool.filter { $0.id != player.id }.compactMap { metrics($0)?.riskAdjustedMean }
        let better = others.filter { $0 > value }.count
        return StarterRank(rank: better + 1, total: others.count + (isStarter ? 1 : 0), isStarter: isStarter)
    }

    /// How many waiver cards each position aims for once the list is topped up (150 in all).
    public static let waiverTargets: [String: Int] = ["QB": 15, "RB": 35, "WR": 45, "TE": 25, "K": 15, "DEF": 15]

    /// Best available non-trending players to fill each position up to its target. RB/WR/TE are ranked
    /// by touches + targets over the last 2 games (the best waiver signal in the 2022–25 backtests),
    /// QB/K/DEF by average over the last 2 games; ties go to the higher season average.
    public static func topUp(existing: [PlayerReport], pool: [PlayerReport], k: Double) -> [PlayerReport] {
        var added: [PlayerReport] = []
        for (position, target) in waiverTargets {
            let need = target - existing.filter { $0.position == position }.count
            guard need > 0 else { continue }
            func key(_ p: PlayerReport) -> (Double, Double) {
                let recent = p.current(lastGames: 2, k: k)
                let primary = ["RB", "WR", "TE"].contains(position) ? recent?.opportunitiesPerGame : recent?.mean
                return (primary ?? -1, p.current?.mean ?? -1)
            }
            // Skip players who can't play (Out, IR, Doubtful): not worth a roster spot this week.
            added += pool.filter { $0.position == position && !$0.isUnavailable }.sorted { key($0) > key($1) }.prefix(need)
        }
        return added
    }

    public static func rankedByStartersAvg(_ teams: [LeagueTeam]) -> [LeagueTeam] {
        teams.sorted { $0.totals.startersAvgTotal > $1.totals.startersAvgTotal }
    }

    static func slotOrder(_ position: String) -> Int {
        ["QB", "RB", "WR", "TE", "K", "DEF"].firstIndex(of: position) ?? 99
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
