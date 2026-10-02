/// أسطح الإخراج التي يجب أن يصل إليها كل إعداد في نموذج الورقة.
enum ExportSurface {
  /// لوحة المعاينة التفاعلية (المرجع البصري الذي يراه المدرس).
  preview,

  /// ملف PDF المتجه (`PaginatedPdfExamEngine` + `PdfPaperBuilder`).
  pdfVector,

  /// ملف Word القابل للتحرير (نص + OMML + جداول).
  docxEditable,

  /// التصدير الدقيق (Exact): صور صفحات المعاينة نفسها في PDF وWord.
  exact,
}

/// بند في عقد التصدير: خاصية واحدة في النموذج ومسار وصولها إلى Renderers.
class ExportContractEntry {
  const ExportContractEntry({
    required this.property,
    required this.effect,
    required this.surfaces,
    required this.evidence,
  });

  /// اسم الخاصية كما في النموذج (مثال: `QuestionModel.categoryAlign`).
  final String property;

  /// الأثر البصري المطلوب وصوله (مثال: «محاذاة سطر القسم»).
  final String effect;

  /// الأسطح التي يصل إليها الأثر فعلاً.
  final List<ExportSurface> surfaces;

  /// الدليل داخل الشيفرة (دور/دالة/مفتاح) — يُراجع يدوياً عند أي تغيير.
  final String evidence;

  bool get reachesPreview => surfaces.contains(ExportSurface.preview);

  bool get reachesPdf => surfaces.contains(ExportSurface.pdfVector);

  bool get reachesWord => surfaces.contains(ExportSurface.docxEditable);

  bool get isPreviewOnly =>
      reachesPreview && !reachesPdf && !reachesWord && !surfaces.contains(ExportSurface.exact);

  bool get isPartial =>
      !isPreviewOnly && surfaces.length < ExportSurface.values.length;
}

/// **تدقيق عقد التصدير**: كل إعداد في النموذج مصنَّف حسب الأسطح التي يصل
/// إليها، مع دليل في الشيفرة. الهدف المُختبَر: لا توجد خاصية «تعمل في
/// المعاينة وحدها» ([ExportContractAudit.previewOnly] فارغة)، وكل بند موسوم
/// بدليل يُراجع عند تغيير المعمارية.
///
/// التصدير الدقيق ([ExportSurface.exact]) لا يُعادة فيه حساب أي شيء: هو
/// صورة الصفحة النهائية، فيرث كل بند بالبناء — ولذلك يُذكر له حدّ صريح في
/// البنود التي لا يستطيع Word القابل للتحرير تمثيلها (فلا تُدَّعى تغطية كاذبة).
abstract final class ExportContractAudit {
  static const List<ExportContractEntry> entries = <ExportContractEntry>[
    // ------------------------------ إعدادات الورقة ------------------------------
    ExportContractEntry(
      property: 'PaperSettings.baseFontSize (fontScale)',
      effect: 'قياس كل أحجام الخطوط مرة واحدة',
      surfaces: ExportSurface.values,
      evidence: 'ExamTypography.resolve + page_snapshot_service',
    ),
    ExportContractEntry(
      property: 'PaperSettings.lineSpacing (heightScale)',
      effect: 'قياس كل ارتفاعات الأسطر ومضاعفات w:line',
      surfaces: ExportSurface.values,
      evidence: 'ExamTypography.resolve + VisualTextStyle.lineTwips',
    ),
    ExportContractEntry(
      property: 'PaperSettings.defaultFont',
      effect: 'الخط الافتراضي لكل الأدوار',
      surfaces: ExportSurface.values,
      evidence: 'ExamTypography.resolve(font:) + DocxDocumentExportService._fontName',
    ),
    ExportContractEntry(
      property: 'PaperSettings.marginMm',
      effect: 'صندوق المحتوى والهوامش والإطار',
      surfaces: ExportSurface.values,
      evidence: 'PaperMetrics.contentWidthFor/pageContentHeightFor + w:pgMar',
    ),
    ExportContractEntry(
      property: 'PaperSettings.numerals',
      effect: 'نسق الأرقام في الترقيم والدرجات',
      surfaces: ExportSurface.values,
      evidence: 'ExamBlueprint (_value/_marks) → displayItemLabel/formatNumber',
    ),
    ExportContractEntry(
      property: 'PaperSettings.questionLabelStyle',
      effect: 'نمط تسمية السؤال (رسمي/مختصر)',
      surfaces: ExportSurface.values,
      evidence: 'ExamDocument.autoQuestionLabel في البناء الثلاثي',
    ),
    ExportContractEntry(
      property: 'PaperSettings.autoNumberQuestions/autoLetterBranches',
      effect: 'إعادة الترقيم بعد الحذف/النقل',
      surfaces: ExportSurface.values,
      evidence: 'ExamDocument.displayBranchLabel/displayItemLabel',
    ),
    ExportContractEntry(
      property: 'PaperSettings.showQuestionMarks',
      effect: 'إظهار «(٢٠ درجة)» أو إخفاؤها',
      surfaces: ExportSurface.values,
      evidence: 'ExamBlueprint._marks → title.marks',
    ),
    ExportContractEntry(
      property: 'PaperSettings.headerBorder',
      effect: 'إطار جدول الترويسة',
      surfaces: ExportSurface.values,
      evidence: 'HeaderBlueprint.framed → PaperHeaderView/w:tblBorders/_buildHeader',
    ),
    ExportContractEntry(
      property: 'PaperSettings.pageBorder + frameImagePath',
      effect: 'إطار الصفحة (صورة أو متجه) باتباع الهامش',
      surfaces: ExportSurface.values,
      evidence: 'PDF frame() / DOCX _buildFrameHeader+pgBorders / _buildPageFrame',
    ),

    // ------------------------------ الترويسة والتذييل ------------------------------
    ExportContractEntry(
      property: 'ExamHeaderModel.{schoolName,examType,academicYear,session,'
          'schoolGender,subject,grade,time}',
      effect: 'أسطر الترويسة الثلاثة',
      surfaces: ExportSurface.values,
      evidence: 'HeaderBlueprint → _headerBlock/header()/_buildHeader',
    ),
    ExportContractEntry(
      property: 'ExamHeaderModel.showBismillah',
      effect: 'سطر البسملة بخط أميري مستقل',
      surfaces: ExportSurface.values,
      evidence: 'VisualRole.bismillah في الثلاثة',
    ),
    ExportContractEntry(
      property: 'ExamHeaderModel.style.{font,fontSize,bold,italic,underline,'
          'color,align,lineHeight,paragraphSpacing}',
      effect: 'تنسيق سطور الترويسة والتذييل',
      surfaces: ExportSurface.values,
      evidence: 'roleStyle(headerBody) + _headerParagraph(line/after/jc)',
    ),
    ExportContractEntry(
      property: 'ExamFooterModel.{closingPhrase,primary,secondary}',
      effect: 'العبارة الختامية والتوقيعات في أسفل آخر صفحة',
      surfaces: ExportSurface.values,
      evidence: 'FooterBlueprint → PaperFooterView/footer()/_buildFooterTable',
    ),

    // ------------------------------ بنية السؤال ------------------------------
    ExportContractEntry(
      property: 'QuestionModel.category',
      effect: 'سطر القسم قبل سطر العنوان',
      surfaces: ExportSurface.values,
      evidence: 'VisualElementKind.category',
    ),
    ExportContractEntry(
      property: 'QuestionModel.categoryAlign',
      effect: 'محاذاة سطر القسم (left/center/right) مستقلةً عن السؤال',
      surfaces: ExportSurface.values,
      evidence: 'VisualRole.category + toPdfAlign(categoryAlign) + _wordAlign(categoryAlign)',
    ),
    ExportContractEntry(
      property: 'QuestionModel.{statement,marks,numberOverride}',
      effect: 'سطر العنوان: الرقم ← المنطوق ← الدرجة',
      surfaces: ExportSurface.values,
      evidence: 'TitleLineBlueprint + VisualElementKind.title',
    ),
    ExportContractEntry(
      property: 'QuestionModel.{titleAlign,bodyAlign,style.align}',
      effect: 'محاذاة الكتابة داخل السؤال',
      surfaces: ExportSurface.values,
      evidence: 'VisualElement.align → toPdfAlign/_wordAlign/_textAlignFor',
    ),
    ExportContractEntry(
      property: 'QuestionModel.body',
      effect: 'نص السؤال (يُحذف عند فراغه)',
      surfaces: ExportSurface.values,
      evidence: 'QuestionBlueprint.body → VisualRole.questionBody',
    ),
    ExportContractEntry(
      property: 'QuestionModel.style.{font,fontSize,bold,italic,underline,'
          'color,lineHeight,paragraphSpacing}',
      effect: 'تنسيق السؤال المخصص (مطلق يتقدم على القياس العام)',
      surfaces: ExportSurface.values,
      evidence: 'ExamTypography.resolve(override:)',
    ),
    ExportContractEntry(
      property: 'QuestionModel.showFrame',
      effect: 'إطار حول كتلة السؤال',
      surfaces: ExportSurface.values,
      evidence: 'VisualMetrics.questionFramePaddingPx في الثلاثة',
    ),
    ExportContractEntry(
      property: 'QuestionModel.dividerAfter',
      effect: 'فاصل رسومي بعد السؤال',
      surfaces: ExportSurface.values,
      evidence: 'VisualElementKind.divider → _divider/_buildDividerWidget',
    ),
    ExportContractEntry(
      property: 'QuestionModel.spacingAfter',
      effect: 'المسافة بين السؤال والسؤال التالي',
      surfaces: ExportSurface.values,
      evidence: 'PaginationEngine.spacingAfter + _writeQuestionSpacing',
    ),

    // ------------------------------ الفرع والنقاط ------------------------------
    ExportContractEntry(
      property: 'BranchModel.{content.statement,marks}',
      effect: 'سطر عنوان الفرع',
      surfaces: ExportSurface.values,
      evidence: 'VisualRole.branchTitle (إزاحة 26px = 390 تويب)',
    ),
    ExportContractEntry(
      property: 'BranchModel.{content.body,style,showFrame,dividerAfter}',
      effect: 'نص الفرع وتنسيقه وإطاره وفاصله',
      surfaces: ExportSurface.values,
      evidence: 'VisualRole.branchBody + branchGapPx',
    ),
    ExportContractEntry(
      property: 'BranchItem.{kind,text,labelOverride,marks,align}',
      effect: 'سطر النقطة (الرقم ← النص ← الملحق ← الدرجة)',
      surfaces: ExportSurface.values,
      evidence: 'VisualRole.point + pointIndentPx',
    ),
    ExportContractEntry(
      property: 'QuestionOption.{text,labelOverride}',
      effect: 'صف الخيارات تحت النقطة',
      surfaces: ExportSurface.values,
      evidence: 'VisualRole.option + optionIndentPx/optionLabelGapPx',
    ),
    ExportContractEntry(
      property: 'QuestionOption.align',
      effect: 'محاذاة خيار بعينه',
      // Word القابل للتحرير يكتب صف الخيارات فقرةً واحدة (نص متصل) كما كان،
      // فلا يميّز محاذاة خيار داخل الصف؛ أما Exact فيرث المحاذاة بالصورة.
      surfaces: <ExportSurface>[
        ExportSurface.preview,
        ExportSurface.pdfVector,
        ExportSurface.exact,
      ],
      evidence: 'option.option.align في المعاينة وPDF (قيد معلن في Word)',
    ),

    // ------------------------------ العناصر الحرة والمعادلات ------------------------------
    ExportContractEntry(
      property: 'FloatingElement.{dx,dy,width,height,rotationDegrees}',
      effect: 'موضع العنصر وحجمه ودورانه بإحداثيات اللوحة',
      surfaces: ExportSurface.values,
      evidence: 'ExamCanvasGeometry 1:1 + pw.Positioned + w:drawing (wp:anchor)',
    ),
    ExportContractEntry(
      property: 'FloatingElement.pageIndex',
      effect: 'الصفحة التي يقيم فيها العنصر',
      surfaces: ExportSurface.values,
      evidence: '_elementGeometry.pageIndex → placements في الثلاثة',
    ),
    ExportContractEntry(
      property: 'FloatingElement.textStyle / shape / formula',
      effect: 'تنسيق مربع النص ورسم الشكل والمعادلة',
      surfaces: ExportSurface.values,
      evidence: 'FloatingElementsPdf.build + _buildTextBox + MathRasters/OMML',
    ),
    ExportContractEntry(
      property: r'النص الغني ($...$ و﴿...﴾)',
      effect: 'مقاطع نص/رياضيات/قرآن داخل السطر',
      surfaces: ExportSurface.values,
      evidence: 'RichContent.parse → لقطات PDF/Word ومحرك المعاينة',
    ),
  ];

  /// بنود لا تصل إلا إلى المعاينة — يجب أن تكون فارغة دائماً.
  static List<ExportContractEntry> get previewOnly =>
      entries.where((entry) => entry.isPreviewOnly).toList(growable: false);

  /// بنود تُعلن تغطية جزئية (يقيناً لا ادّعاء): تُعرَض في تقرير الجاهزية.
  static List<ExportContractEntry> get partial =>
      entries.where((entry) => entry.isPartial).toList(growable: false);

  /// بنود وصلت إلى كل الأسطح بلا استثناء.
  static List<ExportContractEntry> get complete => entries
      .where((entry) => entry.surfaces.length == ExportSurface.values.length)
      .toList(growable: false);
}
