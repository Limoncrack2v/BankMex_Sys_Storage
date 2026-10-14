import '../../data/models/member.dart';
import '../../domain/catalog_mappers.dart';
import '../../domain/models/recipe_adjustment.dart';
import '../../domain/recipe_adjustment.dart';
import 'recipe.dart';

/// La clave del hogar de [members] (tamaño y alergias; ver [householdKeyOf]),
/// la misma que le sale al motor de ajuste para ese hogar.
String householdKeyForMembers(List<Member> members) => householdKeyOf(
  members.isEmpty ? 1 : members.length,
  {for (final member in members) ...?member.allergies},
);

/// Las recetas de [recipes] con su adaptación si ya está aprobada: la que el
/// nutriólogo aprobó para esa receta, para esta versión de la receta y para el
/// hogar de [members] (mismo tamaño y mismas alergias). Las demás quedan como
/// están, que es lo que ve la familia mientras la sugerencia espera al
/// nutriólogo, si la rechazó, o si la receta o el hogar cambiaron después.
///
/// Una adaptación que lleve un ingrediente al que alguien del hogar es
/// alérgico no se aplica nunca, aunque esté aprobada: se queda la receta base,
/// que el plan y las sugerencias dejan fuera.
List<Recipe> applyAdjustments(
  List<Recipe> recipes,
  List<RecipeAdjustment> adjustments, {
  required List<Member> members,
}) {
  if (adjustments.isEmpty) return recipes;
  final key = householdKeyForMembers(members);
  final allergies = {for (final member in members) ...?member.allergies};
  return [
    for (final recipe in recipes)
      _adapted(recipe, adjustments, key, allergies) ?? recipe,
  ];
}

Recipe? _adapted(
  Recipe recipe,
  List<RecipeAdjustment> adjustments,
  String householdKey,
  Set<Allergy> allergies,
) {
  if (recipe.id.isEmpty || recipe.signature.isEmpty) return null;
  for (final adjustment in adjustments) {
    if (adjustment.status != AdjustmentStatus.approved ||
        adjustment.recipeId != recipe.id ||
        adjustment.baseSignature != recipe.signature ||
        adjustment.householdKey != householdKey) {
      continue;
    }
    final hasAllergen = adjustment.ingredients.any(
      (ingredient) => allergies.any(
        (allergy) => containsAllergen(ingredient.productName, allergy),
      ),
    );
    if (hasAllergen) continue;
    return Recipe(
      id: recipe.id,
      signature: recipe.signature,
      adaptation: adjustment.summary,
      name: recipe.name,
      image: recipe.image,
      minutes: recipe.minutes,
      servings: adjustment.servings,
      kcalPerServing: recipe.kcalPerServing,
      ingredients: [
        for (final ingredient in adjustment.ingredients)
          RecipeIngredient(
            ingredient.productName,
            ingredient.quantity,
            CatalogMappers.foodUnit(ingredient.unit),
          ),
      ],
      steps: recipe.steps,
    );
  }
  return null;
}
