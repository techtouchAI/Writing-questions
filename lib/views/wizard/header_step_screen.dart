import 'package:flutter/material.dart';

import '../../models/exam_header_model.dart';
import '../../models/subject_catalog.dart';
import '../../models/subject_layout.dart';

/// الخطوة 1 من المعالج: إدخال الترويسة الوزارية (يمين / وسط / يسار).
///
/// الحقول مقسّمة إلى ثلاث بطاقات تحاكي أعمدة النموذج الوزاري؛ تغيير المادة
/// يعيد اختيار قالب التنسيق ([SubjectLayoutTemplate]) ويعيد تعبئة الأعمدة
/// بالقيم الافتراضية للقالب عند الطلب.
class HeaderStepScreen extends StatefulWidget {
  const HeaderStepScreen({
    super.key,
    required this.initialHeader,
    required this.initialName,
    required this.onNext,
  });

  final ExamHeaderModel initialHeader;
  final String initialName;

  /// يُستدعى بالترويسة النهائية واسم النموذج عند الضغط على [التالي].
  final void Function(ExamHeaderModel header, String name) onNext;

  @override
  State<HeaderStepScreen> createState() => _HeaderStepScreenState();
}

class _HeaderStepScreenState extends State<HeaderStepScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _subjectController;
  late final TextEditingController _instructionsController;
  late final Map<HeaderSlot, List<TextEditingController>> _columns;
  late bool _customSubject;

  @override
  void initState() {
    super.initState();
    final header = widget.initialHeader;
    _nameController = TextEditingController(text: widget.initialName);
    _subjectController = TextEditingController(text: header.subject);
    _instructionsController = TextEditingController(text: header.instructions);
    _columns = <HeaderSlot, List<TextEditingController>>{
      for (final slot in HeaderSlot.values)
        slot: <TextEditingController>[
          for (final line in header.column(slot).lines) TextEditingController(text: line),
        ],
    };
    _customSubject = !SubjectCatalog.knownSubjects.contains(header.subject);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _subjectController.dispose();
    _instructionsController.dispose();
    for (final controllers in _columns.values) {
      for (final controller in controllers) {
        controller.dispose();
      }
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
    widget.onNext(_collect(), _nameController.text.trim());
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
                  labelText: 'اسم النموذج (للتنظيم داخل التطبيق) *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'اسم النموذج مطلوب.' : null,
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
              ),
            ],
          ],
        ),
      ),
    );
  }
}
