# P1 semantic-pipeline map (before implementation)

## Current construction path

- **`ExamDocument` creation**: `ExamWizardController` creates the initial model in `lib/providers/exam_wizard_controller.dart`; saved documents enter through `ExamDocument.fromMap/fromJson` in `lib/models/exam_document.dart`; controller edits create immutable copies and normalize question numbering. `header_step_screen.dart` also creates a temporary `ExamDocument` solely for its live header/footer preview.
- **`ExamBlueprint` creation**: `ExamBlueprint.from(document)` invokes `_BlueprintBuilder` in `lib/layout/blueprint/exam_blueprint.dart`. `ExamWizardController.blueprint` caches it for Preview. The PDF engine, DOCX builder, and header-step preview currently also call `ExamBlueprint.from` independently.
- **Preview**: `exam_preview_screen.dart` reads `controller.blueprint` for question order, title numbers/marks, categories, header, and footer, but renders editable body fields from `ExamDocument`/model values. `PaperField` passes source strings to `TexText`; `TexText` then calls `RichContent.parse` while building the widget. Option labels are independently requested from `ExamDocument.displayOptionLabel` in `_buildPointOptions`. Attachments/floating elements are discovered from the domain models and rendered in a page overlay. Header/footer widgets render `HeaderBlueprint`/`FooterBlueprint` strings.
- **PDF**: `PaginatedPdfExamEngine` independently calls `ExamBlueprint.from`; `PdfPaperBuilder` consumes that blueprint. It renders numbers, labels, statements, marks, and options as separate widgets in many cases, but header/footer fields arrive as already-composed strings. `_renderText` calls `TexContent.split` and its plain-text path calls `QuranText.split`; floating/legacy attachments are separately collected from `ExamDocument` and rendered by `FloatingElementsPdf`.
- **DOCX**: `_DocxBuilder` independently creates `ExamBlueprint.from(document)`. Header/footer lines and question/branch/point content come from the blueprint; `_titleRuns`, `_pointRuns`, and `_optionRuns` construct DOCX runs and separators. `_runsXml` calls `RichContent.parse` before producing ordinary runs, Quran runs, OMML, or the existing raster fallback. Floating elements/attachments are separately scanned from `ExamDocument`.

## Semantic construction and flattening sites found

| Surface | Current construction/flattening | Current consumer(s) |
|---|---|---|
| Question label/number | `ExamDocument.autoQuestionLabel` / `SubjectLayoutTemplate.questionLabel`; `_BlueprintBuilder._question` appends `questionSeparator` to the label, while a manual `numberOverride` is emitted verbatim. `TitleLineBlueprint.number` stores the combined label+separator; `TitleLineBlueprint.line` joins number, statement, and marks. | Preview, PDF, DOCX |
| Item label | `ExamDocument.autoItemLabel` returns `'${formatNumber(itemIndex + 1)}-'`; `displayItemLabel` substitutes a manual override. | Preview, PDF, DOCX |
| Branch label | `ExamDocument.displayBranchLabel`; `_BlueprintBuilder._branch` concatenates label + `branchSeparator` into `TitleLineBlueprint.number`. | Preview, PDF, DOCX |
| Option label | `ExamDocument.autoOptionLabel` returns `'( ${branchLabel} )'`; `displayOptionLabel` substitutes an override. `OptionBlueprint.line` joins label + text. | Preview (currently independently recalculates), PDF, DOCX |
| Marks | `_BlueprintBuilder._marks` flattens the number, parentheses, unit, and spaces into strings such as `'(٢٠ درجة)'`. `PointBlueprint.line` joins label/text/trailer/marks. | Preview, PDF, DOCX |
| Options row | `PointBlueprint.optionsLine` joins option lines with five NBSP characters; DOCX has its own `_optionSeparator` policy. | DOCX compatibility path; tests/API |
| Category | `QuestionBlueprint.section` stores the trimmed category as a string. | Preview, PDF, DOCX |
| Header | `_BlueprintBuilder._header` independently combines prefixes/labels, values, spaces, blank dotted lines, school gender/session, and localized year digits into `rightLines`, `centerLines`, and `leftLines` strings. | Preview, PDF, DOCX |
| Footer/signatures | `_footer` trims closing phrase/name and resolves title labels; `SignatureBlueprint.nameLine` chooses name or dotted placeholder. | Preview, PDF, DOCX |
| Rich text / Quran / math | `RichContent.parse` is the shared existing parser, but Preview `TexText`, PDF `_renderText`, and DOCX `_runsXml` invoke it from legacy strings. `VisualRun` identifies text/math/Quran, and Quran runs carry Amiri style; LaTeX text is split by `TexContent`, Quran by `QuranText`. | Preview, PDF, DOCX |
| Attachments / floating elements | Question/branch attachments and document-level `floatingElements` remain domain-model objects; Preview, PDF, and DOCX separately scan them. PDF `needsQuranicFont` has its own exhaustive field scan. `FloatingElement` contains renderer/layout-bearing data (bytes, dx/dy, size, page index), so the IR must refer to it by semantic identity rather than embed the model. | Preview, PDF, DOCX |

## Existing contracts to preserve/classify

- `RichContent` / `VisualRun` are the current rich-inline nucleus; `VisualRunKind` already distinguishes text, LaTeX, and Quran, and `VisualRunStyle` carries Quran font intent.
- `ExamTypography`, `VisualMetrics`, and `PaperMetrics` are established rendering/layout contracts. P1 IR may refer to semantic style roles/overrides and alignment intent, but must not copy metrics or measured geometry.
- `ExamTextStyles` is compatibility-only in the PDF builder signature (P0-GATE-08 proves it is passed but unused); keep it.
- `VisualRunStyle.baselineShiftPt` is a public unused contract (P0-GATE-08); keep it for later.
- Legacy flattened getters (`autoItemLabel`, `TitleLineBlueprint.line`, `PointBlueprint.optionsLine`, and related getters) have public/test consumers; retain them as derived compatibility projections, but do not use them to construct DocumentIR or Preview semantics.
- `VisualLayoutEngine` / `VisualDocument` in `lib/layout/visual/visual_document.dart` are not called by production code (search found no call site). They contain layout intent/metrics and duplicate content-building logic; retain and classify them as **candidate for P2**, not as the P1 IR.

This map was written before the P1 implementation. It describes the pre-change paths and is not itself a renderer or a new layout engine.
