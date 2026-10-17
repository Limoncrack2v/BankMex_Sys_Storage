import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/ui/formatting.dart';
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

Member member(
  String name, {
  List<Allergy>? allergies,
  List<ChronicCondition>? conditions,
}) => Member(
  memberId: 'member-${_nextId++}',
  name: name,
  memberType: MemberType.adult,
  createdAt: DateTime(2026, 9, 1),
  allergies: allergies,
  chronicConditions: conditions,
);

Member child(String name, {int? age, double? weightKg}) => Member(
  memberId: 'member-${_nextId++}',
  name: name,
  memberType: MemberType.child,
  createdAt: DateTime(2026, 9, 1),
  age: age,
  weightKg: weightKg,
);

List<double> quantities(Recipe recipe) =>
    recipe.ingredients.map((i) => i.quantity).toList();

void main() {
  group('householdPortions', () {
    test('adults without obesity count 1 regardless of age or weight', () {
      expect(householdPortions([member('Ana'), member('Luis')]), 2);
      expect(householdPortions(const []), 0);
    });

    test('an adult with obesity counts their share of the kcal deficit', () {
      // 2200 de 2700 kcal (sin edad ni peso).
      expect(
        householdPortions([
          member('Ana'),
          member('Luis', conditions: const [ChronicCondition.obesity]),
        ]),
        closeTo(1 + 2200 / 2700, 1e-9),
      );
    });

    test('children count by age, and weight when known', () {
      expect(householdPortions([child('Sofía', age: 5)]), closeTo(0.6, 1e-9));
      // 0.6 * 0.7 + (20 / 70) * 0.3
      expect(
        householdPortions([child('Sofía', age: 5, weightKg: 20)]),
        closeTo(0.42 + 20 / 70 * 0.3, 1e-9),
      );
      expect(householdPortions([child('Beto', age: 1)]), closeTo(0.25, 1e-9));
      expect(householdPortions([child('Leo', age: 15)]), closeTo(1, 1e-9));
    });

    test('weight alone is a share of an adult weight, bounded', () {
      expect(householdPortions([child('Sofía', weightKg: 35)]), 0.5);
      expect(householdPortions([child('Bebé', weightKg: 3)]), 0.2);
      expect(householdPortions([child('Leo', weightKg: 90)]), 1);
    });

    test('a child without age or weight is not cut down', () {
      expect(householdPortions([child('Sofía')]), 1);
    });

    test('scaledForHousehold uses portions and headcount', () {
      final scaled = scaledForHousehold(SampleData.sopaDeLentejas, [
        member('Ana'),
        member('Luis'),
        child('Sofía', weightKg: 35),
      ]);

      expect(scaled.servings, 3);
      expect(scaled.ingredients.first.quantity, 0.156);
    });
  });

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

    test('scales quantities by portions but shows the headcount', () {
      final scaled = scaledRecipe(SampleData.sopaDeLentejas, 3, portions: 2.5);

      expect(scaled.servings, 3);
      expect(scaled.ingredients.first.quantity, 0.156);
      // Mismo número de integrantes, pero comen menos que 4 adultos.
      final base = SampleData.sopaDeLentejas;
      expect(scaledRecipe(base, base.servings, portions: 3), isNot(same(base)));
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

  group('conditionConflicts', () {
    test('finds the ingredients to avoid and who has the condition', () {
      final conflicts = conditionConflicts(SampleData.sandwichDeJamonYQueso, [
        member('José', conditions: const [ChronicCondition.hypertension]),
        member('María', conditions: const []),
        member('Ana'),
      ]);

      expect(conflicts, hasLength(1));
      expect(conflicts.single.condition, ChronicCondition.hypertension);
      expect(conflicts.single.members, ['José']);
      expect(conflicts.single.ingredients, ['Jamón de pavo']);
      expect(
        conditionWarning(conflicts.single),
        'Cuidado: esta receta lleva Jamón de pavo, que conviene evitar con '
        'hipertensión (José).',
      );
    });

    test('compares whole words', () {
      expect(
        containsRestricted('Sal de mesa', ChronicCondition.hypertension),
        isTrue,
      );
      expect(
        containsRestricted('Salsa verde', ChronicCondition.hypertension),
        isFalse,
      );
      expect(
        containsRestricted('Azúcar morena', ChronicCondition.diabetes),
        isTrue,
      );
      expect(
        containsRestricted('Refrescos', ChronicCondition.kidneyDisease),
        isTrue,
      );
      expect(
        containsRestricted('Crema ácida', ChronicCondition.highCholesterol),
        isTrue,
      );
    });

    test('no conflicts when nobody has a condition', () {
      expect(
        conditionConflicts(SampleData.sandwichDeJamonYQueso, [member('Ana')]),
        isEmpty,
      );
    });
  });

  group('exclusionKeywords', () {
    test('joins allergies and conditions without repeats', () {
      final keywords = exclusionKeywords([
        member('María', allergies: const [Allergy.egg]),
        member(
          'José',
          conditions: const [
            ChronicCondition.diabetes,
            ChronicCondition.obesity,
          ],
        ),
      ]);

      expect(keywords, containsAll(['huevo', 'azucar', 'manteca']));
      expect(keywords.where((k) => k == 'azucar'), hasLength(1));
      expect(keywords, orderedEquals([...keywords]..sort()));
    });

    test('empty when nobody registered allergies or conditions', () {
      expect(exclusionKeywords([member('Ana')]), isEmpty);
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
      expect(containsAllergen('Pancita de res', Allergy.gluten), isFalse);
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

  group('buildMealPlan', () {
    test('puts first the recipes that use what expires sooner', () {
      final plan = buildMealPlan(SampleData.recipes, [
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
        // Ronda nueva: la leche y el jitomate ya caducaron, ya nada urgente.
        'Arroz con atún',
      ]);
      // La tarjeta de hoy cuenta desde hoy; las demás dicen la fecha, así que
      // el mismo jitomate dice lo mismo en cada tarjeta.
      expect(plan.map((e) => e.reason), [
        'Usa Leche entera (caduca mañana)\nTe faltan 2 ingredientes',
        'Usa Jamón de pavo (caduca el jue 24)\nTe faltan 2 ingredientes',
        'Usa Jitomate (caduca el sáb 26)\nTe faltan 2 ingredientes',
        'Usa Jitomate (caduca el sáb 26)\nTe faltan 3 ingredientes',
        'Usa Jitomate (caduca el sáb 26)\nTe faltan 4 ingredientes',
        'Con productos de tu despensa',
        'Te faltan 3 ingredientes',
      ]);
      expect(plan.map((e) => e.urgency), [
        ExpirationUrgency.urgent,
        ExpirationUrgency.urgent,
        ExpirationUrgency.urgent,
        ExpirationUrgency.urgent,
        ExpirationUrgency.urgent,
        ExpirationUrgency.fresh,
        ExpirationUrgency.fresh,
      ]);
    });

    test('says "caduca hoy" and uses the most urgent matching item', () {
      final plan = buildMealPlan(
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
      final plan = buildMealPlan(
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
      final plan = buildMealPlan(SampleData.recipes, const [], today: today);

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
      final plan = buildMealPlan(
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
      expect(buildMealPlan(const [], const [], today: today), isEmpty);
    });

    test('a 14 day plan covers two weeks of consecutive dates', () {
      final a = recipe(const [
        RecipeIngredient('Arroz', 0.2, FoodUnit.kg),
      ], name: 'A');
      final b = recipe(const [
        RecipeIngredient('Frijol', 0.2, FoodUnit.kg),
      ], name: 'B');
      final c = recipe(const [
        RecipeIngredient('Avena', 0.2, FoodUnit.kg),
      ], name: 'C');

      // Empieza a media tarde de un jueves y cruza de septiembre a octubre.
      final thursday = DateTime(2026, 9, 24, 17, 30);
      final plan = buildMealPlan(
        [a, b, c],
        const [],
        today: thursday,
        days: 14,
      );

      expect(plan.map((e) => e.date), [
        for (var day = 24; day <= 30; day++) DateTime(2026, 9, day),
        for (var day = 1; day <= 7; day++) DateTime(2026, 10, day),
      ]);
      expect(plan.map((e) => e.day), [
        'Jue', 'Vie', 'Sáb', 'Dom', 'Lun', 'Mar', 'Mié', //
        'Jue', 'Vie', 'Sáb', 'Dom', 'Lun', 'Mar', 'Mié',
      ]);
      // Con 3 recetas se repiten en el mismo orden hasta llenar los 14 días.
      expect(plan.map((e) => e.recipe.name).join(), 'ABCABCABCABCAB');
    });

    test('is 7 days long unless told otherwise', () {
      final plan = buildMealPlan(SampleData.recipes, const [], today: today);

      expect(plan, hasLength(7));
      expect(plan.first.date, today);
      expect(plan.last.date, DateTime(2026, 9, 27));
    });

    test('uses the portions of the recipes it receives', () {
      final pantry = [
        item('Avena', 1, FoodUnit.kg),
        item('Leche entera', 0.8, FoodUnit.l),
        item('Plátano', 8, FoodUnit.piece),
      ];

      expect(
        buildMealPlan(
          [SampleData.avenaConFruta],
          pantry,
          today: today,
        ).first.reason,
        'Con productos de tu despensa',
      );
      expect(
        buildMealPlan(
          [scaledRecipe(SampleData.avenaConFruta, 4)],
          pantry,
          today: today,
        ).first.reason,
        'Te falta 1 ingrediente',
      );
    });
  });

  group('buildMealPlan día por día', () {
    final conLeche = recipe(const [
      RecipeIngredient('Leche entera', 0.2, FoodUnit.l),
    ], name: 'Con leche');
    final conArroz = recipe(const [
      RecipeIngredient('Arroz', 0.2, FoodUnit.kg),
    ], name: 'Con arroz');
    final conFrijol = recipe(const [
      RecipeIngredient('Frijol', 0.2, FoodUnit.kg),
    ], name: 'Con frijol');
    final conJitomate = recipe(const [
      RecipeIngredient('Jitomate', 0.2, FoodUnit.kg),
    ], name: 'Con jitomate');

    test('un producto que caduca el día 1 no sale en el motivo de ninguna '
        'tarjeta posterior (14 días y 3 recetas)', () {
      final plan = buildMealPlan(
        [conLeche, conArroz, conFrijol],
        [
          item('Leche entera', 5, FoodUnit.l, days: 1),
          item('Arroz', 5, FoodUnit.kg, days: 200),
          item('Frijol', 5, FoodUnit.kg, days: 90),
        ],
        today: today,
        days: 14,
      );

      expect(plan, hasLength(14));
      expect(plan.first.recipe, same(conLeche));
      expect(plan.first.reason, 'Usa Leche entera (caduca mañana)');
      expect(plan.first.urgency, ExpirationUrgency.urgent);
      // La receta con leche sale varias veces, pero solo la primera puede
      // nombrar la leche: el resto de los días ya caducó.
      final laterMilk = plan.skip(1).where((e) => e.recipe == conLeche);
      expect(laterMilk.length, greaterThanOrEqualTo(3));
      for (final entry in laterMilk) {
        expect(entry.reason, 'Te falta 1 ingrediente', reason: '${entry.date}');
        expect(entry.urgency, ExpirationUrgency.fresh);
      }
      for (final entry in plan.skip(1)) {
        expect(entry.reason, isNot(contains('Leche')), reason: '${entry.date}');
      }
    });

    test('"caduca en N días" solo en la tarjeta de hoy; las demás dicen la '
        'fecha. Urgente / Pronto, desde la fecha de la tarjeta', () {
      final plan = buildMealPlan(
        [conJitomate, conArroz],
        [
          item('Jitomate', 10, FoodUnit.kg, days: 5),
          item('Arroz', 10, FoodUnit.kg, days: 100),
        ],
        today: today,
      );

      expect(plan.map((e) => e.recipe.name), [
        'Con jitomate',
        'Con arroz',
        'Con jitomate',
        'Con arroz',
        'Con jitomate',
        'Con arroz',
        'Con jitomate',
      ]);
      expect(plan.map((e) => e.reason), [
        'Usa Jitomate (caduca en 5 días)',
        'Con productos de tu despensa',
        'Usa Jitomate (caduca el sáb 26)',
        'Con productos de tu despensa',
        'Usa Jitomate (caduca el sáb 26)',
        'Con productos de tu despensa',
        // El jitomate caducó el sábado: el domingo ya no se nombra.
        'Te falta 1 ingrediente',
      ]);
      expect(plan.map((e) => e.urgency), [
        ExpirationUrgency.soon,
        ExpirationUrgency.fresh,
        ExpirationUrgency.urgent,
        ExpirationUrgency.fresh,
        ExpirationUrgency.urgent,
        ExpirationUrgency.fresh,
        ExpirationUrgency.fresh,
      ]);
    });

    test('un producto dice "caduca ese día" solo en su último día', () {
      final plan = buildMealPlan(
        [conJitomate, conArroz],
        [
          item('Jitomate', 10, FoodUnit.kg, days: 4),
          item('Arroz', 10, FoodUnit.kg, days: 100),
        ],
        today: today,
      );

      expect(plan[0].reason, 'Usa Jitomate (caduca en 4 días)');
      expect(plan[2].reason, 'Usa Jitomate (caduca el vie 25)');
      expect(plan[4].reason, 'Usa Jitomate (caduca ese día)');
      expect(plan[4].urgency, ExpirationUrgency.urgent);
      expect(plan[6].reason, 'Te falta 1 ingrediente');
    });

    test('con 14 días ninguna tarjeta nombra un producto caducado ni se '
        'equivoca en los días que le quedan', () {
      final octubre13 = DateTime(2026, 10, 13);
      final pantry = [
        item('Leche entera', 1, FoodUnit.l, days: 1, registered: octubre13),
        item('Jamón de pavo', 2, FoodUnit.kg, days: 3, registered: octubre13),
        item('Jitomate', 3, FoodUnit.kg, days: 5, registered: octubre13),
        item('Plátano', 20, FoodUnit.piece, days: 6, registered: octubre13),
        item('Arroz', 5, FoodUnit.kg, days: 200, registered: octubre13),
        item('Frijol', 5, FoodUnit.kg, days: 90, registered: octubre13),
        item('Avena', 2, FoodUnit.kg, days: 60, registered: octubre13),
      ];

      final plan = buildMealPlan(
        SampleData.recipes,
        pantry,
        today: octubre13,
        days: 14,
      );

      expect(plan, hasLength(14));
      final named = RegExp(r'^Usa (.+) \((.+)\)$', multiLine: true);
      var cardsWithProduct = 0;
      for (final entry in plan) {
        for (final match in named.allMatches(entry.reason)) {
          cardsWithProduct++;
          final left = pantry
              .where((p) => productDisplayName(p.productId) == match.group(1))
              .map((p) => p.daysLeftOn(entry.date))
              .toList();
          // Es un producto de la despensa que sigue vigente en esa fecha y la
          // frase coincide con los días que le quedan en esa fecha.
          expect(left, isNotEmpty);
          expect(
            left
                .where((days) => days >= 0)
                .map((days) => _expiresPhrase(days, entry.date, octubre13)),
            contains(match.group(2)),
            reason: '${entry.date}: ${entry.reason}',
          );
        }
      }
      expect(cardsWithProduct, greaterThanOrEqualTo(5));
      // La leche caduca el 14: el 19 y el 25 ya no pueden nombrarla.
      final byDay = {for (final e in plan) e.date.day: e};
      expect(byDay[19]!.reason, isNot(contains('Leche')));
      expect(byDay[25]!.reason, isNot(contains('Leche')));
    });

    test('lo que los días anteriores ya usaron no se promete otra vez', () {
      final lecheAgotada = buildMealPlan(
        [
          recipe(const [RecipeIngredient('Leche entera', 1, FoodUnit.l)]),
          conArroz,
        ],
        [
          item('Leche entera', 1, FoodUnit.l, days: 6),
          item('Arroz', 10, FoodUnit.kg, days: 100),
        ],
        today: today,
        days: 4,
      );
      final conSobrante = buildMealPlan(
        [
          recipe(const [RecipeIngredient('Leche entera', 1, FoodUnit.l)]),
          conArroz,
        ],
        [
          item('Leche entera', 2, FoodUnit.l, days: 6),
          item('Arroz', 10, FoodUnit.kg, days: 100),
        ],
        today: today,
        days: 4,
      );

      expect(lecheAgotada[0].reason, 'Usa Leche entera (caduca en 6 días)');
      // El lunes se bebió el litro entero: el miércoles no queda leche.
      expect(lecheAgotada[2].reason, 'Te falta 1 ingrediente');
      expect(lecheAgotada[2].urgency, ExpirationUrgency.fresh);
      // Con 2 litros sí queda, y sigue caducando el domingo.
      expect(conSobrante[2].reason, 'Usa Leche entera (caduca el dom 27)');
    });

    test('un día sin nada usable elige la receta con menos faltantes y no '
        'inventa un producto', () {
      final dosFaltantes = recipe(const [
        RecipeIngredient('Arroz', 0.2, FoodUnit.kg),
        RecipeIngredient('Frijol', 0.2, FoodUnit.kg),
      ], name: 'Dos faltantes');
      final tresFaltantes = recipe(const [
        RecipeIngredient('Arroz', 0.2, FoodUnit.kg),
        RecipeIngredient('Frijol', 0.2, FoodUnit.kg),
        RecipeIngredient('Atún', 1, FoodUnit.can),
      ], name: 'Tres faltantes');

      final plan = buildMealPlan(
        [conLeche, tresFaltantes, dosFaltantes],
        [item('Leche entera', 5, FoodUnit.l, days: 0)],
        today: today,
        days: 4,
      );

      expect(plan.map((e) => e.recipe.name), [
        'Con leche',
        'Dos faltantes',
        'Tres faltantes',
        // Ronda nueva: la leche caducó hoy, así que ya no cuenta.
        'Con leche',
      ]);
      expect(plan.map((e) => e.reason), [
        'Usa Leche entera (caduca hoy)',
        'Te faltan 2 ingredientes',
        'Te faltan 3 ingredientes',
        'Te falta 1 ingrediente',
      ]);
      expect(plan.map((e) => e.urgency), [
        ExpirationUrgency.urgent,
        ExpirationUrgency.fresh,
        ExpirationUrgency.fresh,
        ExpirationUrgency.fresh,
      ]);
    });

    test('no repite la receta del día anterior aunque al empezar otra ronda '
        'sea la mejor', () {
      final plan = buildMealPlan(
        [conLeche, conArroz],
        [
          item('Leche entera', 5, FoodUnit.l, days: 1),
          item('Arroz', 5, FoodUnit.kg, days: 100),
        ],
        today: today,
        days: 4,
      );

      // El miércoles la leche ya caducó y "Con arroz" es la única receta con
      // algo que usar, pero salió el martes: toca "Con leche".
      expect(plan.map((e) => e.recipe.name), [
        'Con leche',
        'Con arroz',
        'Con leche',
        'Con arroz',
      ]);
      expect(plan[2].reason, 'Te falta 1 ingrediente');
    });

    test('con la despensa vacía todos los días dicen solo lo que falta', () {
      final plan = buildMealPlan(
        SampleData.recipes,
        const [],
        today: today,
        days: 14,
      );

      for (final entry in plan) {
        expect(entry.reason, isNot(contains('Usa')));
        expect(entry.urgency, ExpirationUrgency.fresh);
      }
    });

    test('una receta no se repite dos días seguidos y cada ronda las trae '
        'todas', () {
      final pantries = <List<PantryItem>>[
        const [],
        [
          item('Leche entera', 1, FoodUnit.l, days: 1),
          item('Jitomate', 1, FoodUnit.kg, days: 5),
          item('Arroz', 2, FoodUnit.kg, days: 200),
        ],
      ];
      for (final pantry in pantries) {
        final plan = buildMealPlan(
          SampleData.recipes,
          pantry,
          today: today,
          days: 14,
        );
        final names = plan.map((e) => e.recipe.name).toList();

        for (var i = 1; i < names.length; i++) {
          expect(names[i], isNot(names[i - 1]), reason: 'día $i');
        }
        final total = SampleData.recipes.length;
        expect(names.take(total).toSet(), hasLength(total));
        expect(names.skip(total).take(total).toSet(), hasLength(total));
      }
      // Con una sola receta no hay de otra: se repite.
      final unica = buildMealPlan([conArroz], const [], today: today, days: 3);
      expect(unica.map((e) => e.recipe), [
        same(conArroz),
        same(conArroz),
        same(conArroz),
      ]);
    });

    test('cuenta los días de calendario al cruzar de mes, de año y de 29 de '
        'febrero', () {
      for (final (start, expiry) in [
        (DateTime(2026, 9, 28, 23, 30), 'caduca el sáb 3'),
        (DateTime(2026, 12, 29, 8), 'caduca el dom 3'),
        (DateTime(2028, 2, 27, 23, 59), 'caduca el vie 3'),
      ]) {
        final day = DateTime(start.year, start.month, start.day);
        final plan = buildMealPlan(
          [conLeche, conArroz],
          [
            item('Leche entera', 10, FoodUnit.l, days: 5, registered: day),
            item('Arroz', 10, FoodUnit.kg, days: 100, registered: day),
          ],
          today: start,
        );

        expect(plan.map((e) => e.date), [
          for (var offset = 0; offset < 7; offset++)
            DateTime(day.year, day.month, day.day + offset),
        ], reason: '$start');
        // La leche sale los días 0, 2, 4 y 6 y caduca el día 5.
        expect(plan[0].reason, 'Usa Leche entera (caduca en 5 días)');
        expect(plan[2].reason, 'Usa Leche entera ($expiry)', reason: '$start');
        expect(plan[4].reason, 'Usa Leche entera ($expiry)', reason: '$start');
        expect(plan[6].reason, 'Te falta 1 ingrediente', reason: '$start');
      }
    });
  });
}

/// Lo que dice la tarjeta del [date] de lo que le quedan [days] días.
String _expiresPhrase(int days, DateTime date, DateTime today) {
  if (date != today) {
    if (days == 0) return 'caduca ese día';
    final expiry = DateTime(date.year, date.month, date.day + days);
    const weekdays = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
    return 'caduca el ${weekdays[expiry.weekday - 1]} ${expiry.day}';
  }
  return switch (days) {
    0 => 'caduca hoy',
    1 => 'caduca mañana',
    _ => 'caduca en $days días',
  };
}
