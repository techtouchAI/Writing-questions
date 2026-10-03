/// Structural text direction metadata for semantic document content.
///
/// This is independent of Flutter, PDF, and OOXML. `auto` lets a node describe
/// mixed-script content without embedding bidi controls; `inherit` leaves the
/// resolution to its containing semantic block.
enum DocumentDirection { rtl, ltr, auto, inherit }
