import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/tex_content.dart';

void main() {
  group('TexContent.split', () {
    test('detects plain text without math', () {
      expect(TexContent.containsMath('نص عادي تماماً'), isFalse);
      expect(
        TexContent.split('نص عادي'),
        <TexSegment>[const TexSegment.plain('نص عادي')],
      );
    });

    test('splits inline math between text runs in order', () {
      final segments = TexContent.split(r'حل المعادلة $x^2+1$ بالتفصيل');

      expect(segments, hasLength(3));
      expect(segments[0], const TexSegment.plain('حل المعادلة '));
      expect(segments[1], const TexSegment.math('x^2+1'));
      expect(segments[2], const TexSegment.plain(' بالتفصيل'));
    });

    test('splits block math (\$\$...\$\$) as its own segment', () {
      final segments = TexContent.split(r'قبل' '\n' r'$$\frac{a}{b}$$' '\n' r'بعد');

      expect(segments, hasLength(3));
      expect(segments[0], const TexSegment.plain('قبل\n'));
      expect(segments[1], const TexSegment.math(r'\frac{a}{b}', isBlock: true));
      expect(segments[2], const TexSegment.plain('\nبعد'));
    });

    test('keeps escaped \$ literal instead of starting a formula', () {
      final segments = TexContent.split(r'السعر 5\$ فقط');

      expect(segments, hasLength(1));
      expect(segments.first.isMath, isFalse);
      expect(segments.first.text, r'السعر 5\$ فقط');
    });

    test('findSpans locates inline and block spans with source offsets', () {
      const source = r'حل $x^2$ ثم $$\frac{a}{b}$$ تم';
      final spans = TexContent.findSpans(source);

      expect(spans, hasLength(2));
      expect(spans[0].isBlock, isFalse);
      expect(spans[0].latex, 'x^2');
      expect(source.substring(spans[0].start, spans[0].end), r'$x^2$');
      expect(spans[1].isBlock, isTrue);
      expect(spans[1].latex, r'\frac{a}{b}');
      expect(source.substring(spans[1].start, spans[1].end), r'$$\frac{a}{b}$$');
    });

    test('findSpans ignores escaped dollars and maps offsets past them', () {
      const source = r'السعر 5\$ ثم $x$';
      final spans = TexContent.findSpans(source);

      expect(spans, hasLength(1));
      expect(spans.single.latex, 'x');
      expect(source.substring(spans.single.start, spans.single.end), r'$x$');
    });

    test('findSpans returns no spans for plain or empty text', () {
      expect(TexContent.findSpans('نص عادي'), isEmpty);
      expect(TexContent.findSpans(''), isEmpty);
      expect(TexContent.findSpans(r'\$'), isEmpty);
    });

    test('supports chemistry/physics formulas inline', () {
      final segments = TexContent.split(r'الصيغة $H_2O$ والقوة $F=ma$');

      expect(segments, hasLength(4));
      expect(segments[1], const TexSegment.math('H_2O'));
      expect(segments[3], const TexSegment.math('F=ma'));
      expect(TexContent.containsMath(r'$E=mc^2$'), isTrue);
    });
  });
}
