# Semantic PDF text encoding — isolated prototype

**Prototype only. Nothing here is imported by the application, and no production
file is touched by this directory.** It exists to answer one question with
measurements instead of reasoning:

> Can a PDF encoding keep the **visual glyph order** untouched (identical ink,
> identical positions, identical fonts) while making the four extractors return
> the **exact logical Arabic source**?

The answer recorded by this prototype is **no**, with the evidence in
`docs/review/pr48_semantic_pdf_encoding.md`. This README documents how to
reproduce every number in that report.

## What it does

1. Reproduces the shipped Naskh pipeline outside Dart (`shaping.py`):
   contextual shaping to Unicode presentation forms, UAX #9 reordering at
   paragraph level 1, one CID per visual glyph, `/ToUnicode` derived from the
   glyph — the same semantics as `third_party/pdf/.../bidi_utils.dart::
   shapeRtlRun` and `lib/pdf_engine/canonical_text.dart::shapedRun`.
2. Adds the link the production encoder does not have: every shaped glyph keeps
   the **source segment** it renders (`align_source`). Concatenating those
   segments in logical order reproduces the source word byte for byte, including
   a mark written *inside* a lam-alef ligature.
3. Writes a minimal, valid Type0/Identity-H PDF with a per-(glyph, payload) CID
   allocation (`pdfwriter.py`), exactly like `PdfTtfFont._cidForPair`, so ink is
   identical across strategies by construction.
4. Emits each encoding strategy (`strategies.py`), extracts with the four
   pinned engines and renders every page to PNG (`run_prototype.py`).

## Run

```sh
pip install pymupdf==2.0 pypdfium2==5.14.0 pdfminer.six==20260107 \
            pypdf==6.21.4 arabic-reshaper==3.0.1 python-bidi==0.6.12 fonttools

python3 tool/prototype_semantic_pdf/run_prototype.py --out /path/to/artifacts
python3 tool/prototype_semantic_pdf/probe_engine_model.py --out /path/to/artifacts/engine-model
python3 tool/prototype_semantic_pdf/probe_mechanisms.py --out /path/to/artifacts/mechanisms
python3 -m unittest tool/test_prototype_semantic_pdf.py
```

Artifacts (`--out`) are deliberately **not** committed: one PDF per strategy,
per-page PNGs, raw extraction per engine and `report.json` with every SHA256.
`docs/review/pr48_semantic_pdf_evidence.json` holds the committed summary.

## Files

| file | role |
|---|---|
| `shaping.py` | presentation-form shaping, UAX #9 order, source-segment alignment |
| `pdfwriter.py` | minimal Type0 PDF writer, CID allocation, `/ToUnicode`, `/W` |
| `strategies.py` | the encoding strategies under test (all ink-invariant) |
| `corpus.py` | the representative corpus and its exact logical references |
| `compare.py` | strict comparator: no normalisation, no substring acceptance |
| `outline.py` | glyph→path emission, used only by the outlined-mark experiments |
| `run_prototype.py` | driver: PDFs, extraction, PNG/SHA, matrix |
| `probe_engine_model.py` | proves each extractor's ordering policy (P1–P7) |
| `probe_mechanisms.py` | proves ActualText / invisible / artifact / empty-CID behaviour |

## Strategies

| name | stream order | payload | extra mechanism |
|---|---|---|---|
| `visual_legacy_payload` | visual | decomposed, ligature letters reversed | — (shipped behaviour) |
| `visual_logical_payload` | visual | decomposed, logical | — |
| `visual_segment_payload` | visual | exact source segment, visual order | — |
| `logical_segment_payload` | logical (`Tm` per glyph) | exact source segment | — |
| `logical_decomposed` | logical | decomposed | — |
| `logical_segment_actual` | logical | exact source segment | word `/ActualText` |
| `visual_segment_actual` | visual | exact source segment | word `/ActualText` |
| `visual_segment_outlined_marks` | visual | exact source segment | ligature-owned marks drawn as outlines |
| `visual_cluster_outlined_marks` | visual | per-cluster payload | every mark drawn as outline |
| `word_payload_single_cid` | visual | whole word on the first CID | — |
| `visual_plus_invisible` | visual | unmapped visible glyphs | invisible logical layer |

"swallowed" marks (a combining mark whose character is already inside a
ligature's source segment) are the only glyphs that need an empty `/ToUnicode`
entry; every engine was measured emitting `(cid:N)` or a raw control byte for
those, which is why the outlined-mark variant exists.
