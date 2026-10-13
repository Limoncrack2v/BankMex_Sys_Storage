import 'package:bank_storage_app/application/bank_storage_facade.dart';
import 'package:bank_storage_app/data/models/family.dart';
import 'package:bank_storage_app/data/repositories/family_repository.dart';
import 'package:bank_storage_app/data/repositories/meal_plan_repository.dart';
import 'package:bank_storage_app/data/repositories/member_repository.dart';
import 'package:bank_storage_app/data/repositories/pantry_repository.dart';
import 'package:bank_storage_app/data/repositories/recipe_repository.dart';
import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:bank_storage_app/domain/recipe_catalog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// RecipeRepository de mentira: guarda lo que le piden crear o actualizar.
class _FakeRecipes extends Fake implements RecipeRepository {
  final saved = <Recipe>[];

  @override
  Future<Recipe> create(Recipe recipe) async {
    saved.add(recipe);
    return recipe;
  }

  @override
  Future<Recipe> update(Recipe recipe) async {
    saved.add(recipe);
    return recipe;
  }
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

  group('editar una receta con ids que esta versión no conoce', () {
    final stored = Recipe.fromMap('r1', {
      'name': 'Guardada',
      'status': 'approved',
      'nutritionalTags': ['bajoEnSodio', 'sinGluten'],
      'requiredEquipment': ['estufa', 'freidoraDeAire'],
    });

    test('los validadores aceptan los ids que ya estaban guardados', () {
      expect(Recipe.validateNutritionalTags(const ['sinGluten']), isNotNull);
      expect(
        Recipe.validateNutritionalTags(
          const ['sinGluten'],
          keep: const {'sinGluten'},
        ),
        isNull,
      );
      expect(
        Recipe.validateNutritionalTags(
          const ['sinGluten', 'sinGluten'],
          keep: const {'sinGluten'},
        ),
        isNotNull,
      );
      expect(
        Recipe.validateRequiredEquipment(const ['freidoraDeAire']),
        isNotNull,
      );
      expect(
        Recipe.validateRequiredEquipment(
          const ['freidoraDeAire'],
          keep: const {'freidoraDeAire'},
        ),
        isNull,
      );
    });

    test(
      'guardar conserva los ids desconocidos de la receta guardada',
      () async {
        final recipes = _FakeRecipes();

        await _facade(recipes)
            .updateRecipe(stored.copyWith(name: 'Editada'), previous: stored);

        expect(recipes.saved.single.name, 'Editada');
        expect(recipes.saved.single.nutritionalTags, [
          'bajoEnSodio',
          'sinGluten',
        ]);
        expect(recipes.saved.single.requiredEquipment, [
          'estufa',
          'freidoraDeAire',
        ]);
      },
    );

    test('un id desconocido nuevo llega como Future fallido, sin lanzar al '
        'llamar', () async {
      final recipes = _FakeRecipes();
      final edited = stored.copyWith(
        nutritionalTags: const ['bajoEnSodio', 'picante'],
      );

      late Future<Recipe> save;
      expect(
        () => save = _facade(recipes).updateRecipe(edited, previous: stored),
        returnsNormally,
      );
      await expectLater(save, throwsArgumentError);
      expect(recipes.saved, isEmpty);
    });

    test('publicar o dejar pendiente con un id desconocido también llega '
        'como Future fallido', () async {
      final recipes = _FakeRecipes();
      final facade = _facade(recipes);
      final creates = <Future<Recipe> Function()>[
        () => facade.publishRecipe(
          name: 'Nueva',
          ingredients: _ingredients,
          steps: const ['Cocer'],
          prepTimeMinutes: 30,
          caloriesPerServing: 150,
          nutritionalTags: const ['picante'],
        ),
        () => facade.submitRecipe(
          name: 'Nueva',
          ingredients: _ingredients,
          steps: const ['Cocer'],
          prepTimeMinutes: 30,
          caloriesPerServing: 150,
          nutritionalTags: const ['picante'],
        ),
      ];

      for (final create in creates) {
        late Future<Recipe> save;
        expect(() => save = create(), returnsNormally);
        await expectLater(save, throwsArgumentError);
      }
      expect(recipes.saved, isEmpty);
    });

    test('los ids desconocidos repetidos se conservan una sola vez', () {
      final recipe = Recipe.fromMap('r2', {
        'name': 'Repetida',
        'nutritionalTags': ['sinGluten', 'bajoEnSodio', 'sinGluten'],
        'requiredEquipment': ['freidoraDeAire', 'estufa', 'freidoraDeAire'],
      });

      expect(recipe.unknownNutritionalTags, ['sinGluten']);
      expect(recipe.unknownEquipment, ['freidoraDeAire']);
      expect(
        Recipe.validateNutritionalTags([
          'bajoEnSodio',
          ...recipe.unknownNutritionalTags,
        ], keep: recipe.nutritionalTags.toSet()),
        isNull,
      );
    });
  });
}
