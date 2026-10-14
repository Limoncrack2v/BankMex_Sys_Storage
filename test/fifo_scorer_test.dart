import 'package:bank_storage_app/domain/fifo_scorer.dart';
import 'package:bank_storage_app/domain/models/family_profile.dart';
import 'package:bank_storage_app/domain/models/pantry_item.dart';
import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:bank_storage_app/domain/recipe_on_demand.dart';
import 'package:flutter_test/flutter_test.dart';

PantryItem pantry({
  required String name,
  required DateTime expiration,
  double quantity = 1000,
  String unit = 'g',
}) {
  return PantryItem(
    id: name,
    familyId: 'fam',
    productId: name,
    name: name,
    quantity: quantity,
    unit: unit,
    expirationDate: expiration,
    category: 'test',
    originalQuantity: quantity,
    consumedQuantity: 0,
    status: PantryItemStatus.available,
  );
}

RecipeIngredient ingredient(String name, {String unit = 'g'}) =>
    RecipeIngredient(productName: name, quantity: 100, unit: unit);

Recipe recipe(String id, List<RecipeIngredient> ingredients) {
  return Recipe(
    id: id,
    name: id,
    ingredients: ingredients,
    steps: const ['x'],
    prepTimeMinutes: 1,
    caloriesPerServing: 1,
    status: RecipeStatus.approved,
  );
}

void main() {
  final now = DateTime(2026, 9, 20, 8);
  final today = DateTime(2026, 9, 20, 23);
  final inMonths = DateTime(2026, 12, 20);

  // La leche caduca hoy; el arroz, los frijoles y la avena, en meses.
  final milkPantry = [
    pantry(name: 'leche', unit: 'ml', expiration: today),
    pantry(name: 'arroz', expiration: inMonths),
    pantry(name: 'frijol', expiration: inMonths),
    pantry(name: 'avena', expiration: inMonths),
  ];
  final threeItems = recipe('three_items', [
    ingredient('arroz'),
    ingredient('frijol'),
    ingredient('avena'),
  ]);
  final milk = recipe('milk', [ingredient('leche', unit: 'ml')]);

  String pick(List<Recipe> recipes, List<PantryItem> items) =>
      FifoScorer.pickBest(recipes: recipes, pantryItems: items, now: now).id;

  group('FifoScorer.pickBest', () {
    test('prefers the item that expires today over three that expire in '
        'months', () {
      expect(pick([threeItems, milk], milkPantry), 'milk');
      expect(pick([milk, threeItems], milkPantry), 'milk');
    });

    test('using more pantry items does not beat an earlier expiration', () {
      final items = [
        pantry(name: 'leche', unit: 'ml', expiration: DateTime(2026, 9, 25)),
        pantry(name: 'arroz', expiration: DateTime(2026, 9, 26)),
        pantry(name: 'frijol', expiration: DateTime(2026, 9, 26)),
        pantry(name: 'avena', expiration: DateTime(2026, 9, 26)),
      ];
      expect(pick([threeItems, milk], items), 'milk');
    });

    test('breaks a tie on the expiration day by fewest missing '
        'ingredients', () {
      final items = [
        pantry(name: 'leche', unit: 'ml', expiration: today),
        // Mismo día que la leche, a otra hora: sigue siendo empate.
        pantry(name: 'arroz', expiration: DateTime(2026, 9, 20, 12)),
      ];
      final missingTwo = recipe('missing_two', [
        ingredient('leche', unit: 'ml'),
        ingredient('canela'),
        ingredient('azucar'),
      ]);
      final missingOne = recipe('missing_one', [
        ingredient('arroz'),
        ingredient('canela'),
      ]);
      expect(pick([missingTwo, missingOne], items), 'missing_one');
      expect(pick([missingOne, missingTwo], items), 'missing_one');
    });

    test('keeps the first recipe when both criteria tie', () {
      final other = recipe('other_milk', [ingredient('leche', unit: 'ml')]);
      expect(pick([milk, other], milkPantry), 'milk');
      expect(pick([other, milk], milkPantry), 'other_milk');
    });

    test('ignores expired, consumed and empty items', () {
      final items = [
        pantry(name: 'leche', unit: 'ml', expiration: DateTime(2026, 9, 19)),
        pantry(
          name: 'yogur',
          expiration: today,
        ).copyWith(status: PantryItemStatus.consumed),
        pantry(name: 'queso', expiration: today, quantity: 0),
        pantry(name: 'arroz', expiration: inMonths),
      ];
      final unusable = recipe('unusable', [
        ingredient('leche', unit: 'ml'),
        ingredient('yogur'),
        ingredient('queso'),
      ]);
      final rice = recipe('rice', [ingredient('arroz')]);
      expect(pick([unusable, rice], items), 'rice');
    });

    test('puts last the recipes that use nothing from the pantry', () {
      final nothing = recipe('nothing', [ingredient('canela')]);
      final rice = recipe('rice', [ingredient('arroz')]);
      expect(pick([nothing, rice], milkPantry), 'rice');
    });
  });

  test('the on-demand recipe uses the milk that expires today', () {
    const family = FamilyProfile(
      id: 'fam',
      authUid: 'fake',
      adults: 2,
      children: [],
      dietaryRestrictions: [],
    );
    final picked = RecipeOnDemand.getSingleRecipeOnDemand(
      family: family,
      pantryItems: milkPantry,
      recipes: [threeItems, milk],
      now: now,
    );
    expect(picked?.id, 'milk');
  });
}
