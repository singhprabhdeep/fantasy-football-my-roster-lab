import Foundation
import Observation
import RosterLabKit

@MainActor
@Observable
final class AppModel {
    private enum Keys {
        static let leagueId = "leagueId"
        static let username = "username"
        static let k = "riskK"
        // v3: default is the last 2 games (one of the strongest windows in the backtests).
        static let waiverGames = "waiverGamesV3"
        static let useFinishedGames = "useFinishedGames"
        static let demo = "demoMode"
    }

    /// The bundled demo league: a real 10-team half-PPR league, anonymized, frozen going into week 13 of 2025.
    static let demoLeagueId = "demo-2025"
    static let demoUsername = "demo"
    static let demoCaption = "Demo league · going into week 13 of 2025"


    /// Game windows offered on the Waivers tab. 0 means every game this season.
    static let gameWindows = [0, 1, 2, 3, 4, 5, 6, 8, 10, 12]

    var leagueId: String { didSet { UserDefaults.standard.set(leagueId, forKey: Keys.leagueId) } }
    var username: String { didSet { UserDefaults.standard.set(username, forKey: Keys.username) } }
    /// Risk-adjusted mean = mean − k × downside deviation.
    var k: Double { didSet { UserDefaults.standard.set(k, forKey: Keys.k) } }
    /// How many of each player's most recent games the Waivers tab uses. 0 means the whole season.
    var waiverGames: Int { didSet { UserDefaults.standard.set(waiverGames, forKey: Keys.waiverGames) } }
    /// Count this week's games as soon as they're final (player numbers and the Sortino base).
    var useFinishedGames: Bool { didSet { UserDefaults.standard.set(useFinishedGames, forKey: Keys.useFinishedGames) } }
    /// Showing the bundled demo league instead of the user's own.
    private(set) var isDemo: Bool { didSet { UserDefaults.standard.set(isDemo, forKey: Keys.demo) } }

    /// False until the user has picked a league or the demo, which shows the setup screen.
    var isSetUp: Bool { isDemo || (!leagueId.isEmpty && !username.isEmpty) }

    private(set) var dashboard: Dashboard?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let liveService = RosterLabService()
    /// Built on first use: reading the demo file takes a moment.
    private var demoService: RosterLabService?
    private var service: RosterLabService {
        guard isDemo else { return liveService }
        if let demoService { return demoService }
        let store = Bundle.main.url(forResource: "DemoLeague", withExtension: "json").flatMap { try? FixtureStore(url: $0) }
        let made = RosterLabService(client: SleeperClient(fixtures: store))
        demoService = made
        return made
    }

    init() {
        let defaults = UserDefaults.standard
        leagueId = defaults.string(forKey: Keys.leagueId) ?? ""
        username = defaults.string(forKey: Keys.username) ?? ""
        isDemo = defaults.bool(forKey: Keys.demo)
        k = defaults.object(forKey: Keys.k) as? Double ?? 1.0
        waiverGames = defaults.object(forKey: Keys.waiverGames) == nil ? 2 : defaults.integer(forKey: Keys.waiverGames)
        useFinishedGames = defaults.bool(forKey: Keys.useFinishedGames)
    }

    /// Current-season metrics limited to the Waivers tab's game window.
    func waiverMetrics(_ player: PlayerReport) -> SeasonMetrics? {
        player.current(lastGames: waiverGames == 0 ? nil : waiverGames, k: k)
    }

    /// Where a player's risk-adjusted avg ranks among everyone in a league starting lineup at
    /// his position. `windowed` uses the Waivers "Games used" window for him and the pool alike.
    func riskRank(_ player: PlayerReport, windowed: Bool = false) -> StarterRank? {
        guard let dashboard else { return nil }
        let metrics: (PlayerReport) -> SeasonMetrics? = windowed ? waiverMetrics : { $0.current }
        return RosterLabService.riskAdjustedRank(of: player, among: dashboard.leagueStarters(at: player.position),
                                                 metrics: metrics)
    }

    var waiverWindowLabel: String {
        switch waiverGames {
        case 0: return "full \(dashboard?.season ?? "") season"
        case 1: return "last game"
        default: return "last \(waiverGames) games"
        }
    }

    // MARK: Setup

    /// The user's leagues for the setup screen.
    func findLeagues(username: String) async throws -> [SleeperLeague] {
        try await liveService.leagues(username: username)
    }

    func useLeague(_ league: SleeperLeague, username: String) async {
        isDemo = false
        self.username = username.trimmingCharacters(in: .whitespaces)
        leagueId = league.leagueId
        dashboard = nil
        await load(refresh: true)
    }

    func startDemo() async {
        isDemo = true
        dashboard = nil
        await load()
    }

    /// Back to the setup screen to pick another league (or leave the demo).
    func changeLeague() {
        isDemo = false
        leagueId = ""
        dashboard = nil
        errorMessage = nil
    }

    func load(refresh: Bool = false) async {
        guard isSetUp, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let config = isDemo
                ? RosterLabConfig(leagueId: Self.demoLeagueId, username: Self.demoUsername, k: k)
                : RosterLabConfig(leagueId: leagueId.trimmingCharacters(in: .whitespaces),
                                  username: username.trimmingCharacters(in: .whitespaces), k: k,
                                  useFinishedGames: useFinishedGames)
            dashboard = try await service.loadDashboard(config, refresh: refresh)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearCacheAndReload() async {
        service.clearCache()
        await load(refresh: true)
    }
}
