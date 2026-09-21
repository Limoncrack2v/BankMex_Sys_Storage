import 'package:cloud_firestore/cloud_firestore.dart';

enum MemberType { adult, child }

/// Solo se captura para niñas y niños (en la app: "Niño" / "Niña").
enum MemberSex { male, female }

/// Alergias y restricciones alimentarias que se pueden registrar.
enum Allergy { dairy, gluten, peanut, shellfish, egg, soy }

class Member {
  static const int maxNameLength = 100;
  static const int maxAge = 120;
  static const double maxWeightKg = 500;

  final String memberId;
  final String name;
  final MemberType memberType;
  final DateTime createdAt;
  final int? age;
  final double? weightKg;
  final MemberSex? sex;

  /// null = no se ha capturado; vacía = "Ninguna".
  final List<Allergy>? allergies;

  Member({
    required this.memberId,
    required this.name,
    required this.memberType,
    required this.createdAt,
    this.age,
    this.weightKg,
    this.sex,
    this.allergies,
  });

  factory Member.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final sex = data['sex'] as String?;
    final allergies = data['allergies'] as List?;

    return Member(
      memberId: doc.id,
      name: data['name'] as String,
      memberType: MemberType.values.byName(data['memberType'] as String),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      age: (data['age'] as num?)?.toInt(),
      weightKg: (data['weightKg'] as num?)?.toDouble(),
      sex: sex == null ? null : MemberSex.values.byName(sex),
      allergies: allergies
          ?.map((a) => Allergy.values.byName(a as String))
          .toList(),
    );
  }

  /// Los campos opcionales solo se escriben si tienen valor, para respetar
  /// validMember en firestore.rules.
  Map<String, dynamic> toFirestore() => {
    'name': name.trim(),
    'memberType': memberType.name,
    'createdAt': Timestamp.fromDate(createdAt),
    if (age != null) 'age': age,
    if (weightKg != null) 'weightKg': weightKg,
    if (sex != null) 'sex': sex!.name,
    if (allergies != null) 'allergies': allergies!.map((a) => a.name).toList(),
  };

  Member copyWith({String? memberId}) => Member(
    memberId: memberId ?? this.memberId,
    name: name,
    memberType: memberType,
    createdAt: createdAt,
    age: age,
    weightKg: weightKg,
    sex: sex,
    allergies: allergies,
  );

  static String? validateName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'El nombre no puede estar vacío';
    if (trimmed.length > maxNameLength) {
      return 'El nombre no puede tener más de $maxNameLength caracteres';
    }
    return null;
  }

  String? validate() {
    final nameError = validateName(name);
    if (nameError != null) return nameError;
    if (age != null && (age! < 0 || age! > maxAge)) {
      return 'La edad debe estar entre 0 y $maxAge años';
    }
    if (weightKg != null &&
        (!weightKg!.isFinite || weightKg! <= 0 || weightKg! > maxWeightKg)) {
      return 'El peso debe ser mayor a 0 y no más de ${maxWeightKg.toInt()} kg';
    }
    if (allergies != null && allergies!.toSet().length != allergies!.length) {
      return 'Las alergias no pueden repetirse';
    }
    return null;
  }
}
