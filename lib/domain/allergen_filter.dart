import '../data/models/member.dart';
import 'exclusion_list.dart';
import 'models/family_profile.dart';
import 'models/recipe.dart';

/// Deja fuera de las sugerencias y del plan las recetas que chocan con el
/// hogar. Una alergia siempre excluye; una enfermedad crónica solo si
/// [excludeRecipesForChronicConditions] lo pide (hoy solo avisa). Usa
/// [containsAllergen] y [containsRestricted], las mismas reglas que los
/// avisos de lib/ui/models/recipe.dart.
class AllergenFilter {
  /// Alergias del hogar. [FamilyProfile.dietaryRestrictions] mezcla alergias
  /// y enfermedades por nombre.
  static List<Allergy> allergiesOf(FamilyProfile family) => [
    for (final allergy in Allergy.values)
      if (family.dietaryRestrictions.contains(allergy.name)) allergy,
  ];

  static List<ChronicCondition> conditionsOf(FamilyProfile family) => [
    for (final condition in ChronicCondition.values)
      if (family.dietaryRestrictions.contains(condition.name)) condition,
  ];

  /// Las recetas de [recipes] que no chocan con [family].
  static List<Recipe> safeRecipes({
    required List<Recipe> recipes,
    required FamilyProfile family,
    bool excludeConditions = excludeRecipesForChronicConditions,
  }) {
    final allergies = allergiesOf(family);
    final conditions = excludeConditions
        ? conditionsOf(family)
        : const <ChronicCondition>[];
    if (allergies.isEmpty && conditions.isEmpty) return recipes;
    return recipes
        .where((recipe) => !_conflicts(recipe, allergies, conditions))
        .toList();
  }

  static bool containsAllergenOf(Recipe recipe, List<Allergy> allergies) =>
      _conflicts(recipe, allergies, const []);

  static bool _conflicts(
    Recipe recipe,
    List<Allergy> allergies,
    List<ChronicCondition> conditions,
  ) {
    for (final ingredient in recipe.ingredients) {
      for (final allergy in allergies) {
        if (containsAllergen(ingredient.productName, allergy)) return true;
      }
      for (final condition in conditions) {
        if (containsRestricted(ingredient.productName, condition)) return true;
      }
    }
    return false;
  }
}
