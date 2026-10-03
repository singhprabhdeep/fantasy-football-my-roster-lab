import Foundation

/// What defenses have done against a team's offense so far: for each game the offense has played,
/// the stats of the defense it faced. Averaged, this says how friendly a matchup is for a defense.
public struct Matchups: Sendable {
    /// week → team → opponent that week.
    public let opponents: [Int: [String: String]]
    /// Completed weeks of this season: week → team defense → its stats that week.
    public let defenseWeeks: [Int: [String: DefenseLine]]

    public init(schedule: [ScheduleGame], defenseWeeks: [Int: [String: DefenseLine]]) {
        var opponents: [Int: [String: String]] = [:]
        for game in schedule {
            opponents[game.week, default: [:]][game.home] = game.away
            opponents[game.week, default: [:]][game.away] = game.home
        }
        self.opponents = opponents
        self.defenseWeeks = defenseWeeks
    }

    public func opponent(of team: String, week: Int) -> String? {
        opponents[week]?[team]
    }

    /// Per-game averages of what defenses have done against `offense`, over its most recent
    /// `lastGames` games (nil = every game so far). Returns nil when it hasn't played yet.
    public func allowedBy(offense: String, lastGames: Int?) -> (line: DefenseLine, games: Int)? {
        var lines: [DefenseLine] = []
        for week in defenseWeeks.keys.sorted() {
            guard let defense = opponent(of: offense, week: week),
                  let line = defenseWeeks[week]?[defense] else { continue }
            lines.append(line)
        }
        if let lastGames, lastGames < lines.count { lines = Array(lines.suffix(lastGames)) }
        guard let average = DefenseLine.average(lines) else { return nil }
        return (average, lines.count)
    }

    // MARK: Expected FPTS

    /// Average fantasy points of every defense in every finished week so far.
    public var leagueAverageFPTS: Double? {
        let all = defenseWeeks.values.flatMap { $0.values.map(\.fantasyPoints) }
        return all.isEmpty ? nil : all.reduce(0, +) / Double(all.count)
    }

    /// A defense's own fantasy points in each game it played, oldest first.
    public func ownFPTS(_ team: String) -> [Double] {
        defenseWeeks.keys.sorted().compactMap { defenseWeeks[$0]?[team]?.fantasyPoints }
    }

    /// Fantasy points that defenses scored against `offense` in each of its games, oldest first.
    public func allowedFPTS(_ offense: String) -> [Double] {
        defenseWeeks.keys.sorted().compactMap { week in
            opponent(of: offense, week: week).flatMap { defenseWeeks[week]?[$0]?.fantasyPoints }
        }
    }

    /// Expected FPTS this week = own avg + (opponent's allowed avg − league avg), over the whole
    /// season so far, with each average pulled toward the league average as if it had
    /// `smoothingGames` extra games at that average. Equal weight on the defense and the matchup.
    /// Chosen in the 2024–25 backtest (research/def_expected_backtest.py) over other weights and
    /// windows; the last-2-games window did much worse, so this always uses the whole season.
    /// 2022–23 kept the order (Replace > Watch > Don't replace) but with a much smaller edge.
    public func expectedFPTS(team: String, week: Int, smoothingGames: Double = ExpectedFPTS.smoothingGames) -> ExpectedFPTS? {
        guard let league = leagueAverageFPTS, let opponent = opponent(of: team, week: week) else { return nil }
        let own = ownFPTS(team), allowed = allowedFPTS(opponent)
        guard !own.isEmpty, !allowed.isEmpty else { return nil }
        func smoothed(_ xs: [Double]) -> Double {
            (xs.reduce(0, +) + smoothingGames * league) / (Double(xs.count) + smoothingGames)
        }
        return ExpectedFPTS(opponent: opponent, own: smoothed(own), opponentAllowed: smoothed(allowed), leagueAverage: league)
    }
}

public struct ExpectedFPTS: Sendable, Equatable {
    public static let smoothingGames = 2.0

    public let opponent: String
    /// Smoothed own FPTS per game.
    public let own: Double
    /// Smoothed FPTS per game that defenses scored against this week's opponent.
    public let opponentAllowed: Double
    public let leagueAverage: Double

    public var value: Double { own + (opponentAllowed - leagueAverage) }
}
