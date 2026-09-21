import 'package:cloud_firestore/cloud_firestore.dart';

enum FoodType {
  grain,
  legume,
  canned,
  dairy,
  produce,
  protein,
  beverage,
  other,
}

enum FoodUnit { kg, g, l, ml, piece, can, pack }

class PantryItem {
  static const double maxQuantity = 1000000;

  final String pantryItemId;
  final String productId;
  final String deliveryId;
  final FoodType type;
  final double quantity;
  final FoodUnit unit;
  final int daysUntilExpiration;
  final bool synchronized;
  final String deviceId;
  final DateTime localTimestamp;

  PantryItem({
    required this.pantryItemId,
    required this.productId,
    required this.deliveryId,
    required this.type,
    required this.quantity,
    required this.unit,
    required this.daysUntilExpiration,
    required this.synchronized,
    required this.deviceId,
    required this.localTimestamp,
  });

  factory PantryItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    return PantryItem(
      pantryItemId: doc.id,
      productId: data['productId'] as String,
      deliveryId: data['deliveryId'] as String,
      type: FoodType.values.byName(data['type'] as String),
      quantity: (data['quantity'] as num).toDouble(),
      unit: FoodUnit.values.byName(data['unit'] as String),
      daysUntilExpiration: (data['daysUntilExpiration'] as num).toInt(),
      synchronized: data['synchronized'] as bool? ?? false,
      deviceId: data['deviceId'] as String,
      localTimestamp: (data['localTimestamp'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'productId': productId,
    'deliveryId': deliveryId,
    'type': type.name,
    'quantity': quantity,
    'unit': unit.name,
    'daysUntilExpiration': daysUntilExpiration,
    'synchronized': synchronized,
    'deviceId': deviceId,
    'localTimestamp': Timestamp.fromDate(localTimestamp),
  };

  PantryItem withDeliveryId(String deliveryId) => PantryItem(
    pantryItemId: pantryItemId,
    productId: productId,
    deliveryId: deliveryId,
    type: type,
    quantity: quantity,
    unit: unit,
    daysUntilExpiration: daysUntilExpiration,
    synchronized: synchronized,
    deviceId: deviceId,
    localTimestamp: localTimestamp,
  );

  String? validate() {
    if (productId.trim().isEmpty) return 'El producto es obligatorio';
    if (deliveryId.trim().isEmpty) return 'La entrega es obligatoria';
    if (!quantity.isFinite || quantity <= 0 || quantity > maxQuantity) {
      return 'La cantidad debe ser mayor a 0 y no más de ${maxQuantity.toInt()}';
    }
    if (daysUntilExpiration < 0) {
      return 'Los días para caducar no pueden ser negativos';
    }
    if (deviceId.trim().isEmpty) return 'El dispositivo es obligatorio';
    return null;
  }
}
