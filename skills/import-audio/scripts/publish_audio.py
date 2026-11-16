#!/usr/bin/env python3
"""Upload a staged audio tree, index it, write Grimoire metadata, and verify it.

usage: publish_audio.py --plan DIR|plan.json [--run-dir DIR] [--cli PATH]
                        [--poll-seconds 5] [--scan-timeout 1800]

Reads DIR/stage/tree (from stage_audio.py) and plan["root"], e.g.
"audio/Example Soundworks". In order:
  1. refuses if a library scan is running (a scan swallows writes)
  2. creates every missing folder level below audio/, parent first
  3. uploads each staged file with --on-conflict skip. A 409 "already exists"
     is a skip, not a failure (the server answers exit 2 for it)
  4. checks every target on the server (files browse) at its staged size; never the library mount
  5. one scoped `library rescan`, polled until running is false
  6. resolves ids from `audio list` by relative_path
  7. writes tags + description: `audio batch-update` for rows uploaded now
     (tags there REPLACE); an additive `audio batch-tag` only for rows that were
     already present, so a re-run never strips tags someone added by hand
  8. reads every row back with `audio get`: title, tags, description, and the
     album/artist/artwork the plan expects

stdout: {"rows":N,"uploaded":N,"skipped":N,"new_audio":N,"verified":N,"ok":true}
receipt: DIR/receipts/publish.json
exit: 0 ok · 1 usage · 2 precondition/server error · 3 some row failed verification
"""
import argparse, json, os, subprocess, sys, time, unicodedata

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), '..', '..', '..', 'lib'))
from grimoire_skills import config  # noqa: E402

NFC = lambda s: unicodedata.normalize('NFC', s)


def run(cli, *args, input=None):
    p = subprocess.run([cli, *args], capture_output=True, text=True, input=input)
    try:
        body = json.loads(p.stdout) if p.stdout.strip() else {}
    except json.JSONDecodeError:
        body = {}
    return p.returncode, body, p.stderr + p.stdout


def die(code, msg):
    print(msg, file=sys.stderr)
    sys.exit(code)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--plan', required=True)
    ap.add_argument('--run-dir', help='default: the folder holding the plan')
    ap.add_argument('--cli', default=None, help='CLI path (default: config, PATH, ./bin/grimoire-cli)')
    ap.add_argument('--poll-seconds', type=float, default=5)
    ap.add_argument('--scan-timeout', type=float, default=1800)
    a = ap.parse_args()
    a.cli = config.cli_path(config.load(), a.cli)
    plan_file, plan_dir = config.plan_paths(a.plan)
    a.run_dir = a.run_dir or plan_dir
    plan = json.load(open(plan_file, encoding='utf-8'))
    root = plan.get('root', '').rstrip('/')
    rows = plan.get('rows') or []
    if not root.startswith('audio/') and root != 'audio':
        die(1, f'plan root must lie under audio/: {root!r}')
    tree = os.path.join(a.run_dir, 'stage', 'tree')
    missing = [r['target'] for r in rows if not os.path.lexists(os.path.join(tree, r['target']))]
    if missing:
        die(2, 'not staged (run stage_audio.py first):\n' + '\n'.join(missing))
    os.makedirs(os.path.join(a.run_dir, 'receipts'), exist_ok=True)
    rec = dict(root=root, entries=[])

    # 1. a running scan swallows writes
    rc, st, err = run(a.cli, 'library', 'scan-status')
    if rc:
        die(2, 'scan-status failed: ' + err.strip()[-200:])
    if st.get('running'):
        die(2, 'a library scan is running - wait for it; writes fired now are dropped')

    # 2. folders, parent first
    dirs = sorted({os.path.dirname(r['target']) for r in rows})
    levels = []
    for d in dirs:
        parts = (root + ('/' + d if d else '')).split('/')
        for i in range(2, len(parts) + 1):
            p = '/'.join(parts[:i])
            if p not in levels:
                levels.append(p)
    created = []
    for p in levels:
        rc, _, err = run(a.cli, 'files', 'browse', '--path', p)
        if rc == 0:
            continue
        if 'No such path' not in err:
            die(2, f'cannot read {p}: ' + err.strip()[-200:])
        parent, name = p.rsplit('/', 1)
        rc, _, err = run(a.cli, 'files', 'folder', 'create', '--parent', parent, '--name', name)
        if rc:
            die(2, f'cannot create {p}: ' + err.strip()[-200:])
        created.append(p)
    rec['created'] = created

    # 3. upload
    for r in rows:
        dest = root + ('/' + os.path.dirname(r['target']) if os.path.dirname(r['target']) else '')
        rc, body, err = run(a.cli, 'files', 'upload', '--destination', dest,
                            '--file', os.path.join(tree, r['target']), '--on-conflict', 'skip')
        base = os.path.basename(r['target'])
        if rc == 0 and NFC(body.get('name', '')) == NFC(base):
            state = 'uploaded'
        elif 'already exists' in err:
            state = 'skipped'
        else:
            state = 'failed'
        rec['entries'].append(dict(target=r['target'], upload=state, error='' if state != 'failed' else err.strip()[-200:]))
    up = [e for e in rec['entries'] if e['upload'] == 'uploaded']
    if any(e['upload'] == 'failed' for e in rec['entries']):
        json.dump(rec, open(os.path.join(a.run_dir, 'receipts', 'publish.json'), 'w'), ensure_ascii=False, indent=1)
        die(2, 'uploads failed: ' + ', '.join(e['target'] for e in rec['entries'] if e['upload'] == 'failed'))

    # 4. the server's listing is the ground truth an upload receipt is not (never the library mount)
    listings = {}
    for r in rows:
        d = root + ('/' + os.path.dirname(r['target']) if os.path.dirname(r['target']) else '')
        if d not in listings:
            rc, body, err = run(a.cli, 'files', 'browse', '--path', d)
            listings[d] = {NFC(e['name']): e.get('size') for e in body.get('entries', [])} if rc == 0 else {}
        want = os.path.getsize(os.path.realpath(os.path.join(tree, r['target'])))
        got = listings[d].get(NFC(os.path.basename(r['target'])))
        if got != want:
            die(2, f'{r["target"]} on the server: {got} bytes, staged {want}')

    # 5. index
    rc, _, err = run(a.cli, 'library', 'rescan', '--scope', root, '--metadata-mode', 'missing')
    if rc:
        die(2, 'rescan refused: ' + err.strip()[-200:])
    t0 = time.time()
    while True:
        rc, st, err = run(a.cli, 'library', 'scan-status')
        if rc == 0 and st.get('running') is False:
            break
        if time.time() - t0 > a.scan_timeout:
            die(2, 'scan still running after --scan-timeout; read `grimoire-cli logs` before touching it')
        time.sleep(a.poll_seconds)
    rec['new_audio'] = st.get('new_audio')

    # 6. ids
    rc, lst, err = run(a.cli, 'audio', 'list', '--limit', '100000')
    if rc:
        die(2, 'audio list failed: ' + err.strip()[-200:])
    ids = {NFC(x['relative_path']): x['id'] for x in lst.get('audio', [])}
    for r, e in zip(rows, rec['entries']):
        e['id'] = ids.get(NFC(root + '/' + r['target']))
    unresolved = [e['target'] for e in rec['entries'] if not e['id']]
    if unresolved:
        json.dump(rec, open(os.path.join(a.run_dir, 'receipts', 'publish.json'), 'w'), ensure_ascii=False, indent=1)
        die(2, 'not indexed after the scan:\n' + '\n'.join(unresolved))

    # 7. metadata: replace on new rows, add-only on rows that were already there
    fresh = [dict(id=e['id'], tags=r['tags'], **({'description': r['description']} if r.get('description') else {}))
             for r, e in zip(rows, rec['entries']) if e['upload'] == 'uploaded']
    if fresh:
        rc, body, err = run(a.cli, 'audio', 'batch-update', '--stdin', input=json.dumps({'items': fresh}, ensure_ascii=False))
        if rc not in (0, 3):
            die(2, 'batch-update failed: ' + err.strip()[-200:])
        rec['batch_update_errors'] = body.get('errors', [])
    old = [(r, e) for r, e in zip(rows, rec['entries']) if e['upload'] == 'skipped']
    for tag in sorted({t for r, _ in old for t in r['tags']}):
        ids_t = [e['id'] for r, e in old if tag in r['tags']]
        run(a.cli, 'audio', 'batch-tag', '--stdin', input=json.dumps({'ids': ids_t, 'tags': [tag]}))

    # 8. read back
    verified = 0
    for r, e in zip(rows, rec['entries']):
        rc, g, err = run(a.cli, 'audio', 'get', '--id', e['id'])
        pr = []
        if rc:
            pr.append('audio get failed')
        else:
            if NFC(g.get('title') or '') != NFC(r['title']):
                pr.append(f'title {g.get("title")!r}, expected {r["title"]!r}')
            if not set(r['tags']) <= set(g.get('tags') or []):
                pr.append(f'tags {g.get("tags")}')
            if e['upload'] == 'uploaded' and (r.get('description') or '') != (g.get('description') or ''):
                pr.append('description differs')
            exp = r.get('expect') or {}
            for k in ('album', 'artist'):
                if exp.get(k) and NFC(g.get(k) or '') != NFC(exp[k]):
                    pr.append(f'{k} {g.get(k)!r}, expected {exp[k]!r}')
            if exp.get('artwork') and not g.get('has_artwork'):
                pr.append('no artwork')
        e['problems'] = pr
        verified += not pr
    json.dump(rec, open(os.path.join(a.run_dir, 'receipts', 'publish.json'), 'w'), ensure_ascii=False, indent=1)
    res = dict(rows=len(rows), uploaded=len(up), skipped=sum(e['upload'] == 'skipped' for e in rec['entries']),
               created=len(created), new_audio=rec['new_audio'], verified=verified, ok=verified == len(rows))
    print(json.dumps(res, separators=(',', ':')))
    for e in rec['entries']:
        for p in e.get('problems', []):
            print(f'FAIL {e["target"]} :: {p}', file=sys.stderr)
    sys.exit(0 if res['ok'] else 3)


if __name__ == '__main__':
    main()
