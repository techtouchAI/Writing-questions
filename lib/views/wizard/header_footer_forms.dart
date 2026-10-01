import 'package:flutter/material.dart';

import '../../models/exam_catalog.dart';
import '../../models/exam_footer_model.dart';
import '../../models/exam_header_model.dart';
import '../../models/subject_catalog.dart';
import '../widgets/labeled_dropdown.dart';
import '../widgets/suggestion_text_field.dart';

/// عنوان قسم داخل نموذج الترويسة/التذييل.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

/// نموذج بيانات الترويسة (مدخلات منظّمة بتلميحات إرشادية لكل حقل).
///
/// نموذج «حي»: كل تعديل يستدعي [onChanged] بالترويسة الجديدة فوراً، فيستعمله
/// معالج الخطوة 1 (مسودة تُحفظ عند المتابعة) وورقة التعديل السريع على
/// المعاينة (تُطبَّق التعديلات مباشرة) بالشيفرة نفسها.
///
/// الحقول بحسب مواصفة الورقة: اسم المدرسة (يمين)، البسملة/نوع الامتحان/
/// العام الدراسي/الدور (وسط)، المادة/الصف/الوقت (يسار).
class HeaderForm extends StatefulWidget {
  const HeaderForm({
    super.key,
    required this.initial,
    required this.onChanged,
    this.now,
  });

  final ExamHeaderModel initial;
  final ValueChanged<ExamHeaderModel> onChanged;

  /// تاريخ اقتراحات العام الدراسي (الآن افتراضياً؛ يُمرَّر في الاختبارات).
  final DateTime? now;

  @override
  State<HeaderForm> createState() => _HeaderFormState();
}

class _HeaderFormState extends State<HeaderForm> {
  static const String _customSubject = '__custom_subject__';
  static const String _noSubject = '__no_subject__';

  late ExamHeaderModel _header;
  late final TextEditingController _school;
  late final TextEditingController _examType;
  late final TextEditingController _year;
  late final TextEditingController _grade;
  late final TextEditingController _time;
  late final TextEditingController _subject;
  late bool _customMode;

  @override
  void initState() {
    super.initState();
    _header = widget.initial;
    _school = TextEditingController(text: _header.schoolName);
    _examType = TextEditingController(text: _header.examType);
    _year = TextEditingController(text: _header.academicYear);
    _grade = TextEditingController(text: _header.grade);
    _time = TextEditingController(text: _header.time);
    _subject = TextEditingController(text: _header.subject);
    _customMode = _header.subject.isNotEmpty &&
        !SubjectCatalog.knownSubjects.contains(_header.subject);
  }

  @override
  void dispose() {
    _school.dispose();
    _examType.dispose();
    _year.dispose();
    _grade.dispose();
    _time.dispose();
    _subject.dispose();
    super.dispose();
  }

  void _update(ExamHeaderModel next) {
    setState(() => _header = next);
    widget.onChanged(next);
  }

  Widget _gap() => const SizedBox(height: 12);

  Widget _subjectField() {
    if (_customMode) {
      return TextFormField(
        controller: _subject,
        decoration: InputDecoration(
          labelText: 'المادة',
          hintText: 'أدخل اسم المادة هنا',
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'اختيار من المواد المعرفة',
            onPressed: () {
              setState(() => _customMode = false);
              _update(_header.copyWith(subject: ''));
              _subject.clear();
            },
          ),
        ),
        onChanged: (value) => _update(_header.copyWith(subject: value.trim())),
      );
    }
    const known = SubjectCatalog.knownSubjects;
    final subject = _header.subject;
    return LabeledDropdown<String>(
      label: 'المادة',
      hint: 'اختر المادة (أو اتركها منقطة للكتابة اليدوية)',
      value: subject.isEmpty
          ? _noSubject
          : (known.contains(subject) ? subject : null),
      values: const <String>[...known, _customSubject, _noSubject],
      labelOf: (value) {
        if (value == _customSubject) {
          return 'مادة أخرى (إدخال يدوي)';
        }
        if (value == _noSubject) {
          return 'بدون (تُطبع منقطة)';
        }
        return value;
      },
      onChanged: (value) {
        if (value == _customSubject) {
          setState(() => _customMode = true);
          _subject.clear();
          _update(_header.copyWith(subject: ''));
          return;
        }
        _update(_header.copyWith(subject: value == _noSubject ? '' : value));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final template = _header.layoutTemplate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SectionTitle('يمين الورقة: المدرسة', icon: Icons.school_outlined),
        _gap(),
        TextFormField(
          controller: _school,
          decoration: const InputDecoration(
            labelText: 'اسم المدرسة',
            hintText: 'أدخل اسم المدرسة هنا',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => _update(_header.copyWith(schoolName: value)),
        ),
        _gap(),
        LabeledDropdown<SchoolGender>(
          label: 'السطر الثالث',
          hint: 'اختر للبنين أو للبنات',
          value: _header.schoolGender,
          values: SchoolGender.values,
          labelOf: (gender) => gender.menuLabel,
          onChanged: (gender) => _update(_header.copyWith(schoolGender: gender)),
        ),
        const SizedBox(height: 20),
        const _SectionTitle('وسط الورقة: الامتحان', icon: Icons.assignment_outlined),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('إظهار البسملة'),
          subtitle: const Text('بسم الله الرحمن الرحيم بخط خطّي أنيق'),
          value: _header.showBismillah,
          onChanged: (value) => _update(_header.copyWith(showBismillah: value)),
        ),
        SuggestionTextField(
          controller: _examType,
          label: 'نوع الامتحان',
          hint: 'مثال: نصف السنة أو نهاية السنة',
          suggestions: ExamCatalog.examTypeSuggestions,
          onChanged: (value) => _update(_header.copyWith(examType: value)),
        ),
        _gap(),
        SuggestionTextField(
          controller: _year,
          label: 'العام الدراسي',
          hint: 'مثال: 2026/2027',
          suggestions: AcademicYear.suggestions(widget.now),
          onChanged: (value) => _update(_header.copyWith(academicYear: value)),
        ),
        _gap(),
        LabeledDropdown<ExamSession>(
          label: 'الدور الامتحاني (يُطبع تحت العام الدراسي)',
          hint: 'اختر الدور الأول أو الثاني أو الثالث',
          value: _header.session,
          values: ExamSession.values,
          labelOf: (session) => session.menuLabel,
          onChanged: (session) => _update(_header.copyWith(session: session)),
        ),
        const SizedBox(height: 20),
        const _SectionTitle('يسار الورقة: المادة والصف', icon: Icons.menu_book_outlined),
        _gap(),
        _subjectField(),
        const SizedBox(height: 4),
        Text(
          'قالب التنسيق: ${template.arabicLabel}${template.isLtr ? ' (LTR)' : ''}',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        _gap(),
        TextFormField(
          controller: _grade,
          decoration: const InputDecoration(
            labelText: 'الصف',
            hintText: 'مثال: الثالث المتوسط',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => _update(_header.copyWith(grade: value)),
        ),
        _gap(),
        SuggestionTextField(
          controller: _time,
          label: 'الوقت',
          hint: 'مثال: ساعتان',
          suggestions: ExamCatalog.timeSuggestions,
          onChanged: (value) => _update(_header.copyWith(time: value)),
        ),
        const SizedBox(height: 6),
        const Text(
          'الحقول الفارغة (المادة/الصف/الوقت) تُطبع خطاً منقطاً للكتابة اليدوية.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}

/// نموذج التذييل: العبارة الختامية (قائمة من عشر عبارات) وكتلتا التوقيع.
///
/// التوقيع الأساسي يظهر **يسار** الورقة دائماً، والثاني **يمينها** فقط بعد أن
/// يضيفه المدرس صراحةً (ويمكنه إزالته). نموذج «حي» كـ[HeaderForm].
class FooterForm extends StatefulWidget {
  const FooterForm({super.key, required this.initial, required this.onChanged});

  final ExamFooterModel initial;
  final ValueChanged<ExamFooterModel> onChanged;

  @override
  State<FooterForm> createState() => _FooterFormState();
}

class _FooterFormState extends State<FooterForm> {
  late ExamFooterModel _footer;
  late final TextEditingController _primaryName;
  late final TextEditingController _secondaryName;

  @override
  void initState() {
    super.initState();
    _footer = widget.initial;
    _primaryName = TextEditingController(text: _footer.primary.name);
    _secondaryName = TextEditingController(text: _footer.secondary?.name ?? '');
  }

  @override
  void dispose() {
    _primaryName.dispose();
    _secondaryName.dispose();
    super.dispose();
  }

  void _update(ExamFooterModel next) {
    setState(() => _footer = next);
    widget.onChanged(next);
  }

  Widget _signatureFields({
    required String heading,
    required SignatureModel signature,
    required TextEditingController nameController,
    required ValueChanged<SignatureModel> onChanged,
    Widget? trailing,
  }) {
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(heading, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 10),
            LabeledDropdown<SignatureTitle>(
              label: 'اللقب',
              hint: 'اختر اللقب',
              value: signature.title,
              values: SignatureTitle.values,
              labelOf: (title) => title.label,
              onChanged: (title) => onChanged(signature.copyWith(title: title)),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'الاسم',
                hintText: 'أدخل اسمك هنا (أو اتركه منقطاً للتوقيع اليدوي)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => onChanged(signature.copyWith(name: value)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phrases = <String>[
      '',
      ...ExamCatalog.closingPhrases,
      if (_footer.closingPhrase.isNotEmpty &&
          !ExamCatalog.closingPhrases.contains(_footer.closingPhrase))
        _footer.closingPhrase,
    ];
    final secondary = _footer.secondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SectionTitle('تذييل الورقة (أسفل آخر صفحة)', icon: Icons.draw_outlined),
        const SizedBox(height: 12),
        LabeledDropdown<String>(
          label: 'العبارة الختامية (وسط التذييل)',
          hint: 'اختر عبارة ختامية',
          value: _footer.closingPhrase,
          values: phrases,
          labelOf: (phrase) => phrase.isEmpty ? 'بدون عبارة ختامية' : phrase,
          onChanged: (phrase) => _update(_footer.copyWith(closingPhrase: phrase)),
        ),
        const SizedBox(height: 12),
        _signatureFields(
          heading: 'التوقيع الأساسي (يسار الورقة)',
          signature: _footer.primary,
          nameController: _primaryName,
          onChanged: (signature) => _update(_footer.copyWith(primary: signature)),
        ),
        const SizedBox(height: 12),
        if (secondary == null)
          OutlinedButton.icon(
            onPressed: () => _update(_footer.withSecondaryAdded()),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('إضافة مدرس ثانٍ (يمين الورقة)'),
          )
        else
          _signatureFields(
            heading: 'التوقيع الثاني (يمين الورقة)',
            signature: secondary,
            nameController: _secondaryName,
            onChanged: (signature) =>
                _update(_footer.copyWith(secondary: () => signature)),
            trailing: TextButton.icon(
              onPressed: () {
                _secondaryName.clear();
                _update(_footer.withSecondaryRemoved());
              },
              icon: const Icon(Icons.person_remove_outlined, size: 18),
              label: const Text('إزالة'),
            ),
          ),
      ],
    );
  }
}
