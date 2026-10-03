import SwiftUI

/// Why the Waivers tab shows the stats it does, in the order it does, with the backtest numbers
/// behind each choice. Correlations are with a player's rest-of-season points per game, across
/// every RB/WR/TE on waivers, weeks 3–14.
struct WaiverStatsInfo: View {
    private struct Row: Identifiable {
        let id = UUID()
        let stat: String
        let number: String
        let why: String
    }

    private let shown: [Row] = [
        Row(stat: "1. Touches + targets", number: "0.61 · 0.57 · 0.57 · 0.53",
            why: "Top signal in 2025 and 2022, within 0.03 of Avg in 2024 and 2023. The players it ranked highest held their scoring after pickup (6.2 → 6.5, 6.1 → 6.4, 6.1 → 5.7, 6.3 → 5.8 pts/game), and it found the pickup that beat your lowest player most often (7 of 12 weeks in 2023 and 2022)."),
        Row(stat: "2. Avg", number: "0.54 · 0.60 · 0.59 · 0.50",
            why: "Solid across the pool (best in 2024 and 2023), but its top-ranked players were often hot streaks that cooled off (7.6 → 6.0, 7.7 → 6.7, 7.5 → 5.8, 7.9 → 5.4)."),
        Row(stat: "3–4. Risk-adj avg + rank", number: "0.56 · 0.60 · 0.60 · 0.51",
            why: "As good as Avg every year. The rank against league starters makes the number readable."),
        Row(stat: "5. Snap share", number: "0.54 · 0.52 · 0.51 · 0.50",
            why: "The second usage signal. Its top players went up after pickup every year (4.9 → 6.2, 5.4 → 6.0, 4.9 → 5.2, 5.4 → 6.3), but its single top pick rarely beat your lowest player."),
        Row(stat: "6. Sortino > 0", number: "50 · 52 · 49 · 48%",
            why: "Only useful as a yes/no: how often players above 0 beat a typical starter the next week, against 41 · 41 · 40 · 39% for players below 0. That split held every year. The raw number had no signal in any year."),
        Row(stat: "Games badge", number: "",
            why: "Stats on 1–3 games are the ones that cooled off most, so the game count stays in view."),
    ]

    private let moved: [Row] = [
        Row(stat: "Downside dev", number: "−0.56 · −0.58 · −0.59 · −0.51",
            why: "Looks strong, but it's mostly \"how far below a typical starter\", which is Avg flipped."),
        Row(stat: "SD", number: "0.42 · 0.48 · 0.42 · 0.36",
            why: "Positive only because good players have bigger swings. It tracks scoring level, not risk."),
        Row(stat: "Sortino ratio (raw number)", number: "0.38 · 0.48 · 0.42 · 0.35",
            why: "Weak for ranking. Kept as the > 0 flag instead."),
        Row(stat: "CV", number: "−0.28 · −0.23 · −0.34 · −0.26",
            why: "At or near the bottom of 17 stats tested every year. Says how consistent a player has been, not how good he'll be."),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("From replaying four seasons (2022–2025) of a 10-team half-PPR league (weeks 3–14): each week, every player on waivers was scored with only the games played before that week, then compared with how he scored for the rest of the season. Numbers are listed 2025 · 2024 · 2023 · 2022. Correlations run from 0 (no link) to 1 (perfect).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Replace, Watch or Don't replace") {
                    Text("Each pickup is compared with your lowest player at his position (lowest average over his last 2 games, bench included), on two things: Sleeper's projection for this week, and touches + targets over the last 2 games. Backtested on every team, every week of 2022–2025:")
                        .font(.subheadline)
                    RowView(row: Row(stat: "Replace (strong)", number: "75 · 74 · 68 · 64%",
                                     why: "Projection 2+ points higher and 4+ more touches + targets. The pickup outscored your player the rest of the season this often, by about 2–3.5 points a week. In 2023 and 2022 it did no better than plain Replace."))
                    RowView(row: Row(stat: "Replace", number: "71 · 68 · 68 · 66%",
                                     why: "Projection 2+ points higher and 2–4 more touches + targets. QBs: projection 2+ points higher (71 · 62 · 57 · 45%), the least steady call. Check the news before swapping a QB."))
                    RowView(row: Row(stat: "Watch", number: "46 · 44 · 40 · 47%",
                                     why: "Only one of the two signals. A coin flip that slightly favors keeping your player, so check the news before claiming."))
                    RowView(row: Row(stat: "Don't replace", number: "11 · 12 · 9 · 13%",
                                     why: "Neither signal. The pickup almost never outscored your player."))
                    Text("Needs 2+ games, including the most recent week, to say Replace. A better average alone was a bad reason to switch: pickups chosen that way won only 37–51% of the time.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Injuries and role changes") {
                    Text("From Sleeper's player list (injury status, refreshed every 2 hours) and each team's usage this season.")
                        .font(.subheadline)
                    RowView(row: Row(stat: "Out, IR, Doubtful", number: "",
                                     why: "Never recommended to start, and never a Replace pickup. Shown in red next to the name."))
                    RowView(row: Row(stat: "Questionable", number: "",
                                     why: "A warning only (orange). Check before kickoff."))
                    RowView(row: Row(stat: "Lead role", number: "",
                                     why: "Most touches + targets at his position on his team this season (2+ games)."))
                    RowView(row: Row(stat: "Likely lead", number: "",
                                     why: "The lead is out and he's the clear next man up. If two backups are within 75% of each other's usage it's a Committee instead."))
                    RowView(row: Row(stat: "Role-adjusted touches", number: "RB 0.43 · WR 0.69 · TE 0.55",
                                     why: "Expected touches = w × his last-2-game touches + (1 − w) × the lead's touches per game, then × his points per touch (pulled toward RB 0.74 · WR 1.33 · TE 1.31 per touch). The weights w come from 377 games in 2022–25 where a lead RB/WR/TE sat out: RB backups jumped +5.4 touches and +4.5 points on average (they inherit much of the workload), WRs +1.0 touches, TEs +1.3. For RBs this cut the touch error from 7.4 to 6.2, and helped in 3 of the 4 seasons (not 2022)."))
                    Text("A likely lead's waiver call uses his role-adjusted touches instead of his last 2 games. Turn on \"Starter out: show backups only\" to list just these players.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("FAAB bids for backups") {
                    Text("Likely lead and Committee cards suggest a FAAB bid. From every game in 2022–2025 where a lead RB/WR/TE sat out (377 games):")
                        .font(.subheadline)
                    RowView(row: Row(stat: "Backups added", number: "21%",
                                     why: "Of 234 backups on waivers, most weren't added at all, and 72% of those added went for $0 as free agents."))
                    RowView(row: Row(stat: "Winning bids", number: "median $3",
                                     why: "90th percentile $6. RB max $5, WR max $4, TE max $17 (one claim on Trey McBride; only 3 TE claims). When two teams bid, the winner beat the 2nd bid by about $3."))
                    RowView(row: Row(stat: "After the lead returned", number: "7.7 pts",
                                     why: "Backups scored 6.4 before, 11.3 in the vacancy game and 7.7 afterwards, so a short absence is mostly a one- or two-week rental."))
                    RowView(row: Row(stat: "Short absence (Out, Doubtful)", number: "",
                                     why: "By role-adjusted points expected: 10+ is $5–7, 8–10 is $3–5, 6–8 is $1–3, under 6 (or a committee) is $0–1."))
                    RowView(row: Row(stat: "Lead on IR", number: "",
                                     why: "The role could last, so ranges follow the league's bids on any RB/WR/TE claim (median $2, 90th $10): 10+ is $8–12, 8–10 is $7–11, 6–8 is $3–6, under 6 is $1–3."))
                    Text("The top of any range is capped at about 30% of the FAAB you have left. In the back half of the waiver order, bid odd amounts: ties go to waiver order. The sample is small (18 FAAB claims in four seasons), so treat these as how this league has behaved, not a rule.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Upcoming week: defense calls (your data, no projections)") {
                    Text("Under DEF → Upcoming week, each defense gets an Expected FPTS for this week, built only from your league's own numbers:")
                        .font(.subheadline)
                    Text("Expected FPTS = own avg + (opponent's allowed avg − league avg)")
                        .font(.subheadline.monospaced())
                    RowView(row: Row(stat: "Own avg", number: "",
                                     why: "The defense's fantasy points per game this season, with your league's scoring. How good the defense is."))
                    RowView(row: Row(stat: "Opponent's allowed avg", number: "",
                                     why: "Fantasy points per game that earlier defenses scored against this week's opponent. How friendly the matchup is."))
                    RowView(row: Row(stat: "League avg", number: "",
                                     why: "Average fantasy points of every defense in every game so far. The opponent term is how much easier or harder than a typical opponent this one is."))
                    RowView(row: Row(stat: "Smoothing", number: "2 games",
                                     why: "Each average is pulled toward the league average as if it had 2 extra games at that average. Early in the season one blowout would otherwise swing everything; the effect fades as real games pile up."))
                    RowView(row: Row(stat: "Weights", number: "equal",
                                     why: "The defense and the matchup count equally. Backtested against 1/3–2/3 and 60/40 mixes; equal weights held up as well as any and are easiest to read."))
                    RowView(row: Row(stat: "Window", number: "whole season",
                                     why: "Always the whole season, whatever Games used says. On the last 2 games, Replace calls were right only about 40% of the time in 2025."))
                    Text("The call, and how often the pickup outscored your defense that week:")
                        .font(.subheadline)
                    RowView(row: Row(stat: "Replace", number: "53 · 73 · 47 · 46%", why: "Expected FPTS 4+ higher than your defense's."))
                    RowView(row: Row(stat: "Watch", number: "43 · 50 · 40 · 42%", why: "Within ±4. The gap is too small to matter."))
                    RowView(row: Row(stat: "Don't replace", number: "34 · 32 · 39 · 41%", why: "4+ lower."))
                    Text("For comparison: looking only at the opponent was 53 · 60 · 47 · 49% on Replace, and Sleeper's projection (the Season view's call) was 67 · 81 · 53 · 58%. You chose your own data here on purpose. 2024 was the easy year; in 2023 and 2022 every method's edge shrank, so treat Replace here as a nudge, not a lock. The per-game rows under it (FPTS, points allowed, sacks, ...) still follow Games used, and the list is sorted by FPTS.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Kickers and defenses") {
                    Text("These are this-week (streaming) calls, judged on Sleeper's projection for this week. Numbers are how often the pickup outscored your player that week. Holding a pickup for the rest of the season didn't reliably help.")
                        .font(.subheadline)
                    RowView(row: Row(stat: "Your K or DEF isn't playing", number: "70–85%",
                                     why: "Bye or ruled out: Replace this week with anyone who is playing."))
                    RowView(row: Row(stat: "DEF: Replace (strong)", number: "67 · 81 · 53 · 58%", why: "Projected 2+ points higher."))
                    RowView(row: Row(stat: "DEF: Replace", number: "60 · 74 · 50 · 54%", why: "Projected 1–2 points higher."))
                    RowView(row: Row(stat: "DEF: Watch", number: "51 · 63 · 44 · 48%", why: "Projected 0–1 point higher."))
                    RowView(row: Row(stat: "DEF: Don't replace", number: "31 · 35 · 33 · 35%", why: "Projected lower than yours."))
                    RowView(row: Row(stat: "K: Watch", number: "50 · 57 · 37 · 63%",
                                     why: "Projected 1+ point higher. Kicker projections are too close together to reliably beat a healthy kicker, so a kicker only gets Replace when yours isn't playing."))
                    RowView(row: Row(stat: "K: Don't replace", number: "32 · 38 · 37 · 37%", why: "Projected less than a point higher, or lower."))
                }
                Section("On each card, in this order") {
                    ForEach(shown) { row in RowView(row: row) }
                }
                Section("Moved to the compare page") {
                    ForEach(moved) { row in RowView(row: row) }
                }
                Section("Defaults") {
                    Text("**Rank by Touches + targets** because it best finds players whose role is growing. **Last 2 games** reacts fastest to a new role. Touches over the last 2 games scored 0.60 · 0.54 · 0.55 · 0.51, the last 3 games 0.61 · 0.57 · 0.57 · 0.53, and the whole season 0.60 · 0.59 · 0.59 · 0.55, so a longer window was a bit steadier in every year but 2025.")
                        .font(.subheadline)
                }
                Section("Keep in mind") {
                    Text("The league's own pickups did better than any stat in all four years (8.1 → 10.0, 7.2 → 9.6, 7.9 → 9.3 and 7.3 → 9.0 pts/game after pickup), because managers act on news like injuries and depth-chart changes. Use these stats to spot who's getting the ball, then check the news.")
                        .font(.subheadline)
                }
            }
            .navigationTitle("Why these stats")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private struct RowView: View {
        let row: Row

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                // Four seasons of numbers don't always fit beside the name; they wrap below it.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.stat).font(.subheadline.weight(.semibold))
                        Spacer()
                        number
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.stat).font(.subheadline.weight(.semibold))
                        number
                    }
                }
                Text(row.why).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }

        @ViewBuilder private var number: some View {
            if !row.number.isEmpty {
                Text(row.number).font(.subheadline.monospacedDigit()).foregroundStyle(Color.accentColor).lineLimit(1)
            }
        }
    }
}
