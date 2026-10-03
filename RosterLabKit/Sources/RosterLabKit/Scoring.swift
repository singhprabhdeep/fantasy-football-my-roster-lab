import Foundation

public enum Scoring {
    /// Fantasy points for one player-week: every stat times the league's weight for it.
    /// This reproduces Sleeper's own matchup points exactly for the league's custom scoring.
    public static func points(stats: [String: Double], scoring: [String: Double]) -> Double {
        var total = 0.0
        for (key, value) in stats {
            if let weight = scoring[key] { total += value * weight }
        }
        return (total * 100).rounded() / 100
    }

    public static func played(_ stats: [String: Double]?) -> Bool {
        (stats?["gp"] ?? 0) > 0
    }
}

public enum WeeklyTargets {
    /// Average points scored by all league starters at each position in one week.
    /// FLEX starters count toward their real position. Empty slots ("0") are skipped.
    public static func compute(matchups: [SleeperMatchup], positionOf: (String) -> String?) -> [String: Double] {
        var sums: [String: Double] = [:]
        var counts: [String: Int] = [:]
        var anyPoints = false
        for matchup in matchups {
            guard let starters = matchup.starters, let points = matchup.startersPoints,
                  starters.count == points.count else { continue }
            for (playerId, pts) in zip(starters, points) where playerId != "0" {
                guard let position = positionOf(playerId) else { continue }
                sums[position, default: 0] += pts
                counts[position, default: 0] += 1
                if pts != 0 { anyPoints = true }
            }
        }
        // A week where nobody has scored yet has not been played.
        guard anyPoints else { return [:] }
        return sums.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value / Double(counts[entry.key] ?? 1)
        }
    }
}
