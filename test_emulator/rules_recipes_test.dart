// Pruebas de firestore.rules (colección recipes) contra el emulador de
// Firestore (127.0.0.1:8080): quién crea, edita, aprueba y rechaza recetas.
// Los campos de una receta se prueban en rules_recipe_validation_test.dart.
//
// Uso: flutter test test_emulator/rules_recipes_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'support/emulator.dart';

Map<String, Object?> now() => ts(DateTime.utc(2026, 9, 21, 12));

/// Perfil de users/{uid}.
Map<String, Map<String, Object?>> profile(String role) => {
  'name': str('Nombre'),
  'email': str('x@y.com'),
  'role': str(role),
  'createdAt': now(),
};

/// Una receta completa y válida (Recipe.toMap) en el estado dado. [extra]
/// agrega los campos que escribe el nutriólogo.
Map<String, Map<String, Object?>> recipe(
  String status, {
  Map<String, Map<String, Object?>> extra = const {},
}) => {
  'name': str('Arroz con frijoles'),
  'ingredients': arr([
    mapValue({
      'productName': str('Arroz'),
      'quantity': number(0.25),
      'unit': str('kg'),
    }),
  ]),
  'steps': arr([str('Cocer el arroz.')]),
  'prepTimeMinutes': integer(30),
  'caloriesPerServing': integer(250),
  'status': str(status),
  'dietaryTags': arr([]),
  'nutritionalTags': arr([]),
  'requiredEquipment': arr([]),
  'image': str(''),
  'servings': integer(4),
  ...extra,
};

Map<String, Map<String, Object?>> approvedRecipe() => recipe(
  'approved',
  extra: {'approvedBy': str('nutri1'), 'approvedAt': now()},
);

Map<String, Map<String, Object?>> rejectedDraft() => recipe(
  'draft',
  extra: {
    'reviewNote': str('Falta la cantidad de sal'),
    'rejectedBy': str('nutri1'),
    'rejectedAt': now(),
  },
);

Future<void> seedFixtures() async {
  final admin = Db.admin();
  await admin.setDoc('users/staff1', profile('staff'));
  await admin.setDoc('users/fam1', profile('family'));
  await admin.setDoc('users/nutri1', profile('nutritionist'));
  await admin.setDoc('users/nutri2', profile('nutritionist'));
}

// Aprobar o rechazar pide una sesión de menos de 5 minutos (recentlySignedIn
// en firestore.rules).
Db staleNutri() => Db.user('nutri1', signedInAgo: const Duration(minutes: 6));
Db nutri() => Db.user('nutri1', signedInAgo: const Duration(minutes: 4));
Db staff() => Db.user('staff1', signedInAgo: const Duration(minutes: 6));
Db fam1() => Db.user('fam1');

Map<String, Object?> approve({String by = 'nutri1'}) => {
  'status': str('approved'),
  'approvedBy': str(by),
  'approvedAt': serverTimestamp,
};

Map<String, Object?> reject({String note = 'Falta sal'}) => {
  'status': str('draft'),
  'reviewNote': str(note),
  'rejectedBy': str('nutri1'),
  'rejectedAt': serverTimestamp,
};

void main() {
  useProject('demo-bamx-recipes');

  setUpAll(requireEmulator);
  setUp(() async {
    await clearFirestore();
    await seedFixtures();
  });

  group('staff: crear', () {
    test(
      'crea un borrador o una pendiente, también con sesión vieja',
      () async {
        await assertAllowed(staff().setDoc('recipes/r1', recipe('draft')));
        await assertAllowed(staff().setDoc('recipes/r2', recipe('pending')));
      },
    );

    test('no crea una receta aprobada', () async {
      await assertDenied(staff().setDoc('recipes/r1', approvedRecipe()));
      await assertDenied(staff().setDoc('recipes/r1', recipe('approved')));
    });

    test('no crea con campos de revisión', () async {
      await assertDenied(
        staff().setDoc(
          'recipes/r1',
          recipe(
            'pending',
            extra: {'approvedBy': str('nutri1'), 'approvedAt': now()},
          ),
        ),
      );
      await assertDenied(
        staff().setDoc(
          'recipes/r1',
          recipe(
            'draft',
            extra: {
              'reviewNote': str('x'),
              'rejectedBy': str('nutri1'),
              'rejectedAt': now(),
            },
          ),
        ),
      );
    });
  });

  group('staff: editar', () {
    test('mueve entre borrador y pendiente', () async {
      await Db.admin().setDoc('recipes/r1', recipe('draft'));
      await assertAllowed(
        staff().updateDoc('recipes/r1', {'status': str('pending')}),
      );
      await assertAllowed(
        staff().updateDoc('recipes/r1', {'status': str('draft')}),
      );
    });

    test('edita el contenido de un borrador y de una pendiente', () async {
      await Db.admin().setDoc('recipes/r1', recipe('draft'));
      await Db.admin().setDoc('recipes/r2', recipe('pending'));
      await assertAllowed(
        staff().updateDoc('recipes/r1', {'name': str('Otro nombre')}),
      );
      await assertAllowed(
        staff().updateDoc('recipes/r2', {'servings': integer(6)}),
      );
    });

    test('no publica una pendiente ni un borrador', () async {
      await Db.admin().setDoc('recipes/r1', recipe('pending'));
      await Db.admin().setDoc('recipes/r2', recipe('draft'));
      await assertDenied(
        staff().updateDoc('recipes/r1', {'status': str('approved')}),
      );
      await assertDenied(
        staff().updateDoc('recipes/r2', {'status': str('approved')}),
      );
      await assertDenied(
        staff().updateDoc('recipes/r1', {
          'status': str('approved'),
          'approvedBy': str('staff1'),
          'approvedAt': serverTimestamp,
        }),
      );
    });

    test('no cambia el contenido de una aprobada dejándola aprobada', () async {
      await Db.admin().setDoc('recipes/r1', approvedRecipe());
      await assertDenied(
        staff().updateDoc('recipes/r1', {'name': str('Otro nombre')}),
      );
      await assertDenied(
        staff().updateDoc('recipes/r1', {'servings': integer(8)}),
      );
    });

    test('saca una aprobada a borrador o a pendiente', () async {
      await Db.admin().setDoc('recipes/r1', approvedRecipe());
      await Db.admin().setDoc('recipes/r2', approvedRecipe());
      await assertAllowed(
        staff().updateDoc('recipes/r1', {
          'status': str('draft'),
          'approvedBy': deleteField,
          'approvedAt': deleteField,
        }),
      );
      await assertAllowed(
        staff().updateDoc('recipes/r2', {
          'status': str('pending'),
          'name': str('Con cambios'),
          'approvedBy': deleteField,
          'approvedAt': deleteField,
        }),
      );
    });

    test('al sacar una aprobada no queda quién la aprobó', () async {
      await Db.admin().setDoc('recipes/r1', approvedRecipe());
      await assertDenied(
        staff().updateDoc('recipes/r1', {'status': str('pending')}),
      );
    });

    test('no escribe campos de revisión', () async {
      await Db.admin().setDoc('recipes/r1', recipe('draft'));
      await assertDenied(
        staff().updateDoc('recipes/r1', {
          'reviewNote': str('Inventado'),
          'rejectedBy': str('nutri1'),
          'rejectedAt': now(),
        }),
      );
    });

    test(
      'un borrador rechazado conserva el motivo mientras es borrador',
      () async {
        await Db.admin().setDoc('recipes/r1', rejectedDraft());
        await assertAllowed(
          staff().updateDoc('recipes/r1', {'name': str('Corregida')}),
        );
        await assertDenied(
          staff().updateDoc('recipes/r1', {'reviewNote': str('Otro motivo')}),
        );
      },
    );

    test('al reenviar a revisión se borra el motivo del rechazo', () async {
      await Db.admin().setDoc('recipes/r1', rejectedDraft());
      await assertDenied(
        staff().updateDoc('recipes/r1', {'status': str('pending')}),
      );
      await assertAllowed(
        staff().updateDoc('recipes/r1', {
          'status': str('pending'),
          'reviewNote': deleteField,
          'rejectedBy': deleteField,
          'rejectedAt': deleteField,
        }),
      );
    });

    test('borra una receta en cualquier estado', () async {
      await Db.admin().setDoc('recipes/r1', approvedRecipe());
      await Db.admin().setDoc('recipes/r2', recipe('pending'));
      await assertAllowed(staff().deleteDoc('recipes/r1'));
      await assertAllowed(staff().deleteDoc('recipes/r2'));
    });
  });

  group('nutriólogo: aprobar', () {
    test('aprueba una pendiente con sesión reciente', () async {
      await Db.admin().setDoc('recipes/r1', recipe('pending'));
      await assertAllowed(nutri().updateDoc('recipes/r1', approve()));
      final stored = await adminDoc('recipes/r1');
      expect(fieldValue(stored, 'status'), 'approved');
      expect(fieldValue(stored, 'approvedBy'), 'nutri1');
    });

    test('no aprueba con sesión vieja', () async {
      await Db.admin().setDoc('recipes/r1', recipe('pending'));
      await assertDenied(staleNutri().updateDoc('recipes/r1', approve()));
    });

    test('aprueba a su nombre y a la hora del servidor', () async {
      await Db.admin().setDoc('recipes/r1', recipe('pending'));
      await assertDenied(
        nutri().updateDoc('recipes/r1', approve(by: 'nutri2')),
      );
      await assertDenied(
        nutri().updateDoc('recipes/r1', {
          'status': str('approved'),
          'approvedBy': str('nutri1'),
          'approvedAt': ts(DateTime.utc(2020)),
        }),
      );
      await assertDenied(
        nutri().updateDoc('recipes/r1', {'status': str('approved')}),
      );
    });

    test('no cambia el contenido al aprobar', () async {
      await Db.admin().setDoc('recipes/r1', recipe('pending'));
      await assertDenied(
        nutri().updateDoc('recipes/r1', {
          ...approve(),
          'name': str('Otro nombre'),
        }),
      );
      await assertDenied(
        nutri().updateDoc('recipes/r1', {'servings': integer(8)}),
      );
    });

    test('solo aprueba una pendiente', () async {
      await Db.admin().setDoc('recipes/r1', recipe('draft'));
      await Db.admin().setDoc('recipes/r2', approvedRecipe());
      await assertDenied(nutri().updateDoc('recipes/r1', approve()));
      await assertDenied(nutri().updateDoc('recipes/r2', approve()));
    });
  });

  group('nutriólogo: rechazar', () {
    test('rechaza una pendiente con motivo y sesión reciente', () async {
      await Db.admin().setDoc('recipes/r1', recipe('pending'));
      await assertAllowed(nutri().updateDoc('recipes/r1', reject()));
      final stored = await adminDoc('recipes/r1');
      expect(fieldValue(stored, 'status'), 'draft');
      expect(fieldValue(stored, 'reviewNote'), 'Falta sal');
      expect(fieldValue(stored, 'rejectedBy'), 'nutri1');
    });

    test('no rechaza sin motivo', () async {
      await Db.admin().setDoc('recipes/r1', recipe('pending'));
      await assertDenied(nutri().updateDoc('recipes/r1', reject(note: '')));
      await assertDenied(nutri().updateDoc('recipes/r1', reject(note: '   ')));
      await assertDenied(
        nutri().updateDoc('recipes/r1', {
          'status': str('draft'),
          'rejectedBy': str('nutri1'),
          'rejectedAt': serverTimestamp,
        }),
      );
      await assertDenied(
        nutri().updateDoc('recipes/r1', reject(note: 'a' * 301)),
      );
    });

    test('no rechaza con sesión vieja', () async {
      await Db.admin().setDoc('recipes/r1', recipe('pending'));
      await assertDenied(staleNutri().updateDoc('recipes/r1', reject()));
    });

    test('no cambia el contenido al rechazar', () async {
      await Db.admin().setDoc('recipes/r1', recipe('pending'));
      await assertDenied(
        nutri().updateDoc('recipes/r1', {
          ...reject(),
          'name': str('Otro nombre'),
        }),
      );
    });

    test('no regresa a pendiente ni saca una aprobada', () async {
      await Db.admin().setDoc('recipes/r1', approvedRecipe());
      await Db.admin().setDoc('recipes/r2', recipe('draft'));
      await assertDenied(nutri().updateDoc('recipes/r1', reject()));
      await assertDenied(nutri().updateDoc('recipes/r2', reject()));
      await assertDenied(
        nutri().updateDoc('recipes/r1', {'status': str('pending')}),
      );
    });
  });

  group('nutriólogo: no escribe más', () {
    test('no crea, edita contenido ni borra', () async {
      await Db.admin().setDoc('recipes/r1', recipe('pending'));
      await assertDenied(nutri().setDoc('recipes/r2', recipe('pending')));
      await assertDenied(nutri().setDoc('recipes/r3', recipe('approved')));
      await assertDenied(
        nutri().updateDoc('recipes/r1', {'name': str('Otro nombre')}),
      );
      await assertDenied(nutri().deleteDoc('recipes/r1'));
    });
  });

  group('lectura y familia', () {
    test('la familia lee solo las aprobadas', () async {
      await Db.admin().setDoc('recipes/r1', approvedRecipe());
      await Db.admin().setDoc('recipes/r2', recipe('pending'));
      await Db.admin().setDoc('recipes/r3', recipe('draft'));
      await assertAllowed(fam1().getDoc('recipes/r1'));
      await assertDenied(fam1().getDoc('recipes/r2'));
      await assertDenied(fam1().getDoc('recipes/r3'));
    });

    test('la familia no escribe recetas', () async {
      await Db.admin().setDoc('recipes/r1', recipe('pending'));
      await assertDenied(fam1().setDoc('recipes/r2', recipe('pending')));
      await assertDenied(fam1().updateDoc('recipes/r1', approve(by: 'fam1')));
      await assertDenied(fam1().deleteDoc('recipes/r1'));
    });

    test(
      'el nutriólogo lee las pendientes y las aprobadas, no los borradores',
      () async {
        await Db.admin().setDoc('recipes/r1', recipe('pending'));
        await Db.admin().setDoc('recipes/r2', recipe('draft'));
        await Db.admin().setDoc('recipes/r3', approvedRecipe());
        await assertAllowed(nutri().getDoc('recipes/r1'));
        await assertDenied(nutri().getDoc('recipes/r2'));
        await assertAllowed(nutri().getDoc('recipes/r3'));
      },
    );
  });
}
