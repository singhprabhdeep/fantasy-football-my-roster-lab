import XCTest
@testable import RosterLabKit

final class MetricsTests: XCTestCase {
    func testHandCheckedSeason() throws {
        // Points 10, 20, 30 against a flat target of 15.
        let weeks = [10.0, 20, 30].enumerated().map { WeekResult(week: $0.offset + 1, points: $0.element, target: 15) }
        let m = try XCTUnwrap(MetricsCalculator.season("2026", weeks: weeks, k: 1))

        XCTAssertEqual(m.games, 3)
        XCTAssertEqual(m.mean, 20, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m.standardDeviation), 10, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m.coefficientOfVariation), 0.5, accuracy: 1e-9)
        // Only week 1 is below target: sqrt(5² / 3)
        XCTAssertEqual(try XCTUnwrap(m.downsideDeviation), (25.0 / 3).squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m.averageExcess), 5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m.averageTarget), 15, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m.sortino), 5 / (25.0 / 3).squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m.riskAdjustedMean), 20 - (25.0 / 3).squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(m.weeksBelowTarget, 1)
    }

    func testKScalesRiskAdjustedMean() throws {
        let weeks = [WeekResult(week: 1, points: 5, target: 15), WeekResult(week: 2, points: 25, target: 15)]
        let k1 = try XCTUnwrap(MetricsCalculator.season("2026", weeks: weeks, k: 1).flatMap(\.riskAdjustedMean))
        let k2 = try XCTUnwrap(MetricsCalculator.season("2026", weeks: weeks, k: 2).flatMap(\.riskAdjustedMean))
        let dd = (100.0 / 2).squareRoot()
        XCTAssertEqual(k1, 15 - dd, accuracy: 1e-9)
        XCTAssertEqual(k2, 15 - 2 * dd, accuracy: 1e-9)
    }

    func testNoBadWeeksLeavesSortinoEmpty() throws {
        let weeks = [WeekResult(week: 1, points: 20, target: 10), WeekResult(week: 2, points: 25, target: 10)]
        let m = try XCTUnwrap(MetricsCalculator.season("2026", weeks: weeks, k: 1))
        XCTAssertTrue(m.hasNoBadWeeks)
        XCTAssertNil(m.sortino)
        XCTAssertEqual(try XCTUnwrap(m.riskAdjustedMean), m.mean, accuracy: 1e-9)
    }

    func testSingleGameHasNoSpread() throws {
        let m = try XCTUnwrap(MetricsCalculator.season("2026", weeks: [WeekResult(week: 1, points: 18, target: 12)], k: 1))
        XCTAssertNil(m.standardDeviation)
        XCTAssertNil(m.coefficientOfVariation)
        XCTAssertTrue(m.hasNoBadWeeks)
        XCTAssertNil(m.sortino)
    }

    func testLowMeanSkipsCV() throws {
        let weeks = [WeekResult(week: 1, points: 1, target: 8), WeekResult(week: 2, points: 1.5, target: 8)]
        let m = try XCTUnwrap(MetricsCalculator.season("2026", weeks: weeks, k: 1))
        XCTAssertNotNil(m.standardDeviation)
        XCTAssertNil(m.coefficientOfVariation)
    }

    func testWeeksWithoutTargetStillCountTowardMean() throws {
        let weeks = [WeekResult(week: 1, points: 10, target: nil), WeekResult(week: 2, points: 20, target: 25)]
        let m = try XCTUnwrap(MetricsCalculator.season("2026", weeks: weeks, k: 1))
        XCTAssertEqual(m.mean, 15, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m.downsideDeviation), 5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m.averageTarget), 25, accuracy: 1e-9, "base ignores weeks without a target")
    }

    func testBaseAveragesWeeklyTargets() throws {
        let weeks = [WeekResult(week: 1, points: 10, target: 12), WeekResult(week: 2, points: 20, target: 18)]
        let m = try XCTUnwrap(MetricsCalculator.season("2026", weeks: weeks, k: 1))
        XCTAssertEqual(try XCTUnwrap(m.averageTarget), 15, accuracy: 1e-9)
    }

    func testEmptySeasonIsNil() {
        XCTAssertNil(MetricsCalculator.season("2026", weeks: [], k: 1))
    }
}

final class TargetAndScoringTests: XCTestCase {
    let positions = ["qb1": "QB", "rb1": "RB", "rb2": "RB", "wr1": "WR", "rb3": "RB"]

    func testTargetAveragesStartersByRealPosition() {
        // Team 2 starts a RB at FLEX; it counts toward the RB average.
        let matchups = [
            SleeperMatchup(rosterId: 1, starters: ["qb1", "rb1", "wr1"], startersPoints: [20, 10, 12]),
            SleeperMatchup(rosterId: 2, starters: ["rb2", "rb3", "0"], startersPoints: [14, 6, 0]),
        ]
        let targets = WeeklyTargets.compute(matchups: matchups) { self.positions[$0] }
        XCTAssertEqual(targets["QB"], 20)
        XCTAssertEqual(targets["RB"], 10)
        XCTAssertEqual(targets["WR"], 12)
    }

    func testUnplayedWeekHasNoTarget() {
        let matchups = [SleeperMatchup(rosterId: 1, starters: ["qb1"], startersPoints: [0])]
        XCTAssertTrue(WeeklyTargets.compute(matchups: matchups) { self.positions[$0] }.isEmpty)
    }

    func testScoringUsesLeagueWeights() {
        let scoring = ["rec": 0.5, "rec_yd": 0.1, "rec_td": 6, "fum_lost": -2]
        let stats = ["rec": 6.0, "rec_yd": 83, "rec_td": 1, "fum_lost": 1, "gp": 1, "pts_ppr": 99]
        XCTAssertEqual(Scoring.points(stats: stats, scoring: scoring), 15.3, accuracy: 1e-9)
        XCTAssertTrue(Scoring.played(stats))
        XCTAssertFalse(Scoring.played(["gp": 0]))
        XCTAssertFalse(Scoring.played(nil))
    }

    func testSeasonDataSkipsWeeksNotPlayed() {
        let season = SeasonData(season: "2026", scoring: ["rec": 1], weeks: [
            1: .init(stats: ["p": ["rec": 5, "gp": 1]], targets: ["WR": 4]),
            2: .init(stats: [:], targets: ["WR": 6]),
            3: .init(stats: ["p": ["rec": 2, "gp": 0]], targets: ["WR": 5]),
        ])
        XCTAssertEqual(season.results(playerId: "p", position: "WR"),
                       [WeekResult(week: 1, points: 5, target: 4, opportunities: 0)])
    }

    func testParseStatsIgnoresNonNumbers() {
        let json = #"{"123": {"pts_half_ppr": 12.5, "gp": 1, "note": "x"}, "SEA": {"pts_allow_7_13": 1}}"#
        let stats = SleeperClient.parseStats(Data(json.utf8))
        XCTAssertEqual(stats["123"], ["pts_half_ppr": 12.5, "gp": 1])
        XCTAssertEqual(stats["SEA"]?["pts_allow_7_13"], 1)
    }
}

final class ServiceHelperTests: XCTestCase {
    func testCompletedWeeks() throws {
        let decode = { (json: String) in try JSONDecoder().decode(NFLState.self, from: Data(json.utf8)) }
        let wk3 = try decode(#"{"week":3,"season":"2026","season_type":"regular"}"#)
        XCTAssertEqual(RosterLabService.completedWeeks(season: "2026", state: wk3), [1, 2])
        XCTAssertEqual(RosterLabService.completedWeeks(season: "2025", state: wk3).count, 18)
        let wk1 = try decode(#"{"week":1,"season":"2026","season_type":"regular"}"#)
        XCTAssertEqual(RosterLabService.completedWeeks(season: "2026", state: wk1), [])
    }

    func testLowestScoringIncludesBench() {
        func player(_ id: String, _ pos: String, _ pts: [Double]) -> PlayerReport {
            let weeks = pts.enumerated().map { WeekResult(week: $0.offset + 1, points: $0.element, target: 10) }
            return PlayerReport(id: id, name: id, position: pos, team: nil, currentSeason: "2026",
                                seasons: [MetricsCalculator.season("2026", weeks: weeks, k: 1)!])
        }
        let strong = player("strong", "WR", [20, 22])
        let weak = player("weak", "WR", [8, 12])
        let benchWR = player("bench", "WR", [2, 3])
        let te = player("te", "TE", [5, 6])

        let injured = PlayerReport(id: "injured", name: "injured", position: "WR", team: nil, currentSeason: "2026", seasons: [])

        XCTAssertEqual(RosterLabService.lowestScoring([strong, weak, benchWR, injured])?.id, "bench",
                       "lowest average wins, bench included, players with no games skipped")
        XCTAssertEqual(RosterLabService.lowestScoring([te])?.id, "te")
        XCTAssertEqual(RosterLabService.lowestScoring([injured])?.id, "injured")
        XCTAssertEqual(RosterLabService.worstToBest([strong, injured, weak, benchWR]).map(\.id),
                       ["bench", "weak", "strong", "injured"], "worst average first, no games last")
        XCTAssertNil(RosterLabService.lowestScoring([]))
    }

    func testWaiversRankedBySortino() {
        func candidate(_ id: String, _ pts: [Double]) -> WaiverCandidate {
            let weeks = pts.enumerated().map { WeekResult(week: $0.offset + 1, points: $0.element, target: 10) }
            let seasons = MetricsCalculator.season("2026", weeks: weeks, k: 1).map { [$0] } ?? []
            let player = PlayerReport(id: id, name: id, position: "WR", team: nil, currentSeason: "2026", seasons: seasons)
            return WaiverCandidate(player: player, adds: 1, comparison: nil, myPlayers: [])
        }
        let ranked = RosterLabService.rankedBySortino([
            candidate("noGames", []),
            candidate("mixed", [5, 20]),        // sortino = 2.5 / 3.54 ≈ 0.71
            candidate("neverBelow", [12, 14]),  // no bad weeks -> top
            candidate("bad", [4, 6]),           // sortino = -1
            candidate("mostlyGood", [9, 25]),   // sortino = 7 / 0.71 ≈ 9.9
        ])
        XCTAssertEqual(ranked.map(\.player.id), ["neverBelow", "mostlyGood", "mixed", "bad", "noGames"])
    }

    func testLastGamesWindowUsesMostRecentGames() throws {
        let weeks = [2.0, 4, 20, 22].enumerated().map { WeekResult(week: $0.offset + 1, points: $0.element, target: 10) }
        let player = PlayerReport(id: "p", name: "p", position: "WR", team: nil, currentSeason: "2026",
                                  seasons: [MetricsCalculator.season("2026", weeks: weeks, k: 1)!])
        let last2 = try XCTUnwrap(player.current(lastGames: 2, k: 1))
        XCTAssertEqual(last2.games, 2)
        XCTAssertEqual(last2.mean, 21, accuracy: 1e-9)
        XCTAssertTrue(last2.hasNoBadWeeks, "the trend only shows in the recent window")
        XCTAssertEqual(try XCTUnwrap(player.current(lastGames: nil, k: 1)).games, 4)
        XCTAssertEqual(try XCTUnwrap(player.current(lastGames: 8, k: 1)).games, 4, "window larger than games played uses them all")
    }

    func testLineupTotalsAndRanking() {
        func player(_ id: String, _ weeks: [(Double, Double)]) -> PlayerReport {
            let results = weeks.enumerated().map { WeekResult(week: $0.offset + 1, points: $0.element.0, target: $0.element.1) }
            let seasons = MetricsCalculator.season("2026", weeks: results, k: 1).map { [$0] } ?? []
            return PlayerReport(id: id, name: id, position: "WR", team: nil, currentSeason: "2026", seasons: seasons)
        }
        // a: avg 15, base 12. b: avg 8, base 10. c: no games, left out.
        let totals = LineupTotals(starters: [player("a", [(10, 11), (20, 13)]), player("b", [(8, 10)]), player("c", [])])
        XCTAssertEqual(totals.startersAvgTotal, 23, accuracy: 1e-9)
        XCTAssertEqual(totals.baseTotal, 22, accuracy: 1e-9)
        XCTAssertEqual(totals.difference, 1, accuracy: 1e-9)
        // a: DD = sqrt(1²/2) → RAM 15 − 0.7071; b: DD = 2 → RAM 6
        XCTAssertEqual(totals.riskAdjustedTotal, 15 - (0.5).squareRoot() + 6, accuracy: 1e-9)
        // Only a has an SD (√50); b has one game.
        XCTAssertEqual(totals.standardDeviation, (50.0).squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(totals.countedStarters, 2)
        XCTAssertEqual(totals.totalStarters, 3)

        func team(_ id: Int, _ starters: [PlayerReport]) -> LeagueTeam {
            LeagueTeam(rosterId: id, teamName: "\(id)", managerName: "\(id)", isMine: false,
                       starters: starters, totals: LineupTotals(starters: starters))
        }
        let ranked = RosterLabService.rankedByStartersAvg([
            team(1, [player("x", [(5, 10)])]),
            team(2, [player("y", [(30, 10)])]),
            team(3, [player("z", [(12, 10)])]),
        ])
        XCTAssertEqual(ranked.map(\.rosterId), [2, 3, 1])
    }

    func testPlayerLabels() {
        let hurts = PlayerReport(id: "6904", name: "Jalen Hurts", position: "QB", team: "PHI", number: 1,
                                 currentSeason: "2026", seasons: [])
        XCTAssertEqual(hurts.fullLabel, "Jalen Hurts (1) PHI")
        let niners = PlayerReport(id: "SF", name: "San Francisco 49ers", position: "DEF", team: "SF",
                                  currentSeason: "2026", seasons: [])
        XCTAssertEqual(niners.fullLabel, "San Francisco 49ers SF")
        let freeAgent = PlayerReport(id: "x", name: "Tyreek Hill", position: "WR", team: nil, number: 10,
                                     currentSeason: "2026", seasons: [])
        XCTAssertEqual(freeAgent.tagline, "(10) FA")
    }

    func testPlayerInfoDecodesNumber() throws {
        let json = #"{"6904": {"full_name": "Jalen Hurts", "position": "QB", "team": "PHI", "number": 1}, "SF": {"first_name": "San Francisco", "last_name": "49ers", "position": "DEF", "team": "SF", "number": null}}"#
        let players = try JSONDecoder().decode([String: PlayerInfo].self, from: Data(json.utf8))
        XCTAssertEqual(players["6904"]?.number, 1)
        XCTAssertNil(players["SF"]?.number)
    }

    func testRiskAdjustedRankAmongStarters() {
        func wr(_ id: String, _ pts: Double) -> PlayerReport {
            // One week against a base of 10: RAM = pts when pts ≥ 10, else pts − (10 − pts).
            let season = MetricsCalculator.season("2026", weeks: [WeekResult(week: 1, points: pts, target: 10)], k: 1)!
            return PlayerReport(id: id, name: id, position: "WR", team: nil, currentSeason: "2026", seasons: [season])
        }
        let pool = [wr("a", 30), wr("b", 20), wr("c", 12), wr("d", 8)]  // RAM 30, 20, 12, 6

        XCTAssertEqual(RosterLabService.riskAdjustedRank(of: pool[2], among: pool),
                       StarterRank(rank: 3, total: 4, isStarter: true))
        let bench = RosterLabService.riskAdjustedRank(of: wr("bench", 15), among: pool)
        XCTAssertEqual(bench, StarterRank(rank: 3, total: 4, isStarter: false), "would slot in 3rd")
        let awful = RosterLabService.riskAdjustedRank(of: wr("awful", 2), among: pool)!  // RAM −6
        XCTAssertTrue(awful.isBelowAll)
        XCTAssertNil(RosterLabService.riskAdjustedRank(
            of: PlayerReport(id: "x", name: "x", position: "WR", team: nil, currentSeason: "2026", seasons: []), among: pool))
    }

    func testUsageStats() throws {
        let wr = WeekResult.usage(stats: ["rec_tgt": 9, "off_snp": 52, "tm_off_snp": 65], position: "WR")
        XCTAssertEqual(wr.opportunities, 9)
        XCTAssertEqual(try XCTUnwrap(wr.snapShare), 0.8, accuracy: 1e-9)
        let rb = WeekResult.usage(stats: ["rush_att": 14, "rec_tgt": 3], position: "RB")
        XCTAssertEqual(rb.opportunities, 17)
        XCTAssertNil(rb.snapShare, "no snap counts")
        let qb = WeekResult.usage(stats: ["rush_att": 5, "off_snp": 76, "tm_off_snp": 76], position: "QB")
        XCTAssertNil(qb.opportunities)
        XCTAssertEqual(qb.snapShare, 1)
        XCTAssertNil(WeekResult.usage(stats: ["off_snp": 0, "tm_off_snp": 60], position: "DEF").snapShare)

        // Averages follow the game window.
        let weeks = [WeekResult(week: 1, points: 5, target: 10, opportunities: 4, snapShare: 0.3),
                     WeekResult(week: 2, points: 9, target: 10, opportunities: 8, snapShare: 0.5),
                     WeekResult(week: 3, points: 14, target: 10, opportunities: 12, snapShare: 0.7)]
        let player = PlayerReport(id: "p", name: "p", position: "WR", team: nil, currentSeason: "2026",
                                  seasons: [MetricsCalculator.season("2026", weeks: weeks, k: 1)!])
        XCTAssertEqual(try XCTUnwrap(player.current?.opportunitiesPerGame), 8, accuracy: 1e-9)
        let last2 = try XCTUnwrap(player.current(lastGames: 2, k: 1))
        XCTAssertEqual(try XCTUnwrap(last2.opportunitiesPerGame), 10, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(last2.snapShare), 0.6, accuracy: 1e-9)
    }

    // MARK: Recommendations

    private func player(_ id: String, _ pos: String, proj: Double?, points: [Double] = [10, 10],
                        touches: [Double] = [6, 6]) -> PlayerReport {
        let weeks = points.enumerated().map {
            WeekResult(week: $0.offset + 1, points: $0.element, target: 10,
                       opportunities: touches[$0.offset], snapShare: 0.5)
        }
        return PlayerReport(id: id, name: id, position: pos, team: nil, projection: proj, currentSeason: "2026",
                            seasons: [MetricsCalculator.season("2026", weeks: weeks, k: 1)!])
    }

    func testStartSitConfidenceMatchesBacktestTable() {
        // Two WRs 4 points apart: the 2025 table had 65% for a 3–5 point gap.
        let c = LineupAdvisor.confidence(projectionGap: 4, positions: "WR", "WR")
        XCTAssertEqual(c, 0.66, accuracy: 0.02)
        XCTAssertEqual(LineupAdvisor.confidence(projectionGap: 0, positions: "RB", "WR"), 0.5, accuracy: 1e-9)
        XCTAssertEqual(LineupAdvisor.confidence(projectionGap: 40, positions: "RB", "RB"), 0.85, "capped")
    }

    func testStartSitSwapsBenchPlayerIntoFlex() {
        let slots = ["QB", "RB", "WR", "FLEX"]
        let qb = player("qb", "QB", proj: 20)
        let rb1 = player("rb1", "RB", proj: 14)
        let wr1 = player("wr1", "WR", proj: 12)
        let flexStarter = player("te", "TE", proj: 5)
        let benchRB = player("rb2", "RB", proj: 11)
        let byeWR = player("wr2", "WR", proj: nil)
        let advice = LineupAdvisor.advise(starters: [qb, rb1, wr1, flexStarter], bench: [benchRB, byeWR], slots: slots)

        XCTAssertEqual(advice["rb2"]?.action, .moveToStarter)
        XCTAssertEqual(advice["te"]?.action, .moveToBench)
        XCTAssertEqual(advice["te"]?.versus, "rb2")
        XCTAssertEqual(advice["rb2"]?.versus, "te", "names the starter he replaces")
        XCTAssertEqual(advice["rb2"]?.confidence, advice["te"]?.confidence)
        XCTAssertEqual(advice["qb"]?.action, .keepStarting)
        XCTAssertNil(advice["qb"]?.confidence, "no other QB")
        XCTAssertEqual(advice["wr2"]?.action, .keepOnBench)
        XCTAssertEqual(advice["wr2"]?.unavailable, true)
        XCTAssertEqual(advice["rb2"]?.strength, "Strong", "6-point gap: about 74%, like the 72% for 5–8 points in 2025")
    }

    func testWaiverAdvice() throws {
        let mine = player("mine", "WR", proj: 6, points: [4, 5], touches: [4, 5])
        let strong = player("hot", "WR", proj: 10, points: [8, 9], touches: [9, 10])
        let a = try XCTUnwrap(WaiverAdvisor.advise(pickup: strong, mine: mine, k: 1, throughWeek: 2))
        XCTAssertEqual(a.action, .replace)
        XCTAssertTrue(a.strong)

        let usageOnly = player("usage", "WR", proj: 6.5, points: [3, 4], touches: [9, 9])
        XCTAssertEqual(WaiverAdvisor.advise(pickup: usageOnly, mine: mine, k: 1, throughWeek: 2)?.action, .watch)

        let weak = player("weak", "WR", proj: 5, points: [12, 2], touches: [3, 4])
        XCTAssertEqual(WaiverAdvisor.advise(pickup: weak, mine: mine, k: 1, throughWeek: 2)?.action, .keep)

        // Didn't play the latest week: capped at Watch.
        XCTAssertEqual(WaiverAdvisor.advise(pickup: strong, mine: mine, k: 1, throughWeek: 3)?.action, .watch)

        // Kickers: projections too close together to beat a healthy kicker; replace only on a bye.
        let k1 = player("k", "K", proj: 9)
        XCTAssertEqual(WaiverAdvisor.advise(pickup: k1, mine: player("k2", "K", proj: 7), k: 1, throughWeek: 2)?.action, .watch)
        XCTAssertEqual(WaiverAdvisor.advise(pickup: k1, mine: player("k3", "K", proj: 8.5), k: 1, throughWeek: 2)?.action, .keep)
        let byeK = try XCTUnwrap(WaiverAdvisor.advise(pickup: k1, mine: player("k4", "K", proj: nil), k: 1, throughWeek: 2))
        XCTAssertEqual(byeK.action, .replace)
        XCTAssertTrue(byeK.thisWeekOnly)

        // Defenses: this week's projection gap.
        let d1 = player("d1", "DEF", proj: 9)
        XCTAssertEqual(WaiverAdvisor.advise(pickup: d1, mine: player("d2", "DEF", proj: 6.5), k: 1, throughWeek: 2)?.strong, true)
        XCTAssertEqual(WaiverAdvisor.advise(pickup: d1, mine: player("d3", "DEF", proj: 7.5), k: 1, throughWeek: 2)?.action, .replace)
        XCTAssertEqual(WaiverAdvisor.advise(pickup: d1, mine: player("d4", "DEF", proj: 8.5), k: 1, throughWeek: 2)?.action, .watch)
        XCTAssertEqual(WaiverAdvisor.advise(pickup: d1, mine: player("d5", "DEF", proj: 10), k: 1, throughWeek: 2)?.action, .keep)
    }

    func testStatsCheck() throws {
        let pick = player("pick", "WR", proj: 12, points: [6, 7], touches: [5, 5])
        let other = player("other", "WR", proj: 9, points: [14, 16], touches: [9, 10])
        let against = try XCTUnwrap(StatsCheck.compare(pick: pick, other: other, k: 1))
        XCTAssertEqual(against.verdict, .disagree)
        XCTAssertEqual(against.favoringOther.count, 4)

        let agrees = try XCTUnwrap(StatsCheck.compare(pick: other, other: pick, k: 1))
        XCTAssertEqual(agrees.verdict, .agree)

        let mixed = player("mixed", "WR", proj: 9, points: [4, 5], touches: [9, 10])
        XCTAssertEqual(StatsCheck.compare(pick: pick, other: mixed, k: 1)?.verdict, .split)
        XCTAssertEqual(StatsCheck.compare(pick: pick, other: mixed, k: 1)?.favoringOther, ["more touches + targets"])
    }

    func testKeepCallsCompareWithPlayersWhoArentMoving() {
        let wr1 = player("wr1", "WR", proj: 12), wr2 = player("wr2", "WR", proj: 10)
        let wr3 = player("wr3", "WR", proj: 11), wr4 = player("wr4", "WR", proj: 9)
        let advice = LineupAdvisor.advise(starters: [wr1, wr2], bench: [wr3, wr4], slots: ["WR", "FLEX"])
        XCTAssertEqual(advice["wr3"]?.action, .moveToStarter)
        XCTAssertEqual(advice["wr3"]?.versus, "wr2")
        XCTAssertEqual(advice["wr1"]?.action, .keepStarting)
        XCTAssertEqual(advice["wr1"]?.versus, "wr4", "not wr2, who is a starter being benched")
        XCTAssertEqual(advice["wr4"]?.action, .keepOnBench)
        XCTAssertEqual(advice["wr4"]?.versus, "wr1", "not wr3, who is a bench player moving in")
    }

    func testDefensePerGame() throws {
        let season = SeasonData(season: "2026", scoring: ["sack": 1, "int": 2], weeks: [
            1: .init(stats: ["SF": ["gp": 1, "pts_allow": 17, "sack": 3, "int": 1, "def_td": 1, "fum_rec": 0]], targets: ["DEF": 7]),
            2: .init(stats: ["SF": ["gp": 1, "pts_allow": 27, "sack": 1, "int": 0, "def_st_td": 1, "fum_rec": 2]], targets: ["DEF": 7]),
        ])
        let weeks = season.results(playerId: "SF", position: "DEF")
        let m = try XCTUnwrap(MetricsCalculator.season("2026", weeks: weeks, k: 1))
        let d = try XCTUnwrap(m.defensePerGame)
        XCTAssertEqual(d.pointsAllowed, 22)
        XCTAssertEqual(d.sacks, 2)
        XCTAssertEqual(d.interceptions, 0.5)
        XCTAssertEqual(d.touchdowns, 1, "defensive + special-teams TDs")
        XCTAssertEqual(d.fumbleRecoveries, 1)
        XCTAssertEqual(d.fantasyPoints, 3, "sack 1, int 2: week 1 = 3 + 2, week 2 = 1")
        XCTAssertNil(season.results(playerId: "SF", position: "WR").first?.defense)
    }

    func testMatchupsAverageWhatDefensesDidAgainstAnOffense() throws {
        // NO played DET in week 1 and BAL in week 2; LV plays NO in week 3.
        let schedule = [ScheduleGame(week: 1, home: "DET", away: "NO"), ScheduleGame(week: 2, home: "NO", away: "BAL"),
                        ScheduleGame(week: 3, home: "LV", away: "NO")]
        let weeks: [Int: [String: DefenseLine]] = [
            1: ["DET": DefenseLine(pointsAllowed: 30, sacks: 5, interceptions: 2, touchdowns: 0, fumbleRecoveries: 1, fantasyPoints: 10)],
            2: ["BAL": DefenseLine(pointsAllowed: 24, sacks: 3, interceptions: 0, touchdowns: 0, fumbleRecoveries: 0, fantasyPoints: 3)],
        ]
        let m = Matchups(schedule: schedule, defenseWeeks: weeks)
        XCTAssertEqual(m.opponent(of: "LV", week: 3), "NO")
        let all = try XCTUnwrap(m.allowedBy(offense: "NO", lastGames: nil))
        XCTAssertEqual(all.games, 2)
        XCTAssertEqual(all.line.pointsAllowed, 27)
        XCTAssertEqual(all.line.sacks, 4)
        XCTAssertEqual(all.line.interceptions, 1)
        XCTAssertEqual(all.line.fumbleRecoveries, 0.5)
        XCTAssertEqual(all.line.fantasyPoints, 6.5)
        XCTAssertEqual(m.allowedBy(offense: "NO", lastGames: 1)?.line.pointsAllowed, 24, "most recent game only")
        XCTAssertNil(m.allowedBy(offense: "LV", lastGames: nil))
        XCTAssertNil(m.opponent(of: "SF", week: 3), "bye")
    }

    func testMatchupFPTSDefenseCalls() {
        func call(_ a: Double?, _ b: Double?, pickupBye: Bool = false, mineBye: Bool = false) -> WaiverAction? {
            WaiverAdvisor.matchupAdvice(pickupFPTS: a, mineFPTS: b, pickupOnBye: pickupBye, mineOnBye: mineBye,
                                        mineName: "SF", gamesUsed: 0)?.action
        }
        XCTAssertEqual(call(14.5, 4.5), .replace)
        XCTAssertEqual(call(6.0, 4.5), .watch)
        XCTAssertEqual(call(3.0, 4.5), .watch)
        XCTAssertEqual(call(2.0, 4.5), .keep)
        XCTAssertEqual(call(nil, 4.5, mineBye: true), .replace)
        XCTAssertEqual(call(9, 4.5, pickupBye: true), .keep)
        XCTAssertNil(call(nil, 4.5))
    }

    func testExpectedFPTSWithSmoothing() throws {
        // Week 3: MIN vs TB, SF vs ARI. Weeks 1-2 give each side two games.
        let schedule = [ScheduleGame(week: 1, home: "MIN", away: "X1"), ScheduleGame(week: 2, home: "MIN", away: "X2"),
                        ScheduleGame(week: 1, home: "TB", away: "D1"), ScheduleGame(week: 2, home: "TB", away: "D2"),
                        ScheduleGame(week: 3, home: "MIN", away: "TB")]
        func line(_ f: Double) -> DefenseLine { DefenseLine(pointsAllowed: 0, sacks: 0, interceptions: 0, touchdowns: 0, fumbleRecoveries: 0, fantasyPoints: f) }
        let weeks: [Int: [String: DefenseLine]] = [
            1: ["MIN": line(10), "D1": line(22), "X1": line(3), "TB": line(1)],
            2: ["MIN": line(18), "D2": line(7), "X2": line(0), "TB": line(3)],
        ]
        let m = Matchups(schedule: schedule, defenseWeeks: weeks)
        XCTAssertEqual(try XCTUnwrap(m.leagueAverageFPTS), 8, accuracy: 1e-9)   // (10+22+3+1+18+7+0+3)/8
        let e = try XCTUnwrap(m.expectedFPTS(team: "MIN", week: 3))
        XCTAssertEqual(e.opponent, "TB")
        XCTAssertEqual(e.own, (10 + 18 + 2 * 8) / 4.0, accuracy: 1e-9)             // 11.0
        XCTAssertEqual(e.opponentAllowed, (22 + 7 + 2 * 8) / 4.0, accuracy: 1e-9)  // 11.25
        XCTAssertEqual(e.value, 11.0 + 11.25 - 8, accuracy: 1e-9)

        func expected(_ v: Double) -> ExpectedFPTS { ExpectedFPTS(opponent: "X", own: v, opponentAllowed: 8, leagueAverage: 8) }
        func call(_ a: Double, _ b: Double) -> WaiverAction? {
            WaiverAdvisor.expectedAdvice(pickup: expected(a), mine: expected(b), pickupOnBye: false, mineOnBye: false, mineName: "SF")?.action
        }
        XCTAssertEqual(call(14, 7), .replace)
        XCTAssertEqual(call(10, 7), .watch)
        XCTAssertEqual(call(3, 7), .keep)
    }

    func testTopUpFillsEachPositionWithBestUsage() {
        let existingWRs = (0..<44).map { player("wr\($0)", "WR", proj: nil) }
        let pool = [player("busy", "WR", proj: nil, touches: [9, 10]), player("quiet", "WR", proj: nil, touches: [2, 1]),
                    player("qbA", "QB", proj: nil, points: [20, 22]), player("qbB", "QB", proj: nil, points: [5, 6])]
        let added = RosterLabService.topUp(existing: existingWRs, pool: pool, k: 1)
        XCTAssertEqual(added.filter { $0.position == "WR" }.map(\.id), ["busy"], "WRs need only 1 more to reach 45")
        XCTAssertEqual(added.filter { $0.position == "QB" }.map(\.id), ["qbA", "qbB"], "higher average first")
        XCTAssertEqual(RosterLabService.waiverTargets.values.reduce(0, +), 150)
    }

    func testFinishedGamesWeekUsesOnlyFinalGames() throws {
        // Thursday: DAL–PHI is final; everyone else hasn't played.
        let team = ["dalRB": "DAL", "phiRB": "PHI", "sfRB": "SF", "phiWR": "PHI"]
        let pos = ["dalRB": "RB", "phiRB": "RB", "sfRB": "RB", "phiWR": "WR"]
        let matchups = [SleeperMatchup(rosterId: 1, starters: ["dalRB", "sfRB"], startersPoints: [12, 0]),
                        SleeperMatchup(rosterId: 2, starters: ["phiRB", "phiWR"], startersPoints: [8, 15])]
        let stats: WeeklyStats = ["dalRB": ["gp": 1, "rush_yd": 120], "phiRB": ["gp": 1], "phiWR": ["gp": 1],
                                  "sfRB": ["gp": 1, "rush_yd": 20]]   // in progress, not final
        let week = try XCTUnwrap(RosterLabService.finishedGamesWeek(
            matchups: matchups, stats: stats, finishedTeams: ["DAL", "PHI"],
            positionOf: { pos[$0] }, teamOf: { team[$0] }))
        XCTAssertEqual(week.targets["RB"], 10, "only the two final RB starters: (12 + 8) / 2")
        XCTAssertEqual(week.targets["WR"], 15)
        XCTAssertNil(week.stats["sfRB"], "SF's game isn't final")
        XCTAssertNotNil(week.stats["dalRB"])
        XCTAssertNil(RosterLabService.finishedGamesWeek(matchups: matchups, stats: stats, finishedTeams: [],
                                                         positionOf: { pos[$0] }, teamOf: { team[$0] }))
    }

    // MARK: News and roles

    func testRolesFromUsageAndInjuries() throws {
        func u(_ id: String, _ tpg: Double, recent: Double, pts: Double = 8, out: Bool = false) -> RoleModel.Usage {
            RoleModel.Usage(id: id, name: id, team: "NO", position: "RB", games: 3, touchesPerGame: tpg,
                            recentTouches: recent, recentPoints: pts, unavailable: out, injuryStatus: out ? "Out" : nil)
        }
        // Lead healthy.
        var r = RoleModel.roles([u("etienne", 18, recent: 18), u("kamara", 9, recent: 10)])
        XCTAssertEqual(r["etienne"]?.kind, .lead)
        XCTAssertNil(r["kamara"])

        // Lead out, clear next man up.
        r = RoleModel.roles([u("etienne", 18, recent: 18, out: true), u("kamara", 9, recent: 10, pts: 8), u("third", 3, recent: 3)])
        let k = try XCTUnwrap(r["kamara"])
        XCTAssertEqual(k.kind, .likelyLead)
        XCTAssertEqual(k.vacatedBy, "etienne")
        XCTAssertEqual(try XCTUnwrap(k.expectedTouches), 0.43 * 10 + 0.57 * 18, accuracy: 1e-9)   // 14.56
        let ppt = (8 + 6 * 0.74) / (10 + 6.0)
        XCTAssertEqual(try XCTUnwrap(k.expectedPoints), 14.56 * ppt, accuracy: 1e-9)

        // Lead out, two backups close in usage.
        r = RoleModel.roles([u("etienne", 18, recent: 18, out: true), u("a", 9, recent: 9), u("b", 8, recent: 8)])
        XCTAssertEqual(r["a"]?.kind, .committee)
        XCTAssertEqual(r["b"]?.kind, .committee)
    }

    func testFAABBidRanges() throws {
        func backup(_ pos: String, _ kind: RoleKind, lead: String, pts: Double?) -> PlayerReport {
            PlayerReport(id: "b", name: "b", position: pos, team: "NYJ", currentSeason: "2026", seasons: [],
                         role: RoleInfo(kind: kind, vacatedBy: "Lead", vacatedStatus: lead,
                                        expectedTouches: pts == nil ? nil : 10, expectedPoints: pts))
        }
        let status = FAABStatus(budget: 50, remaining: 37, waiverPosition: 8, teams: 10)
        // Short absences, by expected points.
        let allen = try XCTUnwrap(FAABAdvisor.advice(for: backup("RB", .likelyLead, lead: "Out", pts: 11.6), status: status))
        XCTAssertEqual([allen.low, allen.high], [5, 7])
        XCTAssertFalse(allen.longTerm)
        XCTAssertTrue(allen.detail.contains("odd amount"))
        XCTAssertEqual(FAABAdvisor.advice(for: backup("WR", .likelyLead, lead: "Out", pts: 9.3), status: status)?.high, 5)
        XCTAssertEqual(FAABAdvisor.advice(for: backup("RB", .committee, lead: "Doubtful", pts: nil), status: status)?.high, 1)
        // Lead on IR: the role can last, so the range is higher.
        let gordon = try XCTUnwrap(FAABAdvisor.advice(for: backup("RB", .likelyLead, lead: "IR", pts: 8.8), status: status))
        XCTAssertEqual([gordon.low, gordon.high], [7, 11])
        XCTAssertTrue(gordon.longTerm)
        // Capped at ~30% of what's left.
        let broke = FAABStatus(budget: 50, remaining: 10, waiverPosition: 1, teams: 10)
        let capped = try XCTUnwrap(FAABAdvisor.advice(for: backup("RB", .likelyLead, lead: "IR", pts: 12), status: broke))
        XCTAssertEqual([capped.low, capped.high], [3, 3])
        XCTAssertFalse(capped.detail.contains("odd amount"))
        // No bid for leads, or in leagues without FAAB.
        XCTAssertNil(FAABAdvisor.advice(for: backup("RB", .lead, lead: "Out", pts: 12), status: status))
        XCTAssertNil(FAABAdvisor.advice(for: backup("RB", .likelyLead, lead: "Out", pts: 12), status: nil))
    }

    func testInjuryHardRules() throws {
        let out = InjuryInfo(status: "Out", bodyPart: "Hamstring", notes: "Strain")
        XCTAssertEqual(out?.detail, "Out · Hamstring (Strain)")
        XCTAssertEqual(out?.isUnavailable, true)
        XCTAssertEqual(InjuryInfo(status: "Questionable", bodyPart: nil, notes: nil)?.isUnavailable, false)
        XCTAssertNil(InjuryInfo(status: nil, bodyPart: nil, notes: nil))

        // An injured starter with a big projection is benched.
        let hurt = PlayerReport(id: "hurt", name: "hurt", position: "RB", team: nil, projection: 20, currentSeason: "2026",
                                seasons: [], injury: out)
        let backup = PlayerReport(id: "backup", name: "backup", position: "RB", team: nil, projection: 8, currentSeason: "2026", seasons: [])
        let advice = LineupAdvisor.advise(starters: [hurt], bench: [backup], slots: ["RB"])
        XCTAssertEqual(advice["hurt"]?.action, .moveToBench)
        XCTAssertEqual(advice["backup"]?.action, .moveToStarter)

        // An injured waiver pickup is never a Replace.
        let mine = player("mine", "WR", proj: 2, points: [1, 1], touches: [1, 1])
        let injuredPickup = PlayerReport(id: "p", name: "p", position: "WR", team: nil, projection: 15, currentSeason: "2026",
                                         seasons: mine.seasons, injury: out)
        XCTAssertEqual(WaiverAdvisor.advise(pickup: injuredPickup, mine: mine, k: 1, throughWeek: 2)?.action, .keep)
    }
}
