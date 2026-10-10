# C6 visual parity: findings and blockers

Status: **C6 is blocked.** The Vector PDF gate is still red and no fix has been approved.

- Gate: Vector PDF RMSE against the canonical Preview must be ≤ 0.02 on every gated page. Exact-PDF must stay at 0.
- Official CI result on `main` (run `37862672149`): page 1 = 0.0750014, page 2 = 0.079265. Both fail. Exact-PDF = 0. Exact-Word = 0.0608117 / 0.0688867 (limit 0.12, passes).
- Threshold, Poppler, and expected images are unchanged. No gate has been relaxed.

This file records what was measured, what is still a hypothesis, and which decisions need approval. Probe code is in git history, not in the tree: commits `15d8c60` (round 1) and `8d19e90` (round 2, which fixed the italic probe and added the no-host condition). The earlier italic numbers in `15d8c60` are invalid and were replaced in `8d19e90`.

## 1. Math raster contract (measured)

The gate's test contract decides whether math is rasterised. Three conditions were measured with the production `PdfMathRasters.rasterize`:

| Condition | Math rasters (of 6) | Pumps to finish |
|---|---|---|
| Gate contract: no `MathSnapshotHost` (`main`) | 0 | 1 (every formula falls back to text) |
| Host mounted, pump-only driver | 0 | never (400 pumps, not done) |
| Host mounted, pump plus one real event turn per pump (`e2a1483`) | 6 | 4 |

Conclusions:

- `main`'s baseline (0.0750) measures math as text fallback on the PDF side. The production app mounts the host (`lib/main.dart`), so this baseline does not exercise production's math raster path.
- The reapplied contract (0.0676) is the only one that rasterises math. Its yield is needed under fake async, because PNG encoding needs a real event turn. The yield is a harness necessity, not a product behaviour. Whether its output is byte-identical to a real-async run is **not yet measured**.
- The Preview side's math path in the gate is **not measured** by these probes.
- **Verdict:** the 0.0676 result is not like-for-like with 0.0750. Do not switch the contract on it. The baseline stays until the two open checks above are measured and the user decides.

## 2. Italic (measured, study only, no PDF change)

- The PDF output is identical with and without italic: RMSE 0.000000 for both Latin lines. The vendored PDF engine ignores the italic flag, and no italic face is bundled.
- The Preview does slant. Upright vs italic Preview RMSE: 0.1078 (`lat_a`), 0.1056 (`lat_b`), 0.0510 (Arabic), 0.0516 (mixed). Ink ratio stays within 0.95–1.02.
- Control: even upright text, with no italic and no math, differs between PDF and Preview by RMSE 0.0624 (`lat_a`) and 0.1185 (`lat_b`) after centroid alignment. This includes misregistration, which this probe cannot separate from rendering differences.
- **Not measured:** the page-level share of the italic gap. The probe cannot isolate it, and the italic gap is the same size as the upright registration noise.
- The row-centroid slant metric is unreliable on real text, so it is not used.

## 3. Floating frames and clipping (measured)

Root cause: `SvgImage` in the vendored `pdf` package defaults to `clip: true`. Clipping cuts the outer half of a centred stroke. The production square shape also insets its rectangle by `stroke/2`, so the frame is offset as well.

Box SSE by variant (lower is better), at `stroke = 1.0 pt`, positions p0 / p1 / p2 / p3:

| Variant | p0 | p1 | p2 | p3 |
|---|---|---|---|---|
| Production `shapeToSvg` (inset, clip default) | 361.6 | 487.2 | 338.3 | 212.1 |
| Full-box, clip default | 107.5 | 106.1 | 198.0 | 199.6 |
| Full-box, `clip: false` (keeps `#111827`, white fill) | 48.8 | 50.8 | 48.4 | 47.3 |
| `pw.Border.all` (black, no fill) | 66.2 | 47.0 | 72.8 | 93.2 |

At `stroke = 2.0 pt`:

| Variant | p0 | p1 | p2 | p3 |
|---|---|---|---|---|
| Production `shapeToSvg` (inset, clip default) | 899.5 | 883.0 | 924.8 | 940.3 |
| Full-box, clip default | 390.9 | 381.6 | 493.1 | 502.7 |
| Full-box, `clip: false` | 62.0 | 32.5 | 72.0 | 102.7 |
| `pw.Border.all` | 66.3 | 46.4 | 73.2 | 94.3 |

- Production edge offsets at 2.0 pt, p0: +1.50 / −1.50 / +1.38 / −1.13 px (left, right, top, bottom). With `clip: false`: about 0.
- Thickness ratio at 2.0 pt, p0: production 0.93, clip default 0.52 (outer half cut), `clip: false` 0.85.
- The approved geometry-only fix (`70edaf5`, inset removed, clip still default) halved the stroke and gave SSE 359. That matches the clip-default rows above.
- Full-box with `clip: false` matches `pw.Border.all` in fidelity while keeping the existing colour and white fill.
- Colour (`#111827` vs black) has no consistent cost. `#111827` had lower SSE in 6 of 8 cases. The reason is not established.
- Page-level bound (earlier C8 analysis): excluding the framed float entirely moves page 1 from 0.0749 to 0.0681. The frame can contribute at most about 0.007 of the 0.0749 gap.

## 4. Occlusion mismatch (measured, new finding)

- Production shapes (`shapeToSvg` square and rectangle) are filled white by default (`filled: true`).
- The Preview's `_paintShape` is stroke-only, with no fill.
- With a black block under the shape (`stroke 1.0`, p0): PDF interior ink = 0.000 (the white fill hides it) for all SVG variants. Preview = 1.000 (visible). `pw.Border.all` (no fill) = 1.000. Box SSE 8170–8482 for SVG variants vs 94.7 for the border variant.
- This matters only where a floating shape overlaps other content. Its effect on the gated fixture is not measured.

## 5. Text residual (hypothesis, not solved)

- The remaining gap is concentrated in text: 74–82% of page 1 SSE and essentially all of page 2 SSE (from the earlier C8 analysis).
- Hypothesis: a rasteriser and glyph-placement difference between Flutter and Poppler. This is consistent with the measured control floor in section 2, but not proven. Sub-pixel registration has not been tested.

## 6. Decisions needed

1. **Contract.** Keep the `main` baseline (0.0750), or adopt the reapplied contract (0.0676, not like-for-like). Recommendation: keep the baseline until the Preview-side math path and the real-async equivalence check are measured. Requires approval to change the test contract.
2. **Frame fix (P-A).** Add `clip: false` at the production shape call site (`lib/pdf_engine/floating_elements_pdf.dart`), keeping the approved geometry fix. Changes PDF output. Expected page gain ≤ 0.007. Needs approval.
3. **Occlusion (P-B).** Remove the PDF shape fill (PDF change), or add a fill to the Preview (Preview change, separate approval). Needs a decision.
4. **Text residual.** Requires a sub-pixel registration probe, or acceptance that C6 cannot close without a larger change. A threshold change is not an option.
5. **Italic.** Study only. Fixing it means adding an italic face or synthetic oblique to the PDF, which is a PDF change and needs separate approval.
6. **Release.** No production keystore exists. The CI APK is debug-signed. No release, store upload, or merge has been done.

## 7. Recommendation

C6 cannot be closed by the frame fix alone. Its maximum page-level gain is about 0.007 against a 0.05–0.06 gap that is mostly text. Report C6 as blocked. Do not claim a visual match. Decide on items 1–3 before implementing any change.

## 8. Frame fix on the gate (measured, CI)

Official gate results, page 1 / page 2 Vector PDF RMSE (ceiling 0.02):

| Commit | Change | Page 1 | Page 2 |
|---|---|---|---|
| `main` | baseline | 0.0750014 | 0.079265 |
| `70edaf5` | inset removed (geometry only) | 0.0711328 | 0.079265 |
| `c7f5f26` | plus `clip: false` on the `SvgImage` | 0.0711328 | 0.079265 |
| `77f47f4` | plus wrapper `overflow` visible for generated square/rectangle frames | 0.0683264 | 0.079265 |

Both pages still FAIL. Exact-PDF 0 on both pages. Exact-Word 0.0608117 / 0.0688867 (OK). Analyze, test and build APK succeeded on `77f47f4` (run `38043681973`). The `clip: false` change alone did nothing on the gate. The cause was the wrapper, not the `SvgImage`.

Root cause of the no-change result: `CanonicalLayoutPdfPainter` wraps each floating element in `pw.Stack(overflow: pw.Overflow.clip)`. That clip cut the outer half of the stroke whatever the `SvgImage` flag was. `FloatingElementsPdf.build` has no callers in `lib`. Its tests cover dead code, so the live fix is tested through `svgClipsToBox` and `centredFrameOverflows`.

Rendered edge ink at 96 dpi, page 1 frame (px per edge, from the gate's PNGs):

| Image | left | right | top | bottom |
|---|---|---|---|---|
| Preview (Flutter, antialiased) | 2.66 | 2.66 | 2.86 | 2.75 |
| Vector PDF, `c7f5f26` | 0.90 | 1.01 | 1.94 | 1.79 |
| Vector PDF, `77f47f4` | 1.79 | 1.79 | 2.72 | 2.69 |

The PDF trace (`tool/diag_c6_pdf_frame.py`, run `38044063653`) finds no clip active on the frame's fill or stroke, and no image drawn over the frame. So the remaining vertical thinning is not a clip.

Poppler probe (the gate's `pdftoppm`, isolated frame at the fixture's geometry, run `38044421042`), px per edge:

| Case | left | right | top | bottom |
|---|---|---|---|---|
| 2 pt centred stroke (production shape) | 2.00 | 2.00 | 3.00 | 3.00 |
| Same ring as filled even-odd outline | 2.71 | 2.71 | 2.78 | 2.78 |

Poppler snaps stroked rectangle edges to whole pixels. The stroke is therefore 0.7 px thin on the vertical edges and off on the horizontal ones. The filled ring is within about 0.1 px of the Preview on every edge. This is a measured candidate, not yet a change. It would alter how the frame is emitted in the PDF (content only; no Preview or expected-image change). It needs approval before implementation, and a gate run afterwards.

Status: the frame is mostly accounted for. Page 1 (0.0683) is close to the earlier "framed float excluded" value (0.0681). The remaining gap is the text residual (section 5). C6 remains BLOCKED.

## 9. Whole-page variants on the gate's pipeline (measured, CI)

Run `38050338004` (commit `4eb6767`). The gate's Vector PDF is re-rendered with `pdftoppm -r 96`, resized to 794x1123, cropped 2 px, and compared with `compare -metric RMSE`. The base reproduces the gate exactly (p1 0.0683264, p2 0.079265). Diagnostic copies only; no production change. Script: `tool/diag_c6_variants.py`.

| Variant | Page 1 RMSE | Delta | Page 2 RMSE | Delta |
|---|---|---|---|---|
| base (`77f47f4` output) | 0.0683264 | — | 0.0792650 | — |
| frame stroke as filled even-odd ring (page 1 frame only; page 2 has no frame) | 0.0680394 | −0.0002870 | 0.0792650 | 0 (control) |
| whole page shift x −0.50 pt | 0.0821047 | +0.0137783 | 0.1239410 | +0.0446760 |
| shift x −0.25 | 0.0741713 | +0.0058449 | 0.0983627 | +0.0190977 |
| shift x +0.25 | 0.0697469 | +0.0014205 | 0.0793495 | +0.0000845 |
| shift x +0.50 | 0.0764797 | +0.0081533 | 0.1005340 | +0.0212690 |
| shift y −0.50 | 0.0930992 | +0.0247728 | 0.1318110 | +0.0525460 |
| shift y −0.25 | 0.0708284 | +0.0025020 | 0.0756405 | −0.0036245 |
| shift y +0.25 | 0.0749152 | +0.0065888 | 0.0792650 | 0 |
| shift y +0.50 | 0.0966097 | +0.0282833 | 0.1431470 | +0.0638820 |

Frame edge ink, page 1 (px): base 1.79 / 1.79 / 2.83 / 2.69 (left, right, top, bottom); ring 2.42 / 2.42 / 2.63 / 2.49; Preview 2.66 / 2.66 / 2.86 / 2.75.

Findings (measured):
- The frame's content encoding is a closed `m/l/h` path, stroked with `2 w 1 J 1 j` under a flipped CTM. It is not a `re` operator. The trace found no clip or image over it.
- The ring moves the vertical edges toward the Preview, but the page gain is −0.0003. The frame is not the limiting factor. Page 2 has no frame and is unchanged. The ring is not recommended as a standalone change.
- Translation does not explain the gap. Page 1 is at its minimum with no shift. Shifts of ±0.25 pt add at most +0.007. Page 2 improves by 0.0036 at y −0.25 pt. That is the best point on this grid, but the page is still far from 0.02. It is not applied, because a fitted offset is not a fix.
- The RMSE surface is shallow around zero (≤0.007 for ±0.25 pt). The residual of about 0.06 is therefore shape-level, not registration. Likely candidates are glyph rasterisation and antialiasing differences between Poppler and the Flutter Preview. This is a hypothesis, not measured directly.
- Limitation: the shift probe moves the whole page, including the frame, images and text. A text-only isolation would need content filtering, which has not been done.

Status: C6 remains BLOCKED. The official gate is red (page 1 0.0683264, page 2 0.079265).
