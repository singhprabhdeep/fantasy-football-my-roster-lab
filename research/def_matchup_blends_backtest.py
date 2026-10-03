exec(open(__import__('os').path.join(__import__('os').path.dirname(__file__), 'def_matchup_rules_backtest.py')).read().split('rows = []')[0])
def own(team, w, last=None):
    xs = [def_fpts(team, x) for x in range(1, w) if def_fpts(team, x) is not None]
    if last: xs = xs[-last:]
    return sum(xs) / len(xs) if xs else None
feats = defaultdict(list)
for w in range(3, 15):
    pool = [p for p in candidates(w) if pos(p) == 'DEF']
    for t in M[w - 1]:
        mine = [q for q in t['players'] if pos(q) == 'DEF' and windowed(q, w, 2)]
        if not mine: continue
        low = min(mine, key=lambda q: windowed(q, w, 2)['mean'])
        if not played(low, w) or opp[w].get(low) is None: continue
        for p in pool:
            if not played(p, w) or opp[w].get(p) is None: continue
            win = week_pts(p, w) > week_pts(low, w)
            for name, fn in {
                'matchup, last 2': lambda t: matchup_fpts(t, w, 2),
                'matchup, season': lambda t: matchup_fpts(t, w, 99),
                'own avg, season': lambda t: own(t, w),
                'own + matchup (season, 50/50)': lambda t: (own(t, w) + matchup_fpts(t, w, 99)) / 2 if own(t, w) is not None and matchup_fpts(t, w, 99) is not None else None,
                'own + matchup (last 2, 50/50)': lambda t: (own(t, w, 2) + matchup_fpts(t, w, 2)) / 2 if own(t, w, 2) is not None and matchup_fpts(t, w, 2) is not None else None,
            }.items():
                a, b = fn(p), fn(low)
                if a is not None and b is not None: feats[name].append((a - b, win))
for name, rows in feats.items():
    out = []
    for x in (1, 2, 3):
        up = [r for r in rows if r[0] >= x]; mid = [r for r in rows if -x < r[0] < x]; dn = [r for r in rows if r[0] <= -x]
        f = lambda s: f'{sum(r[1] for r in s) / len(s):4.0%}' if s else '-'
        out.append(f'±{x}: R {f(up)} W {f(mid)} D {f(dn)}')
    print(f'{name:32s} ' + ' | '.join(out))
