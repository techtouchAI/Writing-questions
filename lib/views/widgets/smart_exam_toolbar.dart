import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart' show Math;
import 'package:image_picker/image_picker.dart';

import '../../models/floating_element.dart';
import '../../models/quran_text.dart';
import 'formula_inserter.dart';

/// يفتح بلاطة صور النظام ويعيد بايتات الصورة المختارة (أو null عند الإلغاء).
Future<List<int>?> pickImageBytes() async {
  try {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) {
      return null;
    }
    return file.readAsBytes();
  } catch (_) {
    // المنصات غير المدعومة أو رفض الصلاحية: لا نُسقط اللوحة.
    return null;
  }
}

/// أداة سياقية ذكية فوق لوحة الورقة بخمسة تبويبات:
/// نص | رياضيات | كيمياء | فيزياء | وسائط.
///
/// - **نص**: عناصر نصية سريعة (سؤال/فرع/قسم).
/// - **رياضيات/كيمياء/فيزياء**: مكتبة صيغ LaTeX تُدرج مباشرة في الحقل
///   النشط على اللوحة ($...$ سطرية أو $$...$$ منفردة) عبر [FormulaInserter].
/// - **وسائط**: إدراج صور (بلاطة الوسائط) وأشكال (مثلث/دائرة/مربع/
///   مستطيل/خط/سهم) ومربعات نص وفواصل كعناصر حرة فوق الورقة.
class SmartExamToolbar extends StatelessWidget {
  const SmartExamToolbar({
    super.key,
    required this.inserter,
    required this.onInsertText,
    required this.onAddImage,
    required this.onAddShape,
    this.onAddQuestion,
    this.onAddBranch,
    this.onAddTextBox,
    this.onAddDivider,
    this.onEquationEditor,
    this.stagedFormula,
    this.onFormulaDragEnd,
    this.onAddFormula,
    this.onClearStagedFormula,
  });

  final FormulaInserter inserter;
  final ValueChanged<String> onInsertText;
  final ValueChanged<List<int>> onAddImage;
  final ValueChanged<FloatingShapeType> onAddShape;
  final VoidCallback? onAddQuestion;
  final VoidCallback? onAddBranch;
  final VoidCallback? onAddTextBox;
  final VoidCallback? onAddDivider;

  /// يفتح محرر المعادلات المرئي: [template] صيغة جاهزة للتحميل فيه
  /// (أو null لمعادلة فارغة)، و[preferBlock] يقترح النمط المنفرد،
  /// و[editExisting] يحرّر صيغة موجودة في الحقل بدل إدراج جديدة.
  /// بغيابه تُدرج الصيغ خاماً عبر [inserter] كما في السابق.
  final void Function({String? template, bool preferBlock, bool editExisting})?
      onEquationEditor;

  /// معادلة حُرِّرت للتوّ وتنتظر موضعها: تُعرض بطاقة تُسحب إلى أي نقطة على
  /// الورقة، أو ينقر المستخدم مكانها داخل الورقة فتستقر فيه.
  final String? stagedFormula;

  /// نهاية سحب بطاقة المعادلة ([DragTarget] على الورقة يستقبلها).
  final void Function(DraggableDetails details)? onFormulaDragEnd;

  /// إدراج معادلة **حرة** (تبويب وسائط): محرّر ثم بطاقة تُسحب لأي موضع.
  final VoidCallback? onAddFormula;

  /// إلغاء المعادلة المرشّحة قبل إقامتها على الورقة.
  final VoidCallback? onClearStagedFormula;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: DefaultTabController(
        length: 5,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (stagedFormula != null)
              _StagedFormulaBar(
                latex: stagedFormula!,
                onDragEnd: onFormulaDragEnd,
                onClear: onClearStagedFormula,
              ),
            const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: <Widget>[
                Tab(icon: Icon(Icons.text_fields, size: 18), text: 'نص'),
                Tab(icon: Icon(Icons.functions, size: 18), text: 'رياضيات'),
                Tab(icon: Icon(Icons.science, size: 18), text: 'كيمياء'),
                Tab(icon: Icon(Icons.bolt, size: 18), text: 'فيزياء'),
                Tab(icon: Icon(Icons.perm_media, size: 18), text: 'وسائط'),
              ],
            ),
            SizedBox(
              height: 56,
              child: TabBarView(
                children: <Widget>[
                  _TextTab(
                    inserter: inserter,
                    onInsertText: onInsertText,
                    onAddQuestion: onAddQuestion,
                    onAddBranch: onAddBranch,
                  ),
                  _FormulaTab(
                    inserter: inserter,
                    formulas: _mathFormulas,
                    onEquationEditor: onEquationEditor,
                  ),
                  _FormulaTab(
                    inserter: inserter,
                    formulas: _chemistryFormulas,
                    onEquationEditor: onEquationEditor,
                  ),
                  _FormulaTab(
                    inserter: inserter,
                    formulas: _physicsFormulas,
                    onEquationEditor: onEquationEditor,
                  ),
                  _MediaTab(
                    onAddImage: onAddImage,
                    onAddShape: onAddShape,
                    onAddTextBox: onAddTextBox,
                    onAddDivider: onAddDivider,
                    onAddFormula: onAddFormula,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// صيغة جاهزة: [label] للعرض و[latex] لمصدر الصيغة.
class FormulaSnippet {
  const FormulaSnippet(this.label, this.latex);

  final String label;
  final String latex;
}

const List<FormulaSnippet> _mathFormulas = <FormulaSnippet>[
  FormulaSnippet('كسر', r'\frac{a}{b}'),
  FormulaSnippet('جذر', r'\sqrt{x}'),
  FormulaSnippet('أس', r'x^{2}'),
  FormulaSnippet('فرعي', r'x_{1}'),
  FormulaSnippet('متكامل', r'\int_{a}^{b} f(x)\,dx'),
  FormulaSnippet('مجموع', r'\sum_{i=1}^{n} i'),
  FormulaSnippet('نهاية', r'\lim_{x \to 0}'),
  FormulaSnippet('معادلة', r'\frac{-b \pm \sqrt{b^2-4ac}}{2a}'),
];

const List<FormulaSnippet> _chemistryFormulas = <FormulaSnippet>[
  FormulaSnippet('ماء', r'H_2O'),
  FormulaSnippet('ثاني أكسيد الكربون', r'CO_2'),
  FormulaSnippet('حمض الكبريتيك', r'H_2SO_4'),
  FormulaSnippet('الأمونيا', r'NH_3'),
  FormulaSnippet('سهم تفاعل', r'\rightarrow'),
  FormulaSnippet('تفاعل عكوس', r'\rightleftharpoons'),
  FormulaSnippet('معادلة أيونية', r'Ag^+ + Cl^- \rightarrow AgCl'),
];

const List<FormulaSnippet> _physicsFormulas = <FormulaSnippet>[
  FormulaSnippet('قوانين نيوتن', r'F = ma'),
  FormulaSnippet('نسبية', r'E = mc^2'),
  FormulaSnippet('قانون أوم', r'V = IR'),
  FormulaSnippet('الشغل', r'W = F \cdot d'),
  FormulaSnippet('سرعة', r'v = \frac{s}{t}'),
  FormulaSnippet('متغير', r'\vec{F}'),
];

class _TextTab extends StatelessWidget {
  const _TextTab({
    required this.inserter,
    required this.onInsertText,
    required this.onAddQuestion,
    required this.onAddBranch,
  });

  final FormulaInserter inserter;
  final ValueChanged<String> onInsertText;
  final VoidCallback? onAddQuestion;
  final VoidCallback? onAddBranch;

  @override
  Widget build(BuildContext context) {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      children: <Widget>[
        if (onAddQuestion != null)
          _ChipButton(
            icon: Icons.add_circle_outline,
            label: 'سؤال جديد',
            onTap: onAddQuestion!,
          ),
        if (onAddBranch != null)
          _ChipButton(
            icon: Icons.alt_route,
            label: 'فرع جديد',
            onTap: onAddBranch!,
          ),
        _ChipButton(
          icon: Icons.wrap_text,
          label: 'سطر جديد',
          onTap: () => onInsertText('\n'),
        ),
        _ChipButton(
          icon: Icons.notes,
          label: 'ملاحظة للمعلم',
          onTap: () => onInsertText('ملاحظة: '),
        ),
        // وسم آية قرآنية: يغلّف التحديد (أو يضع المؤشر بين القوسين) فيُرسم
        // المقطع بالخط القرآني في اللوحة وفي الطباعة معاً.
        _ChipButton(
          icon: Icons.menu_book,
          label: 'آية قرآنية',
          onTap: () => inserter.wrapSelection(QuranText.openMarker, QuranText.closeMarker),
        ),
      ],
    );
  }
}

class _FormulaTab extends StatelessWidget {
  const _FormulaTab({
    required this.inserter,
    required this.formulas,
    required this.onEquationEditor,
  });

  final FormulaInserter inserter;
  final List<FormulaSnippet> formulas;
  final void Function({String? template, bool preferBlock, bool editExisting})?
      onEquationEditor;

  @override
  Widget build(BuildContext context) {
    final editor = onEquationEditor;
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      children: <Widget>[
        // معادلة **حرة**: تُكتب في المحرر المرئي ثم تُسحب إلى أي موضع على
        // الورقة (الضغط الطويل: يبدأ المحرر بالنمط المنفرد).
        if (editor != null)
          _ChipButton(
            icon: Icons.edit,
            label: 'محرر المعادلات',
            onTap: () => editor(),
            onLongPress: () => editor(preferBlock: true),
          ),
        // تحرير صيغة موجودة داخل حقل نصي (يبقى الإدراج السطري متاحاً بذلك).
        if (editor != null)
          _ChipButton(
            icon: Icons.edit_note,
            label: 'تحرير معادلة',
            onTap: () => editor(editExisting: true),
          ),
        for (final formula in formulas)
          _ChipButton(
            icon: Icons.functions,
            label: formula.label,
            // الصيغة الجاهزة تُحمَّل في المحرر المرئي ثم تُسحب كمعادلة حرة
            // إلى أي موضع، وبغياب المحرر تُدرج خاماً كما في السابق.
            onTap: editor == null
                ? () => inserter.insert('\$${formula.latex}\$')
                : () => editor(template: formula.latex),
            onLongPress: editor == null
                ? () => inserter.insert('\$\$${formula.latex}\$\$')
                : () => editor(template: formula.latex, preferBlock: true),
          ),
      ],
    );
  }
}

/// بطاقة المعادلة المرشّحة: تُسحب إلى أي موضع على الورقة.
///
/// السحب يُنشئ `FloatingElement` من نوع المعادلة، و[DragTarget] على الصفحة
/// يقيمها في موضع الإفلات تماماً — فموضعها اختيار المستخدم لا قيد السؤال.
class _StagedFormulaBar extends StatelessWidget {
  const _StagedFormulaBar({required this.latex, this.onDragEnd, this.onClear});

  final String latex;
  final void Function(DraggableDetails details)? onDragEnd;
  final VoidCallback? onClear;

  static const double _cardWidth = 150;
  static const double _cardHeight = 70;

  FloatingElement _element() => FloatingElement(
        type: FloatingElementType.formula,
        label: latex,
        dx: 0,
        dy: 0,
        width: _cardWidth,
        height: _cardHeight,
      );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final card = Container(
      width: _cardWidth,
      height: _cardHeight,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.primary, width: 1.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Math.tex(
          latex,
          textStyle: const TextStyle(fontSize: 16),
        ),
      ),
    );
    return Container(
      width: double.infinity,
      color: colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: <Widget>[
          Draggable<FloatingElement>(
            data: _element(),
            feedback: Material(
              color: Colors.transparent,
              child: Opacity(opacity: 0.9, child: card),
            ),
            childWhenDragging: Opacity(opacity: 0.3, child: card),
            onDragEnd: onDragEnd,
            child: card,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'معادلتك جاهزة: اسحبها إلى المكان الذي تريده على الورقة، '
              'أو اضغط داخل الورقة فتستقر في موضع الضغط.',
              style: TextStyle(fontSize: 12, color: colorScheme.onPrimaryContainer),
            ),
          ),
          IconButton(
            tooltip: 'إلغاء الإدراج',
            iconSize: 18,
            onPressed: onClear,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _MediaTab extends StatelessWidget {
  const _MediaTab({
    required this.onAddImage,
    required this.onAddShape,
    required this.onAddTextBox,
    required this.onAddDivider,
    this.onAddFormula,
  });

  final ValueChanged<List<int>> onAddImage;
  final ValueChanged<FloatingShapeType> onAddShape;
  final VoidCallback? onAddTextBox;
  final VoidCallback? onAddDivider;
  final VoidCallback? onAddFormula;

  Future<void> _pickImage() async {
    final bytes = await pickImageBytes();
    if (bytes != null) {
      onAddImage(bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      children: <Widget>[
        _ChipButton(
          icon: Icons.image,
          label: 'صورة',
          onTap: _pickImage,
        ),
        if (onAddFormula != null)
          _ChipButton(
            icon: Icons.functions,
            label: 'معادلة حرة',
            onTap: onAddFormula!,
          ),
        _ChipButton(
          icon: Icons.change_history,
          label: 'مثلث',
          onTap: () => onAddShape(FloatingShapeType.triangle),
        ),
        _ChipButton(
          icon: Icons.circle_outlined,
          label: 'دائرة',
          onTap: () => onAddShape(FloatingShapeType.circle),
        ),
        _ChipButton(
          icon: Icons.crop_square,
          label: 'مربع',
          onTap: () => onAddShape(FloatingShapeType.square),
        ),
        _ChipButton(
          icon: Icons.rectangle_outlined,
          label: 'مستطيل',
          onTap: () => onAddShape(FloatingShapeType.rectangle),
        ),
        _ChipButton(
          icon: Icons.remove,
          label: 'خط',
          onTap: () => onAddShape(FloatingShapeType.line),
        ),
        _ChipButton(
          icon: Icons.arrow_forward,
          label: 'سهم',
          onTap: () => onAddShape(FloatingShapeType.arrow),
        ),
        if (onAddTextBox != null)
          _ChipButton(
            icon: Icons.text_fields,
            label: 'مربع نص',
            onTap: onAddTextBox!,
          ),
        if (onAddDivider != null)
          _ChipButton(
            icon: Icons.horizontal_rule,
            label: 'فاصل',
            onTap: onAddDivider!,
          ),
      ],
    );
  }
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
