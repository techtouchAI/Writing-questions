import 'package:flutter/material.dart';

import '../../models/exam_header_model.dart';
import '../../models/paper_font.dart';
import '../../models/paper_settings.dart';
import '../../models/paper_text_style.dart';
import '../../models/subject_catalog.dart';
import '../../models/subject_layout.dart';

/// الخطوة 1 من المعالج: إدخال الترويسة (عنوان + يمين / وسط / يسار).
///
/// الحقول مقسّمة إلى بطاقات تحاكي أعمدة الورقة؛ تغيير المادة
/// يعيد اختيار قالب التنسيق ([SubjectLayoutTemplate]) ويعيد تعبئة الأعمدة
/// بالقيم الافتراضية للقالب عند الطلب. جميع الحقول اختيارية وقابلة للحذف
/// ما عدا اسم النموذج والمادة، وتصميم الترويسة (خط/حجم/محاذاة/إطار)
/// يُعاين مباشرة قبل المتابعة.
class HeaderStepScreen extends StatefulWidget {
  const HeaderStepScreen({
    super.key,
    required this.initialHeader,
    required this.initialName,
    required this.initialSettings,
    required this.onNext,
    this.onDraft,
  });

  final ExamHeaderModel initialHeader;
  final String initialName;
  final PaperSettings initialSettings;

  /// يُستدعى بالترويسة النهائية واسم النموذج والإعدادات عند [التالي].
  final void Function(ExamHeaderModel header, String name, PaperSettings settings) onNext;

  /// يُستدعى بالمسودة الحالية عند التخلص من الشاشة دون [التالي] (خروج
  /// مبكر بزر الرجوع) حتى لا يضيع ما كتبه المدرس قبل الحفظ التلقائي.
  final void Function(ExamHeaderModel header, String name, PaperSettings settings)? onDraft;

  @override
  State<HeaderStepScreen> createState() => _HeaderStepScreenState();
}

/// حقل واحد من نموذج معلومات الترويسة التفصيلية.
class _HeaderInfoField {
  const _HeaderInfoField(this.key, this.label, this.hint);
  final String key;
  final String label;
  final String hint;
}

/// حقول معلومات الترويسة مجمّعة بالأقسام (الجهة/الامتحان/الوقت/الطالب).
const List<MapEntry<String, List<_HeaderInfoField>>> _headerInfoSections =
    <MapEntry<String, List<_HeaderInfoField>>>[
  MapEntry<String, List<_HeaderInfoField>>('معلومات الجهة', <_HeaderInfoField>[
    _HeaderInfoField('country', 'الدولة / الجهة', 'جمهورية العراق'),
    _HeaderInfoField('ministry', 'الوزارة', 'وزارة التربية'),
    _HeaderInfoField('directorate', 'المديرية العامة للتربية', 'مديرية تربية بابل'),
    _HeaderInfoField('school', 'اسم المدرسة', 'إعدادية الحلة للبنين'),
  ]),
  MapEntry<String, List<_HeaderInfoField>>('معلومات الامتحان', <_HeaderInfoField>[
    _HeaderInfoField('grade', 'الصف والمرحلة', 'الصف الثالث المتوسط'),
    _HeaderInfoField('branch', 'الفرع', 'العلمي'),
    _HeaderInfoField('year', 'العام الدراسي', '2026 / 2027'),
    _HeaderInfoField('round', 'الدور', 'الدور الأول'),
    _HeaderInfoField('examType', 'نوع الامتحان', 'امتحانات نصف السنة'),
  ]),
  MapEntry<String, List<_HeaderInfoField>>('الوقت والدرجة', <_HeaderInfoField>[
    _HeaderInfoField('time', 'الوقت', 'ساعتان ونصف'),
    _HeaderInfoField('totalMarks', 'الدرجة الكلية', '100'),
  ]),
  MapEntry<String, List<_HeaderInfoField>>('معلومات الطالب', <_HeaderInfoField>[
    _HeaderInfoField('studentName', 'اسم الطالب', 'يُترك فارغاً ليملأه الطالب'),
    _HeaderInfoField('studentNumber', 'الرقم الامتحاني', 'يُترك فارغاً ليملأه الطالب'),
    _HeaderInfoField('division', 'الشعبة', 'أ'),
  ]),
];

class _HeaderStepScreenState extends State<HeaderStepScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _subjectController;
  late final TextEditingController _instructionsController;
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final Map<HeaderSlot, List<TextEditingController>> _columns;
  late final Map<String, TextEditingController> _info;
  late bool _customSubject;
  late PaperFont _font;
  late double _fontSize;
  late bool _bold;
  late PaperAlign _align;
  late bool _headerBorder;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final header = widget.initialHeader;
    _nameController = TextEditingController(text: widget.initialName);
    _subjectController = TextEditingController(text: header.subject);
    _instructionsController = TextEditingController(text: header.instructions);
    _titleController = TextEditingController(text: header.title);
    _notesController = TextEditingController(text: header.notes);
    _columns = <HeaderSlot, List<TextEditingController>>{
      for (final slot in HeaderSlot.values)
        slot: <TextEditingController>[
          for (final line in header.column(slot).lines) TextEditingController(text: line),
        ],
    };
    _info = <String, TextEditingController>{
      for (final section in _headerInfoSections)
        for (final field in section.value)
          field.key: TextEditingController(
            text: field.key == 'country'
                ? 'جمهورية العراق'
                : field.key == 'ministry'
                    ? 'وزارة التربية'
                    : '',
          ),
    };
    _customSubject = !SubjectCatalog.knownSubjects.contains(header.subject);
    _font = header.style.font ?? widget.initialSettings.defaultFont;
    _fontSize = (header.style.fontSize ?? 10).clamp(8.0, 16.0).toDouble();
    _bold = header.style.bold ?? false;
    _align = header.style.align ?? PaperAlign.center;
    _headerBorder = widget.initialSettings.headerBorder;
  }

  @override
  void dispose() {
    // خروج مبكر: حفظ المسودة (بشرط وجود مادة واسم صالحين) قبل التحرير.
    final draft = widget.onDraft;
    if (draft != null && !_submitted) {
      final name = _nameController.text.trim();
      final subject = _subjectController.text.trim();
      if (name.isNotEmpty && subject.isNotEmpty) {
        draft(_collect(), name, _collectSettings());
      }
    }
    _nameController.dispose();
    _subjectController.dispose();
    _instructionsController.dispose();
    _titleController.dispose();
    _notesController.dispose();
    for (final controllers in _columns.values) {
      for (final controller in controllers) {
        controller.dispose();
      }
    }
    for (final controller in _info.values) {
      controller.dispose();
    }
    super.dispose();
  }

  ExamHeaderModel _collect() {
    return ExamHeaderModel(
      subject: _subjectController.text.trim(),
      right: HeaderColumn(_columns[HeaderSlot.right]!.map((c) => c.text).toList()),
      center: HeaderColumn(_columns[HeaderSlot.center]!.map((c) => c.text).toList()),
      left: HeaderColumn(_columns[HeaderSlot.left]!.map((c) => c.text).toList()),
      instructions: _instructionsController.text.trim(),
      title: _titleController.text.trim(),
      notes: _notesController.text.trim(),
      style: PaperTextStyle(font: _font, fontSize: _fontSize, bold: _bold, align: _align),
    );
  }

  PaperSettings _collectSettings() {
    return widget.initialSettings.copyWith(headerBorder: _headerBorder);
  }

  /// يوزّع معلومات النموذج التفصيلية على أعمدة الترويسة والعنوان.
  ///
  /// الكتابة فوق الأعمدة والعنوان فقط؛ التعليمات والملاحظات لا تُمسّ
  /// (عدا ملء الدرجة الكلية في الملاحظات إن كانت فارغة)، وتبقى كل الأسطر
  /// قابلة للتحرير أو التفريغ يدوياً بعد التوزيع.
  void _distributeHeaderInfo() {
    String value(String key) => _info[key]!.text.trim();
    final country = value('country');
    final ministry = value('ministry');
    final directorate = value('directorate');
    final school = value('school');
    final grade = value('grade');
    final branch = value('branch');
    final year = value('year');
    final round = value('round');
    final examType = value('examType');
    final time = value('time');
    final totalMarks = value('totalMarks');
    final studentName = value('studentName');
    final studentNumber = value('studentNumber');
    final division = value('division');
    final subject = _subjectController.text.trim();

    void fillColumn(HeaderSlot slot, List<String> lines) {
      final controllers = _columns[slot]!;
      for (var i = 0; i < controllers.length; i++) {
        controllers[i].text = i < lines.length ? lines[i] : '';
      }
    }

    final examLine = <String>[examType, year].where((part) => part.isNotEmpty).join(' ');
    setState(() {
      fillColumn(HeaderSlot.right, <String>[country, ministry, directorate]);
      fillColumn(HeaderSlot.center, <String>[school, examLine, round]);
      fillColumn(HeaderSlot.left, <String>[
        time.isEmpty ? 'الوقت:' : 'الوقت: $time',
        studentName.isEmpty ? 'الاسم:' : 'الاسم: $studentName',
        studentNumber.isEmpty ? 'الرقم الامتحاني:' : 'الرقم الامتحاني: $studentNumber',
      ]);
      if (subject.isNotEmpty) {
        final titleParts = <String>['أسئلة امتحان مادة $subject'];
        final gradePart = <String>[
          grade,
          if (branch.isNotEmpty) '($branch)',
          if (division.isNotEmpty) 'شعبة $division',
        ].where((part) => part.isNotEmpty).join(' ');
        if (gradePart.isNotEmpty) {
          titleParts.add(gradePart);
        }
        _titleController.text = titleParts.join(' — ');
      }
      if (_notesController.text.trim().isEmpty && totalMarks.isNotEmpty) {
        _notesController.text = 'الدرجة الكلية: $totalMarks';
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم توزيع المعلومات على أعمدة الترويسة والعنوان.')),
    );
  }

  void _applyMinisterialDefaults() {
    final defaults = ExamHeaderModel.ministerialDefault(
      subject: _subjectController.text.trim().isEmpty
          ? 'اللغة العربية'
          : _subjectController.text.trim(),
    );
    setState(() {
      for (final slot in HeaderSlot.values) {
        final lines = defaults.column(slot).lines;
        for (var index = 0; index < lines.length; index++) {
          _columns[slot]![index].text = lines[index];
        }
      }
      _instructionsController.text = defaults.instructions;
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    _submitted = true;
    widget.onNext(_collect(), _nameController.text.trim(), _collectSettings());
  }

  @override
  Widget build(BuildContext context) {
    final template = SubjectLayoutTemplate.fromSubject(_subjectController.text);
    return Scaffold(
      appBar: AppBar(title: const Text('الخطوة 1: ترويسة النموذج الوزاري')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم الورقة (للتنظيم داخل التطبيق) *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'اسم الورقة مطلوب.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'عنوان الامتحان (يظهر أعلى الترويسة)',
                  hintText: 'مثال: أسئلة امتحان مادة اللغة العربية',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              _buildSubjectField(),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'قالب التنسيق: ${template.arabicLabel}'
                      '${template.isLtr ? ' (LTR)' : ''}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _applyMinisterialDefaults,
                    icon: const Icon(Icons.auto_fix_high, size: 18),
                    label: const Text('تعبئة وزارية افتراضية'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildInfoCard(),
              _buildColumnCard(
                slot: HeaderSlot.right,
                title: 'العمود الأيمن',
                hints: const <String>['التاريخ', 'المادة', 'الصف / المرحلة'],
                icon: Icons.align_horizontal_right,
              ),
              _buildColumnCard(
                slot: HeaderSlot.center,
                title: 'العمود الأوسط',
                hints: const <String>[
                  'وزارة التربية — اسم المدرسة',
                  'امتحانات نصف السنة 2026/2027',
                  'الدور',
                ],
                icon: Icons.align_horizontal_center,
              ),
              _buildColumnCard(
                slot: HeaderSlot.left,
                title: 'العمود الأيسر',
                hints: const <String>['الوقت', 'الاسم', 'الرقم الامتحاني'],
                icon: Icons.align_horizontal_left,
              ),
              TextFormField(
                controller: _instructionsController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة / تعليمات أعلى الأسئلة (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات إضافية أسفل الترويسة (اختياري)',
                  hintText: 'الوقت، الدرجة الكلية، أي نص...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              _buildDesignCard(),
              const SizedBox(height: 12),
              _buildLivePreview(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      // زر المتابعة ثابت أسفل الشاشة (كخطوة الأسئلة): يبقى ظاهراً وقابلاً
      // للنقر مهما طال النموذج، بدل دفنه تحت الحقول.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.arrow_back),
            label: const Text('التالي: إعداد السؤال الأول',
                style: TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }

  Widget _buildSubjectField() {
    if (_customSubject) {
      return TextFormField(
        controller: _subjectController,
        decoration: InputDecoration(
          labelText: 'المادة الدراسية *',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'اختيار من المواد المعرفة',
            onPressed: () => setState(() => _customSubject = false),
          ),
        ),
        onChanged: (_) => setState(() {}),
        validator: (value) =>
            value == null || value.trim().isEmpty ? 'المادة مطلوبة.' : null,
      );
    }
    return DropdownButtonFormField<String>(
      value: SubjectCatalog.knownSubjects.contains(_subjectController.text)
          ? _subjectController.text
          : null,
      decoration: const InputDecoration(
        labelText: 'المادة الدراسية *',
        border: OutlineInputBorder(),
      ),
      items: <DropdownMenuItem<String>>[
        ...SubjectCatalog.knownSubjects.map(
          (subject) => DropdownMenuItem<String>(value: subject, child: Text(subject)),
        ),
        const DropdownMenuItem<String>(
          value: '__custom_subject__',
          child: Text('مادة أخرى (إدخال يدوي)'),
        ),
      ],
      validator: (value) => _subjectController.text.trim().isEmpty ? 'المادة مطلوبة.' : null,
      onChanged: (value) {
        if (value == '__custom_subject__') {
          setState(() {
            _customSubject = true;
            _subjectController.clear();
          });
          return;
        }
        if (value != null) {
          setState(() => _subjectController.text = value);
        }
      },
    );
  }

  /// بطاقة نموذج معلومات الترويسة التفصيلية مع زر التوزيع التلقائي.
  Widget _buildInfoCard() {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'معلومات الترويسة التفصيلية',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'املأ الحقول ثم وزّعها على الأعمدة — وتبقى قابلة للتحرير يدوياً.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            for (final section in _headerInfoSections) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                section.key,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              for (final field in section.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextFormField(
                    controller: _info[field.key],
                    decoration: InputDecoration(
                      labelText: field.label,
                      hintText: field.hint,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _distributeHeaderInfo,
                icon: const Icon(Icons.view_column_outlined),
                label: const Text('توزيع المعلومات على أعمدة الترويسة والعنوان'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumnCard({
    required HeaderSlot slot,
    required String title,
    required List<String> hints,
    required IconData icon,
  }) {
    final controllers = _columns[slot]!;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 18),
                const SizedBox(width: 6),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            for (var index = 0; index < controllers.length; index++) ...<Widget>[
              const SizedBox(height: 8),
              TextFormField(
                controller: controllers[index],
                decoration: InputDecoration(
                  labelText: 'السطر ${index + 1}',
                  hintText: index < hints.length ? hints[index] : null,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// بطاقة تصميم الترويسة (خط/حجم/عريض/محاذاة/إطار).
  Widget _buildDesignCard() {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(Icons.palette_outlined, size: 18),
                SizedBox(width: 6),
                Text('تصميم الترويسة', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<PaperFont>(
                    value: _font,
                    decoration: const InputDecoration(
                      labelText: 'الخط',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: PaperFont.values
                        .map((font) => DropdownMenuItem<PaperFont>(
                              value: font,
                              child: Text(
                                font.arabicLabel,
                                style: TextStyle(fontSize: 12, fontFamily: font.family),
                              ),
                            ))
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _font = value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<double>(
                    value: _fontSize,
                    decoration: const InputDecoration(
                      labelText: 'الحجم',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const <double>[8, 9, 10, 11, 12, 14, 16]
                        .map((size) => DropdownMenuItem<double>(
                              value: size,
                              child: Text('${size.toInt()}',
                                  style: const TextStyle(fontSize: 12)),
                            ))
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _fontSize = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: SegmentedButton<PaperAlign>(
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const <ButtonSegment<PaperAlign>>[
                      ButtonSegment<PaperAlign>(
                        value: PaperAlign.right,
                        icon: Icon(Icons.format_align_right, size: 16),
                      ),
                      ButtonSegment<PaperAlign>(
                        value: PaperAlign.center,
                        icon: Icon(Icons.format_align_center, size: 16),
                      ),
                      ButtonSegment<PaperAlign>(
                        value: PaperAlign.left,
                        icon: Icon(Icons.format_align_left, size: 16),
                      ),
                    ],
                    selected: <PaperAlign>{_align},
                    onSelectionChanged: (selected) =>
                        setState(() => _align = selected.single),
                  ),
                ),
                IconButton(
                  tooltip: 'عريض',
                  isSelected: _bold,
                  icon: const Icon(Icons.format_bold),
                  onPressed: () => setState(() => _bold = !_bold),
                ),
                IconButton(
                  tooltip: 'إطار حول الترويسة',
                  isSelected: _headerBorder,
                  icon: const Icon(Icons.border_outer),
                  onPressed: () => setState(() => _headerBorder = !_headerBorder),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TextAlign _previewAlign() {
    switch (_align) {
      case PaperAlign.left:
        return TextAlign.left;
      case PaperAlign.center:
        return TextAlign.center;
      case PaperAlign.right:
      case PaperAlign.start:
      case PaperAlign.end:
      case PaperAlign.justify:
        return TextAlign.right;
    }
  }

  /// معاينة حية لشكل الترويسة قبل المتابعة.
  Widget _buildLivePreview() {
    final style = TextStyle(
      fontFamily: _font.family,
      fontSize: _fontSize + 4,
      fontWeight: _bold ? FontWeight.bold : FontWeight.normal,
    );
    Widget column(List<TextEditingController> controllers) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final field in controllers)
              Text(
                field.text.isEmpty ? ' ' : field.text,
                style: style.copyWith(fontSize: _fontSize + 1),
                textAlign: _previewAlign(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(Icons.preview_outlined, size: 18),
                SizedBox(width: 6),
                Text('معاينة الترويسة', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: <Widget>[
                  if (_titleController.text.trim().isNotEmpty)
                    Text(
                      _titleController.text,
                      style: style.copyWith(
                        fontSize: _fontSize + 6,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      textAlign: _previewAlign(),
                    ),
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      border: _headerBorder
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary, width: 1.2)
                          : null,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        column(_columns[HeaderSlot.right]!),
                        const SizedBox(width: 6),
                        column(_columns[HeaderSlot.center]!),
                        const SizedBox(width: 6),
                        column(_columns[HeaderSlot.left]!),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
