import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/ui/models/expiration_urgency.dart';
import 'package:bank_storage_app/ui/models/recipe.dart';
import 'package:bank_storage_app/ui/sample_data.dart';

/// Lunes.
final today = DateTime(2026, 9, 21);
var _nextId = 0;

PantryItem item(
  String productId,
  double quantity,
  FoodUnit unit, {
  int days = 30,
  DateTime? registered,
}) => PantryItem(
  pantryItemId: 'item-${_nextId++}',
  productId: productId,
  deliveryId: 'entrega-001',
  type: FoodType.other,
  quantity: quantity,
  unit: unit,
  daysUntilExpiration: days,
  synchronized: true,
  deviceId: 'device-test',
  localTimestamp: registered ?? today,
);

Recipe recipe(
  List<RecipeIngredient> ingredients, {
  String name = 'Prueba',
  int servings = 2,
}) => Recipe(
  name: name,
  image: '',
  minutes: 10,
  servings: servings,
  kcalPerServing: 100,
  ingredients: ingredients,
  steps: const ['Paso 1.'],
);

Member member(String name, {List<Allergy>? allergies}) => Member(
  memberId: 'member-${_nextId++}',
  name: name,
  memberType: MemberType.adult,
  createdAt: DateTime(2026, 9, 1),
  allergies: allergies,
);

List<double> quantities(Recipe recipe) =>
    recipe.ingredients.map((i) => i.quantity).toList();

void main() {
  group('scaledRecipe', () {
    test('multiplies every quantity by household / servings', () {
      final scaled = scaledRecipe(SampleData.sopaDeLentejas, 6);

      expect(scaled.servings, 6);
      expect(quantities(scaled), [0.375, 0.75, 0.45, 0.075]);
      expect(scaled.ingredients.map((i) => i.unit), [
        FoodUnit.kg,
        FoodUnit.kg,
        FoodUnit.kg,
        FoodUnit.l,
      ]);
      expect(scaled.name, SampleData.sopaDeLentejas.name);
      expect(scaled.kcalPerServing, SampleData.sopaDeLentejas.kcalPerServing);
      expect(scaled.steps, SampleData.sopaDeLentejas.steps);
      expect(
        scaledRecipe(SampleData.sopaDeLentejas, 2).ingredients.first.amount,
        '0.125 kg',
      );
    });

    test('rounds to 3 decimals and never down to 0', () {
      final base = recipe(const [
        RecipeIngredient('Arroz', 0.1, FoodUnit.kg),
        RecipeIngredient('Aceite', 0.25, FoodUnit.l),
        RecipeIngredient('Sal', 0.001, FoodUnit.kg),
      ], servings: 3);

      expect(quantities(scaledRecipe(base, 2)), [0.067, 0.167, 0.001]);
      expect(quantities(scaledRecipe(base, 1)), [0.033, 0.083, 0.001]);
    });

    test('rounds pieces, cans and packs up to whole numbers', () {
      expect(quantities(scaledRecipe(SampleData.avenaConFruta, 3)), [
        0.225,
        0.75,
        3,
      ]);
      // 2 latas para 4 porciones: 1.5 latas para 3 -> 2, 0.5 para 1 -> 1.
      expect(quantities(scaledRecipe(SampleData.arrozConAtun, 3))[1], 2);
      expect(quantities(scaledRecipe(SampleData.arrozConAtun, 1))[1], 1);
      expect(
        quantities(scaledRecipe(SampleData.sandwichDeJamonYQueso, 3)).first,
        6,
      );
      final packs = recipe(const [
        RecipeIngredient('Galletas', 1, FoodUnit.pack),
      ], servings: 8);
      expect(quantities(scaledRecipe(packs, 1)), [1]);
      expect(quantities(scaledRecipe(packs, 9)), [2]);
    });

    test('floating point noise does not add an extra piece', () {
      // 3 * 7 / 3 = 7.000000000000001 en punto flotante.
      final base = recipe(const [
        RecipeIngredient('Plátano', 3, FoodUnit.piece),
      ], servings: 3);

      expect(quantities(scaledRecipe(base, 7)), [7]);
    });

    test('keeps the recipe as is when the household is unknown or equal', () {
      final base = SampleData.avenaConFruta;

      expect(scaledRecipe(base, 0), same(base));
      expect(scaledRecipe(base, -1), same(base));
      expect(scaledRecipe(base, base.servings), same(base));
    });

    test('the scaled recipe drives availability and consumption', () {
      final pantry = [
        item('Avena', 1, FoodUnit.kg),
        item('Leche entera', 0.8, FoodUnit.l),
        item('Plátano', 8, FoodUnit.piece),
      ];
      final forFour = scaledRecipe(SampleData.avenaConFruta, 4);

      expect(
        checkAvailability(
          forFour,
          pantry,
          today: today,
        ).map((a) => a.available),
        [true, false, true],
      );
      final plan = planConsumption(forFour, pantry, today: today);
      expect(plan.map((c) => c.amount), [0.3, 0.8, 4]);
    });
  });

  group('allergyConflicts', () {
    test('finds the ingredient and the allergic member', () {
      final conflicts = allergyConflicts(SampleData.avenaConFruta, [
        member('María', allergies: const [Allergy.dairy]),
        member('Diego', allergies: const []),
        member('Ana'),
      ]);

      expect(conflicts, hasLength(1));
      expect(conflicts.single.allergy, Allergy.dairy);
      expect(conflicts.single.members, ['María']);
      expect(conflicts.single.ingredients, ['Leche entera']);
      expect(
        allergyWarning(conflicts.single),
        'Atención: esta receta contiene lácteos (Leche entera), y María '
        'tiene alergia.',
      );
    });

    test('ignores accents, case and plurals', () {
      expect(containsAllergen('Camarones', Allergy.shellfish), isTrue);
      expect(containsAllergen('Ostiones frescos', Allergy.shellfish), isTrue);
      expect(containsAllergen('Maní tostado', Allergy.peanut), isTrue);
      expect(containsAllergen('Cacahuates', Allergy.peanut), isTrue);
      expect(containsAllergen('QUESOS', Allergy.dairy), isTrue);
      expect(containsAllergen('Yogures', Allergy.dairy), isTrue);
      expect(containsAllergen('Huevos', Allergy.egg), isTrue);
      expect(containsAllergen('Panes', Allergy.gluten), isTrue);
      expect(containsAllergen('Tortillas de harina', Allergy.gluten), isTrue);
      expect(containsAllergen('Cereales', Allergy.gluten), isTrue);
      expect(containsAllergen('Salsa de soja', Allergy.soy), isTrue);
    });

    test('compares whole words, not pieces of words', () {
      expect(containsAllergen('Lechuga', Allergy.dairy), isFalse);
      expect(containsAllergen('Queso panela', Allergy.gluten), isFalse);
      expect(containsAllergen('Empanada', Allergy.gluten), isFalse);
      expect(containsAllergen('Arroz', Allergy.gluten), isFalse);
      expect(containsAllergen('Jamón de pavo', Allergy.egg), isFalse);
    });

    test('groups members by allergy, in the order of Allergy', () {
      final conflicts = allergyConflicts(SampleData.sandwichDeJamonYQueso, [
        member('Diego', allergies: const [Allergy.gluten, Allergy.dairy]),
        member(' María ', allergies: const [Allergy.dairy]),
        member('Ana', allergies: const [Allergy.shellfish]),
      ]);

      expect(conflicts.map((c) => c.allergy), [Allergy.dairy, Allergy.gluten]);
      expect(conflicts.first.members, ['Diego', 'María']);
      expect(conflicts.first.ingredients, ['Queso panela']);
      expect(conflicts.last.members, ['Diego']);
      expect(conflicts.last.ingredients, ['Pan de caja']);
      expect(conflicts.map(allergyWarning), [
        'Atención: esta receta contiene lácteos (Queso panela), y Diego y '
            'María tienen alergia.',
        'Atención: esta receta contiene gluten (Pan de caja), y Diego tiene '
            'alergia.',
      ]);
    });

    test('lists every ingredient with the allergen', () {
      final conflicts = allergyConflicts(
        recipe(const [
          RecipeIngredient('Leche', 1, FoodUnit.l),
          RecipeIngredient('Arroz', 0.2, FoodUnit.kg),
          RecipeIngredient('Crema', 0.1, FoodUnit.l),
          RecipeIngredient('Mantequilla', 0.05, FoodUnit.kg),
        ]),
        [
          member('Isabel', allergies: const [Allergy.dairy]),
        ],
      );

      expect(conflicts.single.ingredients, ['Leche', 'Crema', 'Mantequilla']);
      expect(
        allergyWarning(conflicts.single),
        'Atención: esta receta contiene lácteos (Leche, Crema y '
        'Mantequilla), y Isabel tiene alergia.',
      );
    });

    test('is empty when nobody is allergic to what the recipe has', () {
      final family = [
        member('María', allergies: const [Allergy.dairy]),
        member('Diego'),
      ];

      expect(allergyConflicts(SampleData.frijolesDeLaOlla, family), isEmpty);
      expect(allergyConflicts(SampleData.avenaConFruta, const []), isEmpty);
    });
  });

  group('joinWithAnd', () {
    test('joins with commas and "y"', () {
      expect(joinWithAnd(const []), '');
      expect(joinWithAnd(const ['María']), 'María');
      expect(joinWithAnd(const ['María', 'Diego']), 'María y Diego');
      expect(
        joinWithAnd(const ['Ana', 'María', 'Diego']),
        'Ana, María y Diego',
      );
    });

    test('uses "e" before an "i" sound', () {
      expect(joinWithAnd(const ['María', 'Isabel']), 'María e Isabel');
      expect(joinWithAnd(const ['Ana', 'Hilda']), 'Ana e Hilda');
      expect(joinWithAnd(const ['Ana', 'Íñigo']), 'Ana e Íñigo');
      expect(joinWithAnd(const ['Ana', 'Hielo']), 'Ana y Hielo');
    });
  });

  group('buildWeeklyPlan', () {
    test('puts first the recipes that use what expires sooner', () {
      final plan = buildWeeklyPlan(SampleData.recipes, [
        item('Leche entera', 1, FoodUnit.l, days: 1),
        item('Jamón de pavo', 0.5, FoodUnit.kg, days: 3),
        item('Jitomate', 1, FoodUnit.kg, days: 5),
        item('Arroz', 2, FoodUnit.kg, days: 200),
        item('Frijol', 1, FoodUnit.kg, days: 90),
      ], today: today);

      expect(plan.map((e) => e.day), [
        'Lun',
        'Mar',
        'Mié',
        'Jue',
        'Vie',
        'Sáb',
        'Dom',
      ]);
      expect(plan.map((e) => e.recipe.name), [
        'Avena con fruta',
        'Sándwich de jamón y queso',
        // Mismo jitomate (5 días): primero la que tiene menos faltantes.
        'Arroz con atún',
        'Sopa de lentejas',
        'Sopa de pasta con verduras',
        'Frijoles de la olla',
        'Avena con fruta',
      ]);
      expect(plan.map((e) => e.reason), [
        'Usa Leche entera (caduca mañana)\nTe faltan 2 ingredientes',
        'Usa Jamón de pavo (caduca en 3 días)\nTe faltan 2 ingredientes',
        'Usa Jitomate (caduca en 5 días)\nTe faltan 2 ingredientes',
        'Usa Jitomate (caduca en 5 días)\nTe faltan 3 ingredientes',
        'Usa Jitomate (caduca en 5 días)\nTe faltan 3 ingredientes',
        'Con productos de tu despensa',
        'Usa Leche entera (caduca mañana)\nTe faltan 2 ingredientes',
      ]);
      expect(plan.map((e) => e.urgency), [
        ExpirationUrgency.urgent,
        ExpirationUrgency.urgent,
        ExpirationUrgency.soon,
        ExpirationUrgency.soon,
        ExpirationUrgency.soon,
        ExpirationUrgency.fresh,
        ExpirationUrgency.urgent,
      ]);
    });

    test('says "caduca hoy" and uses the most urgent matching item', () {
      final plan = buildWeeklyPlan(
        [SampleData.avenaConFruta],
        [
          item('Avena', 1, FoodUnit.kg, days: 60),
          item('Leche entera', 1, FoodUnit.l, days: 4),
          item('Plátanos', 6, FoodUnit.piece, days: 0),
        ],
        today: today,
      );

      expect(plan.first.reason, 'Usa Plátanos (caduca hoy)');
      expect(plan.first.urgency, ExpirationUrgency.urgent);
    });

    test('ignores expired items', () {
      final plan = buildWeeklyPlan(
        [SampleData.avenaConFruta, SampleData.frijolesDeLaOlla],
        [
          item(
            'Leche entera',
            1,
            FoodUnit.l,
            days: 1,
            registered: DateTime(2026, 9, 18),
          ),
          item('Frijol', 1, FoodUnit.kg, days: 10),
        ],
        today: today,
      );

      expect(plan.first.recipe.name, 'Frijoles de la olla');
      expect(plan.first.reason, 'Con productos de tu despensa');
      expect(plan.first.urgency, ExpirationUrgency.fresh);
      expect(plan[1].recipe.name, 'Avena con fruta');
      expect(plan[1].reason, 'Te faltan 3 ingredientes');
      expect(plan[1].urgency, ExpirationUrgency.fresh);
    });

    test('with an empty pantry still lists 7 days with what is missing', () {
      final plan = buildWeeklyPlan(SampleData.recipes, const [], today: today);

      expect(plan, hasLength(7));
      expect(plan.map((e) => e.recipe.name), [
        'Frijoles de la olla',
        'Avena con fruta',
        'Sopa de lentejas',
        'Arroz con atún',
        'Sándwich de jamón y queso',
        'Sopa de pasta con verduras',
        'Frijoles de la olla',
      ]);
      expect(plan.map((e) => e.reason), [
        'Te falta 1 ingrediente',
        'Te faltan 3 ingredientes',
        'Te faltan 4 ingredientes',
        'Te faltan 4 ingredientes',
        'Te faltan 4 ingredientes',
        'Te faltan 4 ingredientes',
        'Te falta 1 ingrediente',
      ]);
      expect(plan.every((e) => e.urgency == ExpirationUrgency.fresh), isTrue);
    });

    test('cycles the recipes to fill the week, starting today', () {
      final a = recipe(const [
        RecipeIngredient('Arroz', 0.2, FoodUnit.kg),
      ], name: 'A');
      final b = recipe(const [
        RecipeIngredient('Frijol', 0.2, FoodUnit.kg),
      ], name: 'B');

      final thursday = DateTime(2026, 9, 24);
      final plan = buildWeeklyPlan(
        [a, b],
        [item('Frijol', 1, FoodUnit.kg, days: 2, registered: thursday)],
        today: thursday,
      );

      expect(plan.map((e) => e.recipe), [
        same(b),
        same(a),
        same(b),
        same(a),
        same(b),
        same(a),
        same(b),
      ]);
      expect(plan.map((e) => e.day), [
        'Jue',
        'Vie',
        'Sáb',
        'Dom',
        'Lun',
        'Mar',
        'Mié',
      ]);
      expect(buildWeeklyPlan(const [], const [], today: today), isEmpty);
    });

    test('uses the portions of the recipes it receives', () {
      final pantry = [
        item('Avena', 1, FoodUnit.kg),
        item('Leche entera', 0.8, FoodUnit.l),
        item('Plátano', 8, FoodUnit.piece),
      ];

      expect(
        buildWeeklyPlan(
          [SampleData.avenaConFruta],
          pantry,
          today: today,
        ).first.reason,
        'Con productos de tu despensa',
      );
      expect(
        buildWeeklyPlan(
          [scaledRecipe(SampleData.avenaConFruta, 4)],
          pantry,
          today: today,
        ).first.reason,
        'Te falta 1 ingrediente',
      );
    });
  });
}
