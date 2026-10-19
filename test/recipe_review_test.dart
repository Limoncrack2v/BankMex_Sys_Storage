import 'package:bank_storage_app/application/bank_storage_facade.dart';
import 'package:bank_storage_app/data/repositories/family_repository.dart';
import 'package:bank_storage_app/data/repositories/meal_plan_repository.dart';
import 'package:bank_storage_app/data/repositories/member_repository.dart';
import 'package:bank_storage_app/data/repositories/pantry_repository.dart';
import 'package:bank_storage_app/data/repositories/recipe_repository.dart';
import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:bank_storage_app/domain/recipe_catalog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// RecipeRepository de mentira: apunta lo que le piden escribir.
class _FakeRecipes extends Fake implements RecipeRepository {
  Recipe? stored;
  final calls = <String>[];

  @override
  Future<Recipe?> getById(String recipeId) async =>
      stored?.id == recipeId ? stored : null;

  @override
  Future<Recipe> update(Recipe recipe) async {
    calls.add('update ${recipe.status.name}');
    return recipe;
  }

  @override
  Future<void> approve(String recipeId, {required String reviewerUid}) async =>
      calls.add('approve $recipeId by $reviewerUid');

  @override
  Future<void> reject(
    String recipeId, {
    required String reviewerUid,
    required String note,
  }) async => calls.add('reject $recipeId by $reviewerUid: $note');
}

class _FakeFamilies extends Fake implements FamilyRepository {}

class _FakePantry extends Fake implements PantryRepository {}

class _FakeMembers extends Fake implements MemberRepository {}

class _FakeMealPlans extends Fake implements MealPlanRepository {}

class _FakeFirestore extends Fake implements FirebaseFirestore {}

BankStorageFacade _facade(_FakeRecipes recipes) => BankStorageFacade(
  families: _FakeFamilies(),
  pantry: _FakePantry(),
  members: _FakeMembers(),
  recipes: recipes,
  mealPlans: _FakeMealPlans(),
  firestore: _FakeFirestore(),
);

Recipe _recipe(RecipeStatus status, {Map<String, dynamic>? extra}) =>
    Recipe.fromMap('r1', {
      'name': 'Sopa',
      'status': status.name,
      'ingredients': [
        {'productName': 'Lenteja', 'quantity': 0.25, 'unit': 'kg'},
      ],
      'steps': ['Cocer'],
      'prepTimeMinutes': 30,
      'caloriesPerServing': 200,
      ...?extra,
    });

void main() {
  group('RecipeStatus', () {
    test('has the three states and reads them back', () {
      expect(RecipeStatus.values.map((s) => s.name), [
        'draft',
        'pending',
        'approved',
      ]);
      for (final status in RecipeStatus.values) {
        expect(RecipeStatus.fromFirestore(status.firestoreValue), status);
      }
    });

    test('an unknown or missing value waits for review', () {
      expect(RecipeStatus.fromFirestore('archivada'), RecipeStatus.pending);
      expect(RecipeStatus.fromFirestore(null), RecipeStatus.pending);
    });
  });

  group('Recipe review fields', () {
    test('are written only when they have a value', () {
      expect(
        _recipe(RecipeStatus.pending).toMap().keys,
        isNot(contains('approvedBy')),
      );
      expect(
        _recipe(RecipeStatus.pending).toMap().keys,
        isNot(contains('reviewNote')),
      );
    });

    test('are read from the document', () {
      final rejected = _recipe(
        RecipeStatus.draft,
        extra: {
          'reviewNote': 'Falta sal',
          'rejectedBy': 'nutri1',
          'rejectedAt': DateTime(2026, 10, 14),
        },
      );
      expect(rejected.reviewNote, 'Falta sal');
      expect(rejected.rejectedBy, 'nutri1');
      expect(rejected.rejectedAt, DateTime(2026, 10, 14));
      expect(rejected.toMap()['reviewNote'], 'Falta sal');
    });

    test('copyWith keeps them', () {
      final approved = _recipe(
        RecipeStatus.approved,
        extra: {'approvedBy': 'nutri1', 'approvedAt': DateTime(2026, 10, 14)},
      );
      expect(approved.copyWith(name: 'Otra').approvedBy, 'nutri1');
    });
  });

  group('withStaffStatus', () {
    final approved = _recipe(
      RecipeStatus.approved,
      extra: {'approvedBy': 'nutri1', 'approvedAt': DateTime(2026, 10, 14)},
    );
    final rejected = _recipe(
      RecipeStatus.draft,
      extra: {
        'reviewNote': 'Falta sal',
        'rejectedBy': 'nutri1',
        'rejectedAt': DateTime(2026, 10, 14),
      },
    );

    test('leaving approved drops who approved it', () {
      for (final status in [RecipeStatus.draft, RecipeStatus.pending]) {
        final recipe = approved.withStaffStatus(status);
        expect(recipe.status, status);
        expect(recipe.approvedBy, isNull);
        expect(recipe.approvedAt, isNull);
      }
    });

    test('a rejected draft keeps its note while it stays a draft', () {
      final recipe = rejected.withStaffStatus(RecipeStatus.draft);
      expect(recipe.reviewNote, 'Falta sal');
      expect(recipe.rejectedBy, 'nutri1');
    });

    test('sending it back to review clears the note', () {
      final recipe = rejected.withStaffStatus(RecipeStatus.pending);
      expect(recipe.reviewNote, isNull);
      expect(recipe.rejectedBy, isNull);
      expect(recipe.rejectedAt, isNull);
    });
  });

  group('RecipeCatalog review', () {
    final pending = _recipe(RecipeStatus.pending);

    test('approve needs a pending recipe', () {
      for (final status in [RecipeStatus.draft, RecipeStatus.approved]) {
        expect(
          () => RecipeCatalog.approveRecipe(
            _recipe(status),
            approvedBy: 'nutri1',
            at: DateTime(2026, 10, 14),
          ),
          throwsStateError,
        );
      }
    });

    test('reject returns a draft with the note, who and when', () {
      final rejected = RecipeCatalog.rejectRecipe(
        pending,
        rejectedBy: 'nutri1',
        note: '  Falta sal  ',
        at: DateTime(2026, 10, 14),
      );
      expect(rejected.status, RecipeStatus.draft);
      expect(rejected.reviewNote, 'Falta sal');
      expect(rejected.rejectedBy, 'nutri1');
      expect(rejected.rejectedAt, DateTime(2026, 10, 14));
    });

    test('reject needs a note of at most 300 characters', () {
      for (final note in ['', '   ', 'a' * 301]) {
        expect(
          () => RecipeCatalog.rejectRecipe(
            pending,
            rejectedBy: 'nutri1',
            note: note,
            at: DateTime(2026, 10, 14),
          ),
          throwsArgumentError,
        );
      }
    });

    test('a draft can be submitted', () {
      final draft = RecipeCatalog.submitRecipe(
        name: 'Nueva',
        ingredients: const [
          RecipeIngredient(productName: 'arroz', quantity: 1, unit: 'kg'),
        ],
        steps: const ['x'],
        prepTimeMinutes: 1,
        caloriesPerServing: 1,
        status: RecipeStatus.draft,
      );
      expect(draft.status, RecipeStatus.draft);
    });
  });

  group('BankStorageFacade review', () {
    test('approve writes only through approve, with the reviewer', () async {
      final recipes = _FakeRecipes()..stored = _recipe(RecipeStatus.pending);
      final approved = await _facade(recipes)
          .approveRecipe('r1', reviewerUid: 'nutri1');
      expect(recipes.calls, ['approve r1 by nutri1']);
      expect(approved.status, RecipeStatus.approved);
      expect(approved.approvedBy, 'nutri1');
    });

    test('reject writes the trimmed note and returns the draft', () async {
      final recipes = _FakeRecipes()..stored = _recipe(RecipeStatus.pending);
      final rejected = await _facade(recipes)
          .rejectRecipe('r1', reviewerUid: 'nutri1', note: ' Falta sal ');
      expect(recipes.calls, ['reject r1 by nutri1: Falta sal']);
      expect(rejected.status, RecipeStatus.draft);
    });

    test('reject without a note writes nothing', () async {
      final recipes = _FakeRecipes()..stored = _recipe(RecipeStatus.pending);
      await expectLater(
        _facade(recipes).rejectRecipe('r1', reviewerUid: 'nutri1', note: ' '),
        throwsArgumentError,
      );
      expect(recipes.calls, isEmpty);
    });

    test('only a pending recipe is reviewed', () async {
      for (final status in [RecipeStatus.draft, RecipeStatus.approved]) {
        final recipes = _FakeRecipes()..stored = _recipe(status);
        await expectLater(
          _facade(recipes).approveRecipe('r1', reviewerUid: 'nutri1'),
          throwsStateError,
        );
        expect(recipes.calls, isEmpty);
      }
      await expectLater(
        _facade(_FakeRecipes()).approveRecipe('nope', reviewerUid: 'nutri1'),
        throwsStateError,
      );
    });

    test('Staff cannot save a recipe as approved', () async {
      final recipes = _FakeRecipes();
      await expectLater(
        _facade(recipes).updateRecipe(
          _recipe(RecipeStatus.approved),
          previous: _recipe(RecipeStatus.pending),
        ),
        throwsArgumentError,
      );
      expect(recipes.calls, isEmpty);
    });

    test('Staff can send a recipe back to draft', () async {
      final recipes = _FakeRecipes();
      final approved = _recipe(RecipeStatus.approved);
      await _facade(recipes).updateRecipe(
        approved.withStaffStatus(RecipeStatus.draft),
        previous: approved,
      );
      expect(recipes.calls, ['update draft']);
    });
  });
}
