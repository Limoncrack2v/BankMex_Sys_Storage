import 'package:cloud_firestore/cloud_firestore.dart';

import 'delivery.dart';
import 'pantry_item.dart';

/// Producto de una despensa estándar. A diferencia de [DeliveryItem] no
/// guarda una fecha de caducidad sino cuántos días dura desde que se entrega
/// ([shelfLifeDays]), porque la misma despensa se entrega en fechas distintas.
class StandardBasketItem {
  final String productId;
  final FoodType type;
  final double quantity;
  final FoodUnit unit;
  final int shelfLifeDays;

  const StandardBasketItem({
    required this.productId,
    required this.type,
    required this.quantity,
    required this.unit,
    required this.shelfLifeDays,
  });

  factory StandardBasketItem.fromMap(Map<String, dynamic> data) =>
      StandardBasketItem(
        productId: data['productId'] as String,
        type: FoodType.values.byName(data['type'] as String),
        quantity: (data['quantity'] as num).toDouble(),
        unit: FoodUnit.values.byName(data['unit'] as String),
        shelfLifeDays: (data['shelfLifeDays'] as num).toInt(),
      );

  /// El producto de una entrega en [deliveryDate]: caduca [shelfLifeDays]
  /// días después.
  DeliveryItem toDeliveryItem(DateTime deliveryDate) => DeliveryItem(
    productId: productId,
    type: type,
    quantity: quantity,
    unit: unit,
    expirationDate: DateTime(
      deliveryDate.year,
      deliveryDate.month,
      deliveryDate.day + shelfLifeDays,
    ),
  );
}

/// Contenido fijo de una despensa del banco (standardBaskets/{basketId}).
/// Solo la escriben los scripts de tool/ (tool/standard_baskets.mjs); el
/// staff la lee para llenar los productos de una entrega.
class StandardBasket {
  final String basketId;
  final String name;
  final String description;
  final List<StandardBasketItem> items;

  const StandardBasket({
    required this.basketId,
    required this.name,
    required this.description,
    required this.items,
  });

  factory StandardBasket.fromMap(String basketId, Map<String, dynamic> data) =>
      StandardBasket(
        basketId: basketId,
        name: data['name'] as String,
        description: data['description'] as String? ?? '',
        items: (data['items'] as List? ?? const [])
            .map(
              (item) => StandardBasketItem.fromMap(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(),
      );

  factory StandardBasket.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) => StandardBasket.fromMap(doc.id, doc.data() ?? <String, dynamic>{});

  /// Los productos de esta despensa para una entrega en [deliveryDate].
  List<DeliveryItem> toDeliveryItems(DateTime deliveryDate) =>
      items.map((item) => item.toDeliveryItem(deliveryDate)).toList();

  /// Los productos de una entrega de [packages] despensas de cada una de
  /// [baskets] (p. ej. básica + frescos) en [deliveryDate]. Cada cantidad se
  /// multiplica por [packages], porque onDeliveryWritten copia
  /// `item.quantity` tal cual a la despensa. Un producto que viene igual en
  /// dos despensas (mismo nombre, tipo, unidad y caducidad) queda en una sola
  /// línea con la suma.
  ///
  /// Lanza [ArgumentError] si [packages] no está entre 1 y
  /// [Delivery.maxPackages], o si salen más de [Delivery.maxItems] productos
  /// (el límite de validDelivery).
  static List<DeliveryItem> deliveryItemsFor(
    List<StandardBasket> baskets, {
    required int packages,
    required DateTime deliveryDate,
  }) {
    if (packages < 1 || packages > Delivery.maxPackages) {
      throw ArgumentError(
        'El número de despensas debe estar entre 1 y ${Delivery.maxPackages}',
      );
    }
    final merged = <String, DeliveryItem>{};
    for (final basket in baskets) {
      for (final item in basket.toDeliveryItems(deliveryDate)) {
        final key = [
          item.productId.trim().toLowerCase(),
          item.type.name,
          item.unit.name,
          item.expirationDate.toIso8601String(),
        ].join('|');
        final previous = merged[key];
        merged[key] = DeliveryItem(
          productId: previous?.productId ?? item.productId.trim(),
          type: item.type,
          quantity: _round3(
            (previous?.quantity ?? 0) + item.quantity * packages,
          ),
          unit: item.unit,
          expirationDate: item.expirationDate,
        );
      }
    }
    if (merged.length > Delivery.maxItems) {
      throw ArgumentError(
        'Las despensas suman ${merged.length} productos; una entrega acepta '
        'hasta ${Delivery.maxItems}',
      );
    }
    return merged.values.toList();
  }

  /// Evita residuos de punto flotante (0.4 * 3 = 1.2000000000000002).
  static double _round3(double value) => (value * 1000).round() / 1000;
}
