import '../../data/models/delivery.dart';
import '../../data/models/pantry_item.dart';
import '../../data/models/standard_basket.dart';

/// Un producto del formulario de entregas, leído de sus campos. Sirve para
/// comparar la lista con lo que llenaron las despensas estándar sin depender
/// de los controladores de texto.
class ProductLine {
  const ProductLine({
    required this.name,
    required this.quantity,
    required this.type,
    required this.unit,
    required this.expiration,
  });

  /// El producto de una entrega, tal como queda en el formulario al llenarlo.
  factory ProductLine.fromItem(DeliveryItem item) => ProductLine(
    name: item.productId.trim(),
    quantity: item.quantity,
    type: item.type,
    unit: item.unit,
    expiration: DateTime(
      item.expirationDate.year,
      item.expirationDate.month,
      item.expirationDate.day,
    ),
  );

  final String name;

  /// Null si el campo está vacío o no es un número.
  final double? quantity;
  final FoodType type;
  final FoodUnit unit;
  final DateTime? expiration;

  /// Sin nombre, cantidad ni caducidad: no hay nada que perder. El tipo y la
  /// unidad no cuentan, porque traen un valor por omisión.
  bool get isBlank => name.isEmpty && quantity == null && expiration == null;

  @override
  bool operator ==(Object other) =>
      other is ProductLine &&
      other.name == name &&
      other.quantity == quantity &&
      other.type == type &&
      other.unit == unit &&
      other.expiration == expiration;

  @override
  int get hashCode => Object.hash(name, quantity, type, unit, expiration);
}

bool _sameLines(List<ProductLine> a, List<ProductLine> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Qué hace el formulario con la lista de productos cuando cambian las
/// despensas elegidas, la fecha de entrega o el número de despensas.
enum BasketFillAction {
  /// No se toca nada: la lista ya es la que toca, o no hay nada que llenar y
  /// el staff ya capturó productos a mano.
  keep,

  /// La lista está vacía o sigue tal como se llenó: se reemplaza.
  fill,

  /// El staff ya editó la lista: no se toca y se le avisa, con la opción de
  /// reemplazarla.
  askFirst,
}

/// [current] es la lista del formulario, [lastFilled] lo que se llenó la
/// última vez (vacía si nunca) y [target] lo que toca ahora.
BasketFillAction basketFillOn({
  required List<ProductLine> current,
  required List<ProductLine> lastFilled,
  required List<ProductLine> target,
}) {
  final blank = current.every((line) => line.isBlank);
  if (_sameLines(current, target)) return BasketFillAction.keep;
  if (blank) {
    return target.isEmpty ? BasketFillAction.keep : BasketFillAction.fill;
  }
  if (_sameLines(current, lastFilled)) return BasketFillAction.fill;
  // Quitar todas las despensas no borra lo que el staff capturó a mano.
  return target.isEmpty ? BasketFillAction.keep : BasketFillAction.askFirst;
}

/// Qué falta para poder llenar los productos.
enum BasketWait { date, packages }

/// Lo que toca llenar, o por qué todavía no se puede.
class BasketTarget {
  const BasketTarget.items(List<DeliveryItem> this.items)
    : waitingFor = null,
      problem = null;
  const BasketTarget.waiting(BasketWait this.waitingFor)
    : items = null,
      problem = null;
  const BasketTarget.problem(String this.problem)
    : items = null,
      waitingFor = null;

  /// Los productos que dan las despensas; vacía si no hay ninguna elegida.
  final List<DeliveryItem>? items;
  final BasketWait? waitingFor;

  /// Por qué no se pueden llenar (p. ej. suman más de [Delivery.maxItems]).
  final String? problem;
}

/// Los productos de [baskets] para [packages] despensas entregadas en [date].
/// No lanza: lo que [StandardBasket.deliveryItemsFor] rechaza vuelve como
/// [BasketTarget.problem].
BasketTarget basketTarget({
  required List<StandardBasket> baskets,
  required DateTime? date,
  required int? packages,
}) {
  if (baskets.isEmpty) return const BasketTarget.items([]);
  if (date == null) return const BasketTarget.waiting(BasketWait.date);
  if (packages == null) return const BasketTarget.waiting(BasketWait.packages);
  try {
    return BasketTarget.items(
      StandardBasket.deliveryItemsFor(
        baskets,
        packages: packages,
        deliveryDate: date,
      ),
    );
  } on ArgumentError catch (error) {
    return BasketTarget.problem(
      '${error.message}. Quita una despensa de la selección.',
    );
  }
}
