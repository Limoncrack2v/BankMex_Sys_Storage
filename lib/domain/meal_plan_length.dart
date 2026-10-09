/// Cuántos días abarca el plan de comidas de una familia, según su próxima
/// entrega (families/{familyId}.nextDeliveryDate).
class MealPlanLength {
  static const weekly = 7;
  static const biweekly = 14;

  /// Semanal si la próxima entrega es en 7 días o menos y quincenal si falta
  /// más, para que el plan alcance hasta que llegue la siguiente despensa.
  /// Sin entrega programada, o si su fecha ya pasó, es semanal. Cuenta días
  /// de calendario: la hora no importa.
  static int daysFor({DateTime? nextDelivery, DateTime? now}) {
    if (nextDelivery == null) return weekly;
    final clock = now ?? DateTime.now();
    final daysLeft = _dateOnly(nextDelivery)
        .difference(_dateOnly(clock))
        .inDays;
    return daysLeft > weekly ? biweekly : weekly;
  }

  // En UTC para que un cambio de horario no altere la cuenta de días.
  static DateTime _dateOnly(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);
}
