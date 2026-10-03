"""Replace / Watch / Don't replace backtest.

For every team, week 3-14 and position, compare each available player (2+ games, played last week)
with that team's lowest player at the position (lowest avg over the last 2 games, bench included,
as the Waivers card does). Outcome: did the pickup score more points over weeks w..14 than the
player he'd replace? Points per week, with 0 for weeks a player didn't play.
"""
import json, math, statistics as st
from collections import defaultdict
src = open(__import__('os').path.join(__import__('os').path.dirname(__file__), 'waiver_backtest_2025.py')).read().split("# ---------- 1. Does")[0]
exec(src)

PR = {w: json.load(open(f'p{w}.json')) for w in REG_WEEKS}
def proj(pid, w):
    s = PR[w].get(pid)
    if not s or s.get('gp', 1) == 0: return 0.0
    return sum(v * sc.get(k, 0) for k, v in s.items() if isinstance(v, (int, float)))

def usage(pid, w, last=2):
    xs = []
    for x in range(w - 1, 0, -1):
        s = S[x].get(pid)
        if s and s.get('gp', 0) > 0:
            xs.append(s.get('rush_att', 0) + s.get('rec_tgt', 0))
            if len(xs) == last: break
    return sum(xs) / len(xs) if xs else None

def ros_per_week(pid, w):
    return sum(week_pts(pid, x) for x in range(w, ROS_END + 1)) / (ROS_END - w + 1)

rows = []
for w in range(3, 15):
    pool = candidates(w)
    for t in M[w - 1]:                       # rosters as they stood going into week w
        for position in ('QB', 'RB', 'WR', 'TE'):
            mine = [q for q in t['players'] if pos(q) == position and windowed(q, w, 2)]
            if not mine: continue
            low = min(mine, key=lambda q: windowed(q, w, 2)['mean'])
            lm = windowed(low, w, 2)
            for p in pool:
                if pos(p) != position: continue
                pm = windowed(p, w, 2)
                rows.append(dict(
                    w=w, pos=position,
                    dP=proj(p, w) - proj(low, w),
                    dA=pm['mean'] - lm['mean'],
                    dT=(usage(p, w) - usage(low, w)) if position != 'QB' and usage(p, w) is not None and usage(low, w) is not None else None,
                    win=ros_per_week(p, w) > ros_per_week(low, w),
                    margin=ros_per_week(p, w) - ros_per_week(low, w)))
print('pickup-vs-lowest pairs:', len(rows))
base = sum(r['win'] for r in rows) / len(rows)
print(f'any available player beats the lowest: {base:.1%}')

def report(label, pred, subset=None):
    sel = [r for r in (subset or rows) if pred(r)]
    if len(sel) < 15:
        print(f'   {label:44s} n={len(sel)} (too few)'); return
    print(f'   {label:44s} right {sum(r["win"] for r in sel) / len(sel):5.1%}  avg gain {st.mean(r["margin"] for r in sel):+5.1f} pts/wk  n={len(sel)}')

print('-- single-signal rules (all positions)')
for x in (2, 4, 6, 8):
    report(f'projection gap >= {x}', lambda r, x=x: r['dP'] >= x)
for x in (3, 6, 9):
    report(f'avg (last 2) gap >= {x}', lambda r, x=x: r['dA'] >= x)
skill = [r for r in rows if r['dT'] is not None]
print('-- RB/WR/TE only')
for x in (2, 4, 6):
    report(f'touches+targets gap >= {x}', lambda r, x=x: r['dT'] >= x, skill)
print('-- combined rules (RB/WR/TE)')
for x in (2, 3, 4, 6):
    for y in (0, 2, 4):
        report(f'proj gap >= {x} and touches gap >= {y}', lambda r, x=x, y=y: r['dP'] >= x and r['dT'] >= y, skill)
print('-- QB')
qb = [r for r in rows if r['pos'] == 'QB']
for x in (2, 4, 6):
    report(f'QB projection gap >= {x}', lambda r, x=x: r['dP'] >= x, qb)
json.dump(rows, open('waiver_rules_rows.json', 'w'))
