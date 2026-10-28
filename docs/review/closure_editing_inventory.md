## حالة المراجعة الحالية — لا قبول شامل

Baseline4b1f: Main40600056283 نجح8/219/1038/3/analyze/actualAPK؛ لكن C6 WOULD FAIL83،
واختلاف الدرجة/الرأس مرئي. المرجع الأعلى هو [closure_status.md](closure_status.md).
الـPENDING القديمة أدناه موسومة تاريخية؛ لا تنقلها إلى نتيجة الشفرة الجديدة.

| نطاق التحرير | أقوى دليل baseline | ما يزال غير مثبت |
|---|---|---|
| question/branch reorder | 6 actual long-press drags320/360، model كامل/undo/redo/live-PDF | كل split/long/boundary/media/format combination؛ كل صفحة بصريًا |
| Text/Math/Chemistry/Physics/Media | R8 targets42 command instances؛ native audits تشمل75 width-cases | كل command → insert/edit/delete/history → preview/PDF، لا مجرد وجود أو invocation |
| point/option/blank/continuation | اختبارات canonical والإنتاج الحالية | كل original/continuation/endpage320/360 مع نفس model/coords و48dp |
| format/mixed/math/color | اختبارات native/PDF وactual raw operators الحالية | كل أداة/نطاق/حد صفحة؛ حبر + في Visual sample يحتاج تشخيصًا |
| assets/concurrent export | actual delayed old/new image + document-version races | platform picker وكل نوع asset/format/load/export ordering |
| printed drag / text / marks handles | أضيف mounted-frame inventory لجميع primitives في6 حالات قبل/بعد مع transformed screen-dp وscreenshot/hit sample | effective48×48، overlap، containment/accessibility، dialogs/continuation/platform selection؛ كل صف effectiveTargetVerified=false |
| Android keyboard/focus/save | أضيف real-APK emulator smoke evidence path؛ PENDING | Arabic/English composition، long multiline/options، insets/navigation/export، actual IME matrix |

لا استنتاج شامل من R8 أو من قياس allocated/rendered bounds. الجرد الجديد محدود
بالإطارات الملتقطة وليس كل حالات التطبيق؛ جميع الحالات غير المقاسة **unverified**.
التقرير الشامل يحدد قواعد الدرجة غير المحسومة و83 مخالفة C6 فردية. candidate OFF.

---
## جرد وسجل تاريخي محفوظان للتتبع

# Editing inventory — source map, NOT final acceptance

Scope: branch `arena/8513fa6c-writing-questions`, subsequent work after
`fbb9b8e1c16ebd46344d60d48b6e4dedc02d2145`. That SHA's main run40582445191
completed FAILURE (full951/3; analyzer clean; APK not executed), Extended/Visual/C6
SUCCESS. The complete command logs and originals were hash-verified and retrieved.
**Those are not final-SHA results for the new source/test changes.**
Every unexecuted row below remains unproved; no candidate activation.

## Specialty toolbar

Source: `lib/views/widgets/smart_exam_toolbar.dart`. Five distinct tabs,
**42 visible command instances** when optional production callbacks are supplied:
Text5, Math10, Chemistry9, Physics8, Media10. Math8/Chemistry7/Physics6 are
snippet counts, NOT total command counts: each also has open/edit equation.
Do not merge the five categories.

**T8** = `test/layout/canonical/production_fragment_regression_test.dart`,
`R8 all five specialty tabs and every command retain 48dp targets at $width dp`.
This enumerates all commands below at320/360, scrolls them into view and measures
width/height >=48dp. It DOES NOT invoke each command or prove insertion,
selection, history, page-boundary editing or PDF parity. This distinction applies
to every row, even where a separate model/widget test exists.

| Tab | Command | Existing source test map / limitation |
|---|---|---|
| نص | سؤال جديد | T8; AUD-UR-01 model history is not candidate toolbar target proof |
| نص | فرع جديد | T8; AUD-UR-01 model history is not candidate toolbar target proof |
| نص | سطر جديد | T8; functional insertion/history/export proof outstanding |
| نص | ملاحظة للمعلم | T8; functional insertion/history/export proof outstanding |
| نص | آية قرآنية | T8; functional insertion/history/export proof outstanding |
| رياضيات | محرر المعادلات | T8; functional insertion/history/export proof outstanding |
| رياضيات | تحرير معادلة | T8; functional insertion/history/export proof outstanding |
| رياضيات | كسر | T8; functional insertion/history/export proof outstanding |
| رياضيات | جذر | T8; functional insertion/history/export proof outstanding |
| رياضيات | أس | T8; functional insertion/history/export proof outstanding |
| رياضيات | فرعي | T8; functional insertion/history/export proof outstanding |
| رياضيات | متكامل | T8; functional insertion/history/export proof outstanding |
| رياضيات | مجموع | T8; functional insertion/history/export proof outstanding |
| رياضيات | نهاية | T8; functional insertion/history/export proof outstanding |
| رياضيات | معادلة | T8; functional insertion/history/export proof outstanding |
| كيمياء | محرر المعادلات | T8; functional insertion/history/export proof outstanding |
| كيمياء | تحرير معادلة | T8; functional insertion/history/export proof outstanding |
| كيمياء | ماء | T8; functional insertion/history/export proof outstanding |
| كيمياء | ثاني أكسيد الكربون | T8; functional insertion/history/export proof outstanding |
| كيمياء | حمض الكبريتيك | T8; functional insertion/history/export proof outstanding |
| كيمياء | الأمونيا | T8; functional insertion/history/export proof outstanding |
| كيمياء | سهم تفاعل | T8; functional insertion/history/export proof outstanding |
| كيمياء | تفاعل عكوس | T8; functional insertion/history/export proof outstanding |
| كيمياء | معادلة أيونية | T8; functional insertion/history/export proof outstanding |
| فيزياء | محرر المعادلات | T8; functional insertion/history/export proof outstanding |
| فيزياء | تحرير معادلة | T8; functional insertion/history/export proof outstanding |
| فيزياء | قوانين نيوتن | T8; functional insertion/history/export proof outstanding |
| فيزياء | نسبية | T8; functional insertion/history/export proof outstanding |
| فيزياء | قانون أوم | T8; functional insertion/history/export proof outstanding |
| فيزياء | الشغل | T8; functional insertion/history/export proof outstanding |
| فيزياء | سرعة | T8; functional insertion/history/export proof outstanding |
| فيزياء | متغير | T8; functional insertion/history/export proof outstanding |
| وسائط | صورة | T8; AUD-ELEM-01 / AUD-UR-01 are partial; real picker/loading/export races outstanding |
| وسائط | معادلة حرة | T8; functional insertion/history/export proof outstanding |
| وسائط | مثلث | T8; functional insertion/history/export proof outstanding |
| وسائط | دائرة | T8; functional insertion/history/export proof outstanding |
| وسائط | مربع | T8; functional insertion/history/export proof outstanding |
| وسائط | مستطيل | T8; functional insertion/history/export proof outstanding |
| وسائط | خط | T8; functional insertion/history/export proof outstanding |
| وسائط | سهم | T8; functional insertion/history/export proof outstanding |
| وسائط | مربع نص | T8; functional insertion/history/export proof outstanding |
| وسائط | فاصل | T8; AUD-DIV-01 addition/undo/redo; final-page paint/clip and final-SHA review outstanding |

Staged formula card drag, long-press display mode and cancel are additional
interactions, not extra snippet entries. All remain unproved as complete
candidate edit → history → same-document export sequences at this SHA.

## Primary toolbar / navigation / formatting

Source: `lib/views/wizard/preview_toolbar.dart`. AUD tests below live in
`test/wizard/preview_buttons_functional_audit_test.dart` unless specified.
R8 checks the eight named regression controls AND enumerates InkResponse
controls in PreviewToolbar, AppBar and the current question-actions bar (>20
primary controls). This covers those rendered scopes, NOT every dialog, owner
state, printed drag handle or continuation. It is measurement, not functionality.

| Control / workflow | Existing test source / evidence gap |
|---|---|
| تراجع | AUD-UR-01..06; candidate source/point-option tests; no new final-SHA result |
| إعادة | AUD-UR-01..03; candidate point-option commands; no new final-SHA result |
| قفل/فتح التحريك | AUD-LOCK-01; legacy floating drag is not question/branch reorder |
| تصغير | AUD-NOFX-01; primary R8 target |
| نسبة التكبير / 100% | AUD-NOFX-01; not in primary R8 eight-control list |
| تكبير | AUD-NOFX-01; primary R8 target |
| ملاءمة الورقة | AUD-NOFX-01; primary R8 target |
| توسيط الورقة | AUD-NOFX-01; primary R8 target |
| تحديد متعدد | AUD-UR-04; fragment source/style/print invariance needs final review |
| تحديد/إلغاء تحديد الكل | No final-SHA complete candidate selection/print/export proof |
| الخط / تلقائي | AUD-UR-01 model styles; all actual menu choices and script shaping unproved |
| حجم الخط / تلقائي / مخصص | AUD-UR-01 + invalid-value cases; actual menu/blank/boundary proof incomplete |
| عريض | selection_toolbar_state_test.dart; primary R8 target; final parity unproved |
| مائل | selection_toolbar_state_test.dart; primary R8 target; final parity unproved |
| تحته خط | selection_toolbar_state_test.dart; primary R8 target; final parity unproved |
| محاذاة يمين | preview_toolbar_test.dart alignment; AUD-ALIGN/UR; final candidate proof missing |
| توسيط النص | preview_toolbar_test.dart alignment; AUD-UR-06; final candidate proof missing |
| محاذاة يسار | preview_toolbar_test.dart alignment; AUD-UR-05; final candidate proof missing |
| ضبط النص | AUD-JUSTIFY-01; final fragment mixed-RTL/PDF proof missing |
| تباعد الأسطر | preview_toolbar_test.dart line-spacing; all presets/custom and boundaries unproved |
| تباعد الفقرات | preview_toolbar_test.dart paragraph-spacing; final boundary/clip proof missing |
| تباعد الأسئلة | AUD-UR-01 / invalid-value tests are partial; full actual menu/boundary proof missing |
| اللون | selection_toolbar_state_test.dart / preview_toolbar_test.dart; final rendered color parity unproved |
| إطار حول التحديد | AUD-UR-01 model history; continuation/end-page frame painting unproved |
| شريط الصيغ والوسائط | R7 default-hidden/document invariance; AUD-NOFX-02; primary R8 target |
| حفظ | AUD-PERSIST-01 + AUD-HDR-01; real persistence during assets/IME not proved |
| مراجعة وتصدير PDF | AUD-NOFX-02 review/cancel is NOT actual export; async freshness/asset cases missing |

## Owner/field/element workflows and required missing tests

Source mappings are not final-SHA execution proof; see closure_status.md for the historical fbb result.
Candidate tests: `test/wizard/canonical_editor_candidate_test.dart`.
Screen tests: `test/wizard/canonical_preview_screen_test.dart`.

| Workflow | Test/source map | Remaining acceptance gap |
|---|---|---|
| Original and continuation question/branch text | `candidate native question and branch source keeps IME across fragments` at320/360 | Final results and actual selection/edit screenshots/PDF missing |
| Empty question/branch and entirely unprinted owners | Candidate empty / entirely unprinted owner tests at320/360; AUD-EMPTY-01 | All tools while blank, focus and actual print invariance not fully audited |
| Numbers/marks/title dialogs | Candidate metadata test at320/360; question_actions_bar_test.dart | All metadata/point dialogs and touch targets not fully reviewed |
| Points/options add/edit/type/label/delete | Candidate point-option commands/continuations and same-frame earlier deletion; AUD-MCQ/PTS/TYPE | Final run, long-option image review, both original/continuation and end-page proof |
| Question add/copy/delete | AUD-DUP-01, AUD-UR-01; existing action bar | Complete candidate pointer-driven operation/history/export proof |
| Branch add/copy/delete | AUD-DUP-02, AUD-UR-01; candidate fields | Preserve distinct «إضافة فرع» owner target versus «فرع جديد» selection target; no equivalence asserted |
| Actual QUESTION reorder drag | NEW real_reorder_export_test.dart, 2 widths, real long-press + entire model undo/redo + live PDF coordinates/order + PNGs | PENDING execution and actual originals review; not candidate parity |
| Actual BRANCH move/swap within/between questions | NEW real_reorder_export_test.dart, 4 cases, real gesture, owner/content/marks/history and live PDF checks | PENDING execution and actual originals review; not candidate parity |
| Floating element move/resize/rotate/ownership | preview_toolbar_test.dart; AUD-LOCK/ROT/ELEM; screen floating destination-page drag | Not question/branch reorder; real media loading and all owner fragments incomplete |
| Header/footer editing | AUD-HDR-01, AUD-ALIGN-HDR-01 | fbb header4/4 independent outline check and one actual image pair reviewed; final-SHA and all metadata edits still unproved |
| Divider edit/delete and final boundary | AUD-DIV-01 only establishes addition/history metrics | Final-page plan/clip/paint and editing proof incomplete |
| Inline/display math and specialist templates | Production/native math evidence tests; bounded floating-fit test | Final-SHA glyph-ink review, all insertion/edit/copy/delete sequences missing |
| Focus/IME/composition/keyboard | Candidate native source tests at320/360 | No actual platform keyboard/picker/manual integration pass; all media/format focus changes incomplete |
| Late layout completion | screen `stale layout completion cannot replace the newer document page` | Not a complete export race test |
| Dispose during pending layout | screen `disposing while canonical layout is pending discards late result` | Not a complete asset-loading race test |
| Export DURING text/model/style change | NEW export_version_race_test.dart, real review/export UI, real old bytes with controlled completion, version change/refusal/current PDF | PENDING execution; external/controller update, not real keyboard IME; library-write race not separately controlled |
| Export DURING asset/font/media loading | NEW asset_completion_race_test.dart: actual image bytes/pixels, pending old decode, current PDF text+image count, reject late old assets | PENDING execution; uses existing injected canonical asset boundary, not platform picker or all production-font/media-error races |
| All controls at320/360 and page boundaries | Specialty R8 measures42 commands + five tabs; primary R8 includes rendered InkResponse scopes | Full primary, nested dialogs, owner actions, handles, empty/continuation cases remain unproved |

**No activation:** shared fixed print remains authoritative; candidate remains
OFF. Do not remove controls, merge non-equivalent branch commands, alter stored
models, hide overflow or relax any existing gate to close these gaps.


## Explicit remaining acceptance gaps

- Printed drag icons are18/16 paper pixels, transformed by zoom; no assertion
  here proves a48dp effective hit region for them. Whole-scope R8 is NOT proof
  of these handles or every nested dialog/blank/continuation state.
- The new six drags use a short one-page mixed-text fixture. They do not prove
  cross-page reorders of the split long math/media fixture or long-option edits.
- The new image race checks actual green preview pixels and one emitted image;
  it does not independently decode the PDF image's color pixels or prove all
  formats, failed loads, concurrent saves or the platform picker.
- The new export race controls the PDF completion boundary; it does not claim
  actual hardware IME composition or every style/media update during encoding.
- Native Amiri ActualText preserves logical source metadata. Spatial MuPDF RTL
  copy order is explicitly unverified, not silently counted as parity.
- All new Dart tests are PENDING at this snapshot; source code is not a PASS.


### Actual execution at513938a (not transferable to subsequent fix)

Main40585963097 native-first116/2, analyzer clean, Extended40585962900 success.
The new4 branch drags,2 external-version export races,2 image-completion races,
3 independent raw-PDF measuring tests, and1 real OpenType/ActualText PDF test
passed. BOTH question drags failed with a framework RangeError; no full-suite,
APK, Visual or C6 execution followed. Stable-ID rebinding in DragTarget.builder
and phase-specific FlutterErrorDetails assertions are added next; NOT proven yet.
No activation and no promotion of this partial result into final acceptance.


### Broader narrow audits and newly observed visual defect

At8bfcc66, all6 real drags passed; full979/0, analyzer clean, actual31.3MB APK
built. This DOES NOT close visual parity: opening the earlier original branch
PDF revealed Arabic words overlapping inside the LTR English title/marks.
`FlutterTextMetrics._measureWords/_caretBoundsDetailed` and independent native
selection/PDF non-overlap regressions are changed next; outcome is PENDING.

`preview_button_audit_test.dart` has25 actual pointer/model/dialog cases,
including all font/size/line-spacing/color presets,6 shape insertions, text
insertion/guidance, image picker stubs/cancel/replace, resize and persistence.
Previously its helper defaulted to1600dp. The same original assertions are now
registered at1600/320/360 defaults; explicit width overrides remain explicit.
These are stronger than callback invocation, but NOT actual platform image
picking/IME, every math-template insertion, or all per-tool PDF/color parity.
The new narrow execution and Arabic-locale/3x drag evidence are PENDING.

No48dp assertion for scaled print drag handles, no full split-long-document
reorder/media/format export matrix, and no universal candidate parity are
claimed. All remaining gaps above still prevent CLOSED/candidate activation.

### 5eb narrow execution / next patch

Main40590392389 (SHA5eb88fd…) ran all75 existing pointer-audit cases at
1600/320/360 defaults without excluding any original assertion. Native gate185
passed/12failed, all12 in the narrow audit (six at each narrow width). Four per
width require actual scrolling of lazy specialty command lists before lookup;
settings dropdown horizontal overflow and resize scroll-arena failure are real
production defects. Desktop25 remained green. Helpers now scroll the proper tab
list before real taps; settings/resize production repairs and stricter absolute
screen-to-paper resize checks await the next SHA's CI. No callback shortcut.

Opened same-document5eb320 actual drag PNG3× and PDF: Arabic-word overlap in PDF
is repaired in this sample; **legacy native/PDF marks alignment is visibly NOT
parity** (edge vs inline). Legacy drag chrome still consumes print-row width.
Canonical candidate remains OFF; completing its anchored edit/drag equivalents
and full long-split/all-tools matrix is still required. Green targeted layout
checks cannot close that visual discrepancy or establish device rendering/IME.
