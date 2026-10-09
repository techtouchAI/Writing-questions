// [C6-EXPERIMENT] NOT FOR MERGE. Diagnostic only: quantizes a baseline (pt)
// to the whole 96-dpi device pixel grid, to test whether the residual is
// caused by renderer baseline rounding at fractional positions.
double c6SnapBaselinePt(double baselinePt) =>
    (baselinePt * 4 / 3).roundToDouble() * 3 / 4;
