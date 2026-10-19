import 'package:bank_storage_app/application/bank_storage_facade.dart';
import 'package:bank_storage_app/data/models/family.dart';
import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart' as data;
import 'package:bank_storage_app/data/repositories/family_repository.dart';
import 'package:bank_storage_app/data/repositories/meal_plan_repository.dart';
import 'package:bank_storage_app/data/repositories/member_repository.dart';
import 'package:bank_storage_app/data/repositories/pantry_repository.dart';
import 'package:bank_storage_app/data/repositories/recipe_repository.dart';
import 'package:bank_storage_app/domain/meal_plan_generator.dart';
import 'package:bank_storage_app/domain/models/family_profile.dart';
import 'package:bank_storage_app/domain/models/meal_plan.dart';
import 'package:bank_storage_app/domain/models/pantry_item.dart';
import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:bank_storage_app/domain/recipe_adjustment.dart';
import 'package:bank_storage_app/domain/recipe_planner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// Repos de mentira: con `implements` no corre el constructor real, así que no
// hace falta Firebase. Solo responden lo que la fachada le pide al planner.

class _Families implements FamilyRepository {
  @override
  Future<Family?> getFamily(String familyId) async => Family(
    familyId: familyId,
    address: 'Calle 1',
    registrationDate: DateTime(2026, 9, 1),
    authUid: familyId,
    appliances: const [],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Members implements MemberRepository {
  @override
  Stream<List<Member>> watchAllMembers(String familyId) =>
      Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Pantry implements PantryRepository {
  @override
  Stream<List<data.PantryItem>> watchAllPantryItems(String familyId) =>
      Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Recipes implements RecipeRepository {
  _Recipes(this.catalog);

  final List<Recipe> catalog;

  @override
  Future<List<Recipe>> listByStatus(RecipeStatus status) async => catalog;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MealPlans implements MealPlanRepository {
  @override
  Future<MealPlan> create(MealPlan plan) async =>
      throw StateError('generateMealPlan no debe guardar el plan');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Firestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Planner de mentira: guarda lo que le pasa la fachada y regresa algo que
/// las reglas nunca darían, para saber que la respuesta salió de aquí.
class _Planner implements RecipePlanner {
  _Planner(this.suggestion);

  final Recipe? suggestion;
  String? suggestedFor;
  List<Recipe>? suggestedFrom;
  String? plannedFor;
  int? plannedDays;

  @override
  Future<Recipe?> suggestRecipe({
    required FamilyProfile family,
    required List<PantryItem> pantryItems,
    required List<Recipe> recipes,
    DateTime? now,
  }) async {
    suggestedFor = family.id;
    suggestedFrom = recipes;
    return suggestion;
  }

  @override
  Future<RecipeAdjustmentSuggestion?> suggestAdjustment({
    required AdjustmentContext household,
    required Recipe recipe,
  }) async => null;

  @override
  Future<MealPlanGeneration> planDays({
    required FamilyProfile family,
    required List<PantryItem> pantryItems,
    required List<Recipe> recipes,
    required int days,
    DateTime? startDate,
    DateTime? now,
  }) async {
    plannedFor = family.id;
    plannedDays = days;
    final start = DateTime(2026, 10, 12);
    return MealPlanGeneration(
      plan: MealPlan(
        id: '',
        familyId: family.id,
        dateRangeStart: start,
        dateRangeEnd: start.add(Duration(days: days)),
        meals: const [],
      ),
      updatedPantry: const [],
      requestedDays: days,
      filledDays: 99,
    );
  }
}

Recipe recipe(String id) => Recipe(
  id: id,
  name: id,
  ingredients: const [
    RecipeIngredient(productName: 'arroz', quantity: 100, unit: 'g'),
  ],
  steps: const ['x'],
  prepTimeMinutes: 1,
  caloriesPerServing: 1,
  status: RecipeStatus.approved,
);

void main() {
  final catalog = [recipe('del_catalogo')];

  BankStorageFacade facadeWith(RecipePlanner planner) => BankStorageFacade(
    families: _Families(),
    members: _Members(),
    pantry: _Pantry(),
    recipes: _Recipes(catalog),
    mealPlans: _MealPlans(),
    firestore: _Firestore(),
    planner: planner,
  );

  group('BankStorageFacade uses the injected RecipePlanner', () {
    test('getSingleRecipeOnDemand returns what the planner suggests', () async {
      final planner = _Planner(recipe('del_planner'));
      final suggested = await facadeWith(planner)
          .getSingleRecipeOnDemand('fam');

      // La despensa está vacía: las reglas regresarían null.
      expect(suggested?.id, 'del_planner');
      expect(planner.suggestedFor, 'fam');
      expect(planner.suggestedFrom, catalog);
    });

    test('getSingleRecipeOnDemand is null when the planner has none', () async {
      final suggested = await facadeWith(_Planner(null))
          .getSingleRecipeOnDemand('fam');
      expect(suggested, isNull);
    });

    test('generateMealPlan returns what the planner plans', () async {
      final planner = _Planner(null);
      final generated = await facadeWith(planner)
          .generateMealPlan(familyId: 'fam', days: 3);

      expect(planner.plannedFor, 'fam');
      expect(planner.plannedDays, 3);
      // Las reglas nunca llenan más días de los pedidos.
      expect(generated.filledDays, 99);
    });
  });
}
