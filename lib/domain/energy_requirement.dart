import '../data/models/member.dart';
import 'portion_adjuster.dart';

/// Requerimiento aproximado de energía (kcal/día) por persona, según
/// FAO/WHO/UNU, "Human energy requirements" (2004), con actividad moderada.
///
/// - 1 a 17 años: tablas 4.5 y 4.6 (niños y niñas).
/// - Menores de 1 año: ~80 kcal por kg (sin peso, 700 kcal).
/// - 18 años o más: metabolismo basal de Schofield × PAL 1.75.
///
/// Sin sexo (en la app solo se captura para niñas y niños) se promedian
/// ambos. Un adulto sin peso usa 70 kg y sin edad el rango de 30 a 59 años.
/// Una niña o niño sin edad no se puede estimar (null).
class EnergyRequirement {
  static const double activityLevel = 1.75;
  static const double infantKcalPerKg = 80;
  static const int infantDefaultKcal = 700;

  /// kcal/día de 1 a 17 años (índice = edad - 1): (niños, niñas).
  static const List<(int, int)> childKcal = [
    (948, 865),
    (1129, 1047),
    (1252, 1156),
    (1360, 1241),
    (1467, 1330),
    (1573, 1428),
    (1692, 1554),
    (1830, 1698),
    (1978, 1854),
    (2150, 2006),
    (2341, 2149),
    (2548, 2276),
    (2770, 2379),
    (2990, 2449),
    (3178, 2491),
    (3322, 2503),
    (3410, 2503),
  ];

  /// kcal/día redondeadas a la decena, o null si no hay datos suficientes.
  static int? dailyKcal(Member member) {
    final age = member.age;
    final weight = member.weightKg;
    if (age == null && member.memberType == MemberType.child) return null;

    final double kcal;
    if (age != null && age < 1) {
      kcal = weight == null
          ? infantDefaultKcal.toDouble()
          : weight * infantKcalPerKg;
    } else if (age != null && age < 18) {
      final (boys, girls) = childKcal[age - 1];
      kcal = switch (member.sex) {
        MemberSex.male => boys.toDouble(),
        MemberSex.female => girls.toDouble(),
        null => (boys + girls) / 2,
      };
    } else {
      final w = weight ?? PortionAdjuster.adultWeightKg;
      final male = _schofieldMale(age, w);
      final female = _schofieldFemale(age, w);
      final bmr = switch (member.sex) {
        MemberSex.male => male,
        MemberSex.female => female,
        null => (male + female) / 2,
      };
      kcal = bmr * activityLevel;
    }
    return (kcal / 10).round() * 10;
  }

  /// Suma del hogar y cuántos integrantes no se pudieron estimar.
  static ({int kcal, int missing}) household(List<Member> members) {
    var kcal = 0;
    var missing = 0;
    for (final member in members) {
      final value = dailyKcal(member);
      if (value == null) {
        missing++;
      } else {
        kcal += value;
      }
    }
    return (kcal: kcal, missing: missing);
  }

  static double _schofieldMale(int? age, double w) => switch (age) {
    final a? when a < 30 => 15.057 * w + 692.2,
    final a? when a >= 60 => 11.711 * w + 587.7,
    _ => 11.472 * w + 873.1,
  };

  static double _schofieldFemale(int? age, double w) => switch (age) {
    final a? when a < 30 => 14.818 * w + 486.6,
    final a? when a >= 60 => 9.082 * w + 658.5,
    _ => 8.126 * w + 845.6,
  };
}
