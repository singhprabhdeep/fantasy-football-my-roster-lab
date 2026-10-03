import SwiftUI
import RosterLabKit

enum Fmt {
    static func number(_ value: Double?, digits: Int = 1) -> String {
        guard let value, value.isFinite else { return "–" }
        return value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func sortino(_ metrics: SeasonMetrics?) -> String {
        guard let metrics else { return "–" }
        if metrics.hasNoBadWeeks { return "∞" }
        return number(metrics.sortino, digits: 2)
    }
}

/// The metrics shown everywhere, with whether a higher value is better.
enum Metric: String, CaseIterable, Identifiable {
    // Display order everywhere: Avg, SD, Sortino ratio, CV, then the rest.
    case mean = "Avg"
    case sd = "SD"
    case sortino = "Sortino ratio"
    case cv = "CV"
    case dd = "Downside dev"
    case base = "Sortino base"
    case ram = "Risk-adj avg"
    // Usage: how much a player is involved. In the 2025 backtest these were the best early
    // signs of a waiver player about to produce.
    case touches = "Touches + targets"
    case snaps = "Snap share"

    var id: String { rawValue }

    var isUsage: Bool { self == .touches || self == .snaps }


    var higherIsBetter: Bool {
        switch self {
        case .mean, .sortino, .ram, .touches, .snaps: return true
        case .sd, .cv, .dd, .base: return false
        }
    }

    /// The base is a reference line, not a player quality, so it is never highlighted as better.
    var isComparable: Bool { self != .base }

    var explanation: String {
        switch self {
        case .mean: return "Average half-PPR points per game played."
        case .sd: return "How much weekly scores swing around the average."
        case .cv: return "SD ÷ average. Lower means steadier. Blank when the average is under 2."
        case .dd: return "How far the player falls short of the league's average starter at their position, counting only the bad weeks."
        case .base: return "The bar the Sortino ratio measures against: the league's average starter score at this position, averaged over the weeks this player played. The bar moves week to week; Player detail lists each week's value."
        case .sortino: return "Average points above the league starter average, per unit of downside deviation. ∞ means no bad weeks yet."
        case .ram: return "Average minus k × downside deviation."
        case .touches: return "Carries plus targets per game (RB, WR, TE). How often the offense goes to him, even before the points show up."
        case .snaps: return "Share of the team's offensive snaps he played. A rising share usually means a bigger role."
        }
    }

    func value(_ m: SeasonMetrics?) -> Double? {
        guard let m else { return nil }
        switch self {
        case .mean: return m.mean
        case .sd: return m.standardDeviation
        case .cv: return m.coefficientOfVariation
        case .dd: return m.downsideDeviation
        case .base: return m.averageTarget
        case .sortino: return m.hasNoBadWeeks ? .infinity : m.sortino
        case .ram: return m.riskAdjustedMean
        case .touches: return m.opportunitiesPerGame
        case .snaps: return m.snapShare
        }
    }

    func text(_ m: SeasonMetrics?) -> String {
        switch self {
        case .sortino: return Fmt.sortino(m)
        case .cv: return Fmt.number(value(m), digits: 2)
        case .snaps: return value(m).map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
        default: return Fmt.number(value(m))
        }
    }
}

struct PositionBadge: View {
    let position: String

    var body: some View {
        Text(position)
            .font(.caption2.weight(.bold).monospaced())
            .frame(width: 34, height: 22)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch position {
        case "QB": return .red
        case "RB": return .green
        case "WR": return .blue
        case "TE": return .orange
        case "K": return .purple
        case "DEF": return .brown
        default: return .gray
        }
    }
}

struct GamesBadge: View {
    @Environment(AppModel.self) private var model
    let games: Int
    /// The player's games, to check whether one is from the week in progress.
    var weeks: [WeekResult] = []

    private var liveWeek: Int? {
        guard let week = model.dashboard?.inProgressWeek, weeks.contains(where: { $0.week == week }) else { return nil }
        return week
    }

    var body: some View {
        Text("\(games) \(games == 1 ? "game" : "games")" + (liveWeek.map { " · wk \($0) in progress" } ?? ""))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .lineLimit(1)
            .fixedSize()
            .background(games <= 2 ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(games <= 2 ? .orange : .secondary)
    }
}

struct NoisyPositionNote: View {
    var body: some View {
        Label("Kicker and defense scores swing a lot week to week, so these numbers are not fully reliable and can shift sharply.",
              systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct StatCell: View {
    let label: String
    let value: String
    var alignment: HorizontalAlignment = .trailing

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 36, alignment: Alignment(horizontal: alignment, vertical: .center))
    }
}

struct PlayerRow: View {
    /// Row stats, strongest first (2022–2025 backtests). SD, CV, downside dev and snap share
    /// live on Player detail. Touches + targets is blank for QB, K and DEF.
    static func items(player: PlayerReport, current: SeasonMetrics, projectionWeek: Int?) -> [(String, String)] {
        var items = [("Avg", Fmt.number(current.mean))]
        if let week = projectionWeek {
            items.append(("Proj wk \(week)", Fmt.number(player.projection)))
        }
        items += [("Touches + tgts", Fmt.number(current.opportunitiesPerGame)),
                  ("Risk-adj", Fmt.number(current.riskAdjustedMean)),
                  (Reliability.title, Reliability.label(current)),
                  ("Base", Fmt.number(current.averageTarget))]
        return items
    }

    let player: PlayerReport
    /// Risk-adj rank among league starters at the position.
    var rank: StarterRank? = nil
    /// Week the projection is for; nil hides the projection.
    var projectionWeek: Int? = nil
    /// Start/sit call for this week.
    var advice: StartSitAdvice? = nil
    /// Whether the app's own stats back the call.
    var statsCheck: StatsCheck? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PositionBadge(position: player.position)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    PlayerNameText(player: player, weight: .medium)
                    if player.isKickerOrDefense {
                        Image(systemName: "exclamationmark.triangle").font(.caption2).foregroundStyle(.orange)
                    }
                    Spacer(minLength: 4)
                    if let current = player.current { GamesBadge(games: current.games, weeks: current.weeks) }
                }
                if NewsLine.hasNews(player) { NewsLine(player: player) }
                if let advice { StartSitBadge(advice: advice) }
                if let statsCheck { StatsCheckLine(check: statsCheck, rowIsPick: advice?.favorsThisPlayer ?? true) }
                if let current = player.current {
                    let items = Self.items(player: player, current: current, projectionWeek: projectionWeek)
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                        ForEach(0..<((items.count + 2) / 3), id: \.self) { row in
                            GridRow {
                                ForEach(items[(row * 3)..<min(row * 3 + 3, items.count)], id: \.0) { item in
                                    StatCell(label: item.0, value: item.1, alignment: .leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                if row * 3 + 3 > items.count { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                            }
                        }
                    }
                    if let text = RankText.long(rank, position: player.position) {
                        Text("Risk-adj rank: \(text)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No games this season").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct LoadStateOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.dashboard == nil {
            if let error = model.errorMessage {
                ContentUnavailableView {
                    Label("Couldn't load your league", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try again") { Task { await model.load(refresh: true) } }
                }
            } else {
                ProgressView("Loading your league…")
            }
        }
    }
}

/// "Jalen Hurts (1) PHI": the name, then the jersey number and team in smaller grey text.
/// One Text, so a long name wraps onto a second line instead of being cut off.
struct PlayerNameText: View {
    let player: PlayerReport
    var weight: Font.Weight = .regular

    var body: some View {
        (Text(player.name).font(.body.weight(weight))
            + Text("  " + player.tagline).font(.caption).foregroundColor(.secondary)
            + injuryText)
            .lineLimit(2)
    }

    /// "  OUT" / "  Q" in red or orange right after the name.
    private var injuryText: Text {
        guard let injury = player.injury else { return Text("") }
        return Text("  " + injury.short).font(.caption.weight(.bold))
            .foregroundColor(injury.isUnavailable ? .red : .orange)
    }
}

/// Injury detail and role, under a player's name. Nothing shows for a healthy player with no role news,
/// or for a plain "Lead role" unless `showLead` is on.
struct NewsLine: View {
    let player: PlayerReport
    var showLead = false

    /// Whether there's anything to show; callers skip the view otherwise so it takes no space.
    static func hasNews(_ p: PlayerReport, showLead: Bool = false) -> Bool {
        p.injury != nil || p.role.map { $0.kind != .lead || showLead } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let injury = player.injury {
                Label(injury.isUnavailable ? "\(injury.detail) · won't be started or recommended"
                                           : "\(injury.detail) · check before kickoff",
                      systemImage: "cross.case")
                    .font(.caption)
                    .foregroundStyle(injury.isUnavailable ? Color.red : Color.orange)
            }
            if let role = player.role {
                switch role.kind {
                case .likelyLead:
                    Label(likelyLeadText(role), systemImage: "arrow.up.forward.circle")
                        .font(.caption.weight(.medium)).foregroundStyle(.green)
                case .committee:
                    Label("Committee: \(shortName(role.vacatedBy ?? "the lead")) \(Self.statusPhrase(role.vacatedStatus)), sharing the work",
                          systemImage: "person.2").font(.caption).foregroundStyle(.secondary)
                case .lead where showLead:
                    Label("Lead role on his team", systemImage: "star").font(.caption).foregroundStyle(.secondary)
                default:
                    EmptyView()
                }
            }
        }
    }

    /// "out", "doubtful", "on IR", "on PUP"...
    static func statusPhrase(_ status: String?) -> String {
        guard let status else { return "out" }
        return ["Out", "Doubtful", "Questionable"].contains(status) ? status.lowercased() : "on \(status)"
    }

    private func likelyLeadText(_ role: RoleInfo) -> String {
        var text = "Likely lead: \(shortName(role.vacatedBy ?? "the lead")) \(Self.statusPhrase(role.vacatedStatus))"
        if let t = role.expectedTouches, let p = role.expectedPoints {
            text += " · ~\(Fmt.number(t)) touches, ~\(Fmt.number(p)) pts expected"
        }
        return text
    }
}

/// Suggested FAAB bid for a backup whose starter is out, with the reasoning underneath.
struct FAABBidLine: View {
    let bid: BidAdvice

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text("FAAB: ").foregroundStyle(.secondary)
                    + Text(bid.range).fontWeight(.semibold)
                    + Text(bid.longTerm ? " · longer role" : " · short-term fill-in").foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "dollarsign.circle").foregroundStyle(Color.accentColor)
            }
            .font(.caption)
            Text(bid.detail).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 26)
        }
    }
}

/// Wording for a player's risk-adj rank among league starters at his position.
enum RankText {
    static func plural(_ position: String) -> String {
        switch position {
        case "K": return "kickers"
        case "DEF": return "defenses"
        default: return position + "s"
        }
    }

    /// "#12 of 31 starting WRs", "would be #3 of 31 starting WRs" or "below all 31 starting WRs".
    static func long(_ rank: StarterRank?, position: String) -> String? {
        guard let rank, rank.total > 0 else { return nil }
        let pool = "\(rank.total) starting \(plural(position))"
        if rank.isStarter { return "#\(rank.rank) of \(pool)" }
        if rank.isBelowAll { return "below all \(pool)" }
        return "would be #\(rank.rank) of \(pool)"
    }

    /// Compact form for tables: "#12 of 31", "below all 31".
    static func short(_ rank: StarterRank?) -> String {
        guard let rank, rank.total > 0 else { return "–" }
        if rank.isBelowAll { return "below all \(rank.total)" }
        return "#\(rank.rank) of \(rank.total)"
    }
}

/// The one way the Sortino ratio proved useful in the 2022–2025 backtests: players above 0
/// (beating a typical starter on average, including "no bad weeks yet") beat the typical starter
/// the next week about 48–52% of the time, against 39–41% for players below 0, every year.
enum Reliability {
    static let title = "Sortino > 0"

    static func label(_ m: SeasonMetrics?) -> String {
        guard let m, m.downsideDeviation != nil else { return "–" }
        if m.hasNoBadWeeks { return "Yes" }
        return (m.sortino ?? -1) > 0 ? "Yes" : "No"
    }
}

/// "Move to starter · Strong 74% vs A. Mitchell". Changes are colored; keeps are grey.
struct StartSitBadge: View {
    let advice: StartSitAdvice

    var body: some View {
        HStack(spacing: 6) {
            Label(advice.action.rawValue, systemImage: icon)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.15), in: Capsule())
                .foregroundStyle(color)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    private var detail: String {
        if advice.unavailable {
            if advice.action == .moveToBench, let versus = advice.versus { return "Not projected to play · start \(shortName(versus))" }
            return "Not projected to play this week"
        }
        guard let confidence = advice.confidence, let strength = advice.strength else {
            return "No other option at this spot"
        }
        let pct = "\(Int((confidence * 100).rounded()))%"
        guard let versus = advice.versus else { return "\(strength) \(pct)" }
        switch advice.action {
        case .moveToStarter: return "\(strength) \(pct) · in for \(shortName(versus))"
        case .moveToBench: return "\(strength) \(pct) · start \(shortName(versus))"
        default: return "\(strength) \(pct) vs \(shortName(versus))"
        }
    }

    private var icon: String {
        switch advice.action {
        case .keepStarting: return "checkmark.circle"
        case .moveToBench: return "arrow.down.circle"
        case .moveToStarter: return "arrow.up.circle"
        case .keepOnBench: return "minus.circle"
        }
    }

    private var color: Color {
        switch advice.action {
        case .moveToStarter: return .green
        case .moveToBench: return .orange
        case .keepStarting, .keepOnBench: return .secondary
        }
    }
}

/// "Your stats agree" / "Your stats disagree: M. Golden has the higher avg and more touches + targets".
/// Information only: it never changes the start/sit call.
struct StatsCheckLine: View {
    let check: StatsCheck
    /// True on the row of the player the call favors; false on the row of the player it benches.
    var rowIsPick = true

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(check.verdict == .disagree ? Color.orange : Color.secondary)
    }

    private var text: String {
        let lead: String
        switch check.verdict {
        case .agree: return "Your stats agree"
        case .split: lead = "Your stats are split"
        case .disagree: lead = "Your stats disagree"
        }
        if rowIsPick {
            // On the favored player's row: name the other player who has the edge.
            return "\(lead): \(shortName(check.otherName)) has \(Self.list(check.favoringOther))"
        }
        // On the benched player's row the edges are his own, so say who they're over.
        return "\(lead): \(Self.list(check.favoringOther, article: false)) than \(shortName(check.pickName))"
    }

    private var icon: String {
        switch check.verdict {
        case .agree: return "checkmark"
        case .split: return "arrow.left.arrow.right"
        case .disagree: return "exclamationmark.triangle"
        }
    }

    static func list(_ items: [String], article: Bool = true) -> String {
        let words = items.map { article && $0.hasPrefix("higher") ? "the " + $0 : $0 }
        guard words.count > 1 else { return words.first ?? "" }
        return words.dropLast().joined(separator: ", ") + " and " + words.last!
    }
}

extension WaiverCandidate {
    /// "+34K adds", or "Not trending" for players added past Sleeper's 100 trending adds.
    var addsLabel: String {
        trending ? "+\(adds.formatted(.number.notation(.compactName))) adds" : "Not trending"
    }
}
