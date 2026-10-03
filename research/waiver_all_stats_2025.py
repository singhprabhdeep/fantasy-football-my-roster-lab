src = open(__import__('os').path.join(__import__('os').path.dirname(__file__), 'waiver_backtest_2025.py')).read().split("# ---------- 1. Does")[0]
exec(src)
import statistics as st

def full(pid, w, last=None):
    """App-style metrics plus SD/CV/DD over the last `last` games before week w."""
    h = history(pid, w)
    if last: h = h[-last:]
    if not h: return None
    x = [p for p, _ in h]; n = len(x); mean = sum(x) / n
    sd = st.stdev(x) if n >= 2 else None
    gaps = [p - b for p, b in h if b is not None]
    dd = math.sqrt(sum(min(0, g) ** 2 for g in gaps) / len(gaps)) if gaps else None
    ex = sum(gaps) / len(gaps) if gaps else None
    return dict(mean=mean, sd=sd, cv=(sd / mean if sd is not None and mean >= 2 else None), dd=dd,
                sortino=(ex / dd) if dd else None, ram=mean - (dd or 0))

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
    'Avg': lambda p, w: (full(p, w) or {}).get('mean'),
    'Risk-adj avg': lambda p, w: (full(p, w) or {}).get('ram'),
    'Avg, last 3 games': lambda p, w: (full(p, w, 3) or {}).get('mean'),
    'Sortino ratio': lambda p, w: (full(p, w) or {}).get('sortino'),
    'SD': lambda p, w: (full(p, w) or {}).get('sd'),
    'CV': lambda p, w: (full(p, w) or {}).get('cv'),
    'Downside dev': lambda p, w: (full(p, w) or {}).get('dd'),
    'Touches + targets, last 2 games': lambda p, w: usage(p, w, opp, 2),
    'Touches + targets, last 3 games': lambda p, w: usage(p, w, opp, 3),
    'Touches + targets, season': lambda p, w: usage(p, w, opp),
    'Targets only, last 2 games': lambda p, w: usage(p, w, lambda s: s.get('rec_tgt', 0), 2),
    'Carries only, last 2 games': lambda p, w: usage(p, w, lambda s: s.get('rush_att', 0), 2),
    'Red-zone targets, season': lambda p, w: usage(p, w, lambda s: s.get('rec_rz_tgt', 0)),
    'Air yards, last 2 games': lambda p, w: usage(p, w, lambda s: s.get('rec_air_yd', 0), 2),
    'Snap share last week': lambda p, w: usage(p, w, snap, 1),
    'Snap share, last 3 games': lambda p, w: usage(p, w, snap, 3),
    'Snap share, season': lambda p, w: usage(p, w, snap),
}
rows = []
for name, f in STATS.items():
    corr = defaultdict(list); allc = []
    for w in range(3, 15):
        pool = candidates(w)
        for position in ('RB', 'WR', 'TE'):
            vals = [(p, f(p, w)) for p in pool if pos(p) == position and ros_avg(p, w)[1] >= 2]
            vals = [(p, v) for p, v in vals if v is not None and math.isfinite(v)]
            if len(vals) < 10: continue
            c = pearson([v for _, v in vals], [ros_avg(p, w)[0] for p, _ in vals])
            if math.isfinite(c): corr[position].append(c); allc.append(c)
    rows.append((name, st.mean(allc), {k: st.mean(v) for k, v in corr.items()}))
rows.sort(key=lambda r: -abs(r[1]))
for name, c, byp in rows:
    print(f'{name:34s} {c:+.2f}   RB {byp.get("RB", float("nan")):+.2f}  WR {byp.get("WR", float("nan")):+.2f}  TE {byp.get("TE", float("nan")):+.2f}')
