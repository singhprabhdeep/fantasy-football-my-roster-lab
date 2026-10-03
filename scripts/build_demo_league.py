"""Builds RosterLab/DemoLeague.json: a frozen, anonymized snapshot of a real Sleeper league that the
app's demo mode reads instead of the network.

    python3 scripts/build_demo_league.py --league <Sleeper league id> --week 10 --me <roster id>

The snapshot is that league's season as it stood going into `--week` (games before it are final),
plus the previous season for player history. Every manager and team name is replaced and league
ids become demo ids, so nothing identifies the league. NFL players and stats are left as they are.

Sleeper's API has no history for injury news or trending adds, so:
- injuries are rebuilt from the box scores: a player who played in the three weeks before `--week`
  but sat out that week while his team played is marked Out (IR if he missed the next three weeks too);
- the trending list is empty, so the waiver list is the best available players by usage.

The file maps each API path the app requests to that response, so the app's normal code path runs.
"""
import argparse, json, urllib.request
from collections import defaultdict

API = 'https://api.sleeper.app/v1/'
POSITIONS = {'QB', 'RB', 'WR', 'TE', 'K', 'DEF'}
DEMO_USER = 'demo'


def get(path):
    url = path if path.startswith('https://') else API + path
    # api.sleeper.com turns away Python's default user agent.
    with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})) as r:
        return json.load(r)


def team_stats(season, week):
    """api.sleeper.com stats carry each player's team that week (api.sleeper.app's don't)."""
    pos = '&'.join(f'position[]={p}' for p in sorted(POSITIONS))
    return get(f'https://api.sleeper.com/stats/nfl/{season}/{week}?season_type=regular&{pos}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--league', required=True, help='Sleeper league id of the season to snapshot')
    ap.add_argument('--week', type=int, default=13, help='the "current" week in the demo')
    ap.add_argument('--me', type=int, required=True, help='roster id the demo user owns')
    ap.add_argument('--out', default='RosterLab/DemoLeague.json')
    a = ap.parse_args()

    W = a.week
    league = get(f'league/{a.league}')
    season = league['season']
    prev_id = league.get('previous_league_id')
    prev = get(f'league/{prev_id}') if prev_id and prev_id != '0' else None
    ids = {season: f'demo-{season}'}
    if prev: ids[prev['season']] = f'demo-{prev["season"]}'
    players_nfl = get('players/nfl')
    position = {pid: p.get('position') for pid, p in players_nfl.items()}

    out = {}

    def anon_league(lg, previous):
        return {'league_id': ids[lg['season']], 'name': 'Demo League', 'season': lg['season'],
                'status': 'in_season' if lg['season'] == season else 'complete',
                'total_rosters': lg['total_rosters'], 'roster_positions': lg['roster_positions'],
                'scoring_settings': lg['scoring_settings'], 'previous_league_id': previous,
                'settings': {'waiver_budget': (lg.get('settings') or {}).get('waiver_budget', 0)}}

    out['state/nfl'] = {'week': W, 'season': season, 'season_type': 'regular'}
    out[f'league/{ids[season]}'] = anon_league(league, ids.get(prev['season']) if prev else None)
    if prev:
        out[f'league/{ids[prev["season"]]}'] = anon_league(prev, None)

    # Managers: "You" for the demo roster, "Team N" for everyone else.
    rosters = get(f'league/{a.league}/rosters')
    owner = {r['roster_id']: f'demo-user-{r["roster_id"]}' for r in rosters}
    users = [{'user_id': owner[r['roster_id']],
              'display_name': 'You' if r['roster_id'] == a.me else f'Team {r["roster_id"]}',
              'metadata': {'team_name': 'Your Team' if r['roster_id'] == a.me else f'Team {r["roster_id"]}'}}
             for r in rosters]
    out[f'league/{ids[season]}/users'] = users
    out[f'user/{DEMO_USER}'] = {'user_id': owner[a.me], 'display_name': 'You'}

    def slim_matchups(rows):
        return [{'roster_id': m['roster_id'], 'starters': m.get('starters'),
                 'starters_points': m.get('starters_points'), 'players': m.get('players'),
                 'points': m.get('points')} for m in rows]

    # Rosters as they stood for week W (that week's lineups), with FAAB spent through then.
    spent = defaultdict(int)
    for w in range(1, W + 1):
        for t in get(f'league/{a.league}/transactions/{w}'):
            if t['type'] == 'waiver' and t['status'] == 'complete':
                spent[t['roster_ids'][0]] += (t.get('settings') or {}).get('waiver_bid', 0)
    lineups = {m['roster_id']: m for m in get(f'league/{a.league}/matchups/{W}')}
    out[f'league/{ids[season]}/rosters'] = [
        {'roster_id': rid, 'owner_id': owner[rid], 'players': lineups[rid].get('players'),
         'starters': lineups[rid].get('starters'),
         'settings': {'waiver_budget_used': spent[rid], 'waiver_position': None}}
        for rid in sorted(lineups)]

    def keep(stats):
        return {pid: s for pid, s in stats.items() if position.get(pid) in POSITIONS and s.get('gp', 0) > 0}

    used = set()
    for w in range(1, W):
        out[f'league/{ids[season]}/matchups/{w}'] = slim_matchups(get(f'league/{a.league}/matchups/{w}'))
        stats = keep(get(f'stats/nfl/regular/{season}/{w}'))
        out[f'stats/nfl/regular/{season}/{w}'] = stats
        used |= set(stats)
    if prev:
        for w in range(1, 19):
            rows = get(f'league/{prev_id}/matchups/{w}')
            if not rows: continue
            out[f'league/{ids[prev["season"]]}/matchups/{w}'] = slim_matchups(rows)
            stats = keep(get(f'stats/nfl/regular/{prev["season"]}/{w}'))
            out[f'stats/nfl/regular/{prev["season"]}/{w}'] = stats
            used |= set(stats)
    projections = get(f'projections/nfl/regular/{season}/{W}')
    out[f'projections/nfl/regular/{season}/{W}'] = {
        pid: s for pid, s in projections.items() if position.get(pid) in POSITIONS and s.get('gp', 0) > 0}

    # Schedule: games before week W are final, the rest are still to play.
    schedule = get(f'https://api.sleeper.com/schedule/nfl/regular/{season}')
    for g in schedule:
        g['status'] = 'complete' if g['week'] < W else 'pre_game'
    out[f'https://api.sleeper.com/schedule/nfl/regular/{season}'] = [
        {'week': g['week'], 'home': g['home'], 'away': g['away'], 'status': g['status']} for g in schedule]
    out['players/nfl/trending/add?lookback_hours=24&limit=100'] = []

    # Each player's team as of the snapshot, and injuries rebuilt from who sat out.
    team, played, role = {}, defaultdict(set), defaultdict(float)
    for w in range(1, W + 4):
        for r in team_stats(season, w):
            if r.get('team'):
                s = r.get('stats') or {}
                if w < W: team[r['player_id']] = r['team']
                if s.get('gp', 0) > 0: played[r['player_id']].add(w)
                # Only players with a real role get an injury: a starting QB, a kicker, or 4+ touches.
                if W - 3 <= w < W:
                    role[r['player_id']] = max(role[r['player_id']], s.get('pass_att', 0) / 4,
                                               s.get('rush_att', 0) + s.get('rec_tgt', 0),
                                               4 * (s.get('fga', 0) + s.get('xpa', 0)))
    teams_playing = defaultdict(set)
    for g in schedule:
        teams_playing[g['week']] |= {g['home'], g['away']}
    injury = {}
    for pid, weeks in played.items():
        t = team.get(pid)
        if not t or position.get(pid) not in POSITIONS - {'DEF'} or role[pid] < 4: continue
        if weeks & set(range(W - 3, W)) and W not in weeks and t in teams_playing[W]:
            missed_next = all(w not in weeks for w in range(W, W + 4) if t in teams_playing[w])
            injury[pid] = 'IR' if missed_next else 'Out'

    rostered = {p for r in out[f'league/{ids[season]}/rosters'] for p in (r['players'] or [])}
    compact = {}
    for pid in used | rostered | set(out[f'projections/nfl/regular/{season}/{W}']):
        p = players_nfl.get(pid)
        if not p or p.get('position') not in POSITIONS: continue
        status = injury.get(pid)
        compact[pid] = {k: v for k, v in {
            'full_name': p.get('full_name'), 'first_name': p.get('first_name'), 'last_name': p.get('last_name'),
            'position': p.get('position'), 'team': pid if p.get('position') == 'DEF' else team.get(pid),
            'fantasy_positions': p.get('fantasy_positions'), 'number': p.get('number'),
            'injury_status': status, 'injury_notes': 'Missed this week (from box scores)' if status else None,
        }.items() if v is not None}
    out['players-compact-v3'] = compact

    with open(a.out, 'w') as f:
        json.dump(out, f, separators=(',', ':'))
    print(f'wrote {a.out}: {len(out)} responses, {len(compact)} players, {len(injury)} injuries')


if __name__ == '__main__':
    main()
