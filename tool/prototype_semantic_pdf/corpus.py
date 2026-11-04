"""Representative corpus for the semantic-encoding prototype.

Each item is a list of lines; every item gets its own page. The reference is the
**exact logical source** (no normalisation, no mark sorting, no reordering).
"""
from __future__ import annotations

CORPUS = [
    {
        'id': 'salatun',
        'lines': ['سَلَامٌ'],
        'why': 'the failing Android statement word: fatha, lam-alef ligature, dammatan',
    },
    {
        'id': 'short_phrase',
        'lines': ['نص عربي طويل'],
        'why': 'plain unvocalised Arabic words, several words per line',
    },
    {
        'id': 'lam_alef_hamza',
        'lines': ['الْأَلِف'],
        'why': 'lam-alef with hamza (U+FEF7) plus sukun and fatha',
    },
    {
        'id': 'multi_mark',
        'lines': ['مُحَمَّدٌ'],
        'why': 'several marks per word, shadda + fatha on one base',
    },
    {
        'id': 'long_sentence',
        'lines': ['هَذِهِ جُمْلَةٌ عَرَبِيَّةٌ طَوِيلَةٌ جِدًّا لِاخْتِبَارِ الِاسْتِخْرَاجِ.'],
        'why': 'long fully vocalised sentence with punctuation',
    },
    {
        'id': 'mixed',
        'lines': ['نص عربي English 123'],
        'why': 'RTL/LTR mixed run with Latin word and digits',
    },
    {
        'id': 'digits_punct',
        'lines': ['(٢٠ درجة) ٤٥٦'],
        'why': 'Arabic-Indic digits, brackets, punctuation',
    },
    {
        'id': 'two_lines',
        'lines': ['السطر الأول', 'السطر الثاني'],
        'why': 'line wrapping across two visual lines',
    },
    {
        'id': 'allah',
        'lines': ['إِنَّ اللَّهَ'],
        'why': 'word ligature U+FDF2 (الله) next to shadda+fatha',
    },
    {
        'id': 'tanwin_alef',
        'lines': ['عِلْمًا'],
        'why': 'tanwin above an alef that has no visible base separation',
    },
    {
        'id': 'waw_lam_alef',
        'lines': ['وَلَا تَقْرَبُوا'],
        'why': 'fatha between lam and alef inside the lam-alef ligature',
    },
]


def reference(item: dict) -> str:
    return '\n'.join(item['lines'])
