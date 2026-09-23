import 'package:bank_storage_app/domain/name_normalizer.dart';
import 'package:bank_storage_app/domain/pantry_recipe_filter.dart';
import 'package:bank_storage_app/domain/unit_converter.dart';
import 'package:bank_storage_app/domain/models/pantry_item.dart';
import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

PantryItem _item({
  required String name,
  required double quantity,
  required String unit,
  DateTime? expiration,
  PantryItemStatus status = PantryItemStatus.available,
}) {
  return PantryItem(
    id: name,
    familyId: 'fam',
    productId: name,
    name: name,
    quantity: quantity,
    unit: unit,
    expirationDate: expiration ?? DateTime(2030, 1, 1),
    category: 'test',
    originalQuantity: quantity,
    consumedQuantity: 0,
    status: status,
  );
}

Recipe _recipe(String id, List<RecipeIngredient> ingredients) {
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
  final now = DateTime(2026, 9, 20);

  test('matches pantry names ignoring accents and plurals', () {
    expect(NameNormalizer.matches('Lentejas', 'lenteja'), isTrue);
    expect(NameNormalizer.matches('Arroz', 'frijol'), isFalse);
  });

  test('converts kg to g when checking coverage', () {
    final pantry = [_item(name: 'arroz', quantity: 1, unit: 'kg')];
    final recipes = [
      _recipe('arroz_bowl', const [
        RecipeIngredient(productName: 'arroz', quantity: 200, unit: 'g'),
      ]),
    ];
    expect(UnitConverter.compatible('kg', 'g'), isTrue);
    final result = PantryRecipeFilter.filterRecipesByPantry(
      pantryItems: pantry,
      recipes: recipes,
      now: now,
    );
    expect(result.map((recipe) => recipe.id), ['arroz_bowl']);
  });

  test('excludes recipes missing an ingredient or using expired stock', () {
    final pantry = [
      _item(name: 'arroz', quantity: 200, unit: 'g'),
      _item(
        name: 'tomate',
        quantity: 200,
        unit: 'g',
        expiration: DateTime(2026, 9, 1),
      ),
    ];
    final recipes = [
      _recipe('ok', const [
        RecipeIngredient(productName: 'arroz', quantity: 100, unit: 'g'),
      ]),
      _recipe('missing', const [
        RecipeIngredient(productName: 'pasta', quantity: 100, unit: 'g'),
      ]),
      _recipe('expired', const [
        RecipeIngredient(productName: 'tomate', quantity: 50, unit: 'g'),
      ]),
    ];
    final result = PantryRecipeFilter.filterRecipesByPantry(
      pantryItems: pantry,
      recipes: recipes,
      now: now,
    );
    expect(result.map((recipe) => recipe.id), ['ok']);
  });
}
