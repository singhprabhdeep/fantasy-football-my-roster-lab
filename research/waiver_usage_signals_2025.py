src = open(__import__('os').path.join(__import__('os').path.dirname(__file__), 'waiver_backtest_2025.py')).read().split("# ---------- 1. Does")[0]
exec(src)
import statistics as st
def opp_last(pid, w, n=2):
    xs = []
    for x in range(w - 1, 0, -1):
        s = S[x].get(pid)
        if s and s.get('gp', 0) > 0:
            xs.append(s.get('rush_att', 0) + s.get('rec_tgt', 0))
            if len(xs) == n: break
    return sum(xs) / len(xs) if xs else None
def snap_last(pid, w):
    s = S[w - 1].get(pid) or {}
    return s.get('off_snp', 0) / s['tm_off_snp'] if s.get('tm_off_snp') else None
extra = {'Touches+targets, last 2 games': opp_last, 'Snap share last week': snap_last}
for name, f in extra.items():
    corr, before, after = [], [], []
    for w in range(3, 15):
        pool = candidates(w)
        for position in ('RB', 'WR', 'TE'):
            pp = [p for p in pool if pos(p) == position and ros_avg(p, w)[1] >= 2 and f(p, w) is not None]
            if len(pp) < 10: continue
            corr.append(pearson([f(p, w) for p in pp], [ros_avg(p, w)[0] for p in pp]))
            for p in sorted(pp, key=lambda p: f(p, w), reverse=True)[:5]:
                before.append(windowed(p, w)['mean']); after.append(ros_avg(p, w)[0])
    print(f'{name:30s} corr with ROS avg {st.mean(corr):5.2f} | flagged top-5 avg before {st.mean(before):5.1f} -> rest of season {st.mean(after):5.1f}')
# same, RB/WR/TE only, for the app signals for a fair comparison
for name, f in SIGNALS.items():
    corr, before, after = [], [], []
    for w in range(3, 15):
        pool = candidates(w)
        for position in ('RB', 'WR', 'TE'):
            pp = [p for p in pool if pos(p) == position and ros_avg(p, w)[1] >= 2]
            vals = [(p, f(p, w)) for p in pp if f(p, w) is not None and math.isfinite(f(p, w))]
            if len(vals) < 10: continue
            corr.append(pearson([v for _, v in vals], [ros_avg(p, w)[0] for p, _ in vals]))
            for p, _ in sorted(vals, key=lambda x: x[1], reverse=True)[:5]:
                before.append(windowed(p, w)['mean']); after.append(ros_avg(p, w)[0])
    print(f'{name:30s} corr with ROS avg {st.mean(corr):5.2f} | flagged top-5 avg before {st.mean(before):5.1f} -> rest of season {st.mean(after):5.1f}')
