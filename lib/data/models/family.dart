import 'package:cloud_firestore/cloud_firestore.dart';

/// Electrodomésticos con los que cuenta el hogar. [id] es el valor que se
/// guarda en families/{id}.appliances (validFamily en firestore.rules solo
/// acepta estos).
enum Appliance {
  stove('estufa'),
  fridge('refrigerador'),
  oven('horno'),
  microwave('microondas'),
  blender('licuadora'),
  pressureCooker('ollaPresion');

  const Appliance(this.id);

  final String id;

  /// null si [id] no es un electrodoméstico conocido.
  static Appliance? fromId(String id) {
    for (final appliance in values) {
      if (appliance.id == id) return appliance;
    }
    return null;
  }
}

class Family {
  final String familyId;

  /// Nombre del hogar, p. ej. "Familia Ramírez".
  final String? name;
  final String address;
  final DateTime registrationDate;
  final double? recoveryQuotaDefault;
  final String authUid;

  /// Ids de [Appliance], sin repetir.
  final List<String> appliances;

  /// Solo la Cloud Function syncNextDelivery la escribe; la app solo la lee
  final DateTime? nextDeliveryDate;

  Family({
    required this.familyId,
    this.name,
    required this.address,
    required this.registrationDate,
    this.recoveryQuotaDefault,
    required this.authUid,
    required this.appliances,
    this.nextDeliveryDate,
  });

  factory Family.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    return Family(
      familyId: doc.id,
      name: data['name'] as String?,
      address: data['address'] as String,
      registrationDate: (data['registrationDate'] as Timestamp).toDate(),
      recoveryQuotaDefault: (data['recoveryQuotaDefault'] as num?)?.toDouble(),
      authUid: data['authUid'] as String,
      appliances: List<String>.from(data['appliances'] as List? ?? []),
      nextDeliveryDate: (data['nextDeliveryDate'] as Timestamp?)?.toDate(),
    );
  }

  /// Nombre para mostrar; las familias creadas antes de tener nombre usan la
  /// dirección.
  String get displayName {
    final trimmed = name?.trim() ?? '';
    return trimmed.isNotEmpty ? trimmed : address;
  }

  static String? validateAppliances(List<String> appliances) {
    if (appliances.any((id) => Appliance.fromId(id) == null)) {
      return 'Electrodoméstico desconocido';
    }
    if (appliances.toSet().length != appliances.length) {
      return 'Los electrodomésticos no pueden repetirse';
    }
    return null;
  }

  Map<String, dynamic> toFirestore() => {
    if (name != null) 'name': name!.trim(),
    'address': address,
    'registrationDate': Timestamp.fromDate(registrationDate),
    'recoveryQuotaDefault': recoveryQuotaDefault,
    'authUid': authUid,
    'appliances': appliances,
  };
}
