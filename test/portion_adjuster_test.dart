import 'package:bank_storage_app/domain/portion_adjuster.dart';
import 'package:bank_storage_app/domain/models/child_profile.dart';
import 'package:bank_storage_app/domain/models/family_profile.dart';
import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scales ingredients by family adult-equivalent servings vs base of 4', () {
    const family = FamilyProfile(
      id: 'fam',
      authUid: 'x',
      adults: 2,
      children: [ChildProfile(age: 8, weight: 25)],
      dietaryRestrictions: [],
    );
    const recipe = Recipe(
      id: 'r',
      name: 'sopa',
      ingredients: [
        RecipeIngredient(productName: 'arroz', quantity: 400, unit: 'g'),
      ],
      steps: ['x'],
      prepTimeMinutes: 10,
      caloriesPerServing: 100,
      status: RecipeStatus.approved,
    );

    final factor = PortionAdjuster.familyServingFactor(family);
    expect(factor, greaterThan(2));
    expect(factor, lessThan(4));

    final adjusted = PortionAdjuster.adjustPortions(recipe, family);
    expect(adjusted.ingredients.single.quantity, lessThan(400));
    expect(adjusted.ingredients.single.quantity, greaterThan(200));
  });

  test('an extra adult increases ingredient quantities', () {
    const recipe = Recipe(
      id: 'r',
      name: 'sopa',
      ingredients: [
        RecipeIngredient(productName: 'arroz', quantity: 400, unit: 'g'),
      ],
      steps: ['x'],
      prepTimeMinutes: 10,
      caloriesPerServing: 100,
      status: RecipeStatus.approved,
    );
    const two = FamilyProfile(
      id: 'fam',
      authUid: 'x',
      adults: 2,
      children: [],
      dietaryRestrictions: [],
    );
    const three = FamilyProfile(
      id: 'fam',
      authUid: 'x',
      adults: 3,
      children: [],
      dietaryRestrictions: [],
    );

    final forTwo = PortionAdjuster.adjustPortions(recipe, two);
    final forThree = PortionAdjuster.adjustPortions(recipe, three);
    expect(forThree.ingredients.single.quantity,
        greaterThan(forTwo.ingredients.single.quantity));
  });
}
