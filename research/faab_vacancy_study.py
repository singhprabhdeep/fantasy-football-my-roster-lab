"""FAAB paid in a league for backups whose team's lead RB/WR/TE sat out (2022-2025).

For each vacancy game (vacancy_events.json), look for a league claim on the backup in the waiver
run before that game (transactions leg = week) or right after it (leg = week + 1). Budget is $50.

Run from the data folder that fetch_season.py writes (ts_{year}_{week}.json at the top, one
subfolder per season with users.json, rosters.json, players.json, m{week}.json and t{week}.json),
after vacancy_backtest.py has written vacancy_events.json there.
"""
import json, os, statistics as st
from collections import defaultdict

S = '.'
FOLDERS = {int(d): d for d in sorted(os.listdir(S)) if d.isdigit()}   # season folders, e.g. 2022 ... 2025
BUDGET = 50
P = json.load(open(f'{S}/{FOLDERS[max(FOLDERS)]}/players.json'))
events = json.load(open('vacancy_events.json'))

def pct(xs, q):
    xs = sorted(xs)
    if not xs: return float('nan')
    k = (len(xs) - 1) * q
    lo, hi = int(k), min(int(k) + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)

def ts_points(year, pid, weeks):
    out = []
    for w in weeks:
        for r in json.load(open(f'ts_{year}_{w}.json')):
            if r['player_id'] == pid and r['stats'].get('gp', 0) > 0:
                out.append(r['stats'].get('pts_half_ppr', 0))
    return out

claims, all_skill_bids = [], []
availability = defaultdict(int)   # backup already on a league roster going into the vacancy week?
for year, folder in FOLDERS.items():
    users = {u['user_id']: u['display_name'] for u in json.load(open(f'{S}/{folder}/users.json'))}
    owner = {r['roster_id']: users.get(r['owner_id'], str(r['roster_id'])) for r in json.load(open(f'{S}/{folder}/rosters.json'))}
    tx = {w: json.load(open(f'{S}/{folder}/t{w}.json')) for w in range(1, 18)}
    # Running FAAB spent per roster, in transaction order.
    spent, spent_before = defaultdict(int), {}
    for w in range(1, 18):
        for t in sorted(tx[w], key=lambda t: t.get('status_updated') or 0):
            if t['type'] == 'waiver' and t['status'] == 'complete':
                rid = t['roster_ids'][0]
                spent_before[t['transaction_id']] = spent[rid]
                spent[rid] += (t.get('settings') or {}).get('waiver_bid', 0)
                for pid in (t.get('adds') or {}):
                    if P.get(pid, {}).get('position') in ('RB', 'WR', 'TE'):
                        all_skill_bids.append(dict(year=year, week=w, bid=(t.get('settings') or {}).get('waiver_bid', 0)))
    rostered = {w: {p for m in json.load(open(f'{S}/{folder}/m{w}.json')) for p in (m.get('players') or [])} for w in range(1, 18)}
    seen = set()
    for e in events[str(year)]:
        key = (e['backup'], e['week'])
        if key in seen: continue
        seen.add(key)
        already = e['backup'] in rostered[e['week'] - 1]
        availability[already] += 1
        for leg in (e['week'], e['week'] + 1):
            if leg > 17: continue
            wins = [t for t in tx[leg] if t['status'] == 'complete' and e['backup'] in (t.get('adds') or {})]
            if not wins: continue
            t = wins[0]
            losing = [(x.get('settings') or {}).get('waiver_bid', 0) for x in tx[leg]
                      if x['type'] == 'waiver' and x['status'] == 'failed' and e['backup'] in (x.get('adds') or {})]
            bid = (t.get('settings') or {}).get('waiver_bid', 0) if t['type'] == 'waiver' else 0
            rid = t['roster_ids'][0]
            after = ts_points(year, e['backup'], range(leg, 18))
            claims.append(dict(year=year, week=e['week'], leg=leg, pos=e['pos'], name=e['backup_name'].strip(),
                               kind=t['type'], bid=bid, was_rostered=already, losing=sorted(losing, reverse=True), bidders=1 + len(losing),
                               manager=owner.get(rid, '?'),
                               left=BUDGET - spent_before.get(t['transaction_id'], 0) if t['type'] == 'waiver' else None,
                               vacancy_pts=e['pts'], ros_avg=st.mean(after) if after else 0.0, before_avg=e['own_pts']))
            break

vac_games = sum(len(v) for v in events.values())
print(f'vacancy games ({min(FOLDERS)}-{max(FOLDERS)}): {vac_games}; unique backup-weeks: {availability[True] + availability[False]}')
fresh = sum(not c['was_rostered'] for c in claims)
print(f'   backup already on a league roster: {availability[True]}; on waivers: {availability[False]}, of which a league member added {fresh} ({fresh / availability[False]:.0%})')
print(f'   all adds of a backup around his vacancy game (incl. drop-and-re-add): {len(claims)}')
print(f'   via waiver claim {sum(c["kind"] == "waiver" for c in claims)}, via free-agent add ($0) {sum(c["kind"] != "waiver" for c in claims)}')

def describe(label, cs):
    if not cs: print(f'{label}: none'); return
    bids = [c['bid'] for c in cs if c['kind'] == 'waiver']
    contested = [c for c in cs if c['kind'] == 'waiver' and c['losing']]
    gaps = [c['bid'] - c['losing'][0] for c in contested]
    print(f'{label}: n={len(cs)} (waiver {len(bids)})')
    if bids:
        print(f'   winning bid  min ${min(bids)}  25th ${pct(bids, .25):.0f}  median ${pct(bids, .5):.0f}  avg ${st.mean(bids):.1f}'
              f'  75th ${pct(bids, .75):.0f}  90th ${pct(bids, .9):.0f}  max ${max(bids)}  (avg {st.mean(bids) / BUDGET:.0%} of budget)')
        print(f'   contested {len(contested)}/{len(bids)} ({len(contested) / len(bids):.0%}); bidders when contested avg {st.mean(c["bidders"] for c in contested) if contested else 0:.1f}'
              f'; winning margin over 2nd bid: median ${pct(gaps, .5) if gaps else 0:.0f}, avg ${st.mean(gaps) if gaps else 0:.1f}')
    print(f'   production: before {st.mean(c["before_avg"] for c in cs):.1f} pts/g, vacancy game {st.mean(c["vacancy_pts"] for c in cs):.1f}, rest of season {st.mean(c["ros_avg"] for c in cs):.1f}')

describe('ALL positions', claims)
for pos in ('RB', 'WR', 'TE'):
    describe(pos, [c for c in claims if c['pos'] == pos])
describe('Weeks 1-8', [c for c in claims if c['week'] <= 8])
describe('Weeks 9-17', [c for c in claims if c['week'] > 8])
for y in sorted(FOLDERS):
    describe(str(y), [c for c in claims if c['year'] == y])

print('\nBaseline: every RB/WR/TE waiver claim')
for label, cs in (('all', all_skill_bids), ('weeks 1-8', [c for c in all_skill_bids if c['week'] <= 8]),
                  ('weeks 9-17', [c for c in all_skill_bids if c['week'] > 8])):
    b = [c['bid'] for c in cs]
    print(f'   {label:10s} n={len(b)} median ${pct(b, .5):.0f} avg ${st.mean(b):.1f} 75th ${pct(b, .75):.0f} 90th ${pct(b, .9):.0f} max ${max(b)}  $0 share {sum(x == 0 for x in b) / len(b):.0%}')

print('\nWho spends on vacancy backups (waiver claims won)')
by = defaultdict(list)
for c in claims:
    if c['kind'] == 'waiver': by[c['manager']].append(c['bid'])
for m, b in sorted(by.items(), key=lambda kv: -st.mean(kv[1])):
    print(f'   {m:15s} won {len(b):2d}  avg ${st.mean(b):4.1f}  max ${max(b)}')

print('\nBiggest vacancy pickups')
for c in sorted([c for c in claims if c['kind'] == 'waiver'], key=lambda c: -c['bid'])[:12]:
    print(f"   {c['year']} wk{c['week']:>2} {c['pos']} {c['name']:22s} ${c['bid']:>2} by {c['manager']:13s} (left ${c['left']}) losing bids {c['losing']}  ROS {c['ros_avg']:.1f} pts/g")
json.dump(claims, open('faab_claims.json', 'w'), indent=1)
