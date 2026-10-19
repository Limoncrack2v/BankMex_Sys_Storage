import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/app_user.dart';
import 'package:bank_storage_app/data/models/family.dart';
import 'package:bank_storage_app/data/plan_reminder.dart';
import 'package:bank_storage_app/ui/screens/home/home_screen.dart';
import 'package:bank_storage_app/ui/screens/home/open_plan_from_reminder.dart';
import 'package:bank_storage_app/ui/widgets/app_bottom_nav.dart';

/// Como HomeScreen, pero con un texto en vez de cada pestaña: las de verdad
/// leen Firestore y no se pueden armar en estas pruebas.
class _Tabs extends StatefulWidget {
  const _Tabs();

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> with OpenPlanFromReminder {
  int _index = 0;

  @override
  void showPlan() => _index = HomeScreen.planTab;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Text('Pestaña $_index'),
    bottomNavigationBar: AppBottomNav(
      currentIndex: _index,
      onTap: (index) => setState(() => _index = index),
    ),
  );
}

void main() {
  // Lo que pone en true el plugin cuando la familia toca el recordatorio.
  final pending = PlanReminder.instance.openPlanPending;

  tearDown(() => pending.value = false);

  test('the plan tab is "Plan de comidas"', () {
    expect(
      AppBottomNav.familyItems[HomeScreen.planTab].label,
      'Plan de comidas',
    );
  });

  // HomeScreen no se puede montar sin Firestore: esto cuida que un merge no
  // le quite el mixin.
  test('the family home uses it', () {
    final home = HomeScreen(
      family: Family(
        familyId: 'fam',
        address: 'Calle 1',
        registrationDate: DateTime(2026, 9, 1),
        authUid: 'fam',
        appliances: const [],
      ),
      user: AppUser(
        userId: 'fam',
        name: 'Familia',
        email: 'fam@bamx.test',
        role: AppUser.roleFamily,
        createdAt: DateTime(2026, 9, 1),
      ),
    );
    // ignore: invalid_use_of_protected_member
    expect(home.createState(), isA<OpenPlanFromReminder>());
  });

  testWidgets('starts on the plan when the reminder opened the app', (
    tester,
  ) async {
    pending.value = true;

    await tester.pumpWidget(const MaterialApp(home: _Tabs()));

    expect(find.text('Pestaña 2'), findsOneWidget);
    expect(pending.value, isFalse);
  });

  testWidgets('switches to the plan when the reminder is tapped later', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _Tabs()));
    expect(find.text('Pestaña 0'), findsOneWidget);

    pending.value = true;
    await tester.pump();

    expect(find.text('Pestaña 2'), findsOneWidget);
    expect(pending.value, isFalse);
  });

  testWidgets('opens the plan again on the next tap', (tester) async {
    pending.value = true;
    await tester.pumpWidget(const MaterialApp(home: _Tabs()));
    await tester.tap(find.text('Despensa'));
    await tester.pump();
    expect(find.text('Pestaña 0'), findsOneWidget);

    pending.value = true;
    await tester.pump();

    expect(find.text('Pestaña 2'), findsOneWidget);
  });

  testWidgets('stops listening when the screen closes', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Tabs()));
    await tester.pumpWidget(const SizedBox());

    pending.value = true;
    await tester.pump();

    // Nadie la atendió, y sin setState después de dispose.
    expect(pending.value, isTrue);
    expect(tester.takeException(), isNull);
  });
}
