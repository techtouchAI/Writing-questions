"""Tests the bounded diagnostic's acceptance logic, NOT a production repair."""
import copy
import unittest

from audit_pdf_opentype import HEADER_WORDS, QURAN_WORD_COUNTS, outline_check, source_text_check


class OutlineCheckTest(unittest.TestCase):
    def setUp(self):
        self.report = {'words': [
            {'text': text, 'sameOutlineSequence': True}
            for text in sorted(HEADER_WORDS)
        ]}

    def test_all_four_matching_sequences(self):
        self.assertTrue(outline_check(self.report))

    def test_rejects_empty(self):
        self.assertFalse(outline_check({}))
        self.assertFalse(outline_check({'words': []}))

    def test_rejects_missing_word(self):
        self.report['words'].pop()
        self.assertFalse(outline_check(self.report))

    def test_rejects_duplicate_word(self):
        self.report['words'][1] = copy.deepcopy(self.report['words'][0])
        self.assertFalse(outline_check(self.report))

    def test_rejects_extra_word(self):
        self.report['words'].append(copy.deepcopy(self.report['words'][0]))
        self.assertFalse(outline_check(self.report))

    def test_rejects_mismatched_outline_sequence(self):
        self.report['words'][0]['sameOutlineSequence'] = False
        self.assertFalse(outline_check(self.report))

    def test_rejects_absent_result(self):
        del self.report['words'][0]['sameOutlineSequence']
        self.assertFalse(outline_check(self.report))

    def test_rejects_truthy_non_boolean_result(self):
        self.report['words'][0]['sameOutlineSequence'] = 'true'
        self.assertFalse(outline_check(self.report))


class SourceTextCheckTest(unittest.TestCase):
    def setUp(self):
        self.report = dict(actualTextSourceCounts=dict(QURAN_WORD_COUNTS),
            extractorControlCharacters=[], extractorReplacementCharacterCount=0)

    def test_exact_source_tokens_and_no_control_artifacts(self):
        self.assertTrue(source_text_check(self.report))

    def test_missing_source_is_not_an_empty_success(self):
        self.assertFalse(source_text_check({}))
        self.report['actualTextSourceCounts'].pop('إِنَّا')
        self.assertFalse(source_text_check(self.report))

    def test_rejects_unknown_cid_control_artifacts(self):
        self.report['extractorControlCharacters'] = [19]
        self.assertFalse(source_text_check(self.report))

    def test_rejects_replacement_characters(self):
        self.report['extractorReplacementCharacterCount'] = 1
        self.assertFalse(source_text_check(self.report))


if __name__ == '__main__':
    unittest.main()
