import unittest
from pdf_source_diagnostic import codepoints, exact_segment_count


class ExactSourceSegments(unittest.TestCase):
    def test_exact_reference_keeps_combining_marks(self):
        self.assertEqual(exact_segment_count('العنوان/سَلَامٌ English', 'سَلَامٌ'), 1)

    def test_duplicate_suffix_is_not_a_successful_substring(self):
        self.assertEqual(exact_segment_count('سَلَامٌمٌ', 'سَلَامٌ'), 0)

    def test_extra_prefix_or_suffix_marks_fail(self):
        for text in ['َسَلَامٌ', 'سَلَامٌَ', 'سَلَامٌم', 'بسَلَامٌ']:
            with self.subTest(text=text):
                self.assertEqual(exact_segment_count(text, 'سَلَامٌ'), 0)

    def test_reordered_lost_or_repeated_marks_fail(self):
        for text in ['ٌسَلاَم', 'سَلاَمٌ', 'سَالَمٌ', 'سَلامٌ', 'سَلَامٌٌ']:
            with self.subTest(text=text):
                self.assertEqual(exact_segment_count(text, 'سَلَامٌ'), 0)

    def test_plain_arabic_reversal_is_not_accepted(self):
        self.assertEqual(exact_segment_count('العربية', 'العربية'), 1)
        self.assertEqual(exact_segment_count('ةيبرعلا', 'العربية'), 0)

    def test_latin_and_digits_are_not_discarded(self):
        self.assertEqual(exact_segment_count('English 123٤٥٦', 'English 123٤٥٦'), 1)
        self.assertEqual(exact_segment_count('English 123٦٥٤', 'English 123٤٥٦'), 0)
        self.assertEqual(exact_segment_count('English 123٤٥٦7', 'English 123٤٥٦'), 0)

    def test_concatenated_latin_is_not_an_exact_segment(self):
        self.assertEqual(exact_segment_count('سَلَامٌEnglish', 'سَلَامٌ'), 0)

    def test_no_unicode_normalization(self):
        self.assertEqual(exact_segment_count('ا\u0654', 'أ'), 0)
        self.assertEqual(exact_segment_count('أ', 'ا\u0654'), 0)

    def test_multiple_occurrences_remain_multiple(self):
        self.assertEqual(exact_segment_count('سَلَامٌ\nسَلَامٌ', 'سَلَامٌ'), 2)

    def test_whitespace_is_not_normalized(self):
        self.assertEqual(exact_segment_count('English\n123', 'English 123'), 0)

    def test_join_controls_cannot_hide_duplicates(self):
        for text in ['سَلَامٌ\u200dم', 'سَلَامٌ\u200cم']:
            self.assertEqual(exact_segment_count(text, 'سَلَامٌ'), 0)

    def test_codepoints_preserve_source_order(self):
        self.assertEqual(codepoints('سَلَامٌ'),
            ['U+0633', 'U+064E', 'U+0644', 'U+064E', 'U+0627', 'U+0645', 'U+064C'])

    def test_empty_reference_is_not_vacuous_success(self):
        with self.assertRaises(ValueError):
            exact_segment_count('anything', '')


if __name__ == '__main__':
    unittest.main()
