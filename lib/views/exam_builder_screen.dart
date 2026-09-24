import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/exam.dart';
import '../models/exam_duration_rules.dart';
import '../models/exam_header.dart';
import '../models/main_question.dart';
import '../providers/exam_provider.dart';
import '../providers/question_provider.dart';
import 'widgets/export_dialog.dart';
import 'widgets/question_card.dart';

class ExamBuilderScreen extends StatefulWidget {
  const ExamBuilderScreen({super.key, this.existingExam});

  final Exam? existingExam;

  @override
  State<ExamBuilderScreen> createState() => _ExamBuilderScreenState();
}

class _ExamBuilderScreenState extends State<ExamBuilderScreen>
    with SingleTickerProviderStateMixin {
  final _headerFormKey = GlobalKey<FormState>();

  late final TabController _tabController;
  late final TextEditingController _nameController;
  late final TextEditingController _directorateController;
  late final TextEditingController _institutionController;
  late final TextEditingController _titleController;
  late final TextEditingController _subjectController;
  late final TextEditingController _gradeStageController;
  late final TextEditingController _sectionController;
  late final TextEditingController _examDateController;
  late final TextEditingController _durationController;
  late final TextEditingController _academicYearController;
  late final TextEditingController _instructorController;
  late final TextEditingController _instructionsController;

  late String _examType;
  DateTime? _examDate;
  late List<MainQuestion> _selectedQuestions;
  bool _saveAsDefaultHeader = false;
  bool _isSaving = false;

  /// أنواع الاختبارات الرسمية المهيكلة (بدل نص حر).
  static const List<String> _examTypeOptions = <String>[
    'اختبار الفصل الأول',
    'اختبار الفصل الثاني',
    'اختبار نصف السنة',
    'الاختبار النهائي',
    'اختبار تقويمي',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    final examProvider = context.read<ExamProvider>();
    final existingExam = widget.existingExam;
    final header = existingExam?.header ?? examProvider.defaultHeader;

    _selectedQuestions = List<MainQuestion>.from(existingExam?.mainQuestions ?? const []);
    _nameController = TextEditingController(
      text: existingExam?.name ?? 'اختبار منتصف الفصل',
    );
    _directorateController = TextEditingController(text: header.directorate);
    _institutionController = TextEditingController(text: header.institutionName);
    _titleController = TextEditingController(text: header.title);
    _subjectController = TextEditingController(text: header.subject);
    _gradeStageController = TextEditingController(text: header.gradeStage);
    _sectionController = TextEditingController(text: header.section);
    _examType = header.examType;
    _examDate = header.examDate;
    _examDateController = TextEditingController(
      text: header.examDate == null ? '' : _formatExamDate(header.examDate!),
    );
    _durationController = TextEditingController(text: header.duration);
    _academicYearController = TextEditingController(text: header.academicYear);
    _instructorController = TextEditingController(text: header.instructor);
    _instructionsController = TextEditingController(
      text: header.generalInstructions,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _directorateController.dispose();
    _institutionController.dispose();
    _titleController.dispose();
    _subjectController.dispose();
    _gradeStageController.dispose();
    _sectionController.dispose();
    _examDateController.dispose();
    _durationController.dispose();
    _academicYearController.dispose();
    _instructorController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  String _formatExamDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}/$month/$day';
  }

  Future<void> _pickExamDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _examDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _examDate = DateTime(picked.year, picked.month, picked.day);
      _examDateController.text = _formatExamDate(_examDate!);
    });
  }

  void _clearExamDate() {
    setState(() {
      _examDate = null;
      _examDateController.clear();
    });
  }

  void _applyAutoDuration() {
    final duration = ExamDurationRules.calculate(
      grade: _gradeStageController.text,
      subject: _subjectController.text,
    );
    setState(() => _durationController.text = duration);
    _showMessage('حُسب زمن الاختبار آلياً: $duration');
  }

  Future<void> _saveExam() async {
    if (_isSaving) {
      return;
    }
    if (!(_headerFormKey.currentState?.validate() ?? false)) {
      _tabController.animateTo(0);
      return;
    }
    if (_selectedQuestions.isEmpty) {
      _showMessage(
        'يرجى تحديد سؤال واحد على الأقل للاختبار من تبويب اختيار الأسئلة.',
      );
      _tabController.animateTo(1);
      return;
    }

    final header = ExamHeader(
      institutionName: _institutionController.text.trim(),
      directorate: _directorateController.text.trim(),
      section: _sectionController.text.trim(),
      examType: _examType.trim(),
      title: _titleController.text.trim(),
      subject: _subjectController.text.trim(),
      gradeStage: _gradeStageController.text.trim(),
      academicYear: _academicYearController.text.trim(),
      duration: _durationController.text.trim(),
      instructor: _instructorController.text.trim(),
      generalInstructions: _instructionsController.text.trim(),
      examDate: _examDate,
    );
    final exam = Exam(
      id: widget.existingExam?.id,
      name: _nameController.text.trim(),
      header: header,
      mainQuestions: _selectedQuestions,
      createdAt: widget.existingExam?.createdAt,
    );

    var examWasSaved = false;
    setState(() => _isSaving = true);

    try {
      final provider = context.read<ExamProvider>();
      await provider.saveExam(exam);
      examWasSaved = true;
      if (_saveAsDefaultHeader) {
        await provider.updateDefaultHeader(header);
      }

      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (_) => ExportDialog(exam: exam),
      );
    } catch (_) {
      if (mounted) {
        _showMessage(
          examWasSaved
              ? 'تم حفظ الاختبار، لكن تعذر حفظ الترويسة الافتراضية.'
              : 'تعذر حفظ الاختبار. حاول مرة أخرى.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  void _toggleQuestion(MainQuestion question, bool selected) {
    setState(() {
      if (selected) {
        if (!_selectedQuestions.any((item) => item.id == question.id)) {
          _selectedQuestions = <MainQuestion>[..._selectedQuestions, question];
        }
      } else {
        _selectedQuestions = _selectedQuestions
            .where((item) => item.id != question.id)
            .toList(growable: false);
      }
    });
  }

  void _toggleAllQuestions(List<MainQuestion> questions) {
    final questionIds = questions.map((question) => question.id).toSet();
    final selectedIds = _selectedQuestions.map((question) => question.id).toSet();
    final allSelected = questionIds.isNotEmpty && questionIds.every(selectedIds.contains);

    setState(() {
      if (allSelected) {
        _selectedQuestions = _selectedQuestions
            .where((question) => !questionIds.contains(question.id))
            .toList(growable: false);
      } else {
        _selectedQuestions = List<MainQuestion>.from(questions);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final questionProvider = context.watch<QuestionProvider>();
    final questions = questionProvider.questions;
    final selectedQuestionIds = _selectedQuestions
        .map((question) => question.id)
        .toSet();
    final totalMarks = _selectedQuestions.fold<double>(
      0,
      (sum, question) => sum + question.marks,
    );
    final allQuestionsSelected =
        questions.isNotEmpty && questions.every((question) => selectedQuestionIds.contains(question.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingExam == null ? 'بناء اختبار جديد' : 'تعديل الاختبار',
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: <Widget>[
            const Tab(icon: Icon(Icons.settings), text: 'الترويسة'),
            Tab(
              icon: const Icon(Icons.checklist),
              text: 'الأسئلة (${_selectedQuestions.length})',
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'حفظ وتصدير',
            onPressed: _isSaving ? null : _saveExam,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: <Widget>[
          _buildHeaderForm(totalMarks),
          Column(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: <Widget>[
                    Text('تم اختيار ${_selectedQuestions.length} أسئلة'),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        TextButton.icon(
                          icon: const Icon(Icons.shuffle, size: 18),
                          label: const Text('خلط'),
                          onPressed: _isSaving
                              ? null
                              : () {
                                  setState(() => _selectedQuestions.shuffle());
                                },
                        ),
                        TextButton(
                          onPressed: _isSaving || questions.isEmpty
                              ? null
                              : () => _toggleAllQuestions(questions),
                          child: Text(
                            allQuestionsSelected ? 'إلغاء تحديد الكل' : 'تحديد الكل',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: questionProvider.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : questions.isEmpty
                        ? const Center(
                            child: Text(
                              'لا توجد أسئلة في البنك. أضف أسئلة أولاً.',
                            ),
                          )
                        : ListView.builder(
                            itemCount: questions.length,
                            itemBuilder: (context, index) {
                              final question = questions[index];
                              final isSelected = selectedQuestionIds.contains(
                                question.id,
                              );
                              return QuestionCard(
                                question: question,
                                isSelected: isSelected,
                                onSelectChanged: _isSaving
                                    ? null
                                    : (selected) => _toggleQuestion(
                                          question,
                                          selected ?? false,
                                        ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download),
            label: Text(
              _isSaving
                  ? 'جارٍ الحفظ...'
                  : 'حفظ والانتقال للتصدير (PDF / Excel)',
              style: const TextStyle(fontSize: 16),
            ),
            onPressed: _isSaving ? null : _saveExam,
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderForm(double totalMarks) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _headerFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'اسم الاختبار (للتنظيم داخل التطبيق) *',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'اسم الاختبار مطلوب.'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _directorateController,
              decoration: const InputDecoration(
                labelText: 'المديرية / قسم التربية (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _institutionController,
              decoration: const InputDecoration(
                labelText: 'اسم المؤسسة / المدرسة / الجامعة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'عنوان ورقة الاختبار',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _buildTwoColumnFields(
              TextFormField(
                controller: _subjectController,
                decoration: const InputDecoration(
                  labelText: 'المادة الدراسية',
                  border: OutlineInputBorder(),
                ),
              ),
              TextFormField(
                controller: _gradeStageController,
                decoration: const InputDecoration(
                  labelText: 'الصف / المرحلة',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildTwoColumnFields(
              TextFormField(
                controller: _sectionController,
                decoration: const InputDecoration(
                  labelText: 'الشعبة / الفرع (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
              DropdownButtonFormField<String>(
                value: _examTypeOptions.contains(_examType)
                    ? _examType
                    : (_examType.isNotEmpty ? _examType : ''),
                decoration: const InputDecoration(
                  labelText: 'نوع الاختبار',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(value: '', child: Text('غير محدد')),
                  ..._examTypeOptions.map(
                    (option) => DropdownMenuItem<String>(
                      value: option,
                      child: Text(option, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                  if (!_examTypeOptions.contains(_examType) && _examType.isNotEmpty)
                    DropdownMenuItem<String>(
                      value: _examType,
                      child: Text(_examType, style: const TextStyle(fontSize: 13)),
                    ),
                ],
                onChanged: _isSaving
                    ? null
                    : (value) => setState(() => _examType = value ?? ''),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _examDateController,
              readOnly: true,
              onTap: _isSaving ? null : _pickExamDate,
              decoration: InputDecoration(
                labelText: 'تاريخ الاختبار (اختياري)',
                border: const OutlineInputBorder(),
                suffixIcon: _examDateController.text.isEmpty
                    ? const Icon(Icons.event_available_outlined)
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'إزالة التاريخ',
                        onPressed: _isSaving ? null : _clearExamDate,
                      ),
              ),
            ),
            const SizedBox(height: 16),
            _buildTwoColumnFields(
              TextFormField(
                controller: _durationController,
                decoration: const InputDecoration(
                  labelText: 'زمن الاختبار',
                  border: OutlineInputBorder(),
                ),
              ),
              TextFormField(
                controller: _academicYearController,
                decoration: const InputDecoration(
                  labelText: 'العام الدراسي',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _isSaving ? null : _applyAutoDuration,
                icon: const Icon(Icons.timer_outlined, size: 18),
                label: const Text('حساب الزمن آلياً حسب قوانين الوزارة'),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _instructorController,
              decoration: const InputDecoration(
                labelText: 'اسم المعلم (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _instructionsController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'تعليمات وإرشادات الاختبار للطلاب',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _saveAsDefaultHeader,
              onChanged: _isSaving
                  ? null
                  : (value) => setState(
                        () => _saveAsDefaultHeader = value ?? false,
                      ),
              title: const Text('حفظ هذه الترويسة كإعداد افتراضي للاختبارات القادمة'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 8),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'إجمالي الدرجات الحالية: ${_formatMarks(totalMarks)} درجة\n'
                        'عدد الأسئلة: ${_selectedQuestions.length} سؤال',
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
    );
  }

  Widget _buildTwoColumnFields(Widget first, Widget second) {
    return Row(
      children: <Widget>[
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    );
  }

  String _formatMarks(double marks) {
    return marks == marks.truncateToDouble()
        ? marks.toInt().toString()
        : marks.toString();
  }
}
