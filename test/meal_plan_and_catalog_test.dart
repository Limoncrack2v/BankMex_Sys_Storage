import 'package:bank_storage_app/domain/meal_plan_generator.dart';
import 'package:bank_storage_app/domain/recipe_catalog.dart';
import 'package:bank_storage_app/domain/recipe_on_demand.dart';
import 'package:bank_storage_app/domain/models/family_profile.dart';
import 'package:bank_storage_app/domain/models/pantry_item.dart';
import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

PantryItem pantry({
  required String name,
  required double quantity,
  required DateTime expiration,
}) {
  return PantryItem(
    id: name,
    familyId: 'fam',
    productId: name,
    name: name,
    quantity: quantity,
    unit: 'g',
    expirationDate: expiration,
    category: 'test',
    originalQuantity: quantity,
    consumedQuantity: 0,
    status: PantryItemStatus.available,
  );
}

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
  final now = DateTime(2026, 9, 20);
  const family = FamilyProfile(
    id: 'fam',
    authUid: 'fake',
    adults: 2,
    children: [],
    dietaryRestrictions: [],
  );

  test('submit stays pending and approve flips status', () {
    final submitted = RecipeCatalog.submitRecipe(
      name: 'Nueva',
      ingredients: const [
        RecipeIngredient(productName: 'arroz', quantity: 10, unit: 'g'),
      ],
      steps: const ['x'],
      prepTimeMinutes: 1,
      caloriesPerServing: 1,
    );
    expect(submitted.status, RecipeStatus.pending);
    expect(RecipeCatalog.approveRecipe(submitted).status, RecipeStatus.approved);
  });

  test('publish marks the recipe approved for families', () {
    final published = RecipeCatalog.publishRecipe(
      name: 'Publicada',
      ingredients: const [
        RecipeIngredient(productName: 'arroz', quantity: 10, unit: 'g'),
      ],
      steps: const ['x'],
      prepTimeMinutes: 1,
      caloriesPerServing: 1,
    );
    expect(published.status, RecipeStatus.approved);
  });

  test('on-demand recipe prefers the one using food that expires first', () {
    final items = [
      pantry(name: 'zanahoria', quantity: 500, expiration: DateTime(2026, 9, 22)),
      pantry(name: 'arroz', quantity: 2000, expiration: DateTime(2026, 10, 20)),
      pantry(name: 'lentejas', quantity: 500, expiration: DateTime(2026, 11, 1)),
    ];
    final recipes = [
      recipe('later', const [
        RecipeIngredient(productName: 'arroz', quantity: 100, unit: 'g'),
        RecipeIngredient(productName: 'lentejas', quantity: 100, unit: 'g'),
      ]),
      recipe('urgent', const [
        RecipeIngredient(productName: 'zanahoria', quantity: 80, unit: 'g'),
        RecipeIngredient(productName: 'arroz', quantity: 50, unit: 'g'),
      ]),
    ];

    final picked = RecipeOnDemand.getSingleRecipeOnDemand(
      family: family,
      pantryItems: items,
      recipes: recipes,
      now: now,
    );
    expect(picked?.id, 'urgent');
  });

  test('meal plan is FIFO, deducts pantry, and skips pending recipes', () {
    final items = [
      pantry(name: 'zanahoria', quantity: 400, expiration: DateTime(2026, 9, 22)),
      pantry(name: 'arroz', quantity: 2000, expiration: DateTime(2026, 10, 20)),
    ];
    final recipes = [
      recipe('zanahoria_rice', const [
        RecipeIngredient(productName: 'zanahoria', quantity: 80, unit: 'g'),
        RecipeIngredient(productName: 'arroz', quantity: 50, unit: 'g'),
      ]),
      RecipeCatalog.submitRecipe(
        id: 'pending_should_skip',
        name: 'pending',
        ingredients: const [
          RecipeIngredient(productName: 'arroz', quantity: 10, unit: 'g'),
        ],
        steps: const ['x'],
        prepTimeMinutes: 1,
        caloriesPerServing: 1,
      ),
    ];

    final generated = MealPlanGenerator.generateMealPlan(
      family: family,
      pantryItems: items,
      recipes: recipes,
      days: 3,
      startDate: now,
      now: now,
    );

    expect(generated.filledDays, 3);
    expect(
      generated.plan.meals.every((meal) => meal.recipeId == 'zanahoria_rice'),
      isTrue,
    );
    final carrots = generated.updatedPantry.firstWhere((item) => item.id == 'zanahoria');
    expect(carrots.quantity, lessThan(400));
    expect(carrots.consumedQuantity, greaterThan(0));
  });
}
