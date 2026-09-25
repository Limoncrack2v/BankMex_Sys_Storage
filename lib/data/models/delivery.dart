import 'package:cloud_firestore/cloud_firestore.dart';

import 'pantry_item.dart';

/// reassigned: la entrega programada pasó a otra familia (se registró una
/// entrega nueva para ella); se conserva para trazabilidad.
enum DeliveryStatus { scheduled, delivered, cancelled, reassigned }

/// Producto de una entrega, con su fecha de caducidad. Cuando la entrega queda
/// como entregada, la Cloud Function onDeliveryWritten (functions/pantry.js)
/// lo convierte en un PantryItem de la familia.
class DeliveryItem {
  static const int maxNameLength = 100;

  final String productId;
  final FoodType type;
  final double quantity;
  final FoodUnit unit;
  final DateTime expirationDate;

  DeliveryItem({
    required this.productId,
    required this.type,
    required this.quantity,
    required this.unit,
    required this.expirationDate,
  });

  factory DeliveryItem.fromMap(Map<String, dynamic> data) => DeliveryItem(
    productId: data['productId'] as String,
    type: FoodType.values.byName(data['type'] as String),
    quantity: (data['quantity'] as num).toDouble(),
    unit: FoodUnit.values.byName(data['unit'] as String),
    expirationDate: (data['expirationDate'] as Timestamp).toDate(),
  );

  Map<String, dynamic> toMap() => {
    'productId': productId.trim(),
    'type': type.name,
    'quantity': quantity,
    'unit': unit.name,
    'expirationDate': Timestamp.fromDate(expirationDate),
  };

  String? validate() {
    final name = productId.trim();
    if (name.isEmpty) return 'El nombre del producto es obligatorio';
    if (name.length > maxNameLength) {
      return 'El nombre del producto no puede tener más de $maxNameLength caracteres';
    }
    if (!quantity.isFinite ||
        quantity <= 0 ||
        quantity > PantryItem.maxQuantity) {
      return 'La cantidad de $name debe ser mayor a 0';
    }
    return null;
  }

  /// Si ya caducó en la fecha [date] (el mismo día aún no cuenta). La Cloud
  /// Function usa la misma regla para no agregarlo a la despensa.
  bool isExpiredOn(DateTime date) => DateTime(
    expirationDate.year,
    expirationDate.month,
    expirationDate.day,
  ).isBefore(DateTime(date.year, date.month, date.day));
}

class Delivery {
  static const int maxPackages = 100;
  static const int maxItems = 100;
  static const int maxFamilyNameLength = 100;

  final String deliveryId;
  final String familyId;

  /// Copia del nombre de la familia para la tabla de entregas del staff.
  final String familyName;
  final DateTime deliveryDate;
  final int packages;

  /// null = exenta de cuota de recuperación.
  final double? recoveryFee;
  final String? justification;
  final DeliveryStatus status;
  final String? notes;
  final List<DeliveryItem> items;
  final DateTime createdAt;

  /// Entrega original de la que viene esta, si se registró al reasignarla.
  final String? reassignedFrom;

  /// Entrega nueva que se registró al reasignar esta a otra familia. Solo la
  /// escribe DeliveryRepository.reassignDelivery (nunca toFirestore).
  final String? reassignedTo;

  /// Id de la instalación de la app (DeviceIdentity) que hizo la última
  /// escritura. Solo lo escribe DeliveryRepository (nunca toFirestore); las
  /// reglas lo exigen en cada escritura. Es null en una entrega que aún no se
  /// guarda (el formulario del staff) o que no se ha vuelto a escribir desde
  /// antes de existir la estampa.
  final String? deviceId;

  /// Cuándo se hizo la última escritura (registrar o cambiar el estado), con
  /// el reloj del dispositivo: si se guardó sin conexión, es la hora real y no
  /// la de sincronización. Al marcarla como entregada, la Cloud Function la usa
  /// como hora de entrega de los productos. Mismas reglas que [deviceId].
  final DateTime? localTimestamp;

  Delivery({
    required this.deliveryId,
    required this.familyId,
    required this.familyName,
    required this.deliveryDate,
    required this.packages,
    this.recoveryFee,
    this.justification,
    required this.status,
    this.notes,
    required this.items,
    required this.createdAt,
    this.reassignedFrom,
    this.reassignedTo,
    this.deviceId,
    this.localTimestamp,
  });

  bool get isExempt => recoveryFee == null;

  factory Delivery.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    return Delivery(
      deliveryId: doc.id,
      familyId: data['familyId'] as String,
      familyName: data['familyName'] as String,
      deliveryDate: (data['deliveryDate'] as Timestamp).toDate(),
      packages: (data['packages'] as num).toInt(),
      recoveryFee: (data['recoveryFee'] as num?)?.toDouble(),
      justification: data['justification'] as String?,
      status: DeliveryStatus.values.byName(data['status'] as String),
      notes: data['notes'] as String?,
      items: (data['items'] as List)
          .map((item) => DeliveryItem.fromMap(Map<String, dynamic>.from(item)))
          .toList(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      reassignedFrom: data['reassignedFrom'] as String?,
      reassignedTo: data['reassignedTo'] as String?,
      deviceId: data['deviceId'] as String?,
      localTimestamp: (data['localTimestamp'] as Timestamp?)?.toDate(),
    );
  }

  /// El nombre del hogar puede ser su dirección (hasta 200 caracteres) cuando
  /// no tiene nombre; las reglas solo aceptan 100 en la entrega.
  String get _shortFamilyName {
    final name = familyName.trim();
    return name.length > maxFamilyNameLength
        ? name.substring(0, maxFamilyNameLength)
        : name;
  }

  /// Los campos opcionales solo se escriben si tienen valor (validDelivery).
  Map<String, dynamic> toFirestore() {
    final justification = this.justification?.trim() ?? '';
    final notes = this.notes?.trim() ?? '';
    return {
      'familyId': familyId,
      'familyName': _shortFamilyName,
      'deliveryDate': Timestamp.fromDate(deliveryDate),
      'packages': packages,
      if (recoveryFee != null) 'recoveryFee': recoveryFee,
      if (justification.isNotEmpty) 'justification': justification,
      'status': status.name,
      if (notes.isNotEmpty) 'notes': notes,
      'items': items.map((item) => item.toMap()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
      if (reassignedFrom != null) 'reassignedFrom': reassignedFrom,
    };
  }

  String? validate() {
    if (familyId.trim().isEmpty) return 'Selecciona una familia';
    if (packages < 1 || packages > maxPackages) {
      return 'El número de despensas debe estar entre 1 y $maxPackages';
    }
    if (recoveryFee != null &&
        (!recoveryFee!.isFinite || recoveryFee! < 0 || recoveryFee! > 100000)) {
      return 'La cuota de recuperación no es válida';
    }
    if (items.isEmpty || items.length > maxItems) {
      return 'Agrega entre 1 y $maxItems productos';
    }
    for (final item in items) {
      final error = item.validate();
      if (error != null) return error;
    }
    return null;
  }
}
