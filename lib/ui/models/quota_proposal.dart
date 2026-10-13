/// Qué hace el formulario de entregas con la cuota al elegir una familia.
enum QuotaOnSelect {
  /// Es la familia de la última propuesta: no se toca nada.
  keep,

  /// Familia distinta y el staff no ha escrito nada: se propone su cuota.
  propose,

  /// Familia distinta y el staff ya había escrito: se propone y se avisa.
  proposeAndWarn,
}

/// [proposedFor] es la familia de la última propuesta (null si no hay),
/// [selected] la recién elegida y [edited] si el staff tocó la cuota, Exenta
/// o la justificación desde esa propuesta.
QuotaOnSelect quotaOnSelect({
  required String? proposedFor,
  required String selected,
  required bool edited,
}) {
  return selected == proposedFor
      ? QuotaOnSelect.keep
      : !edited
      ? QuotaOnSelect.propose
      : QuotaOnSelect.proposeAndWarn;
}
