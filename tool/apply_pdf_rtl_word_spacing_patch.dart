// أداة حقن إصلاح مسافات الكلمات العربية في نسخة من حزمة pdf.
//
// الاستعمال الأساسي (المتبع في هذا المستودع): تطبيقه على النسخة المحلية
// المُضمَّنة داخل المستودع:
//
//     dart run tool/apply_pdf_rtl_word_spacing_patch.dart third_party/pdf
//
// ويقبل أيضاً مسار مخزن الحزم إن رغبت في تجربة الحزمة الأصلية غير المعدّلة.
//
// المشكلة (pdf 3.11.3):
//   في RichText.layout() تُحسب مواضع الكلمات بالتقدّم الصحيح (advanceWidth)
//   ثم يأتي _Line.realign() في الوضع RTL فيعكس الموضع بعرض **الحبر**
//   (metrics.width) بدل عرض **التقدّم**. والفرق بين الاثنين هو الفراغات
//   الجانبية للمحارف (left/right side bearing)، ولأن آخر محرف عربي يُرسم
//   كنموذج نهائي (final form) يبدأ حبره بعد بداية صندوقه، فإن جزءًا من المسافة
//   بين الكلمتين يتآكل وتظهر الكلمات ملتصقة مثل: "تدورالأرض".
//
// الإصلاح: استخدام advanceWidth في انعكاس RTL داخل _Line.realign()
// (توضيح دلالي فقط؛ لا تغيير في أي واجهة عامة أو تصميم أو خط أو محاذاة).
//
// طريقة العمل: السكربت ليس اعتمادية جديدة ولا يلمس شيئاً سوى ملف
// `lib/src/widgets/text.dart` داخل النسخة المستهدفة (third_party/pdf في هذا
// المستودع)، وهو مكتوب ليكون:
//   * قابلاً للتكرار (idempotent): لا يعدّل شيئاً إن كان التعديل مطبقاً.
//   * صريحاً: يفشل برسالة واضحة إن تغيّر مصدر الحزمة ولم يعد التعديل ينطبق،
//     بدل أن يمرّر الاختبارات على نسخة غير مُصلحة.
import 'dart:io';

const String _patchedMarker = 'advanceWidth; // pdf-rtl-word-spacing-patch';

/// موضع التعديل الأول: واجهة _Span المجرّدة.
const String _spanAnchor = '''  double get width;

  double get height;''';

const String _spanReplacement = '''  double get width;

  /// المسافة التي يشغلها الجزء فعلاً في سطر الطباعة.
  ///
  /// تختلف عن [width] (عرض الحبر) بمقدار الفراغات الجانبية للمحارف، وهي
  /// الأساس الصحيح لترتيب الأجزاء في السطر من اليمين إلى اليسار.
  double get advanceWidth;

  double get height;''';

/// موضع التعديل الثاني: عرض التقدّم لكلمة مرسومة.
const String _wordAnchor = '''  @override
  double get width => metrics.width;''';

const String _wordReplacement = '''  @override
  double get width => metrics.width;

  @override
  double get advanceWidth =>
      metrics.advanceWidth; // pdf-rtl-word-spacing-patch''';

/// موضع التعديل الثالث: عرض التقدّم لعنصر مضمّن (صورة/عنصر واجهة).
const String _widgetSpanAnchor = '''  @override
  double get width => widget.box!.width;''';

const String _widgetSpanReplacement = '''  @override
  double get width => widget.box!.width;

  @override
  double get advanceWidth =>
      widget.box!.width; // pdf-rtl-word-spacing-patch''';

/// موضع التعديل الرابع: توزيع المسافات في سطر مضبوط الطرفين (TextAlign.justify).
const String _justifyAnchor = '''          span.offset = PdfPoint(
            isRTL
                ? delta - x - (span.offset.x + span.width)
                : span.offset.x + x,''';

const String _justifyReplacement = '''          span.offset = PdfPoint(
            isRTL
                ? delta - x - (span.offset.x + span.advanceWidth)
                : span.offset.x + x,''';

/// موضع التعديل الخامس: انعكاس مواضع الأجزاء في الوضع RTL.
const String _realignAnchor = '''    if (isRTL) {
      for (final span in spans) {
        span.offset = PdfPoint(
          delta - (span.offset.x + span.width),
          span.offset.y - baseline,
        );
      }
      return;
    }''';

const String _realignReplacement = '''    if (isRTL) {
      for (final span in spans) {
        // يُزاح كل جزء بمقدار عرض التقدّم لا عرض الحبر، وإلا تآكلت المسافات
        // بين الكلمات العربية (فرق الفراغات الجانبية لنماذج الحروف النهائية).
        span.offset = PdfPoint(
          delta - (span.offset.x + span.advanceWidth),
          span.offset.y - baseline,
        );
      }
      return;
    }''';

void main(List<String> arguments) {
  // الوسيط: مسار النسخة المحلية (third_party/pdf مثلاً)، أو رقم إصدار
  // الحزمة في مخزن الحزم (.pub-cache) للاستعمال اليدوي.
  final argument = arguments.isNotEmpty ? arguments.first : _vendoredDefault;
  final target = _resolveTarget(argument);
  if (target == null) {
    const separator = ' | ';
    final candidates = _candidatePaths(argument).join(separator);
    stderr.writeln(
      'تعذّر العثور على ملف الحزمة المستهدف: $argument\n'
      'مرّر مسار النسخة المحلية (مثل third_party/pdf) أو رقم إصدار موجود في '
      'مخزن الحزم بعد تشغيل flutter pub get.\n'
      'المسارات المُجرَّبة: $candidates',
    );
    exitCode = 2;
    return;
  }

  final source = target.readAsStringSync();
  if (source.contains(_patchedMarker)) {
    stdout.writeln('التعديل مطبّق مسبقاً: ${target.path}');
    return;
  }

  var patched = source;
  for (final step in <List<String>>[
    <String>['_Span', _spanAnchor, _spanReplacement],
    <String>['_Word', _wordAnchor, _wordReplacement],
    <String>['_WidgetSpan', _widgetSpanAnchor, _widgetSpanReplacement],
    <String>['_Line.realign/justify', _justifyAnchor, _justifyReplacement],
    <String>['_Line.realign', _realignAnchor, _realignReplacement],
  ]) {
    final label = step[0];
    final anchor = step[1];
    final replacement = step[2];
    if (!patched.contains(anchor)) {
      stderr.writeln(
        'تعذّر تطبيق التعديل ($label): لم يُعثر على النص الأصلي في '
        '${target.path}.\n'
        'السبب المحتمل: تغيّر إصدار الحزمة pdf. راجع '
        'tool/apply_pdf_rtl_word_spacing_patch.dart وحدّث مواضع التعديل.',
      );
      exitCode = 3;
      return;
    }
    patched = patched.replaceFirst(anchor, replacement);
  }

  // تحقق نهائي: لا يجوز أن يبقى أي انعكاس RTL يستخدم عرض الحبر.
  for (final leftover in <String>[
    'delta - (span.offset.x + span.width)',
    'delta - x - (span.offset.x + span.width)',
  ]) {
    if (patched.contains(leftover)) {
      stderr.writeln(
        'لم يكتمل التعديل: بقي في ${target.path} موضع انعكاس يستخدم عرض '
        'الحبر ($leftover). راجع مواضع التعديل في هذه الأداة.',
      );
      exitCode = 4;
      return;
    }
  }

  final backup = File('${target.path}.orig');
  // للنسخة المُضمَّنة داخل المستودع لا ننشئ نسخة احتياطية: نظام التحكم
  // بالإصدارات هو المرجع (ونحن لا نعدّل عليها فعلاً لأن العلامة موجودة).
  final insideCheckout =
      target.absolute.path.startsWith(Directory.current.absolute.path);
  if (!insideCheckout && !backup.existsSync()) {
    backup.writeAsStringSync(source);
  }
  target.writeAsStringSync(patched);
  stdout.writeln('تم تطبيق إصلاح مسافات RTL على: ${target.path}');
}

/// المسار الافتراضي: النسخة المُضمَّنة داخل المستودع.
const String _vendoredDefault = 'third_party/pdf';

File? _resolveTarget(String argument) {
  for (final path in _candidatePaths(argument)) {
    final file = File(path);
    if (file.existsSync()) {
      return file;
    }
  }
  return null;
}

/// كل المسارات المحتملة لملف الحزمة المستهدف (بترتيب الأولوية).
List<String> _candidatePaths(String argument) {
  const suffix = 'lib/src/widgets/text.dart';
  final paths = <String>[
    if (argument.endsWith('.dart')) argument,
    if (!argument.endsWith('.dart')) '$argument/$suffix',
  ];

  // إن كان الوسيط رقماً، نبحث عنه في مخزن الحزم.
  if (RegExp(r'^[0-9.]+$').hasMatch(argument)) {
    for (final root in _pubCacheRoots()) {
      final hosted = Directory('$root/hosted');
      if (root.trim().isEmpty || !hosted.existsSync()) {
        continue;
      }
      for (final host in hosted.listSync().whereType<Directory>()) {
        paths.add('${host.path}/pdf-$argument/$suffix');
      }
    }
  }
  return paths;
}

List<String> _pubCacheRoots() => <String>[
      if (Platform.environment['PUB_CACHE'] != null)
        Platform.environment['PUB_CACHE']!,
      '${Platform.environment['HOME'] ?? ''}/.pub-cache',
      '${Platform.environment['LOCALAPPDATA'] ?? ''}/Pub/Cache',
    ];
