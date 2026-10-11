// Pruebas de firestore.rules para mealPlans/{planId} contra el emulador de
// Firestore (127.0.0.1:8080).
//
// Uso: flutter test test_emulator/rules_meal_plans_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'support/emulator.dart';

const _project = 'demo-bamx-meal-plans';

Map<String, Object?> now() => ts(DateTime.utc(2026, 9, 21, 12));

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

Map<String, Map<String, Object?>> plan([
  Map<String, Map<String, Object?>> extra = const {},
]) => {
  'familyId': ref('families/famA'),
  'dateRangeStart': ts(DateTime.utc(2026, 10, 12)),
  'dateRangeEnd': ts(DateTime.utc(2026, 10, 19)),
  'meals': arr([
    mapValue({
      'date': ts(DateTime.utc(2026, 10, 12)),
      'recipeId': str('receta1'),
      'servings': number(3.5),
    }),
  ]),
  ...extra,
};

Db staff() => Db.user('staff1');
Db fam1() => Db.user('fam1');
Db fam2() => Db.user('fam2');

/// El plan de famA que ya existe.
const p1 = 'mealPlans/p1';

/// El plan nuevo que intentan crear las pruebas.
const p = 'mealPlans/new';

void main() {
  useProject(_project);

  setUpAll(requireEmulator);

  setUp(() async {
    await clearFirestore();
    final admin = Db.admin();
    await admin.setDoc('users/staff1', profile('staff'));
    await admin.setDoc('users/fam1', profile('family'));
    await admin.setDoc('users/fam2', profile('family'));
    await admin.setDoc('families/famA', family('fam1'));
    await admin.setDoc('families/famB', family('fam2'));
    await admin.setDoc(p1, plan());
  });

  group('mealPlans', () {
    test('la familia lee su plan', () async {
      await assertAllowed(fam1().getDoc(p1));
    });

    test('otra familia no lee el plan', () async {
      await assertDenied(fam2().getDoc(p1));
    });

    test('otra familia no lista los planes de famA', () async {
      await assertDenied(
        fam2().listDocs('mealPlans', where: ('familyId', ref('families/famA'))),
      );
    });

    test('nadie cambia la familia de un plan', () async {
      final change = {'familyId': ref('families/famB')};
      await assertDenied(fam1().updateDoc(p1, change));
      await assertDenied(staff().updateDoc(p1, change));
    });

    test('staff lee el plan de una familia', () async {
      await assertAllowed(staff().getDoc(p1));
    });

    test('la familia lista sus planes', () async {
      await assertAllowed(
        fam1().listDocs('mealPlans', where: ('familyId', ref('families/famA'))),
      );
    });

    test('nadie lista todos los planes sin filtro', () async {
      await assertDenied(staff().listDocs('mealPlans'));
    });

    test('sin sesión no se leen, crean ni borran planes', () async {
      await assertDenied(Db.anonymous().getDoc(p1));
      await assertDenied(Db.anonymous().setDoc(p, plan()));
      await assertDenied(Db.anonymous().deleteDoc(p1));
    });

    test('la familia crea su plan', () async {
      await assertAllowed(fam1().setDoc(p, plan()));
    });

    test('staff crea un plan para la familia', () async {
      await assertAllowed(staff().setDoc(p, plan()));
    });

    test('otra familia no crea un plan para famA', () async {
      await assertDenied(fam2().setDoc(p, plan()));
    });

    test('plan sin comidas válido', () async {
      await assertAllowed(fam1().setDoc(p, plan({'meals': arr([])})));
    });

    test('staff no crea un plan para una familia que no existe', () async {
      await assertDenied(
        staff().setDoc(p, plan({'familyId': ref('families/ghost')})),
      );
    });

    test('familyId como texto rechazado', () async {
      await assertDenied(fam1().setDoc(p, plan({'familyId': str('famA')})));
    });

    test('familyId que apunta a otra colección rechazado', () async {
      await assertDenied(
        fam1().setDoc(p, plan({'familyId': ref('recipes/famA')})),
      );
    });

    test('campo extra rechazado', () async {
      await assertDenied(fam1().setDoc(p, plan({'foo': integer(1)})));
    });

    test('plan sin el campo meals rechazado', () async {
      await assertDenied(fam1().setDoc(p, plan()..remove('meals')));
    });

    test('fecha inicial como texto rechazada', () async {
      await assertDenied(
        fam1().setDoc(p, plan({'dateRangeStart': str('2026-10-12')})),
      );
    });

    test('fecha final antes de la inicial rechazada', () async {
      await assertDenied(
        fam1().setDoc(
          p,
          plan({'dateRangeEnd': ts(DateTime.utc(2026, 10, 11))}),
        ),
      );
    });

    test('meals que no es lista rechazado', () async {
      await assertDenied(fam1().setDoc(p, plan({'meals': str('Pollo asado')})));
    });

    test('101 comidas rechazadas', () async {
      await assertDenied(
        fam1().setDoc(
          p,
          plan({
            'meals': arr(
              List.generate(101, (_) => mapValue({'recipeId': str('r1')})),
            ),
          }),
        ),
      );
    });

    test('la familia cambia las comidas de su plan', () async {
      await assertAllowed(fam1().updateDoc(p1, {'meals': arr([])}));
    });

    test('otra familia no edita el plan', () async {
      await assertDenied(fam2().updateDoc(p1, {'meals': arr([])}));
    });

    test('otra familia no se queda con el plan', () async {
      await assertDenied(
        fam2().updateDoc(p1, {'familyId': ref('families/famB')}),
      );
    });

    test('la familia borra su plan', () async {
      await assertAllowed(fam1().deleteDoc(p1));
    });

    test('otra familia no borra el plan', () async {
      await assertDenied(fam2().deleteDoc(p1));
    });
  });
}
