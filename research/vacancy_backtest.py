"""Vacancy effect: when a team's lead RB/WR/TE misses a game, how much does the next man up's usage jump?

Lead = most touches + targets for that team at the position over the prior weeks (2+ games).
Vacancy week = the lead didn't play but the team did, and the lead played for the same team
within the 2 weeks before (so it's an absence, not a trade or cut).
Backup = the teammate at the position with the most touches + targets in prior weeks (excluding the lead).
Fit: backup's vacancy-week touches ≈ w × his own recent avg + (1 − w) × lead's avg.
"""
import json, statistics as st
from collections import defaultdict

def load(year):
    weeks = {}
    for w in range(1, 19):
        rows = json.load(open(f'ts_{year}_{w}.json'))
        weeks[w] = {r['player_id']: r for r in rows if r['stats'].get('gp', 0) > 0}
    return weeks

def touches(s): return s.get('rush_att', 0) + s.get('rec_tgt', 0)

def study(year):
    W = load(year)
    events = []
    for w in range(3, 18):
        teams_playing = {r['team'] for r in W[w].values()}
        for pos in ('RB', 'WR', 'TE'):
            by_team = defaultdict(lambda: defaultdict(list))   # team -> player -> [(week, touches)]
            for x in range(1, w):
                for pid, r in W[x].items():
                    if r['player'].get('position') == pos:
                        by_team[r['team']][pid].append((x, touches(r['stats'])))
            for team, players in by_team.items():
                if team not in teams_playing: continue
                ranked = sorted(players, key=lambda p: -sum(t for _, t in players[p]) / max(1, len(players[p])))
                ranked = [p for p in ranked if len(players[p]) >= 2]
                if len(ranked) < 2: continue
                lead = ranked[0]
                if lead in W[w]: continue                                   # lead played
                if max(x for x, _ in players[lead]) < w - 2: continue      # long gone: not a fresh absence
                lead_avg = st.mean(t for _, t in players[lead])
                backup = next((p for p in ranked[1:] if p in W[w] and W[w][p]['team'] == team), None)
                if backup is None: continue
                own = [t for _, t in players[backup]]
                own_recent = st.mean(own[-2:])
                actual = touches(W[w][backup]['stats'])
                # everyone else at the position on the team that week
                others = sum(touches(r['stats']) for pid, r in W[w].items()
                             if r['team'] == team and r['player'].get('position') == pos and pid != backup)
                events.append(dict(year=year, week=w, team=team, backup=backup, lead=lead,
                                   backup_name=W[w][backup]['player'].get('first_name', '') + ' ' + W[w][backup]['player'].get('last_name', ''),
                                   pos=pos, lead_avg=lead_avg, own=own_recent, actual=actual,
                                   share=actual / (actual + others) if actual + others else 0,
                                   pts=W[w][backup]['stats'].get('pts_half_ppr', 0),
                                   own_pts=st.mean([W[x][backup]['stats'].get('pts_half_ppr', 0) for x, _ in players[backup]][-2:])))
    return events

def fit_w(ev):
    """Least squares for actual − lead = w (own − lead), i.e. actual = w·own + (1−w)·lead."""
    xs = [e['own'] - e['lead_avg'] for e in ev]; ys = [e['actual'] - e['lead_avg'] for e in ev]
    return sum(x * y for x, y in zip(xs, ys)) / sum(x * x for x in xs)

def mae(ev, w):
    return st.mean(abs(e['actual'] - (w * e['own'] + (1 - w) * e['lead_avg'])) for e in ev)

YEARS = tuple(sorted({int(f.split('_')[1]) for f in __import__('os').listdir('.') if f.startswith('ts_')}, reverse=True))
ALL = {y: study(y) for y in YEARS}
for year in YEARS:
    ev = ALL[year]
    print(f'===== {year}: {len(ev)} vacancy games')
    for pos in ('RB', 'WR', 'TE'):
        e = [x for x in ev if x['pos'] == pos]
        if len(e) < 8: print(f'  {pos}: n={len(e)}'); continue
        w = fit_w(e)
        print(f'  {pos}: n={len(e):3d}  backup {st.mean(x["own"] for x in e):5.1f} -> {st.mean(x["actual"] for x in e):5.1f} touches (lead {st.mean(x["lead_avg"] for x in e):5.1f})  pts {st.mean(x["own_pts"] for x in e):4.1f} -> {st.mean(x["pts"] for x in e):4.1f}  w={w:.2f}  miss own {mae(e, 1):4.1f} fitted {mae(e, w):4.1f}')
print(f'===== pooled: latest 2 seasons vs all {len(YEARS)} seasons')
for pos in ('RB', 'WR', 'TE'):
    e2 = [x for y in YEARS[:2] for x in ALL[y] if x['pos'] == pos]
    e4 = [x for y in YEARS for x in ALL[y] if x['pos'] == pos]
    w2, w4 = fit_w(e2), fit_w(e4)
    base = sum(x['own_pts'] for x in e4) / sum(x['own'] for x in e4)
    print(f'  {pos}: w 2 seasons {w2:.2f} (n={len(e2)}) -> all seasons {w4:.2f} (n={len(e4)})  pts/touch {base:.2f}  miss own {mae(e4, 1):4.1f} fitted {mae(e4, w4):4.1f}'
          f'  jump {st.mean(x["actual"] - x["own"] for x in e4):+.1f} touches {st.mean(x["pts"] - x["own_pts"] for x in e4):+.1f} pts')
    for y in YEARS:
        ey = [x for x in ALL[y] if x['pos'] == pos]
        print(f'      {y}: miss with pooled w {mae(ey, w4):4.1f} vs own-only {mae(ey, 1):4.1f}')
json.dump({str(y): ALL[y] for y in YEARS}, open('vacancy_events.json', 'w'))
