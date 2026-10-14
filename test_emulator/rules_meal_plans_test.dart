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

/// Una comida válida del plan base (rango del 12 al 19 de octubre de 2026).
Map<String, Map<String, Object?>> meal([
  Map<String, Map<String, Object?>> extra = const {},
]) => {
  'date': ts(DateTime.utc(2026, 10, 12)),
  'recipeId': str('receta1'),
  'servings': number(3.5),
  ...extra,
};

/// Un plan con estas comidas, sobre el rango del plan base.
Map<String, Map<String, Object?>> planWith(
  List<Map<String, Map<String, Object?>>> meals, [
  Map<String, Map<String, Object?>> extra = const {},
]) => plan({
  'meals': arr([for (final m in meals) mapValue(m)]),
  ...extra,
});

/// Máximo de comidas (MealPlan.maxMeals): un plan quincenal, una por día.
const maxMeals = 14;

/// Un plan quincenal completo: del 12 al 26 de octubre, una comida por día.
Map<String, Map<String, Object?>> maxPlan({
  int? badIndex,
  Map<String, Map<String, Object?>> bad = const {},
  String? without,
  Map<String, Map<String, Object?>> extra = const {},
}) => {
  ...planWith([
    for (var i = 0; i < maxMeals; i++)
      meal({
        'date': ts(DateTime.utc(2026, 10, 12 + i)),
        'recipeId': str('receta$i'),
        if (i == badIndex) ...bad,
      })..remove(i == badIndex ? without : null),
  ]),
  'dateRangeEnd': ts(DateTime.utc(2026, 10, 26)),
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

    test('la familia lee un plan que no existe', () async {
      await assertAllowed(fam1().getDoc('mealPlans/nope'));
    });

    test('sin sesión no se lee un plan que no existe', () async {
      await assertDenied(Db.anonymous().getDoc('mealPlans/nope'));
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

    test('meals vacío que no es lista rechazado', () async {
      // Sin comidas que revisar, solo is list lo distingue de una lista vacía.
      await assertDenied(fam1().setDoc(p, plan({'meals': str('')})));
      await assertDenied(fam1().setDoc(p, plan({'meals': mapValue({})})));
      await assertDenied(fam1().setDoc(p, plan({'meals': nul()})));
    });

    test('una comida más que el máximo rechazada', () async {
      await assertDenied(
        fam1().setDoc(p, planWith(List.filled(maxMeals + 1, meal()))),
      );
    });

    test('101 comidas válidas rechazadas', () async {
      await assertDenied(fam1().setDoc(p, planWith(List.filled(101, meal()))));
    });

    test('la familia cambia las comidas de su plan', () async {
      await assertAllowed(fam1().updateDoc(p1, {'meals': arr([])}));
    });

    test('la familia no deja su plan inválido al editarlo', () async {
      await assertDenied(fam1().updateDoc(p1, {'foo': integer(1)}));
      await assertDenied(
        fam1().updateDoc(p1, {
          'meals': arr(List.generate(maxMeals + 1, (_) => mapValue(meal()))),
        }),
      );
      await assertDenied(
        fam1().updateDoc(p1, {'dateRangeEnd': ts(DateTime.utc(2026, 10, 1))}),
      );
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

  group('comidas del plan', () {
    Future<void> denied(Map<String, Map<String, Object?>> data) =>
        assertDenied(fam1().setDoc(p, data));

    Future<void> allowed(Map<String, Map<String, Object?>> data) =>
        assertAllowed(fam1().setDoc(p, data));

    Future<void> deniedMeal(Map<String, Map<String, Object?>> data) =>
        denied(planWith([meal(), meal(data)]));

    test('una comida normal se acepta', () async {
      await allowed(planWith([meal()]));
    });

    test('una comida por día de una semana se acepta', () async {
      await allowed(
        planWith([
          for (var i = 0; i < 7; i++)
            meal({
              'date': ts(DateTime.utc(2026, 10, 12 + i)),
              'recipeId': str('r$i'),
            }),
        ]),
      );
    });

    group('campos', () {
      test('comida sin date rechazada', () async {
        await denied(planWith([meal()..remove('date')]));
      });

      test('comida sin recipeId rechazada', () async {
        await denied(planWith([meal()..remove('recipeId')]));
      });

      test('comida sin servings rechazada', () async {
        await denied(planWith([meal()..remove('servings')]));
      });

      test('comida vacía rechazada', () async {
        await denied(planWith([{}]));
      });

      test('comida con un campo extra rechazada', () async {
        await deniedMeal({'notes': str('sin sal')});
        await deniedMeal({'extra': integer(1)});
      });

      test('comida que no es un mapa rechazada', () async {
        await denied(
          plan({
            'meals': arr([str('Pollo asado')]),
          }),
        );
        await denied(
          plan({
            'meals': arr([integer(1)]),
          }),
        );
      });
    });

    group('servings', () {
      test('0 rechazado', () async {
        await deniedMeal({'servings': integer(0)});
        await deniedMeal({'servings': number(0)});
      });

      test('negativo rechazado', () async {
        await deniedMeal({'servings': integer(-1)});
        await deniedMeal({'servings': number(-0.5)});
      });

      test('texto rechazado', () async {
        await deniedMeal({'servings': str('3')});
      });

      test('nulo, booleano o lista rechazados', () async {
        await deniedMeal({'servings': nul()});
        await deniedMeal({'servings': boolean(true)});
        await deniedMeal({
          'servings': arr([integer(1)]),
        });
      });

      test('el menor positivo y el tope se aceptan', () async {
        await allowed(
          planWith([
            meal({'servings': number(0.01)}),
          ]),
        );
        await allowed(
          planWith([
            meal({'servings': integer(1)}),
          ]),
        );
        await allowed(
          planWith([
            meal({'servings': integer(100)}),
          ]),
        );
        await allowed(
          planWith([
            meal({'servings': number(100)}),
          ]),
        );
      });

      test('más del tope rechazado', () async {
        await deniedMeal({'servings': number(100.01)});
        await deniedMeal({'servings': integer(101)});
        await deniedMeal({'servings': integer(1000000)});
      });
    });

    group('recipeId', () {
      test('vacío rechazado', () async {
        await deniedMeal({'recipeId': str('')});
      });

      test('número, nulo o referencia rechazados', () async {
        await deniedMeal({'recipeId': integer(1)});
        await deniedMeal({'recipeId': nul()});
        await deniedMeal({'recipeId': ref('recipes/receta1')});
      });

      test('de 1 y de 128 caracteres aceptado', () async {
        await allowed(
          planWith([
            meal({'recipeId': str('a')}),
          ]),
        );
        await allowed(
          planWith([
            meal({'recipeId': str('a' * 128)}),
          ]),
        );
      });

      test('de 129 caracteres rechazado', () async {
        await deniedMeal({'recipeId': str('a' * 129)});
      });

      test('de 10000 caracteres rechazado', () async {
        await deniedMeal({'recipeId': str('a' * 10000)});
      });

      test('con "/" rechazado', () async {
        await deniedMeal({'recipeId': str('recipes/receta1')});
        await deniedMeal({'recipeId': str('/')});
      });

      test('con saltos de línea de 128 caracteres aceptado', () async {
        await allowed(
          planWith([
            meal({'recipeId': str('a\n' * 64)}),
          ]),
        );
      });
    });

    group('date', () {
      // El rango del plan base va del 12 al 19 de octubre de 2026 (UTC).
      final start = DateTime.utc(2026, 10, 12);
      final end = DateTime.utc(2026, 10, 19);
      const ms = Duration(milliseconds: 1);

      test('exactamente en el inicio del rango aceptada', () async {
        await allowed(
          planWith([
            meal({'date': ts(start)}),
          ]),
        );
      });

      test('exactamente en el fin del rango aceptada', () async {
        await allowed(
          planWith([
            meal({'date': ts(end)}),
          ]),
        );
      });

      test('en medio del rango aceptada', () async {
        await allowed(
          planWith([
            meal({'date': ts(DateTime.utc(2026, 10, 15, 13, 45))}),
          ]),
        );
      });

      test('un milisegundo antes del inicio rechazada', () async {
        await deniedMeal({'date': ts(start.subtract(ms))});
      });

      test('un milisegundo después del fin rechazada', () async {
        await deniedMeal({'date': ts(end.add(ms))});
      });

      test('un día fuera del rango rechazada', () async {
        await deniedMeal({'date': ts(DateTime.utc(2026, 10, 11))});
        await deniedMeal({'date': ts(DateTime.utc(2026, 10, 20))});
      });

      test('muy lejos del rango rechazada', () async {
        await deniedMeal({'date': ts(DateTime.utc(1970))});
        await deniedMeal({'date': ts(DateTime.utc(2100))});
      });

      test('texto, número o nulo rechazados', () async {
        await deniedMeal({'date': str('2026-10-12')});
        await deniedMeal({'date': integer(1760227200000)});
        await deniedMeal({'date': nul()});
      });

      test('un rango de un solo instante acepta solo ese instante', () async {
        final range = {'dateRangeStart': ts(start), 'dateRangeEnd': ts(start)};
        await allowed(
          planWith([
            meal({'date': ts(start)}),
          ], range),
        );
        await denied(
          planWith([
            meal({'date': ts(start.add(ms))}),
          ], range),
        );
      });

      test('la hora de México no cambia el rango', () async {
        // Un plan armado en la Ciudad de México (UTC-6): la medianoche local
        // del 12 de octubre es 06:00 UTC y la del 19, igual.
        final localStart = DateTime.utc(2026, 10, 12, 6);
        final localEnd = DateTime.utc(2026, 10, 19, 6);
        final range = {
          'dateRangeStart': ts(localStart),
          'dateRangeEnd': ts(localEnd),
        };
        await allowed(
          planWith([
            meal({'date': ts(localStart)}),
            meal({'date': ts(localEnd.subtract(const Duration(days: 1)))}),
          ], range),
        );
        await denied(
          planWith([
            meal({'date': ts(localStart.subtract(ms))}),
          ], range),
        );
      });
    });

    group('cantidad máxima de comidas', () {
      test('$maxMeals comidas una por día se aceptan al crear', () async {
        await allowed(maxPlan());
        await assertAllowed(staff().setDoc('mealPlans/staffNew', maxPlan()));
      });

      test('${maxMeals + 1} comidas válidas rechazadas', () async {
        await denied(planWith(List.filled(maxMeals + 1, meal())));
      });

      test('100 comidas válidas rechazadas', () async {
        await denied(planWith(List.filled(100, meal())));
      });

      test('la familia cambia un plan por uno de $maxMeals comidas', () async {
        await assertAllowed(fam1().updateDoc(p1, maxPlan()));
      });

      test('staff cambia un plan por uno de $maxMeals comidas', () async {
        await assertAllowed(staff().updateDoc(p1, maxPlan()));
      });

      test('staff cambia las comidas de un plan de $maxMeals', () async {
        await Db.admin().setDoc(p1, maxPlan());
        await assertAllowed(
          staff().updateDoc(p1, {
            'meals': maxPlan()['meals']!,
            'dateRangeEnd': ts(DateTime.utc(2026, 10, 27)),
          }),
        );
      });

      test('uno inválido al inicio de $maxMeals rechazado', () async {
        await denied(maxPlan(badIndex: 0, bad: {'servings': integer(0)}));
      });

      test('uno inválido en medio de $maxMeals rechazado', () async {
        await denied(maxPlan(badIndex: 7, bad: {'recipeId': str('')}));
      });

      test('uno inválido al final de $maxMeals rechazado', () async {
        final last = maxMeals - 1;
        await denied(maxPlan(badIndex: last, bad: {'servings': integer(0)}));
      });

      test('la última comida de $maxMeals se revisa por cada campo', () async {
        final last = maxMeals - 1;
        await denied(maxPlan(badIndex: last, bad: {'servings': integer(-1)}));
        await denied(maxPlan(badIndex: last, bad: {'servings': str('3')}));
        await denied(maxPlan(badIndex: last, bad: {'servings': number(101)}));
        await denied(maxPlan(badIndex: last, bad: {'recipeId': str('')}));
        await denied(maxPlan(badIndex: last, bad: {'recipeId': str('a/b')}));
        await denied(maxPlan(badIndex: last, bad: {'extra': integer(1)}));
        await denied(
          maxPlan(
            badIndex: last,
            bad: {'date': ts(DateTime.utc(2026, 10, 26, 0, 0, 0, 1))},
          ),
        );
        await denied(
          maxPlan(
            badIndex: last,
            bad: {'date': ts(DateTime.utc(2026, 10, 11))},
          ),
        );
      });

      test('la última comida de $maxMeals sin un campo rechazada', () async {
        for (final field in ['date', 'recipeId', 'servings']) {
          await denied(maxPlan(badIndex: maxMeals - 1, without: field));
        }
      });

      test(
        'el rango de un plan de $maxMeals se acorta sin comidas fuera',
        () async {
          await Db.admin().setDoc(p1, maxPlan());
          // La última comida queda después del nuevo fin.
          await assertDenied(
            fam1().updateDoc(p1, {
              'dateRangeEnd': ts(DateTime.utc(2026, 10, 24)),
            }),
          );
        },
      );
    });

    group('un plan que ya existe', () {
      test('la familia corrige una comida inválida', () async {
        await Db.admin().setDoc(
          p1,
          planWith([
            meal({'servings': integer(0)}),
          ]),
        );
        await assertAllowed(
          fam1().updateDoc(p1, {
            'meals': planWith([meal()])['meals']!,
          }),
        );
      });

      test('la familia no guarda una comida inválida al editar', () async {
        await assertDenied(
          fam1().updateDoc(p1, {
            'meals': planWith([
              meal({'servings': integer(0)}),
            ])['meals']!,
          }),
        );
        await assertDenied(
          fam1().updateDoc(p1, {
            'meals': planWith([
              meal({'extra': integer(1)}),
            ])['meals']!,
          }),
        );
      });

      test('staff no guarda una comida inválida al editar', () async {
        await assertDenied(
          staff().updateDoc(p1, {
            'meals': planWith([
              meal({'recipeId': str('')}),
            ])['meals']!,
          }),
        );
      });

      test('un plan inválido de antes se puede borrar', () async {
        await Db.admin().setDoc(
          p1,
          planWith(List.filled(100, meal({'servings': integer(0)}))),
        );
        await assertAllowed(fam1().deleteDoc(p1));
      });
    });
  });
}
