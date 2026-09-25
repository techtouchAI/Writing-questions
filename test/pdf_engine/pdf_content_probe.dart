// أداة قياس مستقلة (لا تعتمد على أي شيفرة داخلية من حزمة pdf):
// تقرأ ملف PDF ناتجاً عن محرك التصدير وتستخرج منه ما هو **مرسوم فعلاً**:
// كل كلمة، موضعها (Td)، وعرض تقدّمها (من مصفوفة /W الخاصة بالملف نفسه)،
// ونصّها (من خريطة /ToUnicode) — أي نفس ما يقرؤه أي عارض PDF.
import 'dart:convert';
import 'dart:io' show zlib;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart' show TtfParser;

/// كلمة مرسومة فعلياً داخل ملف PDF.
class ProbedWord {
  const ProbedWord({
    required this.text,
    required this.x,
    required this.y,
    required this.fontSize,
    required this.fontName,
    required this.advanceWidth,
    this.baseFont = '',
  });

  /// النص كما يراه العارض (أشكال العرض العربية بعد التشكيل).
  final String text;

  /// اسم مورد الخط المستخدم لهذه الكلمة (مثل /F2).
  final String fontName;

  /// اسم الخط الفعلي كما في `/BaseFont` (مثل `AAAAAA+Amiri-Regular`).
  final String baseFont;

  /// إحداثي البداية الأفقي من أمر Td (نقاط PDF).
  final double x;

  /// إحداثي البداية العمودي من أمر Td (نقاط PDF).
  final double y;

  /// حجم الخط من أمر Tf.
  final double fontSize;

  /// عرض تقدّم الكلمة بنقاط PDF كما تحدده مصفوفة /W في الملف نفسه.
  final double advanceWidth;

  @override
  String toString() => 'ProbedWord("$text" x=${x.toStringAsFixed(3)} '
      'advance=${advanceWidth.toStringAsFixed(3)})';
}

/// سطر نصّي واحد داخل الملف (كلمات متلاصقة في ترتيب الرسم بنفس إحداثي y).
class ProbedLine {
  const ProbedLine({required this.words});

  /// الكلمات بترتيب الرسم: الكلمة الأولى هي الأيمن (بداية النص العربي).
  final List<ProbedWord> words;

  double get fontSize => words.isEmpty ? 0 : words.first.fontSize;

  /// المسافة الفعلية بين الكلمتين [index] و [index + 1] في الملف:
  /// من نهاية صندوق تقدّم الكلمة اليسرى إلى بداية الكلمة اليمنى.
  double gapAfter(int index) {
    final right = words[index];
    final left = words[index + 1];
    return right.x - (left.x + left.advanceWidth);
  }

  List<double> get gaps => <double>[
        for (var index = 0; index + 1 < words.length; index++) gapAfter(index),
      ];

  /// هل الكلمتان [index] و[index + 1] متجاورتان فعلاً داخل المقطع نفسه؟
  ///
  /// قد يضم السطر الواحد (نفس خط القاعدة) كلمات من عنصرين مختلفين: صفّين
  /// داخل `Wrap` مثلاً، أو سطر فرع وسطر خيارات تقاربا في الارتفاع. الفجوة بين
  /// هذين ليست فراغاً بين كلمتين بل تباعد تخطيط (وقد تكون قفزة رجعية كبيرة
  /// لأن الموضع يعود إلى بداية الصف). لذلك نعدّ الزوج تجاوزاً حقيقياً لفراغ
  /// الكلمات فقط إذا كان من النص نفسه (نفس حجم الخط واسم الخط) وكانت فجوته
  /// في مدى فراغ الكلمة: غير سالبة بحدود صغيرة، ولا تزيد عن حجم الخط (فراغ
  /// الكلمة جزء من حجم الخط، أما تباعد `Wrap` فأكبر منه).
  bool areAdjacentInRun(int index) {
    final right = words[index];
    final left = words[index + 1];
    if (right.fontSize != left.fontSize || right.fontName != left.fontName) {
      return false;
    }
    final gap = gapAfter(index);
    return gap >= -0.5 && gap <= right.fontSize;
  }

  /// أزواج الكلمات المتجاورة فعلاً داخل المقطع (انظر [areAdjacentInRun]).
  List<int> get adjacencyIndices => <int>[
        for (var index = 0; index + 1 < words.length; index++)
          if (areAdjacentInRun(index)) index,
      ];

  String describe() => words
      .map((word) => '"${word.text}"@${word.x.toStringAsFixed(2)}'
          '+${word.advanceWidth.toStringAsFixed(2)}')
      .join('  ');

  @override
  String toString() => 'ProbedLine(size=$fontSize) ${describe()}';
}

/// قارئ محتوى PDF: يحلّل الكائنات، الخطوط، مصفوفات العرض، وخريطة ToUnicode،
/// ثم يستخرج الكلمات المرسومة بمواضعها الحقيقية.
class PdfContentProbe {
  PdfContentProbe._(this.lines);

  /// كل سطور النص بالترتيب الذي رُسمت به.
  final List<ProbedLine> lines;

  /// أول سطر يحتوي كلمة نصّها [wordText] بالضبط (بعد التشكيل)، أو null.
  ProbedLine? lineWithWord(String wordText) {
    for (final line in lines) {
      if (line.words.any((word) => word.text == wordText)) {
        return line;
      }
    }
    return null;
  }

  factory PdfContentProbe.fromBytes(Uint8List bytes) {
    final objects = _PdfObjects.parse(bytes);
    final page = objects.pageDict;

    final fontsResource =
        RegExp(r'/Font\s*<<(.*?)>>', dotAll: true).firstMatch(page)?.group(1);
    if (fontsResource == null) {
      throw const FormatException('لا توجد موارد خطوط في الصفحة (/Font).');
    }

    final fonts = <String, _FontData>{};
    for (final match
        in RegExp(r'/(\w+)\s+(\d+)\s+0\s+R').allMatches(fontsResource)) {
      fonts['/${match.group(1)}'] = objects.fontData(int.parse(match.group(2)!));
    }

    final contents = <String>[];
    final single = RegExp(r'/Contents\s+(\d+)\s+0\s+R').firstMatch(page);
    final array = RegExp(r'/Contents\s*\[(.*?)\]', dotAll: true)
        .firstMatch(page)?.group(1);
    if (single != null) {
      final stream = objects.streamOf(int.parse(single.group(1)!));
      if (stream != null) {
        contents.add(stream);
      }
    } else if (array != null) {
      for (final match in RegExp(r'(\d+)\s+0\s+R').allMatches(array)) {
        final stream = objects.streamOf(int.parse(match.group(1)!));
        if (stream != null) {
          contents.add(stream);
        }
      }
    }
    if (contents.isEmpty) {
      throw const FormatException('تعذّر فك ضغط مجرى محتوى الصفحة.');
    }

    return PdfContentProbe._(_parseContent(contents.join('\n'), fonts));
  }

  // ------------------------------------------------------------------
  // تحليل أوامر الرسم: Tf (الخط والحجم) / Td (موضع كلمة) / <cids> (الكلمة)
  // ------------------------------------------------------------------
  static const double _sameLineTolerance = 0.5;

  static List<ProbedLine> _parseContent(
    String content,
    Map<String, _FontData> fonts,
  ) {
    final tokenPattern = RegExp(
      r'/(\w+)\s+([\d.]+)\s+Tf'
      r'|(-?[\d.]+)\s+(-?[\d.]+)\s+Td'
      r'|<([0-9A-Fa-f]*)>',
    );

    final words = <ProbedWord>[];
    var fontSize = 0.0;
    var fontName = '';
    _FontData? font;
    double? pendingX;
    double? pendingY;

    for (final match in tokenPattern.allMatches(content)) {
      if (match.group(1) != null) {
        fontName = '/${match.group(1)}';
        font = fonts[fontName];
        fontSize = double.parse(match.group(2)!);
        continue;
      }
      if (match.group(3) != null) {
        pendingX = double.parse(match.group(3)!);
        pendingY = double.parse(match.group(4)!);
        continue;
      }

      final hex = match.group(5) ?? '';
      if (hex.length < 4 || pendingX == null || pendingY == null) {
        continue;
      }
      final cids = <int>[
        for (var index = 0; index + 4 <= hex.length; index += 4)
          int.parse(hex.substring(index, index + 4), radix: 16),
      ];
      final data = font;
      final advance = data == null
          ? 0.0
          : cids.fold<double>(0, (sum, cid) {
              // عرض الـ CID من مصفوفة /W، وإن لم تكن موجودة نأخذ /DW = 1000.
              final width =
                  cid < data.widths.length ? data.widths[cid] : 1000;
              return sum + width * fontSize / 1000;
            });
      words.add(ProbedWord(
        text: data == null
            ? ''
            : String.fromCharCodes(
                cids.map((cid) => data.cidToUnicode[cid] ?? 0xFFFD),
              ),
        x: pendingX,
        y: pendingY,
        fontSize: fontSize,
        fontName: fontName,
        advanceWidth: advance,
        baseFont: data?.baseFont ?? '',
      ));
      pendingX = null;
      pendingY = null;
    }

    // تجميع الكلمات المتتالية في الرسم التي تشترك في نفس السطر.
    final lines = <ProbedLine>[];
    var bucket = <ProbedWord>[];
    double? bucketY;
    for (final word in words) {
      if (bucketY == null || (bucketY - word.y).abs() <= _sameLineTolerance) {
        bucket.add(word);
        bucketY ??= word.y;
      } else {
        lines.add(ProbedLine(words: bucket));
        bucket = <ProbedWord>[word];
        bucketY = word.y;
      }
    }
    if (bucket.isNotEmpty) {
      lines.add(ProbedLine(words: bucket));
    }
    return lines;
  }
}

/// عرض تقدّم المسافة U+0020 بنقاط PDF من ملف خط فعلي.
///
/// يُحسب بنفس الطريقة التي يحسبها محرك الرسم: عرض المحرف من جدول hmtx مضروباً
/// في حجم الخط. يُستخدم كمرجع خارجي للتأكد من أن الفجوة المرسومة بين الكلمات
/// تساوي المسافة المصمّمة في الخط وليس أقل منها.
double spaceAdvanceFor(ByteData fontData, double fontSize) {
  // نحتفظ بمحلّل واحد لكل خط لأن تحليل ملف الخط كاملاً عملية مكلفة وتُستدعى
  // هذه الدالة عشرات المرات في الاختبارات.
  final parser = _fontParsers[fontData] ??= TtfParser(fontData);
  final glyph = parser.charToGlyphIndexMap[0x20];
  if (glyph == null) {
    throw StateError('الخط لا يحتوي على محرف المسافة U+0020.');
  }
  final metrics = parser.glyphInfoMap[glyph];
  if (metrics == null) {
    throw StateError('لا توجد قياسات لمحرف المسافة في الخط.');
  }
  return metrics.advanceWidth * fontSize;
}

/// محلّلات ملفات الخطوط، واحدة لكل ملف خط (keyed بالكائن نفسه).
final Map<ByteData, TtfParser> _fontParsers = <ByteData, TtfParser>{};

/// بيانات خط واحد كما وردت في ملف PDF.
class _FontData {
  _FontData({required this.widths, required this.cidToUnicode, required this.baseFont});

  /// اسم الخط من `/BaseFont` في كائن الخط (قد يحمل بادئة مجموعة فرعية).
  final String baseFont;

  /// عرض كل CID بالألف من وحدة النص (كما في /W)، بترتيب الـ CID.
  final List<int> widths;

  /// خريطة CID ← نقطة يونيكود من /ToUnicode.
  final Map<int, int> cidToUnicode;
}

/// تحليل كائنات ملف الـ PDF (بدون أي مكتبة خارجية).
class _PdfObjects {
  _PdfObjects._(this._dicts, this._streams);

  final Map<int, String> _dicts;
  final Map<int, String> _streams;

  static _PdfObjects parse(Uint8List bytes) {
    final raw = latin1.decode(bytes, allowInvalid: true);
    final dicts = <int, String>{};
    final streams = <int, String>{};
    final header = RegExp(r'(\d+)\s+(\d+)\s+obj\b');

    var cursor = 0;
    while (cursor < raw.length) {
      final match = header.firstMatch(raw.substring(cursor));
      if (match == null) {
        break;
      }
      final serial = int.parse(match.group(1)!);
      final index = cursor + match.start + match.group(0)!.length;

      final streamIndex = raw.indexOf('stream', index);
      final endObjIndex = raw.indexOf('endobj', index);
      final hasStream = streamIndex != -1 &&
          (endObjIndex == -1 || streamIndex < endObjIndex);

      if (!hasStream) {
        final end = endObjIndex == -1 ? raw.length : endObjIndex;
        dicts[serial] = raw.substring(index, end);
        cursor = end == raw.length ? raw.length : end + 'endobj'.length;
        continue;
      }

      var dataStart = streamIndex + 'stream'.length;
      while (dataStart < raw.length &&
          (raw.codeUnitAt(dataStart) == 0x0d ||
              raw.codeUnitAt(dataStart) == 0x0a)) {
        dataStart++;
      }
      final dictText = raw.substring(index, streamIndex);
      dicts[serial] = dictText;

      // /Length قد يكون رقماً مباشراً أو مرجعاً غير مباشر؛ نجرّب الطريقتين
      // ونقبل أول فك تشفير ينجح.
      final endstream = raw.indexOf('endstream', dataStart);
      final lengthToken = RegExp(r'/Length\s+(\d+)(?:\s+0\s+R)?')
          .firstMatch(dictText);
      final directLength = lengthToken != null &&
              !lengthToken.group(0)!.contains('R')
          ? math.min(dataStart + int.parse(lengthToken.group(1)!), raw.length)
          : null;

      String? decoded;
      for (final dataEnd in <int?>[
        directLength,
        endstream == -1 ? raw.length : endstream,
      ]) {
        if (dataEnd == null || dataEnd <= dataStart) {
          continue;
        }
        decoded = _decodeStream(bytes.sublist(dataStart, dataEnd), dictText);
        if (decoded != null) {
          break;
        }
      }
      if (decoded != null) {
        streams[serial] = decoded;
      }
      final dataEnd = directLength ??
          (endstream == -1 ? raw.length : endstream);

      final next = raw.indexOf('endstream', dataEnd);
      cursor = next == -1 ? raw.length : next + 'endstream'.length;
    }

    return _PdfObjects._(dicts, streams);
  }

  static String? _decodeStream(Uint8List data, String dict) {
    if (dict.contains('/ASCII85Decode')) {
      // مجاري الخطوط الثنائية: لا نحتاجها.
      return null;
    }
    try {
      return latin1.decode(zlib.decode(data), allowInvalid: true);
    } catch (_) {
      // المكتبة لا تضغط المجرى إن لم يصغر حجمه، فيبقى نصاً عادياً.
      return latin1.decode(data, allowInvalid: true);
    }
  }

  String? streamOf(int serial) => _streams[serial];

  String get pageDict {
    for (final entry in _dicts.entries) {
      if (RegExp(r'/Type\s*/Page(?![s\w])').hasMatch(entry.value) &&
          entry.value.contains('/Font')) {
        return entry.value;
      }
    }
    throw const FormatException('لم يُعثر على كائن الصفحة (/Type /Page).');
  }

  _FontData fontData(int serial) {
    final dict = _dicts[serial];
    if (dict == null) {
      throw FormatException('كائن الخط $serial غير موجود في الملف.');
    }

    var widths = <int>[];
    final widthsRef = RegExp(r'/W\s*\[\s*\d+\s+(\d+)\s+0\s+R').firstMatch(dict);
    if (widthsRef != null) {
      final array = _dicts[int.parse(widthsRef.group(1)!)] ?? '';
      widths = <int>[
        for (final number in RegExp(r'-?\d+').allMatches(array))
          int.parse(number.group(0)!),
      ];
    }

    final cidToUnicode = <int, int>{};
    final cmapRef = RegExp(r'/ToUnicode\s+(\d+)\s+0\s+R').firstMatch(dict);
    if (cmapRef != null) {
      final cmap = _streams[int.parse(cmapRef.group(1)!)] ?? '';
      for (final entry in RegExp(
        r'<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]{4})>',
      ).allMatches(cmap)) {
        cidToUnicode[int.parse(entry.group(1)!, radix: 16)] =
            int.parse(entry.group(2)!, radix: 16);
      }
    }

    final baseFont = RegExp(r'/BaseFont\s*/([^\s/>\]]+)').firstMatch(dict)?.group(1) ?? '';

    return _FontData(widths: widths, cidToUnicode: cidToUnicode, baseFont: baseFont);
  }
}
