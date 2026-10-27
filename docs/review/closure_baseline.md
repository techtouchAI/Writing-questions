# Closure baseline — OPEN, no production activation

## Identity and transport

Initial local HEAD: `eab6c5a614654ae2e0096898c3ae3678138aed27`, on
`arena/8513fa6c-writing-questions`, with the persisted cumulative worktree patch.
Fetched only that same remote branch. Every file and blob matched tested
`0fa0c7b0d69ba25f54edc665ae9ccf7387e2dd01`; there were no additional untracked
files. A mixed reset aligned HEAD/index with that fetched history without
changing worktree bytes, switching branches, or force pushing.

Baseline run: https://github.com/techtouchAI/Writing-questions/actions/runs/40411056142

Full run log retrieval was attempted with `gh run view --log`; GitHub redirected
to results-receiver.actions.githubusercontent.com, which returned EOF in this
environment. **The complete archive was not obtained.** Checks annotations
were retrieved. They contain the entire analyzer output (four findings), the
single full-suite failure and separate targeted/gate counts. These are not
misrepresented as a complete raw run log.

Original production inventory: 57 originals; original Visual inventory: four
files (manifest, two preview pages, vector.pdf). Both were fetched through the
strict hash-checked transport, not screenshots of a CI summary. Manual image
inspection is a separate, not-yet-completed acceptance requirement.

## Proven results at the BASELINE, not new-code acceptance

- Production R1/R4: 8/0; native editor: 59/0.
- Full suite: 944/1; canonical gate: 3/0.
- Analyzer: **four infos, all fatal** under `--fatal-infos`:
  `prefer_const_constructors`, production_mixed_math_evidence_test.dart:290–293.
- APK **skipped** after the failed tests/analyzer. No APK acceptance.
- Visual **failed**: page1 header strip uncovered0.127@y72,x121..630,n123;
  content strip uncovered1.000@y864,x566..606,n240. Page2 content gate passed.
- C6 and Extended succeeded; neither establishes visual acceptance.
- Candidate OFF; no PR merge, deletion or production switch authorized.

## Repair diagnosis

### Option label movement

Unchanged failing test: `test/services/structured_export_test.dart`,
`PDF: الخيارات صناديق ثابتة العرض في سطر واحد / ثلاثة خيارات تشترك السطر والرابع يلتفّ، والعرض عرض العقد`.
Actual label pitch151.614pt, expected153pt±1.0. The grid itself has fixed190px
cells and14px spacing. `_layoutOptions` incorrectly shaped the label, spacer,
and content as one paragraph: changing Latin content width moved the label.
The real native `_buildPointOptions` is a Row with an intrinsic label, 6px gap
and Expanded content. Repair that shared layout representation, retaining the
original failing assertion, declared typography and existing models. Extract
the existing native1px label padding into the shared metrics contract rather
than adding a compensating translation. Add an independent content-change,
long-option/pagination and actual PDF anchor regression. No weaker assertion.

### Analyzer

Make the existing immutable diagnostic widget tree const. No analyzer ignores,
severity changes, skipped findings or dependency substitutions.

### Arabic shaping / Visual strip

Still under investigation. Same-font identity alone is not shaped-glyph
identity. Must inspect the matching actual preview/PDF pages before changing
BiDi, shaping, clipping, or coordinates. No threshold change authorized.

## Required remaining work

All new code must pass R1/R4 first, native targeted, unchanged full suite,
clean fatal-info analyze and **actual APK**; all final-SHA Actions followed.
Arabic header, Visual strip, same-document before/after inspection, drag/model/
export, asset/export races and exhaustive 320/360 editing inventory remain
open until specifically proved. This document is NOT a closure report.

### Visual content-strip cause proved from the opened paired page

The actual page1 originals were opened side-by-side. The uncovered y864
fraction has a visibly truncated PDF denominator, while BOTH paths still had
Ahem black blocks. Visual's `loadAppFonts` registered only paper fonts, not the
package KaTeX families already required by the production evidence harness.
Use that same generated-manifest loader here too; preserve the actual fonts
and record its inventory within the hashed Visual manifest.

Separate production geometry defect: FloatingElementView uses MathStyle.text,
2px padding and a centered FittedBox(contain). DocumentIR marked the formula
as display math, and `_layoutFloatLabel` used a start-aligned paragraph with
4px padding and no fit-to-height. This explains the clipped denominator
without blaming the gate or moving a clip. The shared plan now represents the
native text-style math and native centered fitted box, leaving original
snapshot font size/raster unchanged. Added actual-native-versus-plan geometry
regressions at320/360 (1e-6), including denominator containment. No gate
threshold or clip is altered. Arabic header shaping remains a separate defect.

## Follow-up `04704ef` / run40463115820

R1/R4 **8/0**, native **59/2**: the two NEW floating-fit regressions failed
before full validation (actual left61.50269 vs planned63.5750px); original
math/tail/source cases passed. The new harness incorrectly put its visible
formula directly under MaterialApp, inheriting WidgetsApp's bold debug style
(the previously established156px-vs140px problem), unlike production Scaffold.
Move only the test into the actual Scaffold context and explicitly assert
normal inherited weight; do not change production typography or precision.
Full/options/analyze/APK/Visual validation is not inferred from this red run.

Complete Flutter command logs will additionally be uploaded on both success
and failure, AFTER the build step. A separate allowlisted hash-checked transport
accounts explicitly for all six commands, marking skipped/unproduced logs as
`notProduced`, never as passed. This does not recover the inaccessible baseline
GitHub job/setup archive and is not described as that archive. Offline transport
regressions: **8/8**; diagnostic digest self-tests: **32/32**.
