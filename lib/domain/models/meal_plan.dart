import '../firestore_codec.dart';

class MealPlanMeal {
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
}

class MealPlan {
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
}
