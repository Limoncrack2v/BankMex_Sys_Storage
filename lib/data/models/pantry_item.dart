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
  /// Días de [localTimestamp] a la caducidad (no cambia con el tiempo; los
  /// días que quedan hoy se calculan en ui/formatting.dart).
  final int daysUntilExpiration;

  /// Instalación del staff que marcó la entrega (su deviceId), o
  /// 'cloud-function' si la entrega no tenía estampa.
  final String deviceId;

  /// Cuándo recibió la familia el producto: la hora de entrega según el
  /// dispositivo del staff, o la del servidor si no es creíble. La escribe una
  /// vez la Cloud Function al crear el producto y ningún cliente la cambia.
  /// El estado de sincronización no se guarda aquí: sale de
  /// metadata.hasPendingWrites de Firestore.
  final DateTime localTimestamp;

  PantryItem({
    required this.pantryItemId,
    required this.productId,
    required this.deliveryId,
    required this.type,
    required this.quantity,
    required this.unit,
    required this.daysUntilExpiration,
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
