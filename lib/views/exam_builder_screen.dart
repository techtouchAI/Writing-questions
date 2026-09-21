import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/exam.dart';
import '../models/exam_header.dart';
import '../models/question.dart';
import '../providers/question_provider.dart';
import '../providers/exam_provider.dart';
import 'widgets/export_dialog.dart';
import 'widgets/question_card.dart';

class ExamBuilderScreen extends StatefulWidget {
  final Exam? existingExam;

  const ExamBuilderScreen({super.key, this.existingExam});

  @override
  State<ExamBuilderScreen> createState() => _ExamBuilderScreenState();
}

class _ExamBuilderScreenState extends State<ExamBuilderScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _headerFormKey = GlobalKey<FormState>();

  late String _examName;
  late ExamHeader _header;
  late List<Question> _selectedQuestions;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    final examProvider = Provider.of<ExamProvider>(context, listen: false);
    if (widget.existingExam != null) {
      _examName = widget.existingExam!.name;
      _header = ExamHeader.fromMap(widget.existingExam!.header.toMap());
      _selectedQuestions = List.from(widget.existingExam!.questions);
    } else {
      _examName = 'اختبار منتصف الفصل';
      _header = ExamHeader.fromMap(examProvider.defaultHeader.toMap());
      _selectedQuestions = [];
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _saveExam() {
    if (!_headerFormKey.currentState!.validate()) {
      _tabController.animateTo(0);
      return;
    }
    _headerFormKey.currentState!.save();

    if (_selectedQuestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تحديد سؤال واحد على الأقل للاختبار من تبويب اختيار الأسئلة')),
      );
      _tabController.animateTo(1);
      return;
    }

    final exam = Exam(
      id: widget.existingExam?.id,
      name: _examName,
      header: _header,
      questions: List.from(_selectedQuestions),
    );

    Provider.of<ExamProvider>(context, listen: false).saveExam(exam);

    showDialog(
      context: context,
      builder: (ctx) => ExportDialog(exam: exam),
    );
  }

  @override
  Widget build(BuildContext context) {
    final questionProvider = Provider.of<QuestionProvider>(context);
    final totalMarks = _selectedQuestions.fold(0.0, (sum, q) => sum + q.marks);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingExam != null ? 'تعديل الاختبار' : 'بناء وتصدير اختبار جديد'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(icon: Icon(Icons.settings), text: 'ترويسة الاختبار والمعلومات'),
            Tab(icon: const Icon(Icons.checklist), text: 'الأسئلة المختارة (${_selectedQuestions.length})'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'تصدير Word و Excel',
            onPressed: _saveExam,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Header Configuration
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _headerFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    initialValue: _examName,
                    decoration: const InputDecoration(
                      labelText: 'اسم الاختبار (للتنظيم داخل التطبيق) *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty ? 'مطلوب' : null,
                    onSaved: (val) => _examName = val?.trim() ?? '',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: _header.institutionName,
                    decoration: const InputDecoration(
                      labelText: 'اسم المؤسسة / المدرسة / الجامعة',
                      border: OutlineInputBorder(),
                    ),
                    onSaved: (val) => _header.institutionName = val?.trim() ?? '',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: _header.title,
                    decoration: const InputDecoration(
                      labelText: 'عنوان ورقة الاختبار (يظهر في المنتصف)',
                      border: OutlineInputBorder(),
                    ),
                    onSaved: (val) => _header.title = val?.trim() ?? '',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: _header.subject,
                          decoration: const InputDecoration(labelText: 'المادة الدراسية', border: OutlineInputBorder()),
                          onSaved: (val) => _header.subject = val?.trim() ?? '',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          initialValue: _header.gradeStage,
                          decoration: const InputDecoration(labelText: 'الصف / المرحلة', border: OutlineInputBorder()),
                          onSaved: (val) => _header.gradeStage = val?.trim() ?? '',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: _header.duration,
                          decoration: const InputDecoration(labelText: 'زمن الاختبار', border: OutlineInputBorder()),
                          onSaved: (val) => _header.duration = val?.trim() ?? '',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          initialValue: _header.academicYear,
                          decoration: const InputDecoration(labelText: 'العام الدراسي', border: OutlineInputBorder()),
                          onSaved: (val) => _header.academicYear = val?.trim() ?? '',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: _header.generalInstructions,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'تعليمات وإرشادات الاختبار للطلاب',
                      border: OutlineInputBorder(),
                    ),
                    onSaved: (val) => _header.generalInstructions = val?.trim() ?? '',
                  ),
                  const SizedBox(height: 24),
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.blue),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'إجمالي الدرجات الحالية: $totalMarks درجة\nعدد الأسئلة: ${_selectedQuestions.length} سؤال',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Tab 2: Question Selection
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.grey.shade100,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('تم اختيار (${_selectedQuestions.length}) أسئلة'),
                    Row(
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.shuffle, size: 18),
                          label: const Text('خلط الأسئلة'),
                          onPressed: () {
                            setState(() {
                              _selectedQuestions.shuffle();
                            });
                          },
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              if (_selectedQuestions.length == questionProvider.questions.length) {
                                _selectedQuestions.clear();
                              } else {
                                _selectedQuestions = List.from(questionProvider.questions);
                              }
                            });
                          },
                          child: Text(_selectedQuestions.length == questionProvider.questions.length
                              ? 'إلغاء تحديد الكل'
                              : 'تحديد الكل'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: questionProvider.questions.isEmpty
                    ? const Center(child: Text('لا توجد أسئلة في البنك. أضف أسئلة أولاً.'))
                    : ListView.builder(
                        itemCount: questionProvider.questions.length,
                        itemBuilder: (ctx, index) {
                          final q = questionProvider.questions[index];
                          final isSelected = _selectedQuestions.any((item) => item.id == q.id);
                          return QuestionCard(
                            question: q,
                            isSelected: isSelected,
                            onSelectChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedQuestions.add(q);
                                } else {
                                  _selectedQuestions.removeWhere((item) => item.id == q.id);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.file_download),
            label: const Text('حفظ والانتقال للتصدير (Word / Excel)', style: TextStyle(fontSize: 16)),
            onPressed: _saveExam,
          ),
        ),
      ),
    );
  }
}
