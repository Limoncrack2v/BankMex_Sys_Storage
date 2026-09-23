import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/domain/catalog_mappers.dart';
import 'package:bank_storage_app/domain/models/recipe.dart' as domain;
import 'package:flutter_test/flutter_test.dart';

Member member(
  String name,
  MemberType type, {
  int? age,
  double? weightKg,
}) => Member(
      memberId: name,
      name: name,
      memberType: type,
      createdAt: DateTime(2026, 9, 21),
      age: age,
      weightKg: weightKg,
    );

void main() {
  test('familyProfile uses stored age and weight for children', () {
    final profile = CatalogMappers.familyProfile(
      familyId: 'fam',
      authUid: 'uid',
      members: [
        member('María', MemberType.adult, age: 38, weightKg: 68),
        member('José', MemberType.adult, age: 41, weightKg: 79),
        member('Lucía', MemberType.child, age: 9, weightKg: 28),
      ],
    );

    expect(profile.adults, 2);
    expect(profile.children, hasLength(1));
    expect(profile.children.single.age, 9);
    expect(profile.children.single.weight, 28);
  });

  test('recipeToUi keeps the catalog servings so the UI can scale them', () {
    const stored = domain.Recipe(
      id: 'rec_nopal',
      name: 'Tacos de nopal PRUEBA-EMULADOR',
      ingredients: [
        domain.RecipeIngredient(
          productName: 'Nopal PRUEBA-EMULADOR',
          quantity: 4,
          unit: 'piece',
        ),
      ],
      steps: ['x'],
      prepTimeMinutes: 15,
      caloriesPerServing: 140,
      status: domain.RecipeStatus.approved,
      servings: 4,
    );

    final ui = CatalogMappers.recipeToUi(stored);
    expect(ui.name, stored.name);
    expect(ui.servings, 4);
    expect(ui.ingredients.single.quantity, 4);
    expect(ui.minutes, 15);
  });
}
