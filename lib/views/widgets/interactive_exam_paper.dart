import 'package:flutter/material.dart';

import '../../models/exam_canvas_geometry.dart';
import '../../models/floating_element.dart';
import '../../models/label_alphabet.dart';
import '../../models/main_question.dart';
import '../../models/question_branch.dart';
import '../../models/question_type.dart';
import '../../models/tex_content.dart';
import 'floating_element_view.dart';
import 'formula_inserter.dart';
import 'ltr_numeric_field.dart';
import 'tex_text.dart';

/// ربط حقول الترويسة: نفس متحكمات نموذج الترويسة تُشغَّل التحرير المباشر
/// على اللوحة (WYSIWYG) — لا حالة مكررة ولا تعارض عند الحفظ.
class PaperHeaderFields {
  const PaperHeaderFields({
    required this.institutionName,
    required this.directorate,
    required this.subject,
    required this.gradeStage,
    required this.section,
    required this.instructor,
    required this.title,
    required this.examType,
    required this.academicYear,
    required this.duration,
    required this.generalInstructions,
  });

  final TextEditingController institutionName;
  final TextEditingController directorate;
  final TextEditingController subject;
  final TextEditingController gradeStage;
  final TextEditingController section;
  final TextEditingController instructor;
  final TextEditingController title;
  final String examType;
  final TextEditingController academicYear;
  final TextEditingController duration;
  final TextEditingController generalInstructions;
}

/// بيانات سحب فرع أثناء السحب والإفلات الهرمي.
class _BranchDragData {
  const _BranchDragData({required this.questionId, required this.index});

  final String questionId;
  final int index;
}

/// ورقة اختبار A4 تفاعلية (WYSIWYG) — مطابقة 1:1 لبنية الـ PDF.
///
/// - تحرير مباشر لكل النصوص (الترويسة، عناوين الأسئلة، الفروع، الدرجات)
///   عبر `TextFormField(decoration: InputDecoration.collapsed(...))`.
/// - إعادة ترتيب هرمية بالسحب: السؤال الرئيسي كامل (ReorderableListView)،
///   والفرع داخل سؤاله أو إلى أي سؤال آخر (يُعاد ترقيمه ديناميكياً).
/// - العناصر الحرة (صور/أشكال) فوق الطبقة النصية تُسحب بحرية (onPanUpdate).
/// - **بلا خلط آلي**: الترتيب يدوي 100% حسب حالة اللوحة.
class InteractiveExamPaper extends StatefulWidget {
  const InteractiveExamPaper({
    super.key,
    required this.header,
    required this.mainQuestions,
    required this.floatingElements,
    required this.inserter,
    required this.onChanged,
  });

  final PaperHeaderFields header;
  final List<MainQuestion> mainQuestions;
  final List<FloatingElement> floatingElements;
  final FormulaInserter inserter;
  final VoidCallback onChanged;

  @override
  State<InteractiveExamPaper> createState() => _InteractiveExamPaperState();
}

class _InteractiveExamPaperState extends State<InteractiveExamPaper> {
  String? _selectedElementId;

  /// تحكمات النصوص المرتبطة بالعناصر (بحسب المعرف) حتى يبقى المؤشر
  /// ومكان الكتابة ثابتين أثناء السحب وإعادة الترتيب.
  final Map<String, TextEditingController> _textControllers =
      <String, TextEditingController>{};

  double get _totalMarks => widget.mainQuestions.fold<double>(
        0,
        (sum, question) => sum + question.marks,
      );

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _mutate(VoidCallback action) {
    setState(action);
    widget.onChanged();
  }

  TextEditingController _controllerFor(
    String id,
    String initialText,
    ValueChanged<String> onEdit,
  ) {
    return _textControllers.putIfAbsent(id, () {
      final controller = TextEditingController(text: initialText);
      controller.addListener(() {
        onEdit(controller.text);
        // تحديث حي للمعاينة والدرجات المحسوبة أثناء الكتابة.
        setState(() {});
      });
      return controller;
    });
  }

  /// نقل فرع: داخل سؤاله (إعادة ترتيب) أو إلى سؤال آخر (يُعاد ترقيمه آلياً
  /// من موقعه الجديد — التسميات لا تُخزَّن إطلاقاً).
  void _moveBranch(_BranchDragData from, String toQuestionId, int toIndex) {
    final questions = widget.mainQuestions;
    MainQuestion? fromQuestion;
    MainQuestion? toQuestion;
    for (final question in questions) {
      if (question.id == from.questionId) {
        fromQuestion = question;
      }
      if (question.id == toQuestionId) {
        toQuestion = question;
      }
    }
    if (fromQuestion == null || toQuestion == null) {
      return;
    }
    final source = fromQuestion;
    final target = toQuestion;
    _mutate(() {
      final branch = source.branches.removeAt(from.index);
      var insertAt = toIndex;
      if (identical(source, target) && from.index < toIndex) {
        insertAt -= 1;
      }
      insertAt = insertAt.clamp(0, target.branches.length);
      target.branches.insert(insertAt, branch);
    });
  }

  void _addMainQuestion() {
    _mutate(() {
      widget.mainQuestions.add(
        MainQuestion(
          title: '',
          type: QuestionType.essay,
          branches: <QuestionBranch>[QuestionBranch(text: '', marks: 1)],
        ),
      );
    });
  }

  void _deleteFloatingElement(String id) {
    _mutate(() {
      widget.floatingElements.removeWhere((element) => element.id == id);
      if (_selectedElementId == id) {
        _selectedElementId = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // تمرير رأسي + أفقي: ورقة A4 أعرض من شاشة الهاتف، وبدون التمرير الأفقي
    // تُقصّ جانبا الورقة خارج حدود الصفحة ولا يمكن الوصول إليهما.
    return SingleChildScrollView(
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            width: ExamCanvasGeometry.width,
            height: ExamCanvasGeometry.height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: <Widget>[
              // ===== الطبقة السفلية: محتوى الورقة النصي =====
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(ExamCanvasGeometry.margin),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _buildHeader(),
                      const Divider(thickness: 2, color: Color(0xFF1E3A8A)),
                      _buildNotes(),
                      Expanded(
                        child: SingleChildScrollView(
                          child: _buildQuestions(),
                        ),
                      ),
                      _buildFooter(),
                    ],
                  ),
                ),
              ),
              // ===== الطبقة العلوية: العناصر الحرة المطلقة =====
              for (final element in widget.floatingElements)
                Positioned(
                  left: element.dx,
                  top: element.dy,
                  width: element.width,
                  height: element.height,
                  child: _buildFloatingElement(element),
                ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingElement(FloatingElement element) {
    final selected = _selectedElementId == element.id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selectedElementId = element.id),
      onPanUpdate: (details) {
        _mutate(() {
          element.dx = (element.dx + details.delta.dx)
              .clamp(0.0, ExamCanvasGeometry.width - element.width);
          element.dy = (element.dy + details.delta.dy)
              .clamp(0.0, ExamCanvasGeometry.height - element.height);
        });
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: selected
                    ? Border.all(color: const Color(0xFF2563EB), width: 1.4)
                    : null,
              ),
              child: FloatingElementView(element: element),
            ),
          ),
          if (selected)
            Positioned(
              left: -12,
              top: -12,
              child: GestureDetector(
                onTap: () => _deleteFloatingElement(element.id),
                child: const CircleAvatar(
                  radius: 10,
                  backgroundColor: Color(0xFFDC2626),
                  child: Icon(Icons.close, size: 12, color: Colors.white),
                ),
              ),
            ),
          if (selected)
            Positioned(
              right: -6,
              bottom: -6,
              child: GestureDetector(
                onPanUpdate: (details) {
                  _mutate(() {
                    element.width =
                        (element.width + details.delta.dx).clamp(24.0, 600.0);
                    element.height =
                        (element.height + details.delta.dy).clamp(24.0, 600.0);
                  });
                },
                child: const Icon(
                  Icons.south_east,
                  size: 18,
                  color: Color(0xFF2563EB),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final header = widget.header;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _paperField(
                controller: header.institutionName,
                bold: true,
                hint: 'المؤسسة التعليمية',
              ),
              _labelledField('المديرية: ', header.directorate),
              _labelledField('المادة: ', header.subject),
              _labelledField('الصف: ', header.gradeStage),
              _labelledField('الشعبة: ', header.section),
              _labelledField('المعلم: ', header.instructor),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              _paperField(
                controller: header.title,
                bold: true,
                fontSize: 15,
                alignCenter: true,
                hint: 'عنوان ورقة الاختبار',
              ),
              Text(
                header.examType,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              _labelledField('العام الدراسي: ', header.academicYear),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _labelledField('الزمن: ', header.duration),
              Text(
                'الدرجة الكلية: ${_formatMarks(_totalMarks)} درجة',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'اسم الطالب: ..............................',
                style: TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 4),
        Text(
          'عدد الأسئلة: ${widget.mainQuestions.length} سؤال  |  '
          'الدرجة الكلية: ${_formatMarks(_totalMarks)} درجة',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 9, color: Color(0xFF4B5563)),
        ),
        _paperField(
          controller: widget.header.generalInstructions,
          fontSize: 9.5,
          alignCenter: true,
          hint: 'تعليمات الاختبار للطلاب...',
        ),
      ],
    );
  }

  Widget _buildFooter() {
    final instructor = widget.header.instructor.text.trim();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          instructor.isEmpty ? ' ' : 'المعلم: $instructor',
          style: const TextStyle(fontSize: 8.5, color: Color(0xFF4B5563)),
        ),
        const Text(
          'صفحة 1 من 1',
          style: TextStyle(fontSize: 8.5, color: Color(0xFF4B5563)),
        ),
        Text(
          widget.header.institutionName.text,
          style: const TextStyle(fontSize: 8.5, color: Color(0xFF4B5563)),
        ),
      ],
    );
  }

  Widget _buildQuestions() {
    final questions = widget.mainQuestions;
    return Column(
      children: <Widget>[
        // السؤال الرئيسي كامل يُسحب بمقبضه (ترتيب يدوي فقط — لا خلط آلي).
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: questions.length,
          onReorder: (oldIndex, newIndex) {
            _mutate(() {
              if (newIndex > oldIndex) {
                newIndex -= 1;
              }
              final question = questions.removeAt(oldIndex);
              questions.insert(newIndex, question);
            });
          },
          itemBuilder: (context, index) =>
              _buildMainQuestion(questions[index], index),
        ),
        TextButton.icon(
          onPressed: _addMainQuestion,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('سؤال جديد', style: TextStyle(fontSize: 11)),
        ),
      ],
    );
  }

  Widget _buildMainQuestion(MainQuestion question, int questionIndex) {
    return DragTarget<_BranchDragData>(
      key: ValueKey<String>('question-${question.id}'),
      onAcceptWithDetails: (details) =>
          _moveBranch(details.data, question.id, question.branches.length),
      builder: (context, candidateData, rejectedData) {
        final titleText = question.title;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            border: candidateData.isNotEmpty
                ? Border.all(color: const Color(0xFF2563EB), width: 1)
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ReorderableDragStartListener(
                    index: questionIndex,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(Icons.drag_indicator, size: 16),
                    ),
                  ),
                  Text(
                    'س${questionIndex + 1}:',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: _paperField(
                      controller: _controllerFor(
                        'title-${question.id}',
                        titleText,
                        (value) => question.title = value,
                      ),
                      bold: true,
                      fontSize: 11,
                      hint: 'نص السؤال الرئيسي...',
                      registerInserter: true,
                    ),
                  ),
                  Text(
                    '[${_formatMarks(question.marks)} درجة]',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    tooltip: 'إضافة فرع',
                    icon: const Icon(Icons.add, size: 16),
                    onPressed: () => _mutate(
                      () => question.branches
                          .add(QuestionBranch(text: '', marks: 0)),
                    ),
                  ),
                  IconButton(
                    tooltip: 'حذف السؤال',
                    icon: const Icon(Icons.delete_outline, size: 16),
                    onPressed: () => _mutate(
                      () => widget.mainQuestions.removeAt(questionIndex),
                    ),
                  ),
                ],
              ),
              // معاينة حية للمعادلات ($...$) أسفل سطر التحرير.
              if (TexContent.containsMath(titleText))
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 40),
                  child: TexText(
                    titleText,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              for (var branchIndex = 0;
                  branchIndex < question.branches.length;
                  branchIndex++)
                _buildBranch(question, branchIndex),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBranch(MainQuestion question, int branchIndex) {
    final branch = question.branches[branchIndex];
    final branchText = branch.text;
    return DragTarget<_BranchDragData>(
      key: ValueKey<String>('branch-${branch.id}'),
      onAcceptWithDetails: (details) =>
          _moveBranch(details.data, question.id, branchIndex),
      builder: (context, candidateData, rejectedData) {
        return LongPressDraggable<_BranchDragData>(
          data: _BranchDragData(questionId: question.id, index: branchIndex),
          feedback: Material(
            elevation: 4,
            child: Container(
              width: 320,
              padding: const EdgeInsets.all(6),
              color: Colors.white,
              child: Text(
                '${LabelAlphabet.at(branchIndex)}) ${branch.text}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          child: Container(
            color: candidateData.isNotEmpty
                ? const Color(0x222563EB)
                : Colors.transparent,
            padding: const EdgeInsetsDirectional.only(start: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 20,
                      child: Text(
                        // التسمية ديناميكية من الفهرس — لا حقل مخزن (خطوة 2.2).
                        LabelAlphabet.at(branchIndex),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _paperField(
                        controller: _controllerFor(
                          'branch-${branch.id}',
                          branchText,
                          (value) => branch.text = value,
                        ),
                        fontSize: 10.5,
                        hint: 'نص الفرع...',
                        registerInserter: true,
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: LtrNumericField(
                        collapsed: true,
                        hintText: 'درجة',
                        style: const TextStyle(fontSize: 10),
                        initialValue: _formatMarks(branch.marks),
                        onChanged: (value) => _mutate(() {
                          branch.marks =
                              double.tryParse(value.trim().replaceAll('،', '.')) ??
                                  branch.marks;
                        }),
                      ),
                    ),
                    IconButton(
                      tooltip: 'حذف الفرع',
                      icon: const Icon(Icons.close, size: 14),
                      onPressed: () => _mutate(
                        () => question.branches.removeAt(branchIndex),
                      ),
                    ),
                  ],
                ),
                if (TexContent.containsMath(branchText))
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 20),
                    child: TexText(
                      branchText,
                      style: const TextStyle(fontSize: 10.5),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// حقل نصي مسطّح على الورقة (تحرير مباشر بلا حوارات).
  Widget _paperField({
    required TextEditingController controller,
    bool bold = false,
    double fontSize = 10,
    bool alignCenter = false,
    String? hint,
    bool registerInserter = false,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: null,
      textAlign: alignCenter ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      ),
      decoration: InputDecoration.collapsed(
        hintText: hint,
        hintStyle: TextStyle(fontSize: fontSize, color: Colors.grey),
      ),
      onTap: registerInserter
          ? () => widget.inserter.controller = controller
          : null,
    );
  }

  Widget _labelledField(String label, TextEditingController controller) {
    return Row(
      children: <Widget>[
        Text(label, style: const TextStyle(fontSize: 9.5)),
        Expanded(child: _paperField(controller: controller, fontSize: 9.5)),
      ],
    );
  }

  static String _formatMarks(double marks) {
    return marks == marks.truncateToDouble()
        ? marks.toInt().toString()
        : marks.toString();
  }
}
