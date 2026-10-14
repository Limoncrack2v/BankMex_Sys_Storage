import '../../domain/models/meal_plan.dart';
import 'recipe.dart';

/// El plan de comidas como se guarda en mealPlans: una comida por
/// día con el id de la receta y las porciones del hogar. El rango termina el
/// día después de la última comida, igual que en MealPlanGenerator.
///
/// Regresa null si alguna receta no tiene id (no viene del catálogo), porque
/// un plan guardado no podría apuntar a ella.
MealPlan? mealPlanRecord({
  required String familyId,
  required List<MealPlanEntry> entries,
  required DateTime start,
  required int days,
  required double servings,
}) {
  if (entries.any((entry) => entry.recipe.id.isEmpty)) return null;
  final first = DateTime(start.year, start.month, start.day);
  return MealPlan(
    // Sin id: la pantalla le pone el del plan que ya había, si lo hay.
    id: '',
    familyId: familyId,
    dateRangeStart: first,
    dateRangeEnd: DateTime(first.year, first.month, first.day + days),
    meals: [
      for (final entry in entries)
        MealPlanMeal(
          date: DateTime(entry.date.year, entry.date.month, entry.date.day),
          recipeId: entry.recipe.id,
          servings: servings,
        ),
    ],
  );
}

/// Si [a] y [b] son el mismo plan: mismo rango, mismas recetas los mismos días
/// y las mismas porciones. Es lo que decide si hay que volver a guardar.
bool sameMealPlan(MealPlan a, MealPlan b) {
  bool sameDay(DateTime x, DateTime y) =>
      x.year == y.year && x.month == y.month && x.day == y.day;
  if (!sameDay(a.dateRangeStart, b.dateRangeStart) ||
      !sameDay(a.dateRangeEnd, b.dateRangeEnd) ||
      a.meals.length != b.meals.length) {
    return false;
  }
  for (var i = 0; i < a.meals.length; i++) {
    final (x, y) = (a.meals[i], b.meals[i]);
    if (!sameDay(x.date, y.date) ||
        x.recipeId != y.recipeId ||
        (x.servings - y.servings).abs() > 0.001) {
      return false;
    }
  }
  return true;
}
