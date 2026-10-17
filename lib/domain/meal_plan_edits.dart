import 'models/meal_plan.dart';

/// El plan de comidas que guarda una familia (mealPlans/{planId}). Son
/// funciones puras: no escriben nada; MealPlanRepository guarda el resultado.
///
/// Las fechas son medianoche local, como en el plan de la pantalla y en
/// MealPlanGenerator, y dateRangeEnd es el día siguiente al último del plan.
/// Los límites son los de [MealPlan.validate].
abstract final class MealPlanEdits {
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
  /// ArgumentError si [days] no va de 1 a [MealPlan.maxMeals] o si alguna
  /// comida no se puede guardar ([MealPlan.validate]).
  static MealPlan create({
    required String familyId,
    required DateTime start,
    required int days,
    required List<MealPlanMeal> meals,
  }) {
    if (days < 1 || days > MealPlan.maxMeals) {
      throw ArgumentError.value(
        days,
        'days',
        'Un plan abarca de 1 a ${MealPlan.maxMeals} días',
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

  /// [plan] con [recipeId] en [date]: reemplaza la comida de ese día o llena
  /// un día libre; los demás días no cambian. Lanza ArgumentError si [date]
  /// no es un día del plan o si la comida no se puede guardar
  /// ([MealPlan.validate]).
  static MealPlan withRecipe(
    MealPlan plan,
    DateTime date, {
    required String recipeId,
    required double servings,
  }) {
    final day = dateOnly(date);
    if (day.isBefore(dateOnly(plan.dateRangeStart)) ||
        !day.isBefore(dateOnly(plan.dateRangeEnd))) {
      throw ArgumentError.value(date, 'date', 'El día no es parte del plan');
    }
    final updated = _withMeals(
      plan,
      [
        for (final meal in plan.meals)
          if (!sameDay(meal.date, day)) meal,
        MealPlanMeal(date: day, recipeId: recipeId, servings: servings),
      ]..sort((a, b) => a.date.compareTo(b.date)),
    );
    _check(updated);
    return updated;
  }

  /// [plan] sin la comida de [date]: el día queda libre y los demás no
  /// cambian. Si ese día ya estaba libre, las comidas quedan igual.
  static MealPlan withoutMeal(MealPlan plan, DateTime date) =>
      _withMeals(plan, [
        for (final meal in plan.meals)
          if (!sameDay(meal.date, date)) meal,
      ]);

  static MealPlan _withMeals(MealPlan plan, List<MealPlanMeal> meals) =>
      MealPlan(
        id: plan.id,
        familyId: plan.familyId,
        dateRangeStart: plan.dateRangeStart,
        dateRangeEnd: plan.dateRangeEnd,
        meals: meals,
      );

  static void _check(MealPlan plan) {
    final error = plan.validate();
    if (error != null) throw ArgumentError(error);
  }
}
