# Master export-pipeline audit — P0 + P1 + P2

## Baseline independent audit (2026-10-05; clean `main` snapshot before local edits)

This source-and-CI audit checked the clean baseline at `3762bba9c6414747c1ce24b6d9765be321cee221`; the older report below was treated as a lead, not accepted without source, test, merge, and Actions evidence. The session ordering constraint was subsequently breached: implementation edits began before the full requirement matrix and implementation plan were complete. The current dirty-worktree audit and matrix below record that fact and keep every unverified change explicitly unverified; no current-diff result is inferred from baseline CI.

### Repository and GitHub facts

| Fact | Observed evidence |
|---|---|
| Work branch | `arena/01a10a27-writing-questions` (the required session branch) |
| Initial working tree | clean; `git diff`, `git diff --stat`, and `git diff --check` were empty |
| Initial committed/local-only changes | none on the session branch; it pointed at the same `3762bba9c6414747c1ce24b6d9765be321cee221` as `main`/`origin/main` |
| Current session branch on origin | absent; `git ls-remote --heads origin arena/01a10a27-writing-questions` returned no ref, and `gh pr list --head arena/01a10a27-writing-questions` returned `[]` |
| P1 / PR #35 | merged; PR head `a406cae3cd948749351e33aac5c8c170df920855`, merge commit `d392018c60d8c38b4aafabd8e16287a07f9310aa` |
| P2 / PR #36 | already merged (not an open/current PR); PR head `783a0e6fc54c2f7d6d766ad6749997d2decff816`, base P1 merge `d392018c60d8c38b4aafabd8e16287a07f9310aa`, merge commit `c1d74f2d859e9569a55203ad7da3ae27f60889e3` |
| Newer audit / PR #37 | merged; its merge is current `main` SHA `3762bba9c6414747c1ce24b6d9765be321cee221` |
| History availability | checkout was initially shallow; `git fetch --unshallow origin main` made the P1/P2 ancestry inspectable without changing the worktree or branch |
| Local Flutter/Dart/Java | unavailable (`command -v flutter`, `dart`, and `java` found none); no local Flutter command is claimed as run |
| Current-SHA Actions run | run `37238515598`, `main` at `3762bba9c6414747c1ce24b6d9765be321cee221`, completed `success`; Analyze/test/APK job and Visual Regression job succeeded; release attachment was `skipped` because it is tag-only |
| Current-SHA test count | Check annotation on run `37238515598`: **610 tests passed**. The test tree has no configured `skip:`/`@Skip`/`markTestSkipped`; recorded as 610 total, 610 passed, 0 failed, 0 skipped |
| Current-SHA P0 gate | Check annotations: 60 cells, `PASS=32 FAIL=0 DEFERRED_TO_P1=25 NOT_APPLICABLE=3 UNMEASURED=0` |
| Current-SHA P0 annotation severity | The check API also returns one `failure`-level annotation for the explicitly `DEFERRED_TO_P1` editable-DOCX header-part cell; the run and job are still `success`. Record it as a surfaced structural deferral, not a passing cell or a test failure |
| Current-SHA visual measurements | Exact-export comparison annotation: 794×1123 pages; Exact PDF RMSE `0, 0, 0` (cap `0.02`); embedded Exact Word page images byte-identical; LibreOffice render of Exact Word RMSE `0.05891, 0.0685479, 0.0611121` (cap `0.12`). These are not vector-PDF or editable-DOCX visual metrics |
| Current-SHA Android artifact | build step succeeded and artifact metadata reports `writing-questions-release-apk`, 28,510,269 bytes; archive contents could not be downloaded from the Actions blob store in this environment (`EOF`) |
| Current-SHA analyzer/build | the corresponding Analyze, test, and build APK job is completed `success`; its Analyze, Run tests, Build release APK, and Upload APK artifact steps are all completed `success` |
| Current-SHA workflow warning | the check annotations contain a non-blocking Node.js 20 deprecation warning; an upload-artifact action is forced to Node.js 24. No workflow change was made in this patchset |

The job/artifact APIs and check-run annotations were readable, but Actions log
and artifact downloads from `results-receiver.actions.githubusercontent.com`
and Azure blob storage returned `EOF`. Therefore, numeric evidence above is
limited to data actually published in the Check API; this is not represented as
a local build or a downloaded-artifact inspection.

### Baseline architecture at `3762bba9`

```
ExamDocument / ExamBlueprint
          ↓
     DocumentIR                 semantic source (P1)
       ├─ CanonicalLayoutService → LayoutEngine → LayoutDocument
       │                                  ├─ CanonicalLayoutPdfPainter → vector PDF
       │                                  └─ CanonicalLayoutPreviewPage → exact-capture/read-only path
       └─ LegacyDocxAdapter → LegacyBlueprintProjection → editable DOCX builder

Editable DOCX intended compatibility pagination:
  LegacyDocxAdapter → PaginationEngine → explicit Word page breaks

Exact PDF/DOCX:
  captured page snapshots → ExactExportService → image-only documents (not editable)
```

Important distinction at the audited baseline: the normal interactive
`ExamPreviewScreen` still renders its widget tree and reports measured heights
to `ExamWizardController`/`PaginationEngine`; the canonical preview painter is
used for Exact snapshots and review, not as the regular interactive page
renderer. Vector PDF paints `LayoutDocument` directly. At baseline, editable-DOCX
page planning did **not** use the intended compatibility path: it accepted a
complete ID set without checking order or the legacy paginator, and otherwise
asked `PaginatedPdfExamEngine.resolveQuestionPages` for canonical assignments.
The local diff now attempts to fix this; its state is assessed separately below
and is not considered verified.

### Baseline requirement matrix (clean `main` before local implementation edits)

This table is a dated baseline snapshot, not the current worktree status. Its
historic `ALREADY PASS` labels refer only to baseline source plus the cited
`main`-SHA evidence. The current status uses the required `PASS`, `PARTIAL`,
`FAIL`, `MISSING`, and `NOT VERIFIED` values in the worktree matrix below.

| Area | Requirement | Current State | Evidence | Missing | Action | Test |
|---|---|---|---|---|---|---|
| P0 gate | All required export properties measured; no hidden or softened failures | PARTIAL | Current SHA run `37238515598`, 60-cell notice: `32 PASS / 0 FAIL / 25 DEFERRED / 3 N/A / 0 UNMEASURED` | 25 named deferrals and 3 N/A cells remain; 0 FAIL does not mean all requirements passed | Keep each deferral explicit; close product gaps only with an asserting test; do not adjust thresholds | `test/export_gate/p0_export_gate_test.dart`, GATE-00…99 |
| P0 / PDF | Vector export uses canonical page/line/run geometry; RTL gap, Quran spacing, punctuation and PDF structure | PARTIAL — canonical painting is present and measured; preview/PDF pagination parity is not | `PaginatedPdfExamEngine.generate` supplies `LayoutDocument` to `CanonicalLayoutPdfPainter`; current gate summary measures Arabic PDF 4 pages vs preview 5, English PDF 3 vs preview 4; canonical title/Quran gap annotations are present | Interactive Preview still has independent measured widget heights; no vector-PDF raster comparison in the Visual Regression job | Keep PDF paint-only; migrate or explicitly bridge Preview; preserve AUD-PDF-02/P0-GATE-03 assertions | GATE-02/03/04/05, `test/pdf_engine/*`, visual job |
| P0 / DOCX | Editable file contains semantic text, options/branches, images and OMML; correct document/page structure | PARTIAL | `ooxml_probe.dart`, current gate GATE-04…08; DOCX tests; CI suite passes | Header is a first-page body table rather than a Word header part; floating formulas are intentionally written in text flow; pagination plan currently comes from canonical layout | Keep Editable distinct from Exact; correct pagination source/validation and retain named header/math limitations until proven fixed | GATE-06…08, `docx_student_paper_test.dart`, `docx_floating_elements_test.dart`, `docx_math_export_test.dart` |
| P0 / Exact | Exact exports are independent page-image documents, not editable documents | ALREADY PASS (structure) | Exact export service and current tests assert image-only output; current visual job proves embedded Word media byte-identical to preview snapshots | Exact does not prove vector-PDF or editable-DOCX text geometry | Keep Exact as a separate compatibility path; do not count it as structural text coverage | `test/services/exact_export_test.dart`, `test/wizard/export_exact_mode_test.dart` |
| P0 / Arabic, English, mixed text, numbers, punctuation | Logical/visual order, glyph shaping, separators, digits, page geometry | PARTIAL | Current gate has Arabic/English/mixed, numbers and punctuation cells; PDF structure probes and canonical metrics tests; gate summary is green | Preview cells for numerals/punctuation are N/A; all LTR-document cells are deferred; DOCX per-run direction is not derived from each semantic run | Add source-direction-aware adapter coverage without weakening existing geometry limits | GATE-03/07/11, `flutter_text_metrics_test.dart`, export parity tests |
| P0 / Quran | Amiri flow, Quranic word gap and run spacing | ALREADY PASS for measured Preview/VectorPDF/EditableDOCX cells | Current gate and run annotation include Quran title run geometry and canonical/PDF gap evidence; PDF font scan covers Quran content | Exact text properties are not applicable to page-image files; broader visual corpus remains partial | Preserve measured Arabic lexical-gap assertions and font loading behavior | GATE-03/04/09, `paginated_quranic_font_test.dart` |
| P0 / math | Inline/display math, Arabic+math, baseline/spacing, OMML or image fallback | PARTIAL | Canonical `LayoutMathBox` and PDF math raster path exist; current gate counts math runs/images; DOCX OMML tests verify editable equations and that formula runs stay LTR | Arabic `\\text{}` direction inside OMML and DOCX floating-formula geometry remain unverified/deferred; canonical service does a measurement pass then a math-measured layout pass | Retain LTR math token order; add geometry/direction tests before changing OMML behavior | GATE-04/06, `paginated_math_pipeline_test.dart`, `docx_math_export_test.dart`, `docx_math_layout_test.dart` |
| P0 / page assignment | Deterministic one-/multi-page, exact boundary, owned question and body content | PARTIAL | Current canonical layout reports assignments; NBSP page sweep passes on current SHA; gate records 4/5 and 3/4 PDF/interactive-preview page counts | Preview page ownership is not sourced from `LayoutDocument`; Editable DOCX consumes canonical plans rather than validated legacy plans | Use `PaginationEngine` for Editable DOCX and validate every supplied assignment against its actual legacy result | `canonical_nbsp_page_assignment_test.dart`, `pagination_engine_test.dart`, GATE-02/06 |
| P0 / header/footer, branches/options, floating elements | Semantic content and authored ownership/geometry reach outputs | PARTIAL | DocumentIR models these blocks/references; canonical layout has header/footer bounds and `LayoutFloatPlacement`; DOCX/PDF and model tests cover content and image anchors | DOCX first-page body header has no `word/header*.xml`; DOCX formula elements are flow paragraphs; current per-run direction/placement parity is incomplete | Correct only implementation gaps; do not turn a first-page header into a repeating one without a documented product decision | GATE-06/09, header/floating/DOCX tests |
| P1 / DocumentIR | One semantic source for header/footer, question/branch/option/marks, attachments, math and Quran | ALREADY PASS for the semantic model | `lib/layout/document_ir.dart`, `lib/layout/semantic/inline_nodes.dart`; `test/layout/document_ir_test.dart`; PR #35 merge `d392018…` is in current `main` ancestry | Legacy projections can still flatten direction/source metadata at the DOCX boundary | Keep semantics stable; carry missing metadata through adapters without redesigning the IR | `document_ir_test.dart`, `exam_blueprint_test.dart` |
| P1 / adapters | DocumentIR → Preview/PDF/DOCX, preserving RTL/LTR/auto/inherit | PARTIAL | `ExamPreviewScreen` reads controller IR/blueprint; canonical PDF resolves from IR; DOCX uses `LegacyDocxAdapter` | Interactive Preview remains widget layout; DOCX projection serializes semantic nodes to legacy strings and uses document-level RTL/LTR in run properties | Close only proven compatibility gaps; add adapter-level direction tests | GATE-00/07/11, `document_ir_test.dart`, DOCX tests |
| P2 / canonical data model | `LayoutDocument/Page/Block/Line/Run`, point bounds/baseline/ascent/descent, math and float boxes, source offsets/page ownership | PARTIAL | Current layout model exposes pages, blocks, line/run geometry, math boxes, float rectangles and deterministic page ownership | `LayoutRun` has no explicit source-start/source-end fields; IDs/logical index encode fragments indirectly; images are external float resources | Add explicit source offsets while retaining existing IDs and public semantics; test fragment offsets through the final layout model | `layout_document.dart`, `layout_engine.dart`, new canonical geometry regression test |
| P2 / layout & typography | One canonical line breaker/metrics contract for wrapping, alignment, baseline, spacing and NBSP | ALREADY PASS for the export layout path | `FlutterTextMetrics.layoutParagraph` owns canonical wrapping/BiDi/justification; NBSP differential test measures width, line breaking and page assignment; PDF painter has no `Wrap`/pagination | The interactive editor remains another visible layout path; math snapshot resolution currently requires a preliminary layout and a math-measured final layout | Do not add another engine; keep math re-layout explicit or move math measurement before the final geometry pass | `flutter_text_metrics_test.dart`, `canonical_nbsp_page_assignment_test.dart`, GATE-01/10 |
| P2 / Preview | Preview paints `LayoutDocument`, not re-wrap/re-break/re-paginate content | PARTIAL | `CanonicalLayoutPreviewPage` paints point geometry with `TextPainter` only for painting; exact snapshot flow uses it | The regular interactive editor still renders `PaperField`/`TexText`, reports widget heights and uses `PaginationEngine`; its page assignment differs from canonical PDF | Route visible review/print preview through canonical geometry; preserve editor interactions separately and test pointer/edit behavior | `preview_export_visual_parity_test.dart`, `visual_parity_fixture_test.dart`, wizard interaction tests |
| P2 / PDF painter | PDF paints canonical geometry; no renderer-specific wrapping/page assignment | ALREADY PASS for flow geometry | `CanonicalLayoutPdfPainter` positions canonical lines/runs and `PaginatedPdfExamEngine` iterates canonical pages; current P0 gate geometry checks pass | PDF still measures each glyph-run advance for paint-origin mapping, and paints math rasters; this is renderer painting, not line/page layout | Keep any renderer advance mapping confined to painting; add parity assertions if changed | GATE-02/03/05, PDF engine tests |
| DOCX pagination | Editable DOCX must use `LegacyDocxAdapter → PaginationEngine`; supplied assignments must be validated; direct export must derive the legacy plan | FAIL (architecture) | `_resolvedQuestionPages` currently validates only ID membership/uniqueness/completeness, then falls back to `PaginatedPdfExamEngine.resolveQuestionPages`; no call to `PaginationEngine` exists in DOCX service | Neither order nor canonical-vs-legacy assignment is validated; direct DOCX depends on canonical page ownership | Add a DOCX compatibility pagination adapter using `PaginationEngine`, and reject/fallback from any nonmatching supplied assignments | New direct/service/export and invalid-assignment regression tests; keep Exact separate |
| Visual Regression | Pixel render comparison plus geometry assertions across Arabic/English/mixed, digits/punctuation/Quran/NBSP/math, long/page-boundary, header/footer/floats/branches/options/multipage | PARTIAL | Current-SHA visual job has 3-page RMSE/size results; exact Word embedded images are byte-identical; P0 gate and canonical metrics tests provide structural/geometry assertions | Screenshot suite is one composite fixture (not 18 independent visual cases); visual job compares Exact snapshot exports, not vector PDF; no downloaded artifact inspection here | Keep thresholds fixed; broaden geometry/canonical vector-PDF evidence only with a passing root-cause-backed fixture | `test/visual/visual_parity_fixture_test.dart`, `tool/verify_visual_parity.sh`, P0 gate |
| Export/API | PDF bytes/file/service, editable DOCX bytes/file/service, Exact, Preview and wizard flow remain compatible | PARTIAL | Export services and call sites exist; full suite passes on current SHA; Exact mode is separately disclosed | Direct Editable DOCX pagination currently violates the planned source; old saved/export corpus is not available for a full compatibility replay | Preserve public signatures and old formats; add regression coverage for any compatibility fix | `export_file_service_test.dart`, `pdf_export_service_test.dart`, `docx_student_paper_test.dart`, Exact tests |
| Backward compatibility | Old `ExamDocument` saves/exports, Arabic, math, attachments and legacy DOCX remain usable | PARTIAL | Model serialization and existing export tests pass as part of the current 610-test suite | No versioned real-user saved-document corpus or before/after archive comparison in this checkout | Add regression fixtures only for a demonstrated behavioral break; do not alter package/version/storage schemas | model tests, `app_backup_test.dart`, export contract tests |
| CI / Analyze / tests | Fatal-info analysis of source and tests; all test/P0/P1/P2/visual checks on the same SHA | ALREADY PASS for current main SHA | Run `37238515598` on `3762bba…`: Analyze/test/APK and Visual Regression jobs completed success; annotation reports 610 passed | This is baseline evidence only; new implementation requires a new run on its pushed final SHA | Rerun on the eventual final SHA and inspect new check annotations; do not reuse this run as final proof | `.github/workflows/build_apk.yml`, all test suites |
| Android | Release build and actual artifact | ALREADY PASS for current main SHA | Run `37238515598`: Build release APK and Upload APK artifact succeeded; artifact metadata size 28,510,269 bytes | No artifact bytes locally due storage EOF; new SHA needs its own build/artifact | Verify the new SHA's build job, artifact metadata and download if storage becomes available | workflow `Build release APK` / `Upload APK artifact` |
| Git / PR | Work only on the required Arena branch; review current PR/base/head/checks | NOT VERIFIED for new work | Baseline session branch equaled `main`; PR #36 is merged; no session-branch origin ref or open PR | Current worktree is now dirty; no implementation commit/PR exists | Finish audit first, then verify and commit/push only the session branch; open but do not merge a PR | `git status`, `gh pr view`, new-SHA checks |

## Current worktree audit — 2026-10-05 (all code changes NOT VERIFIED)

### Ordering correction

The clean-main baseline report above was written, but implementation edits began
before the full local diff review and final requirement matrix were complete.
That violated the explicit audit-before-implementation constraint. This section
completes the repository, diff, architecture, and status audit for the current
worktree. No product-code change below has been formatted, analyzed, tested, or
run through CI; baseline success is not evidence for this patchset.

**Current verdict: `NOT VERIFIED`.** Do not use `VERIFIED` until all required
implementation gates and tests pass on the final SHA and the matching CI run is
`completed + success`. `READY TO MERGE` additionally requires a mergeable PR with
all required checks green; no PR is merged automatically.

### Git, PR, and worktree facts

| Fact | Current observation |
|---|---|
| Branch / HEAD | `arena/01a10a27-writing-questions`; `HEAD=3762bba9c6414747c1ce24b6d9765be321cee221`, equal to local `main` and `origin/main` |
| Upstream | None configured for the session branch |
| Local commits | None beyond the baseline main commit; all patchset work is uncommitted |
| Staging | No staged changes |
| Worktree | 11 tracked files modified plus one untracked canonical source-offset test; no files deleted or renamed |
| Whitespace check | `git diff --check` returned no diagnostics for tracked changes; a separate `git diff --no-index --check /dev/null <untracked-test>` emitted no whitespace diagnostic (its exit 1 reflects the file difference) |
| Remote session branch | `git ls-remote` found no `arena/01a10a27-writing-questions` ref |
| PR / PR HEAD | `gh pr list --state all --head arena/01a10a27-writing-questions` returned `[]`; there is no current PR HEAD to inspect |
| Main baseline | local `main`, `origin/main`, and `origin/HEAD` all resolve to `3762bba9c6414747c1ce24b6d9765be321cee221` |
| P1/P2 history | PR #35 merged at `d392018c60d8c38b4aafabd8e16287a07f9310aa`; PR #36 merged at `c1d74f2d859e9569a55203ad7da3ae27f60889e3`; PR #37 supplies current `main` |
| SDKs | `flutter`, `dart`, and `java` are unavailable locally; no formatter, analyzer, test, or APK build has been run on this worktree |

### Local change inventory (source of truth: current `git diff`)

| Files | Local change | State / evidence |
|---|---|---|
| `lib/layout/pagination_engine.dart`; `lib/providers/exam_wizard_controller.dart`; `lib/views/wizard/exam_preview_screen.dart` | Add immutable `PaginationInput`, expose the controller's measured blocks/reserve, and pass the interactive legacy plan to Editable Word only after the current `isFullyMeasured` check | Unformatted/unanalysed; footer measurement is not included in `isFullyMeasured` (see findings) |
| `lib/services/docx_document_export_service.dart` | Recompute page groups through `PaginationEngine`; compare candidate groups with its result; build direct-export input from canonical measured block bounds rather than canonical page assignments; preserve semantic `VisualRun`/direction for DOCX text and segment mixed Arabic/Latin runs | Large shared serializer diff; no Word/LibreOffice render or unit test has run |
| `lib/layout/adapters/legacy_blueprint_projection.dart` | Project question/category/body/title/point/option nodes through semantic blueprint constructors instead of flattening them to legacy strings | Direction/inline metadata is retained by design; adapter test edits exist but are unrun |
| `lib/layout/canonical/layout_document.dart`; `lib/layout/canonical/layout_engine.dart` | Add exclusive UTF-16 source offsets to `LayoutRun`, populate from measured fragments, and preserve through scale/move copies | New fields and untracked test are unverified |
| `test/export_gate/p0_export_gate_test.dart` | Capture the actual preview `PaginationInput`, assignments, and count; compare DOCX page breaks with legacy paginator count; replace the blanket RTL-run check with separate Arabic-RTL and embedded-English-LTR assertions | No numeric threshold or golden changed; updated assertions are unrun |
| `test/services/docx_floating_elements_test.dart` | Add paginator-candidate rejection/direct-pagination scenarios and mixed RTL/LTR OOXML run assertions | Tests are unrun; supplied-input coverage does not yet exercise wrong input block order or a missing header block |
| `test/layout/document_ir_test.dart` | Assert semantic directions survive the DOCX projection | Unrun |
| `test/layout/canonical/layout_run_source_offsets_test.dart` (untracked) | Assert wrapped/page-fragmented runs map back to source substrings, including NBSP | Untracked and unrun |
| `docs/export_pipeline_master_audit.md` | Preserve the baseline report and add the current worktree audit/status matrix | Documentation only; still needs final post-implementation verification results later |

No package name, Android application ID, version/build/signing configuration,
Android configuration, `third_party/pdf`, golden image, numeric visual threshold,
or unrelated UI feature was changed in this patchset.

### Current architecture and data flow

```
ExamDocument → ExamBlueprint → DocumentIR
  ├─ CanonicalLayoutService → LayoutEngine → LayoutDocument
  │    ├─ CanonicalLayoutPdfPainter → vector PDF (paint-only geometry)
  │    └─ CanonicalLayoutPreviewPage → Exact capture/review only
  ├─ Interactive ExamPreviewScreen widgets → MeasureSize → PaginationInput
  │    └─ PaginationEngine → interactive legacy page groups
  ├─ LegacyDocxAdapter → semantic LegacyBlueprintProjection → editable DOCX
  │    └─ PaginationInput → PaginationEngine → Word page breaks
  │       (direct-call heights are derived from canonical block bounds;
  │        canonical questionPageAssignments are not used)
  └─ ExactExportService → captured page images → image-only PDF/DOCX
```

The interactive Preview is still a separate widget/layout surface; the current
DOCX changes do not migrate it to `LayoutDocument`. The new DOCX fallback uses
canonical block heights as inputs but asks the legacy `PaginationEngine` to
make its page decision. That is different from using canonical PDF page IDs,
but still needs a parity test showing that the selected legacy inputs represent
all required first-page/header/footer constraints.

### Current requirement matrix (standard status values; evidence is patch-aware)

| Area | Requirement | Status | Evidence inspected | Remaining / next proof |
|---|---|---|---|---|
| P0 gate / complete suite | Preserve all gates and publish current-SHA pass/fail/skip counts | NOT VERIFIED | Baseline `37238515598` reports 610 tests passed; P0 is 60 cells (`32 PASS / 0 FAIL / 25 DEFERRED / 3 N/A / 0 UNMEASURED`); one failure-level annotation describes the deferred DOCX header-part cell | Run analyzer, all tests, P0 matrix and CI on the final SHA; no baseline result carries to this diff |
| P0 DOCX pagination | Editable DOCX uses `PaginationEngine`; supplied page groups are rejected unless complete, ordered, and equal to the paginator result | NOT VERIFIED | Current diff adds `PaginationInput`, exact nested group comparison, and candidate-invalid/direct-export tests | Validate input block order, uniqueness and required header block before using it; test wrong input order, missing header, page boundary, footer reserve and direct fallback; run P0 gate |
| P0 DOCX mixed BiDi | Preserve node directions and emit Arabic/RTL plus Latin/LTR runs in either paper direction | NOT VERIFIED | Current diff retains semantic nodes and `VisualRun`, adds Unicode-range segmentation and an OOXML regression test; baseline gate's blanket all-RTL assertion is re-expressed as Arabic runs RTL + embedded English LTR | The classifier is not a complete Unicode Bidirectional Algorithm; test punctuation, digits, brackets, auto/inherit, RTL text in LTR paper, and Word/LibreOffice output; resolve paragraph alignment overrides and preserve math LTR |
| P0 math / Quran / DOCX typography | Keep OMML LTR, Quran fonts/styles, NBSP, sizing, baseline and spacing | NOT VERIFIED | The shared `_runsXml` path and semantic-run projection were changed; baseline tests pass only on main SHA | Re-run Math/OMML/Quran/NBSP/style assertions; add structural and rendered geometry checks; do not claim parity from Exact pixels |
| P0 header / footer / floats | Preserve field content, ownership, placement and page geometry | PARTIAL | Baseline gate measured header fields in `document.xml`; DOCX still uses a body header table, formula floats remain flow content, and structural header/float cells are deferred | Keep the header repetition decision explicit; no Word anchors/OMML RTL fix has yet been demonstrated; test header/footer reserve in the paginator |
| P0 Exact | Exact remains image-only and independent of editable-DOCX pagination | PARTIAL | Baseline tests and visual check on main pass; Exact uses captured page snapshots | Re-run after the final patchset; distinguish embedded image byte parity from text/layout geometry |
| P1 DocumentIR model | Keep `DocumentIR` as the common semantic source without redesign | PASS (baseline model only) | Existing `document_ir.dart`, typed inline nodes, P1 merge and baseline 610-test CI | Current DOCX semantic projection changes are unverified; retain equivalence tests and verify all semantic node/direction fields |
| P1 adapters / Preview | Preserve direction/content through Preview, PDF and DOCX adapters | PARTIAL | PDF derives layout from `DocumentIR`; local DOCX projection now retains semantic nodes; normal interactive Preview is still widget-rendered | Run adapter tests; interactive Preview migration/parity remains open and no new UI-layout engine should be introduced |
| P2 canonical geometry | `LayoutDocument` owns page/line/run/baseline/float/math geometry and page ownership | PARTIAL | Existing canonical layout and PDF painter source; PDF painter positions resolved geometry | Current page/run offsets are unverified; preview page decisions still use legacy widget measurements |
| P2 source offsets | Expose UTF-16 start/end offsets and preserve them through transforms/splits | NOT VERIFIED | Fields are added and `_LayoutBuilder`/scale/move copies pass fragment offsets; new source-substring test is untracked | Format/analyze/run the test; verify bidi/math/newline fragments and page slicing, not only simple wrapped Latin text |
| P2 typography / NBSP / canonical line breaking | One metrics/line-break/justification contract; no extra layout engine | PARTIAL | Main-SHA NBSP suite and canonical metrics checks passed; `PaginationInput` is only a value wrapper over existing `PaginationEngine` | Re-run after `LayoutRun` changes; Preview remains independent; math still needs preliminary measurement and a final geometry pass |
| P2 Preview/PDF geometry parity | Preview and PDF draw the same `LayoutDocument` without reflow | PARTIAL | Vector PDF paints `LayoutDocument`; canonical Preview painter is used for Exact/review | Interactive Preview still wraps/measures widgets; baseline P0 measured Arabic 4 PDF pages vs 5 Preview, English 3 vs 4; no vector-PDF raster RMSE exists |
| Visual regression | Verify pixels and geometry for Preview/PDF/editable DOCX across required cases | PARTIAL | Baseline Visual job compares Exact images: PDF RMSE `0,0,0` vs `0.02`; embedded Word images byte-identical; LibreOffice Exact Word RMSE `0.05891, 0.0685479, 0.0611121` vs `0.12` | These are Exact-export metrics, not vector-PDF or editable-DOCX text parity; broaden only with fixed thresholds and measured fixtures |
| API / backward compatibility | Keep existing export APIs, documents and unrelated configuration stable | PARTIAL | Changes add optional API fields/arguments; no Android/package/version/golden/third-party changes in diff | No real saved-document corpus replay; analyzer and source compatibility not verified |
| CI / Analyze / tests | Same final SHA passes fatal-info analyze and all tests/gates | NOT VERIFIED | Baseline main run only; local Flutter/Dart unavailable | Push the session branch only; wait for `completed + success`; inspect annotations/logs and exact passed/failed/skipped count |
| Android artifact | Build and inspect release artifact on final SHA | NOT VERIFIED | Baseline artifact metadata is 28,510,269 bytes; blob download failed with EOF | Final-SHA artifact build/upload/download or explicit download limitation; no config changes unless a demonstrated cause requires them |
| Git / PR | Commit/push only to fixed branch; create but never merge PR | NOT VERIFIED | Session branch equals main, is dirty, has no upstream/ref/PR; no local commit exists | Finish fixes/tests, create explicit commit, push only `arena/01a10a27-writing-questions`, open PR, review final checks, do not merge |

### Diff review findings and required follow-up before a verified claim

1. **Validate the pagination input, not only page-ID candidates.** `_paginationInputFor` currently checks that expected question IDs are present and unique, but does not require the header block or prove the blocks are in blueprint/source order. A complete but reordered `PaginationInput` could therefore make the paginator return a reordered plan and then validate a matching candidate. Add checks and regression tests. `ExamWizardController.isFullyMeasured` checks header + questions but not the footer measurement even though `footerReserve` is zero before footer measurement; resolve whether a measured footer reserve is required before Word export and test that boundary.
2. **Review header/category alignment against paragraph direction.** `_buildQuestion` currently precomputes `alignmentOverride: _wordAlign(question.categoryAlign)` using the document default, while `_writeStyledParagraph` now derives paragraph direction from run text. A start/end category alignment in mixed text may therefore be resolved against the wrong direction. Carry the semantic alignment through to the paragraph resolver and test RTL/LTR text on both paper directions.
3. **Do not call the custom script splitter a complete BiDi engine.** `_strongDirectionRtl` uses hand-listed Unicode ranges; it is useful for common Arabic/Hebrew + Latin runs but is not the full Unicode Bidirectional Algorithm. Compare against the existing canonical direction metadata/resolver instead of creating a third layout engine; exercise neutrals, digits, punctuation, paired brackets, explicit `ltr/rtl`, `auto/inherit`, and math. Confirm OOXML with the actual probe and a rendered Word/LibreOffice fixture.
4. **Audit the shared math/Quran path after semantic run projection.** `_semanticRuns` supplies original `VisualRun` objects directly to `_runsXml`; verify math zones still avoid RTL properties, Quran style/font survives, NBSP/literal dollar behavior is unchanged, run order is preserved, and the exported paragraph/page geometry stays within the existing thresholds.
5. **Source offsets remain unverified.** Offsets originate from `MeasuredRunFragment`, relative to each semantic span's UTF-16 source. Confirm offsets remain valid through bidi fragmentation, newline/word slicing, math, page slicing, scale and move; test source substring equality and no interval overlap without changing existing goldens or thresholds.
6. **P0 gate edits are requirement corrections, not a threshold reduction.** The DOCX page-break comparison is moved from canonical PDF page count to the captured `PaginationEngine` plan. The former blanket `title.runs.every(run.rtl)` assertion is split into Arabic-run RTL and embedded-English-run LTR assertions. Both changes are unrun; preserve/assert both sides and do not remove any other gate cell.
7. **Pre-existing P0/P2 work remains open.** Interactive Preview is not a canonical-layout painter; baseline page counts differ; header is a body table; floating formulas are flow content; Arabic OMML direction is deferred; visual RMSE covers Exact only; no versioned saved-document corpus is present. These items cannot be marked `PASS` from the current patch.
8. **Baseline CI is not current-patch CI.** Run `37238515598` is green on `main` SHA `3762bba…`, not the dirty worktree. No local `dart format`, `flutter analyze`, `flutter test`, P0/P1/P2 integration gate, visual run, or Android build has occurred. The current overall status is `NOT VERIFIED`.

### Findings established at the baseline (clean `main`)

1. **Editable DOCX pagination source is wrong.** The writer currently uses a
   canonical page plan both when a caller supplies it and, via a PDF-engine
   fallback, when one does not. The code validates membership but not page order,
   actual page capacity, or equality with `PaginationEngine`. This is the
   highest-priority architecture fix; the test must prove that Editable DOCX
   uses the legacy paginator while Exact remains image-only and independent.
2. **Canonical source offsets are implicit.** `MeasuredRunFragment` already has
   offsets, but `LayoutRun` exposes them only indirectly through
   `logicalIndex`; consumers cannot assert an explicit source interval. Add
   start/end offsets to the canonical geometry model and carry them through
   scaling/movement.
3. **Interactive Preview is a separate layout surface.** Exact capture uses
   `CanonicalLayoutPreviewPage` but the regular editor still wraps and measures
   widgets. The matrix marks this `PARTIAL`; do not claim preview/PDF parity
   until the visible review path is canonical or a separately measured
   interaction-only overlay is proven not to make layout decisions.
4. **Mixed-direction DOCX needs per-run evidence.** The IR and canonical engine
   carry direction; the legacy DOCX serializer currently sets paragraph/run
   direction from the document default. A change must be driven by a mixed
   Arabic/English regression fixture and must not blanket-remove RTL from valid
   Arabic runs or invert OMML.
5. **Visual coverage is not 18 independent screenshots.** The current composite
   fixture and P0 structural probes cover many requested content types, but the
   visual job currently compares Exact snapshots rather than vector PDF. Do
   not lower its `0.02`/`0.12` thresholds; only extend this after a root cause
   and an actual green CI run are available.
6. **Historical assertion changes were context-checked.** The P2 commit replaced
   the parenthesis check that depended on PDF operator-emission order with a
   stronger x-position/visual-order check; replaced math request/resource counts
   with actual canonical Math-run, host-request, and placed-image assertions;
   retained the `mathSpan > 9.0` limit; and updated option-label probes to account
   for semantic punctuation runs while adding a split label/separator assertion.
   PR #37 retained `rightDrift < 1.5`, added a raw-or-digit-normalized DOCX
   header presence assertion, and made the header-cell state follow measured
   OOXML structure. Exact-mode tests were combined without dropping their
   default/editability or Exact-disclosure expectations. No numeric threshold,
   golden, or fixture was found deleted in those historical `main` diffs. The
   current uncommitted patch re-expresses the former blanket title-run direction
   assertion per script (Arabic must be RTL; embedded English must be LTR), as
   listed in the current diff review above; that change is still unverified.
7. **No local SDK is installed.** Local `flutter analyze`/`flutter test` cannot
   be run here. Final verification must use new GitHub Actions checks on the
   implementation SHA and report any inaccessible logs/artifact bytes honestly.

---

> **Historical baseline report retained for traceability.** The original matrix,
> architecture summary, and findings below describe an earlier audit snapshot.
> They are superseded by the baseline-specific matrix and the patch-aware
> `Current worktree audit` above; do not use the older `PASS` labels or page-plan
> claims as current status.

## Historical baseline report (pre-current worktree audit)

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
| Test count reported by CI (baseline) | **607 tests passed**, 0 failed, 0 skipped |
| Test count after this change set | **610 tests passed**, 0 failed, 0 skipped (run `37206836683`, SHA `ade75254`) |
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
| CI | analyze `--fatal-infos` (source **and tests**), tests, gate, visual parity, APK on every push | PASS | baseline run `37202705105` and final run `37206836683` | — (the `test/**` exclusion was removed and the 24 findings fixed, F5) | — | workflow file |
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

* ~~`analysis_options.yaml` excluded `test/**` with a "TEMPORARY (removed before
  the final commit)" comment~~ — **closed**: the exclusion is removed,
  `flutter analyze --fatal-infos` covers the tests again, and the 24 findings the
  analyzer reported on first exposure are fixed. Rule tally published by the
  workflow: 5 `unnecessary_brace_in_string_interps`, 5
  `prefer_adjacent_string_concatenation`, 4 `unused_import`, 4
  `unnecessary_string_escapes`, 3 `prefer_interpolation_to_compose_strings`,
  3 `prefer_const_declarations`, 2 `unnecessary_import`, 1 `unused_element`,
  1 `unnecessary_non_null_assertion`, 1 `prefer_const_constructors`. Evidence:
  run `37206645457` (findings) → run `37206836683` (analyze clean, tests green).
* Visual regression runs on one fixture document (three pages); content-level
  coverage of the 18 cases listed in the request is spread across the P0 gate
  probes and the canonical/metrics tests rather than one image suite.
* ~~The gate prints its full matrix as a CI notice but the per-cell *evidence*
  strings live in `matrix.txt`/`summary.txt` artifacts~~ — **closed**: since this
  change set `build/export_gate/summary.txt` is published as a second check-run
  notice, so the per-cell numbers are readable from the API without artifacts
  (`matrix.txt`/`summary.txt` remain uploaded as artifacts).

### F6 — DOCX deferrals that are product-level

* Floating elements are written into the paragraph flow without `wp:anchor`, so
  Word cannot pin them to the authored position (`floating/editableDocx`).
* OMML runs carry no direction declaration, so Arabic inside a formula is left
  to Word's maths default (`math/editableDocx`).
Both are recorded with reasons; neither is weakened by this audit.

## Change set of this session (what changed and why)

| # | Change | Files | Evidence |
|---|---|---|---|
| 1 | `GATE-06` measures every header field in its raw **and** digit-localized form and now **fails** if a field is absent in both; the recorded `header-footer/editableDocx` deferral keeps only the structural reason (no `word/header*.xml`). `GATE-99` requires the registration to name the localized forms and the cell status to follow the measured header-part structure. | `test/export_gate/p0_export_gate_test.dart` | run `37206836683`: `missingAnywhere` empty; matrix tally unchanged `PASS=32 FAIL=0 DEFERRED=25 N/A=3 UNMEASURED=0`; the deferral annotation names `HDRV/HDC١/HDC٢/HDG١/HDT١` |
| 2 | New canonical NBSP suite: measurement + justification, differential line-breaking (ordinary space vs NBSP at 13 widths), page assignment across 4 page heights with `splitQuestion=true` | `test/layout/canonical/canonical_nbsp_page_assignment_test.dart` (new, 3 tests) | run `37206836683`: `space=2.652 nbsp=2.652 pair=43.608 sum=40.956 justifiedLines=19/21`; `spaceSplitWidths=9 nbspMovedAsUnit=9 nbspLineCounts=[1,2]`; `240pt→13ص 320pt→8ص 420pt→6ص 520pt→5ص` |
| 3 | The NBSP suite harness follows the repo's proven pattern (`TestWidgetsFlutterBinding` + plain `test()` + fonts in `setUpAll`) with explicit 3-minute budgets | same file | first run `37203941994` timed out twice (10 min each) inside `testWidgets`; after the harness change all three tests run and pass (`37206836683`) |
| 4 | `test/**` analyzed again; the 24 reported findings fixed mechanically (identical string values, unused imports removed, `const` where constant, one unused private regex deleted, one redundant `!` dropped) | `analysis_options.yaml` + 9 test files | run `37206645457` published the tally (total=24) → run `37206836683` reports no analyzer finding |
| 5 | CI diagnostics: publish `build/export_gate/summary.txt` as a notice; publish analyzer warnings/infos with a per-rule tally (previously only errors were published, so `--fatal-infos` failures arrived without rule or count) | `.github/workflows/build_apk.yml` | run `37206836683` carries the `P0 gate — summary` and (when needed) the analyzer notices |
| 6 | Historical P0 report carries a measured correction of the "missing DOCX header fields" claim (F1) instead of leaving it as the only "real regression" | `docs/export_p0_gate_report.md` | this document, F1/F2 |

## Verification performed for this change set

* Local: **no Flutter/Dart toolchain in this environment** (SDK hosts are
  unreachable), so nothing is claimed as locally verified; every number below
  comes from GitHub Actions.
* Green runs on the branch: `37206149727` (SHA `74a077ac`) and `37206836683`
  (SHA `ade75254`) — both jobs `success` (`Analyze, test, and build APK`,
  `Visual regression`), `Attach APK to GitHub release` skipped by design
  (tag-only).
* Test count: **610 passed, 0 failed** (607 baseline + 3 new NBSP tests).
* P0 gate: 60 cells, `PASS=32 FAIL=0 DEFERRED_TO_P1=25 NOT_APPLICABLE=3
  UNMEASURED=0`, unchanged by this change set — the deferrals are the ones
  documented in F2/F3/F6, not new ones.
* Visual parity: `tool/verify_visual_parity.sh` green (PDF pages RMSE 0 against
  the 0.02 cap; the Word render of `exact.docx` within the 0.12 cap).
* Android: `flutter build apk --release` success; artifact
  `writing-questions-release-apk` (28,510,271 bytes) plus `p0-export-gate` and
  `visual-parity` artifacts on run `37206836683`.
* Changed gate: `P0GateFixture.headerMarkers` are matched in their raw *and*
  digit-localized forms; a genuinely missing field fails `GATE-06`.

## Remaining issues (pre-existing deferrals, with the exact next fix)

None of these is a regression introduced by this change set; each is already
recorded in the gate with a named reason. They are listed here with the fix path
so the next session does not have to re-derive the root cause.

1. **Editable DOCX header is a first-page body block, not a Word header part**
   (F2; gate cell `header-footer/editableDocx` = `DEFERRED_TO_P1`). Next fix:
   emit `word/header1.xml` with the header table, reference it from `sectPr` as
   `w:type="first"` next to `<w:titlePg/>`, stop writing `_buildHeaderTable()`
   into the body (line 401) and subtract the header height from the first page's
   capacity in the legacy plan. Requires a Word/LibreOffice render check, which
   this environment cannot provide.
2. **Interactive editor preview still measures widget heights** (F3; gate cells
   `pagination/vectorPdf`, `arabic|justification|ltr-document/preview`). Next
   fix: paint `CanonicalLayoutPreviewPage` for the editing surface as well and
   feed `PaginationEngine` from the canonical page plan, so one layout decision
   serves both paints. `test/visual/visual_parity_fixture_test.dart` already
   renders the interactive preview, so the migration is measured by it.
3. **DOCX floats have no `wp:anchor`, OMML runs have no direction**
   (F6; `floating/editableDocx`, `math/editableDocx`). Next fix: write authored
   float geometry as `wp:anchor` positioning and add `w:rtl`/`w:bidi` inside
   `m:r` for Arabic math runs; then both cells can move from `DEFERRED_TO_P1` to
   a measured `PASS`.
4. **LTR paper keeps document-level direction for side blocks and paragraphs**
   (gate cells `ltr-document/vectorPdf`, `ltr-document/editableDocx`). Next fix:
   derive paragraph/run direction from the paragraph's own strong text in
   `PdfPaperBuilder` and `LegacyBlueprintProjection` (the canonical metrics
   layer already resolves per-span direction through `_bidiDirectionFor`). Note
   that the gate criterion `rtlRunLeak` ("no `w:rtl` run anywhere in an LTR
   paper") must then be re-expressed as "an LTR paragraph must not carry
   `w:rtl`", otherwise the fix and the criterion contradict each other.
5. **Three Preview cells are `NOT_APPLICABLE`** (`arabic-numerals`,
   `latin-numerals`, `punctuation`): the widget tree exposes no semantic token
   for them. They become measurable with fix 2 (the canonical layout carries
   per-run content kinds).
6. **The 15 Exact cells are `DEFERRED_TO_P1` by design**: the Exact files are
   page images, so no structural claim can be measured on them; the visual
   parity script is the authority for those paths.
