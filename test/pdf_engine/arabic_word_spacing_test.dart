// اختبارات مسافات الكلمات العربية في مخرجات PDF.
//
// المنهج: لا نفحص الشيفرة الداخلية، بل **نقيس الملف الناتج** — نرسم أسطراً
// معروفة داخل مستند PDF بنفس إعدادات محرك الاختبار (RTL + خط Noto Naskh)،
// ثم نقرأ من الملف نفسه موضع كل كلمة (Td) وعرض تقدّمها (من مصفوفة /W في
// الملف)، ونتأكد أن الفجوة بين كل كلمتين متجاورتين تساوي عرض المسافة المصمّمة
// في الخط (U+0020) لا أقل منها.
//
// قبل إصلاح انعكاس الكلمات RTL في مكتبة pdf (3.11.3) كانت هذه الاختبارات
// تفشل: كان موضع الكلمة يُحسب بعرض الحبر (metrics.width) بدل عرض التقدّم
// (advanceWidth)، فتُسرق مسافة كاملة تقريباً من كل فراغ وتظهر الكلمات ملتصقة
// مثل "تدورالأرض" (والفجوة المقيسة أقل من نصف المسافة المصمّمة).
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:writing_questions_app/pdf_engine/pdf_engine.dart';

import 'pdf_content_probe.dart';

/// النصوص الثلاثة التي أبلغ عنها المستخدم.
const String _spinningEarth = 'تدور الأرض';
const String _circularOrbit = 'مدار دائري';
const String _electricCurrent = 'التيار الكهربائي';

/// الحروف التي تُختبر بعد كلمة تنتهي بالراء (وعند غيره أيضاً).
const List<String> _arabicLetters = <String>[
  'ا', 'ب', 'ت', 'ث', 'ج', 'ح', 'خ', 'د', 'ذ', 'ر', 'ز', 'س', 'ش', 'ص',
  'ض', 'ط', 'ظ', 'ع', 'غ', 'ف', 'ق', 'ك', 'ل', 'م', 'ن', 'ه', 'و', 'ي',
];

/// كلمات أولى تنتهي بالراء (المشكلة المُبلَّغ عنها).
const List<String> _firstWords = <String>['تدور', 'مدار', 'التيار'];

/// كلمات أولى لا تنتهي بالراء (للتأكد أن الإصلاح عام لا خاص بالراء).
const List<String> _otherFirstWords = <String>[
  'الشمس',
  'التلميذ',
  'المدرسة',
  'الكتاب',
  'الطالب',
];

/// أنواع المسافات اليونيكودية المُختبرة. U+0020 هي المسافة التي يكتبها
/// التطبيق في كل نصوصه، و U+00A0 تُختبر للتأكد من أن المكتبة تعاملها بنفس
/// الطريقة (الاثنتان موجودتان في الخط بنفس العرض 0.221 em، وكلتاهما داخل
/// مجموعة الفراغات التي يقسم عليها package:pdf الكلمات).
const Map<String, String> _spaceKinds = <String, String>{
  'U+0020 (المسافة القياسية)': ' ',
  'U+00A0 (مسافة غير قابلة للفصل)': '\u00A0',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ByteData regularFontData;
  late ByteData boldFontData;
  late Future<ExamFonts> fontsFuture;

  /// أصغر عرض مسافة ممكن عند حجم خط معيّن: نأخذ الأصغر بين الخط العادي
  /// والعريض حتى لا يعتمد التأكيد على أي منهما (وكلاهما ٢٢١/١٠٠٠ من الوحدة).
  double minimumSpaceAdvance(double fontSize) {
    final regular = spaceAdvanceFor(regularFontData, fontSize);
    final bold = spaceAdvanceFor(boldFontData, fontSize);
    return regular < bold ? regular : bold;
  }

  /// يرسم كل سطر داخل مستند PDF واحد بنفس إعدادات محرك الاختبار (RTL + نفس
  /// الخط) ثم يعيد قارئ المحتوى لقياس ما رُسم فعلاً في الملف.
  Future<PdfContentProbe> renderLines(
    List<String> lines, {
    double fontSize = 11,
    double lineSpacing = 1.5,
  }) async {
    final fonts = await fontsFuture;
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(PaginatedPdfExamEngine.pageMarginMillimeters),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: <pw.Widget>[
            for (final line in lines)
              pw.Text(
                line,
                style: pw.TextStyle(fontSize: fontSize, lineSpacing: lineSpacing),
              ),
          ],
        ),
      ),
    );
    return PdfContentProbe.fromBytes(await document.save());
  }

  /// يتحقق من أن كل فجوة بين كلمتين متجاورتين فعلاً في السطر تساوي عرض
  /// المسافة المصمّمة، ويعيد عدد الأزواج التي قِيست (للتأكد من أن الاختبار
  /// قاس فعلاً شيئاً ولم يتخطَّ كل الأزواج).
  int expectFullSpaces(ProbedLine line, String text) {
    expect(
      line.fontSize,
      11.0,
      reason: 'حجم الخط المتوقع من أمر Tf — ${line.describe()}',
    );
    final expected = minimumSpaceAdvance(line.fontSize);
    var measured = 0;
    for (final index in line.adjacencyIndices) {
      measured++;
      expect(
        line.gapAfter(index),
        closeTo(expected, 0.05),
        reason: 'السطر "$text": الفجوة بين "${line.words[index].text}" و '
            '"${line.words[index + 1].text}" لا تساوي عرض المسافة '
            '(${expected.toStringAsFixed(3)} نقطة عند ${line.fontSize}).\n'
            'كل الفجوات المقيسة: '
            '${line.gaps.map((gap) => gap.toStringAsFixed(3)).toList()}\n'
            'الكلمات المرسومة: ${line.describe()}',
      );
    }
    return measured;
  }

  setUpAll(() async {
    fontsFuture = ExamFonts.load();
    regularFontData = await rootBundle.load(ExamFonts.regularAsset);
    boldFontData = await rootBundle.load(ExamFonts.boldAsset);
  });

  group('مسافة الكلمات العربية في ملف PDF', () {
    test('النصوص المُبلَّغ عنها تحتفظ بمسافة كاملة بين الكلمات', () async {
      const lines = <String>[_spinningEarth, _circularOrbit, _electricCurrent];
      final probe = await renderLines(lines);
      expect(
        probe.lines.length,
        lines.length,
        reason: 'يجب أن يكون كل نص في سطر واحد غير ملفوف — '
            'الأسطر المقيسة: ${probe.lines.map((l) => l.describe()).toList()}',
      );

      for (var index = 0; index < lines.length; index++) {
        final line = probe.lines[index];
        expect(line.words.length, 2, reason: line.describe());
        expect(expectFullSpaces(line, lines[index]), 1,
            reason: 'السطر "${lines[index]}" يجب أن يُقاس فيه زوج واحد — '
                '${line.describe()}');
      }
    });

    test('المسافة لا تعتمد على الكلمة السابقة: كلمات تنتهي بالراء + كل الحروف',
        () async {
      // لكل زوج (X، Y) نرسم سطرين:
      //   "X Y" : الحالة المُختبرة
      //   "Y Y" : سطر معايرة لا يعتمد على شكل الكلمة الأولى
      // المسافة بين الكلمتين كمية ثابتة من الخط، فيجب أن تتساوى في السطرين
      // تماماً بغض النظر عن الكلمة الأولى (حتى لو انتهت بالراء).
      final tested = <String>[];
      final calibration = <String>[];
      for (final first in _firstWords) {
        for (final letter in _arabicLetters) {
          final second = '$letterب';
          tested.add('$first $second');
          calibration.add('$second $second');
        }
      }

      // نرسم على دفعات حتى تبقى كل صفحة داخل حدودها.
      const pairsPerBatch = 8;
      for (var start = 0; start < tested.length; start += pairsPerBatch) {
        final end =
            (start + pairsPerBatch) > tested.length ? tested.length : start + pairsPerBatch;
        final batchLines = <String>[];
        for (var index = start; index < end; index++) {
          batchLines.add(tested[index]);
          batchLines.add(calibration[index]);
        }
        final probe = await renderLines(batchLines);
        expect(
          probe.lines.length,
          batchLines.length,
          reason: 'عدد الأسطر المقيسة لا يطابق المرسومة — '
              'المُقاس: ${probe.lines.map((l) => l.describe()).toList()}',
        );

        for (var index = start; index < end; index++) {
          final offset = (index - start) * 2;
          final testedLine = probe.lines[offset];
          final calibrationLine = probe.lines[offset + 1];
          expect(testedLine.words.length, 2, reason: testedLine.describe());
          expect(calibrationLine.words.length, 2,
              reason: calibrationLine.describe());

          final distance = testedLine.words[0].x - testedLine.words[1].x;
          final calibrationDistance =
              calibrationLine.words[0].x - calibrationLine.words[1].x;

          expect(
            distance,
            closeTo(calibrationDistance, 0.05),
            reason: 'المسافة بين كلمتي "${tested[index]}" = '
                '${distance.toStringAsFixed(3)} نقطة، وبين كلمتي سطر المعايرة '
                '"${calibration[index]}" = ${calibrationDistance.toStringAsFixed(3)} '
                'نقطة. يجب أن تتساويا لأن مسافة الكلمة كمية ثابتة من الخط.\n'
                'المُقاس: ${testedLine.describe()}',
          );

          expect(
            expectFullSpaces(testedLine, tested[index]) +
                expectFullSpaces(calibrationLine, calibration[index]),
            2,
            reason: 'سطرا "${tested[index]}" و"${calibration[index]}" '
                'يجب أن يُقاس فيهما زوج واحد لكل سطر',
          );
        }
      }
    });

    test('كلمات لا تنتهي بحرف الراء تحتفظ أيضاً بالمسافة الكاملة', () async {
      final lines = <String>[
        for (final first in _otherFirstWords) '$first $first',
        'الشمس تشرق كل صباح',
        'التلميذ يقرأ الكتاب',
        'المدرسة قريبة من البيت',
        'تدور $_circularOrbit',
      ];
      final probe = await renderLines(lines);
      expect(probe.lines.length, lines.length);

      var measured = 0;
      for (var index = 0; index < lines.length; index++) {
        measured += expectFullSpaces(probe.lines[index], lines[index]);
      }
      expect(measured, greaterThanOrEqualTo(11),
          reason: 'عدد الأزواج المقيسة في هذا الاختبار');
    });

    test('الالتفاف والأسئلة متعددة الأسطر تحافظ على المسافة في كل سطر', () async {
      const longSentence =
          'تدور الأرض حول الشمس دورة كاملة كل سنة، ويميل محورها فينتج عن ذلك '
          'تعاقب الفصول الأربعة على سطح الكرة الأرضية، ويستغرق مدار كل كوكب '
          'زمنًا مختلفًا عن الآخر في أثناء دورانه المستمر.';
      final probe = await renderLines(const <String>[longSentence]);

      expect(
        probe.lines.length,
        greaterThan(1),
        reason: 'يجب أن يلتف النص الطويل على أكثر من سطر، '
            'فالالتفاف هو ما يجعل الخلل يظهر في أكثر من موضع.',
      );
      var measured = 0;
      for (final line in probe.lines) {
        measured += expectFullSpaces(line, 'سطر من النص الطويل');
      }
      expect(
        measured,
        greaterThan(10),
        reason: 'يجب أن يُقاس عدد معتبر من الأزواج داخل أسطر النص الملفوف',
      );
    });

    test('النصوص المختلطة (عربي/إنجليزي/أرقام/ترقيم) لا تفقد مسافاتها', () async {
      const lines = <String>[
        'الدرس 2 من الكتاب',
        'المعادلة x + y = 5',
        'تدور الأرض 365 يومًا حول الشمس',
        'قال المعلم: إن العلم نور',
        'اقرأ الفقرة ثم أجب عن السؤال',
      ];
      final probe = await renderLines(lines);
      expect(probe.lines.length, lines.length);

      var measured = 0;
      for (var index = 0; index < lines.length; index++) {
        final line = probe.lines[index];
        measured += expectFullSpaces(line, lines[index]);

        // الأحرف اللاتينية والأرقام تصل إلى الملف كما هي.
        final drawn = line.words.map((word) => word.text).join();
        for (final token in <String>['2', '365', 'x', 'y', '5']) {
          if (lines[index].contains(token)) {
            expect(
              drawn.contains(token),
              isTrue,
              reason: 'الرمز "$token" يجب أن يظهر في الملف — '
                  'المُقاس: ${line.describe()}',
            );
          }
        }
      }
      expect(measured, greaterThanOrEqualTo(9),
          reason: 'عدد الأزواج المقيسة في النصوص المختلطة');
    });

    test('الترتيب من اليمين إلى اليسار والتشكيل سليمان ولا تُرسم مسافة كمحرف',
        () async {
      final probe = await renderLines(
        const <String>[_spinningEarth, _electricCurrent],
      );
      expect(probe.lines.length, 2);

      for (final line in probe.lines) {
        expect(line.words.length, 2, reason: line.describe());

        // 1) الترتيب: الكلمة الأولى منطقياً هي الأيمن في السطر.
        expect(
          line.words[0].x,
          greaterThan(line.words[1].x),
          reason: 'الكلمة الأولى منطقياً يجب أن تُرسم على اليمين — '
              '${line.describe()}',
        );

        // 2) لا وجود لمحرف مسافة داخل الكلمات: المسافة موضع هندسي فقط.
        for (final word in line.words) {
          expect(
            word.text.trim(),
            word.text,
            reason: 'لا يجب أن تُرسم المسافة كمحرف — ${line.describe()}',
          );
          expect(
            word.text.contains(' '),
            isFalse,
            reason: 'لا يجب أن تُرسم المسافة كمحرف — ${line.describe()}',
          );

          // 3) الحروف وصلت بصيغ العرض العربية (Presentation Forms-B) أي أن
          //    التشكيل والوصل تمّا فعلاً.
          for (final codePoint in word.text.codeUnits) {
            expect(
              codePoint,
              inInclusiveRange(0xFE70, 0xFEFF),
              reason: 'الكلمة المرسومة "${word.text}" يجب أن تكون بصيغ العرض '
                  'العربية المتصلة — ${line.describe()}',
            );
          }
        }
      }
    });

    test('أنواع المسافات اليونيكودية: المكتبة تعامل كل ما يطابقه \\s مسافةً '
        'قياسية واحدة، والتطبيق لا يكتب غير U+0020', () async {
      // التطبيق لا يعيد كتابة الفراغات في أي مكان (لا split/join/trim على
      // النصوص)، والمسافة المستخدمة في كل نصوصه هي U+0020. أما U+00A0 فهي
      // داخل مجموعة الفراغات التي يقسم عليها package:pdf (RegExp(r'\s'))
      // ويضيف بدلاً منها عرض المسافة القياسية في الخط (font.stringMetrics(' '))
      // لا عرض الحرف الذي كتبه المستخدم، فنتأكد من ذلك صراحةً هنا.
      for (final entry in _spaceKinds.entries) {
        final text = 'تدور${entry.value}الأرض';
        final probe = await renderLines(<String>[text]);
        expect(probe.lines.length, 1, reason: entry.key);

        final measured = probe.lines.first;
        expect(
          measured.words.length,
          2,
          reason: '${entry.key}: يجب أن يُعامل الفراغ كفاصل بين كلمتين — '
              'المُقاس: ${measured.describe()}',
        );
        expect(expectFullSpaces(measured, entry.key), 1);
      }
    });

    test('الخط العادي والعريض يتفقان على عرض المسافة', () async {
      final regular = spaceAdvanceFor(regularFontData, 11);
      final bold = spaceAdvanceFor(boldFontData, 11);
      expect(
        bold,
        closeTo(regular, 0.01),
        reason: 'عرض المسافة عند 11 نقطة: العادي ${regular.toStringAsFixed(3)} '
            'والعريض ${bold.toStringAsFixed(3)} نقطة — يجب أن يتساويا حتى '
            'يصح أخذ الأصغر بينهما في بقية الاختبارات.',
      );
    });
  });
}
