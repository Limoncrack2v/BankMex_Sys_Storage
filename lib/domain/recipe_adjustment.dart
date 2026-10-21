import '../data/models/member.dart';
import 'allergen_filter.dart';
import 'exclusion_list.dart';
import 'firestore_codec.dart';
import 'models/family_profile.dart';
import 'models/recipe.dart';
import 'portion_adjuster.dart';

/// La clave del hogar de una adaptación: cuántos son y a qué alérgenos hay
/// alergia, en orden alfabético y sin repetir: "4", "4-dairy", "4-dairy-gluten".
/// Dos hogares con la misma clave piden la misma adaptación; si cambian las
/// alergias (aunque no el tamaño) cambia la clave y la adaptación anterior ya
/// no sirve. firestore.rules valida este formato (validAdjustment).
String householdKeyOf(int householdSize, Iterable<Allergy> allergies) {
  final names = {for (final allergy in allergies) allergy.name}.toList()
    ..sort();
  return [householdSize, ...names].join('-');
}

/// Las alergias de una clave de [householdKeyOf], en su orden: "4-dairy-egg"
/// da lácteos y huevo. El primer pedazo es el tamaño del hogar; lo que no sea
/// una alergia conocida se ignora.
List<Allergy> allergiesOfHouseholdKey(String key) {
  final byName = Allergy.values.asNameMap();
  return [for (final part in key.split('-').skip(1)) ?byName[part]];
}

/// Un cambio sugerido a una receta, con el motivo que ve el nutriólogo.
class AdjustmentChange {
  const AdjustmentChange({
    required this.kind,
    required this.reason,
    this.from,
    this.to,
  });

  /// [kindPortions] o [kindSubstitution].
  final String kind;
  static const kindPortions = 'portions';
  static const kindSubstitution = 'substitution';

  /// Por qué se sugiere, p. ej. "alergia a lácteos".
  final String reason;

  /// En una sustitución, el ingrediente de la receta y el que lo reemplaza.
  final String? from;
  final String? to;

  /// Máximos de firestore.rules (validAdjustment): las reglas revisan cada
  /// cambio por su índice y tienen un tope de expresiones, así que una
  /// sugerencia con más cambios no se puede guardar.
  static const int maxPerSuggestion = 6;
  static const int maxTextLength = 200;
  static const int maxNameLength = 100;

  factory AdjustmentChange.fromMap(Map<String, dynamic> map) {
    return AdjustmentChange(
      kind: map['kind'] as String? ?? kindPortions,
      reason: map['reason'] as String? ?? '',
      from: map['from'] as String?,
      to: map['to'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'kind': kind,
    'reason': reason,
    if (from != null) 'from': from,
    if (to != null) 'to': to,
  };
}

/// Lo que el motor sugiere para una receta y un hogar. No lleva nombres, edades
/// ni pesos de los integrantes (MASVS-PRIVACY-1): solo el tamaño del hogar y el
/// motivo de cada cambio, y no se aplica hasta que lo aprueba el nutriólogo.
class RecipeAdjustmentSuggestion {
  const RecipeAdjustmentSuggestion({
    required this.recipeId,
    required this.baseSignature,
    required this.householdSize,
    required this.householdKey,
    required this.servings,
    required this.ingredients,
    required this.changes,
    required this.summary,
  });

  final String recipeId;

  /// Huella del contenido de la receta cuando se hizo la sugerencia (ver
  /// [recipeSignature]): si después se edita la receta, ya no coincide.
  final String baseSignature;
  final int householdSize;

  /// [householdKeyOf] del hogar: tamaño y alergias con los que se sugirió.
  final String householdKey;

  /// Porciones de la receta ya ajustada y sus ingredientes, ya escalados y con
  /// las sustituciones.
  final int servings;
  final List<RecipeIngredient> ingredients;
  final List<AdjustmentChange> changes;

  /// Una línea de qué cambió y por qué.
  final String summary;
}

/// Huella del contenido de una receta (nombre, porciones, ingredientes y
/// pasos): cambia si alguien la edita. Es para detectar ediciones, no para
/// seguridad.
String recipeSignature(Recipe recipe) {
  final buffer = StringBuffer()
    ..write(recipe.name)
    ..write('|${recipe.servings}')
    ..write('|${recipe.prepTimeMinutes}|${recipe.caloriesPerServing}');
  for (final ingredient in recipe.ingredients) {
    buffer.write(
      '|${ingredient.productName},${ingredient.quantity},${ingredient.unit}',
    );
  }
  for (final step in recipe.steps) {
    buffer.write('|$step');
  }
  // FNV-1a de 32 bits.
  var hash = 0x811c9dc5;
  for (final unit in buffer.toString().codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Lo único que un motor de ajuste recibe de un hogar: cuántos son, cuántas
/// porciones de adulto equivalen y a qué alérgenos hay alergia. No lleva
/// nombres, edades ni pesos de los integrantes (MASVS-PRIVACY-1): quien lo
/// construye ([AdjustmentContext.forHousehold], en el dispositivo) los usa
/// para calcular las porciones y no los suelta. Un motor remoto futuro
/// recibiría solo esto, igual que [NutritionTargets] recibe el objetivo
/// calórico y la lista de exclusión.
class AdjustmentContext {
  const AdjustmentContext({
    required this.householdSize,
    required this.portions,
    required this.allergies,
  });

  /// Integrantes del hogar (adultos y niños).
  final int householdSize;

  /// Porciones de adulto que come el hogar (los niños cuentan menos según su
  /// edad y peso).
  final double portions;

  final List<Allergy> allergies;

  String get householdKey => householdKeyOf(householdSize, allergies);

  factory AdjustmentContext.forHousehold(FamilyProfile family) =>
      AdjustmentContext(
        householdSize: family.adults + family.children.length,
        portions: PortionAdjuster.familyServingFactor(family),
        allergies: AllergenFilter.allergiesOf(family),
      );
}

/// El algoritmo por reglas. Una IA lo puede reemplazar detrás de
/// [RecipePlanner.suggestAdjustment] sin cambiar a quien lo usa.
class RecipeAdjustmentRules {
  /// Cómo se llama cada alergia en el motivo de un cambio.
  static const _allergyNames = {
    Allergy.dairy: 'lácteos',
    Allergy.gluten: 'gluten',
    Allergy.peanut: 'cacahuate',
    Allergy.shellfish: 'mariscos',
    Allergy.egg: 'huevo',
    Allergy.soy: 'soya',
  };

  /// Por qué se sustituye cada ingrediente (palabra que lo delata) y con qué:
  /// los candidatos van en orden y se toma el primero que no lleva ningún
  /// alérgeno del hogar. Los nombres de los candidatos no deben llevar palabras
  /// de [allergenKeywords] (el gluten tiene "pasta" y "fideo", así que el
  /// sustituto de la pasta es "Arroz"), porque esa regla compara por palabras y
  /// el candidato se descartaría solo.
  static const _substitutes = <Allergy, List<(List<String>, List<String>)>>{
    Allergy.dairy: [
      (['leche'], ['Bebida de avena', 'Bebida de arroz']),
      (['queso'], ['Tofu', 'Frijol machacado']),
      (['yogurt', 'yogur'], ['Plátano machacado']),
      (['crema'], ['Crema de coco']),
      (['mantequilla'], ['Aceite vegetal']),
    ],
    Allergy.gluten: [
      (['pan'], ['Tortilla de maíz']),
      (['pasta'], ['Arroz']),
      (['harina'], ['Masa de maíz', 'Harina de arroz']),
      (['galleta'], ['Totopos']),
      (['cereal'], ['Hojuelas de maíz']),
      (['trigo'], ['Arroz']),
      (['avena'], ['Amaranto']),
    ],
    Allergy.peanut: [
      (['cacahuate', 'mani'], ['Semilla de girasol']),
    ],
    Allergy.shellfish: [
      (
        ['camaron', 'marisco', 'pulpo', 'calamar', 'ostion', 'jaiba'],
        ['Atún', 'Pollo'],
      ),
    ],
    Allergy.egg: [
      (['huevo'], ['Tofu', 'Frijol machacado']),
    ],
    Allergy.soy: [
      (['soya', 'soja', 'tofu'], ['Frijol', 'Lenteja']),
    ],
  };

  /// Los cambios sugeridos a [recipe] para [family], o null si no hay ninguno
  /// o si algún ingrediente con alérgeno no tiene sustituto seguro (la receta
  /// no se puede adaptar y el plan la deja fuera).
  static RecipeAdjustmentSuggestion? suggest(
    Recipe recipe,
    AdjustmentContext household,
  ) {
    final allergies = household.allergies;
    final householdSize = household.householdSize;
    if (householdSize <= 0) return null;

    final base = recipe.servings > 0
        ? recipe.servings
        : kRecipeBaseServings.round();
    final servings = household.portions.round().clamp(1, 99);
    final scale = servings / base;

    final changes = <AdjustmentChange>[];
    final ingredients = <RecipeIngredient>[];
    for (final ingredient in recipe.ingredients) {
      final scaled = ingredient.copyWith(
        quantity: roundQuantity(ingredient.quantity * scale),
      );
      final conflict = _firstConflict(ingredient.productName, allergies);
      if (conflict == null) {
        ingredients.add(scaled);
        continue;
      }
      final substitute = _substituteFor(
        ingredient.productName,
        conflict,
        allergies,
      );
      if (substitute == null) return null;
      ingredients.add(scaled.copyWith(productName: substitute));
      changes.add(
        AdjustmentChange(
          kind: AdjustmentChange.kindSubstitution,
          reason: 'alergia a ${_allergyNames[conflict]}',
          from: ingredient.productName,
          to: substitute,
        ),
      );
    }
    if (servings != base) {
      changes.insert(
        0,
        AdjustmentChange(
          kind: AdjustmentChange.kindPortions,
          reason:
              'tu hogar es de $householdSize integrantes; la receta rinde '
              '$base porciones',
        ),
      );
    }
    if (changes.isEmpty || changes.length > AdjustmentChange.maxPerSuggestion) {
      return null;
    }

    return RecipeAdjustmentSuggestion(
      recipeId: recipe.id,
      baseSignature: recipeSignature(recipe),
      householdSize: householdSize,
      householdKey: household.householdKey,
      servings: servings,
      ingredients: ingredients,
      changes: changes,
      summary: _summary(changes, servings, householdSize),
    );
  }

  static Allergy? _firstConflict(String name, List<Allergy> allergies) {
    for (final allergy in allergies) {
      if (containsAllergen(name, allergy)) return allergy;
    }
    return null;
  }

  static String? _substituteFor(
    String name,
    Allergy allergy,
    List<Allergy> allergies,
  ) {
    final rules =
        _substitutes[allergy] ?? const <(List<String>, List<String>)>[];
    for (final (words, candidates) in rules) {
      if (!nameMentionsAny(name, words)) continue;
      for (final candidate in candidates) {
        if (_firstConflict(candidate, allergies) == null) return candidate;
      }
    }
    return null;
  }

  /// "Porciones ajustadas a 4 para tu hogar de 4 integrantes; se sustituye
  /// leche entera por bebida de avena por alergia a lácteos". "Se sustituye"
  /// y no "sustituida": el género del ingrediente cambia la palabra.
  static String _summary(
    List<AdjustmentChange> changes,
    int servings,
    int householdSize,
  ) {
    final parts = [
      for (final change in changes)
        if (change.kind == AdjustmentChange.kindPortions)
          'Porciones ajustadas a $servings para tu hogar de $householdSize '
              'integrantes'
        else
          'se sustituye ${change.from!.toLowerCase()} por '
              '${change.to!.toLowerCase()} por ${change.reason}',
    ];
    final text = parts.join('; ');
    return text.length > 300 ? '${text.substring(0, 297)}...' : text;
  }
}
