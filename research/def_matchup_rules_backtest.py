"""Defense calls from matchup FPTS only (no projections).
Matchup FPTS = average fantasy points that earlier defenses scored against this week's opponent,
over the opponent's last 2 games. Gap = pickup's matchup FPTS - my defense's matchup FPTS.
Outcome: did the pickup outscore my defense that week?"""
import json, statistics as st
from collections import defaultdict
src = open(__import__('os').path.join(__import__('os').path.dirname(__file__), 'waiver_backtest_2025.py')).read().split("# ---------- 1. Does")[0]
exec(src)
sched = json.load(open('schedule.json'))
opp = defaultdict(dict)
for g in sched:
    opp[g['week']][g['home']] = g['away']; opp[g['week']][g['away']] = g['home']
def def_fpts(team, w):
    s = S[w].get(team)
    if not s or not s.get('gp'): return None
    return pts(s)
def matchup_fpts(team, w, last=2):
    o = opp[w].get(team)
    if not o: return None
    xs = []
    for x in range(w - 1, 0, -1):
        d = opp[x].get(o)
        if d is not None:
            f = def_fpts(d, x)
            if f is not None: xs.append(f)
        if len(xs) == last: break
    return sum(xs) / len(xs) if xs else None
rows = []
for w in range(3, 15):
    pool = [p for p in candidates(w) if pos(p) == 'DEF']
    for t in M[w - 1]:
        mine = [q for q in t['players'] if pos(q) == 'DEF' and windowed(q, w, 2)]
        if not mine: continue
        low = min(mine, key=lambda q: windowed(q, w, 2)['mean'])
        ml = matchup_fpts(low, w)
        if ml is None or not played(low, w): continue          # my DEF on bye: handled separately
        for p in pool:
            mp = matchup_fpts(p, w)
            if mp is None or not played(p, w): continue
            rows.append((mp - ml, week_pts(p, w) > week_pts(low, w), week_pts(p, w) - week_pts(low, w)))
print('pairs:', len(rows))
for lo, hi in [(-99, -6), (-6, -4), (-4, -2), (-2, -1), (-1, 1), (1, 2), (2, 4), (4, 6), (6, 99)]:
    sel = [r for r in rows if lo <= r[0] < hi]
    if sel: print(f'   gap {lo:>4} to {hi:<4}: pickup won {sum(r[1] for r in sel) / len(sel):5.1%}  avg margin {st.mean(r[2] for r in sel):+5.1f}  n={len(sel)}')
for x in (1, 2, 3, 4):
    up = [r for r in rows if r[0] >= x]; mid = [r for r in rows if -x < r[0] < x]; down = [r for r in rows if r[0] <= -x]
    f = lambda s: f'{sum(r[1] for r in s) / len(s):5.1%} (n={len(s)})' if s else '-'
    print(f'threshold {x}: Replace {f(up)} | Watch {f(mid)} | Don\'t replace {f(down)}')
