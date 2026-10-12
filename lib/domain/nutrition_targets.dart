import '../data/models/member.dart';
import 'energy_requirement.dart';
import 'exclusion_list.dart';

/// Lo único que el motor de recetas (reglas hoy, IA después) recibe de un
/// hogar: cuántas calorías necesita al día y qué ingredientes evitar. Se
/// deriva de los integrantes, pero no lleva nombres, edades, pesos ni
/// enfermedades (MASVS-PRIVACY-1): solo los números y las palabras.
class NutritionTargets {
  const NutritionTargets({
    required this.caloricTarget,
    required this.householdSize,
    required this.unestimatedMembers,
    required this.exclusionList,
  });

  /// Suma de [EnergyRequirement.dailyKcal] de los integrantes, en kcal/día.
  /// No cuenta a [unestimatedMembers].
  final int caloricTarget;

  final int householdSize;

  /// Integrantes sin datos para estimar su energía (una niña o niño sin
  /// edad). Si es mayor a 0, [caloricTarget] se queda corto.
  final int unestimatedMembers;

  /// Palabras de los alérgenos y de las enfermedades crónicas del hogar
  /// ([exclusionKeywords]), sin repetir y en orden alfabético.
  final List<String> exclusionList;

  factory NutritionTargets.forHousehold(List<Member> members) {
    final (:kcal, :missing) = EnergyRequirement.household(members);
    return NutritionTargets(
      caloricTarget: kcal,
      householdSize: members.length,
      unestimatedMembers: missing,
      exclusionList: exclusionKeywords(members),
    );
  }

  Map<String, Object> toJson() => {
    'caloricTarget': caloricTarget,
    'householdSize': householdSize,
    'unestimatedMembers': unestimatedMembers,
    'exclusionList': exclusionList,
  };
}
