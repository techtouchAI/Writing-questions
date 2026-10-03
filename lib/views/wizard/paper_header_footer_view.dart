import 'package:flutter/material.dart';

import '../../layout/blueprint/exam_blueprint.dart';
import '../../layout/document_ir.dart';
import '../../layout/semantic/inline_nodes.dart';
import '../../models/paper_font.dart';
import '../../models/paper_text_style.dart';
import '../widgets/tex_text.dart';
import 'paper_styles.dart';

/// Render-only header view. Production Preview supplies [semanticHeader]; the
/// older blueprint argument is retained for other public/test callers.
class PaperHeaderView extends StatelessWidget {
  const PaperHeaderView({
    super.key,
    this.header,
    this.semanticHeader,
    required this.style,
    required this.defaultFont,
    required this.fontScale,
    required this.heightScale,
  }) : assert(header != null || semanticHeader != null);

  final HeaderBlueprint? header;
  final HeaderBlock? semanticHeader;
  final PaperTextStyle style;
  final PaperFont defaultFont;
  final double fontScale;
  final double heightScale;

  TextStyle _resolve(TextStyle base, [PaperTextStyle? override]) =>
      PaperStyles.resolve(
        base,
        override ?? style,
        defaultFont: defaultFont,
        fontScale: fontScale,
        heightScale: heightScale,
      );

  Widget _legacyLine(String text, TextStyle style, TextAlign align) => TexText(
        text,
        style: style,
        mathTextStyle: style,
        textAlign: align,
      );

  Widget _semanticLine(
    InlineContent content,
    TextStyle style,
    TextAlign align,
  ) =>
      TexText.fromRichContent(
        content.richContent,
        style: style,
        mathTextStyle: style,
        textAlign: align,
      );

  List<Widget> _legacyLines(
    List<String> lines,
    TextStyle lineStyle,
    TextAlign columnAlign,
  ) {
    final align = PaperStyles.toTextAlign(style.align, columnAlign);
    final spacing = style.paragraphSpacing;
    return <Widget>[
      for (final line in lines) ...<Widget>[
        _legacyLine(line, lineStyle, align),
        if (spacing != null && spacing > 0) SizedBox(height: spacing),
      ],
    ];
  }

  List<Widget> _semanticLines(
    List<HeaderLineBlock> lines,
    TextStyle lineStyle,
    TextAlign columnAlign,
  ) {
    final align = PaperStyles.toTextAlign(style.align, columnAlign);
    final spacing = style.paragraphSpacing;
    return <Widget>[
      for (final line in lines) ...<Widget>[
        _semanticLine(
          line.content,
          line.bold ? lineStyle.copyWith(fontWeight: FontWeight.bold) : lineStyle,
          align,
        ),
        if (spacing != null && spacing > 0) SizedBox(height: spacing),
      ],
    ];
  }

  Widget _column(List<Widget> lines) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: lines,
      );

  @override
  Widget build(BuildContext context) {
    final legacy = header;
    final ir = semanticHeader;
    final lineStyle = _resolve(PaperStyles.headerLine);
    final centerStyle = _resolve(PaperStyles.headerCenter);
    final bismillahStyle = _resolve(
      PaperStyles.bismillah,
      PaperTextStyle(font: PaperFont.amiri, bold: false, color: style.color),
    );
    final right = ir == null
        ? _legacyLines(legacy!.rightLines, lineStyle, TextAlign.center)
        : _semanticLines(ir.rightColumn, lineStyle, TextAlign.center);
    final center = ir == null
        ? _legacyLines(legacy!.centerLines, centerStyle, TextAlign.center)
        : _semanticLines(ir.centerColumn, centerStyle, TextAlign.center);
    final left = ir == null
        ? _legacyLines(legacy!.leftLines, lineStyle, TextAlign.right)
        : _semanticLines(ir.leftColumn, lineStyle, TextAlign.right);
    final showBismillah = ir?.showBismillah ?? legacy!.showBismillah;
    final bismillah = ir?.bismillah.content ?? legacy!.bismillahContent;
    final framed = ir?.framed ?? legacy!.framed;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: framed
            ? BoxDecoration(border: Border.all(color: PaperStyles.ink, width: 1.2))
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(flex: 3, child: _column(right)),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (showBismillah)
                    _semanticLine(bismillah, bismillahStyle, TextAlign.center),
                  ...center,
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: _column(left)),
          ],
        ),
      ),
    );
  }
}

/// Render-only footer view. Production Preview supplies [semanticFooter]; the
/// blueprint argument remains as a compatibility path.
class PaperFooterView extends StatelessWidget {
  const PaperFooterView({
    super.key,
    this.footer,
    this.semanticFooter,
    required this.style,
    required this.defaultFont,
    required this.fontScale,
    required this.heightScale,
  }) : assert(footer != null || semanticFooter != null);

  final FooterBlueprint? footer;
  final FooterBlock? semanticFooter;
  final PaperTextStyle style;
  final PaperFont defaultFont;
  final double fontScale;
  final double heightScale;

  Widget _semanticText(InlineContent content, TextStyle textStyle) =>
      TexText.fromRichContent(
        content.richContent,
        style: textStyle,
        mathTextStyle: textStyle,
        textAlign: TextAlign.center,
      );

  Widget _signature(
    SignatureBlueprint? legacy,
    SignatureBlock? semantic,
    TextStyle plain,
    TextStyle bold,
  ) {
    if (semantic != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _semanticText(semantic.title.content, bold),
          const SizedBox(height: 3),
          _semanticText(semantic.name, plain),
        ],
      );
    }
    final source = legacy!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(source.title, style: bold, textAlign: TextAlign.center),
        const SizedBox(height: 3),
        Text(source.nameLine, style: plain, textAlign: TextAlign.center),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final plain = PaperStyles.resolve(
      PaperStyles.headerLine,
      style,
      defaultFont: defaultFont,
      fontScale: fontScale,
      heightScale: heightScale,
    );
    final bold = plain.copyWith(fontWeight: FontWeight.bold);
    final ir = semanticFooter;
    final legacy = footer;
    final secondaryLegacy = legacy?.secondary;
    final secondarySemantic = ir?.secondary;
    final phraseContent = ir?.closingPhrase?.content;
    final phrase = legacy?.closingPhrase;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            flex: 3,
            child: ir == null && secondaryLegacy == null ||
                    ir != null && secondarySemantic == null
                ? const SizedBox.shrink()
                : _signature(secondaryLegacy, secondarySemantic, plain, bold),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: ir != null
                ? phraseContent == null
                    ? const SizedBox.shrink()
                    : _semanticText(phraseContent, bold)
                : phrase == null
                    ? const SizedBox.shrink()
                    : Text(phrase, style: bold, textAlign: TextAlign.center),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: _signature(legacy?.primary, ir?.primary, plain, bold),
          ),
        ],
      ),
    );
  }
}
