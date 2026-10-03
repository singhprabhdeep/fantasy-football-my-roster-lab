import Foundation

// Injury news and role changes, from Sleeper's player list (injury status, depth chart) and each
// team's usage this season. The role-change weights come from research/vacancy_backtest.py:
// when a team's lead RB/WR/TE missed a game in 2022–25, how much the next man up's usage jumped.

public struct InjuryInfo: Sendable, Equatable {
    public let status: String
    public let bodyPart: String?
    public let notes: String?

    public init?(status: String?, bodyPart: String?, notes: String?) {
        guard let status, !status.isEmpty else { return nil }
        self.status = status
        self.bodyPart = bodyPart
        self.notes = notes
    }

    /// Won't play: Out, IR, PUP, suspended, not active, etc. Doubtful counts too: they rarely play.
    public var isUnavailable: Bool { status != "Questionable" }
    public var isQuestionable: Bool { status == "Questionable" }

    /// "Q", "D", "OUT", "IR", ...
    public var short: String {
        switch status {
        case "Questionable": return "Q"
        case "Doubtful": return "D"
        case "Out": return "OUT"
        default: return status.uppercased()
        }
    }

    /// "Out · Hamstring (Strain)"
    public var detail: String {
        let body = [bodyPart, notes.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
        return body.isEmpty ? status : "\(status) · \(body)"
    }
}

public enum RoleKind: String, Sendable {
    /// Most touches + targets at his position on his team this season, and available.
    case lead = "Lead role"
    /// The lead is out and he's the clear next man up.
    case likelyLead = "Likely lead"
    /// The lead is out and two players are close in usage.
    case committee = "Committee"
}

public struct RoleInfo: Sendable, Equatable {
    public let kind: RoleKind
    /// The lead who is out (for likely lead and committee).
    public let vacatedBy: String?
    public let vacatedStatus: String?
    /// Role-adjusted touches + targets next game (likely lead only).
    public let expectedTouches: Double?
    /// Role-adjusted half-PPR points next game (likely lead only).
    public let expectedPoints: Double?
}

public enum RoleModel {
    /// expected touches = w × his last-2-game touches + (1 − w) × the lead's touches per game.
    /// Fitted on 2022–25 vacancy games (RB n=131, WR n=115, TE n=131). RBs take over much of the
    /// lead's workload (w 0.43: +5.4 touches, +4.5 pts on average); WRs and TEs much less.
    public static let weight: [String: Double] = ["RB": 0.43, "WR": 0.69, "TE": 0.55]
    /// Half-PPR points per touch + target in those backups' games before the vacancy.
    public static let pointsPerTouch: [String: Double] = ["RB": 0.74, "WR": 1.33, "TE": 1.31]
    /// A player's own points per touch is pulled toward his position's with this many touches.
    public static let smoothingTouches = 6.0
    /// Two backups within this share of each other's usage split the work.
    public static let committeeRatio = 0.75

    public struct Usage: Sendable {
        public let id: String
        public let name: String
        public let team: String
        public let position: String
        public let games: Int
        public let touchesPerGame: Double
        public let recentTouches: Double
        public let recentPoints: Double
        public let unavailable: Bool
        public let injuryStatus: String?

        public init(id: String, name: String, team: String, position: String, games: Int, touchesPerGame: Double,
                    recentTouches: Double, recentPoints: Double, unavailable: Bool, injuryStatus: String?) {
            self.id = id; self.name = name; self.team = team; self.position = position; self.games = games
            self.touchesPerGame = touchesPerGame; self.recentTouches = recentTouches; self.recentPoints = recentPoints
            self.unavailable = unavailable; self.injuryStatus = injuryStatus
        }
    }

    /// Roles for every RB/WR/TE with 2+ games this season, grouped by team and position.
    public static func roles(_ usage: [Usage]) -> [String: RoleInfo] {
        var result: [String: RoleInfo] = [:]
        let groups = Dictionary(grouping: usage.filter { $0.games >= 2 && weight[$0.position] != nil }) { "\($0.team)|\($0.position)" }
        for members in groups.values {
            let ranked = members.sorted { $0.touchesPerGame > $1.touchesPerGame }
            guard let lead = ranked.first else { continue }
            if !lead.unavailable {
                result[lead.id] = RoleInfo(kind: .lead, vacatedBy: nil, vacatedStatus: nil, expectedTouches: nil, expectedPoints: nil)
                continue
            }
            let next = ranked.dropFirst().filter { !$0.unavailable }
            guard let first = next.first else { continue }
            if next.count > 1, next[next.startIndex + 1].touchesPerGame >= committeeRatio * first.touchesPerGame {
                for p in next.prefix(2) {
                    result[p.id] = RoleInfo(kind: .committee, vacatedBy: lead.name, vacatedStatus: lead.injuryStatus,
                                            expectedTouches: nil, expectedPoints: nil)
                }
            } else {
                let expected = expectedTouches(own: first.recentTouches, leadTouches: lead.touchesPerGame, position: first.position)
                result[first.id] = RoleInfo(kind: .likelyLead, vacatedBy: lead.name, vacatedStatus: lead.injuryStatus,
                                            expectedTouches: expected,
                                            expectedPoints: expected * pointsPerTouch(recentPoints: first.recentPoints,
                                                                                      recentTouches: first.recentTouches,
                                                                                      position: first.position))
            }
        }
        return result
    }

    public static func expectedTouches(own: Double, leadTouches: Double, position: String) -> Double {
        let w = weight[position] ?? 1
        return w * own + (1 - w) * leadTouches
    }

    public static func pointsPerTouch(recentPoints: Double, recentTouches: Double, position: String) -> Double {
        let base = pointsPerTouch[position] ?? 1
        return (recentPoints + smoothingTouches * base) / (recentTouches + smoothingTouches)
    }
}
