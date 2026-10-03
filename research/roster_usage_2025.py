"""Do usage stats predict next week for players on league rosters (what My Roster shows)?"""
src = open(__import__('os').path.join(__import__('os').path.dirname(__file__), 'waiver_backtest_2025.py')).read().split("# ---------- 1. Does")[0]
exec(src)
import statistics as st

def full(pid, w, last=None):
    h = history(pid, w)
    if last: h = h[-last:]
    if not h: return None
    x = [p for p, _ in h]; mean = sum(x) / len(x)
    gaps = [p - b for p, b in h if b is not None]
    dd = math.sqrt(sum(min(0, g) ** 2 for g in gaps) / len(gaps)) if gaps else 0
    return dict(mean=mean, ram=mean - dd, n=len(x))

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

STATS = {
    'Avg': lambda p, w: full(p, w)['mean'],
    'Risk-adj avg': lambda p, w: full(p, w)['ram'],
    'Avg, last 3 games': lambda p, w: full(p, w, 3)['mean'],
    'Touches + targets, last 2': lambda p, w: usage(p, w, opp, 2),
    'Touches + targets, last 3': lambda p, w: usage(p, w, opp, 3),
    'Touches + targets, season': lambda p, w: usage(p, w, opp),
    'Snap share, last week': lambda p, w: usage(p, w, snap, 1),
    'Snap share, last 3': lambda p, w: usage(p, w, snap, 3),
    'Snap share, season': lambda p, w: usage(p, w, snap),
}

def player_weeks(started_only):
    out = []
    for w in range(3, 15):
        for t in M[w]:
            ids = [p for p in t['starters'] if p != '0'] if started_only else t['players']
            for pid in ids:
                if pos(pid) not in {'QB', 'RB', 'WR', 'TE'} or not played(pid, w): continue
                m = full(pid, w)
                if not m or m['n'] < 2: continue
                out.append((pid, w, week_pts(pid, w)))
    return out

def ols_r(xs_list, y):
    """Multiple correlation R of y on the given predictors (least squares, with intercept)."""
    import itertools
    n = len(y); k = len(xs_list)
    X = [[1.0] + [xs[i] for xs in xs_list] for i in range(n)]
    # normal equations
    A = [[sum(X[r][i] * X[r][j] for r in range(n)) for j in range(k + 1)] for i in range(k + 1)]
    b = [sum(X[r][i] * y[r] for r in range(n)) for i in range(k + 1)]
    for i in range(k + 1):                     # Gauss-Jordan
        piv = A[i][i]
        for j in range(i, k + 1): A[i][j] /= piv
        b[i] /= piv
        for r in range(k + 1):
            if r != i:
                f = A[r][i]
                for j in range(i, k + 1): A[r][j] -= f * A[i][j]
                b[r] -= f * b[i]
    pred = [sum(b[j] * X[r][j] for j in range(k + 1)) for r in range(n)]
    return pearson(pred, y)

for label, started in (('Started players', True), ('Everyone on a league roster', False)):
    rows = player_weeks(started)
    print(f'\n=== {label}: correlation with next week\'s points (weeks 3-14) ===')
    for position_set, tag in ((('RB', 'WR', 'TE'), 'RB/WR/TE'), (('QB',), 'QB')):
        sub = [r for r in rows if pos(r[0]) in position_set]
        print(f'-- {tag} (n={len(sub)})')
        for name, f in STATS.items():
            if tag == 'QB' and name.startswith('Touches'): continue
            vals = [(f(p, w), y) for p, w, y in sub]
            vals = [(x, y) for x, y in vals if x is not None]
            print(f'   {name:28s} {pearson([x for x, _ in vals], [y for _, y in vals]):+.2f}  (n={len(vals)})')
        if tag == 'RB/WR/TE':
            trip = [(STATS['Avg'](p, w), STATS['Touches + targets, last 3'](p, w), STATS['Snap share, last 3'](p, w), y) for p, w, y in sub]
            trip = [t for t in trip if None not in t]
            y = [t[3] for t in trip]
            print(f'   Avg alone                    R {ols_r([[t[0] for t in trip]], y):.3f}')
            print(f'   Avg + touches/targets        R {ols_r([[t[0] for t in trip], [t[1] for t in trip]], y):.3f}')
            print(f'   Avg + touches + snap share   R {ols_r([[t[0] for t in trip], [t[1] for t in trip], [t[2] for t in trip]], y):.3f}')

# Start/sit replay across the league: pick lineups by each stat from active players.
print('\n=== Lineups set by each stat vs managers (all teams, weeks 3-14) ===')
opp_pts = {}
for w in REG_WEEKS:
    g = defaultdict(list)
    for t in M[w]: g[t['matchup_id']].append(t)
    for v in g.values():
        if len(v) == 2:
            opp_pts[(w, v[0]['roster_id'])] = v[1]['points']; opp_pts[(w, v[1]['roster_id'])] = v[0]['points']
def pick_value(name):
    f = STATS[name]
    def val(p, w):
        if pos(p) in ('K', 'DEF') or name.startswith('Avg') or name.startswith('Risk'):
            m = full(p, w)
            return (m['mean'] if m else neutral(pos(p), w)) if not name.startswith('Risk') else (m['ram'] if m else neutral(pos(p), w))
        v = f(p, w) if full(p, w) else None
        if v is None:   # QBs have no touches: fall back to avg
            m = full(p, w); return m['mean'] if m else neutral(pos(p), w)
        return v
    return val
for name in ('Avg', 'Risk-adj avg', 'Touches + targets, last 3', 'Snap share, last 3'):
    val = pick_value(name); gain = []; mine = 0.0; rec = [0, 0]
    for w in range(3, 15):
        for t in M[w]:
            pp = t['players_points']
            active = [p for p in t['players'] if played(p, w)]
            score = sum(pp.get(p, 0) for p in best_lineup(active, lambda p: val(p, w)))
            gain.append(score - t['points'])
            if t['roster_id'] == MY_ROSTER:
                mine += score; rec[0 if score > opp_pts[(w, MY_ROSTER)] else 1] += 1
    print(f'{name:28s} vs managers {st.mean(gain):+5.2f} pts/week | Me {mine:7.1f} ({rec[0]}-{rec[1]})')
