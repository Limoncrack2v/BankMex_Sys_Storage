import 'expiration_urgency.dart';

// Modelo solo de UI: PantryItem (lib/data) aún no trae nombre, categoría ni
// unidad del producto. Cuando exista el catálogo de productos, construir este
// objeto a partir de PantryItem + producto.

class PantryProduct {
  const PantryProduct({
    required this.name,
    required this.category,
    required this.remaining,
    required this.daysUntilExpiration,
    required this.synchronized,
  });

  final String name;
  final String category;

  /// Cantidad restante ya formateada con su unidad, p. ej. "2 L".
  final String remaining;
  final int daysUntilExpiration;
  final bool synchronized;

  ExpirationUrgency get urgency =>
      ExpirationUrgency.fromDays(daysUntilExpiration);
}
