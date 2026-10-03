import Foundation

// Start/sit and waiver calls, with confidence numbers taken from replaying the 2022–2025
// seasons of a 10-team half-PPR league (research/startsit_backtest.py, research/waiver_rules_backtest.py).

// MARK: - Start/sit

public enum StartSitAction: String, Sendable {
    case keepStarting = "Keep as starter"
    case moveToBench = "Move to bench"
    case moveToStarter = "Move to starter"
    case keepOnBench = "Keep on bench"

    public var isChange: Bool { self == .moveToBench || self == .moveToStarter }
}

public struct StartSitAdvice: Sendable, Equatable {
    public let action: StartSitAction
    /// The player on the other side of the call: who he beats out, or who beats him out.
    public let versus: String?
    public let versusId: String?
    /// Chance the call is right this week (0.5–0.85). Nil when there's no one to compare with.
    public let confidence: Double?
    /// Set when the player can't play this week (bye, ruled out, no projection).
    public let unavailable: Bool

    public init(action: StartSitAction, versus: String?, versusId: String? = nil, confidence: Double?, unavailable: Bool) {
        self.action = action
        self.versus = versus
        self.versusId = versusId
        self.confidence = confidence
        self.unavailable = unavailable
    }

    /// Whether this call favors the player it's attached to.
    public var favorsThisPlayer: Bool { action == .keepStarting || action == .moveToStarter }

    public var strength: String? {
        guard let confidence else { return nil }
        switch confidence {
        case 0.7...: return "Strong"
        case 0.6..<0.7: return "Lean"
        default: return "Toss-up"
        }
    }
}

public enum LineupAdvisor {
    /// How far a player's actual score typically lands from Sleeper's projection (standard deviation,
    /// points), averaged over the 2024 and 2025 backtests. 2022 and 2023 came out the same (QB 7.1–8.0,
    /// RB 7.0–7.3, WR 6.5–7.1, TE 6.2–6.3, K 4.5–4.9, DEF 6.1–6.3), and confidence matched how often
    /// the calls were right within 1–3 points for confidence levels up to 85% in all four seasons.
    static let projectionMissSD: [String: Double] = [
        "QB": 7.65, "RB": 7.1, "WR": 6.85, "TE": 6.3, "K": 4.75, "DEF": 6.15,
    ]
    /// Above this, the backtests showed the model getting overconfident.
    static let maxConfidence = 0.85

    /// Chance the higher-projected of two players outscores the other.
    public static func confidence(projectionGap gap: Double, positions a: String, _ b: String) -> Double {
        let sa = projectionMissSD[a] ?? 7, sb = projectionMissSD[b] ?? 7
        let z = abs(gap) / (sa * sa + sb * sb).squareRoot()
        let p = 0.5 * (1 + erf(z / 2.0.squareRoot()))
        return min(p, maxConfidence)
    }

    public static func slotAccepts(_ slot: String, position: String) -> Bool {
        switch slot {
        case "FLEX": return ["RB", "WR", "TE"].contains(position)
        case "SUPER_FLEX": return ["QB", "RB", "WR", "TE"].contains(position)
        case "REC_FLEX": return ["WR", "TE"].contains(position)
        case "WRRB_FLEX": return ["RB", "WR"].contains(position)
        default: return slot == position
        }
    }

    /// The best lineup by Sleeper projection (the best lineup-setter in both backtest seasons),
    /// with season average breaking near-ties. Fixed positions are filled before flex spots.
    /// Returns slot index → player id.
    public static func bestLineup(_ players: [PlayerReport], slots: [String]) -> [Int: String] {
        func value(_ p: PlayerReport) -> (Double, Double) {
            let rounded = ((p.projection ?? -99) * 2).rounded() / 2
            return (rounded, p.current?.mean ?? 0)
        }
        let pool = players.filter { ($0.projection ?? 0) > 0 && !$0.isUnavailable }.sorted { value($0) > value($1) }
        var used = Set<String>(), result: [Int: String] = [:]
        let order = slots.indices.sorted { isFlex(slots[$0]) == isFlex(slots[$1]) ? $0 < $1 : !isFlex(slots[$0]) }
        for i in order {
            if let p = pool.first(where: { !used.contains($0.id) && slotAccepts(slots[i], position: $0.position) }) {
                used.insert(p.id); result[i] = p.id
            }
        }
        return result
    }

    static func isFlex(_ slot: String) -> Bool { slot.contains("FLEX") }

    /// One call per rostered player. `starters` are the current starters, `bench` everyone else.
    /// A change names the player it swaps with ("in for Golden"). A keep names the closest player on
    /// the other side of the line whose status isn't changing, so a starter is compared with someone
    /// staying on the bench (not a starter who is about to be benched) and vice versa.
    public static func advise(starters: [PlayerReport], bench: [PlayerReport], slots: [String]) -> [String: StartSitAdvice] {
        let everyone = starters + bench
        let best = bestLineup(everyone, slots: slots)
        let recommended = Set(best.values)
        let current = Set(starters.map(\.id))
        let byId = Dictionary(everyone.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let slotOf = Dictionary(best.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        // Hard rule: Out / IR / Doubtful never gets a start, whatever the projection says.
        func proj(_ p: PlayerReport) -> Double { p.isUnavailable ? 0 : (p.projection ?? 0) }
        func conf(_ better: PlayerReport, over worse: PlayerReport) -> Double {
            confidence(projectionGap: proj(better) - proj(worse), positions: better.position, worse.position)
        }

        var advice: [String: StartSitAdvice] = [:]

        // Swaps: each player moving in replaces the lowest-projected starter moving out whose spot he can fill.
        var goingOut = starters.filter { !recommended.contains($0.id) }
        for incoming in everyone.filter({ recommended.contains($0.id) && !current.contains($0.id) })
                                .sorted(by: { proj($0) > proj($1) }) {
            let slot = slots[slotOf[incoming.id]!]
            let eligible = goingOut.filter { slotAccepts(slot, position: $0.position) || $0.position == incoming.position }
            guard let out = (eligible.isEmpty ? goingOut : eligible).min(by: { proj($0) < proj($1) }) else {
                advice[incoming.id] = StartSitAdvice(action: .moveToStarter, versus: nil, confidence: nil, unavailable: false)
                continue
            }
            goingOut.removeAll { $0.id == out.id }
            let outPlays = proj(out) > 0
            let c = outPlays ? conf(incoming, over: out) : nil
            advice[incoming.id] = StartSitAdvice(action: .moveToStarter, versus: out.name, versusId: out.id, confidence: c, unavailable: false)
            advice[out.id] = StartSitAdvice(action: .moveToBench, versus: incoming.name, versusId: incoming.id, confidence: c, unavailable: !outPlays)
        }

        let moving = Set(advice.keys)
        for p in everyone where advice[p.id] == nil {
            if recommended.contains(p.id), let slot = slotOf[p.id] {
                // Closest player left out who could take this spot, preferring ones already on the bench.
                let leftOut = everyone
                    .filter { !recommended.contains($0.id) && proj($0) > 0 && slotAccepts(slots[slot], position: $0.position) }
                let steady = leftOut.filter { !moving.contains($0.id) }
                let rival = (steady.isEmpty ? leftOut : steady).max { proj($0) < proj($1) }
                advice[p.id] = StartSitAdvice(action: current.contains(p.id) ? .keepStarting : .moveToStarter,
                                              versus: rival?.name, versusId: rival?.id,
                                              confidence: rival.map { conf(p, over: $0) },
                                              unavailable: false)
            } else {
                let out = proj(p) <= 0
                // Weakest recommended starter in a spot this player could fill, preferring ones already starting.
                let blocking = best
                    .filter { slotAccepts(slots[$0.key], position: p.position) }
                    .compactMap { byId[$0.value] }
                let steady = blocking.filter { !moving.contains($0.id) }
                let rival = (steady.isEmpty ? blocking : steady).min { proj($0) < proj($1) }
                advice[p.id] = StartSitAdvice(action: current.contains(p.id) ? .moveToBench : .keepOnBench,
                                              versus: rival?.name, versusId: rival?.id,
                                              confidence: out ? nil : rival.map { conf($0, over: p) },
                                              unavailable: out)
            }
        }
        return advice
    }
}

// MARK: - Do my stats agree?

/// A cross-check of a start/sit call against the app's own stats. It never changes the call:
/// in the 2022–2025 backtests, the projection's pick was right just as often when these stats
/// pointed the other way on close calls (54–59% either way). Only on big projection gaps (6+ points)
/// did a disagree lower it, from about 79% to 69% (103 calls in four seasons).
public struct StatsCheck: Sendable, Equatable {
    public enum Verdict: String, Sendable { case agree, split, disagree }
    public let verdict: Verdict
    /// Stats that favor the other player, e.g. ["higher avg", "more touches + targets"].
    public let favoringOther: [String]
    public let otherName: String
    public let pickName: String

    /// Compares the player the call favors (`pick`) with the other one on season avg, last-2-game
    /// avg, risk-adj avg and, for RB/WR/TE, touches + targets over the last 2 games.
    public static func compare(pick: PlayerReport, other: PlayerReport, k: Double) -> StatsCheck? {
        guard let a = pick.current, let b = other.current else { return nil }
        var checks: [(String, Double?, Double?)] = [
            ("higher avg", a.mean, b.mean),
            ("higher last-2 avg", pick.current(lastGames: 2, k: k)?.mean, other.current(lastGames: 2, k: k)?.mean),
            ("higher risk-adj avg", a.riskAdjustedMean, b.riskAdjustedMean),
        ]
        let skill: Set<String> = ["RB", "WR", "TE"]
        if skill.contains(pick.position), skill.contains(other.position) {
            checks.append(("more touches + targets", pick.current(lastGames: 2, k: k)?.opportunitiesPerGame,
                           other.current(lastGames: 2, k: k)?.opportunitiesPerGame))
        }
        let compared = checks.filter { $0.1 != nil && $0.2 != nil }
        guard !compared.isEmpty else { return nil }
        let againstPick = compared.filter { $0.2! > $0.1! }.map(\.0)
        let verdict: Verdict
        if againstPick.isEmpty { verdict = .agree }
        else if againstPick.count * 2 > compared.count { verdict = .disagree }
        else { verdict = .split }
        return StatsCheck(verdict: verdict, favoringOther: againstPick, otherName: other.name, pickName: pick.name)
    }
}

// MARK: - Waivers

public enum WaiverAction: String, Sendable {
    case replace = "Replace"
    case watch = "Watch"
    case keep = "Don't replace"
}

public struct WaiverAdvice: Sendable, Equatable {
    public let action: WaiverAction
    /// Share of similar calls in 2022–25 where the pickup outscored the player he'd replace over
    /// the rest of the season. Nil where the rule wasn't tested.
    public let pickupWinRate: Double?
    public let strong: Bool
    /// Why the call came out this way.
    public let reason: String
    /// Kicker and defense calls are for this week only (streaming); the rate is for that week.
    public let thisWeekOnly: Bool

    public init(action: WaiverAction, pickupWinRate: Double?, strong: Bool, reason: String, thisWeekOnly: Bool = false) {
        self.action = action
        self.pickupWinRate = pickupWinRate
        self.strong = strong
        self.reason = reason
        self.thisWeekOnly = thisWeekOnly
    }
}

public enum WaiverAdvisor {
    /// Hit rates from the 2022–2025 backtests (average of the four seasons, listed 2025 · 2024 · 2023 · 2022).
    public enum Rates {
        public static let replaceStrong = 0.70     // proj gap ≥ 2 and touches gap ≥ 4: 75.0 · 74.0 · 67.5 · 64.3
        public static let replace = 0.685          // proj gap ≥ 2 and touches gap 2–4: 71.3 · 68.3 · 68.3 · 65.9
        public static let replaceQB = 0.59         // QB proj gap ≥ 2: 71.2 · 61.8 · 56.9 · 45.0
        public static let watch = 0.44             // one of the two signals: 45.8 · 43.9 · 39.5 · 47.3
        public static let keep = 0.115             // neither: 11.2 · 12.1 · 9.2 · 13.1
        public static let keepQB = 0.19            // 20.9 · 20.8 · 20.2 · 15.0

        // Kickers and defenses, judged on this week only. Holding a pickup for the rest of the
        // season didn't reliably help, so these are streaming calls.
        public static let byeReplace = 0.77        // my K/DEF not projected to play: 70–85% every year
        public static let defReplaceStrong = 0.65  // DEF proj gap ≥ 2: 67.2 · 80.9 · 53.2 · 57.9
        public static let defReplace = 0.59        // DEF proj gap 1–2: 59.9 · 73.7 · 50.0 · 54.1
        public static let defWatch = 0.52          // DEF proj gap 0–1: 51.3 · 63.1 · 44.3 · 47.8
        public static let defKeep = 0.33           // DEF proj gap < 0: 31.3 · 35.3 · 32.5 · 34.5
        public static let kWatch = 0.52            // K proj gap ≥ 1: 50.0 · 56.5 · 36.8 · 63.4
        public static let kKeep = 0.36             // K proj gap < 1: 31.6 · 37.9 · 37.3 · 36.7
    }

    /// `pickup` and `mine` are compared on this week's projection and on touches + targets over their
    /// last 2 games, the rule that held up in both seasons. `throughWeek` is the last finished week.
    public static func advise(pickup: PlayerReport, mine: PlayerReport?, k: Double, throughWeek: Int) -> WaiverAdvice? {
        guard let mine else { return nil }
        let position = pickup.position
        // Hard rule: a pickup who's Out / IR / Doubtful isn't worth a claim this week.
        if let injury = pickup.injury, injury.isUnavailable {
            return WaiverAdvice(action: .keep, pickupWinRate: nil, strong: false, reason: injury.detail,
                                thisWeekOnly: position == "K" || position == "DEF")
        }
        if position == "K" || position == "DEF" {
            return streamingAdvice(pickup: pickup, mine: mine, throughWeek: throughWeek)
        }
        guard ["QB", "RB", "WR", "TE"].contains(position) else { return nil }
        let pickupRecent = pickup.current(lastGames: 2, k: k)
        let mineRecent = mine.current(lastGames: 2, k: k)
        let projectionGap = (pickup.projection ?? 0) - (mine.projection ?? 0)
        let proj = "Proj \(format(pickup.projection ?? 0)) vs \(format(mine.projection ?? 0))"

        // The backtest only judged players with 2+ games who played the most recent week.
        let enoughGames = (pickup.current?.games ?? 0) >= 2 && (pickup.current?.weeks.last?.week ?? 0) >= throughWeek

        if position == "QB" {
            if projectionGap >= 2 {
                return enoughGames
                    ? WaiverAdvice(action: .replace, pickupWinRate: Rates.replaceQB, strong: false, reason: proj)
                    : WaiverAdvice(action: .watch, pickupWinRate: nil, strong: false, reason: "\(proj). Needs 2+ recent games first")
            }
            return WaiverAdvice(action: .keep, pickupWinRate: Rates.keepQB, strong: false, reason: proj)
        }

        guard let recentTouches = pickupRecent?.opportunitiesPerGame, let mt = mineRecent?.opportunitiesPerGame else {
            return WaiverAdvice(action: .keep, pickupWinRate: nil, strong: false, reason: "Not enough recent games to compare")
        }
        // A likely lead is judged on his role-adjusted touches (research/vacancy_backtest.py).
        let pt = pickup.role?.expectedTouches ?? recentTouches
        let touchGap = pt - mt
        let roleNote = pickup.role?.expectedTouches == nil ? "" : " (role-adjusted: \(pickup.role?.vacatedBy ?? "lead") out)"
        let detail = "\(proj) · touches + targets \(format(pt)) vs \(format(mt))\(roleNote)"
        if projectionGap >= 2 && touchGap >= 2 {
            let strong = touchGap >= 4
            return enoughGames
                ? WaiverAdvice(action: .replace, pickupWinRate: strong ? Rates.replaceStrong : Rates.replace, strong: strong, reason: detail)
                : WaiverAdvice(action: .watch, pickupWinRate: nil, strong: false, reason: "\(detail). Needs 2+ recent games first")
        }
        if projectionGap >= 2 || touchGap >= 2 {
            return WaiverAdvice(action: .watch, pickupWinRate: Rates.watch, strong: false, reason: detail)
        }
        return WaiverAdvice(action: .keep, pickupWinRate: Rates.keep, strong: false, reason: detail)
    }

    /// Kickers and defenses: this week's projection is the only thing that held up, and only for
    /// this week. Kicker projections are too close together to beat a healthy kicker reliably, so a
    /// kicker is only worth replacing when he isn't playing.
    static func streamingAdvice(pickup: PlayerReport, mine: PlayerReport, throughWeek: Int) -> WaiverAdvice {
        let pickupProj = pickup.projection ?? 0
        let mineProj = mine.projection ?? 0
        let gap = pickupProj - mineProj
        let proj = "This week: proj \(format(pickupProj)) vs \(format(mineProj))"
        let enoughGames = (pickup.current?.games ?? 0) >= 2 && (pickup.current?.weeks.last?.week ?? 0) >= throughWeek
        func make(_ action: WaiverAction, _ rate: Double, strong: Bool = false, note: String = "") -> WaiverAdvice {
            WaiverAdvice(action: action, pickupWinRate: rate, strong: strong, reason: proj + note, thisWeekOnly: true)
        }
        if pickupProj <= 0 { return make(.keep, pickup.position == "K" ? Rates.kKeep : Rates.defKeep, note: ". Not projected to play") }
        if mineProj <= 0 {
            return make(.replace, Rates.byeReplace, note: ". \(mine.name) isn't projected to play this week")
        }
        let replace: (Double, Bool)?
        if pickup.position == "DEF" {
            replace = gap >= 2 ? (Rates.defReplaceStrong, true) : gap >= 1 ? (Rates.defReplace, false) : nil
        } else {
            replace = nil
        }
        if let (rate, strong) = replace {
            return enoughGames ? make(.replace, rate, strong: strong)
                               : WaiverAdvice(action: .watch, pickupWinRate: nil, strong: false,
                                              reason: proj + ". Needs 2+ recent games first", thisWeekOnly: true)
        }
        if pickup.position == "DEF" {
            return gap >= 0 ? make(.watch, Rates.defWatch) : make(.keep, Rates.defKeep)
        }
        return gap >= 1 ? make(.watch, Rates.kWatch) : make(.keep, Rates.kKeep)
    }

    /// Defense calls from matchup FPTS only (no projections): the fantasy points earlier defenses
    /// scored against each defense's opponent this week. A gap of 2+ either way decides it; inside
    /// ±2 is Watch. Pickup win rates that week in the 2025 · 2024 backtest:
    ///   whole-season window: Replace 53% · 60%, Watch 40% · 46%, Don't replace 33% · 38%
    ///   last-2-games window: Replace 43% · 55%, Watch 47% · 48%, Don't replace 37% · 42%
    /// Weaker than the projection rule (Replace 67% · 81%), and chosen deliberately to use only the app's own data.
    public static let matchupThreshold = 2.0

    public static func matchupAdvice(pickupFPTS: Double?, mineFPTS: Double?, pickupOnBye: Bool, mineOnBye: Bool,
                                     mineName: String, gamesUsed: Int) -> WaiverAdvice? {
        if pickupOnBye {
            return WaiverAdvice(action: .keep, pickupWinRate: nil, strong: false, reason: "On bye this week", thisWeekOnly: true)
        }
        if mineOnBye {
            return WaiverAdvice(action: .replace, pickupWinRate: Rates.byeReplace, strong: false,
                                reason: "\(mineName) is on bye this week", thisWeekOnly: true)
        }
        guard let a = pickupFPTS, let b = mineFPTS else { return nil }
        let gap = a - b
        let reason = "Matchup FPTS \(format(a)) vs \(format(b)) (within ±\(format(matchupThreshold)) is Watch)"
        // Hit rates exist only for the two windows that were backtested (0 = whole season).
        let rates: (replace: Double, watch: Double, keep: Double)? =
            gamesUsed == 0 ? (0.565, 0.43, 0.355) : gamesUsed == 2 ? (0.49, 0.475, 0.395) : nil
        let untested = rates == nil ? ". Hit rate only tested for Whole season and Last 2 games" : ""
        if gap >= matchupThreshold {
            return WaiverAdvice(action: .replace, pickupWinRate: rates?.replace, strong: false, reason: reason + untested, thisWeekOnly: true)
        }
        if gap <= -matchupThreshold {
            return WaiverAdvice(action: .keep, pickupWinRate: rates?.keep, strong: false, reason: reason + untested, thisWeekOnly: true)
        }
        return WaiverAdvice(action: .watch, pickupWinRate: rates?.watch, strong: false, reason: reason + untested, thisWeekOnly: true)
    }

    /// Upcoming week defense call from Expected FPTS (the app's own data, no projections).
    /// 4+ higher is Replace, 4+ lower is Don't replace, in between is Watch. Pickup win rates that
    /// week (2025 · 2024 · 2023 · 2022): Replace 53 · 73 · 47 · 46%, Watch 43 · 50 · 40 · 42%,
    /// Don't replace 34 · 32 · 39 · 41%.
    public static let expectedThreshold = 4.0

    public static func expectedAdvice(pickup: ExpectedFPTS?, mine: ExpectedFPTS?, pickupOnBye: Bool, mineOnBye: Bool,
                                      mineName: String) -> WaiverAdvice? {
        if pickupOnBye {
            return WaiverAdvice(action: .keep, pickupWinRate: nil, strong: false, reason: "On bye this week", thisWeekOnly: true)
        }
        if mineOnBye {
            return WaiverAdvice(action: .replace, pickupWinRate: Rates.byeReplace, strong: false,
                                reason: "\(mineName) is on bye this week", thisWeekOnly: true)
        }
        guard let a = pickup, let b = mine else { return nil }
        let gap = a.value - b.value
        let reason = "Expected FPTS \(format(a.value)) vs \(format(b.value)) (within ±\(format(expectedThreshold)) is Watch)"
        if gap >= expectedThreshold {
            return WaiverAdvice(action: .replace, pickupWinRate: 0.55, strong: false, reason: reason, thisWeekOnly: true)
        }
        if gap <= -expectedThreshold {
            return WaiverAdvice(action: .keep, pickupWinRate: 0.365, strong: false, reason: reason, thisWeekOnly: true)
        }
        return WaiverAdvice(action: .watch, pickupWinRate: 0.44, strong: false, reason: reason, thisWeekOnly: true)
    }

    private static func format(_ v: Double) -> String { String(format: "%.1f", v) }
}
