import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/difficulty.dart';
import '../models/question.dart';
import '../models/question_type.dart';
import '../providers/question_provider.dart';
import 'widgets/mcq_options_editor.dart';

class QuestionEditorScreen extends StatefulWidget {
  const QuestionEditorScreen({super.key, this.existingQuestion});

  final Question? existingQuestion;

  @override
  State<QuestionEditorScreen> createState() => _QuestionEditorScreenState();
}

class _QuestionEditorScreenState extends State<QuestionEditorScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _marksController;
  late final TextEditingController _subjectController;
  late final TextEditingController _topicController;
  late final TextEditingController _modelAnswerController;
  late final TextEditingController _explanationController;

  late QuestionType _type;
  late Difficulty _difficulty;
  late List<QuestionOption> _options;
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
    _marksController = TextEditingController(
      text: (question?.marks ?? 1).toString(),
    );
    _subjectController = TextEditingController(text: question?.subject ?? 'عام');
    _topicController = TextEditingController(text: question?.topic ?? '');
    _modelAnswerController = TextEditingController(
      text: question?.modelAnswer ?? '',
    );
    _explanationController = TextEditingController(
      text: question?.explanation ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _marksController.dispose();
    _subjectController.dispose();
    _topicController.dispose();
    _modelAnswerController.dispose();
    _explanationController.dispose();
    super.dispose();
  }

  Future<void> _saveQuestion() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final marks = _parseMarks(_marksController.text);
    if (marks == null) {
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

    final subject = _subjectController.text.trim();
    final question = Question(
      id: widget.existingQuestion?.id,
      title: _titleController.text.trim(),
      type: _type,
      difficulty: _difficulty,
      marks: marks,
      subject: subject.isEmpty ? 'عام' : subject,
      topic: _topicController.text.trim(),
      options: options,
      modelAnswer: _modelAnswerController.text.trim(),
      explanation: _explanationController.text.trim(),
      createdAt: widget.existingQuestion?.createdAt,
    );

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

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  double? _parseMarks(String value) {
    final normalized = value.trim().replaceAll('،', '.').replaceAll(',', '.');
    final marks = double.tryParse(normalized);
    return marks != null && marks.isFinite && marks > 0 ? marks : null;
  }

  String? _validateMarks(String? value) {
    return _parseMarks(value ?? '') == null
        ? 'أدخل درجة موجبة صحيحة، مثل 1 أو 1.5.'
        : null;
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
                      child: TextFormField(
                        controller: _marksController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'الدرجة المستحقة',
                          border: OutlineInputBorder(),
                        ),
                        validator: _validateMarks,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextFormField(
                        controller: _subjectController,
                        decoration: const InputDecoration(
                          labelText: 'المادة / التصنيف',
                          border: OutlineInputBorder(),
                        ),
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
}
