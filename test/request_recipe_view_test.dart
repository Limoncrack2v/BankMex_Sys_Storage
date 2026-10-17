import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/domain/models/recipe_request.dart';
import 'package:bank_storage_app/ui/models/recipe.dart';
import 'package:bank_storage_app/ui/sample_data.dart';
import 'package:bank_storage_app/ui/screens/recipes/request_recipe_screen.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/option_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/large_text.dart' show expectNoBrokenWords;

final today = DateTime(2026, 10, 14);
var _nextId = 0;

PantryItem item(
  String productId,
  double quantity,
  FoodUnit unit,
  int days, {
  FoodType type = FoodType.produce,
}) => PantryItem(
  pantryItemId: 'item-${_nextId++}',
  productId: productId,
  deliveryId: 'entrega',
  type: type,
  quantity: quantity,
  unit: unit,
  daysUntilExpiration: days,
  deviceId: 'device',
  localTimestamp: today,
);

Member member(
  String name,
  MemberType type, {
  int? age,
  double? weightKg,
  List<Allergy> allergies = const [],
  List<ChronicCondition> conditions = const [],
}) => Member(
  memberId: name,
  name: name,
  memberType: type,
  createdAt: DateTime(2026, 9, 1),
  age: age,
  weightKg: weightKg,
  allergies: allergies,
  chronicConditions: conditions,
);

/// La despensa de tool/seed_emulators.mjs (días para caducar desde hoy).
final seedPantry = [
  item('Leche entera', 2, FoodUnit.l, 1, type: FoodType.dairy),
  item('Yogurt natural', 1, FoodUnit.kg, 2, type: FoodType.dairy),
  item('Plátano', 8, FoodUnit.piece, 2),
  item('Jamón de pavo', 250, FoodUnit.g, 3, type: FoodType.protein),
  item('Pan de caja', 1, FoodUnit.piece, 4, type: FoodType.grain),
  item('Jitomate', 3.5, FoodUnit.kg, 5),
  item('Queso panela', 400, FoodUnit.g, 6, type: FoodType.dairy),
  item('Salchicha', 500, FoodUnit.g, 8, type: FoodType.protein),
  item('Zanahoria', 3.5, FoodUnit.kg, 12),
  item('Avena', 1, FoodUnit.kg, 90, type: FoodType.grain),
  item('Pasta para sopa', 500, FoodUnit.g, 120, type: FoodType.grain),
  item('Aceite vegetal', 1, FoodUnit.l, 150, type: FoodType.other),
  item('Lenteja', 1, FoodUnit.kg, 180, type: FoodType.legume),
  item('Arroz', 2, FoodUnit.kg, 210, type: FoodType.grain),
  item('Frijol', 2, FoodUnit.kg, 240, type: FoodType.legume),
  item('Atún en lata', 3, FoodUnit.can, 300, type: FoodType.canned),
];

/// Los integrantes de la Familia Ramírez del seed: alergias a lácteos,
/// gluten, cacahuate y huevo, e hipertensión.
final seedMembers = [
  member(
    'María',
    MemberType.adult,
    age: 38,
    weightKg: 68,
    allergies: [Allergy.dairy],
  ),
  member(
    'José',
    MemberType.adult,
    age: 41,
    weightKg: 79,
    conditions: [ChronicCondition.hypertension],
  ),
  member(
    'Lucía',
    MemberType.child,
    age: 9,
    weightKg: 28,
    allergies: [Allergy.gluten],
  ),
  member(
    'Diego',
    MemberType.child,
    age: 5,
    weightKg: 19,
    allergies: [Allergy.peanut, Allergy.egg],
  ),
];

const seedAppliances = ['refrigerador', 'estufa'];

final jose = member(
  'José',
  MemberType.adult,
  conditions: [ChronicCondition.hypertension],
);

/// Todo lo del sándwich, que lleva jamón, y lo del arroz y las lentejas.
final hamPantry = [
  item('Jamón de pavo', 250, FoodUnit.g, 1, type: FoodType.protein),
  item('Pan de caja', 8, FoodUnit.piece, 2, type: FoodType.grain),
  item('Queso panela', 400, FoodUnit.g, 3, type: FoodType.dairy),
  item('Jitomate', 2, FoodUnit.kg, 5),
  item('Zanahoria', 1, FoodUnit.kg, 12),
  item('Aceite vegetal', 1, FoodUnit.l, 150, type: FoodType.other),
  item('Lenteja', 1, FoodUnit.kg, 180, type: FoodType.legume),
  item('Arroz', 2, FoodUnit.kg, 200, type: FoodType.grain),
  item('Atún en lata', 3, FoodUnit.can, 300, type: FoodType.canned),
];

/// Las letras de la app: con la letra de prueba cada carácter mide 1 em y la
/// revisión de 1.3x no diría nada de la pantalla real.
Future<void> loadFonts() async {
  final nunito = FontLoader('Nunito')
    ..addFont(rootBundle.load('assets/fonts/Nunito-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Nunito-Bold.ttf'));
  final baloo = FontLoader('Baloo2')
    ..addFont(rootBundle.load('assets/fonts/Baloo2-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Baloo2-Bold.ttf'));
  await Future.wait([nunito.load(), baloo.load()]);
}

Widget app(Widget body, {double textScale = 1}) => MaterialApp(
  theme: AppTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(body: body),
);

/// La vista con la búsqueda guardada como en RequestRecipeScreen, en un
/// teléfono de 360 de ancho y alto de sobra para que la lista arme todo.
/// Regresa las recetas que se abrieron.
Future<List<Recipe>> pumpView(
  WidgetTester tester, {
  List<Recipe> recipes = SampleData.recipes,
  List<PantryItem>? pantry,
  List<Member>? members,
  Set<String> loading = const {},
  bool pantryFailed = false,
  bool membersFailed = false,
  RecipeRequest request = const RecipeRequest(),
  double textScale = 1,
  double height = 2400,
}) async {
  tester.view.physicalSize = Size(360, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final opened = <Recipe>[];
  var current = request;
  await tester.pumpWidget(
    app(
      StatefulBuilder(
        builder: (context, setState) => RequestRecipeView(
          recipes: recipes,
          pantry: loading.contains('pantry') || pantryFailed
              ? null
              : pantry ?? seedPantry,
          pantryFailed: pantryFailed,
          members: loading.contains('members') || membersFailed
              ? null
              : members ?? seedMembers,
          membersFailed: membersFailed,
          appliances: loading.contains('appliances') ? null : seedAppliances,
          request: current,
          onRequestChanged: (changed) => setState(() => current = changed),
          onOpenRecipe: opened.add,
          today: today,
        ),
      ),
      textScale: textScale,
    ),
  );
  return opened;
}

Finder option(String label) => find.widgetWithText(OptionButton, label);

/// Si [text] se ve en la pantalla (no tapado ni fuera de la lista).
bool shows(String text) => find.text(text).hitTestable().evaluate().isNotEmpty;

Future<void> scrollToTop(WidgetTester tester) async {
  final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
  list.position.jumpTo(0);
  await tester.pump();
}

bool isSelected(WidgetTester tester, String label) =>
    tester.widget<OptionButton>(option(label)).selected;

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
}

Future<void> tapText(WidgetTester tester, String text) =>
    tap(tester, find.text(text));

void main() {
  setUpAll(loadFonts);

  testWidgets('without asking anything it suggests what uses the food that '
      'expires first', (tester) async {
    await pumpView(tester);

    expect(find.text('Sopa de lentejas'), findsOneWidget);
    expect(find.text('Usa Jitomate (caduca en 5 días)'), findsOneWidget);
    expect(find.text('Pronto'), findsOneWidget);
    expect(find.text('Tienes todos los ingredientes'), findsOneWidget);
    expect(isSelected(tester, 'Lo que sea'), isTrue);
    expect(isSelected(tester, 'Sin prisa'), isTrue);
    expect(find.textContaining('No encontramos'), findsNothing);
    expect(find.textContaining('no alcanza'), findsNothing);
  });

  testWidgets('offers as cravings the products that expire first and that '
      'some recipe for the family uses', (tester) async {
    await pumpView(
      tester,
      pantry: [
        ...seedPantry,
        item('Frijol negro', 1, FoodUnit.kg, 320, type: FoodType.legume),
      ],
    );

    final labels = tester
        .widgetList<OptionButton>(find.byType(OptionButton))
        .map((button) => button.label);
    expect(labels.take(7), [
      'Lo que sea',
      'Jitomate',
      'Zanahoria',
      'Lenteja',
      'Arroz',
      'Frijol',
      'Atún en lata',
    ]);
    // Solo seis. El aceite es de tipo "otro"; la leche y la avena solo las
    // usa una receta con alérgenos de la familia.
    expect(option('Frijol negro'), findsNothing);
    expect(option('Aceite vegetal'), findsNothing);
    expect(option('Leche entera'), findsNothing);
    expect(option('Avena'), findsNothing);
  });

  testWidgets('does not offer what only a recipe to avoid uses', (
    tester,
  ) async {
    await pumpView(tester, pantry: hamPantry, members: [jose]);

    // Solo el sándwich lleva jamón, pan y queso, y va al final por José.
    expect(option('Jamón de pavo'), findsNothing);
    expect(option('Pan de caja'), findsNothing);
    expect(option('Queso panela'), findsNothing);
    expect(option('Jitomate'), findsOneWidget);

    // Si todas las recetas llevan algo que evitar, se ofrece lo que usan.
    await pumpView(
      tester,
      recipes: const [SampleData.sandwichDeJamonYQueso],
      pantry: hamPantry,
      members: [jose],
    );
    expect(option('Jamón de pavo'), findsOneWidget);
  });

  testWidgets('a product option counts for the ingredient it stands for', (
    tester,
  ) async {
    final shake = Recipe(
      id: 'rec_licuado',
      name: 'Licuado de plátano',
      image: SampleData.avenaConFruta.image,
      minutes: 5,
      servings: 1,
      kcalPerServing: 150,
      ingredients: const [
        RecipeIngredient('Leche', 0.25, FoodUnit.l),
        RecipeIngredient('Plátano', 1, FoodUnit.piece),
      ],
      steps: const ['Licúa todo.'],
    );
    await pumpView(
      tester,
      recipes: [shake],
      pantry: [
        item('Leche entera', 1, FoodUnit.l, 3, type: FoodType.dairy),
        item('Plátano', 2, FoodUnit.piece, 2),
      ],
      members: const [],
    );

    await tap(tester, option('Leche entera'));

    expect(isSelected(tester, 'Leche entera'), isTrue);
    expect(find.textContaining('«Leche entera»'), findsNothing);
  });

  testWidgets('a time option asks for a recipe that fits', (tester) async {
    await pumpView(tester);

    await tap(tester, option('30 min'));

    expect(find.text('Arroz con atún'), findsOneWidget);
    expect(isSelected(tester, '30 min'), isTrue);
    expect(isSelected(tester, 'Sin prisa'), isFalse);
  });

  testWidgets('a product option asks for a recipe with it', (tester) async {
    await pumpView(tester);

    await tap(tester, option('Frijol'));

    expect(find.text('Frijoles de la olla'), findsOneWidget);
    expect(isSelected(tester, 'Frijol'), isTrue);
    expect(isSelected(tester, 'Lo que sea'), isFalse);
  });

  testWidgets('what is typed is the craving, not another option', (
    tester,
  ) async {
    await pumpView(tester);

    await tester.enterText(find.byType(TextField), 'frijoles');
    await tester.pump();
    expect(find.text('Frijoles de la olla'), findsOneWidget);
    expect(isSelected(tester, 'Lo que sea'), isFalse);
    expect(isSelected(tester, 'Frijol'), isFalse);
    expect(option('frijoles'), findsNothing);

    // Elegir una opción borra lo escrito.
    await tap(tester, option('Lo que sea'));
    expect(find.text('frijoles'), findsNothing);
    expect(find.text('Sopa de lentejas'), findsOneWidget);
  });

  testWidgets('keeps the chosen product as an option after it runs out', (
    tester,
  ) async {
    await pumpView(
      tester,
      request: const RecipeRequest(craving: 'Frijol', cravingIsProduct: true),
      pantry: [
        for (final item in seedPantry)
          if (item.productId != 'Frijol') item,
      ],
    );

    expect(isSelected(tester, 'Frijol'), isTrue);
  });

  testWidgets('"Otra receta" goes through every recipe for the family and '
      'then offers to start over', (tester) async {
    await pumpView(tester);

    await tapText(tester, 'Otra receta');
    expect(find.text('Arroz con atún'), findsOneWidget);
    await tapText(tester, 'Otra receta');
    expect(find.text('Frijoles de la olla'), findsOneWidget);
    await tapText(tester, 'Otra receta');

    expect(
      find.text('Ya te mostramos todas las recetas para tu familia.'),
      findsOneWidget,
    );
    expect(find.text('Otra receta'), findsNothing);
    expect(find.text('Ver receta'), findsNothing);

    await tapText(tester, 'Volver a empezar');
    expect(find.text('Sopa de lentejas'), findsOneWidget);
  });

  testWidgets('a new search forgets the recipes already seen, the same one '
      'does not', (tester) async {
    await pumpView(tester);
    await tapText(tester, 'Otra receta');
    expect(find.text('Arroz con atún'), findsOneWidget);

    await tap(tester, option('Sin prisa'));
    expect(find.text('Arroz con atún'), findsOneWidget);

    await tap(tester, option('Lo que sea'));
    expect(find.text('Arroz con atún'), findsOneWidget);

    await tap(tester, option('1 hora'));
    expect(find.text('Sopa de lentejas'), findsOneWidget);
  });

  testWidgets('says what the suggestion does not meet', (tester) async {
    await pumpView(tester);

    await tester.enterText(find.byType(TextField), 'pollo');
    await tester.pump();
    await tap(tester, option('15 min'));

    expect(find.text('Arroz con atún'), findsOneWidget);
    expect(
      find.text(
        'Esta receta tarda 30 min, más de los 15 que tienes.\n'
        'Esta receta no lleva «pollo».',
      ),
      findsOneWidget,
    );

    await tapText(tester, 'Otra receta');
    expect(find.text('Sopa de lentejas'), findsOneWidget);
    expect(
      find.text(
        'Esta receta tarda 40 min, más de los 15 que tienes.\n'
        'Esta receta no lleva «pollo».',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Te sugerimos esta'), findsNothing);
  });

  testWidgets('what the pantry lacks is said once, by the card', (
    tester,
  ) async {
    await pumpView(tester, pantry: const []);

    expect(find.text('Frijoles de la olla'), findsOneWidget);
    expect(find.text('Te falta 1 ingrediente'), findsOneWidget);
    expect(find.text('Tienes todos los ingredientes'), findsNothing);
    expect(find.textContaining('despensa'), findsNothing);

    await tapText(tester, 'Otra receta');
    expect(find.textContaining('despensa'), findsNothing);

    await tap(tester, option('15 min'));
    expect(find.textContaining('más de los 15 que tienes.'), findsOneWidget);
  });

  testWidgets('never says no recipe exists when one was left for health', (
    tester,
  ) async {
    // El sándwich alcanza, pero lleva jamón y José tiene hipertensión.
    await pumpView(
      tester,
      recipes: const [
        SampleData.sandwichDeJamonYQueso,
        SampleData.frijolesDeLaOlla,
      ],
      pantry: hamPantry,
      members: [jose],
    );

    expect(find.text('Frijoles de la olla'), findsOneWidget);
    expect(find.textContaining('ninguna'), findsNothing);
    expect(find.textContaining('No encontramos'), findsNothing);

    // El sándwich tarda 8 minutos, pero las lentejas van antes.
    await pumpView(
      tester,
      recipes: const [
        SampleData.sopaDeLentejas,
        SampleData.sandwichDeJamonYQueso,
      ],
      pantry: hamPantry,
      members: [jose],
      request: const RecipeRequest(maxPrepMinutes: 15),
    );
    expect(
      find.text('Esta receta tarda 40 min, más de los 15 que tienes.'),
      findsOneWidget,
    );
  });

  testWidgets('blames the suggestion, not the pantry, for a missed craving', (
    tester,
  ) async {
    await pumpView(
      tester,
      pantry: [
        item('Jitomate', 2, FoodUnit.kg, 5),
        item('Aceite vegetal', 1, FoodUnit.l, 150, type: FoodType.other),
        item('Arroz', 2, FoodUnit.kg, 200, type: FoodType.grain),
        item('Frijol', 2, FoodUnit.kg, 240, type: FoodType.legume),
        item('Atún en lata', 3, FoodUnit.can, 300, type: FoodType.canned),
      ],
      members: const [],
      request: const RecipeRequest(
        craving: 'Frijol',
        cravingIsProduct: true,
        maxPrepMinutes: 30,
      ),
    );

    // Los frijoles alcanzan, pero tardan 90 minutos.
    expect(find.text('Arroz con atún'), findsOneWidget);
    expect(find.text('Esta receta no lleva «Frijol».'), findsOneWidget);
  });

  testWidgets('counts "1 hora" as 60 minutes and says when the time is not '
      'known', (tester) async {
    await pumpView(
      tester,
      recipes: const [SampleData.frijolesDeLaOlla],
      request: const RecipeRequest(maxPrepMinutes: 60),
    );
    expect(isSelected(tester, '1 hora'), isTrue);
    expect(
      find.text('Esta receta tarda 90 min, más de los 60 que tienes.'),
      findsOneWidget,
    );

    await pumpView(
      tester,
      recipes: [
        Recipe(
          id: 'rec_pozole',
          name: 'Pozole',
          image: SampleData.frijolesDeLaOlla.image,
          minutes: 0,
          servings: 4,
          kcalPerServing: 300,
          ingredients: const [RecipeIngredient('Frijol', 0.5, FoodUnit.kg)],
          steps: const ['Cocina todo.'],
        ),
      ],
      request: const RecipeRequest(maxPrepMinutes: 15),
    );
    expect(find.text('No sabemos cuánto tarda esta receta.'), findsOneWidget);
  });

  testWidgets('warns about a chronic condition when nothing else is left', (
    tester,
  ) async {
    await pumpView(
      tester,
      recipes: const [SampleData.sandwichDeJamonYQueso],
      members: [
        member(
          'José',
          MemberType.adult,
          conditions: [ChronicCondition.hypertension],
        ),
      ],
    );

    expect(find.text('Sándwich de jamón y queso'), findsOneWidget);
    expect(
      find.text(
        'Cuidado: esta receta lleva Jamón de pavo, que conviene evitar con '
        'hipertensión (José).',
      ),
      findsOneWidget,
    );
  });

  testWidgets('opens the catalog recipe, not the one scaled to the family', (
    tester,
  ) async {
    final opened = await pumpView(tester);

    await tapText(tester, 'Ver receta');
    await tapText(tester, 'Sopa de lentejas');

    expect(opened, hasLength(2));
    expect(opened, everyElement(same(SampleData.sopaDeLentejas)));
  });

  testWidgets('suggests nothing when the members could not be read', (
    tester,
  ) async {
    await pumpView(tester, membersFailed: true);

    expect(
      find.text(
        'No pudimos revisar las alergias de tu familia. Revisa tu conexión '
        'e intenta de nuevo.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ver receta'), findsNothing);
    expect(find.byType(OptionButton), findsNothing);
  });

  testWidgets('suggests nothing when the pantry could not be read', (
    tester,
  ) async {
    await pumpView(tester, pantryFailed: true);

    expect(
      find.text(
        'No pudimos cargar tu despensa. Revisa tu conexión e intenta de '
        'nuevo.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ver receta'), findsNothing);
  });

  testWidgets('waits for the pantry, the members and the appliances', (
    tester,
  ) async {
    for (final loading in [
      {'pantry', 'members', 'appliances'},
      {'pantry'},
      {'members'},
      {'appliances'},
    ]) {
      await pumpView(tester, loading: loading);

      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
        reason: '$loading',
      );
      expect(find.byType(OptionButton), findsNothing, reason: '$loading');
    }
  });

  testWidgets('says when no recipe suits the family', (tester) async {
    await pumpView(
      tester,
      recipes: const [
        SampleData.avenaConFruta,
        SampleData.sopaDePastaConVerduras,
      ],
    );

    expect(
      find.text(
        'No hay recetas que podamos sugerirte: todas llevan algo a lo que '
        'alguien de tu familia tiene alergia o piden un electrodoméstico que '
        'no tienes.',
      ),
      findsOneWidget,
    );
    expect(find.byType(OptionButton), findsNothing);
    expect(find.text('Ver receta'), findsNothing);
  });

  testWidgets('shows no freshness pill when nothing comes from the pantry', (
    tester,
  ) async {
    await pumpView(tester, pantry: const []);

    expect(find.text('Frijoles de la olla'), findsOneWidget);
    expect(find.text('Fresco'), findsNothing);
  });

  testWidgets('screen readers hear when the suggestion changes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpView(tester);

    expect(
      tester.getSemantics(find.text('Sopa de lentejas')),
      isSemantics(isLiveRegion: true),
    );
    semantics.dispose();
  });

  testWidgets('brings the new suggestion into view', (tester) async {
    // La lista en un teléfono de 360 x 740, sin el encabezado.
    await pumpView(tester, height: 644);
    expect(shows('Sopa de lentejas'), isFalse);

    await tap(tester, option('30 min'));
    await tester.pumpAndSettle();
    expect(shows('Arroz con atún'), isTrue);

    await scrollToTop(tester);
    await tap(tester, option('Sin prisa'));
    await tester.pumpAndSettle();
    expect(shows('Sopa de lentejas'), isTrue);

    await scrollToTop(tester);
    await tap(tester, option('Frijol'));
    await tester.pumpAndSettle();
    expect(shows('Frijoles de la olla'), isTrue);

    await scrollToTop(tester);
    await tester.enterText(find.byType(TextField), 'arroz');
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(shows('Arroz con atún'), isTrue);
    // La tecla de buscar cierra el teclado.
    expect(field.focusNode.hasFocus, isFalse);

    await tester.ensureVisible(find.text('Otra receta'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Otra receta');
    await tester.pumpAndSettle();
    expect(shows('Sopa de lentejas'), isTrue);
  });

  testWidgets('the card on Recetas opens the screen', (tester) async {
    var opened = 0;
    await tester.pumpWidget(app(RequestRecipeCard(onPressed: () => opened++)));

    expect(find.text('¿No sabes qué cocinar?'), findsOneWidget);
    await tapText(tester, 'Pedir una receta');
    expect(opened, 1);
  });

  testWidgets('fits a 360-wide phone with large text', (tester) async {
    await pumpView(tester, textScale: 1.3);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField), 'pollo');
    await tester.pump();
    await tap(tester, option('15 min'));
    expect(find.textContaining('«pollo»'), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (var i = 0; i < 3; i++) {
      await tapText(tester, 'Otra receta');
    }
    expect(find.text('Volver a empezar'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      app(
        Padding(
          padding: const EdgeInsets.all(16),
          child: RequestRecipeCard(onPressed: () {}),
        ),
        textScale: 1.3,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('with even larger text the pills wrap instead of overflowing', (
    tester,
  ) async {
    for (final scale in [1.35, 1.5]) {
      await pumpView(tester, textScale: scale);
      expect(find.text('Tienes todos los ingredientes'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expectNoBrokenWords(tester);
    }
  });
}
