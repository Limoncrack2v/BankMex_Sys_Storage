import 'package:bank_storage_app/data/models/family.dart';
import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:bank_storage_app/domain/recipe_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

const _ingredients = [
  RecipeIngredient(productName: 'Frijol', quantity: 0.5, unit: 'kg'),
];

Recipe _publish({
  List<String> nutritionalTags = const [],
  List<String> requiredEquipment = const [],
}) => RecipeCatalog.publishRecipe(
  name: 'Frijoles de la olla',
  ingredients: _ingredients,
  steps: const ['Cocer'],
  prepTimeMinutes: 90,
  caloriesPerServing: 200,
  nutritionalTags: nutritionalTags,
  requiredEquipment: requiredEquipment,
);

void main() {
  group('NutritionalTag', () {
    test('fromId reconoce cada id y rechaza los desconocidos', () {
      for (final tag in NutritionalTag.values) {
        expect(NutritionalTag.fromId(tag.id), tag);
      }
      expect(NutritionalTag.fromId('Bajo en sodio'), isNull);
    });
  });

  group('Recipe', () {
    test('sin los campos en Firestore quedan vacíos', () {
      final recipe = Recipe.fromMap('r1', {'name': 'Vieja'});
      expect(recipe.nutritionalTags, isEmpty);
      expect(recipe.requiredEquipment, isEmpty);
    });

    test('toMap y fromMap conservan etiquetas y electrodomésticos', () {
      final recipe = _publish(
        nutritionalTags: [
          NutritionalTag.highFiber.id,
          NutritionalTag.lowFat.id,
        ],
        requiredEquipment: [Appliance.stove.id, Appliance.blender.id],
      );
      final map = recipe.toMap();
      expect(map['nutritionalTags'], ['altoEnFibra', 'bajoEnGrasa']);
      expect(map['requiredEquipment'], ['estufa', 'licuadora']);

      final copy = Recipe.fromMap('r1', map);
      expect(copy.nutritionalTags, recipe.nutritionalTags);
      expect(copy.requiredEquipment, recipe.requiredEquipment);
    });

    test('copyWith cambia solo lo que se pasa', () {
      final recipe = _publish(requiredEquipment: [Appliance.stove.id]);
      final edited = recipe.copyWith(
        nutritionalTags: [NutritionalTag.vegetarian.id],
      );
      expect(edited.nutritionalTags, ['vegetariano']);
      expect(edited.requiredEquipment, ['estufa']);
    });

    test('validaciones', () {
      expect(Recipe.validateNutritionalTags(const []), isNull);
      expect(Recipe.validateNutritionalTags(const ['bajoEnSodio']), isNull);
      expect(Recipe.validateNutritionalTags(const ['picante']), isNotNull);
      expect(
        Recipe.validateNutritionalTags(const ['bajoEnSodio', 'bajoEnSodio']),
        isNotNull,
      );
      expect(Recipe.validateRequiredEquipment(const []), isNull);
      expect(Recipe.validateRequiredEquipment(const ['ollaPresion']), isNull);
      expect(Recipe.validateRequiredEquipment(const ['Estufa']), isNotNull);
      expect(
        Recipe.validateRequiredEquipment(const ['horno', 'horno']),
        isNotNull,
      );
    });
  });

  group('RecipeCatalog', () {
    test('publica sin electrodomésticos', () {
      final recipe = _publish();
      expect(recipe.requiredEquipment, isEmpty);
      expect(recipe.status, RecipeStatus.approved);
    });

    test('rechaza etiquetas o electrodomésticos desconocidos', () {
      expect(
        () => _publish(nutritionalTags: const ['picante']),
        throwsArgumentError,
      );
      expect(
        () => _publish(requiredEquipment: const ['Estufa']),
        throwsArgumentError,
      );
    });
  });
}
