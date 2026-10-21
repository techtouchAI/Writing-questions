// اختبارات طبقة تخزين تنسيق النطاقات — لا تعتمد على أي واجهة رسومية.
//
// الغرض: إثبات أن التنسيق يُطبَّق على **المقطع المحدَّد** وحده، وأن التداخل
// واللون الجزئي محفوظان، وأن السلوك عند غياب التحديد معلن لا اجتهادي.
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/text_format_span.dart';

void main() {
  group('تطبيق التنسيق على التحديد', () {
    const text = 'بسم الله الرحمن الرحيم';

    test('كلمة واحدة: التعريض يغطي الكلمة فقط', () {
      final word = TextFormatSpans.targetRange(text, start: 4, end: 8);
      expect(word, isNotNull);
      final spans = TextFormatSpans.apply(
        const <TextFormatSpan>[],
        TextFormatSpan(start: word!.start, end: word.end, bold: true),
        textLength: text.length,
      );
      expect(spans, hasLength(1));
      expect(spans.single.bold, isTrue);
      expect(spans.single.start, 4);
      expect(spans.single.end, 8);
      // المحارف الأخرى بلا نطاق = ترث نمط العنصر كما هو.
      expect(
        TextFormatSpans.attributeAt(spans, 0),
        isNull,
        reason: 'التنسيق تسرّب خارج كلمة التحديد.',
      );
    });

    test('جملة كاملة: نطاق واحد يغطي النص كله', () {
      final spans = TextFormatSpans.apply(
        const <TextFormatSpan>[],
        const TextFormatSpan(start: 0, end: 22, underline: true),
        textLength: text.length,
      );
      expect(spans.single.start, 0);
      expect(spans.single.end, text.length);
      expect(spans.single.underline, isTrue);
    });

    test('تلوين جزئي يحفظ الألوان الأخرى خارج التحديد', () {
      var spans = TextFormatSpans.apply(
        const <TextFormatSpan>[],
        const TextFormatSpan(start: 0, end: 8, color: 0xFFFF0000),
        textLength: text.length,
      );
      spans = TextFormatSpans.apply(
        spans,
        const TextFormatSpan(start: 4, end: 8, color: 0xFF0000FF),
        textLength: text.length,
      );
      expect(spans, hasLength(2));
      expect(spans[0].color, 0xFFFF0000);
      expect(spans[0].start, 0);
      expect(spans[0].end, 4);
      expect(spans[1].color, 0xFF0000FF);
      expect(spans[1].start, 4);
      expect(spans[1].end, 8);
      // ما بعد التحديد لا نطاق له ⇒ يرث اللون الافتراضي.
      expect(TextFormatSpans.attributeAt(spans, 12), isNull);
    });

    test('التداخل لا يمحو التنسيق الخارجي (عريض داخل مائل)', () {
      var spans = TextFormatSpans.apply(
        const <TextFormatSpan>[],
        const TextFormatSpan(start: 0, end: 22, italic: true),
        textLength: text.length,
      );
      spans = TextFormatSpans.apply(
        spans,
        const TextFormatSpan(start: 4, end: 8, bold: true),
        textLength: text.length,
      );
      expect(spans, hasLength(3));
      expect(spans[0].italic, isTrue);
      expect(spans[0].bold, isNull);
      expect(spans[1].italic, isTrue);
      expect(spans[1].bold, isTrue);
      expect(spans[2].italic, isTrue);
      expect(spans[2].bold, isNull);
    });

    test('إزالة خاصية من نطاق تُبقي بقية الخصائص', () {
      var spans = TextFormatSpans.apply(
        const <TextFormatSpan>[],
        const TextFormatSpan(
          start: 0,
          end: 8,
          bold: true,
          color: 0xFF00FF00,
        ),
        textLength: text.length,
      );
      spans = TextFormatSpans.clear(
        spans,
        start: 4,
        end: 8,
        color: true,
        textLength: text.length,
      );
      expect(spans, hasLength(2));
      expect(spans[0].color, 0xFF00FF00);
      expect(spans[0].bold, isTrue);
      expect(spans[1].color, isNull);
      expect(spans[1].bold, isTrue,
          reason: 'إزالة اللون لا يجوز أن تمحو التعريض.');
    });

    test('النطاقات تبقى مرتّبة وغير متداخلة بعد أي عملية', () {
      var spans = const <TextFormatSpan>[
        TextFormatSpan(start: 6, end: 12, italic: true),
        TextFormatSpan(start: 0, end: 4, bold: true),
        TextFormatSpan(start: 2, end: 9, underline: true),
      ];
      spans = TextFormatSpans.normalize(spans, textLength: text.length);
      for (var index = 0; index + 1 < spans.length; index++) {
        expect(spans[index].end, lessThanOrEqualTo(spans[index + 1].start),
            reason: 'نطاقان متداخلان في المخرجات: $spans');
      }
    });
  });

  group('غياب التحديد', () {
    const text = 'بسم الله الرحمن الرحيم';

    test('المؤشر المطوي ينسّق الكلمة التي عليها فقط', () {
      final range = TextFormatSpans.targetRange(text, start: 5, end: 5);
      expect(range, isNotNull);
      expect(range!.start, 4);
      expect(range.end, 8);
      expect(range.length, 4);
    });

    test('نص فارغ: لا نطاق إطلاقًا (لا تنسيق للسؤال كله)', () {
      expect(
        TextFormatSpans.targetRange('', start: 0, end: 0),
        isNull,
      );
    });

    test('تحديد معكوس (من اليسار إلى اليمين) يُطبَّع', () {
      final range = TextFormatSpans.targetRange(text, start: 8, end: 4);
      expect(range!.start, 4);
      expect(range.end, 8);
    });
  });

  group('إعادة تأسيس الإزاحات بعد تحرير النص', () {
    test('إدخال في البداية يزيح النطاق ولا يمدّه', () {
      final rebased = TextFormatSpans.rebase(
        const <TextFormatSpan>[TextFormatSpan(start: 4, end: 8, bold: true)],
        previous: 'بسم الله',
        next: 'xxبسم الله',
      );
      expect(rebased.single.start, 6);
      expect(rebased.single.end, 10);
    });

    test('حذف قبل النطاق يُقلّص الإزاحة', () {
      final rebased = TextFormatSpans.rebase(
        const <TextFormatSpan>[TextFormatSpan(start: 4, end: 8, bold: true)],
        previous: 'بسم الله',
        next: 'سم الله',
      );
      // «بسم الله» ← «سم الله»: النطاق كان «الله» [4,8) فصار [3,7).
      expect(rebased.single.start, 3);
      expect(rebased.single.end, 7);
    });

    test('الكتابة داخل النطاق لا توسّعه على النص الجديد', () {
      final rebased = TextFormatSpans.rebase(
        const <TextFormatSpan>[TextFormatSpan(start: 4, end: 8, bold: true)],
        previous: 'بسم الله',
        next: 'بسم الشيء الله',
      );
      // «الله» صارت «الشيء الله»: الجزء القديم «ال» يبقى [4,6)، والبقية
      // «له» تنتقل إلى [12,14) — والنص المُدخل نفسه يبقى بلا تنسيق.
      expect(rebased, hasLength(2), reason: '$rebased');
      expect(rebased[0].start, 4);
      expect(rebased[0].end, 6);
      expect(rebased[1].start, 12);
      expect(rebased[1].end, 14);
      for (final span in rebased) {
        expect(span.bold, isTrue, reason: 'التنسيق ضاع عند الكتابة داخل الكلمة.');
      }
      // النص المُدخل (بين 6 و12) بلا تعريض.
      expect(TextFormatSpans.attributeAt(rebased, 8)?.bold, isNot(isTrue));
    });
  });

  group('التخزين والتوافق', () {
    test('نطاقات السؤال تعود كما هي بعد الحفظ والتحميل', () {
      final question = QuestionModel(
        id: 'q1',
        questionNumber: 1,
        statement: 'اختر الإجابة الصحيحة',
        body: 'اقرأ ثم أجب',
        statementFormats: const <TextFormatSpan>[
          TextFormatSpan(start: 0, end: 4, bold: true, color: 0xFF112233),
        ],
        bodyFormats: const <TextFormatSpan>[
          TextFormatSpan(start: 5, end: 8, italic: true, underline: true),
        ],
      );
      final restored = QuestionModel.fromMap(question.toMap());
      expect(restored.statementFormats, question.statementFormats);
      expect(restored.bodyFormats, question.bodyFormats);
      expect(restored.statementFormats.single.color, 0xFF112233);
    });

    test('مستند قديم بلا نطاقات يُقرأ بقوائم فارغة', () {
      final legacy = QuestionModel(
        questionNumber: 1,
        branches: <BranchModel>[],
        statement: 'نص قديم',
      ).toMap();
      expect(legacy.containsKey('statementFormats'), isFalse);
      final restored = QuestionModel.fromMap(legacy);
      expect(restored.statementFormats, isEmpty);
      expect(restored.bodyFormats, isEmpty);
    });

    test('نطاقات تالفة في التخزين تُهمل ولا تُسقط المستند', () {
      final map = QuestionModel(
        questionNumber: 1,
        branches: <BranchModel>[],
        statement: 'نص',
      ).toMap();
      map['statementFormats'] = <Object?>[
        <String, Object?>{'start': 'x', 'end': 3, 'bold': true},
        <String, Object?>{'start': 3, 'end': 1, 'bold': true},
        'ليست خريطة',
      ];
      final restored = QuestionModel.fromMap(map);
      expect(restored.statementFormats, isEmpty);
      expect(restored.statement, 'نص');
    });

    test('تنسيق الفرع يعود كما هو بعد الحفظ والتحميل', () {
      final content = BranchContent(
        statement: 'اشرح',
        body: 'بالتفصيل',
        statementFormats: const <TextFormatSpan>[
          TextFormatSpan(start: 0, end: 2, underline: true),
        ],
      );
      final restored = BranchContent.fromMap(content.toMap());
      expect(restored.statementFormats, content.statementFormats);
    });
  });

  group('قصّ النص المشذّب', () {
    test('الفراغات الطرفية لا تُزيح النطاق عن محرفه', () {
      final spans = TextFormatSpans.forTrimmed(
        const <TextFormatSpan>[TextFormatSpan(start: 3, end: 7, bold: true)],
        '   بسم الله  ',
      );
      expect(spans.single.start, 0);
      expect(spans.single.end, 4);
      // النص المشذّب: «بسم الله» — النطاق يغطي «بسم» كما حدّده المدرس.
      expect('   بسم الله  '.trim().substring(0, 4), 'بسم ');
    });
  });
}
