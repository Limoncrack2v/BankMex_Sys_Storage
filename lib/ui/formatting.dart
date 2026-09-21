import '../data/models/member.dart';
import '../data/models/pantry_item.dart';

/// Textos y formatos en español compartidos por las pantallas.

const _monthsShort = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// 2.0 -> "2", 2.5 -> "2.5", 0.25 -> "0.25" (máximo 3 decimales).
String formatNumber(double value) {
  final rounded = (value * 1000).round() / 1000;
  if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
  return rounded
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// Abreviatura de la unidad; las unidades contables van en singular o plural.
String unitLabel(FoodUnit unit, double quantity) {
  final one = quantity == 1;
  return switch (unit) {
    FoodUnit.kg => 'kg',
    FoodUnit.g => 'g',
    FoodUnit.l => 'L',
    FoodUnit.ml => 'ml',
    FoodUnit.piece => one ? 'pieza' : 'piezas',
    FoodUnit.can => one ? 'lata' : 'latas',
    FoodUnit.pack => one ? 'paquete' : 'paquetes',
  };
}

/// Nombre de la unidad para selectores ("Kilogramos (kg)").
String unitName(FoodUnit unit) => switch (unit) {
  FoodUnit.kg => 'Kilogramos (kg)',
  FoodUnit.g => 'Gramos (g)',
  FoodUnit.l => 'Litros (L)',
  FoodUnit.ml => 'Mililitros (ml)',
  FoodUnit.piece => 'Piezas',
  FoodUnit.can => 'Latas',
  FoodUnit.pack => 'Paquetes',
};

/// "2 L", "0.5 kg", "1 pieza", "3 latas".
String formatAmount(double quantity, FoodUnit unit) =>
    '${formatNumber(quantity)} ${unitLabel(unit, quantity)}';

/// "Queda 1 kg", "Quedan 2.5 kg" (concordancia del verbo con la cantidad).
String remainingLabel(double quantity, FoodUnit unit) {
  final verb = formatNumber(quantity) == '1' ? 'Queda' : 'Quedan';
  return '$verb ${formatAmount(quantity, unit)}';
}

String foodTypeLabel(FoodType type) => switch (type) {
  FoodType.grain => 'Granos y cereales',
  FoodType.legume => 'Leguminosas',
  FoodType.canned => 'Enlatados',
  FoodType.dairy => 'Lácteos',
  FoodType.produce => 'Frutas y verduras',
  FoodType.protein => 'Carnes y proteínas',
  FoodType.beverage => 'Bebidas',
  FoodType.other => 'Otros',
};

/// productId guarda el nombre del producto. Los ids tipo slug ("arroz",
/// "leche_entera") se muestran legibles ("Arroz", "Leche entera").
String productDisplayName(String productId) {
  final text = productId.trim().replaceAll(RegExp(r'[_-]+'), ' ');
  if (text.isEmpty) return productId;
  return text[0].toUpperCase() + text.substring(1);
}

DateTime _dateOnlyUtc(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

/// Días que le quedan hoy a un producto. daysUntilExpiration se cuenta desde
/// localTimestamp (cuando se registró el producto), así que se descuentan los
/// días que ya pasaron. Puede ser negativo si ya caducó.
int daysLeft(PantryItem item, {DateTime? today}) {
  final elapsed = _dateOnlyUtc(
    today ?? DateTime.now(),
  ).difference(_dateOnlyUtc(item.localTimestamp)).inDays;
  return item.daysUntilExpiration - elapsed;
}

/// Fecha en que caduca un producto de la despensa.
DateTime expirationDate(PantryItem item) =>
    item.localTimestamp.add(Duration(days: item.daysUntilExpiration));

/// "Caduca mañana", "Caduca en 3 días"… (tarjetas de la despensa).
String expirationLabel(int days) => switch (days) {
  < 0 => 'Caducado',
  0 => 'Caduca hoy',
  1 => 'Caduca mañana',
  _ => 'Caduca en $days días',
};

/// "Hoy", "1 día", "3 días" (etiquetas cortas).
String daysShortLabel(int days) => switch (days) {
  < 0 => 'Caducado',
  0 => 'Hoy',
  1 => '1 día',
  _ => '$days días',
};

/// dd/MM/yy, p. ej. "10/09/26".
String formatDateShort(DateTime date) =>
    '${_twoDigits(date.day)}/${_twoDigits(date.month)}/'
    '${_twoDigits(date.year % 100)}';

/// "10 sep 2026".
String formatDateLong(DateTime date) =>
    '${_twoDigits(date.day)} ${_monthsShort[date.month - 1]} ${date.year}';

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// "Exenta", "$25", "$25.50", "$1,500".
String formatRecoveryFee(double? fee) => fee == null ? 'Exenta' : formatMoney(fee);

/// Pesos: enteros sin decimales, fracciones con 2 decimales y separador de
/// miles con coma ("$1,500", "$25.50").
String formatMoney(double amount) {
  final cents = (amount * 100).round();
  final whole = (cents ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final fraction = cents % 100;
  return fraction == 0
      ? '\$$whole'
      : '\$$whole.${fraction.toString().padLeft(2, '0')}';
}

/// "Adulto", "Niño", "Niña".
String memberKindLabel(Member member) => switch (member.memberType) {
  MemberType.adult => 'Adulto',
  MemberType.child => switch (member.sex) {
    MemberSex.male => 'Niño',
    MemberSex.female => 'Niña',
    null => 'Niña o niño',
  },
};

String allergyLabel(Allergy allergy) => switch (allergy) {
  Allergy.dairy => 'Lácteos',
  Allergy.gluten => 'Gluten',
  Allergy.peanut => 'Cacahuate',
  Allergy.shellfish => 'Mariscos',
  Allergy.egg => 'Huevo',
  Allergy.soy => 'Soya',
};

/// "1 año", "38 años".
String formatAge(int age) => age == 1 ? '1 año' : '$age años';

/// "68 kg", "68.5 kg".
String formatWeight(double kg) => '${formatNumber(kg)} kg';
