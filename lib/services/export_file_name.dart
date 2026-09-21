class ExportFileName {
  const ExportFileName._();

  static String fileName({
    required String value,
    required String extension,
    required String fallbackStem,
  }) {
    final normalizedExtension =
        extension.startsWith('.') ? extension.toLowerCase() : '.${extension.toLowerCase()}';
    final trimmedValue = value.trim();
    final stem = trimmedValue.toLowerCase().endsWith(normalizedExtension)
        ? trimmedValue.substring(0, trimmedValue.length - normalizedExtension.length)
        : trimmedValue;

    return '${_sanitizeFileStem(stem, fallbackStem)}$normalizedExtension';
  }

  static String excelSheetName(String value, {String fallback = 'بنك الأسئلة'}) {
    final invalidCharacters = <int>{
      ...'[]:*?/\\'.runes,
      ...Iterable<int>.generate(32),
    };
    final buffer = StringBuffer();

    for (final rune in value.trim().runes) {
      buffer.write(invalidCharacters.contains(rune) ? ' ' : String.fromCharCode(rune));
    }

    var sanitized = _normalizeWhitespace(buffer.toString())
        .replaceAll(RegExp("^'+|'+$"), '')
        .trim();
    if (sanitized.isEmpty) {
      sanitized = fallback;
    }

    return _truncateRunes(sanitized, 31);
  }

  static String _sanitizeFileStem(String value, String fallback) {
    final invalidCharacters = <int>{
      ...'<>:"/\\|?*'.runes,
      ...Iterable<int>.generate(32),
    };
    final buffer = StringBuffer();

    for (final rune in value.trim().runes) {
      buffer.write(invalidCharacters.contains(rune) ? '_' : String.fromCharCode(rune));
    }

    var sanitized = _normalizeWhitespace(buffer.toString())
        .replaceAll(RegExp('_+'), '_')
        .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '')
        .trim();
    if (sanitized.isEmpty ||
        sanitized == '.' ||
        sanitized == '..' ||
        RegExp(r'^_+$').hasMatch(sanitized)) {
      sanitized = fallback;
    }

    return _truncateRunes(sanitized, 80);
  }

  static String _normalizeWhitespace(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _truncateRunes(String value, int maximumLength) {
    final runes = value.runes.toList(growable: false);
    if (runes.length <= maximumLength) {
      return value;
    }
    return String.fromCharCodes(runes.take(maximumLength));
  }
}
