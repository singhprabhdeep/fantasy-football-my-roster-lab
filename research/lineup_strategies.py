import json
exec(open(__import__('os').path.join(__import__('os').path.dirname(__file__), 'backtest_2025.py')).read().split('# ---------- 1.')[0])
PR = {w: json.load(open(f'p{w}.json')) for w in REG_WEEKS}
def proj(pid, w):
    s = PR[w].get(pid) or {}
    return sum(v * sc.get(k, 0) for k, v in s.items() if isinstance(v, (int, float)))
def lastn(pid, w, n=3):
    h = history(pid, w)
    if not h: return neutral(pos(pid), w)
    x = [p for p, _ in h][-n:]; return sum(x) / len(x)
opp = {}
for w in REG_WEEKS:
    g = defaultdict(list)
    for t in M[w]: g[t['matchup_id']].append(t)
    for v in g.values():
        if len(v) == 2: opp[(w, v[0]['roster_id'])] = v[1]['points']; opp[(w, v[1]['roster_id'])] = v[0]['points']
strategies = {
    'Season avg': lambda p, w: score(p, w, 'mean'),
    'Risk-adj avg': lambda p, w: score(p, w, 'ram'),
    'Last 3 games avg': lambda p, w: lastn(p, w, 3),
    'Sleeper projection': lambda p, w: proj(p, w),
    'Perfect hindsight': None,
}
for name, f in strategies.items():
    tot = 0; rec = [0, 0]; gain = []
    for w in EVAL_WEEKS:
        for t in M[w]:
            pp = t['players_points']; active = [p for p in t['players'] if S[w].get(p, {}).get('gp', 0) > 0]
            val = (lambda p: pp.get(p, 0)) if f is None else (lambda p: f(p, w))
            s = sum(pp.get(p, 0) for p in best_lineup(active, val))
            gain.append(s - t['points'])
            if t['roster_id'] == MY_ROSTER: tot += s; rec[0 if s > opp[(w, MY_ROSTER)] else 1] += 1
    print(f'{name:22s} Me {tot:7.1f} record {rec[0]}-{rec[1]} | vs managers {st.mean(gain):+5.2f} pts/week')
