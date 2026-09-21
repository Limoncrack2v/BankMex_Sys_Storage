import 'package:cloud_firestore/cloud_firestore.dart';

class Family {
  final String familyId;

  /// Nombre del hogar, p. ej. "Familia Ramírez".
  final String? name;
  final String address;
  final DateTime registrationDate;
  final double? recoveryQuotaDefault;
  final String authUid;
  final List<String> appliances;

  Family({
    required this.familyId,
    this.name,
    required this.address,
    required this.registrationDate,
    this.recoveryQuotaDefault,
    required this.authUid,
    required this.appliances,
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
    );
  }

  /// Nombre para mostrar; las familias creadas antes de tener nombre usan la
  /// dirección.
  String get displayName {
    final trimmed = name?.trim() ?? '';
    return trimmed.isNotEmpty ? trimmed : address;
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
