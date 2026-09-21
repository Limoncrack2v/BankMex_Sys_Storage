import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/pantry_item.dart';
import '../../../data/repositories/pantry_repository.dart';
import '../../formatting.dart';
import '../../models/expiration_urgency.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/pill.dart';

/// "Registrar consumo": la familia indica cuánto usó de cada producto de
/// [items] y se descuenta de su despensa. Después de guardar, el mismo sheet
/// muestra la confirmación.
Future<void> showConsumptionSheet(
  BuildContext context, {
  required String familyId,
  required List<PantryItem> items,
}) {
  return showAppBottomSheet<void>(
    context,
    // Arrastrar para cerrar ignora AppSheet.busy; así no se cierra a medio
    // guardar.
    enableDrag: false,
    builder: (_) => _ConsumptionSheet(familyId: familyId, items: items),
  );
}

/// "Se actualizó tu despensa con el consumo de 2 productos."
String consumptionSavedMessage(int count) =>
    'Se actualizó tu despensa con el consumo de $count '
    '${count == 1 ? 'producto' : 'productos'}.';

const _title = 'Registrar consumo';
const _focusRing = Color(0x4D2E7D32);
const _epsilon = 1e-9;

// Sin conexión, Firestore aplica el cambio en el dispositivo (la despensa se
// actualiza al instante) pero el guardado no termina hasta volver a estar en
// línea. Pasado este tiempo se da por guardado y se sincroniza después.
const _saveTimeout = Duration(seconds: 4);
const _pendingSyncNote = 'Se sincronizará cuando haya conexión.';
const _lateErrorMessage =
    'No se pudo guardar el consumo. Revisa tu despensa e intenta de nuevo.';

// En el Figma el sheet de registro mide la pantalla menos 56 px. El cuerpo
// ocupa lo que dejan el header (73), el pie (93) y su propio padding (40).
const _sheetTopGap = 56.0;
const _sheetChrome = 73.0 + 93.0 + 40.0;

/// Cuánto sube o baja cada toque del stepper según la unidad.
double _stepFor(FoodUnit unit) => switch (unit) {
  FoodUnit.kg || FoodUnit.l => 0.5,
  FoodUnit.g => 100,
  FoodUnit.ml => 250,
  FoodUnit.piece || FoodUnit.can || FoodUnit.pack => 1,
};

/// Minúsculas y sin acentos, para buscar "platano" y encontrar "Plátano".
String _searchKey(String text) {
  const accented = 'áàäâéèëêíìïîóòöôúùüûñ';
  const plain = 'aaaaeeeeiiiioooouuuun';
  final buffer = StringBuffer();
  for (final char in text.toLowerCase().trim().split('')) {
    final index = accented.indexOf(char);
    buffer.write(index < 0 ? char : plain[index]);
  }
  return buffer.toString().replaceAll(RegExp('[̀-ͯ]'), '');
}

class _ConsumptionSheet extends StatefulWidget {
  const _ConsumptionSheet({required this.familyId, required this.items});

  final String familyId;
  final List<PantryItem> items;

  @override
  State<_ConsumptionSheet> createState() => _ConsumptionSheetState();
}

class _ConsumptionSheetState extends State<_ConsumptionSheet> {
  final _search = TextEditingController();
  final _amounts = <String, double>{};
  String? _focusedId;
  bool _saving = false;
  String? _error;
  int? _savedCount;

  /// El guardado quedó en el dispositivo y se sincroniza después.
  bool _pendingSync = false;

  bool get _canSave => _amounts.values.any((amount) => amount > 0);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  double _amountOf(PantryItem item) => _amounts[item.pantryItemId] ?? 0;

  void _focus(PantryItem item) {
    if (_focusedId != item.pantryItemId) {
      setState(() => _focusedId = item.pantryItemId);
    }
  }

  void _increase(PantryItem item) {
    final step = _stepFor(item.unit);
    final steps = (_amountOf(item) / step + _epsilon).floor() + 1;
    _setAmount(item, math.min(steps * step, item.quantity));
  }

  // Si el monto quedó fuera de la escala (tope en "Quedan"), baja al escalón
  // anterior: 2.3 kg -> 2 kg.
  void _decrease(PantryItem item) {
    final step = _stepFor(item.unit);
    final steps = (_amountOf(item) / step - _epsilon).ceil() - 1;
    _setAmount(item, math.max(0, steps * step));
  }

  Future<void> _editAmount(PantryItem item) async {
    if (_saving) return;
    _focus(item);
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => _AmountDialog(item: item, initial: _amountOf(item)),
    );
    if (amount == null || !mounted) return;
    _setAmount(item, amount);
  }

  void _setAmount(PantryItem item, double amount) {
    setState(() {
      _focusedId = item.pantryItemId;
      _amounts[item.pantryItemId] = amount;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final entries = [
      for (final item in widget.items)
        if (_amountOf(item) > 0) (item: item, amount: _amountOf(item)),
    ];
    if (entries.isEmpty) return;

    // Se toma antes de esperar: el error de sincronización puede llegar
    // cuando el sheet ya se cerró.
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    final bool synced;
    try {
      synced = await _awaitSave(
        PantryRepository().registerConsumption(widget.familyId, entries),
        onLateError: () => _showSnack(messenger, _lateErrorMessage),
      );
    } catch (e) {
      final message = _errorMessage(e);
      if (!mounted) {
        _showSnack(messenger, message);
        return;
      }
      setState(() {
        _saving = false;
        _error = message;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _savedCount = entries.length;
      _pendingSync = !synced;
    });
  }

  String _errorMessage(Object error) {
    if (error is FirebaseException && error.code == 'not-found') {
      return 'Uno de los productos ya no está en tu despensa. Cierra y vuelve '
          'a abrir Registrar consumo.';
    }
    // Las reglas rechazan que un producto quede en 0 o menos con un descuento
    // parcial: pasa si otro dispositivo registró consumo mientras tanto.
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'Tu despensa cambió mientras registrabas el consumo. Cierra y '
          'vuelve a abrir Registrar consumo.';
    }
    if (error is ArgumentError && error.message is String) {
      final message = error.message as String;
      return message.endsWith('.') ? message : '$message.';
    }
    return 'No se pudo registrar el consumo. Revisa tu conexión e intenta de '
        'nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    final savedCount = _savedCount;
    if (savedCount != null) {
      return AppSheet(
        title: _title,
        body: SuccessContent(
          heading: 'Consumo registrado',
          message: _pendingSync
              ? '${consumptionSavedMessage(savedCount)} $_pendingSyncNote'
              : consumptionSavedMessage(savedCount),
          onDone: () => Navigator.of(context).pop(),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bodyMinHeight = constraints.hasBoundedHeight
            ? math.max(
                0.0,
                constraints.maxHeight -
                    MediaQuery.viewInsetsOf(context).bottom -
                    _sheetTopGap -
                    _sheetChrome,
              )
            : 0.0;

        return AppSheet(
          title: _title,
          busy: _saving,
          body: ConstrainedBox(
            constraints: BoxConstraints(minHeight: bodyMinHeight),
            child: AbsorbPointer(absorbing: _saving, child: _buildBody()),
          ),
          footer: _buildFooter(),
        );
      },
    );
  }

  Widget _buildBody() {
    final query = _searchKey(_search.text);
    final visible = [
      for (final item in widget.items)
        if (query.isEmpty ||
            _searchKey(productDisplayName(item.productId)).contains(query))
          item,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _search,
          hint: 'Buscar producto…',
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Text(
          'Indica cuánto consumió tu familia de cada producto.',
          style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
        ),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(
              'Ningún producto coincide con tu búsqueda.',
              textAlign: TextAlign.center,
              style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
            ),
          ),
        for (final item in visible) ...[
          const SizedBox(height: 12),
          _ConsumptionCard(
            item: item,
            amount: _amountOf(item),
            focused: _focusedId == item.pantryItemId,
            onTap: () => _focus(item),
            onDecrease: () => _decrease(item),
            onIncrease: () => _increase(item),
            onEditAmount: () => _editAmount(item),
          ),
        ],
      ],
    );
  }

  Widget _buildFooter() {
    final error = _error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (error != null) ...[
          InfoBanner(
            message: error,
            background: AppColors.dangerSoft,
            foreground: AppColors.dangerText,
          ),
          const SizedBox(height: 12),
        ],
        PrimaryButton(
          label: 'Guardar consumo',
          icon: AppIcons.check,
          loading: _saving,
          onPressed: _canSave ? _save : null,
        ),
      ],
    );
  }
}

class _ConsumptionCard extends StatelessWidget {
  const _ConsumptionCard({
    required this.item,
    required this.amount,
    required this.focused,
    required this.onTap,
    required this.onDecrease,
    required this.onIncrease,
    required this.onEditAmount,
  });

  final PantryItem item;
  final double amount;
  final bool focused;
  final VoidCallback onTap;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  /// Abre el diálogo para escribir la cantidad exacta.
  final VoidCallback onEditAmount;

  @override
  Widget build(BuildContext context) {
    final name = productDisplayName(item.productId);
    final days = daysLeft(item);
    final urgency = ExpirationUrgency.fromDays(days);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
            color: focused ? AppColors.primary : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: focused
              ? const [BoxShadow(color: _focusRing, spreadRadius: 2)]
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.baloo(17, 21.25, weight: FontWeight.w600),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          remainingLabel(item.quantity, item.unit),
                          style: AppText.nunito(
                            14,
                            21,
                            color: AppColors.textMuted,
                          ),
                        ),
                        Pill(
                          label: daysShortLabel(days),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          fontSize: 13,
                          lineHeight: 19.5,
                          background: urgency.background,
                          foreground: urgency.foreground,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _StepperButton(
              icon: AppIcons.stepperMinus,
              label: 'Quitar consumo de $name',
              onTap: amount > 0 ? onDecrease : null,
            ),
            const SizedBox(width: 8),
            _AmountButton(
              label: formatAmount(amount, item.unit),
              semanticsLabel:
                  'Consumo de $name: ${formatAmount(amount, item.unit)}',
              onTap: onEditAmount,
            ),
            const SizedBox(width: 8),
            _StepperButton(
              icon: AppIcons.stepperPlus,
              label: 'Agregar consumo de $name',
              onTap: amount < item.quantity - _epsilon ? onIncrease : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Botón de 44x44 del stepper; deshabilitado se ve al 40 % y no responde.
class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String icon;
  final String label;
  final VoidCallback? onTap;

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
    side: BorderSide(color: AppColors.border, width: 2),
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Material(
          color: Colors.transparent,
          shape: _shape,
          child: InkWell(
            onTap: onTap,
            customBorder: _shape,
            child: SizedBox.square(
              dimension: 44,
              child: Center(child: AppIcon(icon, size: 20)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cantidad entre los steppers. Al tocarla se escribe la cantidad exacta
/// (para consumos menores al paso del stepper, p. ej. 250 g de 1 kg).
class _AmountButton extends StatelessWidget {
  const _AmountButton({
    required this.label,
    required this.semanticsLabel,
    required this.onTap,
  });

  final String label;
  final String semanticsLabel;
  final VoidCallback onTap;

  static const _hint = 'Escribir cantidad';
  static const _radius = BorderRadius.all(Radius.circular(8));

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: semanticsLabel,
      hint: _hint,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: _hint,
        excludeFromSemantics: true,
        // Material propio para que el efecto del toque se vea sobre la
        // tarjeta blanca, igual que en los steppers.
        child: Material(
          color: Colors.transparent,
          borderRadius: _radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: _radius,
            child: SizedBox(
              width: 64,
              height: 44,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  // Subrayado punteado: indica que la cantidad se puede
                  // editar.
                  child: Text(
                    label,
                    maxLines: 1,
                    style: AppText.nunito(15, 22.5, weight: FontWeight.w700)
                        .copyWith(
                          decoration: TextDecoration.underline,
                          decorationStyle: TextDecorationStyle.dotted,
                          decorationColor: AppColors.textMuted,
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

/// Diálogo para escribir cuánto se consumió de [item], en su unidad. Acepta
/// "0,25" y "0.25". Regresa la cantidad, o null si se cancela.
class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.item, required this.initial});

  final PantryItem item;
  final double initial;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  String? _error;

  // Antes del primer "Usar cantidad" solo se avisa si el número ya escrito
  // está fuera de rango, no mientras el campo está vacío o a medio escribir.
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    final text = widget.initial > 0 ? formatNumber(widget.initial) : '';
    _controller = TextEditingController(text: text)
      ..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    final error = _checkAmount(text, widget.item).error;
    final complete = _parseDecimal(text) != null;
    setState(() => _error = _attempted || complete ? error : null);
  }

  void _submit() {
    final (:value, :error) = _checkAmount(_controller.text, widget.item);
    if (value == null) {
      setState(() {
        _attempted = true;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final error = _error;

    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Escribir cantidad', style: AppText.baloo(20, 30)),
            const SizedBox(height: 4),
            Text(
              '${productDisplayName(item.productId)}. '
              '${remainingLabel(item.quantity, item.unit)}.',
              style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: 'Cantidad consumida (${unitLabel(item.unit, 2)})',
              child: AppTextField(
                controller: _controller,
                focusNode: _focusNode,
                hint: '0',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                maxLength: 9,
                onChanged: _onChanged,
                onSubmitted: (_) => _submit(),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 6),
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: AppText.nunito(14, 21, color: AppColors.dangerText),
                ),
              ),
            ],
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Usar cantidad',
              icon: AppIcons.check,
              onPressed: _submit,
            ),
            const SizedBox(height: 8),
            Center(
              child: TextLinkButton(
                label: 'Cancelar',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Valida lo escrito en el diálogo: un número de 0 a lo que queda de [item].
({double? value, String? error}) _checkAmount(String text, PantryItem item) {
  if (text.trim().isEmpty) {
    return (value: null, error: 'Escribe cuánto consumiste.');
  }
  final parsed = _parseDecimal(text);
  if (parsed == null || parsed < 0) {
    return (value: null, error: 'Escribe un número válido, p. ej. 0.25.');
  }
  // Misma precisión con la que se muestran las cantidades (3 decimales).
  final value = (parsed * 1000).round() / 1000;
  if (value > item.quantity + _epsilon) {
    return (
      value: null,
      error:
          'No puedes registrar más de lo que queda '
          '(${formatAmount(item.quantity, item.unit)}).',
    );
  }
  return (value: math.min(value, item.quantity), error: null);
}

/// "2,5" y "2.5" valen lo mismo.
double? _parseDecimal(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  return value != null && value.isFinite ? value : null;
}

/// Espera [save] hasta [_saveTimeout]. Regresa true si llegó al servidor y
/// false si sigue pendiente (sin conexión el cambio ya quedó en el
/// dispositivo); si después falla al sincronizar, llama a [onLateError].
Future<bool> _awaitSave<T>(
  Future<T> save, {
  required VoidCallback onLateError,
}) async {
  try {
    await save.timeout(_saveTimeout);
    return true;
  } on TimeoutException {
    unawaited(save.then<void>((_) {}, onError: (Object _) => onLateError()));
    return false;
  }
}

void _showSnack(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
