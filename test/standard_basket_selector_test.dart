import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/standard_basket.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/option_button.dart';
import 'package:bank_storage_app/ui/widgets/standard_basket_selector.dart';

const _basica = StandardBasket(
  basketId: 'despensa-basica',
  name: 'Despensa básica',
  description: '',
  items: [],
);
const _frescos = StandardBasket(
  basketId: 'frescos',
  name: 'Frescos',
  description: '',
  items: [],
);

Future<void> _pump(
  WidgetTester tester, {
  List<StandardBasket>? baskets = const [_basica, _frescos],
  bool hasError = false,
  Set<String> selectedIds = const {},
  ValueChanged<StandardBasket>? onToggle,
  String? message,
  String? problem,
  bool staleNotice = false,
  VoidCallback? onRefill,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: StandardBasketSelector(
          baskets: baskets,
          hasError: hasError,
          selectedIds: selectedIds,
          onToggle: onToggle ?? (_) {},
          message: message,
          problem: problem,
          staleNotice: staleNotice,
          onRefill: onRefill,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('muestra una opción por despensa y marca las elegidas', (
    tester,
  ) async {
    await _pump(tester, selectedIds: {'frescos'});

    expect(find.text('Despensa básica'), findsOneWidget);
    expect(find.text('Frescos'), findsOneWidget);
    bool selected(String name) => tester
        .widget<OptionButton>(find.widgetWithText(OptionButton, name))
        .selected;
    expect(selected('Frescos'), isTrue);
    expect(selected('Despensa básica'), isFalse);
  });

  testWidgets('al tocar una opción avisa con su despensa', (tester) async {
    StandardBasket? toggled;
    await _pump(tester, onToggle: (basket) => toggled = basket);

    await tester.tap(find.text('Frescos'));

    expect(toggled, _frescos);
  });

  testWidgets('mientras cargan muestra que están cargando', (tester) async {
    await _pump(tester, baskets: null);

    expect(find.text('Cargando despensas estándar…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('si falló la carga y no hay nada, dice que se agreguen a mano', (
    tester,
  ) async {
    await _pump(tester, baskets: null, hasError: true);

    expect(find.text(StandardBasketSelector.errorMessage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('si hubo un error pero ya hay despensas las sigue mostrando', (
    tester,
  ) async {
    await _pump(tester, hasError: true);

    expect(find.text('Despensa básica'), findsOneWidget);
    expect(find.text(StandardBasketSelector.errorMessage), findsNothing);
  });

  testWidgets('sin despensas dice que se agreguen a mano', (tester) async {
    await _pump(tester, baskets: const []);

    expect(find.text(StandardBasketSelector.emptyMessage), findsOneWidget);
  });

  testWidgets('el aviso de lista editada ofrece reemplazar los productos', (
    tester,
  ) async {
    var refilled = 0;
    await _pump(tester, staleNotice: true, onRefill: () => refilled++);

    expect(find.text(StandardBasketSelector.staleMessage), findsOneWidget);
    await tester.tap(find.text('Reemplazar productos'));

    expect(refilled, 1);
  });

  testWidgets('un problema reemplaza al aviso de lista editada', (
    tester,
  ) async {
    await _pump(
      tester,
      staleNotice: true,
      problem: 'Suman demasiados productos.',
      message: 'Un mensaje.',
    );

    expect(find.text('Suman demasiados productos.'), findsOneWidget);
    expect(find.text('Un mensaje.'), findsNothing);
    expect(find.text(StandardBasketSelector.staleMessage), findsNothing);
  });
}
