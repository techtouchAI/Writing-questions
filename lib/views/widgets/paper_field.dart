import 'package:flutter/material.dart';

import '../../layout/semantic/inline_nodes.dart';
import '../../layout/visual/visual_flutter_style.dart';
import '../../models/quran_text.dart';
import '../../models/tex_content.dart';
import 'mixed_content_editor.dart';

/// حقل النص على ورقة الورقة: **الشكل النهائي فقط** — لا رموز LaTeX خاماً
/// (`$...$`) تظهر على الورقة إطلاقاً.
///
/// - نص عادي (بلا صيغ/آيات): [TextField] للتحرير المباشر كما كان.
/// - نص يحوي صيغة أو آية موسومة: يُعرض **المنسّق النهائي** ([renderBuilder]
///   — نفس ما يطبعه محرك الـ PDF حرفياً)؛ والنقر عليه يفتح محرر المحتوى
///   المختلط ([MixedContentEditor]): النص حقولاً والمعادلات مرسومةً مرئية —
///   فالمستخدم يضيف أي عدد من المعادلات ولا يرى كود LaTeX في أي مرحلة.
/// - عند فقدان التركيز يعود العرض النهائي فوراً؛ وبعد «إدراج معادلة» من
///   الشريط يُغلق التركيز فيُضاف **الشكل النهائي** لا رموزه.
///
/// الحقل يبقى [TextEditingController] نفسه دائماً (المصدر هو الحقيقة
/// المخزَّنة) — المتغير طريقة العرض وحدها.
class PaperField extends StatefulWidget {
  const PaperField({
    super.key,
    required this.controller,
    required this.style,
    required this.renderBuilder,
    this.semanticContent,
    this.textAlign = TextAlign.start,
    this.hint,
    this.onActivate,
    this.onEditFormula,
    this.allowTextSelection = true,
    this.onLongPress,
  });

  /// متحكم النص (نفسه في وضعَي العرض والتحرير).
  final TextEditingController controller;

  /// نمط النص (يُمرَّر كما هو إلى [renderBuilder]).
  final TextStyle style;

  /// يبني الشكل النهائي المعروض (TexText — نفس محرك الطباعة).
  final Widget Function(String text) renderBuilder;

  /// Canonical rich content from DocumentIR when this field is paper output.
  /// `null` keeps the legacy/edit-only source parsing path.
  final InlineContent? semanticContent;

  final TextAlign textAlign;

  /// تلميح الحقل الفارغ (وضع التحرير فقط).
  final String? hint;

  /// يُستدعى عند تفعيل الحقل (تسجيل هدف إدراج الصيغ في الشريط).
  final VoidCallback? onActivate;

  /// يُستدعى عند النقر على صيغة خالصة (فتح محرر المعادلات المرئي).
  final VoidCallback? onEditFormula;

  /// هل يشارك الحقل في إيماءات تأشير النص (الضغط المطوّل لتحديد كلمة)؟
  ///
  /// `false` في وضع التحديد المتعدد على الورقة: يمرّ الضغط المطوّل إلى كتلة
  /// السؤال/الفرع فتُحدَّد من أي موضع. وفي الوضع العادي يُشارك الحقل
  /// بالتأشير **فقط وهو مفعّل** (قيد التحرير) — فضغط مطوّل على نص غير مفعّل
  /// يحدد كتلته كما يتوقع المستخدم، ويبقى تأشير النص متاحاً أثناء الكتابة.
  final bool allowTextSelection;

  /// يُستدعى عند ضغط مطوّل على الحقل **وهو غير قيد التحرير** (أو حين يكون
  /// تأشير النص معطَّلاً في وضع التحديد المتعدد).
  ///
  /// الطبقة التي تستدعيه تسبق محرّك النص في ساحة الإيماءات (انظر
  /// [_buildLongPressLayer]) فيصل الضغط المطوّل إلى كتلة السؤال/الفرع
  /// فتُحدَّد من أي موضع على الورقة، بينما يبقى تأشير النص متاحاً داخل حقل
  /// مفعّل قيد الكتابة.
  final VoidCallback? onLongPress;

  @override
  State<PaperField> createState() => _PaperFieldState();
}

class _PaperFieldState extends State<PaperField> {
  late final FocusNode _focusNode;

  /// طلب تحرير صريح (نقر على العرض النهائي) — يبقى سارياً حتى فقدان التركيز.
  bool _editing = false;

  /// حماية من فتح محرر المحتوى أكثر من مرة في اللحظة نفسها.
  bool _openingRichEditor = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'paper-field');
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant PaperField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) {
      return;
    }
    setState(() {
      if (!_focusNode.hasFocus) {
        _editing = false;
      }
    });
    if (_focusNode.hasFocus) {
      widget.onActivate?.call();
    }
  }

  void _onTextChanged() {
    // إعادة بناء عند تغيير النص خارجياً (إدراج صيغة/تراجع/مزامنة) ليعكس
    // العرض النهائي الجديد فوراً.
    if (!mounted) {
      return;
    }
    setState(() {});
    // صار النص يحوي صيغة أثناء الكتابة (إدراج من شريط الصيغ مثلاً): يُفتح
    // المحرر المرئي فوراً فلا يظهر أي كود LaTeX في حقل التحرير إطلاقاً.
    if (_editing && !_openingRichEditor && TexContent.containsMath(widget.controller.text)) {
      setState(() => _editing = false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _openRichEditor());
    }
  }

  /// يفتح محرر المحتوى المختلط (نص + معادلات) على النص الحالي ويكتب نتيجته
  /// في المتحكم نفسه — فيبقى الحقل قابلاً للتحرير لاحقاً بالطريقة ذاتها.
  Future<void> _openRichEditor() async {
    if (_openingRichEditor) {
      return;
    }
    _openingRichEditor = true;
    try {
      final result = await MixedContentEditor.show(
        context,
        source: widget.controller.text,
      );
      if (!mounted || result == null) {
        return;
      }
      widget.controller.text = result;
      widget.controller.selection = TextSelection.collapsed(offset: result.length);
    } finally {
      _openingRichEditor = false;
    }
  }

  bool get _isRenderable {
    final semantic = widget.semanticContent;
    if (semantic != null) {
      return semantic.hasMath || semantic.hasQuran;
    }
    final text = widget.controller.text;
    return TexContent.containsMath(text) || QuranText.containsQuran(text);
  }

  /// هل النص صيغة خالصة (لا شيء حولها سوى الفراغات)؟ — النقر يفتح المحرر
  /// المرئي مباشرة بدلاً من تحرير المصدر.
  bool get _isPureFormula {
    final semantic = widget.semanticContent;
    if (semantic != null) {
      var hasMath = false;
      for (final run in semantic.richContent.runs) {
        if (run.isMath) {
          hasMath = true;
        } else if (run.text.trim().isNotEmpty) {
          return false;
        }
      }
      return hasMath;
    }
    final text = widget.controller.text;
    final spans = TexContent.findSpans(text);
    if (spans.isEmpty) {
      return false;
    }
    final outside = StringBuffer();
    var cursor = 0;
    for (final span in spans) {
      outside.write(text.substring(cursor, span.start));
      cursor = span.end;
    }
    outside.write(text.substring(cursor));
    return outside.toString().trim().isEmpty;
  }

  void _handleRenderedTap() {
    widget.onActivate?.call();
    if (_isPureFormula && widget.onEditFormula != null) {
      widget.onEditFormula!();
      return;
    }
    // أي نص يحوي معادلة يُفتح في محرر المحتوى المختلط (نص + معادلات مرئية).
    if (widget.semanticContent?.hasMath ??
        TexContent.containsMath(widget.controller.text)) {
      _openRichEditor();
      return;
    }
    setState(() => _editing = true);
    _focusNode.requestFocus();
  }

  /// نمط الفقرة بعد قرار **الضبط** (justify) — بقاعدة واحدة مع `TexText`:
  /// تُحسب التوسعة في `VisualFlutterStyle.justifyWordSpacing` ولا يكرّر أي
  /// سطح منطق «متى يُمَدّ السطر».
  TextStyle _resolveEffectiveStyle(
    BoxConstraints constraints,
    BuildContext context,
  ) {
    final baseStyle = widget.style;
    if (widget.textAlign != TextAlign.justify ||
        !constraints.hasBoundedWidth) {
      return baseStyle;
    }
    final addedSpacing = VisualFlutterStyle.justifyWordSpacing(
      text: widget.controller.text,
      style: baseStyle,
      maxWidth: constraints.maxWidth,
      direction: Directionality.maybeOf(context) ?? TextDirection.rtl,
    );
    if (addedSpacing == null) {
      return baseStyle;
    }
    return baseStyle.copyWith(
      wordSpacing: (baseStyle.wordSpacing ?? 0) + addedSpacing,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveStyle = _resolveEffectiveStyle(constraints, context);
        final showRendered = _isRenderable && !_editing && !_focusNode.hasFocus;
        if (showRendered) {
          return Tooltip(
            message: 'انقر للتحرير',
            child: InkWell(
              onTap: _handleRenderedTap,
              onLongPress: widget.onLongPress,
              child: SizedBox(
                width: double.infinity,
                child: widget.renderBuilder(widget.controller.text),
              ),
            ),
          );
        }
        return SizedBox(
          width: double.infinity,
          child: _buildLongPressLayer(
            TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            maxLines: null,
            textAlign: widget.textAlign,
            style: effectiveStyle,
            decoration: InputDecoration.collapsed(
              hintText: widget.hint,
              hintStyle: effectiveStyle.copyWith(color: Colors.grey),
            ),
              onTap: () {
                setState(() => _editing = true);
                widget.onActivate?.call();
              },
            ),
          ),
        );
      },
    );
  }

  /// يضع طبقة إيماءة شفافة فوق حقل التحرير تلتقط الضغط المطوّل وحده.
  ///
  /// لماذا طبقة عليا لا `GestureDetector` أب؟ لأن `RenderEditable` في Flutter
  /// يضيف مُعرّف ضغط مطوّل إلى ساحة الإيماءات طالما `rendererIgnoresPointer`
  /// مطفأ (وهو مطفأ في `TextField` دائماً)، ومُعرّف النص هذا يفوز على أي
  /// سلف. الطبقة العليا تُدخَل إلى الساحة قبله (الأعلى يُختبر أولاً) فتفوز
  /// بالضغط المطوّل، وبلا `onTap` فيها تمرّ النقرات إلى الحقل فيتركّز
  /// ويظهر المؤشر كالمعتاد.
  ///
  /// **شكل الشجرة ثابت** (`Stack` بطفلين دائماً حين يوجد `onLongPress`):
  /// تغييره بين تركيز وتركيز يُعيد إنشاء `TextField` فينقطع اتصال الكتابة
  /// (وهو ما كان يُسقط الكتابة الفورية في حقل الخيار). التعطيل يتمّ بإخلال
  /// الاستدعاء نفسه (`onLongPress: null`) فلا يبقى للحقل أي مُعرّف ضغط
  /// مطوّل، ويبقى تأشير النص داخل الحقل المفعّل كما كان.
  Widget _buildLongPressLayer(Widget field) {
    final onLongPress = widget.onLongPress;
    if (onLongPress == null) {
      return field;
    }
    // التأشير المدمج متاح فقط حين يكون الحقل مفعّلاً قيد الكتابة (أو وضع
    // التحديد المتعدد مغلقاً): عندها يُسلَّم الضغط المطوّل لمحرّك النص.
    final handOverToText = widget.allowTextSelection && _focusNode.hasFocus;
    return Stack(
      children: <Widget>[
        field,
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPress: handOverToText ? null : onLongPress,
          ),
        ),
      ],
    );
  }
}
