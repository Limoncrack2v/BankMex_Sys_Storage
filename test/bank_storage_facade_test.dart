import 'package:bank_storage_app/application/bank_storage_facade.dart';
import 'package:bank_storage_app/data/models/family.dart';
import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/data/repositories/family_repository.dart';
import 'package:bank_storage_app/data/repositories/meal_plan_repository.dart';
import 'package:bank_storage_app/data/repositories/member_repository.dart';
import 'package:bank_storage_app/data/repositories/pantry_repository.dart';
import 'package:bank_storage_app/data/repositories/recipe_repository.dart';
import 'package:bank_storage_app/domain/models/meal_plan.dart';
import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// Repos de mentira: con `implements` no corre el constructor real, así que no
// hace falta Firebase. Solo responden lo que usa generateMealPlan.

class _Families implements FamilyRepository {
  _Families(this.family);

  final Family? family;

  @override
  Future<Family?> getFamily(String familyId) async => family;

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
  Stream<List<PantryItem>> watchAllPantryItems(String familyId) =>
      Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Recipes implements RecipeRepository {
  @override
  Future<List<Recipe>> listByStatus(RecipeStatus status) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MealPlans implements MealPlanRepository {
  @override
  Future<MealPlan> create(MealPlan plan) async => plan;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Firestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BankStorageFacade facadeFor(Family? family) => BankStorageFacade(
  families: _Families(family),
  members: _Members(),
  pantry: _Pantry(),
  recipes: _Recipes(),
  mealPlans: _MealPlans(),
  firestore: _Firestore(),
);

Family family({DateTime? nextDelivery}) => Family(
  familyId: 'fam',
  address: 'Calle 1',
  registrationDate: DateTime(2026, 9, 1),
  authUid: 'fam',
  appliances: const [],
  nextDeliveryDate: nextDelivery,
);

void main() {
  DateTime inDays(int days) => DateTime.now().add(Duration(days: days));

  group('BankStorageFacade.generateMealPlan', () {
    test(
      'plans 14 days when the next delivery is more than a week away',
      () async {
        final facade = facadeFor(family(nextDelivery: inDays(10)));
        final generated = await facade.generateMealPlan(familyId: 'fam');
        expect(generated.requestedDays, 14);
      },
    );

    test('plans 7 days when the next delivery is within a week', () async {
      final facade = facadeFor(family(nextDelivery: inDays(3)));
      final generated = await facade.generateMealPlan(familyId: 'fam');
      expect(generated.requestedDays, 7);
    });

    test('plans 7 days when no delivery is scheduled', () async {
      final generated = await facadeFor(family())
          .generateMealPlan(familyId: 'fam');
      expect(generated.requestedDays, 7);
    });

    test('an explicit number of days wins over the delivery date', () async {
      final facade = facadeFor(family(nextDelivery: inDays(10)));
      final generated = await facade.generateMealPlan(familyId: 'fam', days: 3);
      expect(generated.requestedDays, 3);
    });

    test('fails when the family does not exist', () {
      expect(
        facadeFor(null).generateMealPlan(familyId: 'fam'),
        throwsStateError,
      );
    });
  });
}
