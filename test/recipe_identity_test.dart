import 'dart:io';

import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/domain/catalog_mappers.dart';
import 'package:bank_storage_app/domain/models/appliance.dart';
import 'package:bank_storage_app/domain/models/recipe.dart' as domain;
import 'package:bank_storage_app/ui/models/recipe.dart';
import 'package:bank_storage_app/ui/sample_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Una receta aprobada tal como llega de recipes/{id}.
const stored = domain.Recipe(
  id: 'rec_tortitas',
  name: 'Tortitas de avena',
  ingredients: [
    domain.RecipeIngredient(productName: 'Avena', quantity: 0.2, unit: 'kg'),
    domain.RecipeIngredient(productName: 'Plátano', quantity: 2, unit: 'piece'),
  ],
  steps: ['Licúa todo y cocina las tortitas en un sartén.'],
  prepTimeMinutes: 20,
  caloriesPerServing: 150,
  status: domain.RecipeStatus.approved,
  requiredEquipment: ['estufa', 'licuadora'],
  servings: 4,
);

Member adult(String name) => Member(
  memberId: name,
  name: name,
  memberType: MemberType.adult,
  createdAt: DateTime(2026, 9, 1),
);

/// Las recetas de tool/catalog_recipes.mjs por nombre, con su id y su
/// `equipment` (vacío si no lo trae).
///
/// SampleData no puede importar el seed (es JavaScript), así que se lee el
/// archivo: si alguien cambia uno sin el otro, estas pruebas fallan.
Map<String, ({String id, List<String> equipment})> readSeedCatalog() {
  final seed = File('tool/catalog_recipes.mjs').readAsStringSync();
  final quoted = RegExp(r"'([^']*)'");
  final recipes = <String, ({String id, List<String> equipment})>{};
  // Cada receta es ['rec_x', recipeFields({name: '...', ...})].
  final entries = RegExp(
    r"'(rec_\w+)',\s*recipeFields\(\{(.*?)\}\)",
    dotAll: true,
  ).allMatches(seed);
  for (final entry in entries) {
    final fields = entry.group(2)!;
    final name = RegExp(r"name: '([^']*)'").firstMatch(fields)!.group(1)!;
    final equipment = RegExp(r'equipment: \[([^\]]*)\]').firstMatch(fields);
    recipes[name] = (
      id: entry.group(1)!,
      equipment: [
        for (final item in quoted.allMatches(equipment?.group(1) ?? ''))
          item.group(1)!,
      ],
    );
  }
  return recipes;
}

void main() {
  group('a catalog recipe keeps its id and equipment', () {
    test('through recipeToUi', () {
      final recipe = CatalogMappers.recipeToUi(stored);

      expect(recipe.id, 'rec_tortitas');
      expect(recipe.requiredEquipment, ['estufa', 'licuadora']);
    });

    test('through scaledRecipe', () {
      final recipe = CatalogMappers.recipeToUi(stored);
      final scaled = scaledRecipe(recipe, 2);

      // Con otras porciones se arma una receta nueva, campo por campo.
      expect(scaled, isNot(same(recipe)));
      expect(scaled.servings, 2);
      expect(scaled.id, 'rec_tortitas');
      expect(scaled.requiredEquipment, ['estufa', 'licuadora']);
    });

    test('through scaledForHousehold', () {
      final recipe = CatalogMappers.recipeToUi(stored);
      final scaled = scaledForHousehold(recipe, [adult('Ana'), adult('Luis')]);

      expect(scaled, isNot(same(recipe)));
      expect(scaled.id, 'rec_tortitas');
      expect(scaled.requiredEquipment, ['estufa', 'licuadora']);
    });
  });

  test('a recipe built without id or equipment has empty ones', () {
    const recipe = Recipe(
      name: 'Prueba',
      image: '',
      minutes: 10,
      servings: 2,
      kcalPerServing: 100,
      ingredients: [],
      steps: ['Paso 1.'],
    );

    expect(recipe.id, isEmpty);
    expect(recipe.requiredEquipment, isEmpty);
    expect(scaledRecipe(recipe, 4).id, isEmpty);
  });

  group('SampleData', () {
    test('ids are unique and not empty', () {
      final ids = [for (final recipe in SampleData.recipes) recipe.id];

      expect(ids, everyElement(isNotEmpty));
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('equipment uses known appliance ids', () {
      for (final recipe in SampleData.recipes) {
        expect(
          Appliance.validateIds(recipe.requiredEquipment),
          isNull,
          reason: recipe.name,
        );
      }
    });

    test('ids and equipment match tool/catalog_recipes.mjs', () {
      final seed = readSeedCatalog();

      for (final recipe in SampleData.recipes) {
        expect(seed.keys, contains(recipe.name));
        expect(recipe.id, seed[recipe.name]!.id, reason: recipe.name);
        expect(
          recipe.requiredEquipment,
          seed[recipe.name]!.equipment,
          reason: recipe.name,
        );
      }
    });
  });
}
