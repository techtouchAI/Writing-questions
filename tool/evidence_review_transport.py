"""Move allowlisted original CI evidence through GitHub's object API.

Azure artifact redirects are inaccessible from the review sandbox. Unattached
blobs provide a GitHub-hosted route without a commit, tree, ref, branch, release,
or tracked binary. Only synthetic regression evidence and allowlisted validation command logs qualify.
Small Checks annotations carry references/checksums, NEVER binary payloads.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess


def api(path, payload=None):
    command = ['gh', 'api', path]
    if payload is not None:
        command += ['--method', 'POST', '--input', '-']
    return json.loads(subprocess.check_output(command, input=None if payload is None else json.dumps(payload).encode()))


def selected(root, profile='production'):
    if profile == 'validation':
        manifest = json.loads((root / 'manifest.json').read_text())
        required = {'production-first.log', 'native-editor-first.log', 'flutter-test.log',
                    'flutter-test-canonical-gate.log', 'flutter-analyze.log', 'flutter-build.log'}
        present, absent = manifest['files'], manifest['notProduced']
        if (len(present) != len(set(present)) or len(absent) != len(set(absent)) or
                set(present) & set(absent) or set(present) | set(absent) != required):
            raise ValueError('Validation logs must account for every command, including unexecuted ones')
        for name in sorted(set(present) | {'manifest.json'}):
            path = root / name
            if not path.is_file() or path.is_symlink():
                raise ValueError(f'Missing/unsafe evidence: {name}')
            yield path
        return
    if profile == 'visual':
        manifest = json.loads((root / 'manifest.json').read_text())
        count = manifest['pageCount']
        if not isinstance(count, int) or not 1 <= count <= 30:
            raise ValueError('Invalid visual page inventory')
        expected = {'vector.pdf', *(f'preview_page_{page}.png' for page in range(1, count + 1))}
        if set(manifest['files']) != expected or len(manifest['files']) != len(expected):
            raise ValueError('Visual manifest does not describe every required original')
        companions = {'manifest.json'}
        if (root / 'arabic-header-outline.json').exists():
            companions.add('arabic-header-outline.json')
        for name in sorted(expected | companions):
            path = root / name
            if not path.is_file() or path.is_symlink():
                raise ValueError(f'Missing/unsafe evidence: {name}')
            yield path
        return
    if profile != 'production':
        raise ValueError('Unknown evidence profile')
    # Enumerate required companions, not merely files that happened to exist.
    names = {'production-font-assets.json'}
    if (root / 'opentype-clusters.pdf').exists():
        names.add('opentype-clusters.pdf')
    # Historical runs predate this case. New evidence must include the ENTIRE
    # companion group if any member exists; never transport a partial PDF set.
    option_evidence = {'optend-manifest.json', 'optend-long.pdf', 'optend-short.pdf'}
    if any((root / name).exists() for name in option_evidence):
        names.update(option_evidence)
    if (root / 'editing-manifest.json').exists():
        expected_editing = {f'drag-{width}-{kind}-{ending}' for width in (320, 360)
            for kind in ('question', 'branch-within', 'branch-between')
            for ending in ('before.png', 'after.png', 'after.pdf')}
        editing = json.loads((root / 'editing-manifest.json').read_text())
        if set(editing['files']) != expected_editing or len(editing['files']) != len(expected_editing):
            raise ValueError('Editing manifest must enumerate every gesture companion')
        names.update(expected_editing | {'editing-manifest.json'})
    for width in (320, 360):
        for style in ('inline', 'display'):
            names.add(f'r13-math-{width}-{style}.png')
    for width in (320, 360):
        r9 = json.loads((root / f'r9-{width}-manifest.json').read_text())
        if r9['pageCount'] < 3:
            raise ValueError('Expected split production evidence including page 2')
        names.update((f'r9-{width}-manifest.json', f'r9-{width}-same-live-plan.pdf',
                      f'r10-native-{width}-manifest.json', f'r10-native-{width}-same-live-plan.pdf'))
        for state in ('before-selection', 'question-selected', 'branch-selected'):
            for page in range(r9['pageCount']):
                names.add(f'r9-{width}-{state}-page-{page}-paper.png')
            names.add(f'r9-{width}-{state}-page-2-phone.png')
        data = json.loads((root / f'r10-native-{width}-manifest.json').read_text())
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


def inventory_sha(rows):
    plain = [{key: value for key, value in row.items()
              if key not in ('inventoryCount', 'inventorySha256')} for row in rows]
    plain.sort(key=lambda row: row['file'])
    return hashlib.sha256(json.dumps(plain, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def publish(args):
    repository = os.environ['GITHUB_REPOSITORY']
    rows = []
    for path in selected(args.root, getattr(args, 'profile', 'production')):
        raw = path.read_bytes()
        result = api(f'repos/{repository}/git/blobs', {'encoding': 'base64', 'content': base64.b64encode(raw).decode()})
        if result['sha'] != git_blob_sha(raw):
            raise ValueError('GitHub returned a different blob identity')
        rows.append(dict(file=path.name, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                         blob=result['sha'], sourceSha=os.environ['GITHUB_SHA'], sourceRun=os.environ['GITHUB_RUN_ID']))
    if not rows or len(rows) > 80:
        raise ValueError(f'Unexpected evidence inventory: {len(rows)}')
    digest = inventory_sha(rows)
    rows = [dict(row, inventoryCount=len(rows), inventorySha256=digest) for row in rows]
    args.index.write_text(json.dumps(rows, indent=2))


def emit(args):
    rows = json.loads(args.index.read_text())
    # At most five notices per step and forty per job (80 references). GitHub
    # truncates at 50 annotations/job even when each step is below its limit.
    group = rows[args.group * 10:(args.group + 1) * 10]
    for offset in range(0, len(group), 2):
        message = json.dumps(group[offset:offset + 2], separators=(',', ':'))
        if len(message) > 2800:
            raise ValueError('Reference exceeds safe Checks message budget')
        print('::notice title=Evidence blob reference::' + message.replace('%', '%25').replace('\n', '%0A').replace('\r', '%0D'))


def fetch(args):
    args.destination.mkdir(parents=True, exist_ok=True)
    # Even a failed API request or incomplete retry invalidates the old marker.
    (args.destination / 'retrieval-provenance.json').unlink(missing_ok=True)
    repository = args.repository
    run = api(f'repos/{repository}/actions/runs/{args.run}')
    jobs = api(f'repos/{repository}/actions/runs/{args.run}/jobs?per_page=100')['jobs']
    rows = []
    for job in jobs:
        if job['name'] != getattr(args, 'job_name', 'Original evidence review transport'):
            continue
        if job['conclusion'] != 'success':
            raise ValueError('Evidence transport job has not succeeded')
        for page in range(1, 20):
            annotations = api(f"repos/{repository}/check-runs/{job['id']}/annotations?per_page=100&page={page}")
            for annotation in annotations:
                if annotation['title'] == 'Evidence blob reference':
                    packet = json.loads(annotation['message'])
                    if not isinstance(packet, list):
                        raise ValueError('Legacy inventory lacks a completeness proof; republish required')
                    rows.extend(packet)
            if len(annotations) < 100:
                break
    if not rows:
        raise ValueError('No verified evidence references; refusing empty success')
    if any(row.get('inventoryCount') != len(rows) for row in rows):
        raise ValueError('Incomplete evidence inventory: annotation truncation')
    digest = inventory_sha(rows)
    if any(row.get('inventorySha256') != digest for row in rows):
        raise ValueError('Evidence inventory checksum mismatch')
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
    (args.destination / 'retrieval-provenance.json').write_text(json.dumps(dict(verifiedComplete=True, count=len(rows), sourceRun=str(args.run),
        sourceSha=run['head_sha'], inventorySha256=digest, files=rows), indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('publish'); p.add_argument('--root', type=Path, required=True); p.add_argument('--index', type=Path, required=True); p.add_argument('--profile', choices=['production', 'visual', 'validation'], default='production')
    p = sub.add_parser('emit'); p.add_argument('--index', type=Path, required=True); p.add_argument('--group', type=int, required=True)
    p = sub.add_parser('fetch'); p.add_argument('--run', required=True); p.add_argument('--repository', default='techtouchAI/Writing-questions'); p.add_argument('--destination', type=Path, required=True); p.add_argument('--job-name', default='Original evidence review transport')
    args = parser.parse_args()
    {'publish': publish, 'emit': emit, 'fetch': fetch}[args.command](args)
