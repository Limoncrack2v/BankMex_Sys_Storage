import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/family.dart';
import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/domain/models/meal_plan.dart';
import 'package:bank_storage_app/ui/models/recipe.dart';
import 'package:bank_storage_app/ui/sample_data.dart';
import 'package:bank_storage_app/ui/screens/meal_plan/meal_plan_screen.dart';
import 'package:bank_storage_app/ui/theme/app_colors.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/pill.dart';

/// Miércoles a media mañana.
final today = DateTime(2026, 10, 14, 9, 30);

final items = [
  for (final (name, quantity, unit, days) in [
    ('Leche entera', 1.0, FoodUnit.l, 1),
    ('Arroz', 2.0, FoodUnit.kg, 200),
    ('Lenteja', 1.0, FoodUnit.kg, 10),
  ])
    PantryItem(
      pantryItemId: 'item-$name',
      productId: name,
      deliveryId: 'entrega-001',
      type: FoodType.other,
      quantity: quantity,
      unit: unit,
      daysUntilExpiration: days,
      deviceId: 'device-test',
      localTimestamp: DateTime(2026, 10, 14),
    ),
];

final people = [
  for (final name in ['Ana', 'Luis'])
    Member(
      memberId: name,
      name: name,
      memberType: MemberType.adult,
      createdAt: DateTime(2026, 9, 1),
    ),
];

Family household({DateTime? nextDelivery}) => Family(
  familyId: 'famA',
  address: 'Calle Uno 1',
  registrationDate: DateTime(2026, 1, 5),
  authUid: 'uid-famA',
  appliances: const [],
  nextDeliveryDate: nextDelivery,
);

AsyncSnapshot<T> loaded<T>(T data) =>
    AsyncSnapshot<T>.withData(ConnectionState.active, data);

AsyncSnapshot<T> failed<T>() => AsyncSnapshot<T>.withError(
  ConnectionState.active,
  FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
);

/// Un plan de lunes 12 a domingo 18 de octubre.
SavedPlans savedPlans({required DateTime end}) => [
  (
    plan: MealPlan(
      id: 'plan1',
      familyId: 'famA',
      dateRangeStart: DateTime(2026, 10, 12),
      dateRangeEnd: end,
      meals: [
        MealPlanMeal(
          date: DateTime(2026, 10, 14),
          recipeId: 'rec_publicada',
          servings: 2,
        ),
      ],
    ),
    pendingSync: false,
  ),
];

/// Lo que se mandó guardar.
Future<List<MealPlan>> pumpTab(
  WidgetTester tester, {
  AsyncSnapshot<List<Recipe>>? catalog,
  AsyncSnapshot<Family?>? family,
  AsyncSnapshot<List<Member>>? members,
  AsyncSnapshot<List<PantryItem>>? pantry,
  AsyncSnapshot<SavedPlans>? plans,
  DateTime Function()? clock,
}) async {
  final saved = <MealPlan>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: MealPlanView(
          familyId: 'famA',
          catalog: catalog ?? loaded(SampleData.recipes),
          family: family ?? loaded<Family?>(household()),
          members: members ?? loaded(people),
          pantry: pantry ?? loaded(items),
          plans: plans ?? loaded<SavedPlans>(const []),
          onSave: (plan) async => saved.add(plan),
          clock: clock ?? () => today,
        ),
      ),
    ),
  );
  return saved;
}

/// Un aviso amarillo con [message], arriba de las tarjetas de los días.
void expectWarning(WidgetTester tester, String message) {
  final text = find.text(message);
  expect(text, findsOneWidget);
  final banner = tester.widget<InfoBanner>(
    find.ancestor(of: text, matching: find.byType(InfoBanner)),
  );
  expect(banner.background, AppColors.warningSoft);
  expect(banner.foreground, AppColors.warningText);
  expect(
    tester.getRect(text).bottom,
    lessThan(tester.getRect(find.text('MIÉ')).top),
  );
}

void main() {
  testWidgets('shows the suggested plan and offers to save it', (tester) async {
    await pumpTab(tester);

    expect(find.text('MIÉ'), findsOneWidget);
    expect(find.text('Guardar este plan'), findsOneWidget);
  });

  testWidgets('waits for the saved plans before showing a plan', (
    tester,
  ) async {
    await pumpTab(tester, plans: const AsyncSnapshot.waiting());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('MIÉ'), findsNothing);
    expect(find.text('Guardar este plan'), findsNothing);
  });

  testWidgets('waits for the catalog, the household and the members too', (
    tester,
  ) async {
    final cases = {
      'catalog': () => pumpTab(tester, catalog: const AsyncSnapshot.waiting()),
      'family': () => pumpTab(tester, family: const AsyncSnapshot.waiting()),
      'members': () => pumpTab(tester, members: const AsyncSnapshot.waiting()),
    };
    for (final MapEntry(key: name, value: pump) in cases.entries) {
      await pump();

      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
        reason: name,
      );
      expect(find.text('Guardar este plan'), findsNothing, reason: name);
    }
  });

  testWidgets('a household without a document still gets a plan', (
    tester,
  ) async {
    await pumpTab(tester, family: loaded<Family?>(null));

    expect(find.text('Guardar este plan'), findsOneWidget);
  });

  testWidgets('if the saved plans cannot be read, it says so above the days '
      'and does not offer to save', (tester) async {
    await pumpTab(tester, plans: failed());

    expectWarning(
      tester,
      'No pudimos revisar si ya guardaste un plan. Revisa tu conexión e '
      'intenta de nuevo.',
    );
    expect(find.text('Guardar este plan'), findsNothing);
  });

  testWidgets('if the members cannot be read, it warns about allergies and '
      'does not offer to save', (tester) async {
    await pumpTab(tester, members: failed());

    expectWarning(
      tester,
      'No pudimos revisar las alergias de tu familia. Revisa tu conexión e '
      'intenta de nuevo.',
    );
    expect(find.text('Guardar este plan'), findsNothing);
  });

  testWidgets('if the household cannot be read, it says so and does not '
      'offer to save', (tester) async {
    await pumpTab(tester, family: failed());

    expectWarning(
      tester,
      'No pudimos cargar los datos de tu hogar. Revisa tu conexión e intenta '
      'de nuevo.',
    );
    expect(find.text('Guardar este plan'), findsNothing);
  });

  testWidgets('if the catalog cannot be read, the sample recipes are shown '
      'but cannot be saved', (tester) async {
    await pumpTab(tester, catalog: failed());

    expectWarning(
      tester,
      'No pudimos cargar las recetas de BAMX. Revisa tu conexión e intenta de '
      'nuevo.',
    );
    expect(find.text('Guardar este plan'), findsNothing);
    expect(find.textContaining('Para guardar tu plan'), findsNothing);
  });

  testWidgets('the sample recipes of an empty catalog cannot be saved', (
    tester,
  ) async {
    await pumpTab(tester, catalog: loaded(const []));

    expect(find.text('MIÉ'), findsOneWidget);
    expect(
      find.text(
        'Para guardar tu plan hacen falta recetas del catálogo de BAMX.',
      ),
      findsOneWidget,
    );
    expect(find.text('Guardar este plan'), findsNothing);
  });

  testWidgets('saving after midnight saves the plan of the new day', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 14, 23, 59);
    final saved = await pumpTab(tester, clock: () => now);
    expect(find.text('MIÉ'), findsOneWidget);

    // La pestaña se quedó abierta: nada la vuelve a armar a medianoche.
    now = DateTime(2026, 10, 15, 0, 1);
    await tester.tap(find.text('Guardar este plan'));
    await tester.pump();

    final plan = saved.single;
    expect(plan.dateRangeStart, DateTime(2026, 10, 15));
    expect(plan.dateRangeEnd, DateTime(2026, 10, 22));
    expect(plan.meals.first.date, DateTime(2026, 10, 15));
  });

  testWidgets('saves 14 days when the next delivery is more than a week away', (
    tester,
  ) async {
    final saved = await pumpTab(
      tester,
      family: loaded<Family?>(household(nextDelivery: DateTime(2026, 10, 25))),
    );

    await tester.tap(find.text('Guardar este plan'));
    await tester.pump();

    expect(saved.single.dateRangeEnd, DateTime(2026, 10, 28));
    expect(saved.single.meals, hasLength(14));
  });

  testWidgets('a plan that already ended gives the suggestion back', (
    tester,
  ) async {
    await pumpTab(
      tester,
      plans: loaded(savedPlans(end: DateTime(2026, 10, 14))),
    );

    expect(find.text('Guardar este plan'), findsOneWidget);
  });

  testWidgets('a saved plan waits for the catalog instead of calling its '
      'recipes gone', (tester) async {
    await pumpTab(
      tester,
      catalog: const AsyncSnapshot.waiting(),
      plans: loaded(savedPlans(end: DateTime(2026, 10, 19))),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Receta no disponible'), findsNothing);
  });
}
