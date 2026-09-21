import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/question.dart';
import '../models/question_type.dart';
import '../models/difficulty.dart';
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

  late QuestionType _type;
  late Difficulty _difficulty;
  late List<QuestionOption> _options;
  bool _trueFalseAnswer = true;

  final _titleController = TextEditingController();
  final _marksController = TextEditingController();
  final _subjectController = TextEditingController();
  final _topicController = TextEditingController();
  final _modelAnswerController = TextEditingController();
  final _explanationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final seed = widget.existingQuestion;
    double marks;
    String subject;
    if (seed != null) {
      _type = seed.type;
      _difficulty = seed.difficulty;
      _options = seed.options
          .map((e) => QuestionOption(id: e.id, text: e.text, isCorrect: e.isCorrect))
          .toList();
      marks = seed.marks;
      subject = seed.subject;

      if (_type == QuestionType.trueFalse && _options.isNotEmpty) {
        final correct = _options.firstWhere(
          (option) => option.isCorrect,
          orElse: () => _options.first,
        );
        _trueFalseAnswer = correct.text == 'صح';
      }
    } else {
      _type = QuestionType.multipleChoice;
      _difficulty = Difficulty.medium;
      _options = [
        QuestionOption(text: '', isCorrect: true),
        QuestionOption(text: '', isCorrect: false),
        QuestionOption(text: '', isCorrect: false),
        QuestionOption(text: '', isCorrect: false),
      ];
      marks = 1.0;
      subject = 'عام';
    }

    _titleController.text = seed?.title ?? '';
    _marksController.text = _formatMarks(marks);
    _subjectController.text = subject;
    _topicController.text = seed?.topic ?? '';
    _modelAnswerController.text = seed?.modelAnswer ?? '';
    _explanationController.text = seed?.explanation ?? '';
  }

  /// ASCII digits, Arabic-Indic digits, plus both decimal separators.
  static final RegExp _marksPattern = RegExp(r'^[\d٠-٩]*[.,٫]?[\d٠-٩]*$');

  static const Map<String, String> _arabicDigits = {
    '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
    '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9', '٫': '.',
  };

  String _normalizeMarks(String raw) => raw.replaceAllMapped(
        RegExp(r'[٠-٩٫]'),
        (match) => _arabicDigits[match.group(0)] ?? match.group(0)!,
      );

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

  String _formatMarks(double marks) =>
      marks % 1 == 0 ? marks.toInt().toString() : marks.toString();

  void _saveQuestion() {
    if (!_formKey.currentState!.validate()) return;

    List<QuestionOption> finalOptions = [];
    if (_type == QuestionType.multipleChoice) {
      finalOptions = _options.where((option) => option.text.trim().isNotEmpty).toList();
      if (finalOptions.length < 2) {
        _showMessage('يجب إدخال خيارين على الأقل لسؤال الخيارات');
        return;
      }
      if (!finalOptions.any((option) => option.isCorrect)) {
        _showMessage('يرجى تحديد خيار واحد صحيح على الأقل');
        return;
      }
    } else if (_type == QuestionType.trueFalse) {
      finalOptions = [
        QuestionOption(text: 'صح', isCorrect: _trueFalseAnswer),
        QuestionOption(text: 'خطأ', isCorrect: !_trueFalseAnswer),
      ];
    }

    final provider = Provider.of<QuestionProvider>(context, listen: false);
    final title = _titleController.text.trim();
    final marks =
        double.tryParse(_normalizeMarks(_marksController.text)) ?? 1.0;
    final subject =
        _subjectController.text.trim().isEmpty ? 'عام' : _subjectController.text.trim();
    final topic = _topicController.text.trim();
    final modelAnswer = _modelAnswerController.text.trim();
    final explanation = _explanationController.text.trim();

    final isEditing = widget.existingQuestion != null;
    if (isEditing) {
      provider.updateQuestion(widget.existingQuestion!.copyWith(
        title: title,
        type: _type,
        difficulty: _difficulty,
        marks: marks,
        subject: subject,
        topic: topic,
        options: finalOptions,
        modelAnswer: modelAnswer,
        explanation: explanation,
      ));
    } else {
      provider.addQuestion(Question(
        title: title,
        type: _type,
        difficulty: _difficulty,
        marks: marks,
        subject: subject,
        topic: topic,
        options: finalOptions,
        modelAnswer: modelAnswer,
        explanation: explanation,
      ));
    }

    _showMessage(isEditing ? 'تم تعديل السؤال بنجاح' : 'تمت إضافة السؤال بنجاح');
    Navigator.of(context).pop();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingQuestion != null ? 'تعديل السؤال' : 'إضافة سؤال جديد'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'حفظ',
            onPressed: _saveQuestion,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // Question Type Selector
            DropdownButtonFormField<QuestionType>(
              value: _type,
              decoration: const InputDecoration(
                labelText: 'نوع السؤال',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
              items: QuestionType.values.map((type) {
                return DropdownMenuItem(value: type, child: Text(type.arabicLabel));
              }).toList(),
              onChanged: (value) {
                if (value != null) setState(() => _type = value);
              },
            ),
            const SizedBox(height: 16),

            // Title / Question Text
            TextFormField(
              controller: _titleController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'نص السؤال *',
                hintText: 'اكتب نص السؤال بوضوح هنا...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'يرجى إدخال نص السؤال';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Row: Difficulty & Marks
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<Difficulty>(
                    value: _difficulty,
                    decoration: const InputDecoration(
                      labelText: 'مستوى الصعوبة',
                      border: OutlineInputBorder(),
                    ),
                    items: Difficulty.values.map((difficulty) {
                      return DropdownMenuItem(
                        value: difficulty,
                        child: Text(difficulty.arabicLabel),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _difficulty = value);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _marksController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(_marksPattern),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'الدرجة المستحقة',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null ||
                          double.tryParse(_normalizeMarks(value)) == null) {
                        return 'أدخل رقماً صحيحاً';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Row: Subject & Topic
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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

            // Dynamic Fields based on Type
            if (_type == QuestionType.multipleChoice)
              McqOptionsEditor(
                options: _options,
                onChanged: (options) => _options = options,
              ),

            if (_type == QuestionType.trueFalse)
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'حدد الإجابة الصحيحة للعبارة:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      RadioListTile<bool>(
                        title: const Text('صح (صحيحة)'),
                        value: true,
                        groupValue: _trueFalseAnswer,
                        onChanged: (value) =>
                            setState(() => _trueFalseAnswer = value ?? true),
                      ),
                      RadioListTile<bool>(
                        title: const Text('خطأ (غير صحيحة)'),
                        value: false,
                        groupValue: _trueFalseAnswer,
                        onChanged: (value) =>
                            setState(() => _trueFalseAnswer = value ?? false),
                      ),
                    ],
                  ),
                ),
              ),

            if (_type == QuestionType.fillInTheBlank || _type == QuestionType.essay) ...[
              TextFormField(
                controller: _modelAnswerController,
                maxLines: _type == QuestionType.essay ? 4 : 2,
                decoration: InputDecoration(
                  labelText: _type == QuestionType.essay
                      ? 'الإجابة النموذجية / معايير التصحيح'
                      : 'الكلمة أو العبارة الصحيحة لإكمال الفراغ',
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // General Explanation / Notes
            TextFormField(
              controller: _explanationController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'تفسير الإجابة / ملاحظات للمعلم (اختياري)',
                hintText: 'يظهر في نموذج الإجابة أو ملف التصدير لتوضيح الحل...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: Text(
                  widget.existingQuestion != null ? 'حفظ التعديلات' : 'إضافة السؤال للبنك',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: _saveQuestion,
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
