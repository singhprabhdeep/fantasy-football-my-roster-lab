"""Expected FPTS for defenses = own + beta * (opponent allowed - league avg), with early-season
shrinkage toward the league average (m pseudo-games). Pickup vs my defense, weeks 3-14."""
import itertools, statistics as st
exec(open(__import__('os').path.join(__import__('os').path.dirname(__file__), 'def_matchup_rules_backtest.py')).read().split('rows = []')[0])
def league_avg(w):
    xs = [def_fpts(t, x) for x in range(1, w) for t in opp[x] if def_fpts(t, x) is not None]
    return sum(xs) / len(xs)
LA = {w: league_avg(w) for w in range(3, 15)}
def own_list(t, w, last):
    xs = [def_fpts(t, x) for x in range(1, w) if def_fpts(t, x) is not None]
    return xs[-last:] if last else xs
def opp_list(t, w, last):
    o = opp[w].get(t)
    xs = []
    for x in range(1, w):
        d = opp[x].get(o) if o else None
        if d is not None and def_fpts(d, x) is not None: xs.append(def_fpts(d, x))
    return xs[-last:] if last else xs
def shrink(xs, L, m):
    return (sum(xs) + m * L) / (len(xs) + m) if xs or m else None
pairs = []
for w in range(3, 15):
    pool = [p for p in candidates(w) if pos(p) == 'DEF']
    for t in M[w - 1]:
        mine = [q for q in t['players'] if pos(q) == 'DEF' and windowed(q, w, 2)]
        if not mine: continue
        low = min(mine, key=lambda q: windowed(q, w, 2)['mean'])
        if not played(low, w) or opp[w].get(low) is None: continue
        for p in pool:
            if played(p, w) and opp[w].get(p):
                pairs.append((w, p, low, week_pts(p, w) > week_pts(low, w)))
def evaluate(beta, m, last):
    rows = []
    for w, p, low, win in pairs:
        L = LA[w]
        def exp(t):
            a, b = own_list(t, w, last), opp_list(t, w, last)
            if not a or not b: return None
            return shrink(a, L, m) + beta * (shrink(b, L, m) - L)
        ea, eb = exp(p), exp(low)
        if ea is not None and eb is not None: rows.append((ea - eb, win))
    return rows
def bands(rows, T):
    up = [r for r in rows if r[0] >= T]; mid = [r for r in rows if -T < r[0] < T]; dn = [r for r in rows if r[0] <= -T]
    pct = lambda s: sum(r[1] for r in s) / len(s) if s else float('nan')
    return pct(up), len(up), pct(mid), pct(dn)
import sys
for last in (None, 2):
    for beta in (0.5, 0.67, 1.0, 1.5):
        for m in (0, 2, 4):
            rows = evaluate(beta, m, last)
            out = ' | '.join(f'T{T}: R {bands(rows, T)[0]:.0%} (n={bands(rows, T)[1]}) W {bands(rows, T)[2]:.0%} D {bands(rows, T)[3]:.0%}' for T in (2, 3, 4, 5))
            print(f'window={"season" if last is None else "last2"} beta={beta} m={m}: {out}')
