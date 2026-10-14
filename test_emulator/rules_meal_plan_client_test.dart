// Pruebas del plan que escribe la pantalla "Plan de comidas"
// (MealPlanRepository.save): un documento vigente por familia, de 7 o 14
// comidas, contra el emulador de Firestore (127.0.0.1:8080). Las reglas en sí
// están en rules_meal_plans_test.dart.
//
// Uso: flutter test test_emulator/rules_meal_plan_client_test.dart
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

/// Como lo guarda la app: familyId es una referencia, cada comida tiene la
/// fecha, el id de la receta y las porciones del hogar.
Map<String, Map<String, Object?>> plan({
  String familyId = 'famA',
  int days = 7,
  String recipe = 'receta1',
}) {
  final start = DateTime.utc(2026, 10, 14);
  return {
    'familyId': ref('families/$familyId'),
    'dateRangeStart': ts(start),
    'dateRangeEnd': ts(start.add(Duration(days: days))),
    'meals': arr([
      for (var i = 0; i < days; i++)
        mapValue({
          'date': ts(start.add(Duration(days: i))),
          'recipeId': str(recipe),
          'servings': number(3.5),
        }),
    ]),
  };
}

Db staff() => Db.user('staff1');
Db fam1() => Db.user('fam1');
Db fam2() => Db.user('fam2');

/// La consulta de MealPlanRepository.listByFamily: los planes de una familia.
Future<List<({String id, Map<String, Object?> fields})>> plansOfFamA() =>
    adminDocs('mealPlans');

void main() {
  useProject('demo-bamx-plan-persist');

  setUpAll(requireEmulator);
  setUp(() async {
    await clearFirestore();
    final admin = Db.admin();
    await admin.setDoc('users/staff1', profile('staff'));
    await admin.setDoc('users/fam1', profile('family'));
    await admin.setDoc('users/fam2', profile('family'));
    await admin.setDoc('families/famA', family('fam1'));
    await admin.setDoc('families/famB', family('fam2'));
  });

  group('el plan vigente de la familia', () {
    test('la familia busca sus planes con la consulta de la app', () async {
      await Db.admin().setDoc('mealPlans/p1', plan());
      await assertAllowed(
        fam1().listDocs('mealPlans', where: ('familyId', ref('families/famA'))),
      );
    });

    test('la familia crea su plan de 7 y el de 14 días', () async {
      await assertAllowed(fam1().setDoc('mealPlans/p1', plan()));
      await assertAllowed(fam1().setDoc('mealPlans/p2', plan(days: 14)));
    });

    test('guardar otra vez reemplaza el documento, no agrega otro', () async {
      await assertAllowed(
        fam1().setDoc('mealPlans/p1', plan(recipe: 'receta1')),
      );
      await assertAllowed(
        fam1().setDoc('mealPlans/p1', plan(recipe: 'receta2')),
      );
      final stored = await plansOfFamA();
      expect(stored, hasLength(1));
      expect(fieldValue(stored.single.fields, 'meals'), isNotNull);
    });

    test('un plan sin comidas (ninguna receta es segura) se guarda', () async {
      await Db.admin().setDoc('mealPlans/p1', plan());
      await assertAllowed(
        fam1().setDoc('mealPlans/p1', {...plan(), 'meals': arr([])}),
      );
    });

    test('otra familia no lee, reemplaza ni borra el plan', () async {
      await Db.admin().setDoc('mealPlans/p1', plan());
      await assertDenied(fam2().getDoc('mealPlans/p1'));
      await assertDenied(fam2().setDoc('mealPlans/p1', plan()));
      await assertDenied(fam2().deleteDoc('mealPlans/p1'));
    });

    test(
      'otra familia no puede guardar un plan a nombre de la primera',
      () async {
        await assertDenied(fam2().setDoc('mealPlans/p9', plan()));
      },
    );

    test(
      'un documento con el id de una familia no bloquea a esa familia',
      () async {
        // famB crea un plan suyo con el id "famA": famA guarda el suyo aparte.
        await assertAllowed(
          fam2().setDoc('mealPlans/famA', plan(familyId: 'famB')),
        );
        await assertAllowed(fam1().setDoc('mealPlans/p1', plan()));
        await assertAllowed(
          fam1().listDocs(
            'mealPlans',
            where: ('familyId', ref('families/famA')),
          ),
        );
      },
    );

    test('el staff puede leer el plan de una familia', () async {
      await Db.admin().setDoc('mealPlans/p1', plan());
      await assertAllowed(staff().getDoc('mealPlans/p1'));
    });
  });
}
