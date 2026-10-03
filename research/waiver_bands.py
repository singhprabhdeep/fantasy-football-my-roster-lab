import json, statistics as st
rows = json.load(open('waiver_rules_rows.json'))
def band(r):
    if r['pos'] == 'QB':
        return 'Replace' if r['dP'] >= 2 else "Don't replace"
    if r['dT'] is None: return None
    if r['dP'] >= 2 and r['dT'] >= 4: return 'Replace (strong)'
    if r['dP'] >= 2 and r['dT'] >= 2: return 'Replace'
    if r['dP'] >= 2 or r['dT'] >= 2: return 'Watch'
    return "Don't replace"
out = {}
for b in ['Replace (strong)', 'Replace', 'Watch', "Don't replace"]:
    for grp, f in (('RB/WR/TE', lambda r: r['pos'] != 'QB'), ('QB', lambda r: r['pos'] == 'QB')):
        sel = [r for r in rows if f(r) and band(r) == b]
        if len(sel) >= 15:
            print(f'{grp:8s} {b:18s} pickup beat your lowest {sum(r["win"] for r in sel) / len(sel):5.1%}  avg gain {st.mean(r["margin"] for r in sel):+5.1f} pts/wk  n={len(sel)}')
