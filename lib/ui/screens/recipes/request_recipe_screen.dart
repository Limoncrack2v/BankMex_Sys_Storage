import 'package:flutter/material.dart';

import '../../../data/catalog_source.dart';
import '../../../data/models/family.dart';
import '../../../data/models/member.dart';
import '../../../data/models/pantry_item.dart';
import '../../../data/repositories/family_repository.dart';
import '../../../data/repositories/member_repository.dart';
import '../../../data/repositories/pantry_repository.dart';
import '../../../domain/models/recipe_request.dart';
import '../../models/recipe.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/option_button.dart';
import '../../widgets/pill.dart';
import 'recipe_detail_screen.dart';

/// Productos de la despensa que se ofrecen como antojo, los que caducan
/// antes. Con todos, las opciones empujarían la receta hasta abajo; los
/// demás se pueden escribir en "¿Algo en especial?".
const _maxCravingOptions = 6;

/// Opciones de "¿Cuánto tiempo tienes?": minutos (null = sin prisa).
const _timeOptions = <(int?, String)>[
  (15, '15 min'),
  (30, '30 min'),
  (60, '1 hora'),
  (null, 'Sin prisa'),
];

/// Tarjeta de la pestaña Recetas que lleva a [RequestRecipeScreen].
class RequestRecipeCard extends StatelessWidget {
  const RequestRecipeCard({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿No sabes qué cocinar?',
            style: AppText.baloo(19, 23.75, weight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Te sugerimos una receta con lo que tienes en tu despensa.',
            style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          PrimaryButton(label: 'Pedir una receta', onPressed: onPressed),
        ],
      ),
    );
  }
}

/// "Pedir una receta": la familia dice qué se le antoja y cuánto tiempo
/// tiene, y se le sugiere una receta a la vez (ver [pickRecipe]). Sin pedir
/// nada es la receta que mejor usa lo que hay en su despensa.
///
/// Lee lo mismo que las otras pestañas: el catálogo aprobado, la despensa,
/// los integrantes y los electrodomésticos del hogar. Sin recetas aprobadas
/// no sugiere nada: no usa datos de muestra.
class RequestRecipeScreen extends StatefulWidget {
  const RequestRecipeScreen({super.key, required this.familyId});

  final String familyId;

  @override
  State<RequestRecipeScreen> createState() => _RequestRecipeScreenState();
}

class _RequestRecipeScreenState extends State<RequestRecipeScreen> {
  RecipeRequest _request = const RecipeRequest();
  late Stream<List<PantryItem>> _pantry;
  late Stream<List<Member>> _members;
  late Stream<List<Recipe>> _catalog;
  late Stream<Family?> _family;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void didUpdateWidget(RequestRecipeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.familyId != widget.familyId) _watch();
  }

  void _watch() {
    _pantry = PantryRepository().watchAllPantryItems(widget.familyId);
    _members = MemberRepository().watchAllMembers(widget.familyId);
    _catalog = watchApprovedCatalogRecipes();
    _family = FamilyRepository().watchFamily(widget.familyId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const _Header(backLabel: 'Volver a recetas'),
          Expanded(
            child: ApprovedCatalogGate(
              stream: _catalog,
              builder: (context, recipes) {
                return StreamBuilder<Family?>(
                  stream: _family,
                  builder: (context, family) => StreamBuilder<List<Member>>(
                    stream: _members,
                    builder: (context, members) =>
                        StreamBuilder<List<PantryItem>>(
                          stream: _pantry,
                          builder: (context, pantry) => RequestRecipeView(
                            recipes: recipes,
                            pantry: pantry.hasError ? null : pantry.data,
                            pantryFailed: pantry.hasError,
                            members: members.hasError ? null : members.data,
                            membersFailed: members.hasError,
                            // Sin el documento del hogar (o si no se pudo
                            // leer) no se sabe qué electrodomésticos tiene.
                            appliances:
                                family.connectionState ==
                                    ConnectionState.waiting
                                ? null
                                : family.data?.appliances ?? const [],
                            request: _request,
                            onRequestChanged: (request) =>
                                setState(() => _request = request),
                            onOpenRecipe: (recipe) => openRecipe(
                              context,
                              recipe,
                              familyId: widget.familyId,
                              backLabel: 'Volver a la sugerencia',
                            ),
                          ),
                        ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Espera el catálogo aprobado y solo entonces llama a [builder]: un
/// indicador mientras carga, un aviso si falla y un estado vacío si el
/// nutriólogo aún no aprobó recetas (igual que la pestaña Plan).
class ApprovedCatalogGate extends StatelessWidget {
  const ApprovedCatalogGate({
    super.key,
    required this.stream,
    required this.builder,
  });

  final Stream<List<Recipe>> stream;
  final Widget Function(BuildContext context, List<Recipe> recipes) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Recipe>>(
      stream: stream,
      builder: (context, catalog) {
        if (catalog.hasError) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              InfoBanner(
                message:
                    'No pudimos leer las recetas. Revisa tu conexión e '
                    'inténtalo de nuevo.',
                background: AppColors.warningSoft,
                foreground: AppColors.warningText,
              ),
            ],
          );
        }
        final recipes = catalog.data;
        if (recipes == null) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }
        if (recipes.isEmpty) {
          return ListView(
            children: const [
              EmptyState(
                title: 'Aún no hay recetas para sugerirte',
                message:
                    'Cuando el nutriólogo apruebe recetas, aquí te sugeriremos '
                    'una.',
              ),
            ],
          );
        }
        return builder(context, recipes);
      },
    );
  }
}

/// El contenido de [RequestRecipeScreen] con los datos ya leídos, sin
/// Firebase: lo que se le antoja, el tiempo que tiene y la receta sugerida.
/// La búsqueda ([request]) la guarda quien la usa y cambia con
/// [onRequestChanged].
class RequestRecipeView extends StatefulWidget {
  const RequestRecipeView({
    super.key,
    required this.recipes,
    required this.pantry,
    required this.members,
    required this.appliances,
    required this.request,
    required this.onRequestChanged,
    required this.onOpenRecipe,
    this.pantryFailed = false,
    this.membersFailed = false,
    this.today,
  });

  /// El catálogo, sin ajustar al hogar.
  final List<Recipe> recipes;

  /// null mientras carga o si no se pudo leer ([pantryFailed]).
  final List<PantryItem>? pantry;
  final bool pantryFailed;

  /// null mientras cargan o si no se pudieron leer ([membersFailed]).
  final List<Member>? members;
  final bool membersFailed;

  /// Ids de Appliance del hogar (vacía si no se sabe); null mientras carga.
  final List<String>? appliances;
  final RecipeRequest request;
  final ValueChanged<RecipeRequest> onRequestChanged;

  /// Recibe la receta del catálogo, sin ajustar ([RecipeSuggestion.recipe]).
  final ValueChanged<Recipe> onOpenRecipe;

  /// Hoy (DateTime.now() si no se da).
  final DateTime? today;

  @override
  State<RequestRecipeView> createState() => _RequestRecipeViewState();
}

class _RequestRecipeViewState extends State<RequestRecipeView> {
  final _special = TextEditingController();
  final _suggestionKey = GlobalKey();

  @override
  void dispose() {
    _special.dispose();
    super.dispose();
  }

  RecipeRequest get _request => widget.request;

  /// Si la opción [craving] (null = lo que sea) es lo que ya se pidió. Lo
  /// escrito no es una opción.
  bool _isCraving(String? craving) {
    final current = _request.cravingText;
    if (craving == null || current == null) return craving == current;
    return _request.cravingIsProduct && _sameCraving(craving, current);
  }

  /// Cambiar el antojo o el tiempo es otra búsqueda: se olvidan las recetas
  /// vistas. Tocar la opción que ya está elegida no cambia nada.
  void _pickCraving(String? craving) {
    _special.clear();
    _revealSuggestion();
    if (_isCraving(craving)) return;
    widget.onRequestChanged(
      RecipeRequest(
        craving: craving,
        cravingIsProduct: craving != null,
        maxPrepMinutes: _request.maxPrepMinutes,
      ),
    );
  }

  void _typeCraving(String text) {
    final request = RecipeRequest(
      craving: text,
      maxPrepMinutes: _request.maxPrepMinutes,
    );
    // Un espacio de más no es otra búsqueda.
    if (_request.cravingIsProduct ||
        request.cravingText != _request.cravingText) {
      widget.onRequestChanged(request);
    }
  }

  void _pickTime(int? minutes) {
    _revealSuggestion();
    if (minutes == _request.maxPrepMinutes) return;
    widget.onRequestChanged(
      RecipeRequest(
        craving: _request.craving,
        cravingIsProduct: _request.cravingIsProduct,
        maxPrepMinutes: minutes,
      ),
    );
  }

  /// Después de cambiar la búsqueda, mueve la lista lo justo para que se vea
  /// la sugerencia.
  void _revealSuggestion() {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        final target = _suggestionKey.currentContext;
        if (!mounted || target == null) return;
        final list = Scrollable.of(target).context.findRenderObject();
        final box = target.findRenderObject()! as RenderBox;
        final top = box.localToGlobal(Offset.zero, ancestor: list).dy;
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          // Si quedó arriba se alinea su inicio; si quedó abajo, su final.
          alignmentPolicy: top < 0
              ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
              : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      })
      ..ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final pantry = widget.pantry;
    final members = widget.members;
    final appliances = widget.appliances;

    // Todo se arma de una vez (no como en ListView) para poder llevar la
    // lista hasta la sugerencia aunque esté lejos.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pedir una receta', style: AppText.baloo(24, 30)),
          const SizedBox(height: 4),
          Text(
            'Elige qué se te antoja y cuánto tiempo tienes. Tomamos en cuenta '
            'las alergias y la salud de tu familia.',
            style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
          ),
          // Sin los integrantes no se pueden descartar sus alérgenos, así que
          // no se sugiere nada.
          if (widget.membersFailed || widget.pantryFailed) ...[
            if (widget.membersFailed) ...[
              const SizedBox(height: 16),
              const InfoBanner(
                message:
                    'No pudimos revisar las alergias de tu familia. Revisa tu '
                    'conexión e intenta de nuevo.',
                background: AppColors.warningSoft,
                foreground: AppColors.warningText,
              ),
            ],
            if (widget.pantryFailed) ...[
              const SizedBox(height: 16),
              const PantryErrorBanner(),
            ],
          ] else if (pantry == null || members == null || appliances == null)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else
            ..._content(pantry, members, appliances),
        ],
      ),
    );
  }

  List<Widget> _content(
    List<PantryItem> pantry,
    List<Member> members,
    List<String> appliances,
  ) {
    final today = widget.today ?? DateTime.now();
    final suitable = recipesForHousehold(
      widget.recipes,
      members: members,
      householdAppliances: appliances,
    );
    if (suitable.isEmpty) {
      return const [
        SizedBox(height: 16),
        InfoBanner(
          message:
              'No hay recetas que podamos sugerirte: todas llevan algo a lo '
              'que alguien de tu familia tiene alergia o piden un '
              'electrodoméstico que no tienes.',
          background: AppColors.warningSoft,
          foreground: AppColors.warningText,
        ),
      ];
    }

    final craving = _request.cravingText;
    // Los productos de tipo "otro" (aceite, sal) no se ofrecen; se pueden
    // escribir.
    final products = [
      for (final item in pantry)
        if (item.type != FoodType.other) item,
    ];
    final options = cravingOptions(
      _avoidingConditions(suitable, members),
      products,
      today: today,
    ).take(_maxCravingOptions).toList();
    // El producto elegido no desaparece de las opciones aunque se acabe
    // mientras se ve la pantalla.
    if (craving != null &&
        _request.cravingIsProduct &&
        !options.any((option) => _sameCraving(option, craving))) {
      options.insert(0, craving);
    }
    final suggestion = pickRecipe(
      widget.recipes,
      pantry,
      members: members,
      householdAppliances: appliances,
      request: _request,
      today: today,
    );

    return [
      const SizedBox(height: 20),
      const FieldLabel('¿Qué se te antoja?'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OptionButton(
            label: 'Lo que sea',
            selected: _isCraving(null),
            pill: true,
            onTap: () => _pickCraving(null),
          ),
          for (final option in options)
            OptionButton(
              label: option,
              selected: _isCraving(option),
              pill: true,
              onTap: () => _pickCraving(option),
            ),
        ],
      ),
      const SizedBox(height: 12),
      AppTextField(
        controller: _special,
        hint: '¿Algo en especial? Ej. sopa',
        textInputAction: TextInputAction.search,
        onChanged: _typeCraving,
        onSubmitted: (_) => _revealSuggestion(),
      ),
      const SizedBox(height: 20),
      const FieldLabel('¿Cuánto tiempo tienes?'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (minutes, label) in _timeOptions)
            OptionButton(
              label: label,
              selected: _request.maxPrepMinutes == minutes,
              pill: true,
              onTap: () => _pickTime(minutes),
            ),
        ],
      ),
      const SizedBox(height: 24),
      if (suggestion == null) ...[
        // Sin recetas vistas siempre hay una: [suitable] no está vacía.
        Column(
          key: _suggestionKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            InfoBanner(
              message: 'Ya te mostramos todas las recetas para tu familia.',
              background: AppColors.primarySoft,
              foreground: AppColors.primaryDark,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SecondaryButton(
          label: 'Volver a empezar',
          onPressed: () => widget.onRequestChanged(_request.restarted()),
        ),
      ] else
        ..._suggestion(suggestion, members),
    ];
  }

  List<Widget> _suggestion(RecipeSuggestion suggestion, List<Member> members) {
    final relaxed = _relaxed(suggestion);
    final conditions = conditionConflicts(suggestion.recipe, members);

    return [
      Column(
        key: _suggestionKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Te sugerimos', style: AppText.baloo(19, 28.5)),
          if (relaxed.isNotEmpty) ...[
            const SizedBox(height: 8),
            InfoBanner(
              message: relaxed.join('\n'),
              background: AppColors.warningSoft,
              foreground: AppColors.warningText,
            ),
          ],
          if (conditions.isNotEmpty) ...[
            const SizedBox(height: 8),
            InfoBanner(
              message: conditions.map(conditionWarning).join('\n'),
              background: AppColors.warningSoft,
              foreground: AppColors.warningText,
            ),
          ],
          const SizedBox(height: 12),
          _SuggestionCard(
            suggestion: suggestion,
            onTap: () => widget.onOpenRecipe(suggestion.recipe),
          ),
        ],
      ),
      const SizedBox(height: 16),
      PrimaryButton(
        label: 'Ver receta',
        onPressed: () => widget.onOpenRecipe(suggestion.recipe),
      ),
      const SizedBox(height: 12),
      SecondaryButton(
        label: 'Otra receta',
        onPressed: () {
          widget.onRequestChanged(
            _request.excluding(recipeKey(suggestion.recipe)),
          );
          _revealSuggestion();
        },
      ),
    ];
  }

  /// Lo que la receta sugerida no cumple de lo que se pidió. Lo que le falta
  /// de la despensa ya lo dice el motivo de la tarjeta.
  List<String> _relaxed(RecipeSuggestion suggestion) {
    final limit = _request.maxPrepMinutes;
    final craving = _request.cravingText;
    final minutes = suggestion.recipe.minutes;

    return [
      if (!suggestion.fitsTime && limit != null)
        minutes > 0
            ? 'Esta receta tarda $minutes min, más de los $limit que tienes.'
            : 'No sabemos cuánto tarda esta receta.',
      if (!suggestion.matchesCraving && craving != null)
        'Esta receta no lleva «$craving».',
    ];
  }
}

bool _sameCraving(String a, String b) => normalizeName(a) == normalizeName(b);

/// Las [recipes] sin nada que evitar por una enfermedad de [members] (las que
/// [pickRecipe] sugiere primero), o todas si ninguna.
List<Recipe> _avoidingConditions(List<Recipe> recipes, List<Member> members) {
  final healthy = [
    for (final recipe in recipes)
      if (conditionConflicts(recipe, members).isEmpty) recipe,
  ];
  return healthy.isEmpty ? recipes : healthy;
}

/// La receta sugerida con las porciones del hogar: por qué se eligió (como en
/// el plan de comidas) y si alcanza con la despensa.
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.suggestion, required this.onTap});

  final RecipeSuggestion suggestion;
  final VoidCallback onTap;

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
    side: BorderSide(color: AppColors.border),
  );

  @override
  Widget build(BuildContext context) {
    final recipe = suggestion.scaled;
    final urgency = suggestion.urgency;
    final reason = Text(
      suggestion.reason,
      style: AppText.nunito(14, 21, color: AppColors.textMuted),
    );

    return Material(
      color: AppColors.surface,
      shape: _shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 2,
              child: ColoredBox(
                color: AppColors.primarySoft,
                child: Image.asset(recipe.image, fit: BoxFit.cover),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Al cambiar la sugerencia, TalkBack la lee.
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      recipe.name,
                      style: AppText.baloo(19, 23.75, weight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  RecipeMeta(recipe),
                  const SizedBox(height: 8),
                  // Sin nada de la despensa siempre diría "Fresco".
                  if (!suggestion.usesPantry)
                    reason
                  else
                    PillRow(
                      gap: 12,
                      leading: reason,
                      trailing: Pill(
                        label: urgency.label,
                        background: urgency.background,
                        foreground: urgency.foreground,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        fontSize: 13,
                        lineHeight: 19.5,
                      ),
                    ),
                  if (suggestion.fitsPantry) ...[
                    const SizedBox(height: 8),
                    const Pill.success(label: 'Tienes todos los ingredientes'),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Regreso a Recetas, como el del detalle de receta.
class _Header extends StatelessWidget {
  const _Header({required this.backLabel});

  final String backLabel;

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
                      Text(
                        backLabel,
                        style: AppText.nunito(
                          16,
                          24,
                          weight: FontWeight.w700,
                          color: AppColors.primaryDark,
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
    );
  }
}
