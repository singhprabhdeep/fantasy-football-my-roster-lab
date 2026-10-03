"""Would the Waivers tab's stats have found useful 2025 pickups, and would they have changed my season?

Before each week w (3-14) the waiver pool is every player not on a league roster at the end of week w-1.
Stats use only games before week w. Rest-of-season (ROS) = weeks w..14.
"""
import json, math, statistics as st
from collections import defaultdict

exec(open(__import__('os').path.join(__import__('os').path.dirname(__file__), 'backtest_2025.py')).read().split('# ---------- 1.')[0])   # shared loaders and metric helpers

MIN_GAMES = 2
ROS_END = 14

def rostered(week):
    return {p for t in M[week] for p in t['players']}

def played(pid, w):
    s = S[w].get(pid)
    return bool(s and s.get('gp', 0) > 0)

def week_pts(pid, w):
    s = S[w].get(pid)
    return pts(s) if s and s.get('gp', 0) > 0 else 0.0

def ros_avg(pid, w):
    """Average points per game played from week w through 14."""
    xs = [week_pts(pid, x) for x in range(w, ROS_END + 1) if played(pid, x)]
    return (sum(xs) / len(xs), len(xs)) if xs else (0.0, 0)

def ros_total(pid, w):
    return sum(week_pts(pid, x) for x in range(w, ROS_END + 1))

def windowed(pid, before, last=None):
    """App metrics over the player's last `last` games (None = whole season so far)."""
    h = history(pid, before)
    if last: h = h[-last:]
    if not h: return None
    x = [p for p, _ in h]; n = len(x); mean = sum(x) / n
    gaps = [p - b for p, b in h if b is not None]
    dd = math.sqrt(sum(min(0, g) ** 2 for g in gaps) / len(gaps)) if gaps else None
    ex = sum(gaps) / len(gaps) if gaps else None
    sortino = (ex / dd) if dd else (math.inf if gaps else None)
    return dict(n=n, mean=mean, ram=mean - (dd or 0), sortino=sortino)

SIGNALS = {
    'Sortino ratio (app default)': lambda p, w: (windowed(p, w) or {}).get('sortino'),
    'Avg': lambda p, w: (windowed(p, w) or {}).get('mean'),
    'Risk-adj avg': lambda p, w: (windowed(p, w) or {}).get('ram'),
    'Avg, last 3 games': lambda p, w: (windowed(p, w, 3) or {}).get('mean'),
}

def candidates(w):
    """Available players with enough history to have stats."""
    pool = []
    taken = rostered(w - 1)
    for pid in S[w - 1]:
        if pid in taken or not pos(pid) or pos(pid) not in {'QB', 'RB', 'WR', 'TE', 'K', 'DEF'}:
            continue
        m = windowed(pid, w)
        # Must have played last week: a player sitting out injured wouldn't be picked up.
        if m and m['n'] >= MIN_GAMES and played(pid, w - 1):
            pool.append(pid)
    return pool

# ---------- 1. Does each signal find the available players who go on to produce? ----------
print('=== Signal quality over the waiver pool (weeks 3-14) ===')
quality = defaultdict(lambda: dict(corr=[], hit=[], top_ros=[]))
best_ros = []
for w in range(3, 15):
    pool = candidates(w)
    ros = {p: ros_avg(p, w)[0] for p in pool}
    for position in ('QB', 'RB', 'WR', 'TE'):
        pp = [p for p in pool if pos(p) == position and ros_avg(p, w)[1] >= 2]
        if len(pp) < 10: continue
        actual_top = set(sorted(pp, key=lambda p: ros[p], reverse=True)[:5])
        for name, f in SIGNALS.items():
            vals = [(p, f(p, w)) for p in pp]
            vals = [(p, v if v is not None else -math.inf) for p, v in vals]
            finite = [(p, v) for p, v in vals if math.isfinite(v)]
            if len(finite) > 5:
                quality[name]['corr'].append(pearson([v for _, v in finite], [ros[p] for p, _ in finite]))
            picked = [p for p, _ in sorted(vals, key=lambda x: x[1], reverse=True)[:5]]
            quality[name]['hit'].append(len(actual_top & set(picked)) / 5)
            quality[name]['top_ros'].append(st.mean(ros[p] for p in picked))
        best_ros.append(st.mean(ros[p] for p in actual_top))
for name, q in quality.items():
    print(f'{name:28s} corr with ROS avg {st.mean(q["corr"]):5.2f} | top-5 flagged that were a real top-5 ROS {st.mean(q["hit"]):5.1%}'
          f' | flagged top-5 ROS avg {st.mean(q["top_ros"]):5.1f}')
print(f'{"(hindsight best 5)":28s} ROS avg {st.mean(best_ros):5.1f}')

# League's actual pickups, for comparison
adds = []
for w in range(3, 15):
    for t in json.load(open(f't{w}.json')):
        if t['status'] == 'complete' and t.get('adds'):
            for pid in t['adds']:
                if pos(pid) in {'QB', 'RB', 'WR', 'TE'}:
                    a, n = ros_avg(pid, w)
                    if n >= 2: adds.append(a)
print(f'League managers\' actual RB/WR/TE/QB adds: ROS avg {st.mean(adds):5.1f} (n={len(adds)})')

# ---------- 2. Replay my season with one waiver move per week ----------
opp = {}
for w in REG_WEEKS:
    g = defaultdict(list)
    for t in M[w]: g[t['matchup_id']].append(t)
    for v in g.values():
        if len(v) == 2:
            opp[(w, v[0]['roster_id'])] = v[1]['points']; opp[(w, v[1]['roster_id'])] = v[0]['points']

def slot_ok(slot, p):
    return pos(p) == slot or (slot == 'FLEX' and pos(p) in FLEX_OK)

def simulate(signal, conservative):
    """Each week, add the available player whose signal most beats the weakest starter he could
    replace (same position, or FLEX for RB/WR/TE), if any does. Drop the lowest-avg bench player
    at his position (or any RB/WR/TE bench player for a flex add). Lineups: my actual starters,
    with pickups swapped in when the signal says they're better."""
    added, dropped = [], set()
    log, total, rec = [], 0.0, [0, 0]
    def val(q, w):
        v = signal(q, w)
        return v if v is not None else -math.inf
    def build_lineup(t, w, roster):
        lineup = [q if q != '0' and q not in dropped else None for q in t['starters']]
        bench = [q for q in roster if q not in lineup and played(q, w)]
        for i, q in enumerate(lineup):                   # fill holes left by dropped starters
            if q is None:
                opts = [b for b in bench if slot_ok(SLOTS[i], b)]
                if opts:
                    pick = max(opts, key=lambda b: val(b, w)); lineup[i] = pick; bench.remove(pick)
        for p in [a for a in added if a in bench]:       # start pickups the signal likes more
            opts = [i for i, q in enumerate(lineup) if q is not None and slot_ok(SLOTS[i], p) and q not in added]
            if opts:
                i = min(opts, key=lambda i: val(lineup[i], w))
                if val(p, w) > val(lineup[i], w):
                    bench.append(lineup[i]); lineup[i] = p; bench.remove(p)
        return lineup
    for w in range(3, 15):
        t = next(x for x in M[w] if x['roster_id'] == MY_ROSTER)
        roster = [p for p in t['players'] if p not in dropped] + [p for p in added if p not in t['players']]
        # --- waiver move before week w ---
        lineup = build_lineup(t, w, roster)
        taken = rostered(w - 1) | (rostered(w) if conservative else set())
        best, best_gain = None, 0.0
        for p in candidates(w):
            if p in taken or p in added: continue
            slots = [i for i, q in enumerate(lineup) if q is not None and slot_ok(SLOTS[i], p)]
            if not slots: continue
            weakest = min((lineup[i] for i in slots), key=lambda q: val(q, w))
            gain = val(p, w) - val(weakest, w)
            if math.isinf(gain) or gain <= best_gain: continue
            bench = [q for q in roster if q not in lineup]
            same = [q for q in bench if pos(q) == pos(p)] or \
                   ([q for q in bench if pos(q) in FLEX_OK] if pos(p) in FLEX_OK else [])
            if not same: continue
            drop = min(same, key=lambda q: (windowed(q, w) or {'mean': 0})['mean'])
            # Never cut someone the stats rate as better than the pickup (e.g. a star on bye).
            if (windowed(drop, w) or {'mean': 0})['mean'] >= windowed(p, w)['mean'] or val(drop, w) >= val(p, w):
                continue
            best, best_gain = (p, drop), gain
        if best:
            p, drop = best
            added.append(p); dropped.add(drop)
            roster = [q for q in roster if q != drop] + [p]
            log.append((w, p, drop))
        lineup = build_lineup(t, w, roster)
        score = sum(week_pts(q, w) if q in added else t['players_points'].get(q, 0) for q in lineup if q)
        total += score; rec[0 if score > opp[(w, MY_ROSTER)] else 1] += 1
    return total, rec, log

actual_total = sum(next(x for x in M[w] if x['roster_id'] == MY_ROSTER)['points'] for w in range(3, 15))
actual_rec = [sum(next(x for x in M[w] if x['roster_id'] == MY_ROSTER)['points'] > opp[(w, MY_ROSTER)] for w in range(3, 15))]
print(f'\n=== My weeks 3-14: actual {actual_total:.1f} pts, {actual_rec[0]}-{12 - actual_rec[0]} ===')
results = {}
for conservative in (False, True):
    label = 'still free after waivers (no competition needed)' if conservative else 'available before waivers (assumes you win the claim)'
    print(f'-- pool: {label}')
    for name, f in SIGNALS.items():
        total, rec, log = simulate(f, conservative)
        results[(name, conservative)] = (total, rec, log)
        print(f'   {name:28s} {total:7.1f} pts ({total - actual_total:+6.1f})  record {rec[0]}-{rec[1]}  moves {len(log)}')
        for w, p, d in log:
            print(f'        wk{w:>2} add {P[p].get("full_name") or p:22s} ({pos(p)}, ROS avg {ros_avg(p, w)[0]:4.1f})'
                  f'  drop {P[d].get("full_name") or d:20s} (ROS avg {ros_avg(d, w)[0]:4.1f})')

json.dump({f'{k[0]}|{k[1]}': [v[0], v[1], [(w, p, d) for w, p, d in v[2]]] for k, v in results.items()},
          open('waiver_results.json', 'w'), indent=1)

print('\n=== Each week: the app\'s top-flagged pickup vs your lowest player at his position (rest of season) ===')
for name, f in SIGNALS.items():
    wins, diffs = 0, []
    for w in range(3, 15):
        t = next(x for x in M[w] if x['roster_id'] == MY_ROSTER)
        roster = t['players']; best = None
        for p in candidates(w):
            mine = [q for q in roster if pos(q) == pos(p)]
            if not mine or f(p, w) is None: continue
            low = min(mine, key=lambda q: (windowed(q, w) or {'mean': 0})['mean'])
            lv = f(low, w)
            if lv is not None and f(p, w) <= lv: continue
            if best is None or f(p, w) > f(best[0], w): best = (p, low)
        if best:
            p, low = best
            d = ros_avg(p, w)[0] - ros_avg(low, w)[0]; diffs.append(d); wins += d > 0
    print(f'{name:28s} pickup out-scored your lowest the rest of the way in {wins}/{len(diffs)} weeks, avg margin {st.mean(diffs):+5.1f} pts/game')
