// =============================================================================
// مسبار OOXML بنيوي لملف DOCX القابل للتحرير (P0.4).
//
// لا يقرأ «نص الملف» ولا يقارن صوراً: يفكّ الحزمة ويفحص **البنية** — الأجزاء
// والعلاقات، ترتيب فقرات `word/document.xml`، خصائص الفقرة (`w:bidi`، `w:jc`،
// `w:ind`، `w:spacing/@w:line`)، خصائص الجريان بترتيبه (`w:rPr`: `w:rtl`،
// `w:b`، `w:i`، `w:u`، `w:sz`، `w:rFonts`، `w:position`)، فواصل الصفحات،
// `m:oMath`/`m:t`، الرسميات وعلاقاتها، و`w:sectPr` (اتجاه الصفحة والهوامش).
//
// كل نتيجة تُقرأ من نفس البايتات التي كُتبت في القرص، فلا مجال لادعاء «الممرّ
// يغطي كذا» من غير قياس، ولا يُكتفى بجذر RMSE.
//
// لا حزمة xml جديدة (منوعات P0.6): الماسح على مستوى الوسوم بالنص، وهو كافٍ
// لمخرجات مولّدنا لأنه لا ينتج CDATA ولا مسنداً يحوي '<' أو '>'.
// =============================================================================
import 'dart:convert';

import 'package:archive/archive.dart';

/// وسم XML واحد: اسم، ونوع (فتح/إغلاق/ذاتي الإغلاق)، وخصائصه.
class OoxmlTag {
  OoxmlTag({
    required this.name,
    required this.isOpen,
    required this.isClose,
    required this.attrs,
  });

  final String name;
  final bool isOpen;
  final bool isClose;
  final Map<String, String> attrs;

  bool get isSelfClosing => !isOpen && !isClose;

  String? operator [](String key) => attrs[key];

  @override
  String toString() =>
      '<${isClose ? '/' : ''}$name${attrs.isEmpty ? '' : ' $attrs'}${isSelfClosing ? '/' : ''}>';
}

/// جريان نصي واحد: `<w:r>` (أو جريان معادلة `m:r`) بنصوصه وبخصائصه.
class OoxmlRun {
  OoxmlRun({
    required this.text,
    required this.isMath,
    required this.propertyTags,
  });

  /// النص المنطقي كما كتبه المولّد (كل `w:t`/`m:t` بترتيبها).
  final String text;
  final bool isMath;

  /// وسوم `w:rPr` لهذا الجريان (بما فيها الخصائص ذاتية الإغلاق `w:b/`, `w:rtl/`).
  final List<OoxmlTag> propertyTags;

  /// هل يظهر الوسم [name] في خصائص الجريان (وبقيمة ليست false)؟
  bool has(String name) {
    for (final tag in propertyTags) {
      if (tag.name == name && !tag.isClose) {
        final value = tag['w:val'];
        return value != 'false' && value != '0' && value != 'none';
      }
    }
    return false;
  }

  /// قيمة `@w:val` للوسم [name] إن وُجد.
  String? valueOf(String name) {
    for (final tag in propertyTags) {
      if (tag.name == name && !tag.isClose) {
        return tag['w:val'];
      }
    }
    return null;
  }

  bool get bold => has('w:b');
  bool get italic => has('w:i');
  bool get underline => has('w:u');
  bool get rtl => has('w:rtl');
  bool get hasPosition =>
      propertyTags.any((tag) => tag.name == 'w:position' && !tag.isClose);
  int? get sizeHalfPoints => int.tryParse(valueOf('w:sz') ?? '');
  String? get font => valueOf('w:rFonts') ?? _firstFontAttr;

  String? get _firstFontAttr {
    for (final tag in propertyTags) {
      if (tag.name == 'w:rFonts') {
        return tag['w:ascii'] ?? tag['w:hAnsi'] ?? tag['w:cs'];
      }
    }
    return null;
  }

  String? get color => valueOf('w:color');

  @override
  String toString() =>
      'run(isMath=$isMath, bold=$bold, italic=$italic, u=$underline, '
      'rtl=$rtl, size=$sizeHalfPoints, font=$font, text="$text")';
}

/// خصائص `<w:pPr>` لفقرة واحدة.
class OoxmlParagraphProps {
  OoxmlParagraphProps({
    required this.tags,
    required this.raw,
  });

  final List<OoxmlTag> tags;
  final String raw;

  bool _present(String name, {bool requireNotFalse = true}) {
    for (final tag in tags) {
      if (tag.name == name && !tag.isClose) {
        if (!requireNotFalse) {
          return true;
        }
        final value = tag['w:val'];
        return value != 'false' && value != '0';
      }
    }
    return false;
  }

  String? _value(String name, String attribute) {
    for (final tag in tags) {
      if (tag.name == name && !tag.isClose) {
        return tag[attribute];
      }
    }
    return null;
  }

  bool get hasBidi => _present('w:bidi');
  String? get alignment => _value('w:jc', 'w:val');
  Map<String, String> get indentAttributes {
    for (final tag in tags) {
      if (tag.name == 'w:ind' && !tag.isClose) {
        return Map<String, String>.from(tag.attrs);
      }
    }
    return const <String, String>{};
  }

  bool get hasIndent => indentAttributes.isNotEmpty;

  int? indentOf(String attribute) =>
      int.tryParse(indentAttributes['w:$attribute'] ?? '');

  int? get lineTwips => int.tryParse(_value('w:spacing', 'w:line') ?? '');
  String? get lineRule => _value('w:spacing', 'w:lineRule');
  int? get before => int.tryParse(_value('w:spacing', 'w:before') ?? '');
  int? get after => int.tryParse(_value('w:spacing', 'w:after') ?? '');
  bool get hasFrameBorder => tags.any((tag) => tag.name == 'w:pBdr' && !tag.isClose);

  /// عدد `<w:br w:type="page"/>` داخل الفقرة.
  int get pageBreaks => RegExp('<w:br w:type="page"/>').allMatches(raw).length;

  @override
  String toString() =>
      'pPr(bidi=$hasBidi, jc=$alignment, ind=$indentAttributes, '
      'line=$lineTwips/$lineRule, before=$before, after=$after)';
}

/// فقرة `<w:p>` واحدة: خصائصها وجريانها بترتيبها ورسمياتها ومعادلاتها.
class OoxmlParagraph {
  OoxmlParagraph({
    required this.index,
    required this.raw,
    required this.props,
    required this.runs,
    required this.mathRegions,
    required this.relationIds,
  });

  final int index;

  /// نص الفقرة الخام كاملاً (بما فيه `m:oMath`) لفحوص لا تُنمَّط.
  final String raw;
  final OoxmlParagraphProps props;

  /// جريان النص (`w:r`) بترتيب كتابته — بلا جريان المعادلات.
  final List<OoxmlRun> runs;

  /// نص كل `m:oMath` في الفقرة (نصوص `m:t` متصلة)، بترتيبها.
  final List<String> mathRegions;

  /// `r:embed` لكل رسمية في الفقرة.
  final List<String> relationIds;

  /// النص المنطقي للفقرة: كل `w:t` بترتيب الجريان.
  String get text => runs.map((run) => run.text).join();

  String get allText => <String>[
        ...runs.map((run) => run.text),
        ...mathRegions,
      ].join(' ');

  bool get hasDrawing =>
      raw.contains('<w:drawing') || raw.contains('<w:pict');

  bool get hasPageBreak => props.pageBreaks > 0;
  int get mathCount => mathRegions.length;

  @override
  String toString() =>
      'w:p#$index ${props.alignment} bidi=${props.hasBidi} '
      'ind=${props.indentAttributes} text="${text.length > 60 ? '${text.substring(0, 60)}…' : text}"';
}

/// محلّل/ماسح OOXML لملف .docx واحد.
class OoxmlProbe {
  OoxmlProbe._(this._parts, this._binarySizes);

  factory OoxmlProbe.decode(List<int> docxBytes) {
    final archive = ZipDecoder().decodeBytes(docxBytes);
    final parts = <String, String>{};
    final binarySizes = <String, int>{};
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      final bytes = file.content as List<int>;
      if (file.name.endsWith('.xml') || file.name.endsWith('.rels')) {
        parts[file.name] = utf8.decode(bytes, allowMalformed: true);
      } else {
        binarySizes[file.name] = bytes.length;
      }
    }
    return OoxmlProbe._(parts, binarySizes);
  }

  final Map<String, String> _parts;
  final Map<String, int> _binarySizes;

  List<String> get partNames =>
      <String>[..._parts.keys, ..._binarySizes.keys]..sort();
  List<String> get xmlPartNames => _parts.keys.toList()..sort();
  List<String> get mediaNames => _binarySizes.keys.toList()..sort();
  Map<String, int> get mediaSizes => _binarySizes;

  bool hasPart(String name) => _parts.containsKey(name) || _binarySizes.containsKey(name);

  String part(String name) {
    final value = _parts[name];
    if (value == null) {
      throw StateError('جزء مفقود في الحزمة: $name');
    }
    return value;
  }

  String? partOrNull(String name) => _parts[name];

  // ------------------------------ المستند ---------------------------------

  String get documentXml => part('word/document.xml');
  String? get stylesXmlOrNull => _parts['word/styles.xml'];
  String get stylesXml => part('word/styles.xml');

  /// فقرات المتن بترتيبها في الملف (بما فيها فقرات جداول الترويسة/التذييل).
  late final List<OoxmlParagraph> paragraphs = _paragraphs(documentXml);

  /// فقرات جزء ترويسة/تذييل منفصل (`word/header1.xml`…).
  List<OoxmlParagraph> headerParagraphs(int number) =>
      _paragraphs(part('word/header$number.xml'));

  List<OoxmlParagraph> footerParagraphs(int number) =>
      _paragraphs(part('word/footer$number.xml'));

  List<OoxmlParagraph> _paragraphs(String xml) {
    final result = <OoxmlParagraph>[];
    var cursor = 0;
    while (true) {
      final open = _indexOfAny(xml, cursor, <String>['<w:p>', '<w:p ']);
      if (open < 0) {
        break;
      }
      final close = xml.indexOf('</w:p>', open);
      if (close < 0) {
        break;
      }
      // `<w:p/>` (فقرة فارغة ذاتية الإغلاق) لا تليق بـ `<w:p>`: تُستثنى.
      final tagEnd = xml.indexOf('>', open);
      if (tagEnd > 0 && xml.substring(open, tagEnd + 1).endsWith('/>')) {
        result.add(OoxmlParagraph(
          index: result.length,
          raw: xml.substring(open, tagEnd + 1),
          props: OoxmlParagraphProps(tags: const <OoxmlTag>[], raw: ''),
          runs: const <OoxmlRun>[],
          mathRegions: const <String>[],
          relationIds: const <String>[],
        ));
        cursor = tagEnd + 1;
        continue;
      }
      final raw = xml.substring(open, close + '</w:p>'.length);
      result.add(_parseParagraph(result.length, raw));
      cursor = close + '</w:p>'.length;
    }
    return result;
  }

  OoxmlParagraph _parseParagraph(int index, String raw) {
    // مقاطع المعادلة تُقصّ أولاً حتى لا تُحسب جريان `m:r` ضمن جريان النص.
    var text = raw;
    final mathRegions = <String>[];
    final mathPattern = RegExp(r'<m:oMath(?:\s[^>]*)?>(.*?)</m:oMath>', dotAll: true);
    text = text.replaceAllMapped(mathPattern, (match) {
      mathRegions.add(_texts(match.group(1)!, 'm:t').join(' '));
      return '';
    });

    final propsStart = _indexOfAny(text, 0, <String>['<w:pPr>', '<w:pPr ']);
    var propsRaw = '';
    if (propsStart >= 0) {
      final propsEnd = text.indexOf('</w:pPr>', propsStart);
      if (propsEnd >= 0) {
        propsRaw = text.substring(propsStart, propsEnd + '</w:pPr>'.length);
      }
    }
    final props = OoxmlParagraphProps(
      tags: scanTags(propsRaw),
      raw: propsRaw,
    );

    final runs = <OoxmlRun>[];
    final runPattern = RegExp(r'<w:r(?:\s[^>]*)?>(.*?)</w:r>', dotAll: true);
    for (final match in runPattern.allMatches(text)) {
      final body = match.group(1)!;
      var propertyRaw = '';
      final propertiesStart =
          _indexOfAny(body, 0, <String>['<w:rPr>', '<w:rPr ']);
      if (propertiesStart >= 0) {
        final propertiesEnd = body.indexOf('</w:rPr>', propertiesStart);
        if (propertiesEnd >= 0) {
          propertyRaw =
              body.substring(propertiesStart, propertiesEnd + '</w:rPr>'.length);
        }
      }
      runs.add(OoxmlRun(
        text: _texts(body, 'w:t').join(),
        isMath: false,
        propertyTags: scanTags(propertyRaw),
      ));
    }
    final relationIds = <String>[
      for (final match in RegExp('r:embed="([^"]+)"').allMatches(raw))
        match.group(1)!,
    ];
    return OoxmlParagraph(
      index: index,
      raw: raw,
      props: props,
      runs: runs,
      mathRegions: mathRegions,
      relationIds: relationIds,
    );
  }

  /// كل نصوص `<name>…</name>` بترتيبها.
  static List<String> _texts(String xml, String name) {
    final pattern = RegExp('<$name(?:\\s[^>]*)?>(.*?)</$name>', dotAll: true);
    return <String>[
      for (final match in pattern.allMatches(xml)) _unescape(match.group(1)!),
    ];
  }

  static int _indexOfAny(String haystack, int start, List<String> needles) {
    var best = -1;
    for (final needle in needles) {
      final at = haystack.indexOf(needle, start);
      if (at >= 0 && (best < 0 || at < best)) {
        best = at;
      }
    }
    return best;
  }

  /// خصائص `<w:sectPr>` (حجم الصفحة، الهوامش، الاتجاه).
  Map<String, Map<String, String>> get sectionProperties {
    final result = <String, Map<String, String>>{};
    final tags = scanTags(documentXml);
    var inside = false;
    for (final tag in tags) {
      if (tag.name == 'w:sectPr') {
        inside = tag.isOpen || tag.isSelfClosing;
        if (tag.isClose) {
          inside = false;
        }
        continue;
      }
      if (inside &&
          const <String>{
            'w:pgSz',
            'w:pgMar',
            'w:cols',
            'w:bidi',
            'w:docGrid',
            'w:pgNumType',
          }.contains(tag.name)) {
        result[tag.name] = Map<String, String>.from(tag.attrs);
      }
    }
    return result;
  }

  /// كل `w:ind` في المستند بخصائصه الخام (لفحص الاتجاهية في P0.5-A).
  List<Map<String, String>> get indentDirectives => <Map<String, String>>[
        for (final paragraph in paragraphs)
          if (paragraph.props.hasIndent) paragraph.props.indentAttributes,
      ];

  /// كل محاذاة `w:jc` في المستند بترتيب الفقرات.
  List<String?> get alignments =>
      paragraphs.map((paragraph) => paragraph.props.alignment).toList();

  /// نصوص `w:t` بترتيبها (تسلسل المحتوى).
  List<String> get textSequence =>
      paragraphs.map((paragraph) => paragraph.text).toList(growable: false);

  /// المستند كله نصاً واحداً بترتيب الجريان.
  String get flatText => textSequence.join(' ');

  /// عدد فواصل الصفحة `<w:br w:type="page"/>` في المتن.
  int get pageBreakCount =>
      RegExp('<w:br w:type="page"/>').allMatches(documentXml).length;

  /// عدد `m:oMath` و`m:oMathPara` في المتن.
  int get inlineMathCount =>
      RegExp('<m:oMath>').allMatches(documentXml).length +
      RegExp('<m:oMath ').allMatches(documentXml).length;
  int get mathParagraphCount =>
      RegExp('<m:oMathPara>').allMatches(documentXml).length +
      RegExp('<m:oMathPara ').allMatches(documentXml).length;

  /// كل نصوص `m:t` في المستند بترتيبها (لفحص ما يصل فعلاً إلى المعادلة).
  List<String> get mathTexts {
    final result = <String>[];
    for (final paragraph in paragraphs) {
      result.addAll(paragraph.mathRegions);
    }
    return result;
  }

  /// صور/رسميات: `r:embed` بترتيبها.
  List<String> get embeddedRelationIds => <String>[
        for (final paragraph in paragraphs) ...paragraph.relationIds,
      ];

  // ------------------------------ العلاقات --------------------------------

  /// قاموس `Id → Target` لعلاقات جزء ما (`word/document.xml` → `word/_rels/…`).
  Map<String, String> relationshipsFor(String partName) {
    final directory = partName.contains('/')
        ? partName.substring(0, partName.lastIndexOf('/'))
        : '';
    final base = partName.substring(partName.lastIndexOf('/') + 1);
    final relsName =
        '$directory${directory.isEmpty ? '' : '/'}_rels/$base.rels';
    final xml = _parts[relsName];
    if (xml == null) {
      return const <String, String>{};
    }
    final result = <String, String>{};
    for (final tag in scanTags(xml)) {
      if (tag.name == 'Relationship' && !tag.isClose) {
        result[tag['Id'] ?? ''] = tag['Target'] ?? '';
      }
    }
    return result;
  }

  /// العلاقات المعلّقة: `r:id` مستعمل في جزء ولا يوجد له تعريف.
  List<String> undefinedRelations(String partName) {
    final defined = relationshipsFor(partName).keys.toSet();
    final xml = part(partName);
    final used = <String>{
      for (final match in RegExp('r:(?:id|embed)="([^"]+)"').allMatches(xml))
        match.group(1)!,
    };
    return used.where((id) => !defined.contains(id)).toList()..sort();
  }

  /// أهداف علاقات لا يوجد لها جزء في الحزمة (ملف مفقود ← Word يرفض الفتح).
  List<String> missingRelationTargets(String partName) {
    final relationships = relationshipsFor(partName);
    final directory = partName.contains('/')
        ? partName.substring(0, partName.lastIndexOf('/'))
        : '';
    final missing = <String>[];
    relationships.forEach((id, target) {
      if (target.isEmpty || target.startsWith('http')) {
        return; // علاقة خارجية (مثل styles لا، بل hyperlink) لا تُفقد هنا.
      }
      final normalized = target.startsWith('/')
          ? target.substring(1)
          : (directory.isEmpty ? target : '$directory/$target');
      if (!hasPart(normalized)) {
        missing.add('$id → $target');
      }
    });
    return missing..sort();
  }

  /// `[Content_Types].xml`: هل لكل جزء xml صريحه؟
  List<String> missingContentTypes() {
    final xml = part('[Content_Types].xml');
    final overrides = <String>{
      for (final match
          in RegExp('PartName="([^"]+)"').allMatches(xml))
        match.group(1)!,
    };
    final defaults = <String>{
      for (final match in RegExp('Extension="([^"]+)"').allMatches(xml))
        match.group(1)!.toLowerCase(),
    };
    final missing = <String>[];
    for (final name in partNames) {
      if (name == '[Content_Types].xml' || name.endsWith('.rels')) {
        continue;
      }
      final extension = name.contains('.') ? name.split('.').last : '';
      if (overrides.contains('/$name') || defaults.contains(extension)) {
        continue;
      }
      missing.add(name);
    }
    return missing..sort();
  }

  // ------------------------------ أدوات عامة ------------------------------

  /// ماسح وسوم XML مسطّح.
  static List<OoxmlTag> scanTags(String xml) {
    final tags = <OoxmlTag>[];
    var cursor = 0;
    final attributePattern = RegExp(r'([\w:.-]+)\s*=\s*"([^"]*)"');
    while (true) {
      final open = xml.indexOf('<', cursor);
      if (open < 0) {
        break;
      }
      final close = xml.indexOf('>', open);
      if (close < 0) {
        break;
      }
      var body = xml.substring(open + 1, close);
      cursor = close + 1;
      if (body.startsWith('?') || body.startsWith('!')) {
        continue;
      }
      final isClose = body.startsWith('/');
      if (isClose) {
        body = body.substring(1);
      }
      final isSelfClosing = body.endsWith('/');
      if (isSelfClosing) {
        body = body.substring(0, body.length - 1);
      }
      body = body.trim();
      final nameEnd = body.indexOf(RegExp(r'\s'));
      final name = nameEnd < 0 ? body : body.substring(0, nameEnd);
      if (name.isEmpty) {
        continue;
      }
      final attrs = <String, String>{};
      if (nameEnd >= 0) {
        for (final match
            in attributePattern.allMatches(body.substring(nameEnd))) {
          attrs[match.group(1)!] = _unescape(match.group(2) ?? '');
        }
      }
      tags.add(OoxmlTag(
        name: name,
        isOpen: !isClose && !isSelfClosing,
        isClose: isClose,
        attrs: attrs,
      ));
    }
    return tags;
  }

  static String _unescape(String value) => value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}
