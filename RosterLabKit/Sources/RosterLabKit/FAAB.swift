import Foundation

// FAAB bid ranges for backups whose team's lead RB/WR/TE is out. From research/faab_vacancy_study.py,
// 2022–2025 in a 10-team half-PPR, $50 FAAB league: of 234 such backups on waivers only 21% were added, 72% of adds were
// $0 free agents, and winning bids ran median $3, 90th percentile $6 (RB max $5, WR max $4, TE max $17
// on 3 claims). A lead on IR makes the backup's role last, so those ranges follow the league's bids on
// any RB/WR/TE claim instead (median $2, 75th $5, 90th $10).

/// My FAAB position this season.
public struct FAABStatus: Sendable, Equatable {
    public let budget: Int
    public let remaining: Int
    /// Waiver order (1 is first). Ties on a bid go to the lower number.
    public let waiverPosition: Int?
    public let teams: Int

    public init(budget: Int, remaining: Int, waiverPosition: Int?, teams: Int) {
        self.budget = budget
        self.remaining = remaining
        self.waiverPosition = waiverPosition
        self.teams = teams
    }

    /// In the back half of the waiver order, where a tie at a round number goes to someone else.
    public var losesTies: Bool { (waiverPosition ?? 0) > teams / 2 }
}

public struct BidAdvice: Sendable, Equatable {
    public let low: Int
    public let high: Int
    /// The lead is on IR (or similar), so the role could last weeks.
    public let longTerm: Bool
    /// "Bid $5–7"
    public var range: String { low == high ? "Bid $\(low)" : "Bid $\(low)–\(high)" }
    /// Why, in a sentence or two.
    public let detail: String
}

public enum FAABAdvisor {
    /// Injury statuses that keep a player out for weeks, not days.
    static let longTermStatuses: Set<String> = ["IR", "PUP", "NFI", "Sus", "NA", "DNR", "COV"]

    /// Range by role-adjusted expected points: (points at least, short absence, long absence).
    static let tiers: [(points: Double, short: ClosedRange<Int>, long: ClosedRange<Int>)] = [
        (10, 5...7, 8...12),
        (8, 3...5, 7...11),
        (6, 1...3, 3...6),
        (-.infinity, 0...1, 1...3),
    ]

    /// Past winning bids for backups at each position, 2022–25.
    static let history: [String: String] = [
        "RB": "RB backups went for $0–5 in 2022–25",
        "WR": "WR backups went for $0–4 in 2022–25",
        "TE": "TE backups went for $2–17 in 2022–25 (only 3 claims)",
    ]

    /// A bid range for a likely lead or committee back, or nil for everyone else.
    public static func advice(for player: PlayerReport, status: FAABStatus?) -> BidAdvice? {
        guard let role = player.role, role.kind != .lead, let status, status.budget > 0 else { return nil }
        let longTerm = role.vacatedStatus.map { longTermStatuses.contains($0) } ?? false
        let points = role.expectedPoints ?? -.infinity
        let tier = tiers.first { points >= $0.points } ?? tiers[tiers.count - 1]
        var range = longTerm ? tier.long : tier.short
        // Keep one pickup to about 30% of what's left, so there's money for a later breakout.
        let cap = max(0, Int((Double(status.remaining) * 0.3).rounded()))
        if range.upperBound > cap { range = min(range.lowerBound, cap)...cap }

        var parts: [String] = []
        let lead = role.vacatedBy ?? "The lead"
        let absence = longTerm ? "\(lead) is on \(role.vacatedStatus ?? "IR"), so the role could last"
                               : "\(lead) is \((role.vacatedStatus ?? "out").lowercased()), likely a short absence"
        parts.append(role.kind == .committee ? "\(absence); sharing the work caps the value." : "\(absence).")
        if let history = history[player.position] { parts.append("\(history).") }
        var budget = "You have $\(status.remaining) left"
        if status.losesTies, let position = status.waiverPosition {
            budget += "; ties go to waiver order and you're #\(position), so bid an odd amount"
        }
        parts.append(budget + ".")
        return BidAdvice(low: range.lowerBound, high: range.upperBound, longTerm: longTerm,
                         detail: parts.joined(separator: " "))
    }
}
