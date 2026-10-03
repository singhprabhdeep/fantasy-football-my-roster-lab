import Foundation

public enum RosterLabError: LocalizedError, Equatable {
    case badResponse(path: String, status: Int)
    case userNotFound(String)
    case rosterNotFound(String)

    public var errorDescription: String? {
        switch self {
        case let .badResponse(path, status):
            return "Sleeper returned an error (\(status)) for \(path). Pull down to try again."
        case let .userNotFound(name):
            return "No Sleeper user named \"\(name)\". Check the spelling (it's your Sleeper username, not your email)."
        case let .rosterNotFound(name):
            return "\(name) doesn't have a team in this league. Use Settings → Change league to pick another."
        }
    }
}

/// How long a cached response stays good.
public enum Freshness: Sendable {
    /// Finished weeks never change.
    case permanent
    case maxAge(TimeInterval)
}

/// All network calls to Sleeper's public, read-only API live here, so a change
/// on Sleeper's side only needs fixing in one file.
public actor SleeperClient {
    private let base = URL(string: "https://api.sleeper.app/v1/")!
    private let session: URLSession
    private let cache: DiskCache
    private let decoder = JSONDecoder()
    /// Demo mode: answer every request from canned responses instead of Sleeper.
    private let fixtures: FixtureStore?

    public init(session: URLSession = .shared, cache: DiskCache = DiskCache(), fixtures: FixtureStore? = nil) {
        self.session = session
        self.cache = cache
        self.fixtures = fixtures
    }

    public nonisolated func clearCache() { cache.clear() }

    /// Returns cached data when fresh; otherwise fetches. If the network fails,
    /// falls back to any cached copy so the app still works offline.
    func data(_ path: String, freshness: Freshness, refresh: Bool = false) async throws -> Data {
        if let fixtures {
            guard let data = fixtures.data(for: path) else { throw RosterLabError.badResponse(path: path, status: 404) }
            return data
        }
        let maxAge: TimeInterval?
        switch freshness {
        case .permanent: maxAge = nil
        case let .maxAge(age): maxAge = refresh ? 0 : age
        }
        if let cached = cache.read(path, maxAge: maxAge) { return cached }

        do {
            // Most calls are relative to api.sleeper.app/v1; the schedule lives on api.sleeper.com.
            guard let url = path.hasPrefix("https://") ? URL(string: path) : URL(string: path, relativeTo: base) else {
                throw RosterLabError.badResponse(path: path, status: 0)
            }
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw RosterLabError.badResponse(path: path, status: status) }
            cache.write(path, data: data)
            return data
        } catch {
            if let stale = cache.read(path, maxAge: nil) { return stale }
            throw error
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ path: String, _ freshness: Freshness, refresh: Bool) async throws -> T {
        try decoder.decode(T.self, from: try await data(path, freshness: freshness, refresh: refresh))
    }

    public func state(refresh: Bool) async throws -> NFLState {
        try await decode(NFLState.self, "state/nfl", .maxAge(3600), refresh: refresh)
    }

    public func league(_ id: String, refresh: Bool) async throws -> SleeperLeague {
        try await decode(SleeperLeague.self, "league/\(id)", .maxAge(3600), refresh: refresh)
    }

    public func rosters(leagueId: String, refresh: Bool) async throws -> [SleeperRoster] {
        // Short cache: lineups change often and the app reloads every time it's opened.
        try await decode([SleeperRoster].self, "league/\(leagueId)/rosters", .maxAge(30), refresh: refresh)
    }

    public func user(_ username: String) async throws -> SleeperUser {
        let data = try await data("user/\(username.lowercased())", freshness: .maxAge(86400 * 7))
        guard let user = try? decoder.decode(SleeperUser.self, from: data) else {
            throw RosterLabError.userNotFound(username)
        }
        return user
    }

    /// A user's NFL leagues for one season, for picking a league at setup.
    public func leagues(userId: String, season: String) async throws -> [SleeperLeague] {
        try await decode([SleeperLeague].self, "user/\(userId)/leagues/nfl/\(season)", .maxAge(0), refresh: true)
    }

    public func users(leagueId: String, refresh: Bool) async throws -> [SleeperUser] {
        try await decode([SleeperUser].self, "league/\(leagueId)/users", .maxAge(86400), refresh: refresh)
    }

    public func matchups(leagueId: String, week: Int, freshness: Freshness) async throws -> [SleeperMatchup] {
        let data = try await data("league/\(leagueId)/matchups/\(week)", freshness: freshness)
        return (try? decoder.decode([SleeperMatchup].self, from: data)) ?? []
    }

    public func stats(season: String, week: Int, freshness: Freshness) async throws -> WeeklyStats {
        let data = try await data("stats/nfl/regular/\(season)/\(week)", freshness: freshness)
        return Self.parseStats(data)
    }

    /// Sleeper's projected stats for a week. They change as news comes in, so re-check hourly.
    public func projections(season: String, week: Int, refresh: Bool) async throws -> WeeklyStats {
        let data = try await data("projections/nfl/regular/\(season)/\(week)", freshness: .maxAge(3600), refresh: refresh)
        return Self.parseStats(data)
    }

    /// NFL regular-season schedule. Undocumented, like the stats endpoints.
    public func schedule(season: String, refresh: Bool) async throws -> [ScheduleGame] {
        try await decode([ScheduleGame].self, "https://api.sleeper.com/schedule/nfl/regular/\(season)",
                         .maxAge(86400), refresh: refresh)
    }

    /// Sleeper returns at most 100 trending players, whatever `limit` or lookback is asked for.
    public func trendingAdds(refresh: Bool, limit: Int = 100) async throws -> [TrendingPlayer] {
        try await decode([TrendingPlayer].self, "players/nfl/trending/add?lookback_hours=24&limit=\(limit)",
                         .maxAge(1800), refresh: refresh)
    }

    /// The full NFL player list is large (several MB), so a slimmed copy is kept. It carries injury
    /// statuses and depth charts, so it's refreshed every 2 hours, or after 10 minutes on a pull-to-refresh.
    public func players(refresh: Bool = false) async throws -> [String: PlayerInfo] {
        // Bump the version when PlayerInfo gains fields so old slimmed copies aren't reused.
        let compactKey = "players-compact-v3"
        if let fixtures {
            return try decoder.decode([String: PlayerInfo].self, from: fixtures.data(for: compactKey) ?? Data("{}".utf8))
        }
        let maxAge: TimeInterval = refresh ? 600 : 7200
        if let compact = cache.read(compactKey, maxAge: maxAge),
           let players = try? decoder.decode([String: PlayerInfo].self, from: compact) {
            return players
        }
        let full = try await data("players/nfl", freshness: .maxAge(maxAge))
        let players = try decoder.decode([String: PlayerInfo].self, from: full)
        if let compact = try? JSONEncoder().encode(players) { cache.write(compactKey, data: compact) }
        return players
    }

    /// Stats values are mostly numbers; anything else is ignored.
    static func parseStats(_ data: Data) -> WeeklyStats {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var result: WeeklyStats = [:]
        result.reserveCapacity(root.count)
        for (playerId, value) in root {
            guard let raw = value as? [String: Any] else { continue }
            var stats: [String: Double] = [:]
            for (key, number) in raw {
                if let n = number as? NSNumber { stats[key] = n.doubleValue }
            }
            result[playerId] = stats
        }
        return result
    }
}
