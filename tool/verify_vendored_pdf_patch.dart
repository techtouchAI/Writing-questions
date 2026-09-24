// فحص سريع: هل التعديل موجود فعلاً في النسخة المُضمَّنة من حزمة pdf؟
//
// يفشل برسالة واضحة إذا استُبدلت third_party/pdf بنسخة أصلية (مثلاً عند تحديث
// الحزمة)، حتى لا تمر الاختبارات على نسخة غير مُصلحة. الاستعمال:
//
//     dart run tool/verify_vendored_pdf_patch.dart
import 'dart:io';

const String _vendoredText =
    'third_party/pdf/lib/src/widgets/text.dart';

/// العلامة التي تتركها أداة الحقن، ووجودها دليل على أن التعديل مطبَّق.
const String _patchedMarker = 'advanceWidth; // pdf-rtl-word-spacing-patch';

/// المواضع التي يجب أن تكون قد تغيّرت عن الأصل (تحقق ثانٍ مستقل عن العلامة).
const List<String> _expectedPatched = <String>[
  'span.offset.x + span.advanceWidth',
  'double get advanceWidth =>',
];

/// المواضع التي لو بقيت لكان الإصلاح ناقصاً.
const List<String> _forbiddenLeftovers = <String>[
  'delta - (span.offset.x + span.width)',
  'delta - x - (span.offset.x + span.width)',
];

void main() {
  final file = File(_vendoredText);
  if (!file.existsSync()) {
    stderr.writeln('لا توجد النسخة المُضمَّنة: $_vendoredText');
    exitCode = 2;
    return;
  }

  final source = file.readAsStringSync();
  final problems = <String>[];

  if (!source.contains(_patchedMarker)) {
    problems.add('لا تحمل علامة التعديل ($_patchedMarker)');
  }
  for (final expected in _expectedPatched) {
    if (!source.contains(expected)) {
      problems.add('ينقصها: $expected');
    }
  }
  for (final leftover in _forbiddenLeftovers) {
    if (source.contains(leftover)) {
      problems.add('ما زالت تحوي انعكاس RTL بعرض الحبر: $leftover');
    }
  }

  if (problems.isEmpty) {
    stdout.writeln('حزمة pdf المُضمَّنة تحمل إصلاح مسافات الكلمات العربية ✔');
    return;
  }

  const lineBreak = '\n';
  final details = problems.map((problem) => ' - $problem').join(lineBreak);
  stderr.writeln(
    'النسخة المُضمَّنة في $_vendoredText لا تحمل إصلاح مسافات الكلمات '
    'العربية:$lineBreak$details$lineBreak'
    'طبّق التعديل: dart run tool/apply_pdf_rtl_word_spacing_patch.dart',
  );
  exitCode = 3;
}
