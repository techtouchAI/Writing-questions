/// خطاً تخطيطي متجهاً مصغّراً (stroke font) لمحارف المعادلات.
///
/// كل محرف = قائمة خطوط (polylines) داخل صندوق وحدات:
/// - سيني [0..advance]، صادي [0..13] بمحور Y نازل (كـ SVG)،
/// - خط الأساس عند y = 10، وارتفاع الأحرف الكبيرة 10 وحدات،
/// - النزول تحت الأساس (descenders) حتى y = 13.
///
/// يُستخدم لتحويل صيغ LaTeX إلى رسوم SVG متجهة خالصة (بلا نصوص SVG)
/// ليطبعها محرك الـ PDF عبر `pw.SvgImage` دون الحاجة لخطوط خارجية.
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
    ]),
    '1': GlyphStrokes(6, <List<double>>[
      <double>[1, 2, 3, 0, 3, 10],
      <double>[1, 10, 5, 10],
    ]),
    '2': GlyphStrokes(7, <List<double>>[
      <double>[0, 2, 2, 0, 5, 0, 7, 2, 7, 4, 0, 10],
      <double>[0, 10, 7, 10],
    ]),
    '3': GlyphStrokes(7, <List<double>>[
      <double>[0, 0, 7, 0, 3, 4],
      <double>[3, 4, 5, 4, 7, 6, 7, 8, 5, 10, 2, 10, 0, 8],
    ]),
    '4': GlyphStrokes(7.5, <List<double>>[
      <double>[5, 10, 5, 0, 0, 7, 7, 7],
    ]),
    '5': GlyphStrokes(7, <List<double>>[
      <double>[7, 0, 0, 0, 0, 4, 5, 4, 7, 6, 7, 8, 5, 10, 2, 10, 0, 8],
    ]),
    '6': GlyphStrokes(7, <List<double>>[
      <double>[7, 0, 2, 1, 0, 5, 0, 8, 2, 10, 5, 10, 7, 8, 7, 6, 5, 4, 2, 4, 0, 6],
    ]),
    '7': GlyphStrokes(7, <List<double>>[
      <double>[0, 0, 7, 0, 3, 10],
    ]),
    '8': GlyphStrokes(7, <List<double>>[
      <double>[2, 0, 5, 0, 7, 2, 7, 3, 5, 5, 2, 5, 0, 7, 0, 8, 2, 10, 5, 10, 7, 8, 7, 7, 5, 5, 2, 5, 0, 3, 0, 2, 2, 0],
    ]),
    '9': GlyphStrokes(7, <List<double>>[
      <double>[0, 10, 5, 9, 7, 5, 7, 2, 5, 0, 2, 0, 0, 2, 0, 4, 2, 6, 5, 6, 7, 4],
    ]),

    // ===== الأحرف اللاتينية الكبيرة =====
    'A': GlyphStrokes(8, <List<double>>[
      <double>[0, 10, 4, 0, 8, 10],
      <double>[1.6, 6, 6.4, 6],
    ]),
    'B': GlyphStrokes(7.5, <List<double>>[
      <double>[0, 0, 0, 10],
      <double>[0, 0, 5, 0, 7, 2, 7, 3, 5, 5, 0, 5],
      <double>[0, 5, 5, 5, 7, 7, 7, 8, 5, 10, 0, 10],
    ]),
    'C': GlyphStrokes(8, <List<double>>[
      <double>[7, 2, 5, 0, 2, 0, 0, 2, 0, 8, 2, 10, 5, 10, 7, 8],
    ]),
    'D': GlyphStrokes(8, <List<double>>[
      <double>[0, 0, 0, 10],
      <double>[0, 0, 5, 0, 8, 3, 8, 7, 5, 10, 0, 10],
    ]),
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
    ]),
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
    ]),
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
    ]),
    'P': GlyphStrokes(7.5, <List<double>>[
      <double>[0, 10, 0, 0, 5, 0, 7, 2, 7, 3, 5, 5, 0, 5],
    ]),
    'Q': GlyphStrokes(8.5, <List<double>>[
      <double>[2, 0, 6, 0, 8, 2, 8, 8, 6, 10, 2, 10, 0, 8, 0, 2, 2, 0],
      <double>[5, 7, 8, 11],
    ]),
    'R': GlyphStrokes(7.5, <List<double>>[
      <double>[0, 10, 0, 0, 5, 0, 7, 2, 7, 3, 5, 5, 0, 5],
      <double>[3, 5, 7, 10],
    ]),
    'S': GlyphStrokes(7, <List<double>>[
      <double>[7, 2, 5, 0, 2, 0, 0, 2, 0, 3, 2, 5, 5, 5, 7, 7, 7, 8, 5, 10, 2, 10, 0, 8],
    ]),
    'T': GlyphStrokes(7.5, <List<double>>[
      <double>[0, 0, 7.5, 0],
      <double>[3.75, 0, 3.75, 10],
    ]),
    'U': GlyphStrokes(8, <List<double>>[
      <double>[0, 0, 0, 8, 2, 10, 6, 10, 8, 8, 8, 0],
    ]),
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
    ]),
    'b': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 0, 0, 10],
      <double>[0, 5, 2, 4, 5, 4, 6, 6, 6, 8, 5, 10, 2, 10, 0, 8],
    ]),
    'c': GlyphStrokes(6, <List<double>>[
      <double>[6, 5, 4, 4, 2, 4, 0, 6, 0, 8, 2, 10, 4, 10, 6, 9],
    ]),
    'd': GlyphStrokes(6.5, <List<double>>[
      <double>[6, 0, 6, 10],
      <double>[6, 5, 4, 4, 2, 4, 0, 6, 0, 8, 2, 10, 5, 10, 6, 9],
    ]),
    'e': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 8, 6, 8, 6, 6, 4, 4, 2, 4, 0, 6, 0, 8, 2, 10, 5, 10, 6, 9],
    ]),
    'f': GlyphStrokes(5, <List<double>>[
      <double>[5, 0, 3, 1, 3, 10],
      <double>[1, 4, 5, 4],
    ]),
    'g': GlyphStrokes(6.5, <List<double>>[
      <double>[6, 4, 6, 12, 4, 13, 2, 13, 0, 12],
      <double>[6, 5, 4, 4, 2, 4, 0, 6, 0, 8, 2, 10, 4, 10, 6, 9],
    ]),
    'h': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 0, 0, 10],
      <double>[0, 5, 2, 4, 5, 4, 6, 6, 6, 10],
    ]),
    'i': GlyphStrokes(3.5, <List<double>>[
      <double>[1.75, 4, 1.75, 10],
      <double>[1.75, 1, 1.75, 2],
    ]),
    'j': GlyphStrokes(4, <List<double>>[
      <double>[3, 4, 3, 12, 2, 13, 0, 13],
      <double>[3, 1, 3, 2],
    ]),
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
    ]),
    'n': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 4, 0, 10],
      <double>[0, 5, 2, 4, 5, 4, 6, 6, 6, 10],
    ]),
    'o': GlyphStrokes(6.5, <List<double>>[
      <double>[2, 4, 5, 4, 6, 6, 6, 8, 5, 10, 2, 10, 0, 8, 0, 6, 2, 4],
    ]),
    'p': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 4, 0, 13],
      <double>[0, 5, 2, 4, 5, 4, 6, 6, 6, 8, 5, 10, 2, 10, 0, 8],
    ]),
    'q': GlyphStrokes(6.5, <List<double>>[
      <double>[6, 4, 6, 13],
      <double>[6, 5, 4, 4, 2, 4, 0, 6, 0, 8, 2, 10, 5, 10, 6, 9],
    ]),
    'r': GlyphStrokes(5, <List<double>>[
      <double>[0, 4, 0, 10],
      <double>[0, 6, 2, 4, 5, 4],
    ]),
    's': GlyphStrokes(6, <List<double>>[
      <double>[5, 5, 3, 4, 1, 4, 0, 5, 1, 6.5, 4, 7, 5, 8.5, 4, 10, 1, 10, 0, 9],
    ]),
    't': GlyphStrokes(5, <List<double>>[
      <double>[2, 1, 2, 8, 4, 10, 5, 10],
      <double>[0, 4, 5, 4],
    ]),
    'u': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 4, 0, 8, 1, 10, 4, 10, 6, 8, 6, 4],
      <double>[6, 6, 6, 10],
    ]),
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
    ]),
    '≡': GlyphStrokes(7.5, <List<double>>[
      <double>[0.5, 2.5, 7, 2.5],
      <double>[0.5, 5, 7, 5],
      <double>[0.5, 7.5, 7, 7.5],
    ]),
    '(': GlyphStrokes(4.5, <List<double>>[
      <double>[3.5, -2, 1.5, 2, 0.5, 5, 1.5, 8, 3.5, 12],
    ]),
    ')': GlyphStrokes(4.5, <List<double>>[
      <double>[1, -2, 3, 2, 4, 5, 3, 8, 1, 12],
    ]),
    '[': GlyphStrokes(4.5, <List<double>>[
      <double>[4, -2, 1, -2, 1, 12, 4, 12],
    ]),
    ']': GlyphStrokes(4.5, <List<double>>[
      <double>[0.5, -2, 3.5, -2, 3.5, 12, 0.5, 12],
    ]),
    '{': GlyphStrokes(5, <List<double>>[
      <double>[4, -2, 2.5, -1, 2.5, 4, 1, 5, 2.5, 6, 2.5, 11, 4, 12],
    ]),
    '}': GlyphStrokes(5, <List<double>>[
      <double>[1, -2, 2.5, -1, 2.5, 4, 4, 5, 2.5, 6, 2.5, 11, 1, 12],
    ]),
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
    ]),
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
    ]),
    '_': GlyphStrokes(7, <List<double>>[
      <double>[0, 11.5, 6.5, 11.5],
    ]),
    '%': GlyphStrokes(9, <List<double>>[
      <double>[0.5, 0, 3, 0, 3, 2.5, 0.5, 2.5, 0.5, 0],
      <double>[8, 0, 8, 2],
      <double>[8, 0, 0.5, 10],
      <double>[6, 7.5, 8.5, 7.5, 8.5, 10, 6, 10, 6, 7.5],
    ]),
    '&': GlyphStrokes(8.5, <List<double>>[
      <double>[8, 4, 3, 0, 1, 1.5, 1, 3.5, 7.5, 7, 7.5, 8.5, 5.5, 10, 3, 10, 0.5, 8],
    ]),
    '#': GlyphStrokes(8, <List<double>>[
      <double>[2.5, 0, 1.5, 10],
      <double>[6, 0, 5, 10],
      <double>[0, 3, 7.5, 3],
      <double>[0, 7, 7.5, 7],
    ]),
    '@': GlyphStrokes(10, <List<double>>[
      <double>[7, 4, 5, 2.5, 3, 2.5, 1.5, 4, 1.5, 6, 3, 7.5, 5, 7.5, 7, 6, 7, 3, 5.5, 2],
      <double>[7, 3, 7, 6.5, 5.5, 8, 3, 8, 1, 7],
    ]),
    r'$': GlyphStrokes(7.5, <List<double>>[
      <double>[6.5, 2, 4.5, 0, 2, 0, 0, 2, 0, 3.5, 2, 5.5, 5, 6.5, 7, 8, 7, 9, 5, 11, 2, 11, 0, 9],
      <double>[3.5, -1.5, 3.5, 12],
    ]),
    '∞': GlyphStrokes(10, <List<double>>[
      <double>[5, 5, 3.5, 3.5, 2, 3.5, 0.5, 5, 2, 6.5, 3.5, 6.5, 5, 5, 6.5, 3.5, 8, 3.5, 9.5, 5, 8, 6.5, 6.5, 6.5, 5, 5],
    ]),
    '→': GlyphStrokes(11, <List<double>>[
      <double>[0, 5, 10, 5],
      <double>[7, 2.5, 10, 5, 7, 7.5],
    ]),
    '←': GlyphStrokes(11, <List<double>>[
      <double>[1, 5, 11, 5],
      <double>[4, 2.5, 1, 5, 4, 7.5],
    ]),
    '⇌': GlyphStrokes(12, <List<double>>[
      <double>[0, 3, 11, 3],
      <double>[8, 0.5, 11, 3, 8, 5.5],
      <double>[1, 8, 12, 8],
      <double>[4, 5.5, 1, 8, 4, 10.5],
    ]),

    // ===== الحروف اليونانية الشائعة في الرياضيات والفيزياء =====
    'α': GlyphStrokes(7, <List<double>>[
      <double>[6, 4, 3, 4, 1, 6, 1, 8.5, 3, 10, 5, 10, 6, 8.5],
      <double>[6, 4, 6, 10, 7, 10.5],
    ]),
    'β': GlyphStrokes(6.5, <List<double>>[
      <double>[5, 0, 1, 0, 0, 3, 0, 8, 1, 10, 4, 10, 5.5, 8.5, 5.5, 6.5, 4, 5, 0, 5],
      <double>[0, 10, 0, 13],
    ]),
    'γ': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 4, 3, 10, 6, 4],
      <double>[3, 10, 3, 12],
    ]),
    'δ': GlyphStrokes(6.5, <List<double>>[
      <double>[4, 0, 2, 1, 1, 3, 1, 8, 2, 10, 4.5, 10, 6, 8, 5, 7],
    ]),
    'ε': GlyphStrokes(6, <List<double>>[
      <double>[5.5, 4, 3, 3.5, 1, 4.5, 1, 6, 3, 6.8, 5, 6.8],
      <double>[5, 6.8, 5.5, 8, 4.5, 10, 2, 10, 0, 8.5],
    ]),
    'θ': GlyphStrokes(7, <List<double>>[
      <double>[2, 0, 5, 0, 6.5, 2, 6.5, 8, 5, 10, 2, 10, 0.5, 8, 0.5, 2, 2, 0],
      <double>[0.5, 5, 6.5, 5],
    ]),
    'λ': GlyphStrokes(7, <List<double>>[
      <double>[0, 0, 3.5, 6, 3.5, 10],
      <double>[3.5, 6, 6, 0],
    ]),
    'μ': GlyphStrokes(7, <List<double>>[
      <double>[0, 4, 0, 12, 1.5, 13.5],
      <double>[0, 6, 1.5, 4, 4, 4, 6, 6, 6, 4],
      <double>[6, 4, 6, 10],
    ]),
    'π': GlyphStrokes(8, <List<double>>[
      <double>[0, 4, 7.5, 4],
      <double>[2, 4, 2, 10],
      <double>[5.5, 4, 5.5, 10],
    ]),
    'σ': GlyphStrokes(7, <List<double>>[
      <double>[6, 4, 2, 4, 0, 6.5, 0, 8.5, 2, 10, 4.5, 10, 6, 8.5, 6, 6],
      <double>[6, 4, 7, 4],
    ]),
    'τ': GlyphStrokes(6.5, <List<double>>[
      <double>[0, 4, 6, 4],
      <double>[3, 4, 3, 10, 5, 10.5],
    ]),
    'φ': GlyphStrokes(8, <List<double>>[
      <double>[3.5, -2, 3.5, 12],
      <double>[5.5, 2.5, 3, 1.5, 1, 3, 1, 8, 3, 9.5, 5.5, 8.5],
    ]),
    'ω': GlyphStrokes(8.5, <List<double>>[
      <double>[0, 5, 1, 4, 2, 4, 2.5, 6, 2.5, 10],
      <double>[2.5, 6, 3, 4, 4.5, 4, 5, 6, 5, 10],
      <double>[5, 6, 5.5, 4, 7, 4, 8, 5],
    ]),
    'Γ': GlyphStrokes(7.5, <List<double>>[
      <double>[0, 0, 7, 0, 0, 0, 0, 10],
    ]),
    'Δ': GlyphStrokes(9, <List<double>>[
      <double>[4.5, 0, 8.5, 10, 0.5, 10, 4.5, 0],
    ]),
    'Ω': GlyphStrokes(9, <List<double>>[
      <double>[0.5, 10, 2, 2, 4.5, 0, 7, 2, 8.5, 10],
      <double>[1.5, 10, 7.5, 10],
      <double>[5.5, 6, 7.5, 6, 7.5, 10],
      <double>[1.5, 6, 3.5, 6, 3.5, 10],
    ]),

    // ===== رموز العمليات الكبيرة (تُرسم بحجم خاص) =====
    '∫': GlyphStrokes(7, <List<double>>[
      <double>[5, -3, 3, -2, 2, 0, 2, 7, 3, 10, 5, 11.5, 6.5, 11],
    ]),
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
class GlyphStrokes {
  const GlyphStrokes(this.advance, this.strokes);

  final double advance;
  final List<List<double>> strokes;
}
