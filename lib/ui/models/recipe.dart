import 'dart:math' as math;

import '../../data/models/member.dart';
import '../../data/models/pantry_item.dart';
import '../formatting.dart';
import 'expiration_urgency.dart';

// Las recetas siguen siendo un catálogo de ejemplo (aún no hay colección en
// Firestore), pero se comparan con la despensa real, se ajustan al número de
// integrantes y se revisan contra las alergias de la familia. El plan de
// comidas se arma con esas recetas y lo que caduca primero en la despensa.

class RecipeIngredient {
  const RecipeIngredient(this.name, this.quantity, this.unit);

  final String name;
  final double quantity;
  final FoodUnit unit;

  /// "0.25 kg", "2 latas".
  String get amount => formatAmount(quantity, unit);
}

class Recipe {
  const Recipe({
    required this.name,
    required this.image,
    required this.minutes,
    required this.servings,
    required this.kcalPerServing,
    required this.ingredients,
    required this.steps,
  });

  final String name;
  final String image;
  final int minutes;
  final int servings;
  final int kcalPerServing;
  final List<RecipeIngredient> ingredients;
  final List<String> steps;

  bool get isQuick => minutes <= 30;
}

class MealPlanEntry {
  const MealPlanEntry({
    required this.day,
    required this.recipe,
    required this.reason,
    required this.urgency,
  });

  /// Abreviatura del día, p. ej. "Lun".
  final String day;
  final Recipe recipe;

  /// Por qué se eligió la receta, p. ej. "Usa Jamón (caduca en 3 días)".
  /// Puede tener dos líneas si además faltan ingredientes.
  final String reason;
  final ExpirationUrgency urgency;
}

class IngredientAvailability {
  const IngredientAvailability({
    required this.ingredient,
    required this.available,
    required this.availableQuantity,
  });

  final RecipeIngredient ingredient;

  /// Si la despensa tiene al menos la cantidad que pide la receta.
  final bool available;

  /// Lo que hay en la despensa, en la unidad del ingrediente.
  final double availableQuantity;
}

const _epsilon = 1e-9;

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
bool _sameWord(String a, String b) {
  if (a == b) return true;
  final (short, long) = a.length <= b.length ? (a, b) : (b, a);
  if (long == '${short}e' && _esPluralStem.hasMatch(short)) return true;
  return short.endsWith('z') &&
      long.endsWith('ce') &&
      long.length == short.length + 1 &&
      long.startsWith(short.substring(0, short.length - 1));
}

/// Iguales, o uno es el inicio del otro palabra por palabra ("leche" y
/// "leche entera").
bool _namesMatch(String a, String b) {
  if (a.isEmpty || b.isEmpty) return false;
  final wordsA = a.split(' ');
  final wordsB = b.split(' ');
  final count = math.min(wordsA.length, wordsB.length);
  for (var i = 0; i < count; i++) {
    if (!_sameWord(wordsA[i], wordsB[i])) return false;
  }
  return true;
}

({String group, double factor}) _unitScale(FoodUnit unit) => switch (unit) {
  FoodUnit.kg => (group: 'mass', factor: 1000),
  FoodUnit.g => (group: 'mass', factor: 1),
  FoodUnit.l => (group: 'volume', factor: 1000),
  FoodUnit.ml => (group: 'volume', factor: 1),
  FoodUnit.piece ||
  FoodUnit.can ||
  FoodUnit.pack => (group: unit.name, factor: 1),
};

/// Convierte [quantity] de [from] a [to] (kg/g y L/ml). Las piezas, latas y
/// paquetes solo equivalen a la misma unidad; si no hay conversión regresa
/// null.
double? convertQuantity(double quantity, FoodUnit from, FoodUnit to) {
  if (from == to) return quantity;
  final source = _unitScale(from);
  final target = _unitScale(to);
  if (source.group != target.group) return null;
  return quantity * source.factor / target.factor;
}

double _round3(double value) => (value * 1000).round() / 1000;

/// Si el producto de la despensa sirve para el ingrediente: mismo nombre (ver
/// [normalizeName]) y una unidad convertible.
bool ingredientMatches(RecipeIngredient ingredient, PantryItem item) =>
    convertQuantity(1, item.unit, ingredient.unit) != null &&
    _namesMatch(
      normalizeName(productDisplayName(item.productId)),
      normalizeName(ingredient.name),
    );

/// Productos de la despensa que sirven para [ingredient]. Los caducados no
/// cuentan: no se sugieren ni se descuentan al preparar una receta.
List<PantryItem> _matchingItems(
  RecipeIngredient ingredient,
  List<PantryItem> pantry,
  DateTime today,
) => [
  for (final item in pantry)
    if (item.quantity > 0 &&
        daysLeft(item, today: today) >= 0 &&
        ingredientMatches(ingredient, item))
      item,
];

/// Cuánto hay de cada ingrediente de [recipe] en la despensa.
List<IngredientAvailability> checkAvailability(
  Recipe recipe,
  List<PantryItem> pantry, {
  DateTime? today,
}) => [
  for (final ingredient in recipe.ingredients)
    _availability(ingredient, pantry, today ?? DateTime.now()),
];

IngredientAvailability _availability(
  RecipeIngredient ingredient,
  List<PantryItem> pantry,
  DateTime today,
) {
  var total = 0.0;
  for (final item in _matchingItems(ingredient, pantry, today)) {
    total += convertQuantity(item.quantity, item.unit, ingredient.unit)!;
  }
  total = _round3(total);
  return IngredientAvailability(
    ingredient: ingredient,
    available: total > 0 && total >= ingredient.quantity - _epsilon,
    availableQuantity: total,
  );
}

/// Lo que se descuenta de la despensa al preparar [recipe]. Cada ingrediente
/// se toma primero de los productos que caducan antes, sin pasar de lo que
/// queda de cada uno. Si varios ingredientes usan el mismo producto se suman
/// en una sola entrada. Los ingredientes que no están en la despensa se
/// omiten, así que la lista puede quedar vacía.
List<({PantryItem item, double amount})> planConsumption(
  Recipe recipe,
  List<PantryItem> pantry, {
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  int days(PantryItem item) => daysLeft(item, today: now);
  final left = Map<PantryItem, double>.identity();
  final taken = Map<PantryItem, double>.identity();

  for (final ingredient in recipe.ingredients) {
    final candidates = _matchingItems(ingredient, pantry, now)
      ..sort((a, b) {
        final byDays = days(a).compareTo(days(b));
        if (byDays != 0) return byDays;
        final byAge = a.localTimestamp.compareTo(b.localTimestamp);
        return byAge != 0 ? byAge : a.pantryItemId.compareTo(b.pantryItemId);
      });

    var needed = ingredient.quantity;
    for (final item in candidates) {
      if (needed <= _epsilon) break;
      final available = left[item] ?? item.quantity;
      if (available <= _epsilon) continue;

      final wanted = convertQuantity(needed, ingredient.unit, item.unit)!;
      final amount = math.min(_round3(math.min(available, wanted)), available);
      if (amount <= 0) continue;

      left[item] = available - amount;
      taken[item] = (taken[item] ?? 0) + amount;
      needed -= convertQuantity(amount, item.unit, ingredient.unit)!;
    }
  }

  final plan = <({PantryItem item, double amount})>[];
  for (final MapEntry(key: item, value: amount) in taken.entries) {
    final total = math.min(_round3(amount), item.quantity);
    if (total > 0) plan.add((item: item, amount: total));
  }
  return plan;
}

// ---------------------------------------------------------------------------
// Porciones según el tamaño del hogar.

/// Piezas, latas y paquetes no se pueden partir.
bool _isCountUnit(FoodUnit unit) =>
    unit == FoodUnit.piece || unit == FoodUnit.can || unit == FoodUnit.pack;

/// [recipe] con porciones para [householdSize] personas: cada cantidad se
/// multiplica por householdSize / servings y se redondea a 3 decimales (las
/// piezas, latas y paquetes se redondean hacia arriba). Si no se conoce el
/// tamaño del hogar (0) o ya coincide con las porciones, regresa la misma
/// receta.
Recipe scaledRecipe(Recipe recipe, int householdSize) {
  if (householdSize <= 0 ||
      recipe.servings <= 0 ||
      householdSize == recipe.servings) {
    return recipe;
  }
  final factor = householdSize / recipe.servings;
  return Recipe(
    name: recipe.name,
    image: recipe.image,
    minutes: recipe.minutes,
    servings: householdSize,
    kcalPerServing: recipe.kcalPerServing,
    ingredients: [
      for (final ingredient in recipe.ingredients)
        RecipeIngredient(
          ingredient.name,
          _scaledQuantity(ingredient, factor),
          ingredient.unit,
        ),
    ],
    steps: recipe.steps,
  );
}

double _scaledQuantity(RecipeIngredient ingredient, double factor) {
  if (ingredient.quantity <= 0) return ingredient.quantity;
  // Se redondea antes de subir al entero para que 2.0000000001 siga siendo 2.
  final scaled = _round3(ingredient.quantity * factor);
  if (_isCountUnit(ingredient.unit)) {
    return math.max(1.0, scaled.ceilToDouble());
  }
  // Una cantidad muy pequeña no debe quedar en 0.
  return math.max(0.001, scaled);
}

// ---------------------------------------------------------------------------
// Alergias de la familia.

/// Palabras que delatan cada alérgeno en el nombre de un ingrediente, en la
/// forma de [normalizeName] (sin acentos y en singular).
const allergenKeywords = <Allergy, List<String>>{
  Allergy.dairy: ['leche', 'yogurt', 'yogur', 'queso', 'crema', 'mantequilla'],
  Allergy.gluten: [
    'pan',
    'pasta',
    'harina',
    'trigo',
    'avena',
    'galleta',
    'cereal',
  ],
  Allergy.peanut: ['cacahuate', 'mani'],
  Allergy.shellfish: [
    'camaron',
    'marisco',
    'pulpo',
    'calamar',
    'ostion',
    'jaiba',
  ],
  Allergy.egg: ['huevo'],
  Allergy.soy: ['soya', 'soja', 'tofu'],
};

/// Si el nombre de un ingrediente contiene el alérgeno: "Leche entera" y
/// "Quesos" llevan lácteos. Se compara palabra por palabra, así que
/// "Lechuga" no cuenta como leche ni "Panela" como pan.
bool containsAllergen(String ingredientName, Allergy allergy) {
  final keywords = [
    for (final keyword in allergenKeywords[allergy] ?? const <String>[])
      normalizeName(keyword),
  ];
  return normalizeName(ingredientName)
      .split(' ')
      .any((word) => keywords.any((keyword) => _sameWord(word, keyword)));
}

/// Una alergia de la familia que choca con una receta: quiénes la tienen y
/// qué ingredientes la contienen.
typedef AllergyConflict = ({
  Allergy allergy,
  List<String> members,
  List<String> ingredients,
});

/// Alergias de [members] que contiene [recipe], en el orden de [Allergy].
/// Vacía si la receta no lleva nada a lo que alguien sea alérgico (o si nadie
/// registró alergias).
List<AllergyConflict> allergyConflicts(Recipe recipe, List<Member> members) {
  final conflicts = <AllergyConflict>[];
  for (final allergy in Allergy.values) {
    final allergic = [
      for (final member in members)
        if (member.allergies?.contains(allergy) ?? false) member.name.trim(),
    ];
    if (allergic.isEmpty) continue;
    final ingredients = [
      for (final ingredient in recipe.ingredients)
        if (containsAllergen(ingredient.name, allergy)) ingredient.name,
    ];
    if (ingredients.isEmpty) continue;
    conflicts.add((
      allergy: allergy,
      members: allergic,
      ingredients: ingredients,
    ));
  }
  return conflicts;
}

/// "Atención: esta receta contiene lácteos (Leche entera), y María tiene
/// alergia." No supone el género de los integrantes (de los adultos no se
/// captura).
String allergyWarning(AllergyConflict conflict) {
  final (:allergy, :members, :ingredients) = conflict;
  final verb = members.length == 1 ? 'tiene alergia' : 'tienen alergia';
  return 'Atención: esta receta contiene '
      '${allergyLabel(allergy).toLowerCase()} (${joinWithAnd(ingredients)}), '
      'y ${joinWithAnd(members)} $verb.';
}

/// "A", "A y B", "A, B y C". Antes de un sonido "i" se usa "e" ("María e
/// Isabel").
String joinWithAnd(List<String> items) {
  if (items.length <= 1) return items.join();
  final last = items.last;
  final and = _startsWithISound.hasMatch(normalizeName(last)) ? 'e' : 'y';
  return '${items.sublist(0, items.length - 1).join(', ')} $and $last';
}

final _startsWithISound = RegExp('^h?i(?![aeiou])');

// ---------------------------------------------------------------------------
// Plan de comidas.

const _weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

typedef _RankedRecipe = ({
  Recipe recipe,
  int index,
  int missing,
  PantryItem? mostUrgent,
  int? days,
});

/// Plan de 7 días que empieza hoy. Primero van las recetas que usan lo que
/// caduca antes en la despensa (lo caducado no cuenta); las que no usan nada
/// de la despensa van al final. Entre iguales va primero la que tiene menos
/// ingredientes faltantes. Con menos de 7 recetas se repiten en el mismo
/// orden.
List<MealPlanEntry> buildWeeklyPlan(
  List<Recipe> recipes,
  List<PantryItem> pantry, {
  DateTime? today,
}) {
  if (recipes.isEmpty) return const [];
  final now = today ?? DateTime.now();
  final ranked = [
    for (var i = 0; i < recipes.length; i++)
      _rankRecipe(recipes[i], i, pantry, now),
  ]..sort(_compareRanked);

  return [
    for (var day = 0; day < 7; day++)
      _planEntry(
        ranked[day % ranked.length],
        _weekdays[(now.weekday - 1 + day) % 7],
      ),
  ];
}

_RankedRecipe _rankRecipe(
  Recipe recipe,
  int index,
  List<PantryItem> pantry,
  DateTime today,
) {
  PantryItem? mostUrgent;
  int? minDays;
  for (final ingredient in recipe.ingredients) {
    for (final item in _matchingItems(ingredient, pantry, today)) {
      final days = daysLeft(item, today: today);
      if (minDays == null || days < minDays) {
        minDays = days;
        mostUrgent = item;
      }
    }
  }
  final missing = checkAvailability(
    recipe,
    pantry,
    today: today,
  ).where((a) => !a.available).length;

  return (
    recipe: recipe,
    index: index,
    missing: missing,
    mostUrgent: mostUrgent,
    days: minDays,
  );
}

int _compareRanked(_RankedRecipe a, _RankedRecipe b) {
  final (aDays, bDays) = (a.days, b.days);
  if (aDays != bDays) {
    if (aDays == null) return 1;
    if (bDays == null) return -1;
    return aDays.compareTo(bDays);
  }
  final byMissing = a.missing.compareTo(b.missing);
  return byMissing != 0 ? byMissing : a.index.compareTo(b.index);
}

/// El motivo nombra el producto solo si caduca pronto (7 días o menos); si
/// no, basta con decir si faltan ingredientes.
MealPlanEntry _planEntry(_RankedRecipe ranked, String day) {
  final (:recipe, :missing, :mostUrgent, :days, index: _) = ranked;
  final urgency = days == null
      ? ExpirationUrgency.fresh
      : ExpirationUrgency.fromDays(days);

  final reasons = [
    if (mostUrgent != null &&
        days != null &&
        urgency != ExpirationUrgency.fresh)
      'Usa ${productDisplayName(mostUrgent.productId)} (${_expiresIn(days)})',
    if (missing == 1) 'Te falta 1 ingrediente',
    if (missing > 1) 'Te faltan $missing ingredientes',
  ];

  return MealPlanEntry(
    day: day,
    recipe: recipe,
    reason: reasons.isEmpty
        ? 'Con productos de tu despensa'
        : reasons.join('\n'),
    urgency: urgency,
  );
}

String _expiresIn(int days) => switch (days) {
  0 => 'caduca hoy',
  1 => 'caduca mañana',
  _ => 'caduca en $days días',
};
