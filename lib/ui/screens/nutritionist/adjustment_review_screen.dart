import 'dart:async';

import 'package:flutter/material.dart';

import '../../../application/bank_storage_facade.dart';
import '../../../data/models/pantry_item.dart';
import '../../../domain/models/recipe.dart';
import '../../../domain/models/recipe_adjustment.dart';
import '../../../domain/recipe_adjustment.dart';
import '../../formatting.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/danger_buttons.dart';
import '../../widgets/pill.dart';
import '../session/step_up_sheet.dart';
import 'adjustment_queue.dart';

/// Sin conexión Firestore deja la escritura en cola y el Future no termina
/// hasta que llega al servidor: pasado este tiempo se da por guardada en el
/// dispositivo.
const _saveTimeout = Duration(seconds: 8);

/// Lo que confirma la palomita cuando se decide. Si la decisión quedó en cola
/// sin conexión, [failedLater] termina en true si el servidor la rechaza al
/// sincronizar, y entonces se avisa con [lateFailure].
typedef _Decided = ({
  String heading,
  String message,
  Future<bool>? failedLater,
  String lateFailure,
});

/// Abre la revisión de [item]. Si se aprueba o se rechaza, la revisión se
/// cierra y se confirma aquí con la palomita: con [context] de la lista, porque
/// la tarjeta ya no está.
///
/// Los parámetros opcionales son para las pruebas: por omisión decide con
/// [BankStorageFacade] y confirma con la contraseña ([ensureRecentSignIn]).
Future<void> openAdjustmentReview(
  BuildContext context, {
  required AdjustmentQueueItem item,
  required String reviewerUid,
  Future<void> Function(String adjustmentId)? approveAdjustment,
  Future<void> Function(String adjustmentId, String reason)? rejectAdjustment,
  Future<bool> Function(BuildContext context)? confirmIdentity,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final decided = await Navigator.of(context).push<_Decided>(
    MaterialPageRoute(
      builder: (_) => AdjustmentReviewScreen(
        item: item,
        reviewerUid: reviewerUid,
        approveAdjustment: approveAdjustment,
        rejectAdjustment: rejectAdjustment,
        confirmIdentity: confirmIdentity,
      ),
    ),
  );
  if (decided == null) return;
  if (context.mounted) {
    await showSuccessSheet(
      context,
      title: 'Adaptaciones por revisar',
      heading: decided.heading,
      message: decided.message,
    );
  }
  // Un rechazo del servidor que llega con la palomita abierta quedaría
  // debajo de ella: se avisa al cerrarla, o cuando llegue.
  final failedLater = decided.failedLater;
  if (failedLater != null && await failedLater) {
    _showSnack(messenger, decided.lateFailure);
  }
}

/// La revisión de una adaptación pendiente: la receta publicada, el hogar
/// (tamaño y alergias, sin nombres), qué cambia y por qué, y cómo quedan los
/// ingredientes. Si la familia nunca la vería, lo avisa y solo deja
/// rechazarla. Aprobar y rechazar piden una sesión reciente (firestore.rules:
/// recentlySignedIn) y no se deshacen.
class AdjustmentReviewScreen extends StatefulWidget {
  const AdjustmentReviewScreen({
    super.key,
    required this.item,
    required this.reviewerUid,
    this.approveAdjustment,
    this.rejectAdjustment,
    this.confirmIdentity,
  });

  final AdjustmentQueueItem item;

  /// El uid del nutriólogo, que firma la decisión.
  final String reviewerUid;
  final Future<void> Function(String adjustmentId)? approveAdjustment;
  final Future<void> Function(String adjustmentId, String reason)?
  rejectAdjustment;
  final Future<bool> Function(BuildContext context)? confirmIdentity;

  @override
  State<AdjustmentReviewScreen> createState() => _AdjustmentReviewScreenState();
}

enum _Decision { approve, reject }

class _AdjustmentReviewScreenState extends State<AdjustmentReviewScreen> {
  /// Hay una decisión en curso, desde su sheet hasta que se guarda: un segundo
  /// toque no abre otra.
  bool _deciding = false;

  /// La que se está guardando: deshabilita los dos botones y muestra su
  /// spinner.
  _Decision? _saving;

  AdjustmentQueueItem get item => widget.item;

  Future<bool> _confirmIdentity() =>
      (widget.confirmIdentity ?? ensureRecentSignIn)(context);

  Future<void> _approve() => _decide(() async {
    final name = item.quotedName;
    final confirmed = await showAppBottomSheet<bool>(
      context,
      enableDrag: false,
      builder: (_) => _ApproveSheet(quotedName: name),
    );
    if (confirmed != true || !mounted) return;
    if (!await _confirmIdentity() || !mounted) return;
    final approve =
        widget.approveAdjustment ??
        (id) async {
          await BankStorageFacade().approveAdjustment(
            id,
            reviewerUid: widget.reviewerUid,
          );
        };
    await _save(
      _Decision.approve,
      () => approve(item.adjustment.id),
      heading: 'Adaptación aprobada',
      done: 'La familia ya verá la versión adaptada de $name.',
      offline:
          'La aprobación de $name se enviará cuando vuelva la conexión. Si '
          'tarda más de unos minutos, tendrás que revisarla otra vez.',
      failed: 'No se pudo aprobar la adaptación de $name. Intenta de nuevo.',
    );
  });

  Future<void> _reject() => _decide(() async {
    final name = item.quotedName;
    final reason = await showAppBottomSheet<String>(
      context,
      enableDrag: false,
      builder: (_) => _RejectSheet(
        quotedName: name,
        // Solo cuando el motivo es seguro. Una receta en revisión o en
        // borrador puede volver a publicarse igual, y entonces la adaptación
        // serviría: rechazarla la quita para siempre.
        initialReason: switch (item.staleness) {
          AdjustmentStaleness.changed =>
            'La receta cambió y esta adaptación ya no aplica.',
          AdjustmentStaleness.unsafe =>
            'La adaptación todavía lleva un alérgeno del hogar.',
          _ => '',
        },
      ),
    );
    if (reason == null || !mounted) return;
    if (!await _confirmIdentity() || !mounted) return;
    final reject =
        widget.rejectAdjustment ??
        (id, reason) async {
          await BankStorageFacade().rejectAdjustment(
            id,
            reviewerUid: widget.reviewerUid,
            reason: reason,
          );
        };
    await _save(
      _Decision.reject,
      () => reject(item.adjustment.id, reason),
      heading: 'Adaptación rechazada',
      done: 'La familia seguirá viendo la receta original de $name.',
      offline:
          'El rechazo de $name se enviará cuando vuelva la conexión. Si tarda '
          'más de unos minutos, tendrás que revisarla otra vez.',
      failed: 'No se pudo rechazar la adaptación de $name. Intenta de nuevo.',
    );
  });

  /// Una decisión a la vez, aunque se toque dos veces mientras se cierra un
  /// sheet.
  Future<void> _decide(Future<void> Function() decision) async {
    if (_deciding) return;
    _deciding = true;
    try {
      await decision();
    } finally {
      _deciding = false;
    }
  }

  /// Guarda la decisión con [write]. Si el servidor la confirma, o si queda en
  /// cola sin conexión, cierra la revisión y la lista lo confirma; si falla,
  /// se queda aquí con un snackbar.
  Future<void> _save(
    _Decision decision,
    Future<void> Function() write, {
    required String heading,
    required String done,
    required String offline,
    required String failed,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final lateFailure =
        'No se guardó la decisión sobre ${item.quotedName}. Vuelve a '
        'revisarla.';
    setState(() => _saving = decision);
    // Un error antes del primer await (p. ej. un ArgumentError) también llega
    // como Future fallido.
    final saved = Future.sync(write);
    String message;
    Future<bool>? failedLater;
    try {
      await saved.timeout(_saveTimeout);
      message = done;
    } on TimeoutException {
      // Si al sincronizar el servidor la rechaza (p. ej. la sesión ya no es
      // reciente), la adaptación vuelve a la lista: se avisa.
      failedLater = saved.then((_) => false, onError: (Object _) => true);
      message = offline;
    } catch (_) {
      if (mounted) setState(() => _saving = null);
      _showSnack(messenger, failed);
      return;
    }
    if (!mounted) {
      // Sin la revisión no hay palomita, pero el aviso sigue haciendo falta.
      if (failedLater != null) {
        unawaited(
          failedLater.then((failed) {
            if (failed) _showSnack(messenger, lateFailure);
          }),
        );
      }
      return;
    }
    Navigator.of(context).pop<_Decided>((
      heading: heading,
      message: message,
      failedLater: failedLater,
      lateFailure: lateFailure,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final adjustment = item.adjustment;
    final recipe = item.recipe;
    final warning = _warning(item);
    final saving = _saving;

    return PopScope(
      // Mientras se guarda no se sale: el resultado se confirma al terminar.
      canPop: saving == null,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            const _Header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  Text(item.title, style: AppText.baloo(24, 30)),
                  if (recipe != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _meta(recipe),
                      style: AppText.nunito(
                        15,
                        22.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _HouseholdBox(item),
                  const SizedBox(height: 20),
                  const _SectionTitle('Cambios'),
                  for (final change in adjustment.changes) ...[
                    const SizedBox(height: 8),
                    _ChangeRow(
                      title: item.changeTitle(change),
                      detail: _changeDetail(item, change),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const _SectionTitle('Ingredientes de la adaptación'),
                  for (final (ingredient, replaced) in _withReplaced(
                    adjustment,
                  )) ...[
                    const SizedBox(height: 8),
                    _IngredientRow(ingredient, replaced: replaced),
                  ],
                  if (recipe != null && recipe.steps.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const _SectionTitle('Preparación'),
                    for (final (index, step) in recipe.steps.indexed) ...[
                      SizedBox(height: index == 0 ? 8 : 12),
                      _StepRow(number: index + 1, text: step),
                    ],
                  ],
                  const SizedBox(height: 20),
                  if (warning != null) ...[
                    InfoBanner(
                      message: warning,
                      background: AppColors.warningSoft,
                      foreground: AppColors.warningText,
                    ),
                    const SizedBox(height: 16),
                  ],
                  // El spinner del botón no tiene texto: se nombra aquí.
                  Semantics(
                    container: true,
                    label: saving == _Decision.approve
                        ? 'Aprobando la adaptación'
                        : null,
                    child: PrimaryButton(
                      label: 'Aprobar adaptación',
                      icon: AppIcons.check,
                      loading: saving == _Decision.approve,
                      // Si la familia nunca la vería, aprobarla no sirve y no
                      // se puede deshacer.
                      onPressed: saving == null && item.staleness == null
                          ? _approve
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    container: true,
                    label: saving == _Decision.reject
                        ? 'Rechazando la adaptación'
                        : null,
                    child: DangerButton(
                      label: 'Rechazar con motivo',
                      loading: saving == _Decision.reject,
                      onPressed: saving == null ? _reject : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "10 min · 2 porciones · 180 kcal por porción", como en las recetas por
  /// revisar.
  static String _meta(Recipe recipe) => [
    '${recipe.prepTimeMinutes} min',
    recipe.servings == 1 ? '1 porción' : '${recipe.servings} porciones',
    if (recipe.caloriesPerServing > 0)
      '${recipe.caloriesPerServing} kcal por porción',
  ].join(' · ');

  /// Por qué no se puede aprobar ahora, o null si se puede.
  static String? _warning(AdjustmentQueueItem item) => switch (item.staleness) {
    null => null,
    AdjustmentStaleness.changed =>
      'La receta cambió después de esta sugerencia y la familia ya no la '
          'vería. Puedes rechazarla; cuando la familia vuelva a abrir la '
          'receta se sugerirá otra.',
    AdjustmentStaleness.inReview =>
      'La receta está en "Recetas por revisar". Si la apruebas sin cambios, '
          'después podrás aprobar esta adaptación.',
    AdjustmentStaleness.unavailable =>
      'La receta no está publicada ahora: está en borrador o se borró. Si se '
          'vuelve a publicar sin cambios, podrás aprobar esta adaptación.',
    AdjustmentStaleness.unsafe =>
      'Esta adaptación todavía lleva un ingrediente con un alérgeno del hogar '
          '(${item.allergenIngredient}). Recházala.',
  };

  /// "Para 4 integrantes" o, de una sustitución, su motivo: "Por alergia a
  /// lácteos".
  static String? _changeDetail(
    AdjustmentQueueItem item,
    AdjustmentChange change,
  ) {
    if (change.kind == AdjustmentChange.kindPortions) {
      return 'Para ${item.householdMembers}';
    }
    final reason = change.reason.trim();
    if (reason.isEmpty) return null;
    return 'Por ${reason[0].toLowerCase()}${reason.substring(1)}';
  }

  /// Los ingredientes de la adaptación, cada uno con el que reemplaza si
  /// salió de una sustitución. Las sustituciones se toman en orden, así que
  /// dos ingredientes con el mismo sustituto no se confunden.
  static List<(RecipeIngredient, String?)> _withReplaced(
    RecipeAdjustment adjustment,
  ) {
    final substitutions = [
      for (final change in adjustment.changes)
        if (change.kind == AdjustmentChange.kindSubstitution &&
            change.from != null)
          change,
    ];
    final rows = <(RecipeIngredient, String?)>[];
    for (final ingredient in adjustment.ingredients) {
      final index = substitutions.indexWhere(
        (change) => change.to == ingredient.productName,
      );
      rows.add((
        ingredient,
        index < 0 ? null : substitutions.removeAt(index).from,
      ));
    }
    return rows;
  }
}

void _showSnack(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Confirma la aprobación, que no se deshace. Regresa true.
class _ApproveSheet extends StatelessWidget {
  const _ApproveSheet({required this.quotedName});

  final String quotedName;

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: 'Aprobar adaptación',
      body: Text(
        'La familia verá la versión adaptada de $quotedName en sus recetas y '
        'en su plan de comidas. No se puede deshacer.',
        style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
      ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrimaryButton(
            label: 'Aprobar adaptación',
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: 8),
          SecondaryButton(
            label: 'Volver',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// Pide el motivo del rechazo, obligatorio, y lo regresa sin espacios de más.
class _RejectSheet extends StatefulWidget {
  const _RejectSheet({required this.quotedName, required this.initialReason});

  final String quotedName;

  /// El motivo ya escrito, para cuando la receta ya no es la misma.
  final String initialReason;

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  late final TextEditingController _reason;

  @override
  void initState() {
    super.initState();
    _reason = TextEditingController(text: widget.initialReason);
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// Como en las reglas: de 1 a 300 caracteres sin los espacios de las orillas.
  bool get _valid {
    final reason = _reason.text.trim();
    return reason.isNotEmpty &&
        reason.length <= RecipeAdjustment.maxReasonLength;
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: 'Rechazar adaptación',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'La familia seguirá viendo la receta original de '
            '${widget.quotedName}. Escribe el motivo; se guarda con la '
            'adaptación y la app no se lo muestra a la familia.',
            style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _reason,
            hint: 'Ej. La sustitución no va con esta receta.',
            textCapitalization: TextCapitalization.sentences,
            minLines: 3,
            maxLines: 5,
            maxLength: RecipeAdjustment.maxReasonLength,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      footer: DangerButton(
        label: 'Rechazar adaptación',
        onPressed: _valid
            ? () => Navigator.of(context).pop(_reason.text.trim())
            : null,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              button: true,
              child: InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                customBorder: const StadiumBorder(),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppIcon(AppIcons.arrowLeft, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Volver a la lista',
                            style: AppText.nunito(
                              16,
                              24,
                              weight: FontWeight.w700,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El hogar para el que se sugirió y lo que verá la familia si se aprueba.
class _HouseholdBox extends StatelessWidget {
  const _HouseholdBox(this.item);

  final AdjustmentQueueItem item;

  @override
  Widget build(BuildContext context) {
    final text = AppText.nunito(15, 22.5);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Adaptación para un hogar de ${item.householdMembers}',
            style: AppText.nunito(
              15,
              22.5,
              weight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(item.allergiesLabel, style: text),
          const SizedBox(height: 8),
          Text(
            'Lo que verá la familia: ${item.adjustment.summary}',
            style: text,
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppText.baloo(19, 28.5));
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.title, required this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppText.nunito(16, 24, weight: FontWeight.w700)),
          if (detail != null)
            Text(
              detail,
              style: AppText.nunito(14, 21, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow(this.ingredient, {required this.replaced});

  final RecipeIngredient ingredient;

  /// El ingrediente de la receta que este reemplaza, si es una sustitución.
  final String? replaced;

  @override
  Widget build(BuildContext context) {
    final replaced = this.replaced;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      // Con letra grande la cantidad baja en vez de partir el nombre.
      child: PillRow(
        leading: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ingredient.productName, style: AppText.nunito(16, 24)),
            if (replaced != null)
              Text(
                'En lugar de $replaced',
                style: AppText.nunito(14, 21, color: AppColors.textMuted),
              ),
          ],
        ),
        trailing: Text(
          _amount(ingredient),
          style: AppText.nunito(15, 22.5, weight: FontWeight.w700),
        ),
      ),
    );
  }

  /// "0.25 kg", "2 latas"; una unidad que no se reconoce va como está (igual
  /// que en las recetas por revisar).
  static String _amount(RecipeIngredient ingredient) {
    final unit = FoodUnit.values
        .where((option) => option.name == ingredient.unit.trim().toLowerCase())
        .firstOrNull;
    return unit == null
        ? '${formatNumber(ingredient.quantity)} ${ingredient.unit}'
        : formatAmount(ingredient.quantity, unit);
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    // El círculo crece con la letra para que el número quepa.
    final size = MediaQuery.textScalerOf(context).scale(32);

    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: AppText.baloo(16, 24, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(text, style: AppText.nunito(16, 22)),
            ),
          ),
        ],
      ),
    );
  }
}
