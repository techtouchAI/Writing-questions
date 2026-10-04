# Master export-pipeline audit — P0 + P1 + P2

Scope: the whole printed-output system of the app — Preview, vector PDF, editable
DOCX, Exact PDF/DOCX, canonical layout, BiDi, NBSP, math, pagination, visual
regression, CI, Android release, backward compatibility.

Method: repository inspection, byte-level CI evidence (check-run annotations of
the GitHub Actions run for `c1d74f2`, the P0 gate output, and the visual-parity
job), plus the code paths themselves. Nothing here is marked PASS because code
exists; every PASS names the measured evidence. Statuses used:
`PASS` / `PARTIAL` / `FAIL` / `MISSING` / `NOT VERIFIED`.

Baseline and evidence sources

| Item | Value |
|---|---|
| P1 merge (semantic/DocumentIR) | `d392018c60d8c38b4aafabd8e16287a07f9310aa` — "P1: unify preview and exports through DocumentIR" (18 files, +3316/−507) |
| P2 merge (canonical layout) | `c1d74f2d859e9569a55203ad7da3ae27f60889e3` — PR #36, 27 files, +6365/−602 |
| CI run inspected on the baseline | `37202705105` (`main` @ `c1d74f2`): Analyze+test+APK **success**, Visual regression **success**, release-attach *skipped* (tag-only) |
| Test count reported by CI | **607 tests passed**, 0 failed, 0 skipped |
| P0 gate matrix (60 cells) | `PASS=32 FAIL=0 DEFERRED_TO_P1=25 NOT_APPLICABLE=3 UNMEASURED=0` |
| Visual parity on the baseline | PDF p1–p3 RMSE **0** (cap 0.02); Word embedded pixels **byte-identical**; Word rendered RMSE 0.05891 / 0.0685479 / 0.0611121 (cap 0.12) |
| Artifacts / job logs | **not downloadable from this environment** (blob storage unreachable); evidence is read from check-run annotations and the run/job API |

## Architecture as implemented

```
Semantic layer (ExamDocument + ExamBlueprint)
        │
        ▼
DocumentIR  (lib/layout/document_ir.dart — semantic only, no geometry)
        │
        ├── CanonicalLayoutService.resolve
        │        ExamDocumentLayoutAdapter.configurationFor  (policy + float inputs)
        │        LayoutEngine.layout  →  LayoutDocument      (page/line/run geometry)
        │            ▲ second pass with LayoutMathMetricsResolver when math snapshots exist
        │        │
        │        ├── Preview:  CanonicalLayoutPreviewPage (CustomPainter, pt geometry, no re-layout)
        │        └── PDF:      CanonicalLayoutPdfPainter via PaginatedPdfExamEngine
        │                      (same LayoutDocument object may be injected by the preview)
        │
        ├── LegacyDocxAdapter → LegacyBlueprintProjection (string-shaped blueprint)
        │        └── DocxDocumentExportService._DocxBuilder
        │               PageBreakReason plan from canonical questionPageAssignments
        │               (falls back to PaginationEngine inputs; validated against it)
        │
        └── ExactExportService  (independent path: page snapshots into PDF/DOCX, not editable)
```

DOCX note (`lib/services/docx_document_export_service.dart`): the editable file
is the P1 legacy path — it keeps the Word-editable run/OMML/table structures and
receives the *scalar* page plan from the canonical layer; it never consumes
absolute PDF coordinates. The header is printed as a table at the top of the body
(`_buildHeaderTable`, line 401) and a `word/header1.xml` part is built only for
the page-frame image case (`pageBorder` + frame bytes, line 431).

## Matrix

Legend: **Path columns** are the four measured passes of the P0 gate
(Preview / VectorPDF / EditableDOCX / Exact).

### P0 — export truth gates

| Area | Requirement | Current State | Evidence | Missing | Action | Test |
|---|---|---|---|---|---|---|
| P0 gate | 15 features × 4 paths measured, no cell unmeasured | PARTIAL — 32 PASS / 0 FAIL / 25 DEFERRED / 3 N/A / 0 UNMEASURED | CI annotation "P0 gate — matrix (60 cells)" + `matrix.txt` artifact | 25 cells carry named deferrals | keep deferrals truthful; this audit re-verified the one FAIL-level claim (see F1) | `test/export_gate/p0_export_gate_test.dart` (GATE-00…99) |
| PDF export | vector PDF from canonical geometry, no second layout engine | PASS | `paginated_pdf_exam_engine.dart` paints `LayoutDocument`; canonical-vs-PDF token deltas ≈ 0.000pt in the gate annotation | — | — | GATE-02/03/05 |
| DOCX export | editable DOCX from the P1 legacy path | PASS (structure) | parts/rels/`w:t` order/OMML/`w:ind`/`sectPr` checks in GATE-04…07 | float anchoring & OMML direction deferrals (F6) | tracked, not weakened | GATE-04…08 |
| RTL / Arabic | logical order, shaping, no Latin-digit leak | PASS | GATE-02/03 order + Arabic presentation forms checks; PDF RMSE 0 vs preview | — | — | GATE-02/03, visual parity |
| English / mixed | LTR paper and mixed runs | PASS for VectorPDF+EditableDOCX; Preview DEFERRED on the parts that the widget tree does not expose as paragraphs | GATE-11 records LTR order/paragraph rules; `ltr-document/preview` deferred | preview-tree measurement (F3) | — | GATE-11 |
| Numbers / punctuation | digits never mirrored, separators keep position | PASS (VectorPDF/EditableDOCX) | GATE-03/04 number & separator positions; NOT_APPLICABLE for Preview/Exact where the probe has no semantic tokens | — | — | GATE-03/04 |
| Quran | Amiri flow on every printed surface | PASS (Preview/VectorPDF/EditableDOCX) | GATE-05/06 Quran run fonts; canonical Quran token map annotation | — | — | GATE-05/06 |
| Math | OMML/raster, baseline, spacing | PARTIAL — EditableDOCX + Exact deferred (RTL inside OMML) | GATE-05/06 math counts and texts; `math/editableDocx` reason names the OMML direction decision | OMML run direction | tracked (F6) | GATE-05/06 |
| Page assignment | deterministic, question not split by the *layout* layer | PASS (VectorPDF/EditableDOCX/Exact); VectorPDF deferred for the interactive-preview vs PDF page-count delta | GATE-02/06 page counts; `pagination/vectorPdf` records the measured delta | interactive preview uses measured widget heights (F3) | canonical path is the single source for exports | GATE-02/06, `canonical_nbsp_page_assignment_test.dart` |
| Word spacing / justification | single-line paragraphs are not stretched | PASS on the rule; the per-line distribution source is deferred | GATE-05 + GATE-10 measurements; `justification/vectorPdf` deferred | per-line justification unification (F3) | — | GATE-05/10 |
| Floating elements | authored geometry preserved | PARTIAL — deferred on EditableDOCX/Exact | GATE-06 records `r:embed` + no `wp:anchor` | Word anchoring policy | tracked (F6) | GATE-06 |
| Header / footer | fields reach the printed surface | PASS (fields present); DEFERRED for the Word header-part structure | **corrected measurement** (F1): all five header fields are in `document.xml` with their localized digits; no `word/header*.xml` because the header is a first-page body block | once-vs-repeat decision for a real Word header part (F2) | gate fixed to measure the localized forms; deferral reason corrected | GATE-06/99 |
| Branches / options | branch and option content ordered and attributed | PASS | GATE-04/06/09 sequence checks | — | — | GATE-09 |
| Multi-page documents | page plan identical across passes | PASS | GATE-02 (PDF pages) vs GATE-06 (`pageBreakCount+1`) equality | — | — | GATE-02/06 |
| Visual regression | rendered files vs preview snapshots | PASS | RMSE 0 (PDF) / 0.059–0.069 (Word render), embedded pixels byte-identical (see Visual section) | more content fixtures (F5) | — | `test/visual/visual_parity_fixture_test.dart` + `tool/verify_visual_parity.sh` |

### P1 — semantic pipeline

| Area | Requirement | Current State | Evidence | Missing | Action | Test |
|---|---|---|---|---|---|---|
| DocumentIR | single semantic source for Preview/PDF/DOCX | PASS — `DocumentIR.fromBlueprint` is the only constructor used by the canonical service, the PDF facade and the DOCX builder | `canonical_layout_service.dart`, `_DocxBuilder` factory (`docx_document_export_service.dart:333`) | — | — | `test/layout/document_ir_test.dart` |
| Semantic blocks / inline elements | numbers, separators, marks, labels stay distinct | PASS — `NumberNode/SeparatorNode/LabelNode`, `InlineContent` | `lib/layout/semantic/inline_nodes.dart` | — | — | `document_ir_test.dart` |
| Direction model | rtl / ltr / auto / inherit carried in IR | PASS | `DocumentDirection`, per-node direction, `_bidiDirectionFor` | — | — | `document_ir_test.dart`, `flutter_text_metrics_test.dart` |
| Header / footer / attachments / floats in IR | referenced without embedding geometry | PASS | `HeaderBlock`, `FooterBlock`, `FloatingElementReference` | — | — | `document_ir_test.dart` |
| DocumentIR → Preview | preview consumes IR | PARTIAL — exact-capture/review preview paints the canonical `LayoutDocument`; the interactive editor still measures widgets (F3) | `exam_preview_screen.dart:216/2007/2560/3319`; `_buildPage`+`MeasureSize` path retained | full interactive migration | documented, not hidden | `preview_export_visual_parity_test.dart`, GATE-00/01 |
| DocumentIR → PDF adapter | PDF paints IR-derived geometry | PASS | `PaginatedPdfExamEngine` + `CanonicalLayoutPdfPainter` | — | — | GATE-02/03/05 |
| DocumentIR → DOCX adapter | legacy projection only at the boundary | PASS | `LegacyDocxAdapter` → `LegacyBlueprintProjection.build` | — | — | GATE-04/06 |

### P2 — canonical layout

| Area | Requirement | Current State | Evidence | Missing | Action | Test |
|---|---|---|---|---|---|---|
| Canonical service | DocumentIR → one layout decision | PASS | `CanonicalLayoutService.resolve` (+ math second pass) | — | — | GATE-01, `flutter_text_metrics_test.dart` |
| LayoutDocument / Page / Element / Run | page, bounds, line, run, baseline, ascent, descent, spacing, alignment, direction, source offset, page ownership | PASS | `layout_document.dart` fields; run ids carry semantic path + offsets | — | — | `document_ir_test.dart`, canonical tests |
| Math geometry | math box owned by canonical layout | PASS | `LayoutMathBox`, `layout_math_metrics_resolver.dart`; PDF consumes `mathRasters` keyed by run | — | — | GATE-05 |
| Image / float geometry | authored float geometry resolved by the adapter, page-owned | PASS (canonical), PARTIAL in DOCX (F6) | `_placeFloatingElements`, `FloatingLayoutInput` | Word anchoring | tracked | GATE-06 |
| Preview painter | draws `LayoutDocument` without re-layout | PASS for the canonical painter (used by Exact capture and review); interactive editor path separate (F3) | `canonical_layout_preview.dart` paints run x/baseline; `_paintText` is a painter, not a breaker | interactive migration | documented | GATE-01/10 |
| PDF painter | draws `LayoutDocument` without re-layout | PASS | `canonical_layout_pdf_painter.dart`; gate asserts pdf≈canonical deltas ≈ 0 | — | — | GATE-02/03/05 |
| Pagination determinism | one-page, multi-page, boundary, branch/option, header/footer, float, math, Arabic/mixed | PARTIAL — canonical pagination covered by the gate and the new NBSP test; the interactive preview keeps `PaginationEngine` measured heights | GATE-02/06, `canonical_nbsp_page_assignment_test.dart` | interactive-path unification (F3) | — | GATE-02/06, NBSP tests |
| NBSP | non-breaking in measurement, line breaking, page assignment | PASS (implementation) + **new test added** | `_isNonbreakingSpace`/`_isJustifiableSpace` in `flutter_text_metrics.dart`; `canonical_nbsp_page_assignment_test.dart` | — | — | `canonical_nbsp_page_assignment_test.dart` |
| BiDi | logical vs visual order, run splitting, word boundaries | PASS | canonical run `logicalIndex`/`visualIndex`, fragment directional splitting, gate order checks | — | — | GATE-02/03/11 |
| Performance | layout computed once, shared by painters | PASS for the export preview→PDF handoff (`layoutDocument:` parameter); the interactive editor resolves its own canonical layout only for capture | `paginated_pdf_exam_engine.generate(layoutDocument:)`; `exam_preview_screen.dart:2560–2673` | — | — | code + GATE-01 timing stage |

### DOCX / Exact

| Area | Requirement | Current State | Evidence | Missing | Action | Test |
|---|---|---|---|---|---|---|
| Editable DOCX | Word-editable, legacy path | PASS | parts/rels/run properties/OMML | — | — | GATE-04…08 |
| Page assignments | validated against the canonical plan | PASS | `GATE-06` asserts `pageBreakCount + 1 == PDF pageCount`; engine rejects assignments that do not fit or do not match the question order (`_paginateUsingAssignedPages`) | — | — | GATE-06 |
| Exact DOCX/PDF | snapshot path, not editable | PASS | exact files contain no selectable text (asserted) | — | — | GATE-01B/06 |
| Direct/service/library export | three call sites | PASS | `DocxDocumentExportService` static API + `ExportFileService` | — | — | `export_file_service_test.dart`, `structured_export_test.dart` |
| Student paper / floating / OMML / images / RTL / multi-page | measured in the gate | PARTIAL (floats/OMML RTL deferred) | GATE-06 evidence strings | anchoring + OMML direction | tracked (F6) | GATE-06 |

### CI / Android / compatibility

| Area | Requirement | Current State | Evidence | Missing | Action | Test |
|---|---|---|---|---|---|---|
| CI | analyze `--fatal-infos`, tests, gate, visual parity, APK on every push | PASS | baseline run 37202705105 | `test/**` is excluded from analysis by a temporary comment in `analysis_options.yaml` (F5) | decide: re-enable and fix lints | workflow file |
| Android release | `flutter build apk --release` artifact | PASS on baseline | job "Analyze, test, and build APK" success; `writing-questions-release-apk` uploaded | — | — | workflow |
| Backward compatibility | existing documents/exports unchanged | PASS per gate cells (options/marks/RTL/LTR/multi-page) | GATE-02…11 | — | — | documented tests |
| third_party/pdf | vendored patch preserved | PASS | workflow step `verify_vendored_pdf_patch.dart` in the baseline run | — | — | tool script |

## Findings of this audit

### F1 — The "DOCX header regression" was a measurement artifact (fixed here)

The gate published, on every run, an `::error` annotation claiming a *real
product regression*: "header fields HDRV/HDC1/HDC2/HDG1/HDT1 do not reach
`word/header*.xml`, and four of them do not appear in `document.xml` at all".

Measured root cause: the header values pass through
`ExamDocument.localizeDigits` before they are written to any part (the fixture
uses `PaperNumerals.auto` with the Islamic-education template, i.e. Arabic-Indic
digits), so the fixture marker `HDC1` is written as `HDC١`. A raw `contains`
search for `HDC1` can therefore never succeed — the *text* is present, the
non-localized marker string is not. Byte evidence (temporary CI probe, removed):
the first paragraphs of `editable.docx` for `P0GateFixture.rtl()` read
`… نصف السنةHDC١`, `… HDC٢ ٢٠٢٦/٢٠٢٧`, `… HDG١`, `… HDT١`, and the raw probe result
was `HDC1:raw=false:flat=false` next to `HDRV:raw=true:flat=true`.

Action taken (P0 gate, no product change was warranted):
* `GATE-06` now measures every header field in both its raw and localized form
  and **fails the gate** if a field is absent in both — a real absence is no
  longer tolerated.
* The recorded cell stays `DEFERRED_TO_P1`, but for the *structural* reason that
  remains true (no `word/header*.xml` part exists because the header is a
  first-page body block; see F2), and its reason names
  `docx_document_export_service.dart:431` as the condition.
* `GATE-99` now also requires the registration to name the localized forms and
  requires the cell status to match the measured header-part structure
  (PASS once a part carries all five fields, `DEFERRED_TO_P1` while none does).

### F2 — Editable DOCX header lives in the body, not in a Word header part

`body.write(_buildHeaderTable())` (line 401) puts the header table at the top of
`document.xml`; `word/header1.xml` is built only when `pageBorder` is set *and* a
frame image exists (line 431), and that part contains the frame picture only.
Consequence: Word never sees the header as a header; it prints it once as body
content (which is exactly what Preview and the vector PDF do — header once on
page 1, footer once on the last page — and why the visual parity job measures
RMSE 0.059–0.069 against the preview). Turning it into a real Word header part
forces a decision the project has not yet made (does the header repeat on every
page?) and changes page-1 body capacity, i.e. the page heights the paginator
accounts for. It is therefore recorded as a deferral with a named reason instead
of being silently changed — and the false "missing fields" claim around it was
removed (F1).

### F3 — The interactive editor preview is not (yet) a `LayoutDocument` painter

The canonical preview surface (`CanonicalLayoutPreviewPage`) is used by the
Exact capture/review flow, and the PDF export consumes the *same* `LayoutDocument`
object (`generate(layoutDocument:)`). The interactive editing surface still
paints widget-built pages whose heights are measured through `MeasureSize` and
fed to `ExamWizardController.reportBlockHeight`/`PaginationEngine`. The direct
consequence is visible in the gate: `pagination/vectorPdf` is deferred because
the *interactive preview* page count and the PDF page count are produced by two
different height sources. The exported artifacts (PDF, DOCX, Exact) are all on
the canonical plan and agree with each other.

### F4 — 25 of 60 matrix cells are recorded deferrals

They are not failures: each names a reason and the gate fails if a reason is
missing (`GATE-99`). Groups: (a) Exact cells — the Exact files are page images
by design, so text-structure probes report DEFERRED rather than NOT_APPLICABLE;
(b) Preview cells — the interactive widget tree does not expose every semantic
node as a paragraph (F3); (c) product decisions (F2, F6).

### F5 — Gaps that remain (not hidden)

* `analysis_options.yaml` excludes `test/**` with a "TEMPORARY (removed before
  the final commit)" comment; that exclusion is still present.
* Visual regression runs on one fixture document (three pages); content-level
  coverage of the 18 cases listed in the request is spread across the P0 gate
  probes and the canonical/metrics tests rather than one image suite.
* The gate prints its full matrix as a CI notice but the per-cell *evidence*
  strings live in `matrix.txt`/`summary.txt` artifacts.

### F6 — DOCX deferrals that are product-level

* Floating elements are written into the paragraph flow without `wp:anchor`, so
  Word cannot pin them to the authored position (`floating/editableDocx`).
* OMML runs carry no direction declaration, so Arabic inside a formula is left
  to Word's maths default (`math/editableDocx`).
Both are recorded with reasons; neither is weakened by this audit.

## Verification performed for this change set

* Local: **no Flutter/Dart toolchain in this environment** (and the SDK hosts are
  unreachable), so nothing is claimed as locally verified.
* CI on the audit branch: analyzer, full test suite, P0 gate, visual parity and
  the release APK build must be green on the final SHA — results are recorded in
  the pull request and in the final report accompanying this document.
* Added test: `test/layout/canonical/canonical_nbsp_page_assignment_test.dart`
  (NBSP measurement, line breaking across a width sweep, page assignment across
  four page heights with a split question).
* Changed gate: `P0GateFixture.headerMarkers` are now matched in their raw *and*
  digit-localized forms; a genuinely missing field fails `GATE-06`.
