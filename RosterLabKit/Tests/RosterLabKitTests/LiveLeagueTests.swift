import XCTest
@testable import RosterLabKit

/// Hits Sleeper for real with your own league. Run with:
/// ROSTERLAB_LEAGUE=<league id> ROSTERLAB_USER=<Sleeper username> swift test --filter LiveLeagueTests
final class LiveLeagueTests: XCTestCase {
    func testLoadsRealLeague() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let leagueId = env["ROSTERLAB_LEAGUE"], let username = env["ROSTERLAB_USER"] else {
            throw XCTSkip("Set ROSTERLAB_LEAGUE and ROSTERLAB_USER to run against a real league")
        }
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("rosterlab-live")
        let service = RosterLabService(client: SleeperClient(cache: DiskCache(directory: cacheDir)))
        let config = RosterLabConfig(leagueId: leagueId, username: username, k: 1, useFinishedGames: true)

        let dash = try await service.loadDashboard(config, refresh: false)
        XCTAssertFalse(dash.starters.isEmpty)

        func line(_ p: PlayerReport) -> String {
            let f = { (v: Double?) in v.map { String(format: "%6.2f", $0) } ?? "     –" }
            let seasons = p.seasons.map { "\($0.season):\($0.games)g μ\(f($0.mean))" }.joined(separator: " ")
            let c = p.current
            return "\(p.position.padding(toLength: 4, withPad: " ", startingAt: 0))\(p.name.padding(toLength: 24, withPad: " ", startingAt: 0)) "
                + "SD\(f(c?.standardDeviation)) CV\(f(c?.coefficientOfVariation)) DD\(f(c?.downsideDeviation)) "
                + "Sort\(f(c?.sortino)) RAM\(f(c?.riskAdjustedMean)) | \(seasons)"
        }
        print("\(dash.leagueName) \(dash.season) through week \(dash.throughWeek)")
        print("projections for week", dash.projectionWeek ?? -1, dash.starters.prefix(4).map { "\($0.name): \($0.projection.map { String(format: "%.1f", $0) } ?? "–")" })
        let advice = LineupAdvisor.advise(starters: dash.starters, bench: dash.bench, slots: dash.lineupSlots)
        for p in dash.starters + dash.bench {
            let a = advice[p.id]
            let roster = Dictionary((dash.starters + dash.bench).map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
            if let a, let id = a.versusId, let other = roster[id] {
                let c = a.favorsThisPlayer ? StatsCheck.compare(pick: p, other: other, k: 1) : StatsCheck.compare(pick: other, other: p, k: 1)
                print("      stats: \(c?.verdict.rawValue ?? "-") \(c?.otherName ?? "") \(c?.favoringOther ?? [])")
            }
            print("   \(p.name): \(a?.action.rawValue ?? "-") \(a?.strength ?? "") \(a?.confidence.map { String(format: "%.0f%%", $0 * 100) } ?? "") vs \(a?.versus ?? "-") proj \(p.projection ?? -1)")
        }
        var counts: [String: Int] = [:]
        for w in dash.waivers {
            let low = RosterLabService.lowestScoring(w.myPlayers) { $0.current(lastGames: 2, k: 1) }
            if let adv = WaiverAdvisor.advise(pickup: w.player, mine: low, k: 1, throughWeek: dash.throughWeek) {
                counts[adv.action.rawValue, default: 0] += 1
                if adv.action != .keep { print("   waiver \(w.player.name) (\(w.player.position)): \(adv.action.rawValue) vs \(low?.name ?? "-") | \(adv.reason)") }
            }
        }
        print("waiver calls:", counts)
        let byPos = Dictionary(grouping: dash.waivers, by: { $0.player.position }).mapValues { ($0.count, $0.filter(\.trending).count) }
        for w in dash.waivers.filter({ !$0.trending && $0.player.position == "RB" }).prefix(3) {
            print("top-up RB:", w.player.name, w.player.current(lastGames: 2, k: 1)?.opportunitiesPerGame ?? -1)
        }
        print("waiver list:", dash.waivers.count, "by position (total, trending):", byPos)
        if let m = dash.matchups, let wk = dash.upcomingWeek, let opp = m.opponent(of: "LV", week: wk) {
            let r = m.allowedBy(offense: opp, lastGames: nil)
            print("matchup: LV vs \(opp) wk \(wk): \(String(describing: r))")
            for team in ["JAX", "SF"] {
                if let o = m.opponent(of: team, week: wk) {
                    print("matchup: \(team) vs \(o): \(String(describing: m.allowedBy(offense: o, lastGames: nil)))")
                    for w in m.defenseWeeks.keys.sorted() {
                        if let d = m.opponent(of: o, week: w), let l = m.defenseWeeks[w]?[d] { print("   wk\(w) \(o) vs \(d): fpts \(l.fantasyPoints)") }
                    }
                }
            }
        } else { print("matchup: none", dash.matchups == nil) }
        for p in dash.starters + dash.bench where p.injury != nil || p.role != nil {
            print("roster:", p.name, p.injury?.detail ?? "-", p.role?.kind.rawValue ?? "-", p.role?.vacatedBy ?? "")
        }
        for w in dash.waivers where w.player.role?.kind == .likelyLead || w.player.role?.kind == .committee {
            print("waiver role:", w.player.name, w.player.position, w.player.role!.kind.rawValue, "for", w.player.role!.vacatedBy ?? "",
                  w.player.role!.expectedTouches.map { String(format: "%.1f touches", $0) } ?? "", w.player.role!.expectedPoints.map { String(format: "%.1f pts", $0) } ?? "")
        }
        print("-- Starters"); dash.starters.forEach { print(line($0)) }
        print("-- Bench"); dash.bench.forEach { print(line($0)) }
        print("-- Waivers")
        for w in dash.waivers.prefix(10) {
            print("+\(w.adds) " + line(w.player) + "  vs \(w.comparison?.name ?? "-")")
        }
        if let first = dash.starters.first?.current {
            print("weeks:", first.weeks.map { "wk\($0.week) \($0.points) vs \($0.target.map { String(format: "%.2f", $0) } ?? "-")" })
        }
    }
}
