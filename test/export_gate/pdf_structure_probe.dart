// =============================================================================
// مقياس بنيوي لـ PDF المتجه (P0.3) — مبنيّ على `pdf_content_probe.dart` لكنه
// لا يعدّل فيه: يضيف قراءة **البنية** التي لا تُقرأ من صورة:
//
//   * عدد الصفحات و`/MediaBox` لكل صفحة (حدّ الورقة الحقيقي المطبوع).
//   * سطور الصفحة بترتيب الرسم، وعُقد المحتوى (bounding boxes) لكل سطر.
//   * تسلسل وسوم المحتوى كما رُسمت (ترتيب النص وترتيب البلوكات).
//   * ترتيب الكلمات هندسياً (RTL: تنازلي على x) والفجوات بينها.
//   * أي محارف صور تقديمية عربية (FE70..FEFF / FB50..FDFF) مقابل محارف
//     معجمية غير مشكَّلة (0600..06FF) — فعدم التشكيل خلل بصري لا تراه RMSE.
//   * الأرقام: مشرقية (0660..0669) أم لاتينية (0030..0039) وأين وقع الفاصل.
//   * القوسان والشرطة المائلة والفواصل: مواضعها نسبةً إلى الجريان.
//   * الخطوط المستعملة (BaseFont) وأحجامها وتعداد أسطر كل حجم.
//   * مواضع المعادلات: عدد صور المجرى (XObject) ورتبتها العمودية.
//
// لا RMSE هنا: كل قياس على كائنات PDF الفعلية (ToUnicode + Td + Tf + cm).
// =============================================================================
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:typed_data';

import '../pdf_engine/pdf_content_probe.dart';

/// وسوم ASCII تُقرأ من النص المرسوم للبحث عن تسلسل المحتوى.
final RegExp kMarkerTokenPattern =
    RegExp(r'(?<![A-Za-z0-9])([A-Z][A-Z0-9]{2,})(?![A-Za-z0-9])');

/// حقل `<image>` أو صورة XObject داخل مجرى الصفحة: `/ImNN Do`.
final RegExp _doImagePattern = RegExp(r'/(X[A-Za-z0-9_]+|Im[A-Za-z0-9_]+)\s+Do');

/// صفحة واحدة محلَّلة.
class PdfPageStructure {
  PdfPageStructure({
    required this.index,
    required this.lines,
    required this.mediaBox,
    required this.images,
  });

  final int index;
  final List<ProbedLine> lines;

  /// `/MediaBox [0 0 w h]` كما هي في كائن الصفحة.
  final List<double> mediaBox;

  /// الصور المرسومة في الصفحة بترتيب الرسم (المعادلات المصوَّرة والصور).
  ///
  /// الموضع من `cm` التي تسبق `Do`؛ وقد يكون العرض/الارتفاع بوحدة المصفوفة
  /// حين لا يوسّع الراسم الصورة في `cm` — فلا يُعتمد عليهما دليلاً، بينما
  /// يُعتمد العددُ والترتيبُ والموضعُ الأفقي والعمودي.
  final List<ProbedImage> images;

  /// عدد الصور المرسومة في الصفحة (المعادلات المصوَّرة تُطلب مرة لكل صيغة).
  int get embeddedImageObjects => images.length;

  List<ProbedWord> get words =>
      <ProbedWord>[for (final line in lines) ...line.words];

  int get lineCount => lines.length;
  int get wordCount => words.length;

  double get pageWidth => mediaBox.length >= 4 ? mediaBox[2] : 0;
  double get pageHeight => mediaBox.length >= 4 ? mediaBox[3] : 0;

  /// نص الصفحة كما رُسم، كلمة بكلمة بترتيب الرسم (وليس بترتيب القراءة).
  String get drawnText => words.map((word) => word.text).join(' ');

  /// كل الخطوط المستعملة في الصفحة (BaseFont بلا بادئة المجموعة الفرعية).
  Set<String> get baseFonts => words
      .map((word) => word.baseFont.replaceFirst(RegExp(r'^[A-Z]+6\+'), ''))
      .toSet();

  /// الخطوط كما هي في الملف (مع بادئة المجموعة الفرعية).
  Set<String> get rawBaseFonts =>
      words.map((word) => word.baseFont).toSet();

  /// أحجام الخط المستعملة وعدد الأسطر لكل حجم.
  Map<double, int> get lineCountByFontSize {
    final result = <double, int>{};
    for (final line in lines) {
      result[line.fontSize] = (result[line.fontSize] ?? 0) + 1;
    }
    return result;
  }

  /// صندوق المحتوى: أصغر/أكبر x و y لكل الكلمات المرسومة.
  List<double> get contentBounds {
    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    for (final word in words) {
      minX = math.min(minX, word.x);
      maxX = math.max(maxX, word.x + word.advanceWidth);
      minY = math.min(minY, word.y);
      maxY = math.max(maxY, word.y);
    }
    if (words.isEmpty) {
      return const <double>[];
    }
    return <double>[minX, minY, maxX, maxY];
  }

  /// صناديق السطور (بترتيب الرسم): [x0, y0, x1, y1] لكل سطر.
  List<List<double>> get lineBoxes => <List<double>>[
        for (final line in lines)
          if (line.words.isNotEmpty)
            <double>[
              line.words
                  .map((word) => word.x)
                  .reduce(math.min),
              line.words.first.y,
              line.words
                  .map((word) => word.x + word.advanceWidth)
                  .reduce(math.max),
              line.words.first.y,
            ],
        else
          const <double>[0, 0, 0, 0],
      ];

  /// سطور تحتوي [marker] (وسم ASCII داخل نص مرسوم).
  List<ProbedLine> linesWithMarker(String marker) => lines
      .where((line) => line.words.any((word) => word.text.contains(marker)))
      .toList(growable: false);

  /// فهرس سطر أول ظهور لـ [marker]، أو -1.
  int firstLineIndexOf(String marker) {
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].words.any((word) => word.text.contains(marker))) {
        return index;
      }
    }
    return -1;
  }

  // --------------------------- فحوص العربية والأرقام ---------------------------

  /// محارف عربية معجمية (غير مشكَّلة) مرسومة — صفرُها هو المطلوب.
  int get unshapedArabicLetters {
    var count = 0;
    for (final rune in drawnText.runes) {
      if (rune >= 0x0621 && rune <= 0x064A) {
        count++;
      }
    }
    return count;
  }

  /// محارف صور تقديمية عربية (Presentation Forms A/B) — يجب أن تكون كلها.
  int get presentationFormLetters {
    var count = 0;
    for (final rune in drawnText.runes) {
      if ((rune >= 0xFB50 && rune <= 0xFDFF) ||
          (rune >= 0xFE70 && rune <= 0xFEFF)) {
        count++;
      }
    }
    return count;
  }

  int get arabicIndicDigits {
    var count = 0;
    for (final rune in drawnText.runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        count++;
      }
    }
    return count;
  }

  int get latinDigits {
    var count = 0;
    for (final unit in drawnText.codeUnits) {
      if (unit >= 0x30 && unit <= 0x39) {
        count++;
      }
    }
    return count;
  }

  /// كلمات الصفحة التي تحوي رقماً (مشرقيًا أو لاتينياً) مع فاصل بعده أو قبله.
  List<ProbedWord> get digitTokens => words
      .where((word) => RegExp(r'[٠-٩0-9][:./\-)]|[(./\-:][٠-٩0-9]').hasMatch(word.text))
      .toList(growable: false);

  /// عدد الكلمات التي تبدأ بقوس إيحائي في هذا السطر (لأن RTL يقلب الأقواس).
  int countWordsMatching(RegExp pattern) =>
      words.where((word) => pattern.hasMatch(word.text)).length;

  /// ترتيب الكلمات على x داخل سطر: 'rtl' إذا تنازلي في أغلبه، 'ltr' إذا
  /// تصاعدي، 'mixed' خلاف ذلك. يُحسب على الأزواج المتجاورة في المقطع نفسه.
  static String orderOfLine(ProbedLine line) {
    var descending = 0;
    var ascending = 0;
    for (final index in line.adjacencyIndices) {
      final right = line.words[index];
      final left = line.words[index + 1];
      if (right.x > left.x) {
        descending++;
      } else if (right.x < left.x) {
        ascending++;
      }
    }
    if (descending == 0 && ascending == 0) {
      return 'single';
    }
    if (descending > ascending) {
      return 'rtl';
    }
    if (ascending > descending) {
      return 'ltr';
    }
    return 'mixed';
  }

  /// سطور متعددة الكلمات مرتبة (هي وحدها ما يُقيس اتجاه التدفق).
  List<ProbedLine> get multiWordLines =>
      lines.where((line) => line.adjacencyIndices.isNotEmpty).toList();

  /// فجوات الكلمات (pt) لكل سطر متعدد الكلمات — لقياس «التباعد الزائد».
  List<double> get allGaps => <double>[
        for (final line in multiWordLines) ...line.gaps,
      ];

  /// إحداثيات الصور من أعلى الصفحة إلى أسفلها (ترتيب القراءة في PDF: y أكبر
  /// = أعلى). ترتيبها هو الدليل على **ترتيب المعادلات** في الصفحة.
  List<double> get imageTopsByOrder =>
      images.map((image) => image.y).toList(growable: false);

  Map<String, Object?> toJson() => <String, Object?>{
        'page': index + 1,
        'mediaBox': mediaBox,
        'lineCount': lineCount,
        'wordCount': wordCount,
        'images': embeddedImageObjects,
        'fonts': baseFonts.toList()..sort(),
        'sizes': lineCountByFontSize
            .map((key, value) => MapEntry<String, int>(key.toString(), value)),
        'contentBounds':
            contentBounds.map((value) => value.roundToDouble()).toList(),
        'unshapedArabicLetters': unshapedArabicLetters,
        'presentationFormLetters': presentationFormLetters,
        'arabicIndicDigits': arabicIndicDigits,
        'latinDigits': latinDigits,
        'drawnText': drawnText,
      };
}

/// تقرير بنية ملف PDF كامل.
class PdfStructureReport {
  PdfStructureReport({required this.pages, required this.imageObjects});

  final List<PdfPageStructure> pages;

  /// عدد كائنات الصورة في الملف (`/Subtype/Image` بعد إسقاط المسافات).
  final int imageObjects;

  /// كل الصور المرسومة في كل الصفحات بترتيب الصفحة ثم ترتيب الرسم.
  List<ProbedImage> get allImages =>
      <ProbedImage>[for (final page in pages) ...page.images];

  int get pageCount => pages.length;

  static PdfStructureReport fromBytes(Uint8List bytes) {
    final count = PdfContentProbe.pageCountOf(bytes);
    final raw = latin1.decode(bytes, allowInvalid: true);
    final pages = <PdfPageStructure>[];
    for (var index = 0; index < count; index++) {
      final probe = PdfContentProbe.fromBytes(bytes, pageIndex: index);
      pages.add(PdfPageStructure(
        index: index,
        lines: probe.lines,
        mediaBox: _mediaBoxFor(raw, index),
        images: probe.images,
      ));
    }
    return PdfStructureReport(
      pages: pages,
      imageObjects: _countOccurrences(
        raw.replaceAll(' ', ''), '/Subtype/Image'),
    );
  }

  factory PdfStructureReport.fromFile(String path) =>
      PdfStructureReport.fromBytes(File(path).readAsBytesSync());

  /// `/MediaBox` من كائن الصفحة [index] (بترتيب `/Kids`).
  static List<double> _mediaBoxFor(String raw, int index) {
    final boxes = <List<double>>[];
    for (final match in RegExp(r'/MediaBox\s*\[([^\]]*)\]')
        .allMatches(raw)) {
      final values = <double>[
        for (final token in RegExp(r'-?[\d.]+').allMatches(match.group(1)!))
          double.parse(token.group(0)!),
      ];
      if (values.length == 4) {
        boxes.add(values);
      }
    }
    if (boxes.isEmpty) {
      return const <double>[];
    }
    return boxes[math.min(index, boxes.length - 1)];
  }

  static int _countOccurrences(String haystack, String needle) {
    var count = 0;
    for (var cursor = haystack.indexOf(needle);
        cursor >= 0;
        cursor = haystack.indexOf(needle, cursor + 1)) {
      count++;
    }
    return count;
  }

  /// تسلسل وسوم [known] عبر الملف كله (صفحة فصفحة، ثم سطراً فسطراً) بترتيب
  /// الرسم، مع استبعاد الوسوم في [excluded]. التكرار المتتابع مطويّ.
  List<String> markerSequence({
    required Set<String> known,
    Set<String> excluded = const <String>{},
  }) {
    final sequence = <String>[];
    for (final page in pages) {
      for (final line in page.lines) {
        for (final word in line.words) {
          for (final match in kMarkerTokenPattern.allMatches(word.text)) {
            final marker = match.group(1)!;
            if (!known.contains(marker) || excluded.contains(marker)) {
              continue;
            }
            if (sequence.isNotEmpty && sequence.last == marker) {
              continue;
            }
            sequence.add(marker);
          }
        }
      }
    }
    return sequence;
  }

  /// كل وسوم ASCII الظاهرة في الملف (لكشف أي محتوى زائد لم يتوقعه النموذج).
  Set<String> allMarkers({Set<String> excluded = const <String>{}}) {
    final result = <String>{};
    for (final page in pages) {
      for (final word in page.words) {
        for (final match in kMarkerTokenPattern.allMatches(word.text)) {
          final marker = match.group(1)!;
          if (!excluded.contains(marker)) {
            result.add(marker);
          }
        }
      }
    }
    return result;
  }

  /// صفحة أول ظهور لكل وسم في [markers].
  Map<String, int> pageOfMarker(Iterable<String> markers) {
    final result = <String, int>{};
    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      for (final marker in markers) {
        if (result.containsKey(marker)) {
          continue;
        }
        if (pages[pageIndex].linesWithMarker(marker).isNotEmpty) {
          result[marker] = pageIndex;
        }
      }
    }
    return result;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'pageCount': pageCount,
        'imageObjects': imageObjects,
        'pages': pages.map((page) => page.toJson()).toList(),
      };

  /// نص تشخيصي مختصر يُطبع في سجل CI (الدليل لا يُترك للتخمين).
  String describe() {
    final buffer = StringBuffer('PDF بنية: $pageCount صفحة؛ ');
    for (final page in pages) {
      buffer.write(
        'ص${page.index + 1}: أسطر=${page.lineCount} كلمات=${page.wordCount} '
        'صور=${page.embeddedImageObjects} '
        'خطوط=${page.baseFonts.join(',')} '
        'تقديمي=${page.presentationFormLetters} '
        'مشروط=${page.unshapedArabicLetters} '
        'أرقام-مشرقية=${page.arabicIndicDigits} '
        'أرقام-لاتينية=${page.latinDigits}; ',
      );
    }
    return buffer.toString();
  }
}
