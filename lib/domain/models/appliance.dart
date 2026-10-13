/// Electrodomésticos con los que cuenta el hogar o que pide una receta. [id]
/// es el valor que se guarda en families/{id}.appliances (validFamily en
/// firestore.rules solo acepta estos) y en recipes/{id}.requiredEquipment.
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

  /// Mensaje para mostrar si [ids] trae un electrodoméstico desconocido o
  /// repetido; null si está bien. [keep] son ids que ya estaban guardados: se
  /// aceptan aunque esta versión de la app no los conozca, para no borrarlos
  /// al editar.
  static String? validateIds(List<String> ids, {Set<String> keep = const {}}) {
    if (ids.any((id) => fromId(id) == null && !keep.contains(id))) {
      return 'Electrodoméstico desconocido';
    }
    if (ids.toSet().length != ids.length) {
      return 'Los electrodomésticos no pueden repetirse';
    }
    return null;
  }
}
