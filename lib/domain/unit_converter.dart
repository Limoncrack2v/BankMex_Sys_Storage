enum UnitFamily { mass, volume, count, unknown }

class UnitConverter {
  static const _mass = <String, double>{
    'g': 1,
    'gr': 1,
    'gramo': 1,
    'gramos': 1,
    'kg': 1000,
    'kilo': 1000,
    'kilos': 1000,
  };

  static const _volume = <String, double>{
    'ml': 1,
    'mililitro': 1,
    'mililitros': 1,
    'l': 1000,
    'lt': 1000,
    'litro': 1000,
    'litros': 1000,
  };

  static const _count = <String, double>{
    'pza': 1,
    'pzas': 1,
    'pieza': 1,
    'piezas': 1,
    'unidad': 1,
    'unidades': 1,
    'u': 1,
    'piece': 1,
    'can': 1,
    'pack': 1,
    'lata': 1,
    'latas': 1,
    'rebanada': 1,
    'rebanadas': 1,
  };

  static String canonical(String unit) => unit.trim().toLowerCase();

  static UnitFamily family(String unit) {
    final key = canonical(unit);
    if (_mass.containsKey(key)) return UnitFamily.mass;
    if (_volume.containsKey(key)) return UnitFamily.volume;
    if (_count.containsKey(key)) return UnitFamily.count;
    return UnitFamily.unknown;
  }

  static bool compatible(String left, String right) {
    final leftFamily = family(left);
    final rightFamily = family(right);
    if (leftFamily == UnitFamily.unknown || rightFamily == UnitFamily.unknown) {
      return canonical(left) == canonical(right);
    }
    return leftFamily == rightFamily;
  }

  static double toBase(double quantity, String unit) {
    final key = canonical(unit);
    final factor = _mass[key] ?? _volume[key] ?? _count[key] ?? 1;
    return quantity * factor;
  }

  static double fromBase(double baseQuantity, String unit) {
    final key = canonical(unit);
    final factor = _mass[key] ?? _volume[key] ?? _count[key] ?? 1;
    return baseQuantity / factor;
  }
}
