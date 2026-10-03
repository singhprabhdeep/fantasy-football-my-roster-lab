"""Start/sit backtest: projection-led lineups and calibrated confidence, weeks 3-14."""
import itertools, math, json, statistics as st
from collections import defaultdict
exec(open(__import__('os').path.join(__import__('os').path.dirname(__file__), 'backtest_2025.py')).read().split('# ---------- 1.')[0])

PR = {w: json.load(open(f'p{w}.json')) for w in REG_WEEKS}
def proj(pid, w):
    s = PR[w].get(pid)
    if not s or s.get('gp', 1) == 0: return None
    return sum(v * sc.get(k, 0) for k, v in s.items() if isinstance(v, (int, float)))
def phi(x): return 0.5 * (1 + math.erf(x / math.sqrt(2)))

# 1. How far actual scores land from the projection, by position (the noise the confidence models).
miss = defaultdict(list)
for w in EVAL_WEEKS:
    for t in M[w]:
        for p in t['players']:
            pr = proj(p, w)
            if pr and pr > 0 and S[w].get(p, {}).get('gp', 0) > 0:
                miss[pos(p)].append(t['players_points'].get(p, 0) - pr)
sigma = {k: st.pstdev(v) for k, v in miss.items() if len(v) > 30}
print('projection miss SD by position:', {k: round(v, 1) for k, v in sorted(sigma.items())})

def confidence(gap, pa, pb):
    """P(the higher-projected player outscores the other) under independent normal misses."""
    s = math.sqrt(sigma.get(pa, 7) ** 2 + sigma.get(pb, 7) ** 2)
    return phi(abs(gap) / s)

# 2. Calibration: predicted confidence vs how often the call was right (any two same-team,
#    lineup-eligible players with projections).
buckets = defaultdict(lambda: [0, 0, 0.0])
for w in EVAL_WEEKS:
    for t in M[w]:
        pp = t['players_points']
        act = [p for p in t['players'] if proj(p, w) and proj(p, w) > 0]
        for a, b in itertools.combinations(act, 2):
            if not (pos(a) == pos(b) or (pos(a) in FLEX_OK and pos(b) in FLEX_OK)): continue
            ga = proj(a, w) - proj(b, w)
            if ga == 0: continue
            hi, lo = (a, b) if ga > 0 else (b, a)
            c = confidence(ga, pos(a), pos(b))
            key = min(int(c * 20) * 5, 95)          # 50-55, 55-60, ...
            buckets[key][0] += 1; buckets[key][1] += pp.get(hi, 0) > pp.get(lo, 0); buckets[key][2] += c
print('calibration (predicted -> actual):')
for k in sorted(buckets):
    n, hit, csum = buckets[k]
    if n >= 20: print(f'   {k}-{k + 5}%: predicted {csum / n:5.1%}  actual {hit / n:5.1%}  (n={n})')

# 3. Lineups: projection-led vs managers, plus the calls the app would have shown.
def rec_lineup(players, w):
    """Projection first; season avg only breaks ties within half a point."""
    def val(p):
        pr = proj(p, w)
        m = metrics(p, w)
        avg = m['mean'] if m else 0
        return (round((pr or -99) * 2) / 2, avg)
    return best_lineup([p for p in players if proj(p, w) and proj(p, w) > 0], val)
gain, mine, rec_ = [], 0.0, [0, 0]
opp = {}
for w in REG_WEEKS:
    g = defaultdict(list)
    for t in M[w]: g[t['matchup_id']].append(t)
    for v in g.values():
        if len(v) == 2: opp[(w, v[0]['roster_id'])] = v[1]['points']; opp[(w, v[1]['roster_id'])] = v[0]['points']
swap_calls = []   # (confidence, right?) for each "start X over Y" the app would have shown vs the manager's lineup
for w in EVAL_WEEKS:
    for t in M[w]:
        pp = t['players_points']
        lineup = rec_lineup(t['players'], w)
        score = sum(pp.get(p, 0) for p in lineup)
        gain.append(score - t['points'])
        if t['roster_id'] == MY_ROSTER:
            mine += score; rec_[0 if score > opp[(w, MY_ROSTER)] else 1] += 1
        actual = [p for p in t['starters'] if p != '0']
        ins = [p for p in lineup if p not in actual]
        outs = [p for p in actual if p not in lineup]
        for i in ins:
            cands = [o for o in outs if pos(o) == pos(i) or (pos(o) in FLEX_OK and pos(i) in FLEX_OK)]
            if not cands: continue
            o = min(cands, key=lambda o: proj(o, w) or -99)
            if proj(o, w) is None: continue
            c = confidence(proj(i, w) - proj(o, w), pos(i), pos(o))
            swap_calls.append((c, pp.get(i, 0) > pp.get(o, 0), pp.get(i, 0) - pp.get(o, 0)))
print(f'projection-led lineups vs managers: {st.mean(gain):+.2f} pts/week | Me {mine:.1f} ({rec_[0]}-{rec_[1]})')
for lo, hi, label in [(0.5, 0.6, 'Toss-up'), (0.6, 0.7, 'Lean'), (0.7, 1.01, 'Strong')]:
    sel = [x for x in swap_calls if lo <= x[0] < hi]
    if sel:
        print(f'   {label:8s} swaps vs manager ({lo:.0%}-{min(hi, 1):.0%}): right {sum(x[1] for x in sel) / len(sel):5.1%}, '
              f'avg gain {st.mean(x[2] for x in sel):+5.1f} pts  (n={len(sel)})')
json.dump(dict(sigma=sigma), open('startsit_sigma.json', 'w'))
