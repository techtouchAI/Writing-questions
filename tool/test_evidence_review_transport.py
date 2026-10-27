"""Offline regressions for lossless CI evidence references (no GitHub writes)."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import evidence_review_transport as transport


class EvidenceTransportTest(unittest.TestCase):
    def test_optional_long_option_companions_are_all_required(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            # A minimal historical production inventory. Build explicit fixture
            # names instead of accepting whatever files happen to be present.
            names = {'production-font-assets.json'}
            for width in (320, 360):
                (root / f'r9-{width}-manifest.json').write_text(json.dumps({'pageCount': 3}))
                (root / f'r10-native-{width}-manifest.json').write_text(json.dumps({'lastBranchPage': 2}))
                names.update({f'r9-{width}-same-live-plan.pdf', f'r10-native-{width}-same-live-plan.pdf'})
                for style in ('inline', 'display'):
                    names.add(f'r13-math-{width}-{style}.png')
                for state in ('before-selection', 'question-selected', 'branch-selected'):
                    names.add(f'r9-{width}-{state}-page-2-phone.png')
                    for page in range(3):
                        names.add(f'r9-{width}-{state}-page-{page}-paper.png')
                for state in ('before-selection', 'option-selected'):
                    for view in ('phone', 'paper'):
                        names.add(f'r10-native-{width}-{state}-page-2-{view}.png')
            for name in names:
                (root / name).write_bytes(b'fixture')
            list(transport.selected(root))  # Existing run remains retrievable.
            (root / 'optend-manifest.json').write_text('{}')
            with self.assertRaisesRegex(ValueError, 'Missing/unsafe'):
                list(transport.selected(root))
            for name in ('optend-long.pdf', 'optend-short.pdf'):
                (root / name).write_bytes(b'fixture-pdf')
            delivered = {path.name for path in transport.selected(root)}
            self.assertTrue({'optend-manifest.json', 'optend-long.pdf', 'optend-short.pdf'} <= delivered)
            editing = {f'drag-{width}-{kind}-{ending}' for width in (320, 360)
                for kind in ('question', 'branch-within', 'branch-between')
                for ending in ('before.png', 'after.png', 'after.pdf')}
            (root / 'editing-manifest.json').write_text(json.dumps({'files': sorted(editing)}))
            with self.assertRaisesRegex(ValueError, 'Missing/unsafe'):
                list(transport.selected(root))
            for name in editing:
                (root / name).write_bytes(b'gesture-evidence-fixture')
            self.assertTrue(editing <= {p.name for p in transport.selected(root)})
            (root / 'editing-manifest.json').write_text(json.dumps({'files': sorted(editing)[:-1]}))
            with self.assertRaisesRegex(ValueError, 'every gesture companion'):
                list(transport.selected(root))
            (root / 'editing-manifest.json').write_text(json.dumps({'files': sorted(editing)}))
            (root / 'opentype-clusters.pdf').write_bytes(b'complex-cluster-original-fixture')
            self.assertIn('opentype-clusters.pdf', {p.name for p in transport.selected(root)})
            self.assertLessEqual(len(list(transport.selected(root))), 80)

    def test_validation_logs_distinguish_not_produced_from_success(self):
        names = {'production-first.log', 'native-editor-first.log', 'flutter-test.log',
                 'flutter-test-canonical-gate.log', 'flutter-analyze.log', 'flutter-build.log'}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            present = ['production-first.log', 'flutter-analyze.log']
            for name in present:
                (root / name).write_text('complete command output')
            manifest = dict(files=present, notProduced=sorted(names - set(present)))
            (root / 'manifest.json').write_text(json.dumps(manifest))
            self.assertEqual({p.name for p in transport.selected(root, 'validation')},
                             set(present + ['manifest.json']))
            manifest['notProduced'].remove('flutter-build.log')
            (root / 'manifest.json').write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, 'every command'):
                list(transport.selected(root, 'validation'))

    def test_validation_manifest_cannot_claim_a_missing_log(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'manifest.json').write_text(json.dumps(dict(files=['production-first.log'],
                notProduced=['native-editor-first.log', 'flutter-test.log',
                    'flutter-test-canonical-gate.log', 'flutter-analyze.log', 'flutter-build.log'])))
            with self.assertRaisesRegex(ValueError, 'Missing/unsafe'):
                list(transport.selected(root, 'validation'))

    def test_annotation_packing_stays_below_job_and_step_limits(self):
        rows = [{'file': f'evidence-{i}.png', 'inventoryCount': 80} for i in range(80)]
        with tempfile.TemporaryDirectory() as directory:
            index = Path(directory) / 'index.json'
            index.write_text(json.dumps(rows))
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                for group in range(8):
                    transport.emit(SimpleNamespace(index=index, group=group))
            notices = output.getvalue().splitlines()
            self.assertLessEqual(len(notices), 40, 'GitHub truncates a job at 50 annotations')
            decoded = [json.loads(line.split('::', 2)[2]) for line in notices]
            self.assertEqual([row for pair in decoded for row in pair], rows)

    def test_visual_profile_requires_pdf_and_every_manifest_page(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            names = ['vector.pdf', 'preview_page_1.png', 'preview_page_2.png']
            (root / 'manifest.json').write_text(json.dumps(dict(pageCount=2, files=names)))
            for name in names:
                (root / name).write_bytes(b'original')
            self.assertEqual({p.name for p in transport.selected(root, 'visual')}, set(names + ['manifest.json']))
            (root / names[-1]).unlink()
            with self.assertRaisesRegex(ValueError, 'Missing/unsafe'):
                list(transport.selected(root, 'visual'))

    def test_visual_manifest_cannot_omit_a_companion(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'manifest.json').write_text(json.dumps(dict(pageCount=2, files=['vector.pdf', 'preview_page_1.png'])))
            with self.assertRaisesRegex(ValueError, 'every required original'):
                list(transport.selected(root, 'visual'))

    def exercise_fetch(self, *, truncate=False, corrupt=False):
        rows = []
        blobs = {}
        import base64
        import hashlib
        for i in range(3):
            raw = f'original bytes {i}'.encode()
            sha = transport.git_blob_sha(raw)
            rows.append(dict(file=f'original-{i}.png', bytes=len(raw),
                sha256=hashlib.sha256(raw).hexdigest(), blob=sha, sourceSha='source-sha', sourceRun='123'))
            blobs[sha] = dict(encoding='base64', content=base64.b64encode(raw).decode())
        count = len(rows)
        digest = transport.inventory_sha(rows)
        rows = [dict(row, inventoryCount=count, inventorySha256=digest) for row in rows]
        delivered = rows[:2] if truncate else rows
        annotations = [dict(title='Evidence blob reference', message=json.dumps(delivered))]
        if corrupt:
            blobs[rows[0]['blob']]['content'] = base64.b64encode(b'not the original').decode()

        def fake_api(path):
            if path.endswith('/actions/runs/123'):
                return dict(head_sha='source-sha')
            if '/jobs?' in path:
                return dict(jobs=[dict(name='Original evidence review transport', conclusion='success', id=9)])
            if '/annotations?' in path:
                return annotations
            if '/git/blobs/' in path:
                return blobs[path.rsplit('/', 1)[1]]
            self.fail(f'Unexpected API call {path}')

        with tempfile.TemporaryDirectory() as directory, patch.object(transport, 'api', fake_api):
            destination = Path(directory) / 'retrieved'
            args = SimpleNamespace(repository='owner/repo', run='123', destination=destination)
            if truncate or corrupt:
                with self.assertRaisesRegex(ValueError, 'inventory|checksum'):
                    transport.fetch(args)
                self.assertFalse((destination / 'retrieval-provenance.json').exists())
            else:
                transport.fetch(args)
                provenance = json.loads((destination / 'retrieval-provenance.json').read_text())
                self.assertTrue(provenance['verifiedComplete'])
                self.assertEqual(provenance['count'], 3)
                self.assertEqual(len(list(destination.glob('*.png'))), 3)

    def test_complete_originals_are_verified(self):
        self.exercise_fetch()

    def test_truncated_annotations_cannot_report_success(self):
        self.exercise_fetch(truncate=True)

    def test_corrupt_blob_cannot_report_success(self):
        self.exercise_fetch(corrupt=True)


if __name__ == '__main__':
    unittest.main()
