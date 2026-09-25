import 'package:flutter/material.dart';

import '../../models/exam_header_model.dart';
import '../../models/paper_font.dart';
import '../../models/paper_settings.dart';
import '../../models/paper_text_style.dart';
import '../../models/subject_catalog.dart';
import '../../models/subject_layout.dart';

/// الخطوة 1 من المعالج: إدخال وتصميم الترويسة (عنوان + يمين / وسط / يسار).
///
/// الحقول مقسّمة إلى بطاقات تحاكي أعمدة الورقة؛ بالإضافة إلى نموذج إدخال منظم
/// يتيح تعبئة معلومات الجهة، الامتحان، الطالب، والوقت والدرجة وتوزيعها مباشرة
/// على الأعمدة. جميع الحقول اختيارية وقابلة للتعديل والحذف، وتصميم الترويسة
/// (الخط/الحجم/المحاذاة/الإطار) يُعاين مباشرة قبل المتابعة.
class HeaderStepScreen extends StatefulWidget {
  const HeaderStepScreen({
    super.key,
    required this.initialHeader,
    required this.initialName,
    required this.initialSettings,
    required this.onNext,
  });

  final ExamHeaderModel initialHeader;
  final String initialName;
  final PaperSettings initialSettings;

  /// يُستدعى بالترويسة النهائية واسم النموذج والإعدادات عند [التالي].
  final void Function(ExamHeaderModel header, String name, PaperSettings settings) onNext;

  @override
  State<HeaderStepScreen> createState() => _HeaderStepScreenState();
}

class _HeaderStepScreenState extends State<HeaderStepScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _subjectController;
  late final TextEditingController _instructionsController;
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final Map<HeaderSlot, List<TextEditingController>> _columns;
  late bool _customSubject;
  late PaperFont _font;
  late double _fontSize;
  late bool _bold;
  late PaperAlign _align;
  late bool _headerBorder;

  // حقول النموذج المنظم الإضافية للتعبئة السريعة المرتبة
  late final TextEditingController _countryController;
  late final TextEditingController _ministryController;
  late final TextEditingController _directorateController;
  late final TextEditingController _schoolController;
  late final TextEditingController _gradeController;
  late final TextEditingController _branchFieldController;
  late final TextEditingController _academicYearController;
  late final TextEditingController _examRoundController;
  late final TextEditingController _examTypeController;
  late final TextEditingController _durationController;
  late final TextEditingController _totalMarksController;
  late final TextEditingController _studentNameController;
  late final TextEditingController _studentNoController;
  late final TextEditingController _studentSectionController;

  bool _showStructuredHelper = false;

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
    _customSubject = !SubjectCatalog.knownSubjects.contains(header.subject);
    _font = header.style.font ?? widget.initialSettings.defaultFont;
    _fontSize = (header.style.fontSize ?? 10).clamp(8.0, 16.0).toDouble();
    _bold = header.style.bold ?? false;
    _align = header.style.align ?? PaperAlign.center;
    _headerBorder = widget.initialSettings.headerBorder;

    _countryController = TextEditingController(text: 'جمهورية العراق');
    _ministryController = TextEditingController(text: 'وزارة التربية');
    _directorateController = TextEditingController(text: 'المديرية العامة للتربية');
    _schoolController = TextEditingController(text: 'اسم المدرسة');
    _gradeController = TextEditingController(text: 'الصف الثالث المتوسط');
    _branchFieldController = TextEditingController(text: '');
    _academicYearController = TextEditingController(text: '2025-2026');
    _examRoundController = TextEditingController(text: 'الدور الأول');
    _examTypeController = TextEditingController(text: 'امتحان نصف السنة');
    _durationController = TextEditingController(text: 'ساعتان ونصف');
    _totalMarksController = TextEditingController(text: '100');
    _studentNameController = TextEditingController(text: 'اسم الطالب:');
    _studentNoController = TextEditingController(text: 'الرقم الامتحاني:');
    _studentSectionController = TextEditingController(text: 'الشعبة:');
  }

  @override
  void dispose() {
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
    _countryController.dispose();
    _ministryController.dispose();
    _directorateController.dispose();
    _schoolController.dispose();
    _gradeController.dispose();
    _branchFieldController.dispose();
    _academicYearController.dispose();
    _examRoundController.dispose();
    _examTypeController.dispose();
    _durationController.dispose();
    _totalMarksController.dispose();
    _studentNameController.dispose();
    _studentNoController.dispose();
    _studentSectionController.dispose();
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

  void _applyStructuredHelper() {
    final subject = _subjectController.text.trim().isEmpty ? 'اللغة العربية' : _subjectController.text.trim();
    final ministry = _ministryController.text.trim().isEmpty ? 'وزارة التربية' : _ministryController.text.trim();
    final school = _schoolController.text.trim().isEmpty ? 'اسم المدرسة' : _schoolController.text.trim();
    final directorate = _directorateController.text.trim();
    final grade = _gradeController.text.trim().isEmpty ? 'الصف الثالث المتوسط' : _gradeController.text.trim();
    final branch = _branchFieldController.text.trim();
    final gradeFull = branch.isNotEmpty ? '$grade — $branch' : grade;
    final year = _academicYearController.text.trim().isEmpty ? '2025-2026' : _academicYearController.text.trim();
    final round = _examRoundController.text.trim().isEmpty ? 'الدور الأول' : _examRoundController.text.trim();
    final examType = _examTypeController.text.trim().isEmpty ? 'امتحان نصف السنة' : _examTypeController.text.trim();
    final duration = _durationController.text.trim().isEmpty ? 'ساعتان' : _durationController.text.trim();
    final marks = _totalMarksController.text.trim();

    setState(() {
      // العمود الأيمن
      _columns[HeaderSlot.right]![0].text = 'التاريخ:      /      /';
      _columns[HeaderSlot.right]![1].text = 'المادة: $subject';
      _columns[HeaderSlot.right]![2].text = gradeFull;

      // العمود الأوسط
      _columns[HeaderSlot.center]![0].text = directorate.isNotEmpty ? '$ministry — $directorate' : '$ministry — $school';
      _columns[HeaderSlot.center]![1].text = '$examType للعام الدراسي $year';
      _columns[HeaderSlot.center]![2].text = round;

      // العمود الأيسر
      _columns[HeaderSlot.left]![0].text = 'الوقت: $duration';
      _columns[HeaderSlot.left]![1].text = _studentNameController.text.trim().isEmpty ? 'اسم الطالب:' : _studentNameController.text.trim();
      _columns[HeaderSlot.left]![2].text = _studentNoController.text.trim().isEmpty ? 'الرقم الامتحاني:' : _studentNoController.text.trim();

      // العنوان والملاحظات
      if (_titleController.text.trim().isEmpty) {
        _titleController.text = 'أسئلة امتحان مادة $subject للعام الدراسي $year — $round';
      }
      if (marks.isNotEmpty && _notesController.text.trim().isEmpty) {
        _notesController.text = 'الدرجة الكلية: $marks درجة';
      }
      if (_instructionsController.text.trim().isEmpty) {
        _instructionsController.text = 'ملاحظة: أجب عن جميع الأسئلة الآتية.';
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم توزيع معلومات الترويسة على الأعمدة بنجاح.')),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
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
                  hintText: 'مثال: أسئلة امتحان مادة اللغة العربية للعام الدراسي 2025-2026',
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
              _buildStructuredHelperCard(),
              const SizedBox(height: 12),
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
                  hintText: 'مثال: ملاحظة: أجب عن جميع الأسئلة الآتية.',
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
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('التالي: إعداد السؤال الأول',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStructuredHelperCard() {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.4)),
      ),
      color: theme.colorScheme.primaryContainer.withOpacity(0.2),
      child: ExpansionTile(
        initiallyExpanded: _showStructuredHelper,
        onExpansionChanged: (val) => setState(() => _showStructuredHelper = val),
        leading: Icon(Icons.view_headline_outlined, color: theme.colorScheme.primary),
        title: const Text(
          'نموذج تفصيلي لمعلومات الترويسة (اختياري للتعبئة المنظمة)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
        ),
        subtitle: const Text(
          'الجهة، المدرسة، الصف، الفرع، العام الدراسي، الدور، الوقت، الطالب...',
          style: TextStyle(fontSize: 11),
        ),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  controller: _countryController,
                  decoration: const InputDecoration(labelText: 'الدولة / الجهة', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _ministryController,
                  decoration: const InputDecoration(labelText: 'وزارة التربية', isDense: true, border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  controller: _directorateController,
                  decoration: const InputDecoration(labelText: 'المديرية العامة', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _schoolController,
                  decoration: const InputDecoration(labelText: 'اسم المدرسة', isDense: true, border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  controller: _gradeController,
                  decoration: const InputDecoration(labelText: 'الصف / المرحلة', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _branchFieldController,
                  decoration: const InputDecoration(labelText: 'الفرع (علمي/أدبي...)', isDense: true, border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  controller: _academicYearController,
                  decoration: const InputDecoration(labelText: 'العام الدراسي', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _examRoundController,
                  decoration: const InputDecoration(labelText: 'الدور', isDense: true, border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  controller: _examTypeController,
                  decoration: const InputDecoration(labelText: 'نوع الامتحان', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _durationController,
                  decoration: const InputDecoration(labelText: 'الوقت', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _totalMarksController,
                  decoration: const InputDecoration(labelText: 'الدرجة الكلية', isDense: true, border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  controller: _studentNameController,
                  decoration: const InputDecoration(labelText: 'معلومات الطالب: الاسم', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _studentNoController,
                  decoration: const InputDecoration(labelText: 'الرقم الامتحاني', isDense: true, border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _applyStructuredHelper,
              icon: const Icon(Icons.sync_alt, size: 18),
              label: const Text('توزيع المعلومات على أعمدة الترويسة والعنوان'),
            ),
          ),
          const SizedBox(height: 8),
        ],
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
                Expanded(
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                TextButton(
                  onPressed: () {
                    for (final c in controllers) {
                      c.clear();
                    }
                    setState(() {});
                  },
                  child: const Text('تفريغ', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (var index = 0; index < controllers.length; index++) ...<Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextFormField(
                  controller: controllers[index],
                  decoration: InputDecoration(
                    labelText: 'السطر ${index + 1} (${hints[index]})',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDesignCard() {
    return Card(
      elevation: 0,
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

  Widget _buildLivePreview() {
    final title = _titleController.text.trim();
    final notes = _notesController.text.trim();
    final instructions = _instructionsController.text.trim();
    final textStyle = TextStyle(
      fontFamily: _font.family,
      fontSize: _fontSize,
      fontWeight: _bold ? FontWeight.bold : FontWeight.normal,
    );
    final border = _headerBorder
        ? Border.all(color: Colors.grey.shade400, width: 1)
        : null;

    return Card(
      elevation: 1,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'معاينة حية للترويسة (كما ستظهر في الورقة):',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            if (title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: textStyle.copyWith(fontSize: _fontSize + 2, fontWeight: FontWeight.bold),
                ),
              ),
            Container(
              decoration: BoxDecoration(border: border),
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: _buildPreviewColumn(HeaderSlot.right, textStyle),
                  ),
                  Expanded(
                    child: _buildPreviewColumn(HeaderSlot.center, textStyle),
                  ),
                  Expanded(
                    child: _buildPreviewColumn(HeaderSlot.left, textStyle),
                  ),
                ],
              ),
            ),
            if (instructions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  instructions,
                  style: textStyle.copyWith(fontStyle: FontStyle.italic),
                  textAlign: _previewAlign(),
                ),
              ),
            if (notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  notes,
                  style: textStyle.copyWith(fontSize: _fontSize - 1, color: Colors.grey.shade700),
                  textAlign: _previewAlign(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewColumn(HeaderSlot slot, TextStyle style) {
    final lines = _columns[slot]!.map((c) => c.text).toList();
    return Column(
      crossAxisAlignment: slot == HeaderSlot.center
          ? CrossAxisAlignment.center
          : slot == HeaderSlot.left
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
      children: lines
          .where((l) => l.trim().isNotEmpty)
          .map((line) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Text(
                  line,
                  style: style,
                  textAlign: slot == HeaderSlot.center
                      ? TextAlign.center
                      : slot == HeaderSlot.left
                          ? TextAlign.end
                          : TextAlign.start,
                ),
              ))
          .toList(),
    );
  }
}
