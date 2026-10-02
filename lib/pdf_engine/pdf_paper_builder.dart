import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../layout/blueprint/exam_blueprint.dart';
import '../layout/paper_metrics.dart';
import '../models/exam_document.dart';
import '../models/equation_model.dart';
import '../models/paper_divider.dart';
import '../models/paper_font.dart';
import '../models/paper_settings.dart';
import '../models/paper_text_style.dart';
import '../models/point_kind.dart';
import '../models/quran_text.dart';
import '../services/math_snapshot_renderer.dart' show MathRaster;
import '../models/subject_layout.dart';
import '../models/tex_content.dart';
import 'exam_fonts.dart';
import 'exam_strategy.dart' show ExamTextStyles;
import 'paper_style_resolver.dart';
import 'pdf_math_rasters.dart';

/// بانٍ لعناصر `pw` من [ExamBlueprint]: الترويسة والسؤال والفرع والنقاط
/// والتذييل والإطار — **رسم فقط**، فكل قرار نصي (ترقيم، درجات، حذف عند
/// الفراغ) جاهز في المخطط ومشترك مع المعاينة وWord.
///
/// عناصر الترويسة والتذييل تُرسم بـ`pw.Directionality(rtl)` دائماً (ترتيب
/// الأعمدة فيزيائي: اليمين/الوسط/اليسار) مهما كان اتجاه منطقة الأسئلة.
class PdfPaperBuilder {
  PdfPaperBuilder({
    required this.document,
    required this.blueprint,
    required this.fonts,
    required this.styles,
    this.mathRasters,
  })  : settings = document.settings,
        layout = document.layout;

  final ExamDocument document;
  final ExamBlueprint blueprint;
  final ExamFonts fonts;
  final ExamTextStyles styles;
  final PaperSettings settings;
  final SubjectLayoutTemplate layout;

  /// لقطات المعادلات بمحرك المعاينة نفسه (انظر [PdfMathRasters])؛ `null`
  /// معناها لا مضيف رسم: تُكتب الصيغ نصاً رياضياً مقروءاً بلا كود.
  final PdfMathRasters? mathRasters;

  /// إزاحة بداية كتلة الفرع عن صندوق المحتوى (بنقاط PDF).
  static const double branchIndent = 10;

  /// إزاحة نقاط السؤال/الفرع عن بداية كتلتها (بنقاط PDF).
  static const double pointsIndent = 14;

  /// لون الحبر الوحيد للإطارات والفواصل (أسود: ورقة جاهزة للطباعة).
  static const PdfColor ink = PdfColors.black;

  double get _heightScale => settings.heightScale;

  pw.TextStyle _apply(pw.TextStyle base, PaperTextStyle? override) {
    return PaperStyleResolver.apply(
      base,
      override,
      fonts: fonts,
      defaultFont: settings.defaultFont,
    );
  }

  // ------------------------------------------------------------------
  // الترويسة: ثلاثة أعمدة (يمين موسَّط | وسط موسَّط | يسار محاذى لليمين)
  // ------------------------------------------------------------------

  pw.Widget header() {
    final data = blueprint.header;
    final override = document.header.style;
    final lineStyle = _apply(
      styles.headerBody.copyWith(lineSpacing: 1.6 * _heightScale),
      override,
    );
    final centerStyle = _apply(
      styles.headerBody.copyWith(
        fontWeight: pw.FontWeight.bold,
        lineSpacing: 1.6 * _heightScale,
      ),
      override,
    );

    // تخطيط الترويسة من إعداد المدرس نفسه الذي تقرأه المعاينة وWord:
    // المحاذاة تسود محاذاة العمود، ومسافة الفقرات بعد كل سطر (بكسل
    // منطقي ← نقطة). «بداية السطر» في ترويسة RTL هي اليمين.
    final spacingPt = override.paragraphSpacing == null
        ? null
        : PaperMetrics.pt(override.paragraphSpacing!);
    pw.TextAlign alignFor(pw.TextAlign columnAlign) {
      final align = override.align;
      if (align == null) {
        return columnAlign;
      }
      return PaperStyleResolver.toPdfAlign(align) ?? pw.TextAlign.start;
    }

    // سطر الترويسة يُرسم منسّقاً كما في اللوحة وWord: صيغ `$...$` مرسومةً
    // متجهةً في مكانها داخل السطر، لا كوداً خاماً.
    pw.Widget column(List<String> lines, pw.TextStyle style, pw.TextAlign align) {
      final resolved = alignFor(align);
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisSize: pw.MainAxisSize.min,
        children: <pw.Widget>[
          for (final line in lines) ...<pw.Widget>[
            _renderText(line, style, null, align: resolved),
            if (spacingPt != null && spacingPt > 0) pw.SizedBox(height: spacingPt),
          ],
        ],
      );
    }

    final bismillahStyle = _apply(
      styles.headerBody.copyWith(
        fontSize: 17 * settings.fontScale,
        lineSpacing: 1.5 * _heightScale,
      ),
      // البسملة بخط خطّي أنيق مستقل عن خط الورقة؛ ويبقى لونها لون الترويسة.
      PaperTextStyle(font: PaperFont.amiri, bold: false, color: override.color),
    );

    final centerColumn = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: <pw.Widget>[
        // البسملة موسَّطة دائماً (مستقلة عن محاذاة الترويسة — كاللوحة وWord).
        if (data.showBismillah)
          _fullWidth(
            pw.Text(
              data.bismillah,
              style: bismillahStyle,
              textAlign: pw.TextAlign.center,
            ),
          ),
        for (final line in data.centerLines) ...<pw.Widget>[
          _renderText(
            line,
            centerStyle,
            null,
            align: alignFor(pw.TextAlign.center),
          ),
          if (spacingPt != null && spacingPt > 0) pw.SizedBox(height: spacingPt),
        ],
      ],
    );

    final row = pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        // الأول في اتجاه القراءة العربية = يمين الورقة.
        pw.Expanded(
          flex: 3,
          child: column(data.rightLines, lineStyle, pw.TextAlign.center),
        ),
        pw.SizedBox(width: 6),
        pw.Expanded(flex: 4, child: centerColumn),
        pw.SizedBox(width: 6),
        pw.Expanded(
          flex: 3,
          child: column(data.leftLines, lineStyle, pw.TextAlign.right),
        ),
      ],
    );

    return pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Container(
        decoration: data.framed
            ? pw.BoxDecoration(border: pw.Border.all(color: ink, width: 1.1))
            : null,
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: row,
      ),
    );
  }

  // ------------------------------------------------------------------
  // التذييل: عبارة ختامية وسطاً + توقيع أساسي يساراً + ثانٍ يميناً (اختياري)
  // ------------------------------------------------------------------

  pw.Widget footer() {
    final data = blueprint.footer;
    final override = document.header.style;
    // ارتفاع سطر التذييل = 1.6× معامل الورقة — رقم الترويسة والمعاينة نفسه
    // (كان 1.5 فينحرف التذييل المطبوع عن الشاشة).
    final style = _apply(
      styles.headerBody.copyWith(lineSpacing: 1.6 * _heightScale),
      override,
    );
    final bold = style.copyWith(fontWeight: pw.FontWeight.bold);

    pw.Widget signature(SignatureBlueprint source) {
      return pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          _fullWidth(pw.Text(source.title, style: bold, textAlign: pw.TextAlign.center)),
          pw.SizedBox(height: 3),
          _fullWidth(
            pw.Text(source.nameLine, style: style, textAlign: pw.TextAlign.center),
          ),
        ],
      );
    }

    final secondary = data.secondary;
    final phrase = data.closingPhrase;
    return pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: <pw.Widget>[
          // اليمين: التوقيع الثاني (فقط إن أضافه المدرس).
          pw.Expanded(
            flex: 3,
            child: secondary == null ? pw.SizedBox() : signature(secondary),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            flex: 4,
            child: phrase == null
                ? pw.SizedBox()
                : _fullWidth(pw.Text(phrase, style: bold, textAlign: pw.TextAlign.center)),
          ),
          pw.SizedBox(width: 6),
          // اليسار: التوقيع الأساسي دائماً.
          pw.Expanded(flex: 3, child: signature(data.primary)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // الإطار: صورة PNG شفافة بحجم الصفحة أو إطار متجه داخل الهامش
  // ------------------------------------------------------------------

  /// طبقة الإطار خلف المحتوى (`null` إن لم يُفعَّل). [imageBytes] صورة PNG
  /// اختيارية؛ غيابها (أو تعذّر فك ترميزها) يرتد إلى الإطار المتجه.
  pw.Widget? frame({Uint8List? imageBytes}) {
    if (!settings.pageBorder) {
      return null;
    }
    if (imageBytes != null && imageBytes.isNotEmpty) {
      try {
        return pw.Positioned.fill(
          child: pw.Image(pw.MemoryImage(imageBytes), fit: pw.BoxFit.fill),
        );
      } catch (_) {
        // صورة غير صالحة: يُرسم الإطار المتجه بدلها بدل إسقاط التصدير.
      }
    }
    final inset = settings.marginMm * PdfPageFormat.mm * 0.5;
    return pw.Positioned(
      left: inset,
      top: inset,
      right: inset,
      bottom: inset,
      child: pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(color: ink, width: 1.2)),
      ),
    );
  }

  // ------------------------------------------------------------------
  // السؤال الكامل (كتلة لا تتجزأ)
  // ------------------------------------------------------------------

  pw.Widget question(QuestionBlueprint data) {
    final question = data.model;
    final globalIds = document.floatingElements.map((element) => element.id).toSet();
    final bodyOverride = question.style.copyWith(color: () => null);
    final titleOverride = question.style.copyWith(
      color: () => question.effectiveTitleColor,
    );
    final titleStyle = _apply(styles.question, titleOverride);
    final titleAlign = PaperStyleResolver.toPdfAlign(
      question.titleAlign ?? question.style.align,
    );
    final gap = PaperMetrics.pt(question.style.paragraphSpacing ?? 2);
    final bodyStyle = _apply(
      styles.body.copyWith(
        fontSize: 11 * settings.fontScale,
        lineSpacing: 1.7 * _heightScale,
      ),
      bodyOverride,
    );

    final printablePoints =
        data.points.where((point) => point.isPrintable).toList(growable: false);
    final children = <pw.Widget>[
      if (data.section != null)
        // سطر القسم بمقاسه المستقل (12.5pt × معامل الورقة) ومحاذاته الخاصة
        // من النموذج (`categoryAlign`) — لا يرث تنسيق السؤال، تماماً كما في
        // المعاينة وملف Word.
        _renderText(
          data.section!,
          styles.category,
          fonts.quranic,
          align: PaperStyleResolver.toPdfAlign(question.categoryAlign),
        ),
      _titleLine(
        data.title,
        numberStyle: titleStyle,
        statementStyle: titleStyle,
        align: titleAlign,
      ),
      if (data.body != null)
        pw.Padding(
          padding: pw.EdgeInsets.only(top: gap),
          child: _renderText(
            data.body!,
            bodyStyle,
            fonts.quranic,
            align: PaperStyleResolver.toPdfAlign(question.bodyAlign ?? question.style.align),
          ),
        ),
      if (printablePoints.isNotEmpty)
        pw.Padding(
          padding: pw.EdgeInsetsDirectional.only(start: pointsIndent, top: gap),
          child: _points(printablePoints, bodyOverride),
        ),
      for (final branch in data.branches)
        if (branch.isPrintable(ignoredAttachmentIds: globalIds))
          pw.Padding(
            padding: pw.EdgeInsetsDirectional.only(start: branchIndent, top: gap),
            child: _branch(branch),
          ),
      if (question.dividerAfter != null)
        _divider(question.dividerAfter!, _contentWidth),
    ];

    pw.Widget body = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: children,
    );
    if (question.showFrame) {
      body = pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(color: ink, width: 1)),
        padding: const pw.EdgeInsets.all(5),
        child: body,
      );
    }
    final legacy = question.attachments
        .where((element) => !globalIds.contains(element.id))
        .toList(growable: false);
    if (legacy.isEmpty) {
      return body;
    }
    return _withLegacySpace(body, legacy.fold<double>(0, (max, element) {
      final bottom = (element.dy + element.height) * PaperMetrics.pointsPerPixel;
      return bottom > max ? bottom : max;
    }));
  }

  pw.Widget _branch(BranchBlueprint data) {
    final branch = data.model;
    final globalIds = document.floatingElements.map((element) => element.id).toSet();
    final standalone = data.title.hasStatement &&
        layout.prefersQuranicFont &&
        QuranText.isStandaloneVerse(data.title.statement);
    final base = standalone
        ? styles.body.copyWith(
            fontSize: 12 * settings.fontScale,
            lineSpacing: (layout.lineHeightFactor + 1) * _heightScale,
          )
        : styles.body.copyWith(lineSpacing: layout.lineHeightFactor * _heightScale);
    final bodyStyle = _apply(base, branch.style);
    final align = PaperStyleResolver.toPdfAlign(branch.style.align);
    final gap = PaperMetrics.pt(branch.style.paragraphSpacing ?? 1);
    final printablePoints =
        data.points.where((point) => point.isPrintable).toList(growable: false);

    final children = <pw.Widget>[
      _titleLine(
        data.title,
        numberStyle: bodyStyle.copyWith(fontWeight: pw.FontWeight.bold),
        statementStyle: bodyStyle,
        align: align,
        centerVerse: standalone,
      ),
      if (data.body != null)
        pw.Padding(
          padding: pw.EdgeInsets.only(top: gap),
          child: _renderText(data.body!, bodyStyle, fonts.quranic, align: align),
        ),
      if (printablePoints.isNotEmpty)
        pw.Padding(
          padding: pw.EdgeInsetsDirectional.only(start: pointsIndent, top: gap),
          child: _points(printablePoints, branch.style),
        ),
      if (branch.dividerAfter != null) _divider(branch.dividerAfter!, _contentWidth),
    ];

    pw.Widget body = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: children,
    );
    if (branch.showFrame) {
      body = pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(color: ink, width: 0.8)),
        padding: const pw.EdgeInsets.all(4),
        child: body,
      );
    }
    final legacy = branch.attachments
        .where((element) => !globalIds.contains(element.id))
        .toList(growable: false);
    if (legacy.isEmpty) {
      return body;
    }
    return _withLegacySpace(body, legacy.fold<double>(0, (max, element) {
      final bottom = (element.dy + element.height) * PaperMetrics.pointsPerPixel;
      return bottom > max ? bottom : max;
    }));
  }

  /// سطر العنوان: الرقم ← المنطوق (يتمدّد) ← الدرجة عند حافة السطر الأخرى.
  pw.Widget _titleLine(
    TitleLineBlueprint title, {
    required pw.TextStyle numberStyle,
    required pw.TextStyle statementStyle,
    required pw.TextAlign? align,
    bool centerVerse = false,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(title.number, style: numberStyle),
        pw.SizedBox(width: 4),
        pw.Expanded(
          child: title.hasStatement
              ? _renderText(
                  title.statement,
                  statementStyle,
                  fonts.quranic,
                  align: align,
                  centerVerse: centerVerse,
                )
              : pw.SizedBox(),
        ),
        if (title.marks != null) ...<pw.Widget>[
          pw.SizedBox(width: 4),
          pw.Text(title.marks!, style: statementStyle),
        ],
      ],
    );
  }

  // ------------------------------------------------------------------
  // النقاط المرقّمة بأنواعها المختلطة (تسلسل واحد متصل)
  // ------------------------------------------------------------------

  pw.Widget _points(List<PointBlueprint> points, PaperTextStyle? owner) {
    final style = _apply(
      styles.body.copyWith(lineSpacing: 1.5 * _heightScale),
      owner,
    );
    final ownerAlign = PaperStyleResolver.toPdfAlign(owner?.align);
    final gap = PaperMetrics.pt(owner?.paragraphSpacing ?? 0);
    final children = <pw.Widget>[];
    for (final point in points) {
      if (children.isNotEmpty && gap > 0) {
        children.add(pw.SizedBox(height: gap));
      }
      children.add(_point(point, style, PaperStyleResolver.toPdfAlign(point.item.align) ?? ownerAlign));
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: children,
    );
  }

  pw.Widget _point(PointBlueprint point, pw.TextStyle style, pw.TextAlign? align) {
    final line = point.line.trim().isEmpty
        ? pw.SizedBox()
        : _renderText(point.line, style, fonts.quranic, align: align);
    if (point.kind != PointKind.multipleChoice || point.options.isEmpty) {
      return line;
    }
    final optionStyle = style.copyWith(lineSpacing: 1.4 * _heightScale);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: <pw.Widget>[
        line,
        pw.Padding(
          padding: const pw.EdgeInsetsDirectional.only(start: pointsIndent, top: 1),
          child: pw.Wrap(
            spacing: 14,
            runSpacing: 2,
            children: <pw.Widget>[
              for (final option in point.options)
                _renderText(
                  option.line,
                  optionStyle,
                  fonts.quranic,
                  align: PaperStyleResolver.toPdfAlign(option.option.align) ?? align,
                  // الخيار عنصر داخل Wrap: يأخذ عرضه الطبيعي لتتشارك
                  // الخيارات السطر الواحد كما في الشاشة.
                  fillWidth: false,
                ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _divider(PaperDivider divider, double contentWidth) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(top: divider.spacingBefore, bottom: divider.spacingAfter),
      child: pw.Center(
        child: pw.SizedBox(
          width: contentWidth * divider.widthFraction,
          child: pw.Divider(
            thickness: divider.thickness,
            color: ink,
            height: divider.thickness + 2,
          ),
        ),
      ),
    );
  }

  double get _contentWidth =>
      PdfPageFormat.a4.width - 2 * settings.marginMm * PdfPageFormat.mm;

  /// يحافظ على سلوك المرفقات القديمة التي كانت تحجز مساحة داخل السؤال/الفرع؛
  /// العناصر العامة الجديدة لا تمر عبر هذا المسار.
  pw.Widget _withLegacySpace(pw.Widget body, double minHeight) {
    return pw.ConstrainedBox(
      constraints: pw.BoxConstraints(minHeight: minHeight, minWidth: _contentWidth - 24),
      child: body,
    );
  }

  // ------------------------------------------------------------------
  // نص الورقة: LaTeX وآيات القرآن
  // ------------------------------------------------------------------

  /// نص الورقة: مقاطع LaTeX ($...$) **لقطات من محرك العرض نفسه**
  /// ([PdfMathRasters]) فتُطبع كما تُرى على اللوحة تماماً، وآيات القرآن
  /// الموسومة بـ `﴿ ... ﴾` تُرسم بالخط القرآني (Amiri) إن توفّر، والباقي نص
  /// عادي.
  ///
  /// [centerVerse] يوسّط آية قائمة بذاتها كما في لوحة المعاينة، و[align]
  /// محاذاة الكتلة المختارة من شريط التنسيق، و[fillWidth] يمنح الكتلة عرض
  /// صندوق المحتوى (يُطفأ حين تكون الكتلة عنصراً داخل `Wrap` يتقاسمان السطر).
  pw.Widget _renderText(
    String text,
    pw.TextStyle style,
    pw.Font? quranFont, {
    bool centerVerse = false,
    pw.TextAlign? align,
    int? maxLines,
    bool fillWidth = true,
  }) {
    final segments = TexContent.split(text);
    final hasMath = segments.any((segment) => segment.isMath);
    if (!hasMath) {
      final plain = _plainText(text, style, quranFont,
          centerVerse: centerVerse, align: align, maxLines: maxLines);
      return fillWidth ? _fullWidth(plain) : plain;
    }
    final fontSize = style.fontSize ?? 10.5;
    final rows = <pw.Widget>[];
    var inline = <pw.Widget>[];

    void flushInline() {
      if (inline.isEmpty) {
        return;
      }
      rows.add(
        pw.Wrap(
          spacing: 1,
          runSpacing: 2,
          alignment: _wrapAlign(align),
          crossAxisAlignment: pw.WrapCrossAlignment.center,
          children: List<pw.Widget>.of(inline),
        ),
      );
      inline = <pw.Widget>[];
    }

    for (final segment in segments) {
      if (!segment.isMath) {
        if (segment.text.isNotEmpty) {
          inline.add(_plainText(segment.text, style, quranFont,
              align: align, maxLines: maxLines));
        }
        continue;
      }
      final raster = mathRasters?.lookup(segment.text, fontSize);
      if (raster == null) {
        // صيغة لم تُلتقط (مضيف غائب أو تعذّر الرسم): نص رياضي مقروء —
        // ممنوع ظهور كود LaTeX في أي ملف مهما كان السبب.
        inline.add(
          pw.Text(EquationModel.readableText(segment.text), style: style, textAlign: align),
        );
        continue;
      }
      final image = _mathImage(raster);
      if (segment.isBlock) {
        flushInline();
        rows.add(pw.Center(child: image));
      } else {
        inline.add(image);
      }
    }
    flushInline();
    final block = pw.Column(
      crossAxisAlignment: _columnAlign(align),
      mainAxisSize: pw.MainAxisSize.min,
      children: rows,
    );
    return fillWidth ? _fullWidth(block) : block;
  }

  /// صورة المعادلة بمقاسها الطبيعي بالنقاط: لا تحجيم يدوي ولا تصحيح مواضع —
  /// القياس من المحرك الذي صنع الصورة.
  static pw.Widget _mathImage(MathRaster raster) => pw.Image(
        pw.MemoryImage(raster.pngBytes),
        width: raster.widthPt,
        height: raster.heightPt,
        fit: pw.BoxFit.fill,
      );

  /// يمنح كتلة النص عرض صندوق المحتوى كاملاً قبل حساب الالتفاف والمحاذاة.
  ///
  /// `pw.Text` في مكتبة pdf يقيس صندوقه على عرض **أطول سطر** (تقلّص)،
  /// والمحاذاة والضبط يُحسبان على ذلك العرض المتقلّص: فلا يظهر أثر لمحاذاة
  /// «يسار/وسط/يمين» على فقرة سطرها واحد — بخلاف `TextPainter` على شاشة
  /// المعاينة الذي يعطي النص عرض الورقة المتاح. `pw.SizedBox` بعرض لانهائي
  /// يُقيَّد بالمُتاح فيمنح النص صندوقاً مطابقاً لصندوق الشاشة (WYSIWYG).
  static pw.Widget _fullWidth(pw.Widget child) =>
      pw.SizedBox(width: double.infinity, child: child);

  static pw.CrossAxisAlignment _columnAlign(pw.TextAlign? align) {
    switch (align) {
      case pw.TextAlign.center:
        return pw.CrossAxisAlignment.center;
      case pw.TextAlign.right:
      case pw.TextAlign.end:
        return pw.CrossAxisAlignment.end;
      default:
        return pw.CrossAxisAlignment.start;
    }
  }

  static pw.WrapAlignment _wrapAlign(pw.TextAlign? align) {
    switch (align) {
      case pw.TextAlign.center:
        return pw.WrapAlignment.center;
      case pw.TextAlign.right:
      case pw.TextAlign.end:
        return pw.WrapAlignment.end;
      default:
        return pw.WrapAlignment.start;
    }
  }

  /// نص عادي — وإذا حمل آيات موسومة رُسمت مقاطعها بالخط القرآني [quranFont]
  /// في نفس السطر ([pw.RichText] بامتدادات متعددة الخطوط).
  ///
  /// غياب الخط القرآني أو غياب الوسم يعيد النص كما هو بخط الورقة الأساسي.
  static pw.Widget _plainText(
    String text,
    pw.TextStyle style,
    pw.Font? quranFont, {
    bool centerVerse = false,
    pw.TextAlign? align,
    int? maxLines,
  }) {
    if (quranFont == null || !QuranText.containsQuran(text)) {
      return pw.Text(
        text,
        style: style,
        textAlign: centerVerse ? pw.TextAlign.center : align,
        maxLines: maxLines,
      );
    }
    final spans = <pw.InlineSpan>[];
    for (final segment in QuranText.split(text)) {
      if (segment.text.isEmpty) {
        continue;
      }
      // تنبيه دقيق في حزمة pdf: `copyWith(font:)` يوجَّه إلى خانة الوزن
      // الفارغة فقط، وأي خط مضبوط مسبقاً (مثل Noto الصريح الذي يضعه
      // PaperStyleResolver) يبقى ويسقط الخط الممرَّر. لذلك تُتجاوَز هنا
      // الخانات الأربع صراحةً ليُلبَس الخط القرآني حتماً.
      spans.add(
        pw.TextSpan(
          text: segment.text,
          style: segment.isQuran
              ? style.copyWith(
                  fontNormal: quranFont,
                  fontBold: quranFont,
                  fontItalic: quranFont,
                  fontBoldItalic: quranFont,
                )
              : style,
        ),
      );
    }
    return pw.RichText(
      text: pw.TextSpan(children: spans),
      textAlign: centerVerse ? pw.TextAlign.center : null,
      maxLines: maxLines,
    );
  }
}
