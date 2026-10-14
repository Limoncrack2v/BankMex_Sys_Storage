import '../../data/models/member.dart';
import '../../domain/catalog_mappers.dart';
import '../../domain/models/recipe_adjustment.dart';
import 'recipe.dart';

/// El tamaño del hogar que usa el motor de ajuste (adultos más niños; uno si
/// aún no hay integrantes), para comparar con el de una adaptación.
int householdSizeOf(List<Member> members) =>
    members.isEmpty ? 1 : members.length;

/// Las recetas de [recipes] con su adaptación si ya está aprobada: la que el
/// nutriólogo aprobó para esa receta, para un hogar de [householdSize] y para
/// esta versión de la receta. Las demás quedan como están, que es lo que ve la
/// familia mientras la sugerencia espera al nutriólogo, si la rechazó, o si la
/// receta se editó o el hogar cambió después.
List<Recipe> applyAdjustments(
  List<Recipe> recipes,
  List<RecipeAdjustment> adjustments, {
  required int householdSize,
}) {
  if (adjustments.isEmpty) return recipes;
  return [
    for (final recipe in recipes)
      _adapted(recipe, adjustments, householdSize) ?? recipe,
  ];
}

Recipe? _adapted(
  Recipe recipe,
  List<RecipeAdjustment> adjustments,
  int householdSize,
) {
  if (recipe.id.isEmpty || recipe.signature.isEmpty) return null;
  for (final adjustment in adjustments) {
    if (adjustment.status != AdjustmentStatus.approved ||
        adjustment.recipeId != recipe.id ||
        adjustment.baseSignature != recipe.signature ||
        adjustment.householdSize != householdSize) {
      continue;
    }
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
