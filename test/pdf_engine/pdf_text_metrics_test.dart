// PDF-side baseline mapping: the offset from a single-line text widget top to
// its emitted baseline must be deterministic, positive for real text, linear
// in font size, and zero for degenerate inputs. Correctness of the absolute
// placement is proven by the canonical/PDF parity tests in CI.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/pdf_text_metrics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PdfFont> loadRegular() async {
    final bytes = await rootBundle.load(ExamFonts.regularAsset);
    return PdfTtfFont(PdfDocument(), bytes);
  }

  test('baseline offset is positive and deterministic for Arabic text',
      () async {
    final font = await loadRegular();
    const text = 'السلام عليكم ورحمة الله';
    final first = PdfTextMetrics.baselineOffsetFromTop(
      font: font,
      fontSizePt: 11,
      text: text,
    );
    final second = PdfTextMetrics.baselineOffsetFromTop(
      font: font,
      fontSizePt: 11,
      text: text,
    );
    expect(first, greaterThan(0));
    expect(second, first);
  });

  test('baseline offset scales linearly with font size', () async {
    final font = await loadRegular();
    const text = 'Question 12 (10 marks) سؤال';
    final atEleven = PdfTextMetrics.baselineOffsetFromTop(
      font: font,
      fontSizePt: 11,
      text: text,
    );
    final atTwentyTwo = PdfTextMetrics.baselineOffsetFromTop(
      font: font,
      fontSizePt: 22,
      text: text,
    );
    expect(atEleven, greaterThan(0));
    expect(atTwentyTwo / atEleven, closeTo(2.0, 0.001));
  });

  test('baseline offset is zero for degenerate inputs', () async {
    final font = await loadRegular();
    expect(
      PdfTextMetrics.baselineOffsetFromTop(
        font: font,
        fontSizePt: 11,
        text: '',
      ),
      0,
    );
    expect(
      PdfTextMetrics.baselineOffsetFromTop(
        font: font,
        fontSizePt: 0,
        text: 'نص',
      ),
      0,
    );
  });
}
