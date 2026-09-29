import 'package:flutter/material.dart';

import '../../models/quran_text.dart';
import '../../models/tex_content.dart';

/// حقل النص على ورقة الورقة: **الشكل النهائي فقط** — لا رموز LaTeX خاماً
/// (`$...$`) تظهر على الورقة إطلاقاً.
///
/// - نص عادي (بلا صيغ/آيات): [TextField] للتحرير المباشر كما كان.
/// - نص يحوي صيغة أو آية موسومة: يُعرض **المنسّق النهائي** ([renderBuilder]
///   — نفس ما يطبعه محرك الـ PDF حرفياً)؛ النقر عليه يفتح التحرير:
///   محرر المعادلات المرئي للصيغ الخالصة، وإلا تحرير المصدر في مكانه.
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
    this.textAlign = TextAlign.start,
    this.hint,
    this.onActivate,
    this.onEditFormula,
  });

  /// متحكم النص (نفسه في وضعَي العرض والتحرير).
  final TextEditingController controller;

  /// نمط النص (يُمرَّر كما هو إلى [renderBuilder]).
  final TextStyle style;

  /// يبني الشكل النهائي المعروض (TexText — نفس محرك الطباعة).
  final Widget Function(String text) renderBuilder;

  final TextAlign textAlign;

  /// تلميح الحقل الفارغ (وضع التحرير فقط).
  final String? hint;

  /// يُستدعى عند تفعيل الحقل (تسجيل هدف إدراج الصيغ في الشريط).
  final VoidCallback? onActivate;

  /// يُستدعى عند النقر على صيغة خالصة (فتح محرر المعادلات المرئي).
  final VoidCallback? onEditFormula;

  @override
  State<PaperField> createState() => _PaperFieldState();
}

class _PaperFieldState extends State<PaperField> {
  late final FocusNode _focusNode;

  /// طلب تحرير صريح (نقر على العرض النهائي) — يبقى سارياً حتى فقدان التركيز.
  bool _editing = false;

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
    if (!_focusNode.hasFocus && _editing) {
      setState(() => _editing = false);
    }
    if (_focusNode.hasFocus) {
      widget.onActivate?.call();
    }
  }

  void _onTextChanged() {
    // إعادة بناء عند تغيير النص خارجياً (إدراج صيغة/تراجع/مزامنة) ليعكس
    // العرض النهائي الجديد فوراً.
    if (mounted) {
      setState(() {});
    }
  }

  bool get _isRenderable {
    final text = widget.controller.text;
    return TexContent.containsMath(text) || QuranText.containsQuran(text);
  }

  /// هل النص صيغة خالصة (لا شيء حولها سوى الفراغات)؟ — النقر يفتح المحرر
  /// المرئي مباشرة بدلاً من تحرير المصدر.
  bool get _isPureFormula {
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
    setState(() => _editing = true);
    _focusNode.requestFocus();
  }

  TextStyle _resolveEffectiveStyle(BoxConstraints constraints) {
    final baseStyle = widget.style;
    if (widget.textAlign != TextAlign.justify || !constraints.hasBoundedWidth) {
      return baseStyle;
    }
    final text = widget.controller.text;
    if (text.trim().isEmpty) {
      return baseStyle;
    }
    final words = text.trim().split(RegExp(r'\s+'));
    if (words.length <= 1) {
      return baseStyle;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: baseStyle),
      textDirection: TextDirection.rtl,
    )..layout();
    final availableWidth = constraints.maxWidth;
    if (painter.width < availableWidth) {
      final diff = availableWidth - painter.width;
      if (diff > 0) {
        final maxPerWord = (availableWidth / words.length).clamp(12.0, 60.0);
        final rawSpacing = diff / (words.length - 1);
        final addedSpacing = rawSpacing.clamp(0.0, maxPerWord);
        return baseStyle.copyWith(
          wordSpacing: ((baseStyle.wordSpacing) ?? 0) + addedSpacing,
        );
      }
    }
    return baseStyle;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveStyle = _resolveEffectiveStyle(constraints);
        final showRendered = _isRenderable && !_editing && !_focusNode.hasFocus;
        if (showRendered) {
          return Tooltip(
            message: 'انقر للتحرير',
            child: InkWell(
              onTap: _handleRenderedTap,
              child: SizedBox(
                width: double.infinity,
                child: widget.renderBuilder(widget.controller.text),
              ),
            ),
          );
        }
        return SizedBox(
          width: double.infinity,
          child: TextField(
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
        );
      },
    );
  }
}
