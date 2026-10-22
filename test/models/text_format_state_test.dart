// حالة التنسيق الفعلية لمقطع نصّي — الأساس الذي تقرأ منه أزرار الشريط.
//
// القاعدة المعلنة: الزر يعكس **ما يراه المستخدم في التحديد** لا نمط العنصر.
// أي أن الحالة تُحسب لكل محرف داخل النطاق: خاصية النطاق إن وُجدت، وإلا خاصية
// العنصر. وإذا اختلفت القيم داخل النطاق فالنتيجة «مختلطة» (null) ولا تُنسب
// إلى إحدى القيمتين.
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/text_format_span.dart';

const int _red = 0xFFCC0000;
const int _navy = 0xFF1E3A8A;

void main() {
  group('stateForRange: الوراثة من نمط العنصر', () {
    test('بلا نطاقات: الحالة تساوي نمط العنصر', () {
      final state = TextFormatSpans.stateForRange(
        const <TextFormatSpan>[],
        start: 0,
        end: 4,
        baseBold: true,
        baseColor: _red,
      );
      expect(state.bold, isTrue);
      expect(state.italic, isFalse);
      expect(state.underline, isFalse);
      expect(state.color, _red);
      expect(state.colorMixed, isFalse);
    });

    test('نطاق صريح يتجاوز نمط العنصر في مقطعه', () {
      final state = TextFormatSpans.stateForRange(
        const <TextFormatSpan>[
          TextFormatSpan(start: 0, end: 4, bold: false, color: _navy),
        ],
        start: 0,
        end: 4,
        baseBold: true,
        baseColor: _red,
      );
      expect(state.bold, isFalse);
      expect(state.color, _navy);
    });

    test('مؤشر مطوي: الحالة عند النقطة بلا ادّعاء تحديد', () {
      final state = TextFormatSpans.stateForRange(
        const <TextFormatSpan>[
          TextFormatSpan(start: 4, end: 8, italic: true),
        ],
        start: 4,
        end: 4,
      );
      // لا محارف في النطاق ⇒ لا خاصية من النطاق، بل نمط العنصر.
      expect(state.italic, isFalse);
      expect(state.color, isNull);
    });
  });

  group('stateForRange: التحديد المختلط', () {
    test('كلمة عريضة وأخرى عادية داخل التحديد ⇒ bold مختلط (null)', () {
      final state = TextFormatSpans.stateForRange(
        const <TextFormatSpan>[
          TextFormatSpan(start: 0, end: 4, bold: true),
        ],
        start: 0,
        end: 9,
      );
      expect(state.bold, isNull);
      expect(state.isMixed, isTrue);
    });

    test('تحديد داخل الكلمة العريضة وحدها ⇒ bold صريح', () {
      final state = TextFormatSpans.stateForRange(
        const <TextFormatSpan>[
          TextFormatSpan(start: 0, end: 4, bold: true),
        ],
        start: 1,
        end: 3,
      );
      expect(state.bold, isTrue);
      expect(state.isMixed, isFalse);
    });

    test('لونان مختلفان داخل التحديد ⇒ colorMixed بلا لون واحد', () {
      final state = TextFormatSpans.stateForRange(
        const <TextFormatSpan>[
          TextFormatSpan(start: 0, end: 2, color: _red),
          TextFormatSpan(start: 2, end: 4, color: _navy),
        ],
        start: 0,
        end: 4,
      );
      expect(state.color, isNull);
      expect(state.colorMixed, isTrue);
    });

    test('لون واحد موحّد داخل التحديد ⇒ اللون نفسه', () {
      final state = TextFormatSpans.stateForRange(
        const <TextFormatSpan>[
          TextFormatSpan(start: 0, end: 4, color: _red),
        ],
        start: 0,
        end: 4,
      );
      expect(state.color, _red);
      expect(state.colorMixed, isFalse);
    });

    test('تحديد معكوس (من اليمين إلى اليسار) يُطبَّع', () {
      final forward = TextFormatSpans.stateForRange(
        const <TextFormatSpan>[
          TextFormatSpan(start: 0, end: 4, bold: true),
        ],
        start: 0,
        end: 4,
      );
      final reversed = TextFormatSpans.stateForRange(
        const <TextFormatSpan>[
          TextFormatSpan(start: 0, end: 4, bold: true),
        ],
        start: 4,
        end: 0,
      );
      expect(reversed, forward);
    });

    test('النطاق المتداخل: الخاصية القادمة من النطاق الداخلي تسود', () {
      final state = TextFormatSpans.stateForRange(
        const <TextFormatSpan>[
          TextFormatSpan(start: 0, end: 8, italic: true),
          TextFormatSpan(start: 4, end: 8, bold: true),
        ],
        start: 4,
        end: 8,
      );
      expect(state.italic, isTrue, reason: 'الميل الخارجي ضاع.');
      expect(state.bold, isTrue);
    });
  });

  group('انتقالات التحديد: لا بقايا بين الحالات', () {
    const spans = <TextFormatSpan>[
      TextFormatSpan(start: 0, end: 4, bold: true),
    ];
    TextFormatState? stateAt(int start, int end) => TextFormatSpans.stateForRange(
          spans,
          start: start,
          end: end,
        );

    test('عريض ⇒ عادي ⇒ مختلط ⇒ عريض', () {
      expect(stateAt(0, 4)!.bold, isTrue);
      expect(stateAt(5, 9)!.bold, isFalse);
      expect(stateAt(0, 9)!.bold, isNull);
      expect(stateAt(0, 4)!.bold, isTrue);
    });

    test('الحالة تُقارن بالقيَم فتصلح لكتم إعادة البناء بلا تغيير', () {
      expect(stateAt(0, 4), stateAt(0, 4));
      expect(stateAt(0, 4), isNot(stateAt(5, 9)));
      expect(stateAt(0, 9), isNot(stateAt(0, 4)));
    });
  });
}
