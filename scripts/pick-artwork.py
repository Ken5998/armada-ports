#!/usr/bin/env python3
"""Fills each port's "art" in ports.json with SteamGridDB images (a maintainer's tool, not run on
the handheld). It picks the best-rated static, safe image of each kind for the port's SteamGridDB
game id ("sgdb") and stores the CDN links, which the app downloads without an API key.

    python3 scripts/pick-artwork.py            # ports without art
    python3 scripts/pick-artwork.py --all      # every port again
    python3 scripts/pick-artwork.py pinyon-shift --skip grid=1   # take the second-best grid

Replace any link by hand to use another image: the app only needs a png/jpg URL.
"""
import argparse
import json
import os
import sys
import urllib.request

SEARCH = 'https://www.steamgriddb.com/api/public/search/assets'
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
KINDS = {
    # kind in ports.json: (SteamGridDB asset type, accepted sizes or None for any)
    'grid': ('grid', {(600, 900), (660, 930), (342, 482)}),
    'wide': ('grid', {(920, 430), (460, 215)}),
    'hero': ('hero', None),
    'logo': ('logo', None),
}


def assets(game_id, asset_type):
    out, page = [], 0
    while page < 4:
        body = json.dumps({'asset_type': asset_type, 'game_id': [game_id], 'order': 'score_desc',
                           'page': page}).encode()
        req = urllib.request.Request(SEARCH, data=body, headers={'Content-Type': 'application/json',
                                                                 'User-Agent': 'armada-ports'})
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.load(r)['data']
        out += data['assets']
        if len(out) >= data['total'] or not data['assets']:
            break
        page += 1
    return out


def usable(a, sizes):
    if a.get('nsfw') or a.get('humor') or a.get('epilepsy') or a.get('is_animated') or a.get('is_deleted'):
        return False
    if a.get('mime') not in ('image/png', 'image/jpeg'):
        return False
    return sizes is None or (a.get('width'), a.get('height')) in sizes


def pick(game_id, kind, skip=0):
    asset_type, sizes = KINDS[kind]
    found = [a for a in assets(game_id, asset_type) if usable(a, sizes)]
    if kind == 'hero':
        found.sort(key=lambda a: (a['width'] < 1920, -(a.get('upvotes') or 0) + (a.get('downvotes') or 0)))
    return found[skip]['url'] if len(found) > skip else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('ports', nargs='*')
    ap.add_argument('--all', action='store_true')
    ap.add_argument('--skip', action='append', default=[], help='kind=N: take the N+1th best image')
    args = ap.parse_args()
    skips = {k: int(v) for k, v in (s.split('=') for s in args.skip)}
    path = os.path.join(ROOT, 'ports.json')
    with open(path) as f:
        catalog = json.load(f)
    for port in catalog['ports']:
        if args.ports and port['id'] not in args.ports:
            continue
        if not port.get('sgdb') or (port.get('art') and not args.all and not args.ports):
            continue
        art = dict(port.get('art') or {})
        for kind in KINDS:
            url = pick(port['sgdb'], kind, skips.get(kind, 0))
            if url:
                art[kind] = url
        port['art'] = art
        print(f'{port["id"]}: {", ".join(sorted(art))}', file=sys.stderr)
    with open(path, 'w') as f:
        json.dump(catalog, f, indent=2, ensure_ascii=False)
        f.write('\n')


if __name__ == '__main__':
    main()
