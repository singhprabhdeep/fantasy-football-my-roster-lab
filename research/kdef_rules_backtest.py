"""Kicker and defense pickup rules: this week and rest of season, weeks 3-14."""
import json, statistics as st
from collections import defaultdict
src = open(__import__('os').path.join(__import__('os').path.dirname(__file__), 'waiver_backtest_2025.py')).read().split("# ---------- 1. Does")[0]
exec(src)
PR = {w: json.load(open(f'p{w}.json')) for w in REG_WEEKS}
def proj(pid, w):
    s = PR[w].get(pid)
    if not s or s.get('gp', 1) == 0: return 0.0
    return sum(v * sc.get(k, 0) for k, v in s.items() if isinstance(v, (int, float)))
def ros_per_week(pid, w):
    return sum(week_pts(pid, x) for x in range(w, ROS_END + 1)) / (ROS_END - w + 1)
rows = []
for w in range(3, 15):
    pool = candidates(w)
    for t in M[w - 1]:
        for position in ('K', 'DEF'):
            mine = [q for q in t['players'] if pos(q) == position and windowed(q, w, 2)]
            if not mine: continue
            low = min(mine, key=lambda q: windowed(q, w, 2)['mean'])
            for p in pool:
                if pos(p) != position: continue
                rows.append(dict(pos=position, bye=proj(low, w) == 0, dP=proj(p, w) - proj(low, w),
                                 dA=windowed(p, w, 2)['mean'] - windowed(low, w, 2)['mean'],
                                 dS=windowed(p, w)['mean'] - windowed(low, w)['mean'],
                                 wk=week_pts(p, w) > week_pts(low, w), wkm=week_pts(p, w) - week_pts(low, w),
                                 ros=ros_per_week(p, w) > ros_per_week(low, w), rosm=ros_per_week(p, w) - ros_per_week(low, w)))
def rep(label, pred, position):
    sel = [r for r in rows if r['pos'] == position and not r['bye'] and pred(r)]
    if len(sel) < 15: print(f'   {label:34s} n={len(sel)}'); return
    print(f'   {label:34s} this week {sum(r["wk"] for r in sel) / len(sel):5.1%} ({st.mean(r["wkm"] for r in sel):+4.1f})'
          f' | rest of season {sum(r["ros"] for r in sel) / len(sel):5.1%} ({st.mean(r["rosm"] for r in sel):+4.1f})  n={len(sel)}')
for position in ('K', 'DEF'):
    print(f'-- {position}')
    byes = [r for r in rows if r['pos'] == position and r['bye']]
    print(f'   (your {position} not projected to play: {len(byes)} pairs, any pickup won this week {sum(r["wk"] for r in byes) / max(1, len(byes)):5.1%})')
    rep('everyone available', lambda r: True, position)
    for x in (1, 2, 3, 4):
        rep(f'projection gap >= {x}', lambda r, x=x: r['dP'] >= x, position)
    rep('projection gap 0-1', lambda r: 0 <= r['dP'] < 1, position)
    rep('projection gap < 0', lambda r: r['dP'] < 0, position)
    for x in (2, 4):
        rep(f'season avg gap >= {x}', lambda r, x=x: r['dS'] >= x, position)
        rep(f'proj gap >= 2 and season avg gap >= {x}', lambda r, x=x: r['dP'] >= 2 and r['dS'] >= x, position)
    rep('proj gap >= 1 and season avg gap >= 0', lambda r: r['dP'] >= 1 and r['dS'] >= 0, position)
