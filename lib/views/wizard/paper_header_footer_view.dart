import 'package:flutter/material.dart';

import '../../layout/blueprint/exam_blueprint.dart';
import '../../models/paper_font.dart';
import '../../models/paper_text_style.dart';
import '../widgets/tex_text.dart';
import 'paper_styles.dart';

/// ترويسة الورقة كما تُطبع: ثلاثة أعمدة بحسب المواصفة، للقراءة فقط.
///
/// - **اليمين** (موسَّط): «ادارة» ← اسم المدرسة ← «للبنين».
/// - **الوسط** (موسَّط): البسملة اختيارياً بخط خطّي ← «اسئلة امتحان …» ←
///   «للعام الدراسي …» ← الدور.
/// - **اليسار** (محاذى لليمين): المادة ← الصف ← الوقت ← اسم الطالب.
///
/// تُرسم دائماً باتجاه RTL (ترتيب الأعمدة فيزيائي) مهما كان اتجاه منطقة
/// الأسئلة، وتأخذ كل نصوصها من [HeaderBlueprint] المشترك مع PDF وWord.
class PaperHeaderView extends StatelessWidget {
  const PaperHeaderView({
    super.key,
    required this.header,
    required this.style,
    required this.defaultFont,
    required this.fontScale,
    required this.heightScale,
  });

  final HeaderBlueprint header;

  /// تنسيق الترويسة الذي اختاره المدرس (خط/حجم/عريض/مائل/تسطير/لون).
  final PaperTextStyle style;
  final PaperFont defaultFont;
  final double fontScale;
  final double heightScale;

  TextStyle _resolve(TextStyle base, [PaperTextStyle? override]) {
    return PaperStyles.resolve(
      base,
      override ?? style,
      defaultFont: defaultFont,
      fontScale: fontScale,
      heightScale: heightScale,
    );
  }

  Widget _line(String text, TextStyle style, TextAlign align) {
    // سطر الترويسة يُعرض منسّقاً كما يُطبع: صيغ `$...$` مرسومةً في مكانها
    // (مطابقة للوحة القديمة ولمصدّر Word)، لا كوداً خاماً.
    return TexText(
      text,
      style: style,
      mathTextStyle: style,
      textAlign: align,
    );
  }

  /// أسطر عمود في الترويسة: محاذاة المدرس ([PaperTextStyle.align]) تسود
  /// محاذاة العمود الافتراضية، وبعد كل سطر مسافة الفقرات إن ضبطها —
  /// المصدر الوحيد نفسه الذي يصل إلى ملفي Word وPDF حرفياً.
  List<Widget> _lines(List<String> lines, TextStyle lineStyle, TextAlign columnAlign) {
    final align = PaperStyles.toTextAlign(style.align, columnAlign);
    final spacing = style.paragraphSpacing;
    return <Widget>[
      for (final line in lines) ...<Widget>[
        _line(line, lineStyle, align),
        if (spacing != null && spacing > 0) SizedBox(height: spacing),
      ],
    ];
  }

  Widget _column(List<String> lines, TextStyle lineStyle, TextAlign align) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _lines(lines, lineStyle, align),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lineStyle = _resolve(PaperStyles.headerLine);
    final centerStyle = _resolve(PaperStyles.headerCenter);
    // البسملة بخط خطّي أنيق مستقل عن خط الورقة؛ ويبقى لونها لون الترويسة.
    final bismillahStyle = _resolve(
      PaperStyles.bismillah,
      PaperTextStyle(font: PaperFont.amiri, bold: false, color: style.color),
    );
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: header.framed
            ? BoxDecoration(border: Border.all(color: PaperStyles.ink, width: 1.2))
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // الأول في اتجاه القراءة العربية = يمين الورقة.
            Expanded(
              flex: 3,
              child: _column(header.rightLines, lineStyle, TextAlign.center),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // البسملة موسَّطة دائماً (خطها ومحاذاتها مستقلان عن
                  // تنسيق الترويسة — كما في Word وPDF).
                  if (header.showBismillah)
                    Text(
                      header.bismillah,
                      style: bismillahStyle,
                      textAlign: TextAlign.center,
                    ),
                  ..._lines(header.centerLines, centerStyle, TextAlign.center),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: _column(header.leftLines, lineStyle, TextAlign.right),
            ),
          ],
        ),
      ),
    );
  }
}

/// تذييل الورقة كما يُطبع في أسفل آخر صفحة: عبارة ختامية وسطاً، والتوقيع
/// الأساسي يساراً، والثاني يميناً (فقط إن أضافه المدرس) — للقراءة فقط.
class PaperFooterView extends StatelessWidget {
  const PaperFooterView({
    super.key,
    required this.footer,
    required this.style,
    required this.defaultFont,
    required this.fontScale,
    required this.heightScale,
  });

  final FooterBlueprint footer;
  final PaperTextStyle style;
  final PaperFont defaultFont;
  final double fontScale;
  final double heightScale;

  Widget _signature(SignatureBlueprint source, TextStyle plain, TextStyle bold) {
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
    final secondary = footer.secondary;
    final phrase = footer.closingPhrase;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // اليمين: التوقيع الثاني (فقط إن أضافه المدرس).
          Expanded(
            flex: 3,
            child: secondary == null
                ? const SizedBox.shrink()
                : _signature(secondary, plain, bold),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: phrase == null
                ? const SizedBox.shrink()
                : Text(phrase, style: bold, textAlign: TextAlign.center),
          ),
          const SizedBox(width: 8),
          // اليسار: التوقيع الأساسي دائماً.
          Expanded(flex: 3, child: _signature(footer.primary, plain, bold)),
        ],
      ),
    );
  }
}
