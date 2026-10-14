// Pruebas de firestore.rules para adjustments/{id} (las adaptaciones de recetas
// para un hogar) contra el emulador de Firestore (127.0.0.1:8080).
//
// Uso: flutter test test_emulator/rules_adjustments_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'support/emulator.dart';

Map<String, Object?> now() => ts(DateTime.utc(2026, 10, 14, 12));

Map<String, Map<String, Object?>> profile(String role) => {
  'name': str('Nombre'),
  'email': str('x@y.com'),
  'role': str(role),
  'createdAt': now(),
};

Map<String, Map<String, Object?>> family(String authUid) => {
  'address': str('Calle 1'),
  'registrationDate': now(),
  'authUid': str(authUid),
  'appliances': arr([]),
};

Map<String, Map<String, Object?>> recipe(String status) => {
  'name': str('Arroz con leche'),
  'ingredients': arr([ingredient()]),
  'steps': arr([str('Cocer')]),
  'prepTimeMinutes': integer(30),
  'caloriesPerServing': integer(200),
  'status': str(status),
  'dietaryTags': arr([]),
  'nutritionalTags': arr([]),
  'requiredEquipment': arr([]),
  'image': str(''),
  'servings': integer(4),
};

Map<String, Object?> ingredient({
  String name = 'Bebida de avena',
  num quantity = 1,
  String unit = 'l',
}) => mapValue({
  'productName': str(name),
  'quantity': number(quantity),
  'unit': str(unit),
});

Map<String, Object?> change({
  String kind = 'substitution',
  String reason = 'alergia a lácteos',
}) => mapValue({
  'kind': str(kind),
  'reason': str(reason),
  'from': str('Leche entera'),
  'to': str('Bebida de avena'),
});

/// Una adaptación pendiente como la crea la familia. Sin createdAt: se agrega
/// con la hora del servidor al escribirla (ver [create]).
Map<String, Map<String, Object?>> adjustment({
  Map<String, Map<String, Object?>> change_ = const {},
  List<String> remove = const [],
}) {
  final fields = <String, Map<String, Object?>>{
    'familyId': ref('families/famA'),
    'recipeId': str('r1'),
    'baseSignature': str('abcdef12'),
    'householdSize': integer(4),
    'servings': integer(4),
    'ingredients': arr([ingredient()]),
    'changes': arr([change()]),
    'summary': str('Se sustituye leche entera por bebida de avena'),
    'status': str('pending'),
    ...change_,
  };
  for (final key in remove) {
    fields.remove(key);
  }
  return fields;
}

/// Lo que ya hay en la colección (lo escribe el administrador).
Map<String, Map<String, Object?>> stored({
  String status = 'pending',
  String familyId = 'famA',
}) => {
  ...adjustment(change_: {'familyId': ref('families/$familyId')}),
  'status': str(status),
  'createdAt': now(),
};

/// El id que exigen las reglas y que usa la app: familia, receta, huella de
/// la receta y tamaño del hogar (RecipeAdjustment.documentId).
String idOf(Map<String, Map<String, Object?>> fields) {
  final family = (fields['familyId']?['referenceValue'] as String?)
      ?.split('/')
      .last;
  return '${family}_${fields['recipeId']?['stringValue']}_'
      '${fields['baseSignature']?['stringValue']}_'
      '${fields['householdSize']?['integerValue']}';
}

/// Crea la adaptación como la app: con su id y con createdAt como la hora del
/// servidor.
Future<int> create(
  Db db,
  Map<String, Map<String, Object?>> fields, {
  String? id,
}) => db.commit([
  setWrite(
    'adjustments/${id ?? idOf(fields)}',
    fields,
    requestTimeFields: ['createdAt'],
  ),
]);

Db fam1() => Db.user('fam1');
Db fam2() => Db.user('fam2');
Db staff() => Db.user('staff1');
Db nutri() => Db.user('nutri1', signedInAgo: const Duration(minutes: 4));
Db staleNutri() => Db.user('nutri1', signedInAgo: const Duration(minutes: 6));

Map<String, Object?> approve({String by = 'nutri1'}) => {
  'status': str('approved'),
  'reviewedBy': str(by),
  'reviewedAt': serverTimestamp,
};

Map<String, Object?> reject({String reason = 'No es seguro'}) => {
  'status': str('rejected'),
  'rejectionReason': str(reason),
  'reviewedBy': str('nutri1'),
  'reviewedAt': serverTimestamp,
};

void main() {
  useProject('demo-bamx-adjustments');

  setUpAll(requireEmulator);
  setUp(() async {
    await clearFirestore();
    final admin = Db.admin();
    await admin.setDoc('users/staff1', profile('staff'));
    await admin.setDoc('users/fam1', profile('family'));
    await admin.setDoc('users/fam2', profile('family'));
    await admin.setDoc('users/nutri1', profile('nutritionist'));
    await admin.setDoc('families/famA', family('fam1'));
    await admin.setDoc('families/famB', family('fam2'));
    await admin.setDoc('recipes/r1', recipe('approved'));
    await admin.setDoc('recipes/r2', recipe('pending'));
    await admin.setDoc('recipes/r3', recipe('approved'));
  });

  group('la familia crea la sugerencia', () {
    test(
      'la familia dueña crea una pendiente de una receta aprobada',
      () async {
        await assertAllowed(create(fam1(), adjustment()));
      },
    );

    test('no la crea para otra familia', () async {
      await assertDenied(create(fam2(), adjustment()));
      await assertDenied(
        create(fam1(), adjustment(change_: {'familyId': ref('families/famB')})),
      );
    });

    test('no la crea de una receta pendiente ni que no existe', () async {
      await assertDenied(
        create(fam1(), adjustment(change_: {'recipeId': str('r2')})),
      );
      await assertDenied(
        create(fam1(), adjustment(change_: {'recipeId': str('nope')})),
      );
    });

    test('nace pendiente y sin datos de revisión', () async {
      for (final status in ['approved', 'rejected']) {
        await assertDenied(
          create(fam1(), adjustment(change_: {'status': str(status)})),
        );
      }
      await assertDenied(
        create(
          fam1(),
          adjustment(
            change_: {'reviewedBy': str('nutri1'), 'reviewedAt': now()},
          ),
        ),
      );
    });

    test('el staff y el nutriólogo no la crean', () async {
      await assertDenied(create(staff(), adjustment()));
      await assertDenied(create(nutri(), adjustment()));
    });

    test('la hora de creación es la del servidor', () async {
      await assertDenied(
        fam1().setDoc('adjustments/a1', {...adjustment(), 'createdAt': now()}),
      );
    });

    test('falta un campo o sobra uno', () async {
      for (final key in adjustment().keys) {
        await assertDenied(create(fam1(), adjustment(remove: [key])));
      }
      await assertDenied(
        create(
          fam1(),
          adjustment(change_: {'familyName': str('Familia Ramírez')}),
        ),
      );
    });

    test(
      'no lleva nombres: un campo de más con un nombre se rechaza',
      () async {
        await assertDenied(
          create(
            fam1(),
            adjustment(
              change_: {
                'members': arr([str('María')]),
              },
            ),
          ),
        );
      },
    );

    test('valores inválidos', () async {
      final cases = <Map<String, Map<String, Object?>>>[
        {'baseSignature': str('XYZ')},
        {'baseSignature': str('abcdef1')},
        {'householdSize': integer(0)},
        {'householdSize': integer(51)},
        {'servings': integer(0)},
        {'servings': integer(100)},
        {'summary': str('')},
        {'summary': str('a' * 301)},
        {'ingredients': arr([])},
        {
          'ingredients': arr([ingredient(unit: 'cucharada')]),
        },
        {
          'ingredients': arr([ingredient(quantity: 0)]),
        },
        {'changes': arr([])},
        {
          'changes': arr([change(kind: 'otro')]),
        },
        {
          'changes': arr([change(reason: '')]),
        },
      ];
      for (final fields in cases) {
        await assertDenied(create(fam1(), adjustment(change_: fields)));
      }
    });

    test('una receta con diagonal no se acepta', () async {
      // El id no puede llevar "/": se prueba con un id válido que no coincide.
      await assertDenied(
        create(
          fam1(),
          adjustment(change_: {'recipeId': str('a/b')}),
          id: 'famA_a_b_abcdef12_4',
        ),
      );
    });

    test('el máximo de cambios e ingredientes cabe y uno más no', () async {
      await assertAllowed(
        create(
          fam1(),
          adjustment(
            change_: {
              'changes': arr([for (var i = 0; i < 6; i++) change()]),
              'ingredients': arr([for (var i = 0; i < 10; i++) ingredient()]),
              'summary': str('a' * 300),
            },
          ),
        ),
      );
      await assertDenied(
        create(
          fam1(),
          adjustment(
            change_: {
              'baseSignature': str('abcdef13'),
              'changes': arr([for (var i = 0; i < 7; i++) change()]),
            },
          ),
        ),
      );
      await assertDenied(
        create(
          fam1(),
          adjustment(
            change_: {
              'baseSignature': str('abcdef14'),
              'ingredients': arr([for (var i = 0; i < 11; i++) ingredient()]),
            },
          ),
        ),
      );
    });
  });

  group('el id del documento limita las pendientes', () {
    test('el id es familia, receta, huella y tamaño del hogar', () async {
      expect(idOf(adjustment()), 'famA_r1_abcdef12_4');
      await assertAllowed(create(fam1(), adjustment()));
      expect(await adminDoc('adjustments/famA_r1_abcdef12_4'), isNotNull);
    });

    test('un id que no coincide se deniega', () async {
      for (final id in [
        'a1',
        'famA_r1_abcdef12_5',
        'famA_r2_abcdef12_4',
        'famA_r1_abcdef13_4',
        'famA_r1_abcdef12',
        'famB_r1_abcdef12_4',
      ]) {
        await assertDenied(create(fam1(), adjustment(), id: id));
      }
    });

    test('el id de otra familia se deniega', () async {
      // famB usa el id que le tocaría a famA: no coincide con su familyId.
      await assertDenied(
        create(
          fam2(),
          adjustment(change_: {'familyId': ref('families/famB')}),
          id: 'famA_r1_abcdef12_4',
        ),
      );
      // Con su propio id, sí.
      await assertAllowed(
        create(fam2(), adjustment(change_: {'familyId': ref('families/famB')})),
      );
    });

    test('crear dos veces el mismo id se deniega', () async {
      await assertAllowed(create(fam1(), adjustment()));
      await assertDenied(create(fam1(), adjustment()));
      expect(await adminDocs('adjustments'), hasLength(1));
    });

    test('con otra huella o otro tamaño de hogar es otro documento', () async {
      await assertAllowed(create(fam1(), adjustment()));
      await assertAllowed(
        create(fam1(), adjustment(change_: {'baseSignature': str('abcdef13')})),
      );
      await assertAllowed(
        create(fam1(), adjustment(change_: {'householdSize': integer(5)})),
      );
      await assertAllowed(
        create(fam1(), adjustment(change_: {'recipeId': str('r3')})),
      );
      expect(await adminDocs('adjustments'), hasLength(4));
    });

    test('una pendiente retirada se puede volver a sugerir', () async {
      await assertAllowed(create(fam1(), adjustment()));
      await assertAllowed(fam1().deleteDoc('adjustments/famA_r1_abcdef12_4'));
      await assertAllowed(create(fam1(), adjustment()));
    });

    test(
      'una ya decidida no se puede volver a crear con el mismo id',
      () async {
        await Db.admin().setDoc(
          'adjustments/famA_r1_abcdef12_4',
          stored(status: 'rejected'),
        );
        await assertDenied(create(fam1(), adjustment()));
        // Después de cambiar el tamaño del hogar sí hay una sugerencia nueva.
        await assertAllowed(
          create(fam1(), adjustment(change_: {'householdSize': integer(5)})),
        );
      },
    );
  });

  group('quién la lee', () {
    setUp(() async {
      await Db.admin().setDoc('adjustments/a1', stored());
      await Db.admin().setDoc('adjustments/b1', stored(familyId: 'famB'));
    });

    test('la familia lee solo las suyas', () async {
      await assertAllowed(fam1().getDoc('adjustments/a1'));
      await assertDenied(fam1().getDoc('adjustments/b1'));
      await assertAllowed(
        fam1().listDocs(
          'adjustments',
          where: ('familyId', ref('families/famA')),
        ),
      );
      await assertDenied(fam1().listDocs('adjustments'));
    });

    test('el nutriólogo las lee todas', () async {
      await assertAllowed(nutri().getDoc('adjustments/a1'));
      await assertAllowed(nutri().getDoc('adjustments/b1'));
      await assertAllowed(nutri().listDocs('adjustments'));
    });

    test('el staff y las demás familias no', () async {
      await assertDenied(staff().getDoc('adjustments/a1'));
      await assertDenied(fam2().getDoc('adjustments/a1'));
    });

    test(
      'el nutriólogo no lee nombres de la familia ni de integrantes',
      () async {
        await Db.admin().setDoc('families/famA/members/m1', {
          'name': str('María'),
          'memberType': str('adult'),
          'createdAt': now(),
        });
        await assertDenied(nutri().getDoc('families/famA'));
        await assertDenied(nutri().getDoc('families/famA/members/m1'));
        await assertDenied(
          nutri().listDocs('members', parent: 'families/famA'),
        );
      },
    );
  });

  group('el nutriólogo decide', () {
    setUp(() async {
      await Db.admin().setDoc('adjustments/a1', stored());
    });

    test(
      'aprueba con sesión reciente, a su nombre y a la hora del servidor',
      () async {
        await assertAllowed(nutri().updateDoc('adjustments/a1', approve()));
        final doc = await adminDoc('adjustments/a1');
        expect(fieldValue(doc, 'status'), 'approved');
        expect(fieldValue(doc, 'reviewedBy'), 'nutri1');
      },
    );

    test('rechaza con motivo', () async {
      await assertAllowed(nutri().updateDoc('adjustments/a1', reject()));
      final doc = await adminDoc('adjustments/a1');
      expect(fieldValue(doc, 'status'), 'rejected');
      expect(fieldValue(doc, 'rejectionReason'), 'No es seguro');
    });

    test('no rechaza sin motivo', () async {
      await assertDenied(
        nutri().updateDoc('adjustments/a1', reject(reason: '')),
      );
      await assertDenied(
        nutri().updateDoc('adjustments/a1', reject(reason: '  ')),
      );
      await assertDenied(
        nutri().updateDoc('adjustments/a1', {
          'status': str('rejected'),
          'reviewedBy': str('nutri1'),
          'reviewedAt': serverTimestamp,
        }),
      );
      await assertDenied(
        nutri().updateDoc('adjustments/a1', reject(reason: 'a' * 301)),
      );
    });

    test('con sesión vieja no aprueba ni rechaza', () async {
      await assertDenied(staleNutri().updateDoc('adjustments/a1', approve()));
      await assertDenied(staleNutri().updateDoc('adjustments/a1', reject()));
    });

    test('no firma por otro ni con otra hora', () async {
      await assertDenied(
        nutri().updateDoc('adjustments/a1', approve(by: 'nutri2')),
      );
      await assertDenied(
        nutri().updateDoc('adjustments/a1', {
          'status': str('approved'),
          'reviewedBy': str('nutri1'),
          'reviewedAt': ts(DateTime.utc(2020)),
        }),
      );
    });

    test('no cambia el contenido al decidir ni por separado', () async {
      await assertDenied(
        nutri().updateDoc('adjustments/a1', {
          ...approve(),
          'summary': str('Otro resumen'),
        }),
      );
      await assertDenied(
        nutri().updateDoc('adjustments/a1', {
          ...approve(),
          'ingredients': arr([ingredient(name: 'Arroz')]),
        }),
      );
      await assertDenied(
        nutri().updateDoc('adjustments/a1', {'servings': integer(2)}),
      );
    });

    test('solo decide una pendiente, una sola vez', () async {
      await assertAllowed(nutri().updateDoc('adjustments/a1', approve()));
      await assertDenied(nutri().updateDoc('adjustments/a1', reject()));
      await assertDenied(nutri().updateDoc('adjustments/a1', approve()));
    });

    test('no la regresa a pendiente', () async {
      await Db.admin().setDoc('adjustments/a2', stored(status: 'approved'));
      await assertDenied(
        nutri().updateDoc('adjustments/a2', {'status': str('pending')}),
      );
    });

    test('no la crea ni la borra', () async {
      await assertDenied(nutri().deleteDoc('adjustments/a1'));
    });
  });

  group('nadie edita el contenido', () {
    setUp(() async {
      await Db.admin().setDoc('adjustments/a1', stored());
    });

    test('la familia no edita ni se aprueba sola', () async {
      await assertDenied(
        fam1().updateDoc('adjustments/a1', approve(by: 'fam1')),
      );
      await assertDenied(
        fam1().updateDoc('adjustments/a1', {'summary': str('Otro')}),
      );
      await assertDenied(
        fam1().updateDoc('adjustments/a1', {'status': str('approved')}),
      );
    });

    test('el staff y otra familia tampoco', () async {
      await assertDenied(
        staff().updateDoc('adjustments/a1', {'summary': str('Otro')}),
      );
      await assertDenied(
        fam2().updateDoc('adjustments/a1', approve(by: 'fam2')),
      );
    });
  });

  group('retirar una sugerencia', () {
    test('la familia borra una pendiente suya', () async {
      await Db.admin().setDoc('adjustments/a1', stored());
      await assertAllowed(fam1().deleteDoc('adjustments/a1'));
    });

    test('no borra una ya decidida', () async {
      await Db.admin().setDoc('adjustments/a1', stored(status: 'approved'));
      await Db.admin().setDoc('adjustments/a2', stored(status: 'rejected'));
      await assertDenied(fam1().deleteDoc('adjustments/a1'));
      await assertDenied(fam1().deleteDoc('adjustments/a2'));
    });

    test('otra familia y el staff no la borran', () async {
      await Db.admin().setDoc('adjustments/a1', stored());
      await assertDenied(fam2().deleteDoc('adjustments/a1'));
      await assertDenied(staff().deleteDoc('adjustments/a1'));
    });
  });
}
