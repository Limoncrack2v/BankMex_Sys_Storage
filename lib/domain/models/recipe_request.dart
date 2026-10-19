/// Lo que pide la familia en "Pedir una receta": qué se le antoja, cuánto
/// tiempo tiene y qué recetas ya vio. Todo es opcional; sin nada es "la
/// receta que mejor usa lo que tengo".
///
/// Vive en el dominio para que lo reciban igual el motor de reglas de la UI
/// (pickRecipe en lib/ui/models/recipe.dart) y, más adelante, un
/// RecipePlanner con IA. No lleva datos de salud: lo que el hogar debe evitar
/// sale de sus integrantes ([NutritionTargets.exclusionList]).
class RecipeRequest {
  const RecipeRequest({
    this.craving,
    this.cravingIsProduct = false,
    this.maxPrepMinutes,
  }) : excludeRecipeIds = const <String>{},
       assert(maxPrepMinutes == null || maxPrepMinutes > 0);

  /// La búsqueda con [excludeRecipeIds] ya vistas. Guarda una copia que no se
  /// puede cambiar.
  RecipeRequest.excludingAll(
    Iterable<String> excludeRecipeIds, {
    this.craving,
    this.cravingIsProduct = false,
    this.maxPrepMinutes,
  }) : excludeRecipeIds = Set.unmodifiable(excludeRecipeIds),
       assert(maxPrepMinutes == null || maxPrepMinutes > 0);

  /// Lo que se le antoja, en texto libre: un producto ("Atún en lata") o un
  /// platillo ("sopa"). null o en blanco = lo que sea.
  final String? craving;

  /// Si [craving] viene de una opción (un producto de la despensa).
  final bool cravingIsProduct;

  /// Minutos que tiene para cocinar; null = sin prisa. Se compara con el
  /// tiempo de la receta (prepTimeMinutes en Firestore, minutes en la UI).
  final int? maxPrepMinutes;

  /// Recetas que ya se mostraron con "Otra receta" y no deben repetirse: el
  /// id del catálogo (o la clave que use quien llama si no hay id).
  final Set<String> excludeRecipeIds;

  /// El antojo sin espacios de más; null si no hay.
  String? get cravingText {
    final text = craving?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  /// Una receta sin tiempo (0 o menos) no cabe en ningún límite.
  bool fitsTime(int minutes) {
    final max = maxPrepMinutes;
    return max == null || (minutes > 0 && minutes <= max);
  }

  /// Minutos que [minutes] se pasa del tiempo pedido (0 si cabe).
  int minutesOver(int minutes) {
    final max = maxPrepMinutes;
    return max == null || minutes <= max ? 0 : minutes - max;
  }

  /// La misma búsqueda con [recipeId] ya vista ("Otra receta").
  RecipeRequest excluding(String recipeId) => RecipeRequest.excludingAll(
    [...excludeRecipeIds, recipeId],
    craving: craving,
    cravingIsProduct: cravingIsProduct,
    maxPrepMinutes: maxPrepMinutes,
  );

  /// La misma búsqueda sin recetas vistas ("Volver a empezar").
  RecipeRequest restarted() => RecipeRequest(
    craving: craving,
    cravingIsProduct: cravingIsProduct,
    maxPrepMinutes: maxPrepMinutes,
  );

  /// Para un planner detrás de una Cloud Function. Los ids van ordenados
  /// para que la misma petición dé el mismo JSON.
  Map<String, Object?> toJson() => {
    'craving': cravingText,
    'cravingIsProduct': cravingIsProduct,
    'maxPrepMinutes': maxPrepMinutes,
    'excludeRecipeIds': excludeRecipeIds.toList()..sort(),
  };

  @override
  bool operator ==(Object other) =>
      other is RecipeRequest &&
      other.cravingText == cravingText &&
      other.cravingIsProduct == cravingIsProduct &&
      other.maxPrepMinutes == maxPrepMinutes &&
      other.excludeRecipeIds.length == excludeRecipeIds.length &&
      other.excludeRecipeIds.containsAll(excludeRecipeIds);

  @override
  int get hashCode => Object.hash(
    cravingText,
    cravingIsProduct,
    maxPrepMinutes,
    Object.hashAllUnordered(excludeRecipeIds),
  );
}
