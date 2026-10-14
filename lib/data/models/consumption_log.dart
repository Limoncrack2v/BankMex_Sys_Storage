import 'package:cloud_firestore/cloud_firestore.dart';

import 'pantry_item.dart';

/// Por qué salió un producto de la despensa (campo `reason` de
/// consumptionLogs): se consumió, o ya había caducado y se desechó.
enum ConsumptionReason { consumed, expired }

/// Un documento de families/{familyId}/consumptionLogs: cuánto salió de un
/// producto de la despensa, cuándo y por qué. Solo los escribe
/// PantryRepository.registerConsumption.
class ConsumptionLog {
  ConsumptionLog({
    required this.productId,
    required this.quantity,
    required this.unit,
    required this.type,
    required this.at,
    required this.reason,
  });

  final String productId;
  final double quantity;
  final FoodUnit unit;
  final FoodType type;
  final DateTime at;
  final ConsumptionReason reason;

  bool get wasted => reason == ConsumptionReason.expired;

  factory ConsumptionLog.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return ConsumptionLog(
      productId: data['productId'] as String,
      quantity: (data['quantity'] as num).toDouble(),
      unit: FoodUnit.values.byName(data['unit'] as String),
      type: FoodType.values.byName(data['category'] as String),
      at: (data['at'] as Timestamp).toDate(),
      // Los registros anteriores a `reason` solo eran de consumo.
      reason: data['reason'] == ConsumptionReason.expired.name
          ? ConsumptionReason.expired
          : ConsumptionReason.consumed,
    );
  }
}
