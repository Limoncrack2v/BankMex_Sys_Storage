import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/data/repositories/pantry_repository.dart';
import 'package:bank_storage_app/domain/models/appliance.dart';
import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:bank_storage_app/domain/models/recipe_adjustment.dart';
import 'package:bank_storage_app/domain/recipe_adjustment.dart';
import 'package:bank_storage_app/domain/recipe_catalog.dart';

// The lists of units, categories, tags and states, the limits and the fields of
// recipes, consumptionLogs and adjustments are written in firestore.rules and
// in the Dart models, which cannot import each other. These tests read the
// rules and fail when the copies drift apart (the same idea as
// delivery_rules_consistency_test.dart). The rules themselves are exercised
// against the emulator in test_emulator/rules_recipe_validation_test.dart,
// rules_recipes_test.dart, rules_consumption_logs_test.dart and
// rules_adjustments_test.dart.
void main() {
  final rules = File('firestore.rules').readAsStringSync();

  /// The text of `function [name](...) { ... }` in the rules.
  String body(String name) {
    final start = rules.indexOf('function $name(');
    if (start < 0) throw StateError('function $name not found in the rules');
    final end = rules.indexOf('\n    }\n', start);
    return rules.substring(start, end);
  }

  /// The strings of a rules list: `['a', 'b']` -> [a, b].
  List<String> strings(String list) =>
      RegExp(r"'([^']+)'").allMatches(list).map((m) => m.group(1)!).toList();

  /// The lists of a call like `hasOnly([...])`, in order.
  List<List<String>> lists(String text, String before) =>
      RegExp('$before\\(\\[([^\\]]*)\\]')
          .allMatches(text)
          .map((m) => strings(m.group(1)!))
          .toList();

  int number(String text, String pattern) =>
      int.parse(RegExp(pattern).firstMatch(text)!.group(1)!);

  List<int> positions(String text, String pattern) =>
      RegExp(pattern)
          .allMatches(text)
          .map((m) => int.parse(m.group(1)!))
          .toList();

  final units = FoodUnit.values.map((unit) => unit.name).toList();
  final categories = FoodType.values.map((type) => type.name).toList();

  group('units and categories', () {
    test('a recipe ingredient unit is a FoodUnit', () {
      final match = RegExp(r"item\.unit\.matches\('([a-z|]+)'\)")
          .firstMatch(body('validRecipeIngredient'));

      expect(match, isNotNull);
      expect(match!.group(1)!.split('|'), unorderedEquals(units));
    });

    test('a consumption log unit and category are FoodUnit and FoodType', () {
      final log = body('validConsumptionLog');

      expect(
        strings(
          RegExp(r'data\.unit in (\[[^\]]*\])').firstMatch(log)!.group(1)!,
        ),
        unorderedEquals(units),
      );
      expect(
        strings(
          RegExp(r'data\.category in (\[[^\]]*\])').firstMatch(log)!.group(1)!,
        ),
        unorderedEquals(categories),
      );
    });

    test('an adjustment checks its ingredients like a recipe does', () {
      expect(body('validAdjustment'), contains('validRecipeIngredients('));
    });
  });

  group('tags, equipment and states', () {
    final recipe = body('validRecipe');

    test('nutritional tags are the NutritionalTag ids', () {
      final known = RegExp(
        r'validRecipeTags\(data\.nutritionalTags,\s*(\[[^\]]*\])',
      ).firstMatch(recipe)!.group(1)!;

      expect(
        strings(known),
        unorderedEquals(NutritionalTag.values.map((tag) => tag.id)),
      );
    });

    test('equipment is the Appliance ids', () {
      final known = RegExp(
        r'validRecipeTags\(data\.requiredEquipment,\s*(\[[^\]]*\])',
      ).firstMatch(recipe)!.group(1)!;

      expect(
        strings(known),
        unorderedEquals(Appliance.values.map((appliance) => appliance.id)),
      );
    });

    test('the states of a recipe are the RecipeStatus values', () {
      final states = strings(
        RegExp(r'data\.status in (\[[^\]]*\])').firstMatch(recipe)!.group(1)!,
      );

      expect(
        states,
        unorderedEquals(RecipeStatus.values.map((status) => status.name)),
      );
    });

    test('the states of an adjustment are the AdjustmentStatus values', () {
      final review = body('nutritionistReviewsAdjustment');
      final decided = RegExp(r"data\.status == '([a-z]+)'")
          .allMatches(review)
          .map((m) => m.group(1)!);

      expect({
        'pending',
        ...decided,
      }, AdjustmentStatus.values.map((status) => status.name).toSet());
      expect(body('validAdjustment'), contains("data.status == 'pending'"));
    });
  });

  group('limits', () {
    test(
      'the ingredient cap and positions are RecipeCatalog.maxIngredients',
      () {
        final text = body('validRecipeIngredients');

        expect(
          number(text, r'n >= 1 && n <= (\d+)'),
          RecipeCatalog.maxIngredients,
        );
        expect(positions(text, r'validRecipeIngredient\(items\[(\d+)\]\)'), [
          for (var i = 0; i < RecipeCatalog.maxIngredients; i++) i,
        ]);
      },
    );

    test('the step cap and positions are RecipeCatalog.maxSteps', () {
      final text = body('validRecipeSteps');

      expect(number(text, r'n >= 1 && n <= (\d+)'), RecipeCatalog.maxSteps);
      expect(positions(text, r'steps\[(\d+)\]\.matches'), [
        for (var i = 0; i < RecipeCatalog.maxSteps; i++) i,
      ]);
    });

    test('the dietary tag cap is RecipeCatalog.maxDietaryTags', () {
      expect(
        number(body('validDietaryTags'), r'tags\.size\(\) <= (\d+)'),
        RecipeCatalog.maxDietaryTags,
      );
    });

    test(
      'the change cap and positions are AdjustmentChange.maxPerSuggestion',
      () {
        final text = body('validAdjustmentChanges');

        expect(
          number(text, r'n >= 1 && n <= (\d+)'),
          AdjustmentChange.maxPerSuggestion,
        );
        expect(positions(text, r'validAdjustmentChange\(changes\[(\d+)\]\)'), [
          for (var i = 0; i < AdjustmentChange.maxPerSuggestion; i++) i,
        ]);
        expect(RecipeAdjustment.maxChanges, AdjustmentChange.maxPerSuggestion);
      },
    );

    test('the text limits of an adjustment are the ones of the models', () {
      final change = body('validAdjustmentChange');
      final adjustment = body('validAdjustment');
      final review = body('nutritionistReviewsAdjustment');

      expect(
        number(change, r"reason\.matches\('\(\?s\)\.\{1,(\d+)\}'\)"),
        AdjustmentChange.maxTextLength,
      );
      expect(
        number(change, r"from\.matches\('\(\?s\)\.\{1,(\d+)\}'\)"),
        AdjustmentChange.maxNameLength,
      );
      expect(
        number(change, r"to\.matches\('\(\?s\)\.\{1,(\d+)\}'\)"),
        AdjustmentChange.maxNameLength,
      );
      expect(
        number(adjustment, r"summary\.matches\('\(\?s\)\.\{1,(\d+)\}'\)"),
        RecipeAdjustment.maxSummaryLength,
      );
      expect(
        number(review, r'rejectionReason\.size\(\) <= (\d+)'),
        RecipeAdjustment.maxReasonLength,
      );
    });

    test('the rejection note of a recipe is Recipe.maxReviewNoteLength', () {
      expect(
        number(body('nutritionistRejects'), r'reviewNote\.size\(\) <= (\d+)'),
        Recipe.maxReviewNoteLength,
      );
    });
  });

  group('fields', () {
    test('a recipe has the fields Recipe.toMap writes', () {
      final recipe = Recipe(
        id: 'r1',
        name: 'Sopa',
        ingredients: const [
          RecipeIngredient(productName: 'Lenteja', quantity: 1, unit: 'kg'),
        ],
        steps: const ['Cocer'],
        prepTimeMinutes: 30,
        caloriesPerServing: 200,
        status: RecipeStatus.approved,
        approvedBy: 'nutri1',
        approvedAt: DateTime(2026, 10, 14),
        reviewNote: 'Nota',
        rejectedBy: 'nutri1',
        rejectedAt: DateTime(2026, 10, 14),
      );
      final text = body('validRecipe');
      final only = lists(text, r'data\.keys\(\)\.hasOnly').single;
      final all = lists(text, r'data\.keys\(\)\.hasAll').single;

      expect(only, unorderedEquals(recipe.toMap().keys));
      // hasAll: everything but what only the nutritionist writes.
      expect(
        all,
        unorderedEquals(
          recipe.toMap().keys.toSet().difference({
            'approvedBy',
            'approvedAt',
            'reviewNote',
            'rejectedBy',
            'rejectedAt',
          }),
        ),
      );
    });

    test('a consumption log has the fields PantryRepository writes', () {
      final item = PantryItem(
        pantryItemId: 'p1',
        productId: 'Arroz',
        deliveryId: 'd1',
        type: FoodType.grain,
        quantity: 2,
        unit: FoodUnit.kg,
        daysUntilExpiration: 30,
        deviceId: 'device',
        localTimestamp: DateTime(2026, 10, 1),
      );
      final written = PantryRepository.consumptionLog(
        item: item,
        amount: 1,
        at: DateTime(2026, 10, 14),
        deviceId: 'device',
      ).keys;
      final text = body('validConsumptionLog');

      expect(
        lists(text, r'data\.keys\(\)\.hasOnly').single,
        unorderedEquals(written),
      );
      expect(
        lists(text, r'data\.keys\(\)\.hasAll').single,
        unorderedEquals(written),
      );
    });

    test(
      'an adjustment has the fields the family writes when it creates it',
      () {
        final adjustment = RecipeAdjustment(
          id: '',
          familyId: 'famA',
          recipeId: 'r1',
          baseSignature: 'abcdef12',
          householdSize: 4,
          householdKey: '4-dairy',
          servings: 4,
          ingredients: const [],
          changes: const [],
          summary: 'x',
          status: AdjustmentStatus.pending,
        );
        // familyId and createdAt are added by AdjustmentRepository.create.
        final written = {...adjustment.toMap().keys, 'familyId', 'createdAt'};
        final text = body('validAdjustment');

        expect(
          lists(text, r'data\.keys\(\)\.hasOnly').single,
          unorderedEquals(written),
        );
        expect(
          lists(text, r'data\.keys\(\)\.hasAll').single,
          unorderedEquals(written),
        );
      },
    );

    test('the id of an adjustment is RecipeAdjustment.documentId', () {
      // El orden de las partes en la regla de crear es el del id de Dart.
      final rule = RegExp(
        r"adjustmentId == request\.resource\.data\.familyId\[4\] \+ '_'\s*"
        r"\+ request\.resource\.data\.recipeId \+ '_'\s*"
        r"\+ request\.resource\.data\.baseSignature \+ '_'\s*"
        r"\+ request\.resource\.data\.householdKey",
      ).firstMatch(rules);

      expect(rule, isNotNull);
      expect(
        RecipeAdjustment.documentId(
          familyId: 'famA',
          recipeId: 'r1',
          baseSignature: 'abcdef12',
          householdKey: '4-dairy',
        ),
        'famA_r1_abcdef12_4-dairy',
      );
    });

    test('the household key is the size and the allergies in alphabetical order', () {
      // La regla acepta el tamaño y luego las alergias de Allergy, en orden
      // alfabético y cada una una sola vez.
      final rule = RegExp(
        r"householdKey\.matches\(string\(data\.householdSize\) \+ '([^']+)'\)",
      ).firstMatch(body('validAdjustment'));

      expect(rule, isNotNull);
      final allergies = RegExp(r'\(-([a-z]+)\)\?')
          .allMatches(rule!.group(1)!)
          .map((m) => m.group(1)!)
          .toList();
      final sorted = Allergy.values.map((a) => a.name).toList()..sort();

      expect(allergies, sorted);
      // Y la clave de Dart sale en ese mismo orden.
      expect(
        householdKeyOf(3, Allergy.values.reversed),
        '3-${sorted.join('-')}',
      );
    });

    test('the nutritionist writes only review fields of an adjustment', () {
      final review = body('nutritionistReviewsAdjustment');
      final fields = lists(review, r'affectedKeys\(\)\.hasOnly');

      expect(
        fields[0],
        unorderedEquals(['status', 'reviewedBy', 'reviewedAt']),
      );
      expect(
        fields[1],
        unorderedEquals([
          'status',
          'rejectionReason',
          'reviewedBy',
          'reviewedAt',
        ]),
      );
    });
  });
}
