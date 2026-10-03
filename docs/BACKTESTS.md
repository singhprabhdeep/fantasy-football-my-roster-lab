# Backtests

Every rule and percentage in Roster Lab comes from replaying past seasons of one league: 10 teams, half PPR, $50 FAAB, a QB / 2 RB / 2 WR / TE / 2 FLEX / K / DEF lineup, playoffs from week 15. Seasons 2022–2025, weeks 3–14 unless noted.

**Method.** Each week, every stat is computed only from games played before that week, the way the app would have shown it at the time. The outcome is checked against what happened next: the next week's points for start/sit, the rest of the season for waiver pickups, that week for kicker and defense streaming. Scripts are in [`research/`](../research); run them on any league with `research/fetch_season.py`.

Numbers below read **2025 · 2024 · 2023 · 2022**.

## 1. Which stats predict anything?

Correlation with a player's points the next week (started players):

| Stat | 2025 · 2024 · 2023 · 2022 | What it means for the app |
| --- | --- | --- |
| Avg | 0.35 · 0.35 · 0.34 · 0.40 | Best simple predictor. Shown first on My Roster. |
| Risk-adj avg (avg − k × downside dev) | 0.28 · 0.28 · 0.30 · 0.33 | A little weaker, but readable as a floor. Kept, with a league rank. |
| Sortino ratio | 0.06 · 0.06 · 0.05 · 0.08 | No signal as a number. Kept only as a yes/no flag (below). |
| SD | 0.11 · 0.11 · 0.11 · 0.13 | Tracks scoring level, not risk. Moved off the main rows. |
| CV | −0.13 · −0.19 · −0.13 · −0.16 | Measures consistency, not quality. Moved off. |

The **Sortino > 0** flag held every year: players above 0 beat a typical starter the next week 50 · 52 · 49 · 48% of the time, against 41 · 41 · 40 · 39% for players below 0.

## 2. Setting a lineup

Lineups set by each method, compared with what managers actually started (points per week):

| Method | 2025 · 2024 · 2023 · 2022 |
| --- | --- |
| **Sleeper projection** | **+0.0 · +2.0 · +1.1 · +1.2** |
| 70% projection + 30% season avg | −0.5 · +1.8 · +0.3 · +0.2 |
| Season avg only | behind managers every season |

Every blend tried did worse than the projection alone, so start/sit follows the projection. Its confidence uses a normal model of how far scores land from projections (miss SD by position: QB 7.7, RB 7.1, WR 6.9, TE 6.3, K 4.8, DEF 6.2 points; the 2022–23 values matched within half a point). Predicted confidence matched actual hit rates within 1–3 points up to 85%, in all four seasons.

**Stats cross-check.** When the projection gap is under 6 points, the projection's pick was right just as often when the app's stats disagreed. With a gap of 6+ points and the stats disagreeing, it was right about 69% of the time instead of 79% (103 calls). The app shows the check but doesn't change the call.

## 3. Waiver pickups

Each pickup is compared with the team's lowest player at the position. A pickup "wins" if it outscores that player over the rest of the season.

Signals, correlation with rest-of-season points across the waiver pool:

| Signal | 2025 · 2024 · 2023 · 2022 |
| --- | --- |
| Touches + targets (last 3 games) | 0.61 · 0.57 · 0.57 · 0.53 |
| Avg | 0.54 · 0.60 · 0.59 · 0.50 |
| Snap share | 0.54 · 0.52 · 0.51 · 0.50 |
| Sortino ratio | 0.38 · 0.48 · 0.42 · 0.35 |

Top-5 picks by **Avg** cooled off after pickup (7.6→6.0, 7.7→6.7, 7.5→5.8, 7.9→5.4 points per game); top-5 by **touches + targets** held (6.2→6.5, 6.1→6.4, 6.1→5.7, 6.3→5.8). A better average alone was a bad reason to switch: 37–51% win rates.

The rule the app uses combines this week's projection with usage:

| Call | Rule | Pickup won, 2025 · 2024 · 2023 · 2022 |
| --- | --- | --- |
| Replace (strong) | projection +2 and touches + targets +4 | 75 · 74 · 68 · 64% |
| Replace | projection +2 and touches + targets +2 to 4 | 71 · 68 · 68 · 66% |
| Replace (QB) | projection +2 | 71 · 62 · 57 · 45% |
| Watch | only one of the two | 46 · 44 · 40 · 47% |
| Don't replace | neither | 11 · 12 · 9 · 13% |

Base rate: any available player beat the team's lowest only 14–18% of the time.

## 4. Kickers and defenses (this week only)

Holding a pickup for the rest of the season didn't reliably help, so these are streaming calls.

| Call | 2025 · 2024 · 2023 · 2022 |
| --- | --- |
| Your K/DEF isn't playing | 70–85% |
| DEF projected 2+ higher | 67 · 81 · 53 · 58% |
| DEF projected 1–2 higher | 60 · 74 · 50 · 54% |
| DEF projected lower | 31 · 35 · 33 · 35% |
| K projected 1+ higher (Watch only) | 50 · 57 · 37 · 63% |

**Upcoming-week defense view** (Expected FPTS = defense's average + opponent's points allowed − league average, ±4 band): Replace 53 · 73 · 47 · 46%, Don't replace 34 · 32 · 39 · 41%. The order holds every year, but outside 2024 the edge is small, so the app treats it as a nudge.

## 5. When a starter sits: role changes

377 games where a team's lead RB, WR or TE (by usage) missed a game. The next man up's touches were fitted as `w × his own recent touches + (1 − w) × the lead's`:

| Position | Games | w | Touches gained | Points gained |
| --- | --- | --- | --- | --- |
| RB | 131 | 0.43 | +5.4 | +4.5 |
| WR | 115 | 0.69 | +1.0 | +2.6 |
| TE | 131 | 0.55 | +1.3 | +1.8 |

RB backups take over much of the workload; WRs and TEs much less. For RBs the fitted model cut the touch error from 7.4 to 6.2, and helped in three of four seasons.

## 6. FAAB for those backups

What the league actually paid, from waiver transactions around each of those games:

- Of 234 backups who were on waivers, **21%** were added at all; 72% of adds were $0 free agents.
- Winning bids: median **$3**, 90th percentile $6, max $17. RB max $5, WR max $4, TE max $17 (one breakout tight end; only 3 TE claims).
- When two teams bid, the winner beat the second bid by about $3.
- Backups scored 6.4 points before, 11.3 in the game the lead missed, and 7.7 after he returned: a short absence is mostly a one- or two-week rental.
- Baseline, every RB/WR/TE claim: median $2, 90th percentile $10, max $43.

How the app turns this into a bid range: by role-adjusted points expected, higher when the lead is on IR (the role could last), capped at about 30% of the FAAB left, with a tip to bid odd amounts when you're in the back half of the waiver order. Sample size is small: 18 FAAB claims in four seasons.

## What changed when 2022–23 were added

The first version was tuned on 2024–25 only. Adding two more seasons:

- **Confirmed:** projection-led start/sit, the Replace rule, usage over hot streaks, the Sortino > 0 flag, Avg over risk-adj for next week.
- **Lowered:** every hit rate shown in the app now uses the four-season average; most dropped a few points.
- **Downgraded:** the QB swap rule (45% in 2022) now carries a warning; "Replace (strong)" was no better than Replace in 2022–23.
- **Refit:** RB backups inherit less of the lead's work than 2024–25 suggested (w 0.30 → 0.43), so Likely-lead RB projections dropped about 15%.
