import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/bank_storage_facade.dart';
import '../../../data/models/pantry_item.dart';
import '../../../domain/models/recipe.dart';
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

/// Sin conexión el commit no termina hasta sincronizar; pasado este tiempo se
/// da por guardado (igual que en Entregas).
const _saveTimeout = Duration(seconds: 4);
const _pendingSyncNote = 'Se sincronizará cuando haya conexión.';

/// Imágenes que trae la app; una receta sin imagen usa la de reserva.
const _images = <(String, String)>[
  ('Sin imagen', ''),
  ('Sopa de lentejas', AppImages.sopaDeLentejas),
  ('Arroz con atún', AppImages.arrozConAtun),
  ('Avena con fruta', AppImages.avenaConFruta),
  ('Frijoles de la olla', AppImages.frijolesDeLaOlla),
  ('Sándwich de jamón y queso', AppImages.sandwichJamonQueso),
  ('Sopa de pasta con verduras', AppImages.sopaDePastaConVerduras),
];

/// Alta o edición de una receta del catálogo. [recipe] null es alta.
Future<void> showRecipeFormSheet(BuildContext context, {Recipe? recipe}) {
  return showAppBottomSheet<void>(
    context,
    // Arrastrar para cerrar ignoraría AppSheet.busy mientras se guarda.
    enableDrag: false,
    builder: (_) => _RecipeFormSheet(recipe: recipe),
  );
}

class _RecipeFormSheet extends StatefulWidget {
  const _RecipeFormSheet({this.recipe});

  final Recipe? recipe;

  @override
  State<_RecipeFormSheet> createState() => _RecipeFormSheetState();
}

class _RecipeFormSheetState extends State<_RecipeFormSheet> {
  final _name = TextEditingController();
  final _minutes = TextEditingController();
  final _servings = TextEditingController(text: '4');
  final _calories = TextEditingController();
  late List<_IngredientDraft> _ingredients;
  late List<TextEditingController> _steps;
  String _image = '';

  /// Solo al dar de alta: publicada la ven las familias; pendiente no.
  bool _publish = true;

  bool _saving = false;
  bool _deleting = false;
  String? _error;
  _Confirmation? _confirmation;
  ({String heading, String message})? _success;

  bool get _isEditing => widget.recipe != null;

  @override
  void initState() {
    super.initState();
    final recipe = widget.recipe;
    if (recipe != null) {
      _name.text = recipe.name;
      _minutes.text = '${recipe.prepTimeMinutes}';
      _servings.text = '${recipe.servings}';
      _calories.text = recipe.caloriesPerServing == 0
          ? ''
          : '${recipe.caloriesPerServing}';
      _image = recipe.image;
    }
    _ingredients = [
      for (final ingredient in recipe?.ingredients ?? const [])
        _IngredientDraft.from(ingredient),
      if ((recipe?.ingredients ?? const []).isEmpty) _IngredientDraft(),
    ];
    _steps = [
      for (final step in recipe?.steps ?? const [])
        TextEditingController(text: step),
      if ((recipe?.steps ?? const []).isEmpty) TextEditingController(),
    ];
  }

  @override
  void dispose() {
    _name.dispose();
    _minutes.dispose();
    _servings.dispose();
    _calories.dispose();
    for (final ingredient in _ingredients) {
      ingredient.dispose();
    }
    for (final step in _steps) {
      step.dispose();
    }
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Datos
  // -------------------------------------------------------------------------

  int? get _minuteCount => _positiveInt(_minutes.text);
  int? get _servingCount => _positiveInt(_servings.text);

  /// Las calorías son opcionales; vacío vale 0.
  int? get _calorieCount {
    final text = _calories.text.trim();
    if (text.isEmpty) return 0;
    final value = int.tryParse(text);
    return value != null && value >= 0 && value <= 5000 ? value : null;
  }

  List<RecipeIngredient> get _filledIngredients => [
    for (final ingredient in _ingredients)
      if (ingredient.isFilled) ingredient.toIngredient(),
  ];

  List<String> get _filledSteps => [
    for (final step in _steps)
      if (step.text.trim().isNotEmpty) step.text.trim(),
  ];

  /// Qué le falta para poder guardar (null = lista).
  String? get _missing {
    if (_name.text.trim().isEmpty) return 'Escribe el nombre de la receta.';
    if (_minuteCount == null) {
      return 'Indica el tiempo de preparación en minutos.';
    }
    if (_servingCount == null) return 'Indica para cuántas porciones es.';
    if (_calorieCount == null) return 'Las calorías por porción no son válidas.';
    if (_ingredients.any((ingredient) => ingredient.isPartial)) {
      return 'Completa el producto y la cantidad de cada ingrediente.';
    }
    if (_filledIngredients.isEmpty) return 'Agrega al menos un ingrediente.';
    if (_filledSteps.isEmpty) return 'Agrega al menos un paso.';
    return null;
  }

  // -------------------------------------------------------------------------
  // Acciones
  // -------------------------------------------------------------------------

  Future<void> _save() async {
    if (_saving || _missing != null) return;
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.of(context);
    final name = _name.text.trim();
    setState(() {
      _saving = true;
      _error = null;
    });

    final catalog = BankStorageFacade();
    final recipe = widget.recipe;
    final Future<void> save;
    if (recipe == null && _publish) {
      save = catalog.publishRecipe(
        name: name,
        ingredients: _filledIngredients,
        steps: _filledSteps,
        prepTimeMinutes: _minuteCount!,
        caloriesPerServing: _calorieCount!,
        image: _image,
        servings: _servingCount!,
      );
    } else if (recipe == null) {
      save = catalog.submitRecipe(
        name: name,
        ingredients: _filledIngredients,
        steps: _filledSteps,
        prepTimeMinutes: _minuteCount!,
        caloriesPerServing: _calorieCount!,
        image: _image,
        servings: _servingCount!,
      );
    } else {
      save = catalog.updateRecipe(
        recipe.copyWith(
          name: name,
          ingredients: _filledIngredients,
          steps: _filledSteps,
          prepTimeMinutes: _minuteCount,
          caloriesPerServing: _calorieCount,
          image: _image,
          servings: _servingCount,
        ),
      );
    }

    final bool synced;
    try {
      synced = await _awaitSave(
        save,
        onLateError: (error) => _showSnack(
          messenger,
          'No se pudo sincronizar «$name». Revisa el catálogo e intenta de '
          'nuevo.',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _errorMessage(e, 'guardar la receta');
      });
      return;
    }
    if (!mounted) return;

    final heading = _isEditing
        ? 'Cambios guardados'
        : _publish
        ? 'Receta publicada'
        : 'Receta guardada';
    var message = _isEditing
        ? 'Se guardaron los cambios de «$name».'
        : _publish
        ? '«$name» ya aparece en las recetas de las familias.'
        : '«$name» quedó pendiente de revisión; las familias todavía no la '
              'ven.';
    if (!synced) message = '$message $_pendingSyncNote';
    setState(() {
      _saving = false;
      _success = (heading: heading, message: message);
    });
  }

  Future<void> _publishPending() async {
    final recipe = widget.recipe;
    if (recipe == null || _saving) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });

    final bool synced;
    try {
      synced = await _awaitSave(
        BankStorageFacade().approveRecipe(recipe.id),
        onLateError: (error) => _showSnack(
          messenger,
          'No se pudo sincronizar la publicación de «${recipe.name}».',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _errorMessage(e, 'publicar la receta');
      });
      return;
    }
    if (!mounted) return;

    var message = '«${recipe.name}» ya aparece en las recetas de las familias.';
    if (!synced) message = '$message $_pendingSyncNote';
    setState(() {
      _saving = false;
      _success = (heading: 'Receta publicada', message: message);
    });
  }

  Future<void> _delete() async {
    final recipe = widget.recipe;
    if (recipe == null || _deleting) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _deleting = true;
      _error = null;
    });

    final bool synced;
    try {
      synced = await _awaitSave(
        BankStorageFacade().deleteRecipe(recipe.id),
        onLateError: (error) => _showSnack(
          messenger,
          'No se pudo sincronizar la eliminación de «${recipe.name}».',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = _errorMessage(e, 'eliminar la receta');
      });
      return;
    }
    if (!mounted) return;

    var message =
        '«${recipe.name}» ya no está en el catálogo ni en las recetas de las '
        'familias.';
    if (!synced) message = '$message $_pendingSyncNote';
    setState(() {
      _deleting = false;
      _confirmation = null;
      _success = (heading: 'Receta eliminada', message: message);
    });
  }

  void _addIngredient() =>
      setState(() => _ingredients = [..._ingredients, _IngredientDraft()]);

  void _removeIngredient(_IngredientDraft ingredient) {
    setState(() {
      _ingredients = [..._ingredients]..remove(ingredient);
    });
    ingredient.dispose();
  }

  void _addStep() =>
      setState(() => _steps = [..._steps, TextEditingController()]);

  void _removeStep(TextEditingController step) {
    setState(() {
      _steps = [..._steps]..remove(step);
    });
    step.dispose();
  }

  Future<void> _pickUnit(_IngredientDraft ingredient) async {
    final unit = await _pickOption<FoodUnit>(
      context,
      title: 'Unidad',
      options: FoodUnit.values,
      selected: ingredient.unit,
      labelOf: unitName,
    );
    if (unit != null) setState(() => ingredient.unit = unit);
  }

  Future<void> _pickImage() async {
    final image = await _pickOption<String>(
      context,
      title: 'Imagen',
      options: [for (final (_, path) in _images) path],
      selected: _image,
      labelOf: _imageLabel,
    );
    if (image != null) setState(() => _image = image);
  }

  // -------------------------------------------------------------------------
  // Pantalla
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final success = _success;
    if (success != null) {
      return AppSheet(
        title: _title,
        body: SuccessContent(
          heading: success.heading,
          message: success.message,
          onDone: () => Navigator.of(context).pop(),
        ),
      );
    }
    if (_confirmation == _Confirmation.delete) return _buildDeleteConfirmation();

    final missing = _missing;
    final error = _error;

    return AppSheet(
      title: _title,
      busy: _saving,
      body: AbsorbPointer(absorbing: _saving, child: _buildForm()),
      footer: Column(
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
          if (missing != null && !_saving) ...[
            _HelperText(missing),
            const SizedBox(height: 8),
          ],
          PrimaryButton(
            label: _isEditing ? 'Guardar cambios' : 'Guardar receta',
            icon: AppIcons.check,
            loading: _saving,
            onPressed: missing == null ? _save : null,
          ),
          if (_isEditing && widget.recipe!.status == RecipeStatus.pending) ...[
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Publicar para las familias',
              icon: AppIcons.check,
              onPressed: _saving ? null : _publishPending,
            ),
          ],
          if (_isEditing) ...[
            const SizedBox(height: 8),
            Center(
              child: _DangerLinkButton(
                label: 'Eliminar receta',
                onPressed: _saving
                    ? null
                    : () => setState(() => _confirmation = _Confirmation.delete),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String get _title => _isEditing ? 'Editar receta' : 'Nueva receta';

  Widget _buildDeleteConfirmation() {
    final recipe = widget.recipe!;
    final error = _error;

    return AppSheet(
      title: 'Eliminar receta',
      busy: _deleting,
      body: Text(
        '¿Eliminar «${recipe.name}» del catálogo? Las familias dejarán de '
        'verla. Esta acción no se puede deshacer.',
        style: AppText.nunito(15, 22.5),
      ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            InfoBanner(
              message: error,
              background: AppColors.dangerSoft,
              foreground: AppColors.dangerText,
            ),
            const SizedBox(height: 12),
          ],
          _DangerButton(
            label: 'Eliminar',
            loading: _deleting,
            onPressed: _delete,
          ),
          const SizedBox(height: 8),
          Center(
            child: AbsorbPointer(
              absorbing: _deleting,
              child: TextLinkButton(
                label: 'Cancelar',
                onPressed: () => setState(() {
                  _confirmation = null;
                  _error = null;
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    void refresh(String _) => setState(() => _error = null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabeledField(
          label: 'Nombre',
          required: true,
          child: AppTextField(
            controller: _name,
            hint: 'Ej. Sopa de lentejas',
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            maxLength: 100,
            onChanged: refresh,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: 'Minutos',
                required: true,
                child: AppTextField(
                  controller: _minutes,
                  hint: '40',
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 4,
                  onChanged: refresh,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                label: 'Porciones',
                required: true,
                child: AppTextField(
                  controller: _servings,
                  hint: '4',
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 2,
                  onChanged: refresh,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Calorías por porción',
          child: AppTextField(
            controller: _calories,
            hint: '230',
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 4,
            onChanged: refresh,
          ),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Imagen',
          child: _PickerField(
            label: 'Imagen',
            value: _imageLabel(_image),
            onTap: _pickImage,
          ),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Ingredientes', required: true),
        const SizedBox(height: 2),
        _HelperText(
          'Escribe el producto como aparece en la despensa (Arroz, Atún en '
          'lata); así la app sabe qué familias pueden cocinarla.',
        ),
        for (final ingredient in _ingredients) ...[
          const SizedBox(height: 12),
          _IngredientCard(
            key: ObjectKey(ingredient),
            ingredient: ingredient,
            onEdited: refresh,
            onPickUnit: () => _pickUnit(ingredient),
            onRemove: _ingredients.length > 1
                ? () => _removeIngredient(ingredient)
                : null,
          ),
        ],
        const SizedBox(height: 12),
        SecondaryButton(
          label: 'Agregar ingrediente',
          icon: AppIcons.plus,
          onPressed: _addIngredient,
        ),
        const SizedBox(height: 16),
        const FieldLabel('Preparación', required: true),
        const SizedBox(height: 2),
        _HelperText('Un paso por renglón, en el orden en que se hacen.'),
        for (final (index, step) in _steps.indexed) ...[
          const SizedBox(height: 12),
          _StepField(
            key: ObjectKey(step),
            number: index + 1,
            controller: step,
            onChanged: refresh,
            onRemove: _steps.length > 1 ? () => _removeStep(step) : null,
          ),
        ],
        const SizedBox(height: 12),
        SecondaryButton(
          label: 'Agregar paso',
          icon: AppIcons.plus,
          onPressed: _addStep,
        ),
        if (!_isEditing) ...[
          const SizedBox(height: 16),
          LabeledField(
            label: 'Publicación',
            child: Row(
              children: [
                Expanded(
                  child: OptionButton(
                    label: 'Publicada',
                    selected: _publish,
                    onTap: () => setState(() => _publish = true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OptionButton(
                    label: 'Pendiente',
                    selected: !_publish,
                    onTap: () => setState(() => _publish = false),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _HelperText(
            _publish
                ? 'Las familias la verán en cuanto la guardes.'
                : 'Queda guardada en el catálogo, pero las familias no la ven '
                      'hasta publicarla.',
          ),
        ],
      ],
    );
  }
}

enum _Confirmation { delete }

/// Un ingrediente mientras se edita: producto, cantidad y unidad.
class _IngredientDraft {
  _IngredientDraft();

  factory _IngredientDraft.from(RecipeIngredient ingredient) {
    final draft = _IngredientDraft()
      ..product.text = ingredient.productName
      ..unit = _unitFrom(ingredient.unit);
    draft.quantity.text = formatNumber(ingredient.quantity);
    return draft;
  }

  final product = TextEditingController();
  final quantity = TextEditingController();
  FoodUnit unit = FoodUnit.kg;

  double? get amount {
    final value = double.tryParse(quantity.text.trim().replaceAll(',', '.'));
    return value != null && value.isFinite && value > 0 ? value : null;
  }

  bool get isEmpty => product.text.trim().isEmpty && quantity.text.trim().isEmpty;
  bool get isFilled => product.text.trim().isNotEmpty && amount != null;

  /// A medio llenar: no se puede guardar así.
  bool get isPartial => !isEmpty && !isFilled;

  RecipeIngredient toIngredient() => RecipeIngredient(
    productName: product.text.trim(),
    quantity: amount!,
    unit: unit.name,
  );

  void dispose() {
    product.dispose();
    quantity.dispose();
  }
}

/// La unidad guardada es texto; se aceptan los nombres del enum y algunos
/// alias en español ("lata", "pieza"…). Lo que no se reconoce cae en kg.
FoodUnit _unitFrom(String unit) {
  final value = unit.trim().toLowerCase();
  for (final option in FoodUnit.values) {
    if (option.name == value) return option;
  }
  return switch (value) {
    'lata' || 'latas' => FoodUnit.can,
    'pieza' || 'piezas' || 'pza' => FoodUnit.piece,
    'paquete' || 'paquetes' => FoodUnit.pack,
    'litro' || 'litros' => FoodUnit.l,
    'mililitro' || 'mililitros' => FoodUnit.ml,
    'kilo' || 'kilos' || 'kilogramo' || 'kilogramos' => FoodUnit.kg,
    'gramo' || 'gramos' => FoodUnit.g,
    _ => FoodUnit.kg,
  };
}

String _imageLabel(String path) {
  for (final (label, value) in _images) {
    if (value == path) return label;
  }
  return path.isEmpty ? 'Sin imagen' : path.split('/').last;
}

class _IngredientCard extends StatelessWidget {
  const _IngredientCard({
    super.key,
    required this.ingredient,
    required this.onEdited,
    required this.onPickUnit,
    this.onRemove,
  });

  final _IngredientDraft ingredient;
  final ValueChanged<String> onEdited;
  final VoidCallback onPickUnit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: ingredient.product,
                  hint: 'Ej. Lenteja',
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  maxLength: 100,
                  onChanged: onEdited,
                ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Quitar ingrediente',
                  child: InkWell(
                    onTap: onRemove,
                    customBorder: const CircleBorder(),
                    child: const SizedBox.square(
                      dimension: 40,
                      child: Center(child: AppIcon(AppIcons.close, size: 20)),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: ingredient.quantity,
                  hint: '0',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  maxLength: 9,
                  onChanged: onEdited,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PickerField(
                  label: 'Unidad',
                  value: unitLabel(ingredient.unit, 2),
                  onTap: onPickUnit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepField extends StatelessWidget {
  const _StepField({
    super.key,
    required this.number,
    required this.controller,
    required this.onChanged,
    this.onRemove,
  });

  final int number;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: SizedBox(
            width: 24,
            child: Text(
              '$number.',
              style: AppText.nunito(15, 22.5, weight: FontWeight.w700),
            ),
          ),
        ),
        Expanded(
          child: AppTextField(
            controller: controller,
            hint: 'Ej. Enjuaga las lentejas y ponlas a cocer.',
            textCapitalization: TextCapitalization.sentences,
            minLines: 2,
            maxLines: 4,
            maxLength: 300,
            onChanged: onChanged,
          ),
        ),
        if (onRemove != null) ...[
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Tooltip(
              message: 'Quitar paso',
              child: InkWell(
                onTap: onRemove,
                customBorder: const CircleBorder(),
                child: const SizedBox.square(
                  dimension: 40,
                  child: Center(child: AppIcon(AppIcons.close, size: 20)),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Campo que no se escribe: abre un selector (unidad, imagen).
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      value: value,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.nunito(16, 24),
          ),
        ),
      ),
    );
  }
}

/// Lista de opciones en un bottom sheet (unidad, imagen).
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
          for (final option in options) ...[
            OptionButton(
              label: labelOf(option),
              selected: option == selected,
              onTap: () => Navigator.of(sheetContext).pop(option),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    ),
  );
}

class _HelperText extends StatelessWidget {
  const _HelperText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppText.nunito(14, 21, color: AppColors.textMuted),
    );
  }
}

/// Botón rojo de ancho completo para confirmar el borrado.
class _DangerButton extends StatelessWidget {
  const _DangerButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool loading;

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: AppColors.danger,
        shape: _shape,
        child: InkWell(
          onTap: loading ? null : onPressed,
          customBorder: _shape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              child: Center(
                child: loading
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        label,
                        textAlign: TextAlign.center,
                        style: AppText.nunito(
                          17,
                          25.5,
                          weight: FontWeight.w700,
                          color: Colors.white,
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

/// Enlace rojo subrayado para acciones que no se pueden deshacer.
class _DangerLinkButton extends StatelessWidget {
  const _DangerLinkButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppText.nunito(
            15,
            22.5,
            weight: FontWeight.w700,
            color: AppColors.dangerText,
          ).copyWith(
            decoration: TextDecoration.underline,
            decorationColor: AppColors.dangerText,
          ),
        ),
      ),
    );
  }
}

int? _positiveInt(String text) {
  final value = int.tryParse(text.trim());
  return value != null && value > 0 && value <= 9999 ? value : null;
}

String _errorMessage(Object error, String action) {
  if (error is FirebaseException && error.code == 'permission-denied') {
    return 'Tu cuenta no tiene permiso para $action.';
  }
  if (error is ArgumentError && error.message is String) {
    return error.message as String;
  }
  return 'No se pudo $action. Revisa tu conexión e intenta de nuevo.';
}

/// Espera a que Firestore confirme [save]. Regresa false si pasado
/// [_saveTimeout] sigue pendiente (sin conexión ya quedó en el dispositivo);
/// si después falla al sincronizar, llama a [onLateError].
Future<bool> _awaitSave(
  Future<void> save, {
  required void Function(Object error) onLateError,
}) async {
  try {
    await save.timeout(_saveTimeout);
    return true;
  } on TimeoutException {
    unawaited(save.then<void>((_) {}, onError: onLateError));
    return false;
  }
}

void _showSnack(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
