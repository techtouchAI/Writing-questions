import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/difficulty.dart';
import '../models/label_alphabet.dart';
import '../models/main_question.dart';
import '../models/question_branch.dart';
import '../models/question_option.dart';
import '../models/question_type.dart';
import '../models/subject_catalog.dart';
import '../providers/question_provider.dart';
import 'widgets/ltr_numeric_field.dart';
import 'widgets/mcq_options_editor.dart';

/// مسودة فرع واحد أثناء التحرير (تحكمات نصية مستقلة تُطرح عند الحذف).
class _BranchDraft {
  _BranchDraft({required String text, required String marks})
      : textController = TextEditingController(text: text),
        marksController = TextEditingController(text: marks);

  final TextEditingController textController;
  final TextEditingController marksController;

  void dispose() {
    textController.dispose();
    marksController.dispose();
  }
}

class QuestionEditorScreen extends StatefulWidget {
  const QuestionEditorScreen({super.key, this.existingQuestion});

  final MainQuestion? existingQuestion;

  @override
  State<QuestionEditorScreen> createState() => _QuestionEditorScreenState();
}

class _QuestionEditorScreenState extends State<QuestionEditorScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _subjectController;
  late final TextEditingController _topicController;
  late final TextEditingController _categoryController;
  late final TextEditingController _modelAnswerController;
  late final TextEditingController _explanationController;

  late QuestionType _type;
  late Difficulty _difficulty;
  late List<QuestionOption> _options;
  late bool _customSubject;
  late String _selectedCategory;
  bool _customCategory = false;
  late List<_BranchDraft> _branchDrafts;
  bool _trueFalseAnswer = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final question = widget.existingQuestion;
    _type = question?.type ?? QuestionType.multipleChoice;
    _difficulty = question?.difficulty ?? Difficulty.medium;
    _options = question?.options
            .map((option) => option.copyWith())
            .toList(growable: false) ??
        _defaultOptions();
    _trueFalseAnswer = _trueFalseValue(question?.options);

    _titleController = TextEditingController(text: question?.title ?? '');
    _subjectController = TextEditingController(text: question?.subject ?? 'عام');
    _topicController = TextEditingController(text: question?.topic ?? '');
    _categoryController = TextEditingController(text: question?.category ?? '');
    _modelAnswerController = TextEditingController(
      text: question?.modelAnswer ?? '',
    );
    _explanationController = TextEditingController(
      text: question?.explanation ?? '',
    );

    // المادة المعروفة تُختار من القائمة، وغيرها يبقى إدخالاً يدوياً.
    final subject = _subjectController.text;
    _customSubject = subject.isEmpty || !SubjectCatalog.knownSubjects.contains(subject);

    final category = question?.category.trim() ?? '';
    final categoryPresets = SubjectCatalog.categoriesFor(subject);
    _customCategory = category.isNotEmpty && !categoryPresets.contains(category);
    _selectedCategory = categoryPresets.contains(category) ? category : '';

    // الدرجة الكلية للسؤال = مجموع درجات الفروع آلياً — لا حقل درجة مستقل.
    // سؤال جديد يبدأ بفرع واحد جاهز يحمل درجته (نص الفرع اختياري).
    final existingBranches = question?.branches ?? const <QuestionBranch>[];
    _branchDrafts = existingBranches
        .map(
          (branch) => _BranchDraft(
            text: branch.text,
            marks: branch.marks == branch.marks.truncateToDouble()
                ? branch.marks.toInt().toString()
                : branch.marks.toString(),
          ),
        )
        .toList(growable: true);
    if (_branchDrafts.isEmpty) {
      _branchDrafts.add(_BranchDraft(text: '', marks: ''));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subjectController.dispose();
    _topicController.dispose();
    _categoryController.dispose();
    _modelAnswerController.dispose();
    _explanationController.dispose();
    for (final draft in _branchDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<void> _saveQuestion() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final options = _optionsForCurrentType();
    if (_type == QuestionType.multipleChoice) {
      if (options.length < 2) {
        _showMessage('يجب إدخال خيارين على الأقل لسؤال الخيارات.');
        return;
      }
      if (!options.any((option) => option.isCorrect)) {
        _showMessage('يرجى تحديد خيار واحد صحيح على الأقل.');
        return;
      }
    }

    final branches = _collectBranches();
    if (branches == null) {
      return;
    }

    final subject = _subjectController.text.trim();
    final category = _customCategory
        ? _categoryController.text.trim()
        : _selectedCategory.trim();
    // الدرجة الكلية تُحسب آلياً = مجموع درجات الفروع (roll-up) — لا حقل درجة
    // مستقل يمكن أن يخالف المجموع (خطوة 1.4).
    final question = MainQuestion(
      id: widget.existingQuestion?.id,
      title: _titleController.text.trim(),
      type: _type,
      difficulty: _difficulty,
      subject: subject.isEmpty ? 'عام' : subject,
      topic: _topicController.text.trim(),
      category: category,
      branches: branches,
      options: options,
      modelAnswer: _modelAnswerController.text.trim(),
      explanation: _explanationController.text.trim(),
      createdAt: widget.existingQuestion?.createdAt,
    );
    if (question.marks <= 0) {
      _showMessage('لا يمكن حفظ سؤال بلا درجات: حدّد درجة فرع واحد على الأقل.');
      return;
    }

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final provider = context.read<QuestionProvider>();
      if (widget.existingQuestion == null) {
        await provider.addQuestion(question);
      } else {
        await provider.updateQuestion(question);
      }

      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.existingQuestion == null
                ? 'تمت إضافة السؤال بنجاح.'
                : 'تم حفظ تعديلات السؤال بنجاح.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        _showMessage('تعذر حفظ السؤال. حاول مرة أخرى.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  List<QuestionOption> _optionsForCurrentType() {
    if (_type == QuestionType.trueFalse) {
      return <QuestionOption>[
        QuestionOption(text: 'صح', isCorrect: _trueFalseAnswer),
        QuestionOption(text: 'خطأ', isCorrect: !_trueFalseAnswer),
      ];
    }
    if (_type != QuestionType.multipleChoice) {
      return const <QuestionOption>[];
    }
    return _options
        .where((option) => option.text.trim().isNotEmpty)
        .map((option) => option.copyWith(text: option.text.trim()))
        .toList(growable: false);
  }

  /// يحول مسودات الفروع إلى نماذج صارمة؛ يعيد null عند درجة غير صالحة.
  ///
  /// **لا تُخزَّن تسميات (أ/ب/ج)** — تُولَّد ديناميكياً من الفهرس وقت العرض
  /// والطباعة (خطوة 2.2). الفروع ذات النص الفارغ تبقى محفوظة إذا حملت
  /// درجة (فرع درجة مجردة للسؤال البسيط).
  List<QuestionBranch>? _collectBranches() {
    final branches = <QuestionBranch>[];
    for (var index = 0; index < _branchDrafts.length; index++) {
      final draft = _branchDrafts[index];
      final text = draft.textController.text.trim();
      final marks = _parseBranchMarks(draft.marksController.text);
      if (marks == null) {
        _showMessage('درجة الفرع "${LabelAlphabet.at(index)}" غير صالحة.');
        return null;
      }
      if (text.isEmpty && marks == 0) {
        continue;
      }
      branches.add(
        QuestionBranch(
          text: text,
          marks: marks,
        ),
      );
    }
    return branches;
  }

  double? _parseBranchMarks(String value) {
    final normalized = value.trim().replaceAll('،', '.').replaceAll(',', '.');
    if (normalized.isEmpty) {
      return 0;
    }
    final marks = double.tryParse(normalized);
    return marks != null && marks.isFinite && marks >= 0 ? marks : null;
  }

  /// الدرجة الكلية الحالية = مجموع درجات الفروع (تُحسب لحظياً للعرض فقط).
  double get _totalBranchMarks {
    var total = 0.0;
    for (final draft in _branchDrafts) {
      total += _parseBranchMarks(draft.marksController.text) ?? 0;
    }
    return total;
  }

  String _formatMarks(double marks) {
    return marks == marks.truncateToDouble()
        ? marks.toInt().toString()
        : marks.toString();
  }

  void _addBranchDraft() {
    setState(() {
      _branchDrafts.add(_BranchDraft(text: '', marks: ''));
    });
  }

  void _removeBranchDraft(int index) {
    _branchDrafts[index].dispose();
    setState(() => _branchDrafts.removeAt(index));
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  static List<QuestionOption> _defaultOptions() {
    return <QuestionOption>[
      QuestionOption(text: '', isCorrect: true),
      QuestionOption(text: ''),
      QuestionOption(text: ''),
      QuestionOption(text: ''),
    ];
  }

  static bool _trueFalseValue(List<QuestionOption>? options) {
    if (options == null || options.isEmpty) {
      return true;
    }
    final correctOption = options.where((option) => option.isCorrect).toList();
    return correctOption.isEmpty || correctOption.first.text == 'صح';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingQuestion == null ? 'إضافة سؤال جديد' : 'تعديل السؤال',
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'حفظ',
            onPressed: _isSaving ? null : _saveQuestion,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DropdownButtonFormField<QuestionType>(
                  value: _type,
                  decoration: const InputDecoration(
                    labelText: 'نوع السؤال',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category),
                  ),
                  items: QuestionType.values
                      .map(
                        (type) => DropdownMenuItem<QuestionType>(
                          value: type,
                          child: Text(type.arabicLabel),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _isSaving
                      ? null
                      : (type) {
                          if (type != null) {
                            setState(() => _type = type);
                          }
                        },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'نص السؤال *',
                    hintText: 'اكتب نص السؤال بوضوح هنا...',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  textInputAction: TextInputAction.newline,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'يرجى إدخال نص السؤال.'
                      : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownButtonFormField<Difficulty>(
                        value: _difficulty,
                        decoration: const InputDecoration(
                          labelText: 'مستوى الصعوبة',
                          border: OutlineInputBorder(),
                        ),
                        items: Difficulty.values
                            .map(
                              (difficulty) => DropdownMenuItem<Difficulty>(
                                value: difficulty,
                                child: Text(difficulty.arabicLabel),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: _isSaving
                            ? null
                            : (difficulty) {
                                if (difficulty != null) {
                                  setState(() => _difficulty = difficulty);
                                }
                              },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'الدرجة الكلية (مجموع الفروع)',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          '${_formatMarks(_totalBranchMarks)} درجة',
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _customSubject
                          ? TextFormField(
                              controller: _subjectController,
                              decoration: InputDecoration(
                                labelText: 'المادة / التصنيف',
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.close),
                                  tooltip: 'اختيار من المواد المعرفة',
                                  onPressed: _isSaving
                                      ? null
                                      : () => setState(() {
                                            _customSubject = false;
                                          }),
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                            )
                          : DropdownButtonFormField<String>(
                              value: SubjectCatalog.knownSubjects
                                      .contains(_subjectController.text)
                                  ? _subjectController.text
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'المادة / التصنيف',
                                border: OutlineInputBorder(),
                              ),
                              items: <DropdownMenuItem<String>>[
                                ...SubjectCatalog.knownSubjects.map(
                                  (subject) => DropdownMenuItem<String>(
                                    value: subject,
                                    child: Text(
                                      subject,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ),
                                const DropdownMenuItem<String>(
                                  value: '__custom_subject__',
                                  child: Text(
                                    'مادة أخرى (إدخال يدوي)',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                              onChanged: _isSaving
                                  ? null
                                  : (value) {
                                      if (value == '__custom_subject__') {
                                        setState(() => _customSubject = true);
                                        return;
                                      }
                                      if (value != null) {
                                        setState(() {
                                          _subjectController.text = value;
                                          _selectedCategory = '';
                                          _customCategory = false;
                                          _categoryController.clear();
                                        });
                                      }
                                    },
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _topicController,
                        decoration: const InputDecoration(
                          labelText: 'الوحدة / الفصل (اختياري)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                if (SubjectCatalog.categoriesFor(_subjectController.text).isNotEmpty ||
                    _customCategory) ...<Widget>[
                  const SizedBox(height: 16),
                  _customCategory
                      ? TextFormField(
                          controller: _categoryController,
                          decoration: InputDecoration(
                            labelText: 'قسم السؤال داخل الورقة (مخصص)',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.close),
                              tooltip: 'العودة للأقسام المسبقة',
                              onPressed: _isSaving
                                  ? null
                                  : () => setState(() {
                                        _customCategory = false;
                                        _categoryController.clear();
                                      }),
                            ),
                          ),
                        )
                      : DropdownButtonFormField<String>(
                          value: _selectedCategory.isEmpty ? '' : _selectedCategory,
                          decoration: const InputDecoration(
                            labelText: 'قسم السؤال داخل الورقة (اختياري)',
                            border: OutlineInputBorder(),
                          ),
                          items: <DropdownMenuItem<String>>[
                            const DropdownMenuItem<String>(
                              value: '',
                              child: Text('بدون قسم'),
                            ),
                            ...SubjectCatalog.categoriesFor(_subjectController.text)
                                .map(
                              (category) => DropdownMenuItem<String>(
                                value: category,
                                child: Text(
                                  category,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                            const DropdownMenuItem<String>(
                              value: '__custom_category__',
                              child: Text(
                                'قسم مخصص…',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                          onChanged: _isSaving
                              ? null
                              : (value) {
                                  if (value == '__custom_category__') {
                                    setState(() => _customCategory = true);
                                    return;
                                  }
                                  setState(() => _selectedCategory = value ?? '');
                                },
                        ),
                ],
                const SizedBox(height: 20),
                if (_type == QuestionType.multipleChoice)
                  McqOptionsEditor(
                    options: _options,
                    enabled: !_isSaving,
                    onChanged: (options) {
                      _options = options
                          .map((option) => option.copyWith())
                          .toList(growable: false);
                    },
                  ),
                if (_type == QuestionType.trueFalse)
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'حدد الإجابة الصحيحة للعبارة:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          RadioListTile<bool>(
                            title: const Text('صح (صحيحة)'),
                            value: true,
                            groupValue: _trueFalseAnswer,
                            onChanged: _isSaving
                                ? null
                                : (value) => setState(
                                      () => _trueFalseAnswer = value ?? true,
                                    ),
                          ),
                          RadioListTile<bool>(
                            title: const Text('خطأ (غير صحيحة)'),
                            value: false,
                            groupValue: _trueFalseAnswer,
                            onChanged: _isSaving
                                ? null
                                : (value) => setState(
                                      () => _trueFalseAnswer = value ?? false,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_type == QuestionType.fillInTheBlank ||
                    _type == QuestionType.essay) ...<Widget>[
                  TextFormField(
                    controller: _modelAnswerController,
                    maxLines: _type == QuestionType.essay ? 4 : 2,
                    decoration: InputDecoration(
                      labelText: _type == QuestionType.essay
                          ? 'الإجابة النموذجية / معايير التصحيح *'
                          : 'الكلمة أو العبارة الصحيحة لإكمال الفراغ *',
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'يرجى إدخال الإجابة النموذجية.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _explanationController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'تفسير الإجابة / ملاحظات للمعلم (اختياري)',
                    hintText: 'يظهر في نموذج الإجابة وملف التصدير لتوضيح الحل.',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 20),
                _buildBranchesCard(),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      _isSaving
                          ? 'جارٍ الحفظ...'
                          : widget.existingQuestion == null
                              ? 'إضافة السؤال للبنك'
                              : 'حفظ التعديلات',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _isSaving ? null : _saveQuestion,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBranchesCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'فروع السؤال ودرجاته',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: _isSaving ? null : _addBranchDraft,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('إضافة فرع'),
                ),
              ],
            ),
            const Text(
              'درجة السؤال الكلية = مجموع درجات الفروع آلياً. التسميات (أ، ب، ج...) '
              'تُولَّد تلقائياً من ترتيب الفروع ولا تُحفظ، فيبقى الترقيم متتالياً '
              'حتى بعد حذف فرع وسط القائمة.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
            for (var index = 0; index < _branchDrafts.length; index++) ...<Widget>[
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  SizedBox(
                    width: 22,
                    child: Text(
                      LabelAlphabet.at(index),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: _branchDrafts[index].textController,
                      decoration: const InputDecoration(
                        hintText: 'نص الفرع',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 66,
                    child: LtrNumericField(
                      controller: _branchDrafts[index].marksController,
                      hintText: 'الدرجة',
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: 'حذف الفرع',
                    onPressed: _isSaving
                        ? null
                        : () => _removeBranchDraft(index),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
