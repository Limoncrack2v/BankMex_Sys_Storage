import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:bank_storage_app/domain/recipe_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

RecipeIngredient _ingredient(int i) =>
    RecipeIngredient(productName: 'Producto $i', quantity: 1, unit: 'kg');

Recipe _submit({int ingredients = 1, int steps = 1, int dietaryTags = 0}) =>
    RecipeCatalog.submitRecipe(
      name: 'Receta',
      ingredients: [for (var i = 0; i < ingredients; i++) _ingredient(i)],
      steps: [for (var i = 0; i < steps; i++) 'Paso $i'],
      prepTimeMinutes: 10,
      caloriesPerServing: 100,
      dietaryTags: [for (var i = 0; i < dietaryTags; i++) 'etiqueta$i'],
    );

void main() {
  group('RecipeCatalog limits (the ones validRecipe has in the rules)', () {
    test('a recipe at the limits is accepted', () {
      expect(
        () => _submit(
          ingredients: RecipeCatalog.maxIngredients,
          steps: RecipeCatalog.maxSteps,
          dietaryTags: RecipeCatalog.maxDietaryTags,
        ),
        returnsNormally,
      );
    });

    test('one ingredient over the limit is rejected', () {
      expect(
        () => _submit(ingredients: RecipeCatalog.maxIngredients + 1),
        throwsArgumentError,
      );
    });

    test('one step over the limit is rejected', () {
      expect(
        () => _submit(steps: RecipeCatalog.maxSteps + 1),
        throwsArgumentError,
      );
    });

    test('one dietary tag over the limit is rejected', () {
      expect(
        () => _submit(dietaryTags: RecipeCatalog.maxDietaryTags + 1),
        throwsArgumentError,
      );
    });
  });
}
