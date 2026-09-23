class NameNormalizer {
  static const _accents = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };

  static String normalize(String value) {
    var text = value.trim().toLowerCase();
    _accents.forEach((from, to) {
      text = text.replaceAll(from, to);
    });
    text = text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    return text;
  }

  static String stem(String value) {
    final normalized = normalize(value);
    if (normalized.endsWith('es') && normalized.length > 5) {
      return normalized.substring(0, normalized.length - 2);
    }
    if (normalized.endsWith('s') && normalized.length > 4) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static bool matches(String left, String right) {
    return stem(left) == stem(right);
  }
}
