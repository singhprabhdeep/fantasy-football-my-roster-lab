"""Replay a league's season with the app's metrics, using only data known before each week."""
import json, math, os, statistics as st
from collections import defaultdict

REG_WEEKS = range(1, 15)      # playoffs start week 15
EVAL_WEEKS = range(3, 15)     # need 2 prior weeks
K = 1.0
MY_ROSTER = int(os.environ.get('MY_ROSTER', 5))   # your roster id in the league
SLOTS = ['QB', 'RB', 'RB', 'WR', 'WR', 'TE', 'FLEX', 'FLEX', 'K', 'DEF']
FLEX_OK = {'RB', 'WR', 'TE'}

lg = json.load(open('league.json')); sc = lg['scoring_settings']
P = json.load(open('players.json'))
users = {u['user_id']: u['display_name'] for u in json.load(open('users.json'))}
rosters = json.load(open('rosters.json'))
owner = {r['roster_id']: users.get(r['owner_id'], str(r['roster_id'])) for r in rosters}
M = {w: json.load(open(f'm{w}.json')) for w in REG_WEEKS}
S = {w: json.load(open(f's{w}.json')) for w in REG_WEEKS}

def pos(pid):
    p = P.get(pid, {})
    return p.get('position') or (p.get('fantasy_positions') or [None])[0]

def pts(stats):
    return sum(v * sc.get(k, 0) for k, v in stats.items() if isinstance(v, (int, float)))

# Weekly base: average of every league starter at each position (FLEX by real position).
base = {}
for w in REG_WEEKS:
    sums, cnt = defaultdict(float), defaultdict(int)
    for t in M[w]:
        for pid, p in zip(t['starters'], t['starters_points']):
            if pid != '0' and pos(pid):
                sums[pos(pid)] += p; cnt[pos(pid)] += 1
    base[w] = {k: sums[k] / cnt[k] for k in sums}

def history(pid, before):
    """(points, base) for weeks the player played, strictly before `before`."""
    out = []
    for w in range(1, before):
        s = S[w].get(pid)
        if s and s.get('gp', 0) > 0:
            out.append((pts(s), base[w].get(pos(pid))))
    return out

def metrics(pid, before):
    h = history(pid, before)
    if not h: return None
    x = [p for p, _ in h]; n = len(x); mean = sum(x) / n
    sd = st.stdev(x) if n >= 2 else None
    gaps = [p - b for p, b in h if b is not None]
    dd = math.sqrt(sum(min(0, g) ** 2 for g in gaps) / len(gaps)) if gaps else None
    ex = sum(gaps) / len(gaps) if gaps else None
    sortino = (ex / dd) if dd else (math.inf if gaps else None)
    ram = mean - K * dd if dd is not None else mean
    return dict(n=n, mean=mean, sd=sd, dd=dd, sortino=sortino, ram=ram,
                cv=(sd / mean if sd is not None and mean >= 2 else None))

def neutral(position, before):
    """Score for a player with no history: that position's average base so far."""
    vals = [base[w][position] for w in range(1, before) if position in base[w]]
    return sum(vals) / len(vals) if vals else 0

def score(pid, before, key):
    m = metrics(pid, before)
    if m is None: return neutral(pos(pid), before)
    return m[key]

def pearson(a, b):
    ma, mb = sum(a) / len(a), sum(b) / len(b)
    num = sum((x - ma) * (y - mb) for x, y in zip(a, b))
    den = math.sqrt(sum((x - ma) ** 2 for x in a) * sum((y - mb) ** 2 for y in b))
    return num / den if den else float('nan')

def spearman(a, b):
    def ranks(v):
        order = sorted(range(len(v)), key=lambda i: v[i]); r = [0] * len(v)
        for rank, i in enumerate(order): r[i] = rank
        return r
    return pearson(ranks(a), ranks(b))

def best_lineup(players, value):
    """Fill the league's lineup slots with the highest `value` players. Returns the chosen ids."""
    pool = sorted([p for p in players if pos(p)], key=value, reverse=True)
    used, chosen = set(), []
    for slot in [s for s in SLOTS if s != 'FLEX']:
        for p in pool:
            if p not in used and pos(p) == slot:
                used.add(p); chosen.append(p); break
    for _ in range(SLOTS.count('FLEX')):
        for p in pool:
            if p not in used and pos(p) in FLEX_OK:
                used.add(p); chosen.append(p); break
    return chosen

# ---------- 1. Team level: do lineup totals line up with weekly scores and wins? ----------
team_rows = []
for w in EVAL_WEEKS:
    by_matchup = defaultdict(list)
    for t in M[w]:
        starters = [p for p in t['starters'] if p != '0']
        avg_total = sum(score(p, w, 'mean') for p in starters)
        ram_total = sum(score(p, w, 'ram') for p in starters)
        sds = [metrics(p, w) for p in starters]
        lineup_sd = math.sqrt(sum((m['sd'] or 0) ** 2 for m in sds if m))
        prior = [x['points'] for pw in range(1, w) for x in M[pw] if x['roster_id'] == t['roster_id']]
        row = dict(w=w, rid=t['roster_id'], actual=t['points'], avg_total=avg_total, ram_total=ram_total,
                   sd=lineup_sd, naive=sum(prior) / len(prior))
        team_rows.append(row); by_matchup[t['matchup_id']].append(row)
    for pair in by_matchup.values():
        if len(pair) == 2:
            a, b = pair
            a['won'] = a['actual'] > b['actual']; b['won'] = not a['won']
            for key in ('avg_total', 'ram_total', 'naive'):
                a[f'fav_{key}'] = a[key] > b[key]; b[f'fav_{key}'] = not a[f'fav_{key}']

actual = [r['actual'] for r in team_rows]
print('=== Team-week (weeks 3-14, %d team-weeks) ===' % len(team_rows))
for key, label in [('avg_total', 'Starters avg total'), ('ram_total', 'Risk-adj total'), ('naive', 'Season-to-date points avg (baseline)')]:
    r = pearson([x[key] for x in team_rows], actual)
    picks = [x for x in team_rows if f'fav_{key}' in x]
    acc = sum(x[f'fav_{key}'] == x['won'] for x in picks) / len(picks)
    mae = st.mean(abs(x[key] - x['actual']) for x in team_rows)
    print(f'{label:40s} corr with weekly score {r:5.2f}   picks matchup winner {acc:5.1%}   avg miss {mae:5.1f} pts')
err = [abs(x['actual'] - x['avg_total']) for x in team_rows]
print('Lineup SD vs size of miss: corr %.2f' % pearson([x['sd'] for x in team_rows], err))
inside = sum(abs(x['actual'] - x['avg_total']) <= x['sd'] for x in team_rows) / len(team_rows)
print('Weeks landing within +/-1 lineup SD of avg total: %.0f%%' % (inside * 100))

# ---------- 2. Season level: do the stats line up with final standings? ----------
print('\n=== Season (regular season) ===')
season = []
for r in rosters:
    rid = r['roster_id']; s = r['settings']
    rows = [x for x in team_rows if x['rid'] == rid]
    season.append(dict(rid=rid, name=owner[rid], wins=s['wins'], pf=s['fpts'] + s.get('fpts_decimal', 0) / 100,
                       avg_total=st.mean(x['avg_total'] for x in rows), ram_total=st.mean(x['ram_total'] for x in rows),
                       sd=st.mean(x['sd'] for x in rows)))
season.sort(key=lambda x: (-x['wins'], -x['pf']))
for i, x in enumerate(season, 1): x['finish'] = i
for key, label in [('avg_total', 'Avg weekly starters avg total'), ('ram_total', 'Avg weekly risk-adj total')]:
    print(f'{label:32s} rank corr with wins {spearman([x[key] for x in season], [x["wins"] for x in season]):5.2f}'
          f'   with points for {spearman([x[key] for x in season], [x["pf"] for x in season]):5.2f}')
print(f'{"Points for":32s} rank corr with wins {spearman([x["pf"] for x in season], [x["wins"] for x in season]):5.2f}')
print('finish  team            W  PF       avgTot  riskTot  lineupSD')
for x in season:
    print(f'{x["finish"]:>5}  {x["name"]:15s} {x["wins"]:2d}  {x["pf"]:7.1f}  {x["avg_total"]:6.1f}  {x["ram_total"]:7.1f}  {x["sd"]:6.1f}')

# ---------- 3. Player level: which stat predicts next week best? ----------
print('\n=== Player-week (started players with 2+ prior games) ===')
pl = []
for w in EVAL_WEEKS:
    for t in M[w]:
        for pid, p in zip(t['starters'], t['starters_points']):
            if pid == '0' or not pos(pid): continue
            m = metrics(pid, w)
            if not m or m['n'] < 2: continue
            b = base[w].get(pos(pid))
            pl.append(dict(pos=pos(pid), pts=p, beat=p >= b if b is not None else None, **m))
print('player-weeks:', len(pl))
for key in ('mean', 'ram', 'sortino', 'cv', 'sd'):
    rows = [x for x in pl if x[key] is not None and math.isfinite(x[key])]
    print(f'  {key:8s} corr with next-week points {pearson([x[key] for x in rows], [x["pts"] for x in rows]):5.2f}  (n={len(rows)})')
# Sortino buckets: how often does the player beat the base next week?
def bucket(s):
    if s is None: return None
    if s == math.inf: return 'inf (no bad weeks)'
    if s >= 1: return '>= 1'
    if s >= 0: return '0 to 1'
    if s > -0.9: return '-0.9 to 0'
    return '<= -0.9'
out = defaultdict(list)
for x in pl:
    b = bucket(x['sortino'])
    if b and x['beat'] is not None: out[b].append(x['beat'])
for b in ['inf (no bad weeks)', '>= 1', '0 to 1', '-0.9 to 0', '<= -0.9']:
    if out[b]: print(f'  Sortino {b:20s} beat the base next week {sum(out[b]) / len(out[b]):5.1%}  (n={len(out[b])})')
# Does a steadier player (low prior SD) actually land closer to his average?
rows = [x for x in pl if x['sd'] is not None]
print('  prior SD vs next-week miss from avg: corr %.2f' % pearson([x['sd'] for x in rows], [abs(x['pts'] - x['mean']) for x in rows]))
rows = [x for x in pl if x['cv'] is not None]
print('  prior CV vs next-week miss as share of avg: corr %.2f' % pearson([x['cv'] for x in rows], [abs(x['pts'] - x['mean']) / x['mean'] for x in rows]))

# ---------- 4. My lineups: what if you'd set them by the app's stats? ----------
print(f'\n=== My (roster {MY_ROSTER}) lineup replay ===')
opp_points = {}
for w in REG_WEEKS:
    groups = defaultdict(list)
    for t in M[w]: groups[t['matchup_id']].append(t)
    for g in groups.values():
        if len(g) == 2:
            opp_points[(w, g[0]['roster_id'])] = g[1]['points']; opp_points[(w, g[1]['roster_id'])] = g[0]['points']
record = defaultdict(lambda: [0, 0]); totals = defaultdict(float); weekly = []
for w in EVAL_WEEKS:
    t = next(x for x in M[w] if x['roster_id'] == MY_ROSTER)
    pp = t['players_points']
    # Byes and players ruled out are known before kickoff, so the stat-based lineups only pick
    # from players who actually suited up that week.
    active = [p for p in t['players'] if S[w].get(p, {}).get('gp', 0) > 0]
    lineups = {
        'You (actual)': [p for p in t['starters'] if p != '0'],
        'By avg': best_lineup(active, lambda p: score(p, w, 'mean')),
        'By risk-adj avg': best_lineup(active, lambda p: score(p, w, 'ram')),
        'Perfect hindsight': best_lineup(active, lambda p: pp.get(p, 0)),
    }
    opp = opp_points[(w, MY_ROSTER)]
    line = [w, round(opp, 1)]
    for name, ids in lineups.items():
        score_w = sum(pp.get(p, 0) for p in ids)
        totals[name] += score_w; record[name][0 if score_w > opp else 1] += 1
        line.append(round(score_w, 1))
    weekly.append(line)
print('week  opp    actual  byAvg  byRisk  perfect')
for l in weekly: print('  '.join(str(v).rjust(6) for v in l))
for name in totals:
    print(f'{name:18s} total {totals[name]:7.1f}  record weeks 3-14 {record[name][0]}-{record[name][1]}')

json.dump(dict(team_rows=team_rows, season=season, weekly=weekly, totals=totals, record={k: v for k, v in record.items()}),
          open('results.json', 'w'), default=str, indent=1)
