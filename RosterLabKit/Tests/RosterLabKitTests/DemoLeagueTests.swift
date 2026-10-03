import XCTest
@testable import RosterLabKit

/// Runs the whole pipeline offline on the bundled demo league (RosterLab/DemoLeague.json), the
/// same snapshot the app's demo mode shows. No network.
final class DemoLeagueTests: XCTestCase {
    private func demoService() throws -> RosterLabService {
        let url = URL(fileURLWithPath: #filePath)   // .../RosterLabKit/Tests/RosterLabKitTests/DemoLeagueTests.swift
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RosterLab/DemoLeague.json")
        return RosterLabService(client: SleeperClient(fixtures: try FixtureStore(url: url)))
    }

    func testDemoLeagueLoadsEndToEnd() async throws {
        let service = try demoService()
        let dash = try await service.loadDashboard(RosterLabConfig(leagueId: "demo-2025", username: "demo", k: 1),
                                                   refresh: false)
        XCTAssertEqual(dash.leagueName, "Demo League")
        XCTAssertEqual(dash.throughWeek, 12, "frozen going into week 13")
        XCTAssertEqual(dash.starters.count, 10)
        XCTAssertEqual(dash.teams.count, 10)
        XCTAssertNotNil(dash.projectionWeek)
        XCTAssertGreaterThan(dash.waivers.count, 100)
        // Two seasons of history for player pages.
        XCTAssertTrue(dash.starters.contains { $0.seasons.count == 2 })
        // FAAB comes through from league and roster settings.
        let faab = try XCTUnwrap(dash.faab)
        XCTAssertEqual(faab.budget, 50)
        // Injuries rebuilt from box scores give at least one available backup a role and a bid.
        let backups = dash.waivers.filter { $0.player.role.map { $0.kind != .lead } == true }
        XCTAssertFalse(backups.isEmpty)
        XCTAssertTrue(backups.contains { FAABAdvisor.advice(for: $0.player, status: faab) != nil })
        // No real manager names: everyone is "You" or "Team N".
        XCTAssertTrue(dash.teams.allSatisfy { $0.managerName == "You" || $0.managerName.hasPrefix("Team ") })
    }
}
