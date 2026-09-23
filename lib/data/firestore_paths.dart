/// Nombres de colecciones. Las de familia/despensa ya existían; recipes,
/// mealPlans y consumptionLogs las agrega el catálogo y el plan.
abstract final class FirestorePaths {
  static const families = 'families';
  static const pantryItems = 'pantryItems';
  static const members = 'members';
  static const users = 'users';
  static const recipes = 'recipes';
  static const mealPlans = 'mealPlans';
  static const consumptionLogs = 'consumptionLogs';

  static String familyDoc(String familyId) => '$families/$familyId';
}
