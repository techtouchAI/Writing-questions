/// خطاً تخطيطي متجهاً مصغّراً (stroke font) لمحارف المعادلات.
///
/// كل محرف = قائمة خطوط (polylines) داخل صندوق وحدات:
/// - سيني [0..advance]، صادي [0..13] بمحور Y نازل (كـ SVG)،
/// - خط الأساس عند y = 10، وارتفاع الأحرف الكبيرة 10 وحدات،
/// - النزول تحت الأساس (descenders) حتى y = 13.
///
/// يُستخدم لتحويل صيغ LaTeX إلى رسوم SVG متجهة خالصة (بلا نصوص SVG)
/// ليطبعها محرك الـ PDF عبر `pw.SvgImage` دون الحاجة لخطوط خارجية.
///
/// ## لماذا خط داخلي بدل خط TTF؟
/// خطوط الورقة العربية (نسخ/أميري/تجوال) لا تحوي محارف الرياضيات (يونانية،
/// تكامل، علاقات...) — فحص `cmap` يؤكده — فأي معادلة تحويها كانت تسقط إلى
/// بديل نصي. هذا الخط هو خط الرياضيات الوحيد للتطبيق: يغطي كل ما يُدرجه
/// محرر المعادلات وكل سجلّ [MathSymbols]، ويختبر ذلك
/// `test/pdf_engine/math_symbol_coverage_test.dart` فلا يعود أي محرف ناقصاً.
///
/// ## النعومة
/// المحرف المعلَّم بـ[smooth] يُرسم منحنىً (Bézier عبر Catmull-Rom) لا
/// مضلّعاً: الأشكال الدائرية (الأرقام، الأقواس، اليونانية، المجموعات) تخرج
/// ناعمة كما في الخطوط الحقيقية، بينما تبقى الزوايا الحادة (مثل E وZ و∑)
/// مضلّعات. التقسيم والمقاسات لا تتأثر: القياس يبقى على نقاط التحكم نفسها.
abstract final class MathStrokeFont {
  /// ارتفاع خط الأساس (وحدة) — يقابل ارتفاع الحرف الكبير.
  static const double baseline = 10;

  /// نبضة الوحدة: 14 وحدة = em كامل تقريباً.
  static const double unitsPerEm = 14;

  static double advanceOf(String char) => glyphs[char]?.advance ?? 8;

  static GlyphStrokes? strokesOf(String char) => glyphs[char];

  /// جدول المحارف: المفتاح = المحرف نفسه.
  static const Map<String, GlyphStrokes> glyphs = <String, GlyphStrokes>{
    // ===== الأرقام =====
    '0': GlyphStrokes(7.5, <List<double>>[
      <double>[2, 0, 5, 0, 7, 2, 7, 8, 5, 10, 2, 10, 0, 8, 0, 2, 2, 0],
    ], smooth: true),
    '1': GlyphStrokes(6, <List<double>>[
      <double>[1, 2, 3, 0, 3, 10],
      <double>[1, 10, 5, 10],
    ]),
    '2': GlyphStrokes(7, <List<double>>[
      <double>[0, 2, 2, 0, 5, 0, 7, 2, 7, 4, 0, 10],
      <double>[0, 10, 7, 10],
    ], smooth: true),
    '3': GlyphStrokes(7, <List<double>>[
      <double>[0, 0, 7, 0, 3, 4],
      <double>[3, 4, 5, 4, 7, 6, 7, 8, 5, 10, 2, 10, 0, 8],
    ], smooth: true),
    '4': GlyphStrokes(7.5, <List<double>>[
      <double>[5, 10, 5, 0, 0, 7, 7, 7],
    ]),
    '5': GlyphStrokes(7, <List<double>>[
      <double>[7, 0, 0, 0, 0, 4, 5, 4, 7, 6, 7, 8, 5, 10, 2, 10, 0, 8],
    ], smooth: true),
    '6': GlyphStrokes(7, <List<double>>[
      <double>[7, 0, 2, 1, 0, 5, 0, 8, 2, 10, 5, 10, 7, 8, 7, 6, 5, 4, 2, 4, 0, 6],
    ], smooth: true),
    '7': GlyphStrokes(7, <List<double>>[
      <double>[0, 0, 7, 0, 3, 10],
    ]),
    '8': GlyphStrokes(7, <List<double>>[
      <double>[2, 0, 5, 0, 7, 2, 7, 3, 5, 5, 2, 5, 0, 7, 0, 8, 2, 10, 5, 10, 7, 8, 7, 7, 5, 5, 2, 5, 0, 3, 0, 2, 2, 0],
    ], smooth: true),
    '9': GlyphStrokes(7, <List<double>>[
      <double>[0, 10, 5, 9, 7, 5, 7, 2, 5, 0, 2, 0, 0, 2, 0, 4, 2, 6, 5, 6, 7, 4],
    ], smooth: true),

    // ===== الأرقام العربية المشرقية (٠-٩) =====
    // أشكالها منزوعة من خط الورقة نفسه (Tajawal) كي تتطابق المعادلة مع المتن.
    '٠': GlyphStrokes(6, <List<double>>[
      <double>[3, 3.5, 5, 5.5, 3, 7.5, 1, 5.5, 3, 3.5],
    ]),
    '١': GlyphStrokes(5, <List<double>>[
      <double>[2.5, 0, 2.5, 10],
    ]),
    '٢': GlyphStrokes(7, <List<double>>[
      <double>[1.5, 10, 1.5, 0, 5.5, 0],
    ]),
    '٣': GlyphStrokes(8, <List<double>>[
      <double>[1.5, 10, 1.5, 2],
      <double>[1.5, 2, 2.6, 2, 2.6, 4.5, 3.9, 4.5, 3.9, 2, 5.2, 2, 5.2, 4.5, 6.5, 4.5, 6.5, 2],
    ], smooth: true),
    '٤': GlyphStrokes(7.5, <List<double>>[
      <double>[6, 1, 3, 1, 2, 2.5, 3, 4.5, 5, 5, 3, 5.5, 2, 7.5, 3, 9, 6, 9],
    ], smooth: true),
    '٥': GlyphStrokes(7, <List<double>>[
      <double>[3.5, 1.5, 5.5, 3.5, 5.5, 6.5, 3.5, 8.5, 1.5, 6.5, 1.5, 3.5, 3.5, 1.5],
    ], smooth: true),
    '٦': GlyphStrokes(7, <List<double>>[
      <double>[5.5, 10, 5.5, 0, 1.5, 0],
    ]),
    '٧': GlyphStrokes(7, <List<double>>[
      <double>[1, 0, 3.5, 10, 6, 0],
    ]),
    '٨': GlyphStrokes(7, <List<double>>[
      <double>[1, 10, 3.5, 0, 6, 10],
    ]),
    '٩': GlyphStrokes(7, <List<double>>[
      <double>[2, 1.5, 4, 1.5, 5, 3, 4, 5, 2, 5, 1, 3, 2, 1.5],
      <double>[5, 3, 5, 10],
    ], smooth: true),

    // ===== الأحرف اللاتينية الكبيرة =====
    'A': GlyphStrokes(8, <List<double>>[
      <double>[0, 10, 4, 0, 8, 10],
      <double>[1.6, 6, 6.4, 6],
    ]),
    'B': GlyphStrokes(7.5, <List<double>>[
      <double>[0, 0, 0, 10],
      <double>[0, 0, 5, 0, 7, 2, 7, 3, 5, 5, 0, 5],
      <double>[0, 5, 5, 5, 7, 7, 7, 8, 5, 10, 0, 10],
    ], smooth: true),
    'C': GlyphStrokes(8, <List<double>>[
      <double>[7, 2, 5, 0, 2, 0, 0, 2, 0, 8, 2, 10, 5, 10, 7, 8],
    ], smooth: true),
    'D': GlyphStrokes(8, <List<double>>[
      <double>[0, 0, 0, 10],
      <double>[0, 0, 5, 0, 8, 3, 8, 7, 5, 10, 0, 10],
    ], smooth: true),
    'E': GlyphStrokes(7, <List<double>>[
      <double>[7, 0, 0, 0, 0, 10, 7, 10],
      <double>[0, 5, 5, 5],
    ]),
    'F': GlyphStrokes(7, <List<double>>[
      <double>[7, 0, 0, 0, 0, 10],
      <double>[0, 5, 5, 5],
    ]),
    'G': GlyphStrokes(8.5, <List<double>>[
      <double>[7, 2, 5, 0, 2, 0, 0, 2, 0, 8, 2, 10, 5, 10, 7, 8, 7, 5, 4, 5],
    ], smooth: true),
    'H': GlyphStrokes(8, <List<double>>[
      <double>[0, 0, 0, 10],
      <double>[8, 0, 8, 10],
      <double>[0, 5, 8, 5],
    ]),
    'I': GlyphStrokes(4, <List<double>>[
      <double>[2, 0, 2, 10],
    ]),
    'J': GlyphStrokes(6.5, <List<double>>[
      <double>[6, 0, 6, 8, 4, 10, 2, 10, 0, 8],
    ], smooth: true),
    'K': GlyphStrokes(7.5, <List<double>>[
      <double>[0, 0, 0, 10],
      <double>[7, 0, 0, 5],
      <double>[2, 4, 7, 10],
    ]),
    'L': GlyphStrokes(7, <List<double>>[
      <double>[0, 0, 0, 10, 6, 10],
    ]),
    'M': GlyphStrokes(9, <List<double>>[
      <double>[0, 10, 0, 0, 4.5, 6, 9, 0, 9, 10],
    ]),
    'N': GlyphStrokes(8, <List<double>>[
      <double>[0, 10, 0, 0, 8, 10, 8, 0],
    ]),
    'O': GlyphStrokes(8.5, <List<double>>[
      <double>[2, 0, 6, 0, 8, 2, 8, 8, 6, 10, 2, 10, 0, 8, 0, 2, 2, 0],
    ], smooth: true),
    'P': GlyphStrokes(7.5, <List<double>>[
      <double>[0, 10, 0, 0, 5, 0, 7, 2, 7, 3, 5, 5, 0, 5],
    ], smooth: true),
    'Q': GlyphStrokes(8.5, <List<double>>[
      <double>[2, 0, 6, 0, 8, 2, 8, 8, 6, 10, 2, 10, 0, 8, 0, 2, 2, 0],
      <double>[5, 7, 8, 11],
    ], smooth: true),
    'R': GlyphStrokes(7.5, <List<double>>[
      <double>[0, 10, 0, 0, 5, 0, 7, 2, 7, 3, 5, 5, 0, 5],
      <double>[3, 5, 7, 10],
    ], smooth: true),
    'S': GlyphStrokes(7, <List<double>>[
      <double>[7, 2, 5, 0, 2, 0, 0, 2, 0, 3, 2, 5, 5, 5, 7, 7, 7, 8, 5, 10, 2, 10, 0, 8],
    ], smooth: true),
    'T': GlyphStrokes(7.5, <List<double>>[
      <double>[0, 0, 7.5, 0],
      <double>[3.75, 0, 3.75, 10],
    ]),
    'U': GlyphStrokes(8, <List<double>>[
      <double>[0, 0, 0, 8, 2, 10, 6, 10, 8, 8, 8, 0],
    ], smooth: true),
    'V': GlyphStrokes(8, <List<double>>[
      <double>[0, 0, 4, 10, 8, 0],
    ]),
    'W': GlyphStrokes(10, <List<double>>[
      <double>[0, 0, 2, 10, 5, 3, 8, 10, 10, 0],
    ]),
    'X': GlyphStrokes(8, <List<double>>[
      <double>[0, 0, 8, 10],
      <double>[8, 0, 0, 10],
    ]),
    'Y': GlyphStrokes(8, <List<double>>[
      <double>[0, 0, 4, 5, 8, 0],
      <double>[4, 5, 4, 10],
    ]),
    'Z': GlyphStrokes(7.5, <List<double>>[
      <double>[0, 0, 7.5, 0, 0, 10, 7.5, 10],
    ]),

    // ===== الأحرف اللاتينية الصغيرة (ارتفاع x = 6 فوق الأساس) =====
    'a': GlyphStrokes(6.5, <List<double>>[
      <double>[6, 4, 1, 4, 0, 6, 0, 8, 1, 10, 5, 10, 6, 8],
      <double>[6, 4, 6, 10],
    ], smooth: true),
    'b': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 0, 0, 10],
      <double>[0, 5, 2, 4, 5, 4, 6, 6, 6, 8, 5, 10, 2, 10, 0, 8],
    ], smooth: true),
    'c': GlyphStrokes(6, <List<double>>[
      <double>[6, 5, 4, 4, 2, 4, 0, 6, 0, 8, 2, 10, 4, 10, 6, 9],
    ], smooth: true),
    'd': GlyphStrokes(6.5, <List<double>>[
      <double>[6, 0, 6, 10],
      <double>[6, 5, 4, 4, 2, 4, 0, 6, 0, 8, 2, 10, 5, 10, 6, 9],
    ], smooth: true),
    'e': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 8, 6, 8, 6, 6, 4, 4, 2, 4, 0, 6, 0, 8, 2, 10, 5, 10, 6, 9],
    ], smooth: true),
    'f': GlyphStrokes(5, <List<double>>[
      <double>[5, 0, 3, 1, 3, 10],
      <double>[1, 4, 5, 4],
    ], smooth: true),
    'g': GlyphStrokes(6.5, <List<double>>[
      <double>[6, 4, 6, 12, 4, 13, 2, 13, 0, 12],
      <double>[6, 5, 4, 4, 2, 4, 0, 6, 0, 8, 2, 10, 4, 10, 6, 9],
    ], smooth: true),
    'h': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 0, 0, 10],
      <double>[0, 5, 2, 4, 5, 4, 6, 6, 6, 10],
    ], smooth: true),
    'i': GlyphStrokes(3.5, <List<double>>[
      <double>[1.75, 4, 1.75, 10],
      <double>[1.75, 1, 1.75, 2],
    ]),
    'j': GlyphStrokes(4, <List<double>>[
      <double>[3, 4, 3, 12, 2, 13, 0, 13],
      <double>[3, 1, 3, 2],
    ], smooth: true),
    'k': GlyphStrokes(6, <List<double>>[
      <double>[0, 0, 0, 10],
      <double>[5, 4, 0, 8],
      <double>[2, 7, 5, 10],
    ]),
    'l': GlyphStrokes(4, <List<double>>[
      <double>[1.75, 0, 1.75, 10],
    ]),
    'm': GlyphStrokes(10, <List<double>>[
      <double>[0, 4, 0, 10],
      <double>[0, 5, 1, 4, 2.5, 4, 3.5, 5, 3.5, 10],
      <double>[3.5, 5, 4.5, 4, 6, 4, 7, 5, 7, 10],
    ], smooth: true),
    'n': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 4, 0, 10],
      <double>[0, 5, 2, 4, 5, 4, 6, 6, 6, 10],
    ], smooth: true),
    'o': GlyphStrokes(6.5, <List<double>>[
      <double>[2, 4, 5, 4, 6, 6, 6, 8, 5, 10, 2, 10, 0, 8, 0, 6, 2, 4],
    ], smooth: true),
    'p': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 4, 0, 13],
      <double>[0, 5, 2, 4, 5, 4, 6, 6, 6, 8, 5, 10, 2, 10, 0, 8],
    ], smooth: true),
    'q': GlyphStrokes(6.5, <List<double>>[
      <double>[6, 4, 6, 13],
      <double>[6, 5, 4, 4, 2, 4, 0, 6, 0, 8, 2, 10, 5, 10, 6, 9],
    ], smooth: true),
    'r': GlyphStrokes(5, <List<double>>[
      <double>[0, 4, 0, 10],
      <double>[0, 6, 2, 4, 5, 4],
    ], smooth: true),
    's': GlyphStrokes(6, <List<double>>[
      <double>[5, 5, 3, 4, 1, 4, 0, 5, 1, 6.5, 4, 7, 5, 8.5, 4, 10, 1, 10, 0, 9],
    ], smooth: true),
    't': GlyphStrokes(5, <List<double>>[
      <double>[2, 1, 2, 8, 4, 10, 5, 10],
      <double>[0, 4, 5, 4],
    ], smooth: true),
    'u': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 4, 0, 8, 1, 10, 4, 10, 6, 8, 6, 4],
      <double>[6, 6, 6, 10],
    ], smooth: true),
    'v': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 4, 3, 10, 6, 4],
    ]),
    'w': GlyphStrokes(9, <List<double>>[
      <double>[0, 4, 1.5, 10, 4.5, 6, 7.5, 10, 9, 4],
    ]),
    'x': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 4, 6, 10],
      <double>[6, 4, 0, 10],
    ]),
    'y': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 4, 3, 10],
      <double>[6, 4, 2, 13],
    ]),
    'z': GlyphStrokes(6, <List<double>>[
      <double>[0, 4, 6, 4, 0, 10, 6, 10],
    ]),

    // ===== الرموز والعمليات =====
    '+': GlyphStrokes(8, <List<double>>[
      <double>[4, 2, 4, 8],
      <double>[1, 5, 7, 5],
    ]),
    '-': GlyphStrokes(6, <List<double>>[
      <double>[0.5, 5, 5.5, 5],
    ]),
    '=': GlyphStrokes(7.5, <List<double>>[
      <double>[0.5, 3.5, 7, 3.5],
      <double>[0.5, 6.5, 7, 6.5],
    ]),
    '×': GlyphStrokes(7, <List<double>>[
      <double>[1, 3, 6, 7],
      <double>[6, 3, 1, 7],
    ]),
    '÷': GlyphStrokes(7, <List<double>>[
      <double>[1, 5, 6, 5],
      <double>[3.5, 2.5, 3.5, 2.8],
      <double>[3.5, 7.2, 3.5, 7.5],
    ]),
    '±': GlyphStrokes(7.5, <List<double>>[
      <double>[3.75, 1.5, 3.75, 6.5],
      <double>[1, 4, 6.5, 4],
      <double>[1, 9, 6.5, 9],
    ]),
    '∓': GlyphStrokes(7.5, <List<double>>[
      <double>[3.75, 1.5, 3.75, 6.5],
      <double>[1, 4, 6.5, 4],
      <double>[1, 1.5, 6.5, 1.5],
    ]),
    '·': GlyphStrokes(4, <List<double>>[
      <double>[2, 5, 2.3, 5],
    ]),
    '<': GlyphStrokes(7, <List<double>>[
      <double>[6, 2, 1, 5, 6, 8],
    ]),
    '>': GlyphStrokes(7, <List<double>>[
      <double>[1, 2, 6, 5, 1, 8],
    ]),
    '≤': GlyphStrokes(8, <List<double>>[
      <double>[6, 1, 1, 4, 6, 7],
      <double>[1, 9, 6.5, 9],
    ]),
    '≥': GlyphStrokes(8, <List<double>>[
      <double>[1, 1, 6, 4, 1, 7],
      <double>[1, 9, 6.5, 9],
    ]),
    '≠': GlyphStrokes(7.5, <List<double>>[
      <double>[0.5, 3.5, 7, 3.5],
      <double>[0.5, 6.5, 7, 6.5],
      <double>[5.5, 1.5, 2, 8.5],
    ]),
    '≈': GlyphStrokes(7.5, <List<double>>[
      <double>[0.5, 3, 2, 2, 4, 3, 6, 2, 7, 3],
      <double>[0.5, 6.5, 2, 5.5, 4, 6.5, 6, 5.5, 7, 6.5],
    ], smooth: true),
    '∼': GlyphStrokes(7.5, <List<double>>[
      <double>[0.5, 5, 2, 4, 4, 5, 5.5, 4, 7, 5],
    ], smooth: true),
    '≃': GlyphStrokes(7.5, <List<double>>[
      <double>[0.5, 3, 2, 2, 4, 3, 5.5, 2, 7, 3],
      <double>[0.5, 7, 7, 7],
    ], smooth: true),
    '≅': GlyphStrokes(7.5, <List<double>>[
      <double>[0.5, 2.5, 2, 1.5, 4, 2.5, 5.5, 1.5, 7, 2.5],
      <double>[0.5, 6, 7, 6],
      <double>[0.5, 8.5, 7, 8.5],
    ], smooth: true),
    '≡': GlyphStrokes(7.5, <List<double>>[
      <double>[0.5, 2.5, 7, 2.5],
      <double>[0.5, 5, 7, 5],
      <double>[0.5, 7.5, 7, 7.5],
    ]),
    '∝': GlyphStrokes(8.5, <List<double>>[
      <double>[8, 3, 5, 2.5, 2, 3.5, 1, 5, 2, 6.5, 5, 7.5, 8, 7],
    ], smooth: true),
    '(': GlyphStrokes(4.5, <List<double>>[
      <double>[3.5, -2, 1.5, 2, 0.5, 5, 1.5, 8, 3.5, 12],
    ], smooth: true),
    ')': GlyphStrokes(4.5, <List<double>>[
      <double>[1, -2, 3, 2, 4, 5, 3, 8, 1, 12],
    ], smooth: true),
    '[': GlyphStrokes(4.5, <List<double>>[
      <double>[4, -2, 1, -2, 1, 12, 4, 12],
    ]),
    ']': GlyphStrokes(4.5, <List<double>>[
      <double>[0.5, -2, 3.5, -2, 3.5, 12, 0.5, 12],
    ]),
    '{': GlyphStrokes(5, <List<double>>[
      <double>[4, -2, 2.5, -1, 2.5, 4, 1, 5, 2.5, 6, 2.5, 11, 4, 12],
    ], smooth: true),
    '}': GlyphStrokes(5, <List<double>>[
      <double>[1, -2, 2.5, -1, 2.5, 4, 4, 5, 2.5, 6, 2.5, 11, 1, 12],
    ], smooth: true),
    '|': GlyphStrokes(3, <List<double>>[
      <double>[1.5, -3, 1.5, 13],
    ]),
    '/': GlyphStrokes(6, <List<double>>[
      <double>[5.5, -1, 0.5, 11],
    ]),
    '\\': GlyphStrokes(6, <List<double>>[
      <double>[0.5, -1, 5.5, 11],
    ]),
    '.': GlyphStrokes(3.5, <List<double>>[
      <double>[1.5, 9.5, 1.8, 9.5],
    ]),
    ',': GlyphStrokes(3.5, <List<double>>[
      <double>[2, 9, 1, 12],
    ]),
    ';': GlyphStrokes(3.5, <List<double>>[
      <double>[2, 3, 2.3, 3],
      <double>[2, 9, 1, 12],
    ]),
    ':': GlyphStrokes(3.5, <List<double>>[
      <double>[1.7, 3.5, 2, 3.5],
      <double>[1.7, 9, 2, 9],
    ]),
    '!': GlyphStrokes(3.5, <List<double>>[
      <double>[1.75, 0, 1.75, 6.5],
      <double>[1.75, 9, 1.75, 9.3],
    ]),
    '?': GlyphStrokes(6.5, <List<double>>[
      <double>[0.5, 2, 2, 0, 4.5, 0, 6, 1.5, 6, 3, 3.2, 4.5, 3.2, 6.5],
      <double>[3.2, 9, 3.2, 9.3],
    ], smooth: true),
    "'": GlyphStrokes(3, <List<double>>[
      <double>[1.5, 0, 1.5, 3],
    ]),
    '*': GlyphStrokes(6.5, <List<double>>[
      <double>[3.25, 1, 3.25, 7],
      <double>[0.7, 2.5, 5.8, 5.5],
      <double>[5.8, 2.5, 0.7, 5.5],
    ]),
    '°': GlyphStrokes(5, <List<double>>[
      <double>[2, 0, 3.5, 0, 4, 1, 3.5, 2.5, 2, 2.5, 1.5, 1, 2, 0],
    ], smooth: true),
    '_': GlyphStrokes(7, <List<double>>[
      <double>[0, 11.5, 6.5, 11.5],
    ]),
    '%': GlyphStrokes(9, <List<double>>[
      <double>[0.5, 0, 3, 0, 3, 2.5, 0.5, 2.5, 0.5, 0],
      <double>[8, 0, 8, 2],
      <double>[8, 0, 0.5, 10],
      <double>[6, 7.5, 8.5, 7.5, 8.5, 10, 6, 10, 6, 7.5],
    ], smooth: true),
    '&': GlyphStrokes(8.5, <List<double>>[
      <double>[8, 4, 3, 0, 1, 1.5, 1, 3.5, 7.5, 7, 7.5, 8.5, 5.5, 10, 3, 10, 0.5, 8],
    ], smooth: true),
    '#': GlyphStrokes(8, <List<double>>[
      <double>[2.5, 0, 1.5, 10],
      <double>[6, 0, 5, 10],
      <double>[0, 3, 7.5, 3],
      <double>[0, 7, 7.5, 7],
    ]),
    '@': GlyphStrokes(10, <List<double>>[
      <double>[7, 4, 5, 2.5, 3, 2.5, 1.5, 4, 1.5, 6, 3, 7.5, 5, 7.5, 7, 6, 7, 3, 5.5, 2],
      <double>[7, 3, 7, 6.5, 5.5, 8, 3, 8, 1, 7],
    ], smooth: true),
    r'$': GlyphStrokes(7.5, <List<double>>[
      <double>[6.5, 2, 4.5, 0, 2, 0, 0, 2, 0, 3.5, 2, 5.5, 5, 6.5, 7, 8, 7, 9, 5, 11, 2, 11, 0, 9],
      <double>[3.5, -1.5, 3.5, 12],
    ], smooth: true),
    '~': GlyphStrokes(7.5, <List<double>>[
      <double>[0.5, 5.5, 2, 4.5, 4, 5.5, 5.5, 4.5, 7, 5.5],
    ], smooth: true),
    '^': GlyphStrokes(7, <List<double>>[
      <double>[1.5, 4, 3.5, 1, 5.5, 4],
    ]),
    '√': GlyphStrokes(9, <List<double>>[
      <double>[0, 4, 1.2, 4, 2.6, 7.5, 5, 0.5, 9, 0.5],
    ]),
    '«': GlyphStrokes(8.5, <List<double>>[
      <double>[4, 2, 2, 5, 4, 8],
      <double>[7, 2, 5, 5, 7, 8],
    ]),
    '»': GlyphStrokes(8.5, <List<double>>[
      <double>[1.5, 2, 3.5, 5, 1.5, 8],
      <double>[4.5, 2, 6.5, 5, 4.5, 8],
    ]),
    '∞': GlyphStrokes(10, <List<double>>[
      <double>[5, 5, 3.5, 3.5, 2, 3.5, 0.5, 5, 2, 6.5, 3.5, 6.5, 5, 5, 6.5, 3.5, 8, 3.5, 9.5, 5, 8, 6.5, 6.5, 6.5, 5, 5],
    ], smooth: true),
    '→': GlyphStrokes(11, <List<double>>[
      <double>[0, 5, 10, 5],
      <double>[7, 2.5, 10, 5, 7, 7.5],
    ]),
    '←': GlyphStrokes(11, <List<double>>[
      <double>[1, 5, 11, 5],
      <double>[4, 2.5, 1, 5, 4, 7.5],
    ]),
    '↔': GlyphStrokes(12, <List<double>>[
      <double>[1, 5, 11, 5],
      <double>[3.5, 2.5, 1, 5, 3.5, 7.5],
      <double>[8.5, 2.5, 11, 5, 8.5, 7.5],
    ]),
    '⇒': GlyphStrokes(11, <List<double>>[
      <double>[0.5, 3.5, 8.5, 3.5],
      <double>[0.5, 6.5, 8.5, 6.5],
      <double>[6.5, 1.5, 10.5, 5, 6.5, 8.5],
    ]),
    '⇔': GlyphStrokes(12, <List<double>>[
      <double>[1.5, 3.5, 10.5, 3.5],
      <double>[1.5, 6.5, 10.5, 6.5],
      <double>[4, 1.5, 1, 5, 4, 8.5],
      <double>[8, 1.5, 11, 5, 8, 8.5],
    ]),
    '⇌': GlyphStrokes(12, <List<double>>[
      <double>[0, 3, 11, 3],
      <double>[8, 0.5, 11, 3, 8, 5.5],
      <double>[1, 8, 12, 8],
      <double>[4, 5.5, 1, 8, 4, 10.5],
    ]),

    // ===== العلاقات والمجموعات (رياضيات المنهج) =====
    '∈': GlyphStrokes(8, <List<double>>[
      <double>[7, 2, 4, 2, 1.5, 3.5, 1, 5, 1.5, 6.5, 4, 8, 7, 8],
      <double>[1.3, 5, 6.5, 5],
    ], smooth: true),
    '∉': GlyphStrokes(8.5, <List<double>>[
      <double>[7, 2, 4, 2, 1.5, 3.5, 1, 5, 1.5, 6.5, 4, 8, 7, 8],
      <double>[1.3, 5, 6.5, 5],
      <double>[6.5, 1, 2.5, 9],
    ], smooth: true),
    '⊂': GlyphStrokes(8, <List<double>>[
      <double>[7, 2, 4, 2, 1.5, 3.5, 1, 5, 1.5, 6.5, 4, 8, 7, 8],
    ], smooth: true),
    '⊃': GlyphStrokes(8, <List<double>>[
      <double>[1, 2, 4, 2, 6.5, 3.5, 7, 5, 6.5, 6.5, 4, 8, 1, 8],
    ], smooth: true),
    '⊆': GlyphStrokes(8, <List<double>>[
      <double>[7, 1.5, 4, 1.5, 1.5, 3, 1, 4.5, 1.5, 6, 4, 7.5, 7, 7.5],
      <double>[1, 9.5, 7, 9.5],
    ], smooth: true),
    '⊇': GlyphStrokes(8, <List<double>>[
      <double>[1, 1.5, 4, 1.5, 6.5, 3, 7, 4.5, 6.5, 6, 4, 7.5, 1, 7.5],
      <double>[1, 9.5, 7, 9.5],
    ], smooth: true),
    '∪': GlyphStrokes(8, <List<double>>[
      <double>[1, 2, 1, 7, 2.5, 9, 5.5, 9, 7, 7, 7, 2],
    ], smooth: true),
    '∩': GlyphStrokes(8, <List<double>>[
      <double>[1, 9, 1, 4, 2.5, 2, 5.5, 2, 7, 4, 7, 9],
    ], smooth: true),
    '∅': GlyphStrokes(8, <List<double>>[
      <double>[2.5, 2, 5.5, 2, 7, 4.5, 5.5, 7, 2.5, 7, 1, 4.5, 2.5, 2],
      <double>[0.5, 8, 7.5, 1],
    ], smooth: true),
    '∀': GlyphStrokes(8, <List<double>>[
      <double>[0.5, 0, 4, 10, 7.5, 0],
      <double>[2, 4, 6, 4],
    ]),
    '∃': GlyphStrokes(8, <List<double>>[
      <double>[7, 0, 7, 10],
      <double>[7, 0, 1, 0],
      <double>[7, 5, 3, 5],
      <double>[7, 10, 1, 10],
    ]),
    '¬': GlyphStrokes(7.5, <List<double>>[
      <double>[1, 3, 6.5, 3, 6.5, 7],
    ]),
    '∧': GlyphStrokes(8, <List<double>>[
      <double>[1, 8, 4, 2, 7, 8],
    ]),
    '∨': GlyphStrokes(8, <List<double>>[
      <double>[1, 2, 4, 8, 7, 2],
    ]),
    '⊕': GlyphStrokes(8, <List<double>>[
      <double>[2, 0, 6, 0, 7.5, 3, 7.5, 7, 6, 10, 2, 10, 0.5, 7, 0.5, 3, 2, 0],
      <double>[4, 1, 4, 9],
      <double>[1.5, 5, 6.5, 5],
    ], smooth: true),
    '⊗': GlyphStrokes(8, <List<double>>[
      <double>[2, 0, 6, 0, 7.5, 3, 7.5, 7, 6, 10, 2, 10, 0.5, 7, 0.5, 3, 2, 0],
      <double>[1.8, 1.8, 6.2, 8.2],
      <double>[6.2, 1.8, 1.8, 8.2],
    ], smooth: true),
    '∠': GlyphStrokes(8.5, <List<double>>[
      <double>[7, 2, 1, 8, 7.5, 8],
    ]),
    '⊥': GlyphStrokes(8, <List<double>>[
      <double>[4, 1, 4, 8],
      <double>[0.5, 8, 7.5, 8],
    ]),
    '∥': GlyphStrokes(8, <List<double>>[
      <double>[2.5, 0, 2.5, 10],
      <double>[5.5, 0, 5.5, 10],
    ]),
    '∘': GlyphStrokes(7, <List<double>>[
      <double>[2.5, 3.5, 4.5, 3, 5.5, 4.2, 5.5, 5.8, 4.5, 7, 2.5, 6.5, 2, 5, 2.5, 3.5],
    ], smooth: true),
    '∂': GlyphStrokes(7, <List<double>>[
      <double>[1.5, 4.5, 3, 3.5, 5, 4, 6, 5.5, 5.5, 7.5, 3.5, 8, 1.8, 7, 1.5, 5.5],
      <double>[6, 5.5, 6, 2, 4.5, 0.5, 2.5, 1],
    ], smooth: true),
    '∇': GlyphStrokes(9, <List<double>>[
      <double>[0.5, 0, 8.5, 0, 4.5, 9, 0.5, 0],
    ]),

    // ===== الحروف اليونانية الشائعة في الرياضيات والفيزياء =====
    'α': GlyphStrokes(7, <List<double>>[
      <double>[6, 4, 3, 4, 1, 6, 1, 8.5, 3, 10, 5, 10, 6, 8.5],
      <double>[6, 4, 6, 10, 7, 10.5],
    ], smooth: true),
    'β': GlyphStrokes(6.5, <List<double>>[
      <double>[5, 0, 1, 0, 0, 3, 0, 8, 1, 10, 4, 10, 5.5, 8.5, 5.5, 6.5, 4, 5, 0, 5],
      <double>[0, 10, 0, 13],
    ], smooth: true),
    'γ': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 4, 3, 10, 6, 4],
      <double>[3, 10, 3, 12],
    ]),
    'δ': GlyphStrokes(6.5, <List<double>>[
      <double>[4, 0, 2, 1, 1, 3, 1, 8, 2, 10, 4.5, 10, 6, 8, 5, 7],
    ], smooth: true),
    'ε': GlyphStrokes(6, <List<double>>[
      <double>[5.5, 4, 3, 3.5, 1, 4.5, 1, 6, 3, 6.8, 5, 6.8],
      <double>[5, 6.8, 5.5, 8, 4.5, 10, 2, 10, 0, 8.5],
    ], smooth: true),
    'ζ': GlyphStrokes(6, <List<double>>[
      <double>[5.5, 4, 1, 4, 4, 6.5, 4.5, 9, 3, 10.5, 1, 10, 0.5, 9],
    ], smooth: true),
    'η': GlyphStrokes(6.5, <List<double>>[
      <double>[6, 4, 6, 12],
      <double>[6, 5, 4, 4, 1.5, 4.5, 0.5, 6.5, 0.5, 10],
    ], smooth: true),
    'θ': GlyphStrokes(7, <List<double>>[
      <double>[2, 0, 5, 0, 6.5, 2, 6.5, 8, 5, 10, 2, 10, 0.5, 8, 0.5, 2, 2, 0],
      <double>[0.5, 5, 6.5, 5],
    ], smooth: true),
    'ϑ': GlyphStrokes(7, <List<double>>[
      <double>[1, 3, 3, 0, 5.5, 1.5, 6.5, 5, 5.5, 8.5, 3, 10, 1, 8, 1.5, 5, 4, 4.5, 6, 5.5],
    ], smooth: true),
    'ι': GlyphStrokes(3.5, <List<double>>[
      <double>[1.75, 4, 1.75, 10],
    ]),
    'κ': GlyphStrokes(6.5, <List<double>>[
      <double>[1, 4, 1, 10],
      <double>[5.5, 4, 1.5, 7.5],
      <double>[3, 6.5, 5.5, 10],
    ]),
    'λ': GlyphStrokes(7, <List<double>>[
      <double>[0, 0, 3.5, 6, 3.5, 10],
      <double>[3.5, 6, 6, 0],
    ]),
    'μ': GlyphStrokes(7, <List<double>>[
      <double>[0, 4, 0, 12, 1.5, 13.5],
      <double>[0, 6, 1.5, 4, 4, 4, 6, 6, 6, 4],
      <double>[6, 4, 6, 10],
    ], smooth: true),
    'ν': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 4, 3, 10, 6, 4],
    ]),
    'ξ': GlyphStrokes(6, <List<double>>[
      <double>[5.5, 4, 2, 4, 1, 5, 2.5, 6.5, 4, 7],
      <double>[4, 7, 2, 8, 1.5, 9, 3, 10, 5, 10, 6, 11.5, 4.5, 13],
    ], smooth: true),
    'π': GlyphStrokes(8, <List<double>>[
      <double>[0, 4, 7.5, 4],
      <double>[2, 4, 2, 10],
      <double>[5.5, 4, 5.5, 10],
    ]),
    'ρ': GlyphStrokes(6.5, <List<double>>[
      <double>[1, 4, 1, 13],
      <double>[1, 5, 2.5, 4, 5, 4, 6, 6, 6, 8, 5, 10, 2.5, 10, 1, 8],
    ], smooth: true),
    'σ': GlyphStrokes(7, <List<double>>[
      <double>[6, 4, 2, 4, 0, 6.5, 0, 8.5, 2, 10, 4.5, 10, 6, 8.5, 6, 6],
      <double>[6, 4, 7, 4],
    ], smooth: true),
    'τ': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 4, 6, 4],
      <double>[3, 4, 3, 10, 5, 10.5],
    ], smooth: true),
    'υ': GlyphStrokes(6.5, <List<double>>[
      <double>[0.5, 4, 0.5, 8, 2, 10, 4.5, 10, 6, 8, 6, 4],
    ], smooth: true),
    'φ': GlyphStrokes(8, <List<double>>[
      <double>[3.5, -2, 3.5, 12],
      <double>[5.5, 2.5, 3, 1.5, 1, 3, 1, 8, 3, 9.5, 5.5, 8.5],
    ], smooth: true),
    'ϕ': GlyphStrokes(8, <List<double>>[
      <double>[4, -1, 4, 12],
      <double>[1.5, 4, 4, 3.5, 6.5, 4.5, 6.5, 8, 4, 9.5, 1.5, 8.5, 1.5, 5.5, 3, 4],
    ], smooth: true),
    'χ': GlyphStrokes(6.5, <List<double>>[
      <double>[0.5, 4, 6, 10],
      <double>[6, 4, 0.5, 10],
    ]),
    'ψ': GlyphStrokes(8, <List<double>>[
      <double>[4, 1, 4, 12],
      <double>[1, 4, 1, 7, 2.5, 8.5, 5.5, 8.5, 7, 7, 7, 4],
    ], smooth: true),
    'ω': GlyphStrokes(8.5, <List<double>>[
      <double>[0, 5, 1, 4, 2, 4, 2.5, 6, 2.5, 10],
      <double>[2.5, 6, 3, 4, 4.5, 4, 5, 6, 5, 10],
      <double>[5, 6, 5.5, 4, 7, 4, 8, 5],
    ], smooth: true),
    'Γ': GlyphStrokes(7.5, <List<double>>[
      <double>[0, 0, 7, 0, 0, 0, 0, 10],
    ]),
    'Δ': GlyphStrokes(9, <List<double>>[
      <double>[4.5, 0, 8.5, 10, 0.5, 10, 4.5, 0],
    ]),
    'Θ': GlyphStrokes(8.5, <List<double>>[
      <double>[2, 0, 6, 0, 8, 2, 8, 8, 6, 10, 2, 10, 0, 8, 0, 2, 2, 0],
      <double>[1, 5, 7, 5],
    ], smooth: true),
    'Λ': GlyphStrokes(8, <List<double>>[
      <double>[0.5, 10, 4, 0, 7.5, 10],
    ]),
    'Ξ': GlyphStrokes(7.5, <List<double>>[
      <double>[0.5, 0, 7, 0],
      <double>[1.5, 5, 6, 5],
      <double>[0.5, 10, 7, 10],
    ]),
    'Π': GlyphStrokes(8, <List<double>>[
      <double>[0.5, 0, 7.5, 0],
      <double>[1.5, 0, 1.5, 10],
      <double>[6.5, 0, 6.5, 10],
    ]),
    'Σ': GlyphStrokes(8, <List<double>>[
      <double>[7, 0, 1, 0, 4.5, 5, 1, 10, 7, 10],
    ]),
    'Υ': GlyphStrokes(8, <List<double>>[
      <double>[0.5, 0, 4, 5, 7.5, 0],
      <double>[4, 5, 4, 10],
    ]),
    'Φ': GlyphStrokes(8, <List<double>>[
      <double>[4, -1, 4, 11],
      <double>[4, 1.5, 1.5, 3, 1, 5.5, 2, 8, 4, 9, 6, 8, 7, 5.5, 6.5, 3, 4, 1.5],
    ], smooth: true),
    'Ψ': GlyphStrokes(8.5, <List<double>>[
      <double>[4.25, 0, 4.25, 11],
      <double>[1, 2, 1, 5, 2.5, 6.5, 6, 6.5, 7.5, 5, 7.5, 2],
    ], smooth: true),
    'Ω': GlyphStrokes(9, <List<double>>[
      <double>[0.5, 10, 2, 2, 4.5, 0, 7, 2, 8.5, 10],
      <double>[1.5, 10, 7.5, 10],
      <double>[5.5, 6, 7.5, 6, 7.5, 10],
      <double>[1.5, 6, 3.5, 6, 3.5, 10],
    ], smooth: true),

    // ===== رموز العمليات الكبيرة (تُرسم بحجم خاص) =====
    '∫': GlyphStrokes(7, <List<double>>[
      <double>[5, -3, 3, -2, 2, 0, 2, 7, 3, 10, 5, 11.5, 6.5, 11],
    ], smooth: true),
    '∬': GlyphStrokes(10.5, <List<double>>[
      <double>[5, -3, 3, -2, 2, 0, 2, 7, 3, 10, 5, 11.5, 6.5, 11],
      <double>[8.5, -3, 6.5, -2, 5.5, 0, 5.5, 7, 6.5, 10, 8.5, 11.5, 10, 11],
    ], smooth: true),
    '∭': GlyphStrokes(14, <List<double>>[
      <double>[5, -3, 3, -2, 2, 0, 2, 7, 3, 10, 5, 11.5, 6.5, 11],
      <double>[8.5, -3, 6.5, -2, 5.5, 0, 5.5, 7, 6.5, 10, 8.5, 11.5, 10, 11],
      <double>[12, -3, 10, -2, 9, 0, 9, 7, 10, 10, 12, 11.5, 13.5, 11],
    ], smooth: true),
    '∮': GlyphStrokes(8, <List<double>>[
      <double>[5, -3, 3, -2, 2, 0, 2, 7, 3, 10, 5, 11.5, 6.5, 11],
      <double>[1.5, 4.5, 3.5, 3, 5.5, 4.5, 3.5, 6, 1.5, 4.5],
    ], smooth: true),
    '∑': GlyphStrokes(9, <List<double>>[
      <double>[0.5, -2, 8.5, -2, 3, 5, 8.5, 12, 0.5, 12],
    ]),
    '∏': GlyphStrokes(9, <List<double>>[
      <double>[0.5, -2, 8.5, -2, 8.5, 12, 6, 12, 6, 1, 3, 1, 3, 12, 0.5, 12],
    ]),
  };
}

/// خطوط محرف واحد: [advance] عرض التقدم، و[strokes] خطوط متعددة النقاط
/// (كل واحد [x1,y1,x2,y2,...] بمحور Y نازل وخط أساس y=10).
///
/// [smooth] يوسم المحرف منحنىً: تُحوَّل خطوطه إلى منحنيات Bézier ناعمة عند
/// الرسم (Catmull-Rom عبر نقاط التحكم) بدل وصل النقاط بقطع مستقيمة.
class GlyphStrokes {
  const GlyphStrokes(this.advance, this.strokes, {this.smooth = false});

  final double advance;
  final List<List<double>> strokes;

  /// هل يُرسم المحرف منحنىً ناعماً؟
  final bool smooth;
}
