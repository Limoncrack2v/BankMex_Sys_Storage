import '../data/models/member.dart';
import 'allergen_filter.dart';
import 'exclusion_list.dart';
import 'firestore_codec.dart';
import 'models/family_profile.dart';
import 'models/recipe.dart';
import 'portion_adjuster.dart';

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

  /// Máximo del motivo y de cada nombre (firestore.rules: validAdjustment).
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
  /// alérgeno del hogar. Los nombres de los candidatos no llevan palabras de
  /// [allergenKeywords] salvo las suyas ("Fideo de arroz", no "Pasta de
  /// arroz"), porque esa regla compara por palabras.
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
      (['pasta'], ['Fideo de arroz', 'Arroz']),
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
    FamilyProfile family,
  ) {
    final allergies = AllergenFilter.allergiesOf(family);
    final householdSize = family.adults + family.children.length;
    if (householdSize <= 0) return null;

    final base = recipe.servings > 0
        ? recipe.servings
        : kRecipeBaseServings.round();
    final servings = PortionAdjuster.familyServingFactor(family)
        .round()
        .clamp(1, 99);
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
    if (changes.isEmpty) return null;

    return RecipeAdjustmentSuggestion(
      recipeId: recipe.id,
      baseSignature: recipeSignature(recipe),
      householdSize: householdSize,
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
