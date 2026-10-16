import 'dart:math' as math;

import '../../data/models/member.dart';
import '../../data/models/pantry_item.dart';
import '../../domain/energy_requirement.dart';
import '../../domain/exclusion_list.dart';
import '../../domain/meal_plan_length.dart';
import '../../domain/models/child_profile.dart';
import '../../domain/models/recipe_request.dart';
import '../../domain/portion_adjuster.dart';
import '../formatting.dart';
import 'expiration_urgency.dart';

export '../../domain/exclusion_list.dart';

// Las recetas siguen siendo un catálogo de ejemplo (aún no hay colección en
// Firestore), pero se comparan con la despensa real, se ajustan a la edad y el
// peso de los integrantes y se revisan contra las alergias de la familia. El
// plan de comidas se arma con esas recetas y lo que caduca primero en la
// despensa.

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
    this.id = '',
    required this.name,
    required this.image,
    required this.minutes,
    required this.servings,
    required this.kcalPerServing,
    required this.ingredients,
    required this.steps,
    this.requiredEquipment = const [],
  });

  /// Id del documento recipes/{id}. Las de SampleData llevan el de
  /// tool/catalog_recipes.mjs; vacío si la receta no tiene uno.
  final String id;
  final String name;
  final String image;
  final int minutes;
  final int servings;
  final int kcalPerServing;
  final List<RecipeIngredient> ingredients;
  final List<String> steps;

  /// Ids de Appliance que pide la receta (recipes/{id}.requiredEquipment).
  /// Vacía si no necesita ninguno.
  final List<String> requiredEquipment;

  bool get isQuick => minutes <= 30;
}

class MealPlanEntry {
  const MealPlanEntry({
    required this.date,
    required this.day,
    required this.recipe,
    required this.reason,
    required this.urgency,
  });

  /// Día al que corresponde, sin hora. En un plan de 14 días distingue los
  /// dos "Lun".
  final DateTime date;

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
/// multiplica por portions / servings (portions es householdSize si no se
/// da) y se redondea a 3 decimales (las piezas, latas y paquetes se redondean
/// hacia arriba). Si no se conoce el tamaño del hogar (0) o ya coincide con
/// las porciones, regresa la misma receta.
Recipe scaledRecipe(Recipe recipe, int householdSize, {double? portions}) {
  final target = portions ?? householdSize.toDouble();
  if (householdSize <= 0 ||
      recipe.servings <= 0 ||
      (householdSize == recipe.servings && target == recipe.servings)) {
    return recipe;
  }
  final factor = target / recipe.servings;
  return Recipe(
    id: recipe.id,
    requiredEquipment: recipe.requiredEquipment,
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

/// [recipe] ajustada a lo que come el hogar según la edad, el peso y la
/// salud de sus integrantes ([householdPortions]).
Recipe scaledForHousehold(Recipe recipe, List<Member> members) =>
    scaledRecipe(recipe, members.length, portions: householdPortions(members));

/// Porciones de adulto que come el hogar: cada adulto cuenta 1 (menos si
/// tiene obesidad, [EnergyRequirement.adultPortion]) y cada niño
/// según su edad y peso ([PortionAdjuster.childFactor]); con solo el peso se
/// usa su proporción del peso de un adulto. Un niño sin edad ni peso cuenta
/// 1, para no recortar comida sin datos.
double householdPortions(List<Member> members) {
  var portions = 0.0;
  for (final member in members) {
    portions += switch ((member.memberType, member.age, member.weightKg)) {
      (MemberType.adult, _, _) => EnergyRequirement.adultPortion(member),
      (_, final int age, final weight) => PortionAdjuster.childFactor(
        ChildProfile(age: age, weight: weight ?? 0),
      ),
      (_, null, final double weight) =>
        (weight / PortionAdjuster.adultWeightKg).clamp(0.2, 1.0),
      _ => 1.0,
    };
  }
  return portions;
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

/// Si el nombre de un ingrediente contiene el alérgeno: "Leche entera" y
/// "Quesos" llevan lácteos. Se compara palabra por palabra, así que
/// "Lechuga" no cuenta como leche ni "Panela" como pan.
bool containsAllergen(String ingredientName, Allergy allergy) =>
    _containsKeyword(ingredientName, allergenKeywords[allergy]);

bool _containsKeyword(String ingredientName, List<String>? keywords) {
  final normalized = [
    for (final keyword in keywords ?? const <String>[]) normalizeName(keyword),
  ];
  return normalizeName(ingredientName)
      .split(' ')
      .any((word) => normalized.any((keyword) => _sameWord(word, keyword)));
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

// ---------------------------------------------------------------------------
// Enfermedades crónicas de la familia.

/// Si el nombre de un ingrediente lleva algo que conviene evitar con
/// [condition]: "Sal de mesa" con hipertensión, pero no "Salsa verde".
bool containsRestricted(String ingredientName, ChronicCondition condition) =>
    _containsKeyword(ingredientName, conditionKeywords[condition]);

/// Una enfermedad crónica de la familia que choca con una receta: quiénes la
/// tienen y qué ingredientes conviene evitar.
typedef ConditionConflict = ({
  ChronicCondition condition,
  List<String> members,
  List<String> ingredients,
});

/// Enfermedades de [members] con las que choca [recipe], en el orden de
/// [ChronicCondition].
List<ConditionConflict> conditionConflicts(
  Recipe recipe,
  List<Member> members,
) {
  final conflicts = <ConditionConflict>[];
  for (final condition in ChronicCondition.values) {
    final affected = [
      for (final member in members)
        if (member.chronicConditions?.contains(condition) ?? false)
          member.name.trim(),
    ];
    if (affected.isEmpty) continue;
    final ingredients = [
      for (final ingredient in recipe.ingredients)
        if (containsRestricted(ingredient.name, condition)) ingredient.name,
    ];
    if (ingredients.isEmpty) continue;
    conflicts.add((
      condition: condition,
      members: affected,
      ingredients: ingredients,
    ));
  }
  return conflicts;
}

/// "Cuidado: esta receta lleva Sal y Jamón, que conviene evitar con
/// hipertensión (José)."
String conditionWarning(ConditionConflict conflict) {
  final (:condition, :members, :ingredients) = conflict;
  return 'Cuidado: esta receta lleva ${joinWithAnd(ingredients)}, que '
      'conviene evitar con '
      '${chronicConditionLabel(condition).toLowerCase()} '
      '(${joinWithAnd(members)}).';
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

/// Plan de [days] días que empieza hoy: 7 o 14, según la próxima entrega de
/// la familia (ver [MealPlanLength]).
///
/// Se arma un día a la vez. Cada día se ordenan las recetas contra la despensa
/// tal como estará en esa fecha: lo que ya caducó ese día no cuenta, los días
/// que quedan se cuentan desde la fecha de la tarjeta (no desde hoy) y ya no
/// está lo que se comieron los días anteriores del plan (ver [_PantryReplay]).
/// Van primero las recetas que usan lo que caduca antes; las que no usan nada
/// de la despensa van al final. Entre iguales va primero la que tiene menos
/// ingredientes faltantes y luego la que aparece antes en [recipes].
///
/// Cada receta sale una vez por ronda: cuando se acaban las recetas, empieza
/// otra ronda con todas, salvo la del día anterior, que no se repite dos días
/// seguidos. Si ese día nada de la despensa sirve (todo caducó o se acabó), se
/// elige la receta a la que le faltan menos ingredientes y el motivo solo dice
/// cuántos faltan, sin nombrar ningún producto.
List<MealPlanEntry> buildMealPlan(
  List<Recipe> recipes,
  List<PantryItem> pantry, {
  DateTime? today,
  int days = MealPlanLength.weekly,
}) {
  if (recipes.isEmpty) return const [];
  final now = today ?? DateTime.now();
  final replay = _PantryReplay(pantry);
  final plan = <MealPlanEntry>[];
  // Recetas que ya salieron en la ronda actual y la del día anterior.
  var served = <int>{};
  int? previous;

  for (var offset = 0; offset < days; offset++) {
    final date = DateTime(now.year, now.month, now.day + offset);
    if (served.length == recipes.length) served = {};
    final ranked = [
      for (var i = 0; i < recipes.length; i++)
        if (!served.contains(i) && (recipes.length == 1 || i != previous))
          _rankRecipe(recipes[i], i, replay.current, date),
    ]..sort(_compareRanked);

    final chosen = ranked.first;
    plan.add(_planEntry(chosen, date));
    served.add(chosen.index);
    previous = chosen.index;
    replay.cook(chosen.recipe, date);
  }
  return plan;
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
MealPlanEntry _planEntry(_RankedRecipe ranked, DateTime date) {
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
    date: date,
    day: _weekdays[date.weekday - 1],
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

// ---------------------------------------------------------------------------
// Receta a pedido.

/// Clave para no repetir una receta con "Otra receta": su id de Firestore o,
/// si no tiene, su nombre normalizado.
String recipeKey(Recipe recipe) =>
    recipe.id.isNotEmpty ? recipe.id : normalizeName(recipe.name);

/// Si al hogar le falta algún electrodoméstico que pide [recipe]. Con
/// [householdAppliances] vacía no se sabe qué tiene (appliances: [] también
/// es "no se capturó"), así que no se descarta ninguna.
bool lacksAppliance(Recipe recipe, List<String> householdAppliances) =>
    householdAppliances.isNotEmpty &&
    recipe.requiredEquipment.any((id) => !householdAppliances.contains(id));

/// [recipes] que se le pueden sugerir al hogar: sin alérgenos de ningún
/// integrante y sin electrodomésticos que no tiene. Las enfermedades crónicas
/// no descartan recetas; [pickRecipe] las deja al final.
List<Recipe> recipesForHousehold(
  List<Recipe> recipes, {
  required List<Member> members,
  List<String> householdAppliances = const [],
}) => [
  for (final recipe in recipes)
    if (_suitable(recipe, members, householdAppliances)) recipe,
];

// Una receta sin ingredientes (datos incompletos) no se sugiere.
bool _suitable(Recipe recipe, List<Member> members, List<String> appliances) =>
    recipe.ingredients.isNotEmpty &&
    !lacksAppliance(recipe, appliances) &&
    allergyConflicts(recipe, members).isEmpty;

/// Si [recipe] tiene el antojo: cada palabra escrita (menos "de", "con"...) en
/// su nombre o ingredientes, o un [product] que sirve para un ingrediente.
bool matchesCraving(Recipe recipe, String craving, {bool product = false}) {
  final wanted = normalizeName(craving);
  if (wanted.isEmpty) return true;
  if (!product) {
    final known = {
      ...normalizeName(recipe.name).split(' '),
      for (final ingredient in recipe.ingredients)
        ...normalizeName(ingredient.name).split(' '),
    };
    return [
      for (final word in wanted.split(' '))
        if (!_connectors.contains(word)) word,
    ].every((word) => known.any((other) => _sameWord(other, word)));
  }
  final words = wanted.split(' ');
  if (_containsWords(normalizeName(recipe.name), words)) return true;
  return recipe.ingredients.any((ingredient) {
    final name = normalizeName(ingredient.name);
    return _namesMatch(name, wanted) || _containsWords(name, words);
  });
}

/// Palabras que no cuentan en un antojo escrito ("arroz con pollo").
final _connectors = 'de del con y e a al la el los las en para sin un una'
    .split(' ')
    .toSet();

/// Si [words] van seguidas en [text] (ya normalizado), palabra por palabra.
bool _containsWords(String text, List<String> words) {
  if (text.isEmpty) return false;
  final haystack = text.split(' ');
  for (var start = 0; start + words.length <= haystack.length; start++) {
    var found = true;
    for (var i = 0; i < words.length && found; i++) {
      found = _sameWord(haystack[start + i], words[i]);
    }
    if (found) return true;
  }
  return false;
}

/// Productos de la despensa que se pueden pedir como antojo: los que no han
/// caducado y usa al menos una de [recipes]. Van del que caduca antes al que
/// caduca después (como el plan), un solo nombre por producto aunque esté en
/// varias entregas.
List<String> cravingOptions(
  List<Recipe> recipes,
  List<PantryItem> pantry, {
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  int days(PantryItem item) => daysLeft(item, today: now);
  bool used(PantryItem item) => recipes.any(
    (recipe) => recipe.ingredients.any(
      (ingredient) => ingredientMatches(ingredient, item),
    ),
  );

  final items = [
    for (final item in pantry)
      if (item.quantity > 0 && days(item) >= 0 && used(item)) item,
  ];
  items.sort((a, b) {
    final byDays = days(a).compareTo(days(b));
    return byDays != 0
        ? byDays
        : normalizeName(a.productId).compareTo(normalizeName(b.productId));
  });
  final seen = <String>{};
  return [
    for (final item in items)
      if (seen.add(normalizeName(item.productId)))
        productDisplayName(item.productId),
  ];
}

/// La receta que se sugiere al pedir una (ver [pickRecipe]).
class RecipeSuggestion {
  const RecipeSuggestion({
    required this.recipe,
    required this.scaled,
    required this.missing,
    required this.reason,
    required this.urgency,
    required this.usesPantry,
    required this.fitsTime,
    required this.matchesCraving,
    required this.avoidsConditions,
  });

  /// La receta del catálogo, sin ajustar. Es la que recibe openRecipe
  /// (recipe_detail_screen.dart): el detalle ajusta las porciones y, si
  /// recibiera [scaled], las ajustaría dos veces.
  final Recipe recipe;

  /// [recipe] con las porciones del hogar: la que se muestra y con la que se
  /// cuentan los faltantes.
  final Recipe scaled;

  /// Ingredientes de [scaled] que no alcanzan con la despensa.
  final int missing;

  /// Como en el plan: "Usa Jitomate (caduca en 5 días)", "Te falta 1
  /// ingrediente" o "Con productos de tu despensa".
  final String reason;
  final ExpirationUrgency urgency;

  /// Si usa algo de la despensa; si no, [urgency] no dice nada.
  final bool usesPantry;

  /// Si cabe en el tiempo pedido (siempre, sin límite de tiempo).
  final bool fitsTime;

  /// Si tiene el antojo pedido (siempre, sin antojo).
  final bool matchesCraving;

  /// Si no lleva nada que convenga evitar por una enfermedad de la familia.
  final bool avoidsConditions;

  /// Si se puede preparar con lo que hay en la despensa.
  bool get fitsPantry => missing == 0;
}

typedef _Candidate = ({
  Recipe recipe,
  _RankedRecipe ranked,
  bool avoidsConditions,
  bool fitsTime,
  bool matchesCraving,
  int minutesOver,
});

/// La receta de [recipes] (del catálogo, sin ajustar) que mejor cumple
/// [request], o null si ya no queda ninguna para el hogar.
RecipeSuggestion? pickRecipe(
  List<Recipe> recipes,
  List<PantryItem> pantry, {
  required List<Member> members,
  List<String> householdAppliances = const [],
  RecipeRequest request = const RecipeRequest(),
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final craving = request.cravingText;
  _Candidate? best;
  for (var i = 0; i < recipes.length; i++) {
    final recipe = recipes[i];
    if (request.excludeRecipeIds.contains(recipeKey(recipe)) ||
        !_suitable(recipe, members, householdAppliances)) {
      continue;
    }
    final candidate = (
      recipe: recipe,
      ranked: _rankRecipe(scaledForHousehold(recipe, members), i, pantry, now),
      avoidsConditions: conditionConflicts(recipe, members).isEmpty,
      fitsTime: request.fitsTime(recipe.minutes),
      matchesCraving:
          craving == null ||
          matchesCraving(recipe, craving, product: request.cravingIsProduct),
      minutesOver: request.minutesOver(recipe.minutes),
    );
    if (best == null || _compareCandidates(candidate, best) < 0) {
      best = candidate;
    }
  }
  if (best == null) return null;

  final entry = _planEntry(best.ranked, DateTime(now.year, now.month, now.day));
  return RecipeSuggestion(
    recipe: best.recipe,
    scaled: best.ranked.recipe,
    missing: best.ranked.missing,
    reason: entry.reason,
    urgency: entry.urgency,
    usesPantry: best.ranked.mostUrgent != null,
    fitsTime: best.fitsTime,
    matchesCraving: best.matchesCraving,
    avoidsConditions: best.avoidsConditions,
  );
}

// Antes lo que evita enfermedades y alcanza con la despensa (o le falta
// menos); luego el tiempo, el antojo, los minutos de más y el plan.
int _compareCandidates(_Candidate a, _Candidate b) {
  if (a.avoidsConditions != b.avoidsConditions) {
    return a.avoidsConditions ? -1 : 1;
  }
  final byMissing = a.ranked.missing.compareTo(b.ranked.missing);
  if (byMissing != 0) return byMissing;
  if (a.fitsTime != b.fitsTime) return a.fitsTime ? -1 : 1;
  if (a.matchesCraving != b.matchesCraving) return a.matchesCraving ? -1 : 1;
  // Si ninguna cabe, la que no dice cuánto tarda va después.
  final (aKnown, bKnown) = (a.recipe.minutes > 0, b.recipe.minutes > 0);
  if (!a.fitsTime && aKnown != bKnown) return aKnown ? -1 : 1;
  final byOver = a.minutesOver.compareTo(b.minutesOver);
  return byOver != 0 ? byOver : _compareRanked(a.ranked, b.ranked);
}

// ---------------------------------------------------------------------------
// Lo que sobra después del plan.

/// Qué pasa con un producto de la despensa si se cocina todo el plan.
enum LeftoverStatus {
  /// Ninguna receta del plan lo usa.
  untouched,

  /// El plan usa una parte y todavía queda algo.
  partlyUsed,

  /// El plan se lo come completo.
  usedUp,
}

/// Un producto de la despensa y lo que el plan hace con él.
class PlanLeftover {
  const PlanLeftover({
    required this.item,
    required this.used,
    required this.remaining,
  });

  final PantryItem item;

  /// Lo que usa el plan, en la unidad del producto. Nunca pasa de lo que hay.
  final double used;

  /// Lo que queda después del plan, en la unidad del producto. Nunca es
  /// negativo.
  final double remaining;

  LeftoverStatus get status {
    if (remaining <= _epsilon) return LeftoverStatus.usedUp;
    return used <= _epsilon
        ? LeftoverStatus.untouched
        : LeftoverStatus.partlyUsed;
  }
}

/// Qué queda de cada producto de la despensa después de cocinar las recetas de
/// [plan] en orden. Los productos que ya caducaron hoy o no tienen cantidad no
/// cuentan (como en [planConsumption]); los demás van del que caduca primero al
/// que caduca después.
///
/// Es la misma repetición día por día con la que [buildMealPlan] arma el plan
/// ([_PantryReplay]): cada receta se cocina en la fecha de su tarjeta, así que
/// no usa un producto que ya caducó ese día, y lo que usan los días anteriores
/// ya no está. Una receta repetida usa lo que quede cuando le toca y, cuando un
/// ingrediente se acaba, los días siguientes ya no lo usan. Por eso la cantidad
/// que sobra nunca es negativa, aunque dos días pidan más de lo que hay. Un
/// producto que caduca a media semana sigue en la lista con lo que no alcanzó a
/// usarse antes de caducar.
List<PlanLeftover> planLeftovers(
  List<MealPlanEntry> plan,
  List<PantryItem> pantry, {
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final replay = _PantryReplay(pantry);
  for (final entry in plan) {
    replay.cook(entry.recipe, entry.date);
  }

  return [
    for (var i = 0; i < replay.original.length; i++)
      if (daysLeft(replay.original[i], today: now) >= 0)
        PlanLeftover(
          item: replay.original[i],
          used: _round3(
            math.max(0.0, replay.original[i].quantity - replay.remaining[i]),
          ),
          remaining: replay.remaining[i],
        ),
  ]..sort((a, b) {
    final byDays = daysLeft(
      a.item,
      today: now,
    ).compareTo(daysLeft(b.item, today: now));
    if (byDays != 0) return byDays;
    final byName = normalizeName(productDisplayName(a.item.productId))
        .compareTo(normalizeName(productDisplayName(b.item.productId)));
    return byName != 0
        ? byName
        : a.item.pantryItemId.compareTo(b.item.pantryItemId);
  });
}

/// La despensa mientras se cocina el plan día por día. La comparten
/// [buildMealPlan] (para elegir cada día contra lo que queda), el plan
/// guardado ([planEntryFor]) y [planLeftovers] (para contar lo que sobra), de
/// modo que las cuentas no pueden separarse.
class _PantryReplay {
  _PantryReplay(List<PantryItem> pantry)
    : original = [
        for (final item in pantry)
          if (item.quantity > 0) item,
      ] {
    remaining = [for (final item in original) item.quantity];
    current = List<PantryItem>.of(original);
    for (var i = 0; i < current.length; i++) {
      _positions[current[i]] = i;
    }
  }

  /// Los productos con cantidad, tal como llegaron.
  final List<PantryItem> original;

  /// Lo que queda de cada uno de [original], en su unidad. Nunca es negativo.
  late final List<double> remaining;

  /// Los mismos productos con lo que va quedando: es lo que ve
  /// [planConsumption]. Los caducados siguen aquí, pero no sirven en ninguna
  /// fecha posterior a su caducidad.
  late final List<PantryItem> current;

  final _positions = Map<PantryItem, int>.identity();

  /// Cocina [recipe] el día [date]: descuenta lo que [planConsumption] usaría
  /// ese día de lo que queda.
  void cook(Recipe recipe, DateTime date) {
    for (final (:item, :amount) in planConsumption(
      recipe,
      current,
      today: date,
    )) {
      final i = _positions[item]!;
      remaining[i] = _round3(math.max(0.0, remaining[i] - amount));
      current[i] = _withQuantity(original[i], remaining[i]);
      _positions[current[i]] = i;
    }
  }
}

PantryItem _withQuantity(PantryItem item, double quantity) => PantryItem(
  pantryItemId: item.pantryItemId,
  productId: item.productId,
  deliveryId: item.deliveryId,
  type: item.type,
  quantity: quantity,
  unit: item.unit,
  daysUntilExpiration: item.daysUntilExpiration,
  deviceId: item.deviceId,
  localTimestamp: item.localTimestamp,
);

// ---------------------------------------------------------------------------
// Plan guardado.

/// La tarjeta de [recipe] el día [date] de un plan guardado, como en
/// [buildMealPlan]: con la despensa de esa fecha, sin lo que usa [earlier].
MealPlanEntry planEntryFor(
  Recipe recipe,
  DateTime date,
  List<PantryItem> pantry, {
  List<MealPlanEntry> earlier = const [],
}) {
  final day = DateTime(date.year, date.month, date.day);
  final left = _pantryAfter(earlier, pantry, day);
  return _planEntry(_rankRecipe(recipe, 0, left, day), day);
}

/// Abreviatura del día de [date], como en las tarjetas del plan ("Mié").
String planDayLabel(DateTime date) => _weekdays[date.weekday - 1];

/// [recipes] para elegir la de [date] en un plan guardado, en el orden en que
/// [buildMealPlan] las ve ese día (ver [planEntryFor]).
List<MealPlanEntry> planOptionsFor(
  List<Recipe> recipes,
  List<PantryItem> pantry,
  DateTime date, {
  List<MealPlanEntry> earlier = const [],
}) {
  final day = DateTime(date.year, date.month, date.day);
  final left = _pantryAfter(earlier, pantry, day);
  final ranked = [
    for (var i = 0; i < recipes.length; i++)
      _rankRecipe(recipes[i], i, left, day),
  ]..sort(_compareRanked);
  return [for (final recipe in ranked) _planEntry(recipe, day)];
}

/// [pantry] después de cocinar en orden las tarjetas de [earlier] de antes de
/// [day] ([_PantryReplay]). Los días libres no tienen tarjeta.
List<PantryItem> _pantryAfter(
  List<MealPlanEntry> earlier,
  List<PantryItem> pantry,
  DateTime day,
) {
  final replay = _PantryReplay(pantry);
  for (final entry in earlier) {
    if (entry.date.isBefore(day)) replay.cook(entry.recipe, entry.date);
  }
  return replay.current;
}
