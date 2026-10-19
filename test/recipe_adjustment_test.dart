import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/domain/models/child_profile.dart';
import 'package:bank_storage_app/domain/models/family_profile.dart';
import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:bank_storage_app/domain/recipe_adjustment.dart';
import 'package:bank_storage_app/domain/recipe_planner.dart';
import 'package:flutter_test/flutter_test.dart';

Recipe recipe(
  List<(String, double)> ingredients, {
  int servings = 4,
  String id = 'r1',
}) => Recipe(
  id: id,
  name: 'Arroz con leche',
  ingredients: [
    for (final (name, quantity) in ingredients)
      RecipeIngredient(productName: name, quantity: quantity, unit: 'kg'),
  ],
  steps: const ['Cocer'],
  prepTimeMinutes: 30,
  caloriesPerServing: 200,
  status: RecipeStatus.approved,
  servings: servings,
);

FamilyProfile family({
  int adults = 4,
  List<ChildProfile> children = const [],
  List<String> restrictions = const [],
}) => FamilyProfile(
  id: 'famA',
  authUid: 'famA',
  adults: adults,
  children: children,
  dietaryRestrictions: restrictions,
);

/// El algoritmo con el hogar como lo recibe: sin nombres, edades ni pesos.
RecipeAdjustmentSuggestion? suggest(Recipe recipe, FamilyProfile family) =>
    RecipeAdjustmentRules.suggest(
      recipe,
      AdjustmentContext.forHousehold(family),
    );

void main() {
  final base = recipe([('Arroz', 0.4), ('Leche entera', 1)]);

  group('nothing to change', () {
    test(
      'the household of the recipe without allergies gets no suggestion',
      () {
        expect(suggest(base, family()), isNull);
      },
    );

    test('a household with no members gets no suggestion', () {
      expect(suggest(base, family(adults: 0)), isNull);
    });
  });

  group('portions', () {
    test('the servings follow the household and the ingredients scale', () {
      final suggestion = suggest(base, family(adults: 2))!;

      expect(suggestion.servings, 2);
      expect(suggestion.householdSize, 2);
      expect(suggestion.householdKey, '2');
      expect(suggestion.ingredients.map((i) => i.quantity), [0.2, 0.5]);
      expect(suggestion.changes, hasLength(1));
      expect(suggestion.changes.single.kind, AdjustmentChange.kindPortions);
    });

    test('children count as part of the household and of the portions', () {
      final suggestion = suggest(
        base,
        family(
          adults: 2,
          children: const [
            ChildProfile(age: 9, weight: 28),
            ChildProfile(age: 5, weight: 19),
          ],
        ),
      )!;

      expect(suggestion.householdSize, 4);
      // 2 adultos y 2 niños: menos de 4 porciones de adulto.
      expect(suggestion.servings, lessThan(4));
    });
  });

  group('allergens', () {
    test('milk is replaced by an oat drink for a dairy allergy', () {
      final suggestion = suggest(base, family(restrictions: const ['dairy']))!;

      expect(suggestion.ingredients.map((i) => i.productName), [
        'Arroz',
        'Bebida de avena',
      ]);
      final change = suggestion.changes.single;
      expect(change.kind, AdjustmentChange.kindSubstitution);
      expect(change.from, 'Leche entera');
      expect(change.to, 'Bebida de avena');
      expect(change.reason, 'alergia a lácteos');
      expect(suggestion.servings, 4);
    });

    test('the summary says what changed and why in one line', () {
      final suggestion = suggest(
        base,
        family(adults: 2, restrictions: const ['dairy']),
      )!;

      expect(
        suggestion.summary,
        'Porciones ajustadas a 2 para tu hogar de 2 integrantes; se sustituye '
        'leche entera por bebida de avena por alergia a lácteos',
      );
      expect(suggestion.summary.contains('\n'), isFalse);
    });

    test('the substitute never carries another allergen of the household', () {
      // Bebida de avena sirve con lácteos; con gluten también (la avena lleva
      // gluten en la lista), así que se toma la siguiente: de arroz.
      final suggestion = suggest(
        base,
        family(restrictions: const ['dairy', 'gluten']),
      )!;

      expect(suggestion.ingredients.last.productName, 'Bebida de arroz');
    });

    test('every allergen the recipe has is replaced', () {
      final suggestion = suggest(
        recipe([('Pasta', 0.3), ('Queso', 0.1), ('Huevos', 0.1)]),
        family(restrictions: const ['gluten', 'dairy', 'egg']),
      )!;

      expect(suggestion.ingredients.map((i) => i.productName), [
        'Arroz',
        'Tofu',
        'Tofu',
      ]);
      expect(suggestion.changes.map((c) => c.reason), [
        'alergia a gluten',
        'alergia a lácteos',
        'alergia a huevo',
      ]);
    });

    test('a household without that allergy keeps the ingredient', () {
      expect(suggest(base, family(restrictions: const ['peanut'])), isNull);
    });

    test('a chronic condition alone does not change the recipe', () {
      expect(
        suggest(
          recipe([('Azúcar', 0.1)]),
          family(restrictions: const ['diabetes']),
        ),
        isNull,
      );
    });

    test('no suggestion keeps an allergen in its ingredients', () {
      for (final allergy in [
        'dairy',
        'gluten',
        'peanut',
        'shellfish',
        'egg',
        'soy',
      ]) {
        final names = {
          'dairy': 'Leche',
          'gluten': 'Harina',
          'peanut': 'Cacahuate',
          'shellfish': 'Camarones',
          'egg': 'Huevo',
          'soy': 'Tofu',
        };
        final suggestion = suggest(
          recipe([(names[allergy]!, 0.1)]),
          family(restrictions: [allergy]),
        )!;
        final remaining = suggest(
          recipe([
            for (final ingredient in suggestion.ingredients)
              (ingredient.productName, 0.1),
          ]),
          family(restrictions: [allergy]),
        );
        expect(remaining, isNull, reason: allergy);
      }
    });
  });

  group('householdKey', () {
    test('is the size and the allergies in order, without repeats', () {
      expect(householdKeyOf(4, const []), '4');
      expect(householdKeyOf(4, [Allergy.soy, Allergy.dairy]), '4-dairy-soy');
      expect(
        householdKeyOf(2, [Allergy.egg, Allergy.egg, Allergy.dairy]),
        '2-dairy-egg',
      );
    });

    test('changes when only the allergies change', () {
      final one = AdjustmentContext.forHousehold(
        family(restrictions: const ['dairy']),
      );
      final two = AdjustmentContext.forHousehold(
        family(restrictions: const ['dairy', 'gluten']),
      );

      expect(one.householdSize, two.householdSize);
      expect(one.householdKey, '4-dairy');
      expect(two.householdKey, '4-dairy-gluten');
    });

    test(
      'does not depend on the order of the restrictions or on conditions',
      () {
        final a = AdjustmentContext.forHousehold(
          family(restrictions: const ['gluten', 'diabetes', 'dairy']),
        );
        final b = AdjustmentContext.forHousehold(
          family(restrictions: const ['dairy', 'gluten']),
        );
        expect(a.householdKey, b.householdKey);
      },
    );

    test('the suggestion carries the key of its household', () {
      final suggestion = suggest(base, family(restrictions: const ['dairy']))!;
      expect(suggestion.householdKey, '4-dairy');
    });
  });

  group('recipeSignature', () {
    test('is the same for the same recipe and changes when it is edited', () {
      expect(
        recipeSignature(base),
        recipeSignature(recipe([('Arroz', 0.4), ('Leche entera', 1)])),
      );
      expect(
        recipeSignature(base),
        isNot(recipeSignature(recipe([('Arroz', 0.5), ('Leche entera', 1)]))),
      );
      expect(
        recipeSignature(base),
        isNot(recipeSignature(recipe([('Arroz', 0.4)]))),
      );
    });

    test('is 8 hex characters', () {
      expect(recipeSignature(base), matches(RegExp(r'^[0-9a-f]{8}$')));
    });
  });

  group('RecipePlanner', () {
    test('suggestAdjustment goes through the interface', () async {
      const RecipePlanner planner = RuleBasedRecipePlanner();
      final suggestion = await planner.suggestAdjustment(
        household: AdjustmentContext.forHousehold(
          family(restrictions: const ['dairy']),
        ),
        recipe: base,
      );

      expect(suggestion, isNotNull);
      expect(suggestion!.recipeId, 'r1');
      expect(suggestion.baseSignature, recipeSignature(base));
    });
  });
}
