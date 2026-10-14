import 'meal_plan_length.dart';
import 'models/meal_plan.dart';

/// El plan de comidas que guarda una familia (mealPlans/{planId}). Son
/// funciones puras: no escriben nada; MealPlanRepository guarda el resultado.
///
/// Las fechas son medianoche local, como en el plan de la pantalla y en
/// MealPlanGenerator, y dateRangeEnd es el día siguiente al último del plan.
abstract final class MealPlanEdits {
  /// Un plan abarca 7 o 14 días ([MealPlanLength]) con a lo más una comida
  /// por día.
  static const maxMeals = MealPlanLength.biweekly;

  /// Porciones de una comida: más de 0 y hasta este tope.
  static const maxServings = 100.0;

  /// recipeId es el id de un documento de recipes: de 1 a este número de
  /// caracteres y sin "/".
  static const maxRecipeIdLength = 128;

  static DateTime dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// El plan vigente: el que abarca [today] (desde dateRangeStart y antes de
  /// dateRangeEnd). Si hay varios gana el que empieza después y, si empiezan
  /// el mismo día, el de id mayor, para que todos los dispositivos muestren el
  /// mismo. Null si ninguno abarca [today]: un plan que ya terminó no cuenta.
  static MealPlan? current(Iterable<MealPlan> plans, DateTime today) {
    final day = dateOnly(today);
    MealPlan? best;
    for (final plan in plans) {
      if (day.isBefore(dateOnly(plan.dateRangeStart)) ||
          !day.isBefore(dateOnly(plan.dateRangeEnd))) {
        continue;
      }
      if (best == null || _startsAfter(plan, best)) best = plan;
    }
    return best;
  }

  static bool _startsAfter(MealPlan a, MealPlan b) {
    final byStart = a.dateRangeStart.compareTo(b.dateRangeStart);
    return byStart != 0 ? byStart > 0 : a.id.compareTo(b.id) > 0;
  }

  /// Plan nuevo de [familyId] de [days] días desde el día de [start], aún sin
  /// id. Las comidas quedan a medianoche y en orden: si dos caen el mismo día
  /// se queda la primera y las que caen fuera del plan se descartan. Lanza
  /// ArgumentError si [days] no va de 1 a [maxMeals] o si alguna comida no se
  /// puede guardar ([problem]).
  static MealPlan create({
    required String familyId,
    required DateTime start,
    required int days,
    required List<MealPlanMeal> meals,
  }) {
    if (days < 1 || days > maxMeals) {
      throw ArgumentError.value(
        days,
        'days',
        'Un plan abarca de 1 a $maxMeals días',
      );
    }
    final first = dateOnly(start);
    final end = DateTime(first.year, first.month, first.day + days);
    final byDay = <DateTime, MealPlanMeal>{};
    for (final meal in meals) {
      final day = dateOnly(meal.date);
      if (day.isBefore(first) || !day.isBefore(end)) continue;
      byDay.putIfAbsent(
        day,
        () => MealPlanMeal(
          date: day,
          recipeId: meal.recipeId,
          servings: meal.servings,
        ),
      );
    }
    final plan = MealPlan(
      id: '',
      familyId: familyId,
      dateRangeStart: first,
      dateRangeEnd: end,
      meals: byDay.values.toList()..sort((a, b) => a.date.compareTo(b.date)),
    );
    _check(plan);
    return plan;
  }

  /// La comida de [date] en [plan], o null si ese día está libre.
  static MealPlanMeal? mealOn(MealPlan plan, DateTime date) {
    for (final meal in plan.meals) {
      if (sameDay(meal.date, date)) return meal;
    }
    return null;
  }

  /// Null si [plan] se puede guardar; si no, el motivo. El rango va en orden
  /// y tiene a lo más [maxMeals] comidas, cada una dentro del rango, con el id
  /// de una receta (de 1 a [maxRecipeIdLength] caracteres, sin "/") y
  /// porciones mayores a 0 y de hasta [maxServings].
  static String? problem(MealPlan plan) {
    if (plan.dateRangeEnd.isBefore(plan.dateRangeStart)) {
      return 'El plan termina antes de empezar';
    }
    if (plan.meals.length > maxMeals) {
      return 'Un plan no puede tener más de $maxMeals comidas';
    }
    for (var i = 0; i < plan.meals.length; i++) {
      final error = _mealProblem(plan.meals[i], plan);
      if (error != null) return 'Comida ${i + 1}: $error';
    }
    return null;
  }

  static String? _mealProblem(MealPlanMeal meal, MealPlan plan) {
    if (meal.date.isBefore(plan.dateRangeStart) ||
        meal.date.isAfter(plan.dateRangeEnd)) {
      return 'La fecha de la comida está fuera del rango del plan';
    }
    final recipeId = meal.recipeId;
    if (recipeId.isEmpty) return 'La receta de la comida es obligatoria';
    if (recipeId.runes.length > maxRecipeIdLength) {
      return 'El id de la receta no puede tener más de $maxRecipeIdLength '
          'caracteres';
    }
    if (recipeId.contains('/')) {
      return 'El id de la receta no puede contener "/"';
    }
    final servings = meal.servings;
    if (!servings.isFinite || servings <= 0 || servings > maxServings) {
      return 'Las porciones deben ser mayores a 0 y de hasta '
          '${maxServings.toInt()}';
    }
    return null;
  }

  static void _check(MealPlan plan) {
    final error = problem(plan);
    if (error != null) throw ArgumentError(error);
  }
}
