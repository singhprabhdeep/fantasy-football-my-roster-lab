import Foundation

// Decodable shapes for the parts of Sleeper's API the app uses.
// Explicit CodingKeys everywhere: scoring settings and stats are dictionaries
// with snake_case keys that must not be rewritten by a key strategy.

public struct SleeperLeague: Codable, Sendable {
    public let leagueId: String
    public let name: String
    public let season: String
    public let status: String
    public let totalRosters: Int
    public let rosterPositions: [String]
    public let scoringSettings: [String: Double]
    public let previousLeagueId: String?
    public var settings: Settings? = nil

    public struct Settings: Codable, Sendable {
        /// Season FAAB budget per team (0 or missing when the league doesn't use FAAB).
        public let waiverBudget: Int?

        enum CodingKeys: String, CodingKey {
            case waiverBudget = "waiver_budget"
        }
    }

    enum CodingKeys: String, CodingKey {
        case leagueId = "league_id"
        case name, season, status
        case totalRosters = "total_rosters"
        case rosterPositions = "roster_positions"
        case scoringSettings = "scoring_settings"
        case previousLeagueId = "previous_league_id"
        case settings
    }

    public init(leagueId: String, name: String, season: String, status: String, totalRosters: Int,
                rosterPositions: [String], scoringSettings: [String: Double], previousLeagueId: String?) {
        self.leagueId = leagueId
        self.name = name
        self.season = season
        self.status = status
        self.totalRosters = totalRosters
        self.rosterPositions = rosterPositions
        self.scoringSettings = scoringSettings
        self.previousLeagueId = previousLeagueId
    }
}

public struct SleeperUser: Codable, Sendable {
    public let userId: String
    public let displayName: String?
    public let metadata: Metadata?

    public struct Metadata: Codable, Sendable {
        public let teamName: String?

        enum CodingKeys: String, CodingKey {
            case teamName = "team_name"
        }
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case metadata
    }
}

public struct SleeperRoster: Codable, Sendable {
    public let rosterId: Int
    public let ownerId: String?
    public let players: [String]?
    public let starters: [String]?
    public var settings: Settings? = nil

    public struct Settings: Codable, Sendable {
        public let waiverBudgetUsed: Int?
        /// Waiver order; ties on a FAAB bid go to the lower number.
        public let waiverPosition: Int?

        enum CodingKeys: String, CodingKey {
            case waiverBudgetUsed = "waiver_budget_used"
            case waiverPosition = "waiver_position"
        }
    }

    enum CodingKeys: String, CodingKey {
        case rosterId = "roster_id"
        case ownerId = "owner_id"
        case players, starters, settings
    }
}

public struct SleeperMatchup: Codable, Sendable {
    public let rosterId: Int
    public let starters: [String]?
    public let startersPoints: [Double]?

    enum CodingKeys: String, CodingKey {
        case rosterId = "roster_id"
        case starters
        case startersPoints = "starters_points"
    }

    public init(rosterId: Int, starters: [String]?, startersPoints: [Double]?) {
        self.rosterId = rosterId
        self.starters = starters
        self.startersPoints = startersPoints
    }
}

public struct NFLState: Codable, Sendable {
    public let week: Int
    public let season: String
    public let seasonType: String

    enum CodingKeys: String, CodingKey {
        case week, season
        case seasonType = "season_type"
    }
}

public struct TrendingPlayer: Codable, Sendable {
    public let playerId: String
    public let count: Int

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case count
    }
}

public struct PlayerInfo: Codable, Sendable {
    public let fullName: String?
    public let firstName: String?
    public let lastName: String?
    public let position: String?
    public let team: String?
    public let fantasyPositions: [String]?
    /// Jersey number; nil for team defenses and unsigned players.
    public let number: Int?
    /// "Questionable", "Doubtful", "Out", "IR", "PUP", "Sus", ... nil when healthy.
    public let injuryStatus: String?
    public let injuryBodyPart: String?
    public let injuryNotes: String?
    /// 1 = top of the team's depth chart at `depthChartPosition` (RB, LWR, RWR, SWR, TE, QB).
    public let depthChartOrder: Int?
    public let depthChartPosition: String?

    public init(fullName: String? = nil, firstName: String? = nil, lastName: String? = nil, position: String? = nil,
                team: String? = nil, fantasyPositions: [String]? = nil, number: Int? = nil,
                injuryStatus: String? = nil, injuryBodyPart: String? = nil, injuryNotes: String? = nil,
                depthChartOrder: Int? = nil, depthChartPosition: String? = nil) {
        self.fullName = fullName; self.firstName = firstName; self.lastName = lastName
        self.position = position; self.team = team; self.fantasyPositions = fantasyPositions; self.number = number
        self.injuryStatus = injuryStatus; self.injuryBodyPart = injuryBodyPart; self.injuryNotes = injuryNotes
        self.depthChartOrder = depthChartOrder; self.depthChartPosition = depthChartPosition
    }

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case firstName = "first_name"
        case lastName = "last_name"
        case position, team, number
        case fantasyPositions = "fantasy_positions"
        case injuryStatus = "injury_status"
        case injuryBodyPart = "injury_body_part"
        case injuryNotes = "injury_notes"
        case depthChartOrder = "depth_chart_order"
        case depthChartPosition = "depth_chart_position"
    }

    public var displayName: String {
        if let fullName, !fullName.isEmpty { return fullName }
        return [firstName, lastName].compactMap { $0 }.joined(separator: " ")
    }

    public var fantasyPosition: String? {
        position ?? fantasyPositions?.first
    }
}

public struct ScheduleGame: Codable, Sendable {
    public let week: Int
    public let home: String
    public let away: String
    /// "complete" once the game is final.
    public let status: String?

    public init(week: Int, home: String, away: String, status: String? = nil) {
        self.week = week
        self.home = home
        self.away = away
        self.status = status
    }

    public var isComplete: Bool { status == "complete" }
}

/// One week of raw stats: player id -> stat key -> value.
public typealias WeeklyStats = [String: [String: Double]]
