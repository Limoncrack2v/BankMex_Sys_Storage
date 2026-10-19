import 'package:bank_storage_app/data/models/app_user.dart';
import 'package:bank_storage_app/ui/screens/session/account_sheet.dart';
import 'package:bank_storage_app/ui/theme/app_assets.dart';
import 'package:bank_storage_app/ui/theme/app_colors.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/app_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser _user(String role, String name) => AppUser(
  userId: 'u1',
  name: name,
  email: 'cuenta@bamx.test',
  role: role,
  createdAt: DateTime(2026, 10, 1),
);

Future<void> _open(
  WidgetTester tester,
  AppUser user, {
  List<AccountAction> actions = const [],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showAccountSheet(context, user: user, actions: actions),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a family sees its account and a red sign-out, nothing else', (
    tester,
  ) async {
    await _open(tester, _user(AppUser.roleFamily, 'Familia Ramírez'));

    expect(find.text('Mi cuenta'), findsOneWidget);
    expect(find.text('Familia Ramírez'), findsOneWidget);
    expect(find.text('cuenta@bamx.test'), findsOneWidget);
    expect(find.text('Familia'), findsOneWidget);
    expect(find.byType(SecondaryButton), findsNothing);
    final signOut = tester.widget<PrimaryButton>(
      find.widgetWithText(PrimaryButton, 'Cerrar sesión'),
    );
    expect(signOut.danger, isTrue);
    expect(
      tester
          .widget<Material>(
            find.descendant(
              of: find.byWidget(signOut),
              matching: find.byType(Material),
            ),
          )
          .color,
      AppColors.danger,
    );
  });

  testWidgets('the nutritionist sees their role', (tester) async {
    await _open(tester, _user(AppUser.roleNutritionist, 'Ana'));
    expect(find.text('Nutriólogo'), findsOneWidget);
    expect(find.byType(SecondaryButton), findsNothing);
  });

  testWidgets('a staff action closes the sheet and runs once', (tester) async {
    var calls = 0;
    await _open(
      tester,
      _user(AppUser.roleStaff, 'Staff BAMX'),
      actions: [
        (label: 'Familias', icon: AppIcons.home, onPressed: () => calls++),
      ],
    );
    expect(find.text('Staff'), findsOneWidget);

    await tester.tap(find.text('Familias'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Mi cuenta'), findsNothing);
  });
}
