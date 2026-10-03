# Research

The backtests behind every rule and percentage in the app. Each script replays a season week by week using only data available before that week, then checks what actually happened. Results are summarized in [docs/BACKTESTS.md](../docs/BACKTESTS.md).

## Get data

```bash
python3 research/fetch_season.py --league <your Sleeper league id> --seasons 4 --out data
```

This writes one folder per season (`data/2025/`, `data/2024/`, ...) with the league, users, rosters, players, schedule, and per-week matchups (`m{w}`), stats (`s{w}`), projections (`p{w}`) and transactions (`t{w}`), plus `data/ts_<season>_<week>.json` (RB/WR/TE stats with each player's team). Your league id is in the Sleeper web URL: `sleeper.com/leagues/<id>`.

## Run

Season scripts run from a season folder. `MY_ROSTER` is your roster id in the league (1–N, in `rosters.json`).

```bash
cd data/2025
MY_ROSTER=5 python3 ../../research/backtest_2025.py
python3 ../../research/waiver_rules_backtest.py && python3 ../../research/waiver_bands.py
```

The vacancy and FAAB studies span seasons and run from `data/`:

```bash
cd data
python3 ../research/vacancy_backtest.py && python3 ../research/faab_vacancy_study.py
```

## Scripts

| Script | What it answers | Feeds |
| --- | --- | --- |
| `backtest_2025.py` | Which stats predict next week; lineup totals vs results; a lineup replay for your team. Shared loaders for the others. | Stat order on My Roster |
| `waiver_backtest_2025.py` | Which stats find good pickups; one-move-a-week replay. | Waiver card |
| `waiver_all_stats_2025.py` | Every stat's correlation with rest-of-season points on the waiver pool. | Waiver card, "Why these stats" |
| `waiver_usage_signals_2025.py`, `waiver_cooloff.py`, `waiver_head_to_head.py` | Usage vs points signals; do hot streaks cool; does the top pick beat your lowest player. | Waiver card |
| `roster_usage_2025.py` | Usage vs points for rostered players' next week. | My Roster rows |
| `lineup_strategies.py` | Lineups set by avg, risk-adj, last 3, projection, hindsight. | Start/sit |
| `startsit_backtest.py` | Projection-led start/sit, confidence calibration, miss SD by position. | Start/sit % |
| `waiver_rules_backtest.py` + `waiver_bands.py` | Replace / Watch / Don't replace thresholds and hit rates. | Waiver % |
| `kdef_rules_backtest.py` | Kicker and defense pickups: this week vs rest of season. | K/DEF % |
| `def_matchup_rules_backtest.py`, `def_matchup_blends_backtest.py`, `def_expected_backtest.py` | Defense calls from matchups and Expected FPTS (weights, smoothing, band). | Upcoming week defenses |
| `vacancy_backtest.py` | When a lead RB/WR/TE sits, how much the next man up's usage jumps. | Likely lead / role-adjusted touches |
| `faab_vacancy_study.py` | What the league paid in FAAB for those backups, who bid, and how the backup scored after. | FAAB bid ranges |

Scripts with `_2025` in the name were written for the 2025 season first; they run on any season's folder.
