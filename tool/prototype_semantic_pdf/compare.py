"""Strict comparators for the prototype; no normalisation of Arabic."""
from __future__ import annotations

import unicodedata


def codepoints(text: str) -> list[str]:
    return [f'U+{ord(char):04X}' for char in text]


def _continues_text(char: str) -> bool:
    return bool(char) and (unicodedata.category(char)[0] in 'LMN' or char in '\u200c\u200d')


def exact_segment_count(text: str, reference: str) -> int:
    """Whole, delimited occurrences only - a substring inside a word is not a match."""
    if not reference:
        raise ValueError('empty reference')
    count, offset = 0, 0
    while True:
        start = text.find(reference, offset)
        if start < 0:
            return count
        end = start + len(reference)
        left = text[start - 1] if start else ''
        right = text[end] if end < len(text) else ''
        if not _continues_text(left) and not _continues_text(right):
            count += 1
        offset = start + 1


def canonical_lines(text: str) -> list[str]:
    """Line structure only: drop blank lines and trailing spaces, keep order."""
    lines = [line.strip() for line in text.replace('\r\n', '\n').replace('\r', '\n').split('\n')]
    return [line for line in lines if line]


def flat(text: str) -> str:
    """Whitespace-collapsed text: character order and marks stay exact."""
    return ' '.join(text.split())


def judge(extracted: str, reference: str) -> dict:
    """Strict verdict for one item in one engine.

    `flat_match` requires the exact codepoint sequence (whitespace runs
    collapsed to one space). `line_match` additionally requires the same line
    structure. Duplicated suffixes, reordered marks or extra text all fail
    both, because nothing is normalised or sorted.
    """
    reference_lines = canonical_lines(reference)
    extracted_lines = canonical_lines(extracted)
    reference_flat = flat(reference)
    extracted_flat = flat(extracted)
    # Canonical equivalence is reported separately and never counts as a pass:
    # some engines apply NFC (which reorders combining marks), so a non-canonical
    # source can differ from a correct extraction by canonical ordering alone.
    import unicodedata
    nfc_match = (unicodedata.normalize('NFC', extracted_flat)
                 == unicodedata.normalize('NFC', reference_flat))
    return {
        'flat_match': extracted_flat == reference_flat,
        'canonical_equivalent_only': nfc_match and extracted_flat != reference_flat,
        'source_is_nfc': unicodedata.normalize('NFC', reference_flat) == reference_flat,
        'line_match': extracted_lines == reference_lines,
        'exact_segment_count': exact_segment_count(extracted, flat(reference)),
        'extracted_flat': flat(extracted),
        'reference_flat': flat(reference),
        'extracted_codepoints': codepoints(flat(extracted)),
        'reference_codepoints': codepoints(flat(reference)),
    }
