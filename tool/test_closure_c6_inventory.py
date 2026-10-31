import unittest
import closure_c6_inventory as audit


def annotation(message, title=audit.TITLE):
    return dict(title=title, message=message)


class Inventory(unittest.TestCase):
    def test_retains_each_finding_even_identical_rows(self):
        row = "  WORD-MISSING p1 [block]: no glyphs inside 'x' cause=unresolved"
        result = audit.inventory([annotation('violations: WORD-MISSING=2\n' + row + '\n'),
                                  annotation(row + '\nverdict: WOULD FAIL (report mode)')])
        self.assertEqual(result['findingCount'], 2)
        self.assertEqual([r['id'] for r in result['findings']], ['C6-001', 'C6-002'])
        self.assertTrue(all(r['classification'] == 'inconclusive' for r in result['findings']))

    def test_checks_reverse_order_mid_word_chunks_are_reassembled_losslessly(self):
        text = ('violations: WORD-MISSING=1\n'
                "  WORD-MISSING p1 [block]: no glyphs inside 'test' cause=unresolved\n"
                'verdict: WOULD FAIL (report mode)')
        cut = text.index('glyphs') + 3
        result = audit.inventory([annotation(text[cut:]), annotation(text[:cut])])
        row = result['findings'][0]
        self.assertEqual(row['detail'], "no glyphs inside 'test' cause=unresolved")
        self.assertEqual(row['evidence']['annotationChunksCovered'], [2, 1])
        self.assertEqual(result['reassembledChunkOrder'], [2, 1])

    def test_rejects_truncated_report(self):
        with self.assertRaisesRegex(ValueError, 'counts do not reconcile'):
            audit.inventory([annotation('violations: WORD-MISSING=2\n'
                '  WORD-MISSING p1 [block]: absent\nverdict: WOULD FAIL (report mode)')])

    def test_historical_report_is_not_actual_verdict(self):
        with self.assertRaisesRegex(ValueError, 'one complete'):
            audit.inventory([annotation('violations: WORD-MISSING=0\nverdict: WOULD FAIL',
                title='C6 geometry historical tight-box diagnostic')])

    def test_source_float_is_preserved_and_job_success_is_not_a_pass(self):
        result = audit.inventory([annotation('violations: LINE-MISSING=1 (float 1)\n'
            '  LINE-MISSING p2 [float]: absent\nverdict: WOULD FAIL (report mode)')])
        self.assertEqual(result['findings'][0]['source'], 'float')
        self.assertEqual(result['verdict'], 'WOULD FAIL')


if __name__ == '__main__':
    unittest.main()
