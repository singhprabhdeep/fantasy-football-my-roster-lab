import Foundation

/// The defense stats that drive most of a team defense's score in this league (2024–25:
/// points allowed ~30% of week-to-week swings, sacks ~17%, INTs ~15%, TDs ~15%, fumble recoveries ~10%).
public struct DefenseLine: Sendable, Hashable {
    public let pointsAllowed: Double
    public let sacks: Double
    public let interceptions: Double
    /// Defensive plus special-teams touchdowns (both worth 6 in this league).
    public let touchdowns: Double
    public let fumbleRecoveries: Double
    /// Fantasy points the defense scored, with the league's scoring.
    public let fantasyPoints: Double

    public init(pointsAllowed: Double, sacks: Double, interceptions: Double, touchdowns: Double,
                fumbleRecoveries: Double, fantasyPoints: Double = 0) {
        self.pointsAllowed = pointsAllowed
        self.sacks = sacks
        self.interceptions = interceptions
        self.touchdowns = touchdowns
        self.fumbleRecoveries = fumbleRecoveries
        self.fantasyPoints = fantasyPoints
    }

    public init(stats: [String: Double], scoring: [String: Double]) {
        self.init(pointsAllowed: stats["pts_allow"] ?? 0,
                  sacks: stats["sack"] ?? 0,
                  interceptions: stats["int"] ?? 0,
                  touchdowns: (stats["def_td"] ?? 0) + (stats["def_st_td"] ?? 0),
                  fumbleRecoveries: stats["fum_rec"] ?? 0,
                  fantasyPoints: Scoring.points(stats: stats, scoring: scoring))
    }

    public static func average(_ lines: [DefenseLine]) -> DefenseLine? {
        guard !lines.isEmpty else { return nil }
        let n = Double(lines.count)
        return DefenseLine(pointsAllowed: lines.map(\.pointsAllowed).reduce(0, +) / n,
                           sacks: lines.map(\.sacks).reduce(0, +) / n,
                           interceptions: lines.map(\.interceptions).reduce(0, +) / n,
                           touchdowns: lines.map(\.touchdowns).reduce(0, +) / n,
                           fumbleRecoveries: lines.map(\.fumbleRecoveries).reduce(0, +) / n,
                           fantasyPoints: lines.map(\.fantasyPoints).reduce(0, +) / n)
    }
}

/// A player's score in one week, next to that week's league target for their position.
public struct WeekResult: Sendable, Hashable, Identifiable {
    public var id: Int { week }
    public let week: Int
    public let points: Double
    /// Average points by all league starters at this position that week.
    public let target: Double?
    /// Carries + targets. Nil for QB, K and DEF, where it doesn't describe their role.
    public let opportunities: Double?
    /// Share of the team's offensive snaps, 0–1. Nil when Sleeper has no snap count.
    public let snapShare: Double?
    /// Team defenses only.
    public let defense: DefenseLine?

    public init(week: Int, points: Double, target: Double?, opportunities: Double? = nil, snapShare: Double? = nil,
                defense: DefenseLine? = nil) {
        self.week = week
        self.points = points
        self.target = target
        self.opportunities = opportunities
        self.snapShare = snapShare
        self.defense = defense
    }

    /// Usage for one player-week from raw Sleeper stats.
    public static func usage(stats: [String: Double], position: String) -> (opportunities: Double?, snapShare: Double?) {
        let skill = ["RB", "WR", "TE"].contains(position)
        let opportunities = skill ? (stats["rush_att"] ?? 0) + (stats["rec_tgt"] ?? 0) : nil
        var snapShare: Double?
        if position != "K", position != "DEF", let team = stats["tm_off_snp"], team > 0 {
            snapShare = min(1, (stats["off_snp"] ?? 0) / team)
        }
        return (opportunities, snapShare)
    }
}

public struct SeasonMetrics: Sendable, Identifiable {
    public var id: String { season }
    public let season: String
    public let weeks: [WeekResult]
    public let games: Int
    public let mean: Double
    public let standardDeviation: Double?
    public let coefficientOfVariation: Double?
    public let downsideDeviation: Double?
    /// The Sortino base: the weekly league starter average at this position,
    /// averaged over the weeks this player played.
    public let averageTarget: Double?
    /// Average of (points − target) over weeks that have a target.
    public let averageExcess: Double?
    public let sortino: Double?
    public let riskAdjustedMean: Double?
    public let weeksBelowTarget: Int
    /// Carries + targets per game (RB, WR, TE).
    public let opportunitiesPerGame: Double?
    /// Average share of team offensive snaps, 0–1.
    public let snapShare: Double?
    /// Per-game defense stats (team defenses only).
    public let defensePerGame: DefenseLine?

    /// True when the player has weeks with a target but never fell below it.
    public var hasNoBadWeeks: Bool { downsideDeviation == 0 }
}

public enum MetricsCalculator {
    /// CV is meaningless when the mean is close to zero.
    public static let minimumMeanForCV = 2.0

    public static func season(_ season: String, weeks: [WeekResult], k: Double) -> SeasonMetrics? {
        guard !weeks.isEmpty else { return nil }
        let points = weeks.map(\.points)
        let n = Double(points.count)
        let mean = points.reduce(0, +) / n

        var sd: Double?
        if points.count >= 2 {
            let variance = points.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / (n - 1)
            sd = variance.squareRoot()
        }
        let cv: Double? = sd.flatMap { mean >= minimumMeanForCV ? $0 / mean : nil }

        let targets = weeks.compactMap(\.target)
        let gaps = weeks.compactMap { w in w.target.map { w.points - $0 } }
        var dd: Double?
        var excess: Double?
        var sortino: Double?
        var ram: Double?
        if !gaps.isEmpty {
            let t = Double(gaps.count)
            let downside = gaps.reduce(0) { $0 + min(0, $1) * min(0, $1) } / t
            dd = downside.squareRoot()
            excess = gaps.reduce(0, +) / t
            if let dd, dd > 0, let excess { sortino = excess / dd }
            ram = mean - k * (dd ?? 0)
        }

        return SeasonMetrics(
            season: season,
            weeks: weeks,
            games: weeks.count,
            mean: mean,
            standardDeviation: sd,
            coefficientOfVariation: cv,
            downsideDeviation: dd,
            averageTarget: targets.isEmpty ? nil : targets.reduce(0, +) / Double(targets.count),
            averageExcess: excess,
            sortino: sortino,
            riskAdjustedMean: ram,
            weeksBelowTarget: gaps.filter { $0 < 0 }.count,
            opportunitiesPerGame: average(weeks.compactMap(\.opportunities)),
            snapShare: average(weeks.compactMap(\.snapShare)),
            defensePerGame: DefenseLine.average(weeks.compactMap(\.defense))
        )
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
