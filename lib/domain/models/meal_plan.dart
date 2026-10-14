import '../firestore_codec.dart';
import '../meal_plan_length.dart';

class MealPlanMeal {
  /// Mismo tope que validMeal en firestore.rules: el id de una receta es el
  /// de un documento de recipes (mismo tope que reassignedFrom en las
  /// entregas).
  static const int maxRecipeIdLength = 128;

  /// Mismo tope que validMeal en firestore.rules (igual que los paquetes de
  /// una entrega, Delivery.maxPackages).
  static const double maxServings = 100;

  const MealPlanMeal({
    required this.date,
    required this.recipeId,
    required this.servings,
  });

  final DateTime date;
  final String recipeId;
  final double servings;

  factory MealPlanMeal.fromMap(Map<String, dynamic> map) {
    return MealPlanMeal(
      date: decodeDate(map['date']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      recipeId: decodeRefId(map['recipeId']) ?? '',
      servings: (map['servings'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'date': date,
        'recipeId': recipeId,
        'servings': servings,
      };

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'recipeId': recipeId,
        'servings': servings,
      };

  /// Null si la comida se puede guardar; si no, el motivo. Mismos límites que
  /// validMeal en firestore.rules: la fecha dentro del rango del plan (con los
  /// extremos incluidos), un recipeId de 1 a [maxRecipeIdLength] caracteres
  /// sin "/" y porciones mayores a 0 y de hasta [maxServings].
  String? validate({required DateTime rangeStart, required DateTime rangeEnd}) {
    if (date.isBefore(rangeStart) || date.isAfter(rangeEnd)) {
      return 'La fecha de la comida está fuera del rango del plan';
    }
    if (recipeId.isEmpty) return 'La receta de la comida es obligatoria';
    if (recipeId.runes.length > maxRecipeIdLength) {
      return 'El id de la receta no puede tener más de $maxRecipeIdLength caracteres';
    }
    if (recipeId.contains('/')) {
      return 'El id de la receta no puede contener "/"';
    }
    if (!servings.isFinite || servings <= 0 || servings > maxServings) {
      return 'Las porciones deben ser mayores a 0 y de hasta ${maxServings.toInt()}';
    }
    return null;
  }
}

class MealPlan {
  /// Un plan abarca 7 o 14 días con una comida por día (MealPlanLength), así
  /// que no tiene más de 14. Mismo tope que validMeals en firestore.rules: las
  /// reglas revisan cada comida por su índice y una solicitud solo puede
  /// evaluar 1000 expresiones, así que no pueden aceptar más sin dejar de
  /// revisarlas.
  static const int maxMeals = MealPlanLength.biweekly;

  const MealPlan({
    required this.id,
    required this.familyId,
    required this.dateRangeStart,
    required this.dateRangeEnd,
    required this.meals,
  });

  final String id;
  final String familyId;
  final DateTime dateRangeStart;
  final DateTime dateRangeEnd;
  final List<MealPlanMeal> meals;

  factory MealPlan.fromMap(String id, Map<String, dynamic> map) {
    final rawMeals = map['meals'] as List<dynamic>? ?? const [];
    return MealPlan(
      id: id,
      familyId: decodeRefId(map['familyId']) ?? '',
      dateRangeStart:
          decodeDate(map['dateRangeStart']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      dateRangeEnd:
          decodeDate(map['dateRangeEnd']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      meals: rawMeals
          .map((item) => MealPlanMeal.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'familyId': familyId,
        'dateRangeStart': dateRangeStart,
        'dateRangeEnd': dateRangeEnd,
        'meals': meals.map((meal) => meal.toMap()).toList(),
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'dateRangeStart': dateRangeStart.toIso8601String(),
        'dateRangeEnd': dateRangeEnd.toIso8601String(),
        'meals': meals.map((meal) => meal.toJson()).toList(),
      };

  /// Null si el plan se puede guardar; si no, el motivo. Mismos límites que
  /// validMealPlan en firestore.rules: el rango en orden, a lo más [maxMeals]
  /// comidas y cada una válida dentro del rango.
  String? validate() {
    if (dateRangeEnd.isBefore(dateRangeStart)) {
      return 'El plan termina antes de empezar';
    }
    if (meals.length > maxMeals) {
      return 'Un plan no puede tener más de $maxMeals comidas';
    }
    for (var i = 0; i < meals.length; i++) {
      final error = meals[i].validate(
        rangeStart: dateRangeStart,
        rangeEnd: dateRangeEnd,
      );
      if (error != null) return 'Comida ${i + 1}: $error';
    }
    return null;
  }
}
