import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../models/question_type.dart';
import '../models/difficulty.dart';
import '../providers/question_provider.dart';
import 'widgets/mcq_options_editor.dart';

class QuestionEditorScreen extends StatefulWidget {
  final Question? existingQuestion;

  const QuestionEditorScreen({super.key, this.existingQuestion});

  @override
  State<QuestionEditorScreen> createState() => _QuestionEditorScreenState();
}

class _QuestionEditorScreenState extends State<QuestionEditorScreen> {
  final _formKey = GlobalKey<FormState>();

  late String _title;
  late QuestionType _type;
  late Difficulty _difficulty;
  late double _marks;
  late String _subject;
  late String _topic;
  late List<QuestionOption> _options;
  late String _modelAnswer;
  late String _explanation;

  bool _trueFalseAnswer = true;

  @override
  void initState() {
    super.initState();
    final q = widget.existingQuestion;
    if (q != null) {
      _title = q.title;
      _type = q.type;
      _difficulty = q.difficulty;
      _marks = q.marks;
      _subject = q.subject;
      _topic = q.topic;
      _options = q.options.map((e) => QuestionOption(id: e.id, text: e.text, isCorrect: e.isCorrect)).toList();
      _modelAnswer = q.modelAnswer;
      _explanation = q.explanation;

      if (_type == QuestionType.trueFalse && _options.isNotEmpty) {
        final correct = _options.firstWhere((o) => o.isCorrect, orElse: () => _options.first);
        _trueFalseAnswer = correct.text == 'صح';
      }
    } else {
      _title = '';
      _type = QuestionType.multipleChoice;
      _difficulty = Difficulty.medium;
      _marks = 1.0;
      _subject = 'عام';
      _topic = '';
      _options = [
        QuestionOption(text: '', isCorrect: true),
        QuestionOption(text: '', isCorrect: false),
        QuestionOption(text: '', isCorrect: false),
        QuestionOption(text: '', isCorrect: false),
      ];
      _modelAnswer = '';
      _explanation = '';
    }
  }

  void _saveQuestion() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    List<QuestionOption> finalOptions = [];
    if (_type == QuestionType.multipleChoice) {
      finalOptions = _options.where((o) => o.text.trim().isNotEmpty).toList();
      if (finalOptions.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يجب إدخال خيارين على الأقل لسؤال الخيارات')),
        );
        return;
      }
      if (!finalOptions.any((o) => o.isCorrect)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى تحديد خيار واحد صحيح على الأقل')),
        );
        return;
      }
    } else if (_type == QuestionType.trueFalse) {
      finalOptions = [
        QuestionOption(text: 'صح', isCorrect: _trueFalseAnswer),
        QuestionOption(text: 'خطأ', isCorrect: !_trueFalseAnswer),
      ];
    }

    final provider = Provider.of<QuestionProvider>(context, listen: false);

    if (widget.existingQuestion != null) {
      final updated = widget.existingQuestion!.copyWith(
        title: _title,
        type: _type,
        difficulty: _difficulty,
        marks: _marks,
        subject: _subject,
        topic: _topic,
        options: finalOptions,
        modelAnswer: _modelAnswer,
        explanation: _explanation,
      );
      provider.updateQuestion(updated);
    } else {
      final newQ = Question(
        title: _title,
        type: _type,
        difficulty: _difficulty,
        marks: _marks,
        subject: _subject,
        topic: _topic,
        options: finalOptions,
        modelAnswer: _modelAnswer,
        explanation: _explanation,
      );
      provider.addQuestion(newQ);
    }

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.existingQuestion != null ? 'تم تعديل السؤال بنجاح' : 'تمت إضافة السؤال بنجاح')),
    );
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Question Type Selector
              DropdownButtonFormField<QuestionType>(
                value: _type,
                decoration: const InputDecoration(
                  labelText: 'نوع السؤال',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: QuestionType.values.map((t) {
                  return DropdownMenuItem(
                    value: t,
                    child: Text(t.arabicLabel),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _type = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),

              // Title / Question Text
              TextFormField(
                initialValue: _title,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'نص السؤال *',
                  hintText: 'اكتب نص السؤال بوضوح هنا...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'يرجى إدخال نص السؤال';
                  }
                  return null;
                },
                onSaved: (val) => _title = val?.trim() ?? '',
              ),
              const SizedBox(height: 16),

              // Row: Difficulty & Marks
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<Difficulty>(
                      value: _difficulty,
                      decoration: const InputDecoration(
                        labelText: 'مستوى الصعوبة',
                        border: OutlineInputBorder(),
                      ),
                      items: Difficulty.values.map((d) {
                        return DropdownMenuItem(
                          value: d,
                          child: Text(d.arabicLabel),
                        );
                      }).toList>,
                      onChanged: (val) {
                        if (val != null) setState(() => _difficulty = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: _marks.toString(),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'الدرجة المستحقة',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (val == null || double.tryParse(val) == null) {
                          return 'أدخل رقم صحيح';
                        }
                        return null;
                      },
                      onSaved: (val) => _marks = double.tryParse(val ?? '1.0') ?? 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Row: Subject & Topic
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: _subject,
                      decoration: const InputDecoration(
                        labelText: 'المادة / التصنيف',
                        border: OutlineInputBorder(),
                      ),
                      onSaved: (val) => _subject = val?.trim().isEmpty ?? true ? 'عام' : val!.trim(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: _topic,
                      decoration: const InputDecoration(
                        labelText: 'الوحدة / الفصل (اختياري)',
                        border: OutlineInputBorder(),
                      ),
                      onSaved: (val) => _topic = val?.trim() ?? '',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Dynamic Fields based on Type
              if (_type == QuestionType.multipleChoice)
                McqOptionsEditor(
                  options: _options,
                  onChanged: (opts) => _options = opts,
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
                        const Text('حدد الإجابة الصحيحة للعبارة:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        RadioListTile<bool>(
                          title: const Text('صح (صحيحة)'),
                          value: true,
                          groupValue: _trueFalseAnswer,
                          onChanged: (val) => setState(() => _trueFalseAnswer = val ?? true),
                        ),
                        RadioListTile<bool>(
                          title: const Text('خطأ (غير صحيحة)'),
                          value: false,
                          groupValue: _trueFalseAnswer,
                          onChanged: (val) => setState(() => _trueFalseAnswer = val ?? false),
                        ),
                      ],
                    ),
                  ),
                ),

              if (_type == QuestionType.fillInTheBlank || _type == QuestionType.essay) ...[
                TextFormField(
                  initialValue: _modelAnswer,
                  maxLines: _type == QuestionType.essay ? 4 : 2,
                  decoration: InputDecoration(
                    labelText: _type == QuestionType.essay ? 'الإجابة النموذجية / معايير التصحيح' : 'الكلمة أو العبارة الصحيحة لإكمال الفراغ',
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  onSaved: (val) => _modelAnswer = val?.trim() ?? '',
                ),
                const SizedBox(height: 16),
              ],

              // General Explanation / Notes
              TextFormField(
                initialValue: _explanation,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'تفسير الإجابة / ملاحظات للمعلم (اختياري)',
                  hintText: 'يظهر في نموذج الإجابة أو ملف التصدير لتوضيح الحل...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                onSaved: (val) => _explanation = val?.trim() ?? '',
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
      ),
    );
  }
}
