"""Research corpus for the strict Option-A acceptance target.

Every item carries the exact logical source, its code points, the NFC form and
the expected logical extraction. Nothing is normalised away: the comparison uses
the raw source (see `compare.judge`), so a reordered mark or a lost diacritic is
a failure.

The corpus follows the case list required by the brief: unvocalised, vocalised,
multi-mark, tanwin, shadda+mark, lam-alef, marks inside a ligature span, words
that start/end with compound marks, mixed AR/EN, Arabic-Indic and Western
digits, punctuation, repeated spaces, multiple lines, wrapped lines, long text,
equations, special symbols, OPTEND and the B109 branch tail.
"""
from __future__ import annotations

import unicodedata
from typing import Any

CORPUS: list[dict[str, Any]] = [
    {
        'id': 'plain_arabic',
        'case': 'عربية غير مشكّلة',
        'lines': ['نص عربي طويل'],
    },
    {
        'id': 'vocalised_word',
        'case': 'عربية مشكّلة (بيان الاختبار الأصلي)',
        'lines': ['سَلَامٌ'],
    },
    {
        'id': 'multi_mark',
        'case': 'حركات متعددة على حرف واحد',
        'lines': ['مُحَمَّدٌ'],
    },
    {
        'id': 'tanwin',
        'case': 'التنوين',
        'lines': ['كِتَابٌ قَلَمًا عِلْمٍ'],
    },
    {
        'id': 'shadda_fatha',
        'case': 'الشدة مع الحركات',
        'lines': ['إِنَّ اللَّهَ رَبِّي'],
    },
    {
        'id': 'lam_alef',
        'case': 'لام ألف',
        'lines': ['وَلَا تَقْرَبُوا'],
    },
    {
        'id': 'mark_in_ligature',
        'case': 'علامة داخل امتداد ligature (فتحة بين لام وألف)',
        'lines': ['سَلَامٌ وَلَا'],
    },
    {
        'id': 'compound_edges',
        'case': 'كلمة تبدأ/تنتهي بعلامة مركبة',
        'lines': ['ّللْعَالَمِينَّ'],
    },
    {
        'id': 'mixed',
        'case': 'عربي وإنجليزي مختلط',
        'lines': ['نص عربي English 123'],
    },
    {
        'id': 'digits_arabic',
        'case': 'أرقام هندية (عربية)',
        'lines': ['(٢٠ درجة) ٤٥٦'],
    },
    {
        'id': 'digits_western',
        'case': 'أرقام غربية',
        'lines': ['سؤال 12 من 40'],
    },
    {
        'id': 'punctuation',
        'case': 'علامات ترقيم',
        'lines': ['قال: «هذا نص»؛ ثم انتهى.'],
    },
    {
        'id': 'double_spaces',
        'case': 'مسافات متكررة (مسافتان بين الكلمات)',
        'lines': ['نص  عربي   طويل'],
    },
    {
        'id': 'two_lines',
        'case': 'أسطر متعددة',
        'lines': ['السطر الأول', 'السطر الثاني'],
    },
    {
        'id': 'wrapped',
        'case': 'التفاف الأسطر (سطر منطقي واحد على سطرين بصريين)',
        'lines': ['هَذِهِ جُمْلَةٌ طَوِيلَةٌ جِدًّا', 'لِاخْتِبَارِ الِاسْتِخْرَاجِ'],
    },
    {
        'id': 'long_text',
        'case': 'نص طويل',
        'lines': [
            'هَذِهِ جُمْلَةٌ عَرَبِيَّةٌ طَوِيلَةٌ جِدًّا لِاخْتِبَارِ الِاسْتِخْرَاجِ',
            'مِنْ مَلَفَّاتِ الـ PDF الْمُنْتَجَةِ دَاخِلَ التَّطْبِيقِ.',
        ],
    },
    {
        'id': 'equation',
        'case': 'معادلات رياضية',
        # The Arabic face has no U+00B2 glyph; the app falls back to another
        # face for it, which is out of scope for a single-face research harness.
        'lines': ['٣ + ٤ = ٧', 'x2 + 2x + 1 = 0'],
    },
    {
        'id': 'special_symbols',
        'case': 'رموز خاصة',
        # U+25CA/U+25A0/U+2192/U+21E7 are not in the Arabic face (production
        # falls back); the item keeps symbols the face does cover.
        'lines': ['• § © @ # *'],
    },
    {
        'id': 'optend',
        'case': 'OPTEND',
        'lines': ['OPTEND نهاية الخيار'],
    },
    {
        'id': 'b109',
        'case': 'B109',
        'lines': ['B109 السؤال الحادي عشر'],
    },
]


def reference(item: dict[str, Any]) -> str:
    return '\n'.join(item['lines'])


def codepoints(text: str) -> str:
    return ' '.join(f'U+{ord(char):04X}' for char in text)


def describe(item: dict[str, Any]) -> dict[str, Any]:
    source = reference(item)
    return {
        'id': item['id'],
        'case': item['case'],
        'source': source,
        'codePoints': codepoints(source),
        'nfc': unicodedata.normalize('NFC', source),
        'isNfc': unicodedata.normalize('NFC', source) == source,
        'expectedLogical': source,
    }
