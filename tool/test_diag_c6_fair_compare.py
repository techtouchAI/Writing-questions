import unittest

import diag_c6_fair_compare as fair


class CandidateRule(unittest.TestCase):
    def test_identical_content_above_the_ceiling_is_rejected(self):
        result = fair.candidate(
            {1: 0.035}, {1: 0.049},
            {(1, 'shift_1px'): 0.11, (1, 'delete_band'): 0.04,
             (1, 'underline_4px'): 0.05},
            {1: 0.08})
        self.assertFalse(result['acceptable'])
        self.assertIn('floor above ceiling', result['reasons'])

    def test_a_missed_defect_is_rejected_even_if_the_floor_passes(self):
        result = fair.candidate(
            {1: 0.01}, {1: 0.01},
            {(1, 'shift_1px'): 0.05, (1, 'delete_band'): 0.015,
             (1, 'underline_4px'): 0.04},
            {1: 0.05})
        self.assertFalse(result['acceptable'])
        self.assertTrue(any('delete_band' in reason for reason in result['reasons']))

    def test_cross_renderer_shift_must_also_fail(self):
        result = fair.candidate(
            {1: 0.01}, {1: 0.012},
            {(1, 'shift_1px'): 0.05, (1, 'delete_band'): 0.04,
             (1, 'underline_4px'): 0.04},
            {1: 0.015})
        self.assertFalse(result['acceptable'])

    def test_accepted_only_when_floor_passes_and_every_defect_fails(self):
        result = fair.candidate(
            {1: 0.01, 2: 0.012}, {1: 0.011, 2: 0.013},
            {(1, 'shift_1px'): 0.05, (1, 'delete_band'): 0.03,
             (1, 'underline_4px'): 0.04,
             (2, 'shift_1px'): 0.06, (2, 'delete_band'): 0.03,
             (2, 'underline_4px'): 0.04},
            {1: 0.04, 2: 0.04})
        self.assertTrue(result['acceptable'])
        self.assertEqual(result['reasons'], [])


if __name__ == '__main__':
    unittest.main()
