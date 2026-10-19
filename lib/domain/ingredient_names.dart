// Cómo se comparan los nombres de ingredientes y de productos. Lo usan los dos
// motores de recetas (lib/ui/models/recipe.dart y lib/domain) para que un
// mismo nombre se lea igual en los dos: al buscarlo en la despensa y al
// revisar si lleva un alérgeno.

const _diacritics = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ñ': 'n',
  'ç': 'c',
};

/// Forma comparable de un nombre de producto: minúsculas, sin acentos, sin
/// signos, espacios simples y cada palabra en singular.
/// "  Frijoles  NEGROS" -> "frijol negro", "Atún en lata" -> "atun en lata".
String normalizeName(String text) {
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    // Acentos escritos como carácter aparte (combining marks).
    if (rune >= 0x300 && rune <= 0x36f) continue;
    final char = String.fromCharCode(rune);
    buffer.write(_diacritics[char] ?? char);
  }
  return buffer
      .toString()
      .replaceAll(RegExp('[^a-z0-9]+'), ' ')
      .trim()
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map(_singular)
      .join(' ');
}

/// Quita el plural de forma conservadora: "frijoles" -> "frijol",
/// "lentejas" -> "lenteja", "jitomates" -> "jitomate". Las palabras de 3
/// letras o menos ("de", "mas") no se tocan.
String _singular(String word) {
  if (word.length <= 3 || !word.endsWith('s')) return word;
  final stem = word.substring(0, word.length - 2);
  if (word.endsWith('es') && stem.length >= 3 && _esPluralStem.hasMatch(stem)) {
    return stem;
  }
  if (_vowel.hasMatch(word[word.length - 2])) {
    return word.substring(0, word.length - 1);
  }
  return word;
}

final _esPluralStem = RegExp(r'[lnrdjy]$');
final _vowel = RegExp('[aeiou]');

/// Si dos palabras ya normalizadas son la misma. Cubre plurales que
/// [_singular] no puede resolver solo: "chiles" -> "chil" (igual a "chile") y
/// "nueces" -> "nuece" (igual a "nuez").
bool sameIngredientWord(String a, String b) {
  if (a == b) return true;
  final (short, long) = a.length <= b.length ? (a, b) : (b, a);
  if (long == '${short}e' && _esPluralStem.hasMatch(short)) return true;
  return short.endsWith('z') &&
      long.endsWith('ce') &&
      long.length == short.length + 1 &&
      long.startsWith(short.substring(0, short.length - 1));
}
