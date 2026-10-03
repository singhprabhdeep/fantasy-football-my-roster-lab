src = open(__import__('os').path.join(__import__('os').path.dirname(__file__), 'waiver_backtest_2025.py')).read().split("# ---------- 1. Does")[0]
exec(src)
import statistics as st
for name, f in SIGNALS.items():
    before, after = [], []
    for w in range(3, 15):
        pool = candidates(w)
        for position in ('RB', 'WR', 'TE', 'QB'):
            pp = [p for p in pool if pos(p) == position and ros_avg(p, w)[1] >= 2]
            top = sorted(pp, key=lambda p: (f(p, w) if f(p, w) is not None else -1e9), reverse=True)[:5]
            for p in top:
                before.append(windowed(p, w)['mean']); after.append(ros_avg(p, w)[0])
    print(f'{name:28s} flagged top-5: avg before pickup {st.mean(before):5.1f} -> rest of season {st.mean(after):5.1f}')
b, a = [], []
for w in range(3, 15):
    for t in json.load(open(f't{w}.json')):
        if t['status'] == 'complete' and t.get('adds'):
            for pid in t['adds']:
                if pos(pid) in {'QB', 'RB', 'WR', 'TE'} and ros_avg(pid, w)[1] >= 2:
                    m = windowed(pid, w)
                    if m: b.append(m['mean']); a.append(ros_avg(pid, w)[0])
print(f'{"League managers adds":28s} avg before pickup {st.mean(b):5.1f} -> rest of season {st.mean(a):5.1f}  (n={len(b)})')
