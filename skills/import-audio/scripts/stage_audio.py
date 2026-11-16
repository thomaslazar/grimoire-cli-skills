#!/usr/bin/env python3
"""Build the upload tree for an audio import, and prove it did no harm.

usage: stage_audio.py --plan DIR|plan.json [--run-dir DIR]

For each plan row: a symlink when the file needs no tag change, otherwise a
tagged copy (with "clean": true the source's own tags are dropped first) written with `ffmpeg -c copy` (lossless) under DIR/stage/tree/<target>.
Then every copy is checked three ways: its raw audio frames hash equal to the
source's, every tag it was asked to write reads back as written, and it carries
no `encoder` stamp. The source corpus is never written to.

stdout: {"rows":N,"symlinks":N,"copies":N,"ok":true}   receipt: DIR/receipts/stage.json
exit: 0 ok · 1 usage/tooling · 2 refused before staging · 3 a copy failed a check
"""
import argparse, hashlib, json, os, shutil, subprocess, sys, unicodedata

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), '..', '..', '..', 'lib'))
from grimoire_skills import config  # noqa: E402

NFC = lambda s: unicodedata.normalize('NFC', s)


def die(code, msg):
    print(msg, file=sys.stderr)
    sys.exit(code)


def raw_audio_hash(path):
    # Remuxing to MP3 re-writes an ID3 header and a Xing frame that carry the tags,
    # so a plain `-c copy` hash differs for every retagged file. Strip them first.
    r = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-map', '0:a', '-c', 'copy',
                        '-map_metadata', '-1', '-id3v2_version', '0', '-write_id3v1', '0',
                        '-write_xing', '0', '-f', 'mp3', '-'], capture_output=True)
    if r.returncode:
        raise RuntimeError(r.stderr.decode(errors='replace')[-300:])
    return hashlib.sha256(r.stdout).hexdigest()


def probe(path):
    r = subprocess.run(['ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_format',
                        '-show_streams', path], capture_output=True, text=True)
    j = json.loads(r.stdout or '{}')
    tags = {k.lower(): v for k, v in j.get('format', {}).get('tags', {}).items()}
    pics = [s for s in j.get('streams', []) if s.get('codec_type') == 'video']
    return tags, pics


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument('--plan', required=True)
    ap.add_argument('--run-dir', help='default: the folder holding the plan')
    a = ap.parse_args()
    for tool in ('ffmpeg', 'ffprobe'):
        if not shutil.which(tool):
            die(1, f'{tool} not found - required for tagged copies and their checks')
    plan_file, plan_dir = config.plan_paths(a.plan)
    a.run_dir = a.run_dir or plan_dir
    plan = json.load(open(plan_file, encoding='utf-8'))
    rows = plan.get('rows') or []
    if not rows:
        die(2, 'plan has no rows')

    # refuse before touching anything
    seen, bad = set(), []
    for r in rows:
        t = r.get('target', '')
        if not t or t.startswith('/') or '..' in t.split('/'):
            bad.append(f'target is empty, absolute or escapes the root: {t!r}')
        elif NFC(t) in seen:
            bad.append(f'duplicate target: {t}')
        seen.add(NFC(t))
        if not os.path.isfile(r.get('source', '')):
            bad.append(f'no such source: {r.get("source")}')
        if r.get('cover') and not os.path.isfile(r['cover']):
            bad.append(f'no such cover: {r["cover"]}')
        if '/' in (r.get('title') or '') or '\\' in (r.get('title') or ''):
            bad.append(f'title holds a path separator: {r["title"]!r}')
    if bad:
        die(2, '\n'.join(bad))

    tree = os.path.join(a.run_dir, 'stage', 'tree')
    os.makedirs(os.path.join(a.run_dir, 'receipts'), exist_ok=True)
    out, failed = [], 0
    for r in rows:
        dst = os.path.join(tree, r['target'])
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if os.path.lexists(dst):
            os.remove(dst)
        write = r.get('write') or {}
        if not write and not r.get('cover'):
            os.symlink(os.path.abspath(r['source']), dst)
            out.append(dict(target=r['target'], staged='symlink'))
            continue
        cmd = ['ffmpeg', '-v', 'error', '-y', '-i', r['source']]
        if r.get('cover'):
            cmd += ['-i', r['cover'], '-map', '0:a', '-map', '1:v', '-c', 'copy',
                    '-disposition:v:0', 'attached_pic',
                    '-metadata:s:v', 'title=Album cover', '-metadata:s:v', 'comment=Cover (front)']
        else:
            cmd += ['-map', '0', '-c', 'copy']      # keep the publisher's embedded art
        if r.get('clean'):
            cmd += ['-map_metadata', '-1']        # drop every old tag: only `write` survives
        # +bitexact keeps ffmpeg's own "encoder: Lavf…" stamp out of the tags
        cmd += ['-fflags', '+bitexact', '-id3v2_version', '3']
        for k, v in write.items():
            cmd += ['-metadata', f'{k}={v}']
        p = subprocess.run(cmd + [dst], capture_output=True, text=True)
        e = dict(target=r['target'], staged='copy', problems=[])
        if p.returncode:
            e['problems'].append('ffmpeg: ' + p.stderr.strip()[-200:])
        else:
            if raw_audio_hash(r['source']) != raw_audio_hash(dst):
                e['problems'].append('audio frames differ from the source')
            tags, pics = probe(dst)
            for k, v in write.items():
                if tags.get(k.lower()) != str(v):
                    e['problems'].append(f'{k} reads back {tags.get(k.lower())!r}, wrote {v!r}')
            if 'encoder' in tags:
                e['problems'].append('carries an encoder tag')
            if r.get('clean'):
                extra = sorted(set(tags) - {k.lower() for k in write})
                if extra:
                    e['problems'].append(f'clean copy still carries {extra}')
            if r.get('cover') and not pics:
                e['problems'].append('cover not embedded')
        failed += bool(e['problems'])
        out.append(e)

    res = dict(rows=len(rows), symlinks=sum(x['staged'] == 'symlink' for x in out),
               copies=sum(x['staged'] == 'copy' for x in out), failed=failed,
               entries=out, ok=failed == 0)
    json.dump(res, open(os.path.join(a.run_dir, 'receipts', 'stage.json'), 'w'), ensure_ascii=False, indent=1)
    print(json.dumps({k: res[k] for k in ('rows', 'symlinks', 'copies', 'failed', 'ok')}, separators=(',', ':')))
    for x in out:
        for pr in x.get('problems', []):
            print(f'FAIL {x["target"]} :: {pr}', file=sys.stderr)
    sys.exit(0 if failed == 0 else 3)


if __name__ == '__main__':
    main()
