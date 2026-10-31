"""Real-original negative controls; requires C6_ARTIFACTS, never empty PASS."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import unittest

from audit_c6_quran_words import audit


class ActualHistoricalWords(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)/'originals'
        self.output = Path(self.temp.name)/'output'; self.output.mkdir()
        original = Path(os.environ.get('C6_ARTIFACTS','build/visual_parity'))
        self.root.mkdir()
        for name in ['preview_positions.json','geometry_gate.json','vector.pdf','preview_page_1.png','preview_page_2.png']:
            shutil.copyfile(original/name,self.root/name)
        self.font = Path('assets/fonts/Amiri-Regular.ttf')

    def rebind(self, name):
        # A deliberate same-document test mutation. Rebind provenance so the
        # rejection must come from real paint checks, not just stale hashes.
        path=self.root/'preview_positions.json'
        source=json.loads(path.read_text())
        source['provenance']['artifactSha256'][name]=hashlib.sha256((self.root/name).read_bytes()).hexdigest()
        path.write_text(json.dumps(source))

    def test_all_three_actual_originals_have_exact_outlines_and_positions(self):
        report=audit(self.root,self.font,self.output)
        self.assertTrue(report['allThreeBoundedPaintChecksPassed'])
        self.assertEqual(len(report['rows']),3)
        for row in report['rows']:
            self.assertTrue(row['sameOutlineSequence'])
            self.assertLessEqual(row['maxActualGlyphOriginErrorPt'],1e-4)
            self.assertGreater(row['unicodeAliasCharacters'],0)
            self.assertFalse(row['manualVisualReview'])

    def test_quarter_point_pdf_glyph_shift_is_rejected_without_stale_hash_shortcut(self):
        import pymupdf
        pdf=pymupdf.open(self.root/'vector.pdf')
        pattern=rb'(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+Td'
        count=0
        def shift(m):
            nonlocal count
            count+=1
            return str(float(m[1])+.25).encode()+b' '+m[2]+b' Td'
        for page in pdf:
            for xref in page.get_contents():
                pdf.update_stream(xref,re.sub(pattern,shift,pdf.xref_stream(xref)))
        self.assertGreater(count,3)
        changed=pdf.tobytes();pdf.close();(self.root/'vector.pdf').write_bytes(changed)
        self.rebind('vector.pdf')
        with self.assertRaisesRegex(ValueError,'painted glyph origin moved'):
            audit(self.root,self.font,self.output)

    def test_wrong_source_font_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'outlines differ'):
            audit(self.root,Path('assets/fonts/NotoNaskhArabic-Regular.ttf'),self.output)

    def test_erased_native_ink_is_rejected_after_rebinding(self):
        from PIL import Image
        path=self.root/'preview_page_1.png'
        with Image.open(path) as original: size=original.size
        Image.new('RGB',size,'white').save(path)
        self.rebind(path.name)
        with self.assertRaisesRegex(ValueError,'no visible ink'):
            audit(self.root,self.font,self.output)

    def test_missing_historical_occurrence_is_not_empty_success(self):
        path=self.root/'preview_positions.json'; source=json.loads(path.read_text())
        for line in source['pages'][0]['lines']:
            line['runs']=[r for r in line['runs'] if r['text'] != 'أَعْطَيْنَاكَ']
        path.write_text(json.dumps(source))
        with self.assertRaisesRegex(ValueError,'all three historical rows'):
            audit(self.root,self.font,self.output)

if __name__=='__main__':unittest.main()
