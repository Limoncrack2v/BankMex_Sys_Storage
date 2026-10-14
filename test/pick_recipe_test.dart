import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/domain/catalog_mappers.dart';
import 'package:bank_storage_app/domain/models/recipe.dart' as domain;
import 'package:bank_storage_app/domain/models/recipe_request.dart';
import 'package:bank_storage_app/ui/models/expiration_urgency.dart';
import 'package:bank_storage_app/ui/models/recipe.dart';
import 'package:bank_storage_app/ui/sample_data.dart';
import 'package:flutter_test/flutter_test.dart';

final today = DateTime(2026, 10, 14);
var _nextId = 0;

/// [days] para caducar contados desde [registered] (hoy si no se da).
PantryItem item(
  String productId,
  double quantity,
  FoodUnit unit,
  int days, {
  DateTime? registered,
}) => PantryItem(
  pantryItemId: 'item-${_nextId++}',
  productId: productId,
  deliveryId: 'entrega',
  type: FoodType.other,
  quantity: quantity,
  unit: unit,
  daysUntilExpiration: days,
  deviceId: 'device',
  localTimestamp: registered ?? today,
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
  item('Leche entera', 2, FoodUnit.l, 1),
  item('Yogurt natural', 1, FoodUnit.kg, 2),
  item('Plátano', 8, FoodUnit.piece, 2),
  item('Jamón de pavo', 250, FoodUnit.g, 3),
  item('Pan de caja', 1, FoodUnit.piece, 4),
  item('Jitomate', 3.5, FoodUnit.kg, 5),
  item('Queso panela', 400, FoodUnit.g, 6),
  item('Salchicha', 500, FoodUnit.g, 8),
  item('Zanahoria', 3.5, FoodUnit.kg, 12),
  item('Avena', 1, FoodUnit.kg, 90),
  item('Pasta para sopa', 500, FoodUnit.g, 120),
  item('Aceite vegetal', 1, FoodUnit.l, 150),
  item('Lenteja', 1, FoodUnit.kg, 180),
  item('Arroz', 2, FoodUnit.kg, 210),
  item('Frijol', 2, FoodUnit.kg, 240),
  item('Atún en lata', 3, FoodUnit.can, 300),
];

/// Los integrantes de la Familia Ramírez del seed.
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

RecipeSuggestion? pick({
  RecipeRequest request = const RecipeRequest(),
  List<Recipe> recipes = SampleData.recipes,
  List<PantryItem>? pantry,
  List<Member>? members,
  List<String> appliances = seedAppliances,
}) => pickRecipe(
  recipes,
  pantry ?? seedPantry,
  members: members ?? seedMembers,
  householdAppliances: appliances,
  request: request,
  today: today,
);

/// Lo que se ve al tocar "Otra receta" hasta que ya no queda ninguna.
List<String> showAll({List<Recipe> recipes = SampleData.recipes}) {
  var request = const RecipeRequest();
  final shown = <String>[];
  for (
    var suggestion = pick(request: request, recipes: recipes);
    suggestion != null;
    suggestion = pick(request: request, recipes: recipes)
  ) {
    shown.add(suggestion.recipe.name);
    // Si la exclusión fallara, el ciclo no terminaría.
    if (shown.length > recipes.length) fail('pickRecipe repitió: $shown');
    request = request.excluding(recipeKey(suggestion.recipe));
  }
  return shown;
}

Recipe withoutId(Recipe recipe) => Recipe(
  name: recipe.name,
  image: recipe.image,
  minutes: recipe.minutes,
  servings: recipe.servings,
  kcalPerServing: recipe.kcalPerServing,
  ingredients: recipe.ingredients,
  steps: recipe.steps,
  requiredEquipment: recipe.requiredEquipment,
);

/// [recipe] como llega de recipes/{id}: otra instancia con los mismos datos.
Recipe fromFirestore(Recipe recipe) => CatalogMappers.recipeToUi(
  domain.Recipe(
    id: recipe.id,
    name: recipe.name,
    ingredients: [
      for (final ingredient in recipe.ingredients)
        domain.RecipeIngredient(
          productName: ingredient.name,
          quantity: ingredient.quantity,
          unit: ingredient.unit.name,
        ),
    ],
    steps: recipe.steps,
    prepTimeMinutes: recipe.minutes,
    caloriesPerServing: recipe.kcalPerServing,
    status: domain.RecipeStatus.approved,
    requiredEquipment: recipe.requiredEquipment,
    servings: recipe.servings,
  ),
);

/// Una receta aprobada de recipes/{id} con solo los campos de [data].
Recipe fromDoc(Map<String, dynamic> data) => CatalogMappers.recipeToUi(
  domain.Recipe.fromMap('doc', {...data, 'status': 'approved'}),
);

Recipe recipe(String name, List<RecipeIngredient> ingredients) => Recipe(
  name: name,
  image: '',
  minutes: 5,
  servings: 1,
  kcalPerServing: 100,
  ingredients: ingredients,
  steps: const ['Paso 1.'],
);

void main() {
  test('recipeKey is the catalog id, or the name without one', () {
    expect(recipeKey(SampleData.arrozConAtun), 'rec_arroz_atun');
    expect(recipeKey(withoutId(SampleData.arrozConAtun)), 'arroz con atun');
  });

  group('matchesCraving', () {
    test('finds the craving in the name or in an ingredient', () {
      expect(matchesCraving(SampleData.sopaDeLentejas, 'sopa'), isTrue);
      expect(matchesCraving(SampleData.sopaDeLentejas, 'lentejas'), isTrue);
      expect(matchesCraving(SampleData.arrozConAtun, 'Atún'), isTrue);
      expect(matchesCraving(SampleData.avenaConFruta, 'Leche'), isTrue);
    });

    test('ignores accents, case and plurals', () {
      expect(matchesCraving(SampleData.arrozConAtun, 'atun'), isTrue);
      expect(matchesCraving(SampleData.arrozConAtun, 'JITOMATES'), isTrue);
      expect(matchesCraving(SampleData.frijolesDeLaOlla, 'frijoles'), isTrue);
    });

    test('a pantry product matches the ingredient it stands for', () {
      final shake = recipe('Licuado', const [
        RecipeIngredient('Leche', 0.2, FoodUnit.l),
      ]);

      expect(matchesCraving(shake, 'Leche entera', product: true), isTrue);
      // Escrito, "entera" también tiene que estar en la receta.
      expect(matchesCraving(shake, 'Leche entera'), isFalse);
      expect(
        pick(
          recipes: [shake],
          pantry: const [],
          members: const [],
          request: const RecipeRequest(
            craving: 'Leche entera',
            cravingIsProduct: true,
          ),
        )!.matchesCraving,
        isTrue,
      );
    });

    test('compares whole words, in any order', () {
      final salad = recipe('Ensalada', const [
        RecipeIngredient('Queso panela', 0.1, FoodUnit.kg),
      ]);

      expect(matchesCraving(salad, 'pan'), isFalse);
      expect(matchesCraving(salad, 'pan', product: true), isFalse);
      expect(
        matchesCraving(SampleData.sopaDePastaConVerduras, 'pasta sopa'),
        isTrue,
      );
      expect(
        matchesCraving(SampleData.sopaDePastaConVerduras, 'sopa de pasta'),
        isTrue,
      );
    });

    test('a typed dish needs every word, not just one ingredient', () {
      final arroz = SampleData.arrozConAtun;

      expect(matchesCraving(arroz, 'arroz con pollo'), isFalse);
      expect(matchesCraving(arroz, 'arroz con leche'), isFalse);
      expect(matchesCraving(arroz, 'atún con arroz'), isTrue);
      expect(
        matchesCraving(SampleData.sopaDeLentejas, 'lentejas con zanahoria'),
        isTrue,
      );
      expect(
        pick(request: const RecipeRequest(craving: 'arroz con pollo'))!
            .matchesCraving,
        isFalse,
      );
    });

    test('an unknown craving does not match and a blank one always does', () {
      expect(matchesCraving(SampleData.arrozConAtun, 'pollo'), isFalse);
      expect(matchesCraving(SampleData.arrozConAtun, '  '), isTrue);
    });
  });

  group('allergen names', () {
    test('knows common names of each allergen in a Mexican pantry', () {
      const names = {
        Allergy.gluten: [
          'Fideo',
          'Espagueti',
          'Spaghetti',
          'Macarrones',
          'Coditos',
          'Lasaña',
          'Bolillos',
          'Telera',
          'Empanadas',
          'Panqué',
          'Cebada',
          'Centeno',
          'Cuscús',
        ],
        Allergy.egg: ['Mayonesa', 'Merengues'],
        Allergy.dairy: ['Requesón', 'Jocoque', 'Nata', 'Helado de vainilla'],
        Allergy.shellfish: [
          'Langosta',
          'Langostinos',
          'Almejas',
          'Mejillones',
          'Ostiones',
        ],
      };

      for (final MapEntry(key: allergy, value: ingredients) in names.entries) {
        for (final ingredient in ingredients) {
          expect(
            containsAllergen(ingredient, allergy),
            isTrue,
            reason: '$ingredient (${allergy.name})',
          );
        }
      }
    });

    test('a recipe with one of them is never suggested', () {
      final lucia = member(
        'Lucía',
        MemberType.child,
        age: 9,
        allergies: [Allergy.gluten],
      );

      expect(
        pick(
          recipes: [
            recipe('Sopa de fideo', const [
              RecipeIngredient('Fideo', 0.2, FoodUnit.kg),
            ]),
          ],
          pantry: const [],
          members: [lucia],
        ),
        isNull,
      );
    });
  });

  group('recipesForHousehold', () {
    test('drops allergens and missing appliances', () {
      final names = recipesForHousehold(
        SampleData.recipes,
        members: seedMembers,
        householdAppliances: seedAppliances,
      ).map((recipe) => recipe.name);

      expect(names, [
        'Sopa de lentejas',
        'Arroz con atún',
        'Frijoles de la olla',
      ]);
    });

    test('an empty appliance list means unknown, not none', () {
      expect(
        lacksAppliance(SampleData.sopaDePastaConVerduras, const []),
        isFalse,
      );
      expect(
        lacksAppliance(SampleData.sopaDePastaConVerduras, seedAppliances),
        isTrue,
      );
      expect(
        recipesForHousehold(SampleData.recipes, members: const []),
        SampleData.recipes,
      );
    });

    test('a recipe that needs no appliance suits any household', () {
      expect(lacksAppliance(recipe('Licuado', const []), ['estufa']), isFalse);
    });
  });

  group('cravingOptions', () {
    test('lists what the suitable recipes use, soonest first', () {
      final suitable = recipesForHousehold(
        SampleData.recipes,
        members: seedMembers,
        householdAppliances: seedAppliances,
      );

      expect(cravingOptions(suitable, seedPantry, today: today), [
        'Jitomate',
        'Zanahoria',
        'Aceite vegetal',
        'Lenteja',
        'Arroz',
        'Frijol',
        'Atún en lata',
      ]);
    });

    test('skips expired and empty items but keeps one that expires today', () {
      final options = cravingOptions(
        const [SampleData.sopaDeLentejas],
        [
          item(
            'Lenteja',
            1,
            FoodUnit.kg,
            5,
            registered: today.subtract(const Duration(days: 10)),
          ),
          item('Jitomate', 0, FoodUnit.kg, 30),
          item(
            'Zanahoria',
            1,
            FoodUnit.kg,
            2,
            registered: today.subtract(const Duration(days: 2)),
          ),
          item('Aceite vegetal', 1, FoodUnit.l, 100),
        ],
        today: today,
      );

      expect(options, ['Zanahoria', 'Aceite vegetal']);
    });

    test('names a product once, where its soonest item goes', () {
      final options = cravingOptions(
        const [SampleData.arrozConAtun],
        [
          item('Arroz', 1, FoodUnit.kg, 200),
          item('Jitomate', 1, FoodUnit.kg, 30),
          item('Atún en lata', 2, FoodUnit.can, 30),
          item('arroz', 1, FoodUnit.kg, 3),
        ],
        today: today,
      );

      // Atún y Jitomate caducan el mismo día: van por nombre.
      expect(options, ['Arroz', 'Atún en lata', 'Jitomate']);
    });

    test('skips what no recipe uses and units that do not convert', () {
      final options = cravingOptions(
        const [SampleData.arrozConAtun],
        [
          item('Salchicha', 500, FoodUnit.g, 8),
          // La receta pide Jitomate en kg.
          item('Jitomate', 3, FoodUnit.piece, 5),
          item('Arroz', 1, FoodUnit.kg, 200),
        ],
        today: today,
      );

      expect(options, ['Arroz']);
    });
  });

  group('pickRecipe', () {
    test('picks what uses the food that expires first, with what there is', () {
      final suggestion = pick()!;

      expect(suggestion.recipe, same(SampleData.sopaDeLentejas));
      expect(suggestion.fitsPantry, isTrue);
      expect(suggestion.reason, 'Usa Jitomate (caduca en 5 días)');
      expect(suggestion.urgency, ExpirationUrgency.soon);
      expect(suggestion.fitsTime, isTrue);
      expect(suggestion.matchesCraving, isTrue);
      expect(suggestion.avoidsConditions, isTrue);
    });

    test('says whether it uses anything from the pantry', () {
      expect(pick()!.usesPantry, isTrue);

      final nothing = pick(pantry: const [])!;
      expect(nothing.usesPantry, isFalse);
      expect(nothing.reason, 'Te falta 1 ingrediente');
    });

    test('keeps the catalog recipe to open and the scaled one to show', () {
      final suggestion = pick()!;
      final scaled = scaledForHousehold(SampleData.sopaDeLentejas, seedMembers);

      expect(suggestion.recipe.ingredients.first.quantity, 0.25);
      expect(
        suggestion.scaled.ingredients.first.quantity,
        scaled.ingredients.first.quantity,
      );
      expect(suggestion.scaled.ingredients.first.quantity, lessThan(0.25));
    });

    test('"Otra receta" never repeats until every recipe was shown', () {
      expect(showAll(), [
        'Sopa de lentejas',
        'Arroz con atún',
        'Frijoles de la olla',
      ]);
    });

    test('"Volver a empezar" shows the first recipe again', () {
      final seen = const RecipeRequest()
          .excluding('rec_sopa_lentejas')
          .excluding('rec_arroz_atun')
          .excluding('rec_frijoles');

      expect(pick(request: seen), isNull);
      expect(pick(request: seen.restarted())!.recipe.name, 'Sopa de lentejas');
    });

    test('recipes without an id are told apart by their name', () {
      expect(showAll(recipes: SampleData.recipes.map(withoutId).toList()), [
        'Sopa de lentejas',
        'Arroz con atún',
        'Frijoles de la olla',
      ]);
    });

    test('what was seen in SampleData stays seen in the Firestore catalog', () {
      final seen = const RecipeRequest().excluding(recipeKey(pick()!.recipe));
      final firestore = SampleData.recipes.map(fromFirestore).toList();

      expect(pick(recipes: firestore)!.recipe.name, 'Sopa de lentejas');
      expect(
        pick(recipes: firestore, request: seen)!.recipe.name,
        'Arroz con atún',
      );
    });

    test('respects the time available', () {
      final suggestion = pick(
        request: const RecipeRequest(maxPrepMinutes: 30),
      )!;

      expect(suggestion.recipe.name, 'Arroz con atún');
      expect(suggestion.fitsTime, isTrue);
    });

    test('with no recipe that short, the closest one and says so', () {
      final suggestion = pick(
        request: const RecipeRequest(maxPrepMinutes: 15),
      )!;

      expect(suggestion.recipe.name, 'Arroz con atún');
      expect(suggestion.fitsTime, isFalse);
    });

    test('prefers the craving', () {
      final suggestion = pick(
        request: const RecipeRequest(craving: 'frijoles'),
      )!;

      expect(suggestion.recipe.name, 'Frijoles de la olla');
      expect(suggestion.matchesCraving, isTrue);
    });

    test('an unknown craving falls back to the best recipe and says so', () {
      final suggestion = pick(request: const RecipeRequest(craving: 'pollo'))!;

      expect(suggestion.recipe.name, 'Sopa de lentejas');
      expect(suggestion.matchesCraving, isFalse);
    });

    test('time beats craving, and the craving breaks the tie after', () {
      final quick = pick(
        request: const RecipeRequest(craving: 'frijol', maxPrepMinutes: 30),
      )!;
      expect(quick.recipe.name, 'Arroz con atún');
      expect((quick.fitsTime, quick.matchesCraving), (true, false));

      final nothingFits = pick(
        request: const RecipeRequest(craving: 'frijol', maxPrepMinutes: 15),
      )!;
      expect(nothingFits.recipe.name, 'Frijoles de la olla');
      expect((nothingFits.fitsTime, nothingFits.matchesCraving), (false, true));
    });

    test('what the pantry covers beats time and craving', () {
      final suggestion = pick(
        request: const RecipeRequest(craving: 'atún', maxPrepMinutes: 30),
        pantry: [
          for (final item in seedPantry)
            if (item.productId != 'Atún en lata') item,
        ],
      )!;

      // Arroz con atún cabe en el tiempo y tiene el antojo, pero sin atún no
      // alcanza; de las que alcanzan, la de lentejas es la que menos se pasa.
      expect(suggestion.recipe.name, 'Sopa de lentejas');
      expect(suggestion.fitsPantry, isTrue);
      expect((suggestion.fitsTime, suggestion.matchesCraving), (false, false));
    });

    test('if none is fully covered, the one missing the fewest', () {
      final closest = pick(
        pantry: [
          item('Jitomate', 1, FoodUnit.kg, 1),
          item('Frijol', 0.4, FoodUnit.kg, 200),
        ],
        members: const [],
        appliances: const [],
      )!;
      // Las demás usan el jitomate que caduca mañana, pero les faltan 3.
      expect(closest.recipe.name, 'Frijoles de la olla');
      expect(closest.missing, 1);

      // Antes que el tiempo: con 15 minutos ninguna cabe ni alcanza.
      final quick = pick(
        pantry: const [],
        request: const RecipeRequest(maxPrepMinutes: 15),
      )!;
      expect(quick.recipe.name, 'Frijoles de la olla');
      expect((quick.missing, quick.fitsTime), (1, false));
    });

    test('never suggests an allergen, even if it is the only full recipe', () {
      final suggestion = pick(
        recipes: const [SampleData.avenaConFruta, SampleData.frijolesDeLaOlla],
        pantry: [
          item('Avena', 1, FoodUnit.kg, 30),
          item('Leche entera', 1, FoodUnit.l, 1),
          item('Plátano', 6, FoodUnit.piece, 2),
        ],
        members: [
          member(
            'Lucía',
            MemberType.child,
            age: 9,
            allergies: [Allergy.gluten],
          ),
        ],
      )!;

      expect(suggestion.recipe.name, 'Frijoles de la olla');
      expect(suggestion.fitsPantry, isFalse);
      expect(suggestion.reason, 'Te falta 1 ingrediente');
    });

    test('leaves last what a chronic condition should avoid', () {
      final jose = member(
        'José',
        MemberType.adult,
        conditions: [ChronicCondition.hypertension],
      );
      // El sándwich alcanza y lleva jamón; a los frijoles les falta el frijol.
      final pantry = [
        item('Pan de caja', 4, FoodUnit.piece, 4),
        item('Jamón de pavo', 250, FoodUnit.g, 3),
        item('Queso panela', 400, FoodUnit.g, 6),
        item('Jitomate', 1, FoodUnit.kg, 5),
      ];
      const recipes = [
        SampleData.sandwichDeJamonYQueso,
        SampleData.frijolesDeLaOlla,
      ];

      final suggestion = pick(
        recipes: recipes,
        pantry: pantry,
        members: [jose],
      )!;
      expect(suggestion.recipe.name, 'Frijoles de la olla');
      expect(suggestion.avoidsConditions, isTrue);
      expect(suggestion.fitsPantry, isFalse);

      final last = pick(
        recipes: recipes,
        pantry: pantry,
        members: [jose],
        request: const RecipeRequest().excluding('rec_frijoles'),
      )!;
      expect(last.recipe.name, 'Sándwich de jamón y queso');
      expect(last.avoidsConditions, isFalse);
      expect(last.fitsPantry, isTrue);
    });

    test(
      'an expired item neither covers an ingredient nor gives the reason',
      () {
        final expired = pick(
          recipes: const [SampleData.frijolesDeLaOlla],
          members: const [],
          pantry: [
            item(
              'Frijol',
              2,
              FoodUnit.kg,
              5,
              registered: today.subtract(const Duration(days: 10)),
            ),
          ],
        )!;
        expect(expired.fitsPantry, isFalse);
        expect(expired.reason, 'Te falta 1 ingrediente');
        expect(expired.urgency, ExpirationUrgency.fresh);

        final lastDay = pick(
          recipes: const [SampleData.frijolesDeLaOlla],
          members: const [],
          pantry: [
            item(
              'Frijol',
              2,
              FoodUnit.kg,
              3,
              registered: today.subtract(const Duration(days: 3)),
            ),
          ],
        )!;
        expect(lastDay.fitsPantry, isTrue);
        expect(lastDay.reason, 'Usa Frijol (caduca hoy)');
        expect(lastDay.urgency, ExpirationUrgency.urgent);
      },
    );

    test('skips an approved recipe saved without ingredients', () {
      final empty = fromDoc({'name': 'Receta a medias', 'prepTimeMinutes': 20});

      expect(recipesForHousehold([empty], members: const []), isEmpty);
      expect(
        pick(
          recipes: [empty, SampleData.frijolesDeLaOlla],
          pantry: const [],
          members: const [],
        )!.recipe.name,
        'Frijoles de la olla',
      );
    });

    test('a recipe saved without a time never fits the time asked', () {
      final pozole = fromDoc({
        'name': 'Pozole',
        'ingredients': [
          {'productName': 'Maíz', 'quantity': 1, 'unit': 'kg'},
        ],
      });
      RecipeSuggestion? quick(List<Recipe> recipes) => pick(
        recipes: recipes,
        pantry: const [],
        members: const [],
        request: const RecipeRequest(maxPrepMinutes: 15),
      );

      expect(pozole.minutes, 0);
      expect(quick([pozole])!.fitsTime, isFalse);
      // Si ninguna cabe, va después de las que tardan de más.
      expect(
        quick([pozole, SampleData.frijolesDeLaOlla])!.recipe.name,
        'Frijoles de la olla',
      );
    });

    test('is null when nothing suits the household', () {
      expect(
        pick(
          recipes: const [
            SampleData.avenaConFruta,
            SampleData.sopaDePastaConVerduras,
          ],
        ),
        isNull,
      );
      expect(pick(recipes: const []), isNull);
    });
  });
}
