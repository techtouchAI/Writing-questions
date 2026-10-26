"""Move allowlisted original CI evidence through GitHub's object API.

Azure artifact redirects are inaccessible from the review sandbox. Unattached
blobs provide a GitHub-hosted route without a commit, tree, ref, branch, release,
or tracked binary. Only synthetic regression PNG/PDF/manifest files qualify.
Small Checks annotations carry references/checksums, NEVER binary payloads.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def api(path, payload=None):
    command = ['gh', 'api', path]
    if payload is not None:
        command += ['--method', 'POST', '--input', '-']
    return json.loads(subprocess.check_output(command, input=None if payload is None else json.dumps(payload).encode()))


def selected(root):
    patterns = [
        r'r9-(320|360)-(before-selection|question-selected|branch-selected)-page-\d+-paper\.png',
        r'r9-(320|360)-(before-selection|question-selected|branch-selected)-page-2-phone\.png',
        r'r9-(320|360)-(same-live-plan\.pdf|manifest\.json)',
        r'r10-native-(320|360)-(same-live-plan\.pdf|manifest\.json)',
    ]
    names = {p.name for p in root.iterdir() if any(re.fullmatch(pattern, p.name) for pattern in patterns)}
    for width in (320, 360):
        manifest = root / f'r10-native-{width}-manifest.json'
        data = json.loads(manifest.read_text())
        page = data['lastBranchPage']
        for state in ('before-selection', 'option-selected'):
            for view in ('phone', 'paper'):
                names.add(f'r10-native-{width}-{state}-page-{page}-{view}.png')
    for name in sorted(names):
        path = root / name
        if not path.is_file() or path.is_symlink():
            raise ValueError(f'Missing/unsafe evidence: {name}')
        yield path


def git_blob_sha(data):
    return hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest()


def publish(args):
    repository = os.environ['GITHUB_REPOSITORY']
    rows = []
    for path in selected(args.root):
        raw = path.read_bytes()
        result = api(f'repos/{repository}/git/blobs', {'encoding': 'base64', 'content': base64.b64encode(raw).decode()})
        if result['sha'] != git_blob_sha(raw):
            raise ValueError('GitHub returned a different blob identity')
        rows.append(dict(file=path.name, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                         blob=result['sha'], sourceSha=os.environ['GITHUB_SHA'], sourceRun=os.environ['GITHUB_RUN_ID']))
    if not rows or len(rows) > 80:
        raise ValueError(f'Unexpected evidence inventory: {len(rows)}')
    args.index.write_text(json.dumps(rows, indent=2))


def emit(args):
    rows = json.loads(args.index.read_text())
    for row in rows[args.group * 10:(args.group + 1) * 10]:
        message = json.dumps(row, separators=(',', ':'))
        if len(message) > 2800:
            raise ValueError('Reference exceeds safe Checks message budget')
        print('::notice title=Evidence blob reference::' + message.replace('%', '%25').replace('\n', '%0A').replace('\r', '%0D'))


def fetch(args):
    repository = args.repository
    run = api(f'repos/{repository}/actions/runs/{args.run}')
    jobs = api(f'repos/{repository}/actions/runs/{args.run}/jobs?per_page=100')['jobs']
    rows = []
    for job in jobs:
        if job['name'] != 'Original evidence review transport':
            continue
        if job['conclusion'] != 'success':
            raise ValueError('Evidence transport job has not succeeded')
        for page in range(1, 20):
            annotations = api(f"repos/{repository}/check-runs/{job['id']}/annotations?per_page=100&page={page}")
            rows += [json.loads(a['message']) for a in annotations if a['title'] == 'Evidence blob reference']
            if len(annotations) < 100:
                break
    if not rows:
        raise ValueError('No verified evidence references; refusing empty success')
    args.destination.mkdir(parents=True, exist_ok=True)
    seen = set()
    for row in rows:
        name = row['file']
        if Path(name).name != name or name in seen:
            raise ValueError('Unsafe/duplicate evidence path')
        if row['sourceSha'] != run['head_sha'] or str(row['sourceRun']) != str(args.run):
            raise ValueError('Evidence provenance does not match requested run')
        blob = api(f"repos/{repository}/git/blobs/{row['blob']}")
        if blob['encoding'] != 'base64':
            raise ValueError('Unexpected blob encoding')
        raw = base64.b64decode(blob['content'])
        if len(raw) != row['bytes'] or hashlib.sha256(raw).hexdigest() != row['sha256'] or git_blob_sha(raw) != row['blob']:
            raise ValueError('Truncated/corrupt evidence; checksum mismatch')
        (args.destination / name).write_bytes(raw)
        seen.add(name)
        print('VERIFIED', name, row['sha256'], flush=True)
    (args.destination / 'retrieval-provenance.json').write_text(json.dumps(rows, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('publish'); p.add_argument('--root', type=Path, required=True); p.add_argument('--index', type=Path, required=True)
    p = sub.add_parser('emit'); p.add_argument('--index', type=Path, required=True); p.add_argument('--group', type=int, required=True)
    p = sub.add_parser('fetch'); p.add_argument('--run', required=True); p.add_argument('--repository', default='techtouchAI/Writing-questions'); p.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    {'publish': publish, 'emit': emit, 'fetch': fetch}[args.command](args)
