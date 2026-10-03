src = open(__import__('os').path.join(__import__('os').path.dirname(__file__), 'waiver_backtest_2025.py')).read().split("# ---------- 1. Does")[0]
exec(src)
import statistics as st
def usage(pid, w, fn, last=None):
    xs = []
    for x in range(w - 1, 0, -1):
        s = S[x].get(pid)
        if s and s.get('gp', 0) > 0:
            v = fn(s)
            if v is not None: xs.append(v)
            if last and len(xs) == last: break
    return sum(xs) / len(xs) if xs else None
opp = lambda s: s.get('rush_att', 0) + s.get('rec_tgt', 0)
snap = lambda s: s.get('off_snp', 0) / s['tm_off_snp'] if s.get('tm_off_snp') else None
SIG = dict(SIGNALS)
SIG['Touches + targets, last 2'] = lambda p, w: usage(p, w, opp, 2) if pos(p) in FLEX_OK else None
SIG['Snap share, last 2'] = lambda p, w: usage(p, w, snap, 2) if pos(p) in FLEX_OK else None
for name, f in SIG.items():
    wins, diffs = 0, []
    for w in range(3, 15):
        t = next(x for x in M[w] if x['roster_id'] == MY_ROSTER)
        best = None
        for p in candidates(w):
            if pos(p) not in FLEX_OK: continue          # compare like with like: RB/WR/TE only
            mine = [q for q in t['players'] if pos(q) == pos(p)]
            if not mine or f(p, w) is None: continue
            low = min(mine, key=lambda q: (windowed(q, w) or {'mean': 0})['mean'])
            lv = f(low, w)
            if lv is not None and f(p, w) <= lv: continue
            if best is None or f(p, w) > f(best[0], w): best = (p, low)
        if best:
            p, low = best
            d = ros_avg(p, w)[0] - ros_avg(low, w)[0]; diffs.append(d); wins += d > 0
    print(f'{name:28s} RB/WR/TE pickup beat your lowest {wins}/{len(diffs)} weeks, avg margin {st.mean(diffs):+5.1f} pts/game')
