import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/ui/screens/sign_in/sign_in_screen.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';

const _iphone = Size(402, 874);
const _notice =
    'Tu cuenta fue creada por BAMX Guadalajara. Si aún no tienes los datos '
    'de inicio de sesión, acude a tu centro de distribución BAMX.';

/// Alto del pie con el espacio que el sistema reserva abajo (el indicador
/// del iPhone son 34).
Future<double> _footerHeight(WidgetTester tester, double systemBottom) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: _iphone,
          padding: EdgeInsets.only(bottom: systemBottom),
        ),
        child: const Scaffold(
          body: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [AuthFooter(_notice)],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getSize(find.byType(AuthFooter)).height;
}

void main() {
  group('fittingFontSize', () {
    test('toma el primer tamaño que cabe', () {
      expect(
        fittingFontSize(
          sizes: const [15, 14, 13],
          available: 100,
          // Ancho proporcional al tamaño de letra: a 15 mide 105, a 14 mide 98.
          measure: (size) => size * 7,
        ),
        14,
      );
    });

    test('prefiere el más grande cuando cabe', () {
      expect(
        fittingFontSize(
          sizes: const [15, 14, 13],
          available: 200,
          measure: (size) => size * 7,
        ),
        15,
      );
    });

    test('regresa null si no cabe ni el más chico (se irá a varios renglones)', () {
      expect(
        fittingFontSize(
          sizes: const [15, 14, 13],
          available: 50,
          measure: (size) => size * 7,
        ),
        isNull,
      );
    });

    test('sin ancho definido usa el tamaño preferido', () {
      expect(
        fittingFontSize(
          sizes: const [15, 14, 13],
          available: double.infinity,
          measure: (size) => size * 7,
        ),
        15,
      );
    });
  });

  testWidgets('el aviso del pie absorbe el espacio del sistema, no lo suma', (
    tester,
  ) async {
    final sinEspacio = await _footerHeight(tester, 0);
    final conIndicador = await _footerHeight(tester, 34);

    // Con 20 de padding propio, un indicador de 34 solo agrega los 14 que
    // faltan; antes sumaba los 34 completos.
    expect(conIndicador - sinEspacio, closeTo(14, 0.5));
  });

  testWidgets('el error no se desborda aunque el ancho sea muy chico', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              child: AuthErrorMessage(
                'Correo o contraseña inválidos. Intenta de nuevo.',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AuthErrorMessage), findsOneWidget);
  });

  testWidgets('al aparecer, el error se ve (no queda en alto cero)', (
    tester,
  ) async {
    tester.view.physicalSize = _iphone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const SignInScreen()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'maria@correo.com');
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.pump();
    // Sin Firebase, iniciar sesión falla y muestra el error.
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.byType(AuthErrorMessage), findsOneWidget);
    expect(
      tester.getSize(find.byType(AuthErrorMessage)).height,
      greaterThan(20),
      reason: 'el recuadro del error debe tener alto',
    );
    expect(
      tester.getSize(find.byType(AnimatedSize).first).height,
      greaterThan(20),
      reason: 'el espacio del error debe crecer al aparecer',
    );
  });

  testWidgets('sin error, el espacio del error no deja hueco', (tester) async {
    tester.view.physicalSize = _iphone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const SignInScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AuthErrorMessage), findsNothing);
    expect(
      tester.getSize(find.byType(AnimatedSize).first).height,
      0,
      reason: 'el lugar del error debe medir 0 mientras no hay error',
    );
  });
}
