// Modelo solo de UI: el modelo Family de lib/data todavía no tiene
// integrantes. Cuando exista en backend, reemplazar por ese.

enum MemberType {
  adulto('Adulto'),
  nino('Niño'),
  nina('Niña');

  const MemberType(this.label);

  final String label;
}

const allergyOptions = [
  'Lácteos',
  'Gluten',
  'Cacahuate',
  'Mariscos',
  'Huevo',
  'Soya',
];

class HouseholdMember {
  const HouseholdMember({
    required this.name,
    required this.age,
    this.weightKg,
    required this.type,
    this.allergies = const [],
  });

  final String name;
  final int age;
  final double? weightKg;
  final MemberType type;

  /// Vacía significa "Ninguna".
  final List<String> allergies;

  String get initial {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }
}

/// 68.0 -> "68", 68.5 -> "68.5".
String formatKg(double kg) =>
    kg == kg.roundToDouble() ? kg.toInt().toString() : kg.toString();
