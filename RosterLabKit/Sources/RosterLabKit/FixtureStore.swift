import Foundation

/// Canned Sleeper responses keyed by API path, for demo mode. The file is one JSON object mapping
/// each path the app requests (e.g. "league/demo-2025/rosters") to that response, as written by
/// scripts/build_demo_league.py. With a store, `SleeperClient` never touches the network.
public final class FixtureStore: Sendable {
    private let responses: [String: Data]

    public init(url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RosterLabError.badResponse(path: url.lastPathComponent, status: 0)
        }
        var responses: [String: Data] = [:]
        for (path, value) in root {
            responses[path] = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        }
        self.responses = responses
    }

    public func data(for path: String) -> Data? { responses[path] }
}
