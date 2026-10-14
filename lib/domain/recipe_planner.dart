import 'meal_plan_generator.dart';
import 'models/family_profile.dart';
import 'models/pantry_item.dart';
import 'models/recipe.dart';
import 'recipe_adjustment.dart';
import 'recipe_on_demand.dart';

/// Elige recetas para una familia con lo que hay en su despensa.
///
/// Hoy lo implementa [RuleBasedRecipePlanner]. Una versión con IA (detrás de
/// una Cloud Function) podrá implementarlo después sin cambiar a quien lo
/// usa; por eso los métodos regresan Future aunque las reglas no esperen nada.
abstract interface class RecipePlanner {
  /// Una receta para cocinar ahora, o null si ninguna alcanza.
  ///
  /// Regresa la receta como está en [recipes], sin ajustar a la familia: quien
  /// la muestra o la descuenta de la despensa la escala (igual que con
  /// [planDays], que solo da el id y las porciones).
  Future<Recipe?> suggestRecipe({
    required FamilyProfile family,
    required List<PantryItem> pantryItems,
    required List<Recipe> recipes,
    DateTime? now,
  });

  /// A lo más una receta por día durante [days] días desde [startDate] (hoy
  /// si no se da). Un día sin receta que alcance se queda vacío, así que
  /// filledDays puede ser menor que requestedDays.
  Future<MealPlanGeneration> planDays({
    required FamilyProfile family,
    required List<PantryItem> pantryItems,
    required List<Recipe> recipes,
    required int days,
    DateTime? startDate,
    DateTime? now,
  });

  /// Los cambios que conviene hacerle a [recipe] (una receta aprobada) para el
  /// hogar descrito por [household]: porciones y sustitución de alérgenos, con
  /// el motivo de cada uno. Null si no hay nada que cambiar o si no se puede
  /// adaptar. Es solo una sugerencia: nada se aplica hasta que el nutriólogo
  /// la aprueba.
  ///
  /// Recibe [AdjustmentContext] y no el perfil de la familia: un motor remoto
  /// no recibe nombres, edades ni pesos de los integrantes.
  Future<RecipeAdjustmentSuggestion?> suggestAdjustment({
    required AdjustmentContext household,
    required Recipe recipe,
  });
}

/// Solo reglas, sin servicios externos: delega en [RecipeOnDemand] y
/// [MealPlanGenerator], así que los cambios al filtro, a las porciones o a
/// FIFO le llegan sin tocar esta clase.
class RuleBasedRecipePlanner implements RecipePlanner {
  const RuleBasedRecipePlanner();

  @override
  Future<Recipe?> suggestRecipe({
    required FamilyProfile family,
    required List<PantryItem> pantryItems,
    required List<Recipe> recipes,
    DateTime? now,
  }) async {
    final picked = RecipeOnDemand.getSingleRecipeOnDemand(
      family: family,
      pantryItems: pantryItems,
      recipes: recipes,
      now: now,
    );
    if (picked == null) return null;
    // RecipeOnDemand regresa la receta ya ajustada a la familia pero con las
    // servings del catálogo; quien la volviera a ajustar la reduciría dos veces.
    return recipes.firstWhere((recipe) => recipe.id == picked.id);
  }

  @override
  Future<MealPlanGeneration> planDays({
    required FamilyProfile family,
    required List<PantryItem> pantryItems,
    required List<Recipe> recipes,
    required int days,
    DateTime? startDate,
    DateTime? now,
  }) async {
    return MealPlanGenerator.generateMealPlan(
      family: family,
      pantryItems: pantryItems,
      recipes: recipes,
      days: days,
      startDate: startDate,
      now: now,
    );
  }

  @override
  Future<RecipeAdjustmentSuggestion?> suggestAdjustment({
    required AdjustmentContext household,
    required Recipe recipe,
  }) async => RecipeAdjustmentRules.suggest(recipe, household);
}
