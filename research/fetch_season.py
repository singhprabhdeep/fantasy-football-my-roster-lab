"""Downloads a Sleeper league's seasons for the backtests in this folder.

    python3 research/fetch_season.py --league <league id> --seasons 4 --out data

Writes, for the league and each previous season it links to (up to --seasons):
    data/<season>/league.json, users.json, rosters.json, players.json, schedule.json
    data/<season>/m{week}.json (matchups), s{week}.json (stats), p{week}.json (projections),
                  t{week}.json (transactions)
    data/ts_<season>_<week>.json  (RB/WR/TE stats with each player's team, for vacancy_backtest.py)

Then run a backtest from a season's folder, e.g.:
    cd data/2025 && MY_ROSTER=5 python3 ../../research/backtest_2025.py
    cd data && python3 ../research/vacancy_backtest.py && python3 ../research/faab_vacancy_study.py

Uses only Sleeper's public, read-only API. Weeks 1-18 of the regular season.
"""
import argparse, json, os, urllib.request

API = 'https://api.sleeper.app/v1/'


def get(path):
    url = path if path.startswith('https://') else API + path
    # api.sleeper.com turns away Python's default user agent.
    with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})) as r:
        return json.load(r)


def save(obj, *parts):
    path = os.path.join(*parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        json.dump(obj, f)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--league', required=True, help='Sleeper league id (the newest season to fetch)')
    ap.add_argument('--seasons', type=int, default=4, help='how many seasons to follow back')
    ap.add_argument('--out', default='data')
    a = ap.parse_args()

    players = get('players/nfl')
    league_id = a.league
    for _ in range(a.seasons):
        if not league_id or league_id == '0':
            break
        league = get(f'league/{league_id}')
        season = league['season']
        folder = os.path.join(a.out, season)
        print(f'{season}: {league["name"]}')
        save(league, folder, 'league.json')
        save(get(f'league/{league_id}/users'), folder, 'users.json')
        save(get(f'league/{league_id}/rosters'), folder, 'rosters.json')
        save(players, folder, 'players.json')
        save(get(f'https://api.sleeper.com/schedule/nfl/regular/{season}'), folder, 'schedule.json')
        pos = '&'.join(f'position[]={p}' for p in ('RB', 'WR', 'TE'))
        for w in range(1, 19):
            save(get(f'league/{league_id}/matchups/{w}'), folder, f'm{w}.json')
            save(get(f'league/{league_id}/transactions/{w}'), folder, f't{w}.json')
            save(get(f'stats/nfl/regular/{season}/{w}'), folder, f's{w}.json')
            save(get(f'projections/nfl/regular/{season}/{w}'), folder, f'p{w}.json')
            save(get(f'https://api.sleeper.com/stats/nfl/{season}/{w}?season_type=regular&{pos}'),
                 a.out, f'ts_{season}_{w}.json')
        league_id = league.get('previous_league_id')


if __name__ == '__main__':
    main()
