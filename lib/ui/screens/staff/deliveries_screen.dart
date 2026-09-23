import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/delivery.dart';
import '../../../data/models/family.dart';
import '../../../data/models/pantry_item.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/delivery_repository.dart';
import '../../../data/repositories/family_repository.dart';
import '../../formatting.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/option_button.dart';
import '../../widgets/pill.dart';

/// Sin conexión, Firestore guarda el cambio en el dispositivo pero el commit
/// no termina hasta sincronizar. Pasado este tiempo se da por guardado y la
/// tabla lo muestra pendiente de sincronizar.
const _saveTimeout = Duration(seconds: 4);
const _maxRecoveryFee = 100000.0;
const _pendingSyncNote = 'Se sincronizará cuando haya conexión.';

/// Contenido de la pestaña Entregas del staff: registro de una entrega por
/// familia (con sus productos y caducidades) y tabla de entregas recientes.
class DeliveriesScreen extends StatefulWidget {
  const DeliveriesScreen({
    super.key,
    required this.session,
    required this.onRegisterAccount,
  });

  final AuthSession session;
  final VoidCallback onRegisterAccount;

  @override
  State<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends State<DeliveriesScreen> {
  late final Stream<List<Family>> _families;
  late final Stream<List<DeliveryWithSync>> _deliveries;


  @override
  void initState() {
    super.initState();
    _families = FamilyRepository().watchAllFamilies();
    _deliveries = DeliveryRepository().watchRecentDeliveries();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(),
          const SizedBox(height: 24),
          SecondaryButton(
            label: 'Registrar cuenta',
            icon: AppIcons.plus,
            onPressed: widget.onRegisterAccount,
          ),
          const SizedBox(height: 24),
          _DeliveryForm(families: _families),
          const SizedBox(height: 24),
          _DeliveriesTable(deliveries: _deliveries),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Entregas', style: AppText.baloo(22, 27.5)),
        const SizedBox(height: 2),
        Text(
          'Registra una entrega de despensa por familia.',
          style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Formulario
// ---------------------------------------------------------------------------

class _DeliveryForm extends StatefulWidget {
  const _DeliveryForm({required this.families});

  final Stream<List<Family>> families;

  @override
  State<_DeliveryForm> createState() => _DeliveryFormState();
}

class _DeliveryFormState extends State<_DeliveryForm> {
  final _familyText = TextEditingController();
  final _packages = TextEditingController(text: '1');
  final _fee = TextEditingController();
  final _justification = TextEditingController();
  final _notes = TextEditingController();

  Family? _family;
  DateTime? _date;
  bool _exempt = true;
  DeliveryStatus _status = DeliveryStatus.scheduled;
  List<_ProductDraft> _products = [_ProductDraft()];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _familyText.dispose();
    _packages.dispose();
    _fee.dispose();
    _justification.dispose();
    _notes.dispose();
    for (final product in _products) {
      product.dispose();
    }
    super.dispose();
  }

  int? get _packageCount {
    final value = int.tryParse(_packages.text.trim());
    if (value == null || value < 1 || value > Delivery.maxPackages) return null;
    return value;
  }

  double? get _feeAmount {
    final value = _parseDecimal(_fee.text);
    if (value == null || value < 0 || value > _maxRecoveryFee) return null;
    return value;
  }

  /// Lo que falta para poder registrar; null si el formulario está completo.
  String? get _missing {
    if (_family == null) return 'Selecciona una familia de la lista.';
    if (_date == null) return 'Elige la fecha de entrega.';
    if (_packageCount == null) {
      return 'Indica de 1 a ${Delivery.maxPackages} despensas.';
    }
    if (!_exempt && _feeAmount == null) {
      return 'Escribe la cuota de recuperación o márcala como Exenta.';
    }
    if (!_exempt && _justification.text.trim().isEmpty) {
      return 'Escribe la justificación de la cuota de recuperación.';
    }
    for (final product in _products) {
      final problem = _expirationProblem(product);
      if (problem != null) {
        return 'La caducidad de ${product.displayName} $problem.';
      }
    }
    if (!_products.every((product) => product.isComplete)) {
      return 'Cada producto necesita nombre, cantidad y fecha de caducidad.';
    }
    return null;
  }

  /// Primer día válido de caducidad: la fecha de entrega (o hoy, si la
  /// entrega es antes), para que los productos no lleguen caducados.
  DateTime get _minExpiration {
    final today = DateUtils.dateOnly(DateTime.now());
    final date = _date;
    return date != null && date.isAfter(today)
        ? DateUtils.dateOnly(date)
        : today;
  }

  /// Por qué la caducidad elegida ya no es válida (p. ej. se cambió la fecha
  /// de entrega a después de ella); null si está bien o aún no se elige.
  String? _expirationProblem(_ProductDraft product) {
    final expiration = product.expiration;
    if (expiration == null) return null;
    final date = _date;
    if (date != null && expiration.isBefore(DateUtils.dateOnly(date))) {
      return 'es anterior a la fecha de entrega';
    }
    if (expiration.isBefore(DateUtils.dateOnly(DateTime.now()))) {
      return 'ya pasó';
    }
    return null;
  }

  void _onEdited(String _) => setState(() {});

  void _toggleExempt() {
    setState(() {
      _exempt = !_exempt;
      if (_exempt) {
        _fee.clear();
        _justification.clear();
      }
    });
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? today,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 1, 12, 31),
      helpText: 'Fecha de entrega',
    );
    if (!mounted || picked == null) return;
    setState(() => _date = picked);
  }

  Future<void> _pickType(_ProductDraft product) async {
    FocusScope.of(context).unfocus();
    final picked = await _pickOption<FoodType>(
      context,
      title: 'Tipo de producto',
      options: FoodType.values,
      selected: product.type,
      labelOf: foodTypeLabel,
    );
    if (!mounted || picked == null) return;
    setState(() => product.type = picked);
  }

  Future<void> _pickUnit(_ProductDraft product) async {
    FocusScope.of(context).unfocus();
    final picked = await _pickOption<FoodUnit>(
      context,
      title: 'Unidad',
      options: FoodUnit.values,
      selected: product.unit,
      labelOf: unitName,
    );
    if (!mounted || picked == null) return;
    setState(() => product.unit = picked);
  }

  Future<void> _pickExpiration(_ProductDraft product) async {
    FocusScope.of(context).unfocus();
    final today = DateUtils.dateOnly(DateTime.now());
    final first = _minExpiration;
    final current = product.expiration;
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null || current.isBefore(first) ? first : current,
      firstDate: first,
      lastDate: DateTime(today.year + 10, 12, 31),
      helpText: 'Fecha de caducidad',
    );
    if (!mounted || picked == null) return;
    setState(() => product.expiration = picked);
  }

  void _addProduct() {
    setState(() => _products = [..._products, _ProductDraft()]);
  }

  void _removeProduct(_ProductDraft product) {
    setState(() => _products = [..._products]..remove(product));
    _disposeAfterFrame([product]);
  }

  /// Los campos de texto siguen montados hasta el siguiente frame.
  void _disposeAfterFrame(List<_ProductDraft> products) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final product in products) {
        product.dispose();
      }
    });
  }

  void _reset() {
    final previous = _products;
    setState(() {
      _familyText.clear();
      _family = null;
      _date = null;
      _packages.text = '1';
      _fee.clear();
      _exempt = true;
      _justification.clear();
      _status = DeliveryStatus.scheduled;
      _notes.clear();
      _products = [_ProductDraft()];
      _saving = false;
      _error = null;
    });
    _disposeAfterFrame(previous);
  }

  Future<void> _submit() async {
    if (_saving || _missing != null) return;
    FocusScope.of(context).unfocus();

    final family = _family!;
    final packages = _packageCount!;
    final delivery = Delivery(
      deliveryId: '',
      familyId: family.familyId,
      familyName: family.displayName,
      deliveryDate: _date!,
      packages: packages,
      recoveryFee: _exempt ? null : _feeAmount,
      justification: _exempt ? null : _justification.text.trim(),
      status: _status,
      notes: _notes.text.trim(),
      items: [for (final product in _products) product.toItem()],
      createdAt: DateTime.now(),
    );
    final invalid = delivery.validate();
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    final bool synced;
    try {
      final saved = await _awaitSave(
        DeliveryRepository().registerDelivery(delivery),
        onLateError: (_) => _showSnack(
          messenger,
          'No se pudo sincronizar la entrega de ${family.displayName}. '
          'Regístrala de nuevo.',
        ),
      );
      synced = saved.synced;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _saveErrorMessage(e);
      });
      return;
    }
    if (!mounted) return;

    _reset();
    final noun = packages == 1 ? 'despensa' : 'despensas';
    final message =
        'Se registró la entrega para ${family.displayName} ($packages $noun).';
    showSuccessSheet(
      context,
      title: 'Registrar entrega',
      heading: 'Entrega registrada',
      message: synced ? message : '$message $_pendingSyncNote',
    );
  }

  String _saveErrorMessage(Object error) {
    if (error is AuthException) return error.message;
    if (error is ArgumentError && error.message is String) {
      return error.message as String;
    }
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'Tu cuenta no tiene permiso para registrar esta entrega.';
    }
    return 'No se pudo registrar la entrega. Revisa tu conexión e intenta de '
        'nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    final missing = _missing;
    final error = _error;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AbsorbPointer(absorbing: _saving, child: _buildFields()),
          const SizedBox(height: 16),
          if (error != null) ...[
            InfoBanner(
              message: error,
              background: AppColors.dangerSoft,
              foreground: AppColors.dangerText,
            ),
            const SizedBox(height: 12),
          ],
          if (missing != null && !_saving) ...[
            _HelperText(missing),
            const SizedBox(height: 8),
          ],
          PrimaryButton(
            label: 'Registrar entrega',
            icon: AppIcons.check,
            loading: _saving,
            onPressed: missing == null ? _submit : null,
          ),
        ],
      ),
    );
  }

  Widget _buildFields() {
    final showPackagesError =
        _packages.text.trim().isNotEmpty && _packageCount == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabeledField(
          label: 'Familia',
          required: true,
          child: _FamilyCombobox(
            families: widget.families,
            controller: _familyText,
            selected: _family,
            onSelected: (family) => setState(() => _family = family),
          ),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Fecha de entrega',
          required: true,
          child: _PickerField(
            label: 'Fecha de entrega',
            value: _date == null ? null : formatDateShort(_date!),
            onTap: _pickDate,
          ),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Número de despensas',
          required: true,
          child: AppTextField(
            controller: _packages,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 3,
            onChanged: _onEdited,
          ),
        ),
        if (showPackagesError) ...[
          const SizedBox(height: 6),
          _HelperText(
            'Debe ser de 1 a ${Delivery.maxPackages}.',
            color: AppColors.dangerText,
          ),
        ],
        const SizedBox(height: 16),
        LabeledField(
          label: 'Cuota de recuperación',
          child: Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _fee,
                  hint: '0',
                  prefixText: r'$',
                  enabled: !_exempt,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  maxLength: 9,
                  onChanged: _onEdited,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: OptionButton(
                  label: 'Exenta',
                  selected: _exempt,
                  onTap: _toggleExempt,
                ),
              ),
            ],
          ),
        ),
        if (!_exempt) ...[
          const SizedBox(height: 16),
          LabeledField(
            label: 'Justificación',
            required: true,
            child: AppTextField(
              controller: _justification,
              hint: 'Motivo del monto (nivel de ingreso, tipo de entrega…)',
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 3,
              maxLength: 500,
              onChanged: _onEdited,
            ),
          ),
        ],
        const SizedBox(height: 16),
        LabeledField(
          label: 'Estado',
          child: Row(
            children: [
              Expanded(
                child: OptionButton(
                  label: 'Entregada',
                  selected: _status == DeliveryStatus.delivered,
                  onTap: () =>
                      setState(() => _status = DeliveryStatus.delivered),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OptionButton(
                  label: 'Programada',
                  selected: _status == DeliveryStatus.scheduled,
                  onTap: () =>
                      setState(() => _status = DeliveryStatus.scheduled),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        _HelperText(
          _status == DeliveryStatus.delivered
              ? 'Sus productos pasan a la despensa de la familia al '
                    'registrarla.'
              : 'Sus productos pasan a la despensa de la familia cuando la '
                    'marques como entregada.',
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Notas',
          child: AppTextField(
            controller: _notes,
            hint: 'Observaciones de la entrega…',
            textCapitalization: TextCapitalization.sentences,
            minLines: 3,
            maxLines: 5,
            maxLength: 1000,
          ),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Productos entregados', required: true),
        const SizedBox(height: 2),
        const _HelperText(
          'Agrega cada producto con su cantidad y fecha de caducidad.',
        ),
        for (final product in _products) ...[
          const SizedBox(height: 12),
          _ProductCard(
            key: ObjectKey(product),
            product: product,
            expirationProblem: _expirationProblem(product),
            onEdited: _onEdited,
            onPickType: () => _pickType(product),
            onPickUnit: () => _pickUnit(product),
            onPickExpiration: () => _pickExpiration(product),
            onRemove: _products.length > 1
                ? () => _removeProduct(product)
                : null,
          ),
        ],
        const SizedBox(height: 12),
        SecondaryButton(
          label: 'Agregar producto',
          icon: AppIcons.plus,
          onPressed: _products.length < Delivery.maxItems ? _addProduct : null,
        ),
      ],
    );
  }
}

/// Producto en captura dentro del formulario.
class _ProductDraft {
  final name = TextEditingController();
  final quantity = TextEditingController();
  FoodType type = FoodType.grain;
  FoodUnit unit = FoodUnit.kg;
  DateTime? expiration;

  double? get amount {
    final value = _parseDecimal(quantity.text);
    if (value == null || value <= 0 || value > PantryItem.maxQuantity) {
      return null;
    }
    return value;
  }

  bool get isComplete =>
      name.text.trim().isNotEmpty && amount != null && expiration != null;

  /// Nombre para los mensajes ("Arroz", o "un producto" si aún no tiene).
  String get displayName {
    final text = name.text.trim();
    return text.isEmpty ? 'un producto' : text;
  }

  DeliveryItem toItem() => DeliveryItem(
    productId: name.text.trim(),
    type: type,
    quantity: amount!,
    unit: unit,
    expirationDate: expiration!,
  );

  void dispose() {
    name.dispose();
    quantity.dispose();
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    super.key,
    required this.product,
    this.expirationProblem,
    required this.onEdited,
    required this.onPickType,
    required this.onPickUnit,
    required this.onPickExpiration,
    this.onRemove,
  });

  final _ProductDraft product;

  /// "es anterior a la fecha de entrega" o "ya pasó"; null si es válida.
  final String? expirationProblem;
  final ValueChanged<String> onEdited;
  final VoidCallback onPickType;
  final VoidCallback onPickUnit;
  final VoidCallback onPickExpiration;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final expiration = product.expiration;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: LabeledField(
                  label: 'Producto',
                  child: AppTextField(
                    controller: product.name,
                    hint: 'Ej. Arroz',
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    maxLength: DeliveryItem.maxNameLength,
                    onChanged: onEdited,
                  ),
                ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: Center(child: _RemoveButton(onTap: onRemove!)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          LabeledField(
            label: 'Tipo',
            child: _PickerField(
              label: 'Tipo',
              value: foodTypeLabel(product.type),
              showChevron: true,
              onTap: onPickType,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: LabeledField(
                  label: 'Cantidad',
                  child: AppTextField(
                    controller: product.quantity,
                    hint: '0',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    maxLength: 9,
                    onChanged: onEdited,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: LabeledField(
                  label: 'Unidad',
                  child: _PickerField(
                    label: 'Unidad',
                    value: unitLabel(product.unit, product.amount ?? 2),
                    showChevron: true,
                    onTap: onPickUnit,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LabeledField(
            label: 'Caducidad',
            child: _PickerField(
              label: 'Fecha de caducidad',
              value: expiration == null ? null : formatDateShort(expiration),
              hint: 'Elige la fecha',
              onTap: onPickExpiration,
            ),
          ),
          if (expirationProblem != null) ...[
            const SizedBox(height: 6),
            _HelperText(
              'La caducidad $expirationProblem.',
              color: AppColors.dangerText,
            ),
          ],
        ],
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Quitar producto',
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: const SizedBox.square(
            dimension: 40,
            child: Center(child: AppIcon(AppIcons.close, size: 20)),
          ),
        ),
      ),
    );
  }
}

/// Campo con el estilo de [AppTextField] que abre un selector al tocarlo
/// (fechas, tipo y unidad).
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    this.value,
    this.hint,
    this.showChevron = false,
    required this.onTap,
  });

  /// Nombre del campo para lectores de pantalla.
  final String label;
  final String? value;
  final String? hint;
  final bool showChevron;
  final VoidCallback onTap;

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
    side: BorderSide(color: AppColors.border, width: 2),
  );

  @override
  Widget build(BuildContext context) {
    final value = this.value;

    return Semantics(
      button: true,
      label: label,
      value: value,
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        shape: _shape,
        child: InkWell(
          onTap: onTap,
          customBorder: _shape,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value ?? hint ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.nunito(
                      16,
                      24,
                      color: value == null ? AppColors.hint : AppColors.text,
                    ),
                  ),
                ),
                if (showChevron) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 24,
                    color: AppColors.textMuted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HelperText extends StatelessWidget {
  const _HelperText(this.text, {this.color = AppColors.textMuted});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppText.nunito(14, 21, color: color));
  }
}

/// Lista de opciones en un bottom sheet (tipo de producto y unidad).
Future<T?> _pickOption<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required T selected,
  required String Function(T option) labelOf,
}) {
  return showAppBottomSheet<T>(
    context,
    builder: (sheetContext) => AppSheet(
      title: title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, option) in options.indexed) ...[
            if (index > 0) const SizedBox(height: 8),
            OptionButton(
              label: labelOf(option),
              selected: option == selected,
              onTap: () => Navigator.of(sheetContext).pop(option),
            ),
          ],
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Buscador de familia
// ---------------------------------------------------------------------------

const _listGap = 4.0;
const _listMaxHeight = 240.0;
const _listMinHeight = 96.0;
const _listShadow = [
  BoxShadow(
    color: Color(0x1A000000),
    offset: Offset(0, 10),
    blurRadius: 15,
    spreadRadius: -3,
  ),
  BoxShadow(
    color: Color(0x1A000000),
    offset: Offset(0, 4),
    blurRadius: 6,
    spreadRadius: -4,
  ),
];

/// Campo "Familia": al escribir filtra las familias registradas en una lista
/// flotante 4 px debajo del campo que se sobrepone a los campos siguientes.
class _FamilyCombobox extends StatefulWidget {
  const _FamilyCombobox({
    required this.families,
    required this.controller,
    required this.selected,
    required this.onSelected,
    this.excludeFamilyId,
  });

  final Stream<List<Family>> families;
  final TextEditingController controller;
  final Family? selected;
  final ValueChanged<Family?> onSelected;

  /// Familia que nunca aparece en la lista (al reasignar, la dueña actual de
  /// la entrega).
  final String? excludeFamilyId;

  @override
  State<_FamilyCombobox> createState() => _FamilyComboboxState();
}

class _FamilyComboboxState extends State<_FamilyCombobox> {
  final _overlay = OverlayPortalController();
  final _focus = FocusNode();
  final _tapGroup = Object();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focus.hasFocus) {
      _overlay.show();
    } else {
      _overlay.hide();
    }
  }

  void _open() {
    if (!_overlay.isShowing) _overlay.show();
  }

  /// Con una familia elegida se muestran todas para poder cambiarla.
  List<Family> _matches(List<Family> families) {
    if (widget.selected != null) return families;
    final query = _fold(widget.controller.text.trim());
    if (query.isEmpty) return families;
    return [
      for (final family in families)
        if (_fold('${family.displayName} ${family.address}').contains(query))
          family,
    ];
  }

  void _onChanged(String text) {
    final selected = widget.selected;
    if (selected != null && text != selected.displayName) {
      widget.onSelected(null);
    }
    _open();
    setState(() {});
  }

  void _select(Family family) {
    final name = family.displayName;
    widget.controller.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
    widget.onSelected(family);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Family>>(
      stream: widget.families,
      builder: (context, snapshot) {
        final excluded = widget.excludeFamilyId;
        final families = snapshot.data == null
            ? null
            : [
                for (final family in snapshot.data!)
                  if (family.familyId != excluded) family,
              ];
        final matches = families == null
            ? const <Family>[]
            : _matches(families);

        return TapRegion(
          groupId: _tapGroup,
          onTapOutside: (_) {
            if (_focus.hasFocus) _focus.unfocus();
          },
          child: OverlayPortal.overlayChildLayoutBuilder(
            controller: _overlay,
            overlayChildBuilder: (context, info) => _buildOverlay(
              context,
              info,
              _FamilyList(
                hasError: snapshot.hasError,
                families: families,
                // Los nombres repetidos se cuentan con todas las familias:
                // si la excluida es la tocaya, la otra igual lleva dirección.
                allFamilies: snapshot.data,
                matches: matches,
                emptyMessage: excluded == null
                    ? 'No hay familias registradas'
                    : 'No hay otras familias registradas',
                onSelected: _select,
              ),
            ),
            child: AppTextField(
              controller: widget.controller,
              focusNode: _focus,
              hint: 'Buscar familia registrada…',
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onTap: _open,
              onChanged: _onChanged,
              onSubmitted: (_) {
                if (widget.selected == null && matches.length == 1) {
                  _select(matches.single);
                }
              },
            ),
          ),
        );
      },
    );
  }

  /// Coloca la lista debajo del campo (o encima si abajo no cabe) sin salirse
  /// de la parte visible de la pantalla.
  Widget _buildOverlay(
    BuildContext context,
    OverlayChildLayoutInfo info,
    Widget list,
  ) {
    if (info.childPaintTransform.determinant() == 0) {
      return const SizedBox.shrink();
    }
    final field = info.childSize;
    final media = MediaQueryData.fromView(View.of(context));
    final visible = Rect.fromLTRB(
      0,
      media.padding.top,
      info.overlaySize.width,
      info.overlaySize.height -
          math.max(media.padding.bottom, media.viewInsets.bottom),
    );
    final visibleInField = MatrixUtils.transformRect(
      Matrix4.inverted(info.childPaintTransform),
      visible,
    );
    final spaceBelow = visibleInField.bottom - field.height - _listGap;
    final spaceAbove = -visibleInField.top - _listGap;
    final opensUp = spaceBelow < _listMinHeight && spaceAbove > spaceBelow;
    final maxHeight = (opensUp ? spaceAbove : spaceBelow).clamp(
      _listMinHeight,
      _listMaxHeight,
    );

    return Transform(
      transform: info.childPaintTransform.clone()
        ..translateByDouble(
          0,
          opensUp ? -_listGap : field.height + _listGap,
          0,
          1,
        ),
      child: Align(
        alignment: Alignment.topLeft,
        child: FractionalTranslation(
          translation: Offset(0, opensUp ? -1 : 0),
          child: TapRegion(
            groupId: _tapGroup,
            child: TextFieldTapRegion(
              child: ExcludeFocus(
                child: SizedBox(
                  width: field.width,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    child: list,
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

class _FamilyList extends StatelessWidget {
  const _FamilyList({
    required this.hasError,
    required this.families,
    required this.allFamilies,
    required this.matches,
    required this.emptyMessage,
    required this.onSelected,
  });

  final bool hasError;

  /// Las familias que se pueden elegir; null mientras cargan.
  final List<Family>? families;

  /// Todas las registradas, incluida la excluida, para contar tocayas.
  final List<Family>? allFamilies;
  final List<Family> matches;
  final String emptyMessage;
  final ValueChanged<Family> onSelected;

  @override
  Widget build(BuildContext context) {
    final families = this.families;
    final Widget content;
    if (hasError) {
      content = const _ListMessage(
        'No se pudieron cargar las familias. Revisa tu conexión.',
        color: AppColors.dangerText,
      );
    } else if (families == null) {
      content = const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primary,
            ),
          ),
        ),
      );
    } else if (families.isEmpty) {
      content = _ListMessage(emptyMessage);
    } else if (matches.isEmpty) {
      content = const _ListMessage('Sin resultados');
    } else {
      // Si hay nombres repetidos se muestra la dirección para distinguirlos.
      final counts = <String, int>{};
      for (final family in allFamilies ?? families) {
        final key = _fold(family.displayName);
        counts[key] = (counts[key] ?? 0) + 1;
      }
      content = ListView.builder(
        primary: false,
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: matches.length,
        itemBuilder: (context, index) {
          final family = matches[index];
          final repeated = (counts[_fold(family.displayName)] ?? 0) > 1;
          return _FamilyOption(
            family: family,
            showAddress: repeated && family.address.trim().isNotEmpty,
            onTap: () => onSelected(family),
          );
        },
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 2),
        borderRadius: BorderRadius.circular(12),
        boxShadow: _listShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(type: MaterialType.transparency, child: content),
      ),
    );
  }
}

class _FamilyOption extends StatelessWidget {
  const _FamilyOption({
    required this.family,
    required this.showAddress,
    required this.onTap,
  });

  final Family family;
  final bool showAddress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(family.displayName, style: AppText.nunito(15, 22.5)),
            if (showAddress)
              Text(
                family.address,
                style: AppText.nunito(13, 19.5, color: AppColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

class _ListMessage extends StatelessWidget {
  const _ListMessage(this.text, {this.color = AppColors.textMuted});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(text, style: AppText.nunito(15, 22.5, color: color)),
    );
  }
}

// ---------------------------------------------------------------------------
// Tabla de entregas
// ---------------------------------------------------------------------------

/// Anchos con margen para que ninguna palabra se corte (apellidos largos,
/// "Exenta", encabezados); la fecha sigue en 3 renglones como en el diseño.
const _columns = [
  ('Familia', 118.0),
  ('Fecha', 74.0),
  ('Despensas', 108.0),
  ('Cuota', 96.0),
  ('Productos', 104.0),
  ('Estado', 136.0),
  ('Sinc.', 68.0),
  ('Acción', 183.0),
];

class _DeliveriesTable extends StatelessWidget {
  const _DeliveriesTable({required this.deliveries});

  final Stream<List<DeliveryWithSync>> deliveries;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DeliveryWithSync>>(
      stream: deliveries,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const InfoBanner(
            message:
                'No se pudieron cargar las entregas. Revisa tu conexión e '
                'intenta de nuevo.',
            background: AppColors.dangerSoft,
            foreground: AppColors.dangerText,
          );
        }

        final rows = snapshot.data;
        if (rows == null) {
          return const _TableFrame(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
          );
        }

        // Las columnas crecen con el tamaño de letra del sistema.
        final scale = math.max(
          1.0,
          MediaQuery.textScalerOf(context).scale(15) / 15,
        );
        final widths = [for (final column in _columns) column.$2 * scale];

        return _TableFrame(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: widths.fold<double>(0, (sum, width) => sum + width),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Table(
                    columnWidths: {
                      for (final (index, width) in widths.indexed)
                        index: FixedColumnWidth(width),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    border: const TableBorder(
                      horizontalInside: BorderSide(color: AppColors.border),
                    ),
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(
                          color: AppColors.background,
                        ),
                        children: [
                          for (final column in _columns)
                            _TableCell(
                              child: Text(
                                column.$1,
                                style: AppText.nunito(
                                  14,
                                  21,
                                  weight: FontWeight.w700,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                        ],
                      ),
                      for (final row in rows) _buildRow(context, row),
                    ],
                  ),
                  if (rows.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 24,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: Text(
                        'Aún no hay entregas registradas.',
                        style: AppText.nunito(
                          15,
                          22.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  TableRow _buildRow(BuildContext context, DeliveryWithSync row) {
    final delivery = row.delivery;
    final body = AppText.nunito(15, 22.5);

    void open(_DeliveryAction action) => _showDeliveryActionSheet(
      context,
      delivery: delivery,
      action: action,
    );

    void reassign() => showAppBottomSheet<void>(
      context,
      // Arrastrar para cerrar ignoraría AppSheet.busy mientras se guarda.
      enableDrag: false,
      builder: (_) => _ReassignSheet(delivery: delivery),
    );

    return TableRow(
      children: [
        _TableCell(
          child: Text(
            delivery.familyName,
            style: AppText.nunito(15, 22.5, weight: FontWeight.w600),
          ),
        ),
        _TableCell(
          child: Text(
            formatDateLong(delivery.deliveryDate),
            style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
          ),
        ),
        _TableCell(child: Text('${delivery.packages}', style: body)),
        _TableCell(
          child: Text(formatRecoveryFee(delivery.recoveryFee), style: body),
        ),
        _TableCell(child: Text('${delivery.items.length}', style: body)),
        _TableCell(child: _StatusBadge(delivery.status)),
        _TableCell(
          child: Tooltip(
            message: row.pendingSync
                ? 'Pendiente de sincronizar'
                : 'Sincronizado',
            child: AppIcon(
              row.pendingSync ? AppIcons.cloudPending : AppIcons.cloudSynced,
              size: 20,
            ),
          ),
        ),
        _TableCell(
          child: switch (delivery.status) {
            DeliveryStatus.scheduled => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SecondaryButton(
                  label: 'Entregar',
                  icon: AppIcons.truck,
                  onPressed: () => open(_DeliveryAction.deliver),
                ),
                const SizedBox(height: 4),
                _LinkButton(label: 'Reasignar', onPressed: reassign),
                _LinkButton(
                  label: 'Cancelar',
                  color: AppColors.dangerText,
                  onPressed: () => open(_DeliveryAction.cancel),
                ),
              ],
            ),
            DeliveryStatus.delivered ||
            DeliveryStatus.cancelled ||
            DeliveryStatus.reassigned => Text(
              '—',
              style: AppText.nunito(14, 21, color: AppColors.textMuted),
            ),
          },
        ),
      ],
    );
  }
}

/// Badge de la columna Estado.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status);

  final DeliveryStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, background, foreground) = switch (status) {
      DeliveryStatus.scheduled => (
        'Programada',
        AppColors.warningSoft,
        AppColors.warningText,
      ),
      DeliveryStatus.delivered => (
        'Entregada',
        AppColors.primarySoft,
        AppColors.primaryDark,
      ),
      DeliveryStatus.cancelled => (
        'Cancelada',
        AppColors.background,
        AppColors.textMuted,
      ),
      DeliveryStatus.reassigned => (
        'Reasignada',
        AppColors.slateSoft,
        AppColors.slate,
      ),
    };
    final pill = Pill(
      label: label,
      background: background,
      foreground: foreground,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      fontSize: 13,
      lineHeight: 19.5,
    );
    if (status != DeliveryStatus.cancelled) return pill;

    // Fondo casi blanco: el borde de 1 px lo separa de la fila.
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: const ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: AppColors.border)),
      ),
      child: pill,
    );
  }
}

/// Enlace subrayado de la columna Acción: verde para "Reasignar" y rojo para
/// "Cancelar", que no se puede deshacer.
class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.label,
    required this.onPressed,
    this.color = AppColors.primaryDark,
  });

  final String label;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppText.nunito(
            15,
            22.5,
            weight: FontWeight.w700,
            color: color,
          ).copyWith(decoration: TextDecoration.underline, decorationColor: color),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entregar / cancelar una entrega programada
// ---------------------------------------------------------------------------

enum _DeliveryAction { deliver, cancel }

Future<void> _showDeliveryActionSheet(
  BuildContext context, {
  required Delivery delivery,
  required _DeliveryAction action,
}) {
  return showAppBottomSheet<void>(
    context,
    // Arrastrar para cerrar ignoraría AppSheet.busy mientras se guarda.
    enableDrag: false,
    builder: (_) =>
        _DeliveryActionSheet(delivery: delivery, action: action),
  );
}

/// Productos de [delivery] que ya caducaron en [date]; no entran a la
/// despensa al marcarla como entregada.
Iterable<DeliveryItem> _expiredItems(Delivery delivery, DateTime date) =>
    delivery.items.where((item) => item.isExpiredOn(date));

/// Confirmación de "Entregar" o "Cancelar" que nombra a la familia (en la
/// tabla, al llegar a la columna Acción, la columna Familia ya no se ve).
/// Después de guardar, el mismo sheet muestra la confirmación.
class _DeliveryActionSheet extends StatefulWidget {
  const _DeliveryActionSheet({required this.delivery, required this.action});

  final Delivery delivery;
  final _DeliveryAction action;

  @override
  State<_DeliveryActionSheet> createState() => _DeliveryActionSheetState();
}

class _DeliveryActionSheetState extends State<_DeliveryActionSheet> {
  bool _saving = false;
  String? _error;

  /// Otro dispositivo ya la entregó o canceló: reintentar no serviría.
  bool _alreadyChanged = false;
  String? _successMessage;

  bool get _isDeliver => widget.action == _DeliveryAction.deliver;

  String get _title => _isDeliver ? 'Entregar despensa' : 'Cancelar entrega';

  Future<void> _confirm() async {
    if (_saving || _alreadyChanged) return;
    final delivery = widget.delivery;
    final isDeliver = _isDeliver;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });

    String message;
    try {
      if (isDeliver) {
        final expired = _expiredItems(delivery, DateTime.now()).length;
        final saved = await _awaitSave(
          DeliveryRepository().markDelivered(delivery),
          onLateError: (error) => _showSnack(
            messenger,
            _lateErrorMessage(error, delivery, deliver: true),
          ),
        );
        message = _deliveredMessage(delivery, saved.result ?? expired);
        if (!saved.synced) message = '$message $_pendingSyncNote';
      } else {
        final saved = await _awaitSave(
          DeliveryRepository().cancelDelivery(delivery),
          onLateError: (error) => _showSnack(
            messenger,
            _lateErrorMessage(error, delivery, deliver: false),
          ),
        );
        message =
            'La entrega programada de ${delivery.familyName} para el '
            '${formatDateLong(delivery.deliveryDate)} quedó cancelada.';
        if (!saved.synced) message = '$message $_pendingSyncNote';
      }
    } catch (e) {
      if (!mounted) return;
      final alreadyChanged = _isAlreadyChanged(e);
      setState(() {
        _saving = false;
        _alreadyChanged = alreadyChanged;
        _error = alreadyChanged
            ? 'Esta entrega ya se había marcado desde otro dispositivo.'
            : isDeliver
            ? 'No se pudo marcar la entrega como entregada. Revisa tu '
                  'conexión e intenta de nuevo.'
            : 'No se pudo cancelar la entrega. Revisa tu conexión e intenta '
                  'de nuevo.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _successMessage = message;
    });
  }

  void _close() {
    if (!_saving) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final successMessage = _successMessage;
    if (successMessage != null) {
      return AppSheet(
        title: _title,
        body: SuccessContent(
          heading: _isDeliver ? 'Entrega completada' : 'Entrega cancelada',
          message: successMessage,
          onDone: () => Navigator.of(context).pop(),
        ),
      );
    }

    return AppSheet(
      title: _title,
      busy: _saving,
      body: _isDeliver ? _buildDeliverBody() : _buildCancelBody(),
      footer: _buildFooter(),
    );
  }

  Widget _buildDeliverBody() {
    final delivery = widget.delivery;
    final today = DateTime.now();
    final expired = _expiredItems(delivery, today).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Revisa que sea la familia correcta. Al confirmar, sus productos '
          'pasan a su despensa y la entrega ya no se puede cambiar.',
          style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        _SummaryCard(
          rows: [
            ('Familia', delivery.familyName),
            ('Fecha de entrega', formatDateLong(delivery.deliveryDate)),
            ('Despensas', '${delivery.packages}'),
          ],
        ),
        const SizedBox(height: 16),
        FieldLabel('Productos (${delivery.items.length})'),
        const SizedBox(height: 6),
        _DeliveryItemList(items: delivery.items, today: today),
        if (expired > 0) ...[
          const SizedBox(height: 8),
          _HelperText(
            expired == 1
                ? 'El producto caducado no se agregará a la despensa.'
                : 'Los productos caducados no se agregarán a la despensa.',
            color: AppColors.dangerText,
          ),
        ],
      ],
    );
  }

  Widget _buildCancelBody() {
    final delivery = widget.delivery;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'La entrega programada de ${delivery.familyName} para el '
          '${formatDateLong(delivery.deliveryDate)} se cancelará y sus '
          'productos no entrarán a su despensa.',
          style: AppText.nunito(15, 22.5),
        ),
        const SizedBox(height: 12),
        _HelperText('Esta acción no se puede deshacer.'),
      ],
    );
  }

  Widget _buildFooter() {
    final error = _error;
    final String closeLabel;
    if (_alreadyChanged) {
      closeLabel = 'Cerrar';
    } else {
      closeLabel = _isDeliver ? 'Cancelar' : 'Volver';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          Semantics(
            liveRegion: true,
            child: InfoBanner(
              message: error,
              background: AppColors.dangerSoft,
              foreground: AppColors.dangerText,
            ),
          ),
          const SizedBox(height: 12),
        ],
        PrimaryButton(
          label: _isDeliver ? 'Confirmar entrega' : 'Cancelar entrega',
          icon: _isDeliver ? AppIcons.check : AppIcons.close,
          loading: _saving,
          onPressed: _alreadyChanged ? null : _confirm,
        ),
        const SizedBox(height: 8),
        Center(
          child: Opacity(
            opacity: _saving ? 0.4 : 1,
            child: TextLinkButton(label: closeLabel, onPressed: _close),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reasignar una entrega programada
// ---------------------------------------------------------------------------

/// Pasa una entrega programada a otra familia: la original queda como
/// "Reasignada" y se registra una entrega nueva, programada, para la familia
/// que la recibe. La familia actual no aparece en la búsqueda.
class _ReassignSheet extends StatefulWidget {
  const _ReassignSheet({required this.delivery});

  final Delivery delivery;

  @override
  State<_ReassignSheet> createState() => _ReassignSheetState();
}

class _ReassignSheetState extends State<_ReassignSheet> {
  // Stream propio: el del formulario ya tiene quien lo escuche.
  late final Stream<List<Family>> _families;
  final _familyText = TextEditingController();
  Family? _receiver;
  bool _attempted = false;
  bool _saving = false;
  String? _error;

  /// Otro dispositivo ya la entregó, canceló o reasignó.
  bool _alreadyChanged = false;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _families = FamilyRepository().watchAllFamilies();
  }

  @override
  void dispose() {
    _familyText.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_saving || _alreadyChanged) return;
    final receiver = _receiver;
    if (receiver == null) {
      setState(() => _attempted = true);
      return;
    }
    final delivery = widget.delivery;
    final messenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });

    String message;
    try {
      final saved = await _awaitSave(
        DeliveryRepository().reassignDelivery(delivery, receiver),
        onLateError: (error) =>
            _showSnack(messenger, _lateReassignMessage(error, delivery)),
      );
      message =
          'La entrega del ${formatDateLong(delivery.deliveryDate)} ahora es '
          'para ${receiver.displayName} y quedó programada. La de '
          '${delivery.familyName} quedó como «Reasignada».';
      if (!saved.synced) message = '$message $_pendingSyncNote';
    } catch (e) {
      if (!mounted) return;
      final alreadyChanged = _isAlreadyChanged(e);
      setState(() {
        _saving = false;
        _alreadyChanged = alreadyChanged;
        _error = alreadyChanged
            ? 'Esta entrega ya se había marcado desde otro dispositivo.'
            : 'No se pudo reasignar la entrega. Revisa tu conexión e intenta '
                  'de nuevo.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _successMessage = message;
    });
  }

  void _close() {
    if (!_saving) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final successMessage = _successMessage;
    if (successMessage != null) {
      return AppSheet(
        title: 'Reasignar entrega',
        body: SuccessContent(
          heading: 'Entrega reasignada',
          message: successMessage,
          onDone: () => Navigator.of(context).pop(),
        ),
      );
    }

    final missingReceiver = _attempted && _receiver == null;
    return AppSheet(
      title: 'Reasignar entrega',
      busy: _saving,
      body: AbsorbPointer(
        absorbing: _saving,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'La entrega programada de ${widget.delivery.familyName} se '
              'marcará como «Reasignada» y se registrará una nueva entrega '
              'para la familia que la reciba.',
              style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: 'Familia',
              required: true,
              child: _FamilyCombobox(
                families: _families,
                controller: _familyText,
                selected: _receiver,
                excludeFamilyId: widget.delivery.familyId,
                onSelected: (family) => setState(() => _receiver = family),
              ),
            ),
            if (missingReceiver) ...[
              const SizedBox(height: 6),
              const _HelperText(
                'Selecciona la familia receptora',
                color: AppColors.dangerText,
              ),
            ],
          ],
        ),
      ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Semantics(
              liveRegion: true,
              child: InfoBanner(
                message: _error!,
                background: AppColors.dangerSoft,
                foreground: AppColors.dangerText,
              ),
            ),
            const SizedBox(height: 12),
          ],
          PrimaryButton(
            label: 'Confirmar reasignación',
            icon: AppIcons.check,
            loading: _saving,
            onPressed: _alreadyChanged ? null : _confirm,
          ),
          const SizedBox(height: 8),
          Center(
            child: Opacity(
              opacity: _saving ? 0.4 : 1,
              child: TextLinkButton(
                label: _alreadyChanged ? 'Cerrar' : 'Volver',
                onPressed: _close,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso cuando la reasignación guardada sin conexión falla al sincronizar.
String _lateReassignMessage(Object error, Delivery delivery) {
  final family = delivery.familyName;
  return _isAlreadyChanged(error)
      ? 'La entrega de $family ya se había marcado desde otro dispositivo, '
            'así que no se reasignó.'
      : 'No se pudo sincronizar la reasignación de la entrega de $family. '
            'Revisa la tabla e intenta de nuevo.';
}

/// Otro dispositivo ya la entregó o la canceló: las reglas solo dejan
/// cambiar el estado de una entrega programada, una vez.
bool _isAlreadyChanged(Object error) =>
    error is StateError ||
    (error is FirebaseException && error.code == 'permission-denied');

/// "Los productos de Familia Ramírez se agregarán a su despensa en unos
/// momentos." y, si hay, cuántos no se agregarán por estar caducados hoy. Los
/// agrega la Cloud Function en el servidor, después de guardar la entrega.
String _deliveredMessage(Delivery delivery, int skipped) {
  final family = delivery.familyName;
  final total = delivery.items.length;
  const pending = 'se agregarán a su despensa en unos momentos.';
  if (skipped <= 0) return 'Los productos de $family $pending';
  if (skipped >= total) {
    return total == 1
        ? 'La entrega de $family se marcó como entregada, pero su producto '
              'ya caducó y no se agregará a su despensa.'
        : 'La entrega de $family se marcó como entregada, pero sus productos '
              'ya caducaron y no se agregarán a su despensa.';
  }
  final note = skipped == 1
      ? '1 producto ya caducó y no se agregará.'
      : '$skipped productos ya caducaron y no se agregarán.';
  return 'Los productos de $family $pending $note';
}

/// Aviso cuando el cambio guardado sin conexión falla al sincronizar.
String _lateErrorMessage(
  Object error,
  Delivery delivery, {
  required bool deliver,
}) {
  final family = delivery.familyName;
  if (_isAlreadyChanged(error)) {
    return deliver
        ? 'La entrega de $family ya se había marcado desde otro dispositivo, '
              'así que sus productos no se agregaron otra vez.'
        : 'La entrega de $family ya se había marcado desde otro dispositivo, '
              'así que no se canceló.';
  }
  return deliver
      ? 'No se pudo sincronizar la entrega de $family. Revisa la tabla e '
            'intenta de nuevo.'
      : 'No se pudo sincronizar la cancelación de la entrega de $family. '
            'Revisa la tabla e intenta de nuevo.';
}

/// Datos de la entrega en renglones etiqueta / valor.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, (label, value)) in rows.indexed) ...[
            if (index > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    label,
                    style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Text(
                    value,
                    style: AppText.nunito(15, 22.5, weight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Productos de la entrega; los que ya caducaron se marcan "Caducado".
class _DeliveryItemList extends StatelessWidget {
  const _DeliveryItemList({required this.items, required this.today});

  final List<DeliveryItem> items;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, item) in items.indexed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: index == 0
                  ? null
                  : const BoxDecoration(
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          productDisplayName(item.productId),
                          style: AppText.nunito(
                            15,
                            22.5,
                            weight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          formatAmount(item.quantity, item.unit),
                          style: AppText.nunito(
                            14,
                            21,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (item.isExpiredOn(today)) ...[
                    const SizedBox(width: 8),
                    const Pill(
                      label: 'Caducado',
                      background: AppColors.dangerSoft,
                      foreground: AppColors.dangerText,
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      fontSize: 13,
                      lineHeight: 19.5,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TableFrame extends StatelessWidget {
  const _TableFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _TableCell extends StatelessWidget {
  const _TableCell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Align(alignment: AlignmentDirectional.centerStart, child: child),
    );
  }
}

// ---------------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------------

/// Espera a que Firestore confirme [save] y regresa su resultado. Si pasado
/// [_saveTimeout] sigue pendiente (sin conexión el cambio ya quedó en el
/// dispositivo), regresa synced: false sin resultado; si después falla al
/// sincronizar, llama a [onLateError] con el error.
Future<({bool synced, T? result})> _awaitSave<T>(
  Future<T> save, {
  required void Function(Object error) onLateError,
}) async {
  try {
    return (synced: true, result: await save.timeout(_saveTimeout));
  } on TimeoutException {
    unawaited(save.then<void>((_) {}, onError: onLateError));
    return (synced: false, result: null);
  }
}

void _showSnack(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// "2,5" y "2.5" valen lo mismo.
double? _parseDecimal(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  return value != null && value.isFinite ? value : null;
}

const _accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'};

/// Minúsculas y sin acentos para buscar ("ramirez" encuentra "Ramírez").
String _fold(String text) =>
    text.toLowerCase().split('').map((char) => _accents[char] ?? char).join();
