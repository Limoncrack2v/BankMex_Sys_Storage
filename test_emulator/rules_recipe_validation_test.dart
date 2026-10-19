// Pruebas de validRecipe en firestore.rules (colección recipes) contra el
// emulador de Firestore (127.0.0.1:8080).
//
// Uso: flutter test test_emulator/rules_recipe_validation_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'support/emulator.dart';

Map<String, Object?> now() => ts(DateTime.utc(2026, 10, 14, 12));

Map<String, Object?> ingredient({
  String name = 'Arroz',
  num quantity = 0.25,
  String unit = 'kg',
}) => mapValue({
  'productName': str(name),
  'quantity': number(quantity),
  'unit': str(unit),
});

/// Una receta válida; cada prueba cambia el campo que quiere romper.
Map<String, Map<String, Object?>> recipe({
  Map<String, Map<String, Object?>> change = const {},
  List<String> remove = const [],
}) {
  final fields = <String, Map<String, Object?>>{
    'name': str('Arroz con frijoles'),
    'ingredients': arr([ingredient()]),
    'steps': arr([str('Cocer el arroz.')]),
    'prepTimeMinutes': integer(30),
    'caloriesPerServing': integer(250),
    'status': str('pending'),
    'dietaryTags': arr([]),
    'nutritionalTags': arr([]),
    'requiredEquipment': arr([]),
    'image': str(''),
    'servings': integer(4),
    ...change,
  };
  for (final key in remove) {
    fields.remove(key);
  }
  return fields;
}

Db staff() => Db.user('staff1');

void main() {
  useProject('demo-bamx-recipe-validation');

  setUpAll(requireEmulator);
  setUp(() async {
    await clearFirestore();
    await Db.admin().setDoc('users/staff1', {
      'name': str('Staff'),
      'email': str('s@y.com'),
      'role': str('staff'),
      'createdAt': now(),
    });
  });

  Future<void> denied(Map<String, Map<String, Object?>> fields) =>
      assertDenied(staff().setDoc('recipes/r1', fields));

  group('recipes: campos', () {
    test('una receta completa se guarda', () async {
      await assertAllowed(staff().setDoc('recipes/r1', recipe()));
    });

    test('falta un campo', () async {
      for (final key in recipe().keys) {
        await denied(recipe(remove: [key]));
      }
    });

    test('un campo de más', () async {
      await denied(recipe(change: {'color': str('rojo')}));
    });

    test('nombre vacío o de más de 100 caracteres', () async {
      await denied(recipe(change: {'name': str('')}));
      await denied(recipe(change: {'name': str('a' * 101)}));
      await assertAllowed(
        staff().setDoc('recipes/r2', recipe(change: {'name': str('a' * 100)})),
      );
    });

    test('estado desconocido', () async {
      await denied(recipe(change: {'status': str('archived')}));
    });

    test('números fuera de rango o de otro tipo', () async {
      await denied(recipe(change: {'prepTimeMinutes': integer(0)}));
      await denied(recipe(change: {'prepTimeMinutes': integer(10000)}));
      await denied(recipe(change: {'prepTimeMinutes': str('30')}));
      await denied(recipe(change: {'caloriesPerServing': integer(-1)}));
      await denied(recipe(change: {'caloriesPerServing': integer(5001)}));
      await denied(recipe(change: {'servings': integer(0)}));
      await denied(recipe(change: {'servings': integer(100)}));
      await denied(recipe(change: {'servings': number(2.5)}));
    });

    test('imagen demasiado larga', () async {
      await denied(recipe(change: {'image': str('a' * 301)}));
    });
  });

  group('recipes: ingredientes y pasos', () {
    test('sin ingredientes o sin pasos', () async {
      await denied(recipe(change: {'ingredients': arr([])}));
      await denied(recipe(change: {'steps': arr([])}));
    });

    test('un ingrediente inválido en cualquier posición', () async {
      for (final bad in [
        ingredient(unit: 'cucharada'),
        ingredient(quantity: 0),
        ingredient(name: ''),
        str('Arroz'),
      ]) {
        await denied(
          recipe(
            change: {
              'ingredients': arr([ingredient(), bad]),
            },
          ),
        );
      }
    });

    test('el máximo de ingredientes cabe y uno más no', () async {
      await assertAllowed(
        staff().setDoc(
          'recipes/r1',
          recipe(
            change: {
              'ingredients': arr([for (var i = 0; i < 10; i++) ingredient()]),
            },
          ),
        ),
      );
      await denied(
        recipe(
          change: {
            'ingredients': arr([for (var i = 0; i < 11; i++) ingredient()]),
          },
        ),
      );
    });

    test('un paso vacío, largo o que no es texto', () async {
      await denied(
        recipe(
          change: {
            'steps': arr([str('Uno'), str('')]),
          },
        ),
      );
      await denied(
        recipe(
          change: {
            'steps': arr([str('Uno'), str('a' * 301)]),
          },
        ),
      );
      await denied(
        recipe(
          change: {
            'steps': arr([integer(1)]),
          },
        ),
      );
    });

    test('el máximo de pasos cabe y uno más no', () async {
      await assertAllowed(
        staff().setDoc(
          'recipes/r1',
          recipe(
            change: {
              'steps': arr([for (var i = 0; i < 12; i++) str('Paso $i')]),
            },
          ),
        ),
      );
      await denied(
        recipe(
          change: {
            'steps': arr([for (var i = 0; i < 13; i++) str('Paso $i')]),
          },
        ),
      );
    });

    // Lo más grande que acepta validRecipe, con todas las etiquetas. Al crear
    // y al editar (suma resource.data).
    final biggest = recipe(
      change: {
        'ingredients': arr([for (var i = 0; i < 10; i++) ingredient()]),
        'steps': arr([for (var i = 0; i < 12; i++) str('a' * 300)]),
        'dietaryTags': arr([for (var i = 0; i < 10; i++) str('etiqueta')]),
        'nutritionalTags': arr([
          for (final id in [
            'bajoEnSodio',
            'bajoEnAzucar',
            'bajoEnGrasa',
            'altoEnFibra',
            'altoEnProteina',
            'vegetariano',
            'aptoDiabeticos',
          ])
            str(id),
        ]),
        'requiredEquipment': arr([
          for (final id in [
            'estufa',
            'refrigerador',
            'horno',
            'microondas',
            'licuadora',
            'ollaPresion',
          ])
            str(id),
        ]),
      },
    );

    test('el máximo de todo junto cabe al crear', () async {
      await assertAllowed(staff().setDoc('recipes/r1', biggest));
    });

    test('el máximo de todo junto cabe al editar', () async {
      await Db.admin().setDoc('recipes/r1', biggest);
      await assertAllowed(staff().setDoc('recipes/r1', biggest));
    });
  });

  group('recipes: etiquetas y electrodomésticos', () {
    test('ids conocidos', () async {
      await assertAllowed(
        staff().setDoc(
          'recipes/r1',
          recipe(
            change: {
              'nutritionalTags': arr([
                str('bajoEnSodio'),
                str('aptoDiabeticos'),
              ]),
              'requiredEquipment': arr([str('estufa'), str('ollaPresion')]),
            },
          ),
        ),
      );
    });

    test('un id desconocido o repetido', () async {
      await denied(
        recipe(
          change: {
            'nutritionalTags': arr([str('keto')]),
          },
        ),
      );
      await denied(
        recipe(
          change: {
            'nutritionalTags': arr([str('vegetariano'), str('vegetariano')]),
          },
        ),
      );
      await denied(
        recipe(
          change: {
            'requiredEquipment': arr([str('freidora')]),
          },
        ),
      );
      await denied(
        recipe(
          change: {
            'requiredEquipment': arr([str('horno'), str('horno')]),
          },
        ),
      );
    });

    test('al editar se conserva un id que la receta ya tenía', () async {
      await Db.admin().setDoc(
        'recipes/r1',
        recipe(
          change: {
            'nutritionalTags': arr([str('keto')]),
          },
        ),
      );
      await assertAllowed(
        staff().setDoc(
          'recipes/r1',
          recipe(
            change: {
              'nutritionalTags': arr([str('keto'), str('vegetariano')]),
              'name': str('Otro nombre'),
            },
          ),
        ),
      );
      // Pero no se agrega uno nuevo desconocido.
      await assertDenied(
        staff().setDoc(
          'recipes/r1',
          recipe(
            change: {
              'nutritionalTags': arr([str('keto'), str('paleo')]),
            },
          ),
        ),
      );
    });

    test('más de 10 etiquetas libres', () async {
      await denied(
        recipe(
          change: {
            'dietaryTags': arr([for (var i = 0; i < 11; i++) str('a')]),
          },
        ),
      );
    });
  });

  group('recipes: actualizaciones', () {
    test('una edición que deja un campo inválido se rechaza', () async {
      await Db.admin().setDoc('recipes/r1', recipe());
      await assertDenied(
        staff().updateDoc('recipes/r1', {'servings': integer(0)}),
      );
      await assertAllowed(
        staff().updateDoc('recipes/r1', {'servings': integer(6)}),
      );
    });
  });
}
