import 'package:bank_storage_app/domain/meal_plan_generator.dart';
import 'package:bank_storage_app/domain/models/family_profile.dart';
import 'package:bank_storage_app/domain/models/pantry_item.dart';
import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:bank_storage_app/domain/recipe_catalog.dart';
import 'package:bank_storage_app/domain/recipe_on_demand.dart';
import 'package:bank_storage_app/domain/recipe_planner.dart';
import 'package:flutter_test/flutter_test.dart';

PantryItem pantry(String name, double grams, DateTime expiration) {
  return PantryItem(
    id: name,
    familyId: 'fam',
    productId: name,
    name: name,
    quantity: grams,
    unit: 'g',
    expirationDate: expiration,
    category: 'test',
    originalQuantity: grams,
    consumedQuantity: 0,
    status: PantryItemStatus.available,
  );
}

Recipe recipe(String id, String product, double grams) {
  return Recipe(
    id: id,
    name: id,
    ingredients: [
      RecipeIngredient(productName: product, quantity: grams, unit: 'g'),
    ],
    steps: const ['x'],
    prepTimeMinutes: 1,
    caloriesPerServing: 1,
    status: RecipeStatus.approved,
  );
}

void main() {
  final now = DateTime(2026, 10, 6);
  const family = FamilyProfile(
    id: 'fam',
    authUid: 'fam',
    adults: 2,
    children: [],
    dietaryRestrictions: [],
  );
  // Tipada como la interfaz: las pruebas solo usan el contrato.
  const RecipePlanner planner = RuleBasedRecipePlanner();
  final items = [
    pantry('zanahoria', 400, DateTime(2026, 10, 8)),
    pantry('arroz', 2000, DateTime(2026, 11, 20)),
  ];
  final recipes = [
    recipe('arroz_solo', 'arroz', 100),
    recipe('zanahoria_sola', 'zanahoria', 100),
  ];

  test('suggests the same recipe as RecipeOnDemand', () async {
    final expected = RecipeOnDemand.getSingleRecipeOnDemand(
      family: family,
      pantryItems: items,
      recipes: recipes,
      now: now,
    );
    final suggested = await planner.suggestRecipe(
      family: family,
      pantryItems: items,
      recipes: recipes,
      now: now,
    );
    expect(suggested, isNotNull);
    expect(suggested!.id, expected!.id);
  });

  test('suggests nothing when the only recipe that fits is pending', () async {
    final pending = RecipeCatalog.submitRecipe(
      id: 'pendiente',
      name: 'pendiente',
      ingredients: const [
        RecipeIngredient(productName: 'arroz', quantity: 100, unit: 'g'),
      ],
      steps: const ['x'],
      prepTimeMinutes: 1,
      caloriesPerServing: 1,
    );
    final suggested = await planner.suggestRecipe(
      family: family,
      pantryItems: items,
      recipes: [pending],
      now: now,
    );
    expect(suggested, isNull);
  });

  test('plans the same days as MealPlanGenerator', () async {
    // Un día después de now, para que perder startDate se note.
    final start = DateTime(2026, 10, 7);
    final expected = MealPlanGenerator.generateMealPlan(
      family: family,
      pantryItems: items,
      recipes: recipes,
      days: 7,
      startDate: start,
      now: now,
    );
    final generated = await planner.planDays(
      family: family,
      pantryItems: items,
      recipes: recipes,
      days: 7,
      startDate: start,
      now: now,
    );
    expect(generated.requestedDays, 7);
    expect(generated.filledDays, expected.filledDays);
    expect(
      generated.plan.meals.map((meal) => (meal.date, meal.recipeId)).toList(),
      expected.plan.meals.map((meal) => (meal.date, meal.recipeId)).toList(),
    );
  });
}
