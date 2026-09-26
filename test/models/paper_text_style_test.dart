import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';

void main() {
  group('PaperTextStyle.color', () {
    test('defaults to null (inherits the sheet color)', () {
      expect(PaperTextStyle.empty.color, isNull);
      expect(PaperTextStyle.empty.colorHex, isNull);
      expect(PaperTextStyle.empty.isEmpty, isTrue);
    });

    test('exposes an uppercase RRGGBB hex for XML exporters', () {
      const style = PaperTextStyle(color: 0xFF1E3A8A);
      expect(style.colorHex, '1E3A8A');
      // قناة الألفا تُسقَط من سداسية XML.
      expect(const PaperTextStyle(color: 0x801E3A8A).colorHex, '1E3A8A');
    });

    test('round-trips through toMap/fromMap', () {
      const style = PaperTextStyle(color: 0xFFB91C1C, fontSize: 14);
      final restored = PaperTextStyle.fromMap(style.toMap());
      expect(restored, style);
      expect(restored.color, 0xFFB91C1C);
    });

    test('reads hex strings and tolerates corrupt values', () {
      expect(
        PaperTextStyle.fromMap(const <String, dynamic>{'color': '1E3A8A'}).color,
        0xFF1E3A8A,
      );
      expect(
        PaperTextStyle.fromMap(const <String, dynamic>{'color': '#B91C1C'}).color,
        0xFFB91C1C,
      );
      expect(
        PaperTextStyle.fromMap(const <String, dynamic>{'color': 'bogus'}).color,
        isNull,
      );
      expect(
        PaperTextStyle.fromMap(const <String, dynamic>{'color': -5}).color,
        isNull,
      );
      // مستندات قديمة بلا لون تبقى صالحة.
      expect(
        PaperTextStyle.fromMap(const <String, dynamic>{}).color,
        isNull,
      );
    });

    test('merges and copies with the function form', () {
      const base = PaperTextStyle(fontSize: 12);
      const overlay = PaperTextStyle(color: 0xFF15803D);
      expect(base.merge(overlay).color, 0xFF15803D);
      expect(base.merge(overlay).fontSize, 12);
      expect(overlay.merge(null), overlay);

      expect(
        overlay.copyWith(color: () => null).color,
        isNull,
      );
      expect(
        base.copyWith(color: () => 0xFF000000).color,
        0xFF000000,
      );
    });
  });
}
