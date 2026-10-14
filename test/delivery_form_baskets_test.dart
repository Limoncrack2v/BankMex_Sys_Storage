import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/delivery.dart';
import 'package:bank_storage_app/data/models/family.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/data/models/standard_basket.dart';
import 'package:bank_storage_app/ui/formatting.dart';
import 'package:bank_storage_app/ui/screens/staff/deliveries_screen.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/app_text_field.dart';
import 'package:bank_storage_app/ui/widgets/standard_basket_selector.dart';

const _arroz = StandardBasketItem(
  productId: 'Arroz',
  type: FoodType.grain,
  quantity: 1,
  unit: FoodUnit.kg,
  shelfLifeDays: 365,
);
const _avena = StandardBasketItem(
  productId: 'Avena',
  type: FoodType.grain,
  quantity: 0.4,
  unit: FoodUnit.kg,
  shelfLifeDays: 270,
);
const _huevo = StandardBasketItem(
  productId: 'Huevo',
  type: FoodType.protein,
  quantity: 12,
  unit: FoodUnit.piece,
  shelfLifeDays: 21,
);

const _basica = StandardBasket(
  basketId: 'despensa-basica',
  name: 'Despensa básica',
  description: '',
  items: [_arroz, _avena],
);
const _frescos = StandardBasket(
  basketId: 'frescos',
  name: 'Frescos',
  description: '',
  items: [_huevo],
);

final _today = DateUtils.dateOnly(DateTime.now());

DateTime _in(int days) => DateTime(_today.year, _today.month, _today.day + days);

Future<void> _pumpForm(
  WidgetTester tester, {
  Stream<List<StandardBasket>>? baskets,
}) async {
  tester.view.physicalSize = const Size(900, 60000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: DeliveryForm(
            families: Stream.value(const <Family>[]),
            baskets: baskets ?? Stream.value(const [_basica, _frescos]),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pickBasket(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pump();
}

/// Elige la fecha de entrega: hoy si [day] es null, o ese día del mes
/// actual.
Future<void> _pickDate(WidgetTester tester, {int? day}) async {
  await tester.tap(find.bySemanticsLabel('Fecha de entrega'));
  await tester.pumpAndSettle();
  if (day != null) await tester.tap(find.text('$day'));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> _setPackages(WidgetTester tester, String text) async {
  final field = find.descendant(
    of: find.ancestor(
      of: find.text('Número de despensas *'),
      matching: find.byType(LabeledField),
    ),
    matching: find.byType(TextField),
  );
  await tester.enterText(field, text);
  await tester.pump();
}

Iterable<AppTextField> _fields(WidgetTester tester, String hint) => tester
    .widgetList<AppTextField>(find.byType(AppTextField))
    .where((field) => field.hint == hint);

List<String> _names(WidgetTester tester) => [
  for (final field in _fields(tester, 'Ej. Arroz')) field.controller.text,
];

/// Las cantidades de los productos (el primer campo con "0" es la cuota).
List<String> _quantities(WidgetTester tester) => [
  for (final field in _fields(tester, '0').skip(1)) field.controller.text,
];

AppTextField _nameField(WidgetTester tester, int index) =>
    _fields(tester, 'Ej. Arroz').elementAt(index);

/// Escribe la cantidad del producto [index] (el primer campo con "0" es la
/// cuota).
Future<void> _setQuantity(WidgetTester tester, int index, String text) async {
  await tester.enterText(
    find.byWidget(_fields(tester, '0').elementAt(index + 1)),
    text,
  );
  await tester.pump();
}

void main() {
  group('elegir las despensas', () {
    testWidgets('antes de la fecha no llena nada y la pide', (tester) async {
      await _pumpForm(tester);

      await _pickBasket(tester, 'Despensa básica');

      expect(
        find.text('Elige la fecha de entrega para llenar los productos.'),
        findsOneWidget,
      );
      expect(_names(tester), ['']);
    });

    testWidgets('al elegir la fecha llena los productos', (tester) async {
      await _pumpForm(tester);
      await _pickBasket(tester, 'Despensa básica');

      await _pickDate(tester);

      expect(_names(tester), ['Arroz', 'Avena']);
      expect(_quantities(tester), ['1', '0.4']);
      expect(
        find.text('Llenada con Despensa básica para 1 despensa (2 productos).'),
        findsOneWidget,
      );
    });

    testWidgets('varias despensas suman sus productos en una lista', (
      tester,
    ) async {
      await _pumpForm(tester);
      await _pickDate(tester);

      await _pickBasket(tester, 'Despensa básica');
      await _pickBasket(tester, 'Frescos');

      expect(_names(tester), ['Arroz', 'Avena', 'Huevo']);
      expect(
        find.text(
          'Llenada con Despensa básica y Frescos para 1 despensa '
          '(3 productos).',
        ),
        findsOneWidget,
      );
    });

    testWidgets('las cantidades salen multiplicadas por el número de despensas', (
      tester,
    ) async {
      await _pumpForm(tester);
      await _pickDate(tester);
      await _pickBasket(tester, 'Despensa básica');
      await _pickBasket(tester, 'Frescos');

      await _setPackages(tester, '3');

      expect(_quantities(tester), ['3', '1.2', '36']);

      await _setPackages(tester, '2');

      expect(_quantities(tester), ['2', '0.8', '24']);
    });

    testWidgets('con un número de despensas inválido espera sin tocar la lista', (
      tester,
    ) async {
      await _pumpForm(tester);
      await _pickDate(tester);
      await _pickBasket(tester, 'Despensa básica');

      await _setPackages(tester, '');

      expect(_quantities(tester), ['1', '0.4']);
      expect(
        find.text(
          'Indica de 1 a ${Delivery.maxPackages} despensas para llenar los '
          'productos.',
        ),
        findsOneWidget,
      );

      await _setPackages(tester, '4');

      expect(_quantities(tester), ['4', '1.6']);
    });

    testWidgets('la caducidad se cuenta desde la fecha de entrega', (
      tester,
    ) async {
      await _pumpForm(tester);
      await _pickBasket(tester, 'Despensa básica');
      await _pickBasket(tester, 'Frescos');

      await _pickDate(tester);

      expect(find.text(formatDateShort(_in(365))), findsOneWidget);
      expect(find.text(formatDateShort(_in(270))), findsOneWidget);
      expect(find.text(formatDateShort(_in(21))), findsOneWidget);
    });

    testWidgets('al cambiar la fecha una lista sin editar cambia sus caducidades', (
      tester,
    ) async {
      await _pumpForm(tester);
      await _pickBasket(tester, 'Frescos');
      await _pickDate(tester);
      final day = _today.day == 15 ? 16 : 15;
      final delivery = DateTime(_today.year, _today.month, day);

      await _pickDate(tester, day: day);

      final expiration = DateTime(delivery.year, delivery.month, day + 21);
      expect(find.text(formatDateShort(expiration)), findsOneWidget);
      expect(find.text(formatDateShort(_in(21))), findsNothing);
    });

    testWidgets('quitar la despensa vacía la lista que no se editó', (
      tester,
    ) async {
      await _pumpForm(tester);
      await _pickDate(tester);
      await _pickBasket(tester, 'Despensa básica');

      await _pickBasket(tester, 'Despensa básica');

      expect(_names(tester), ['']);
    });
  });

  group('lo que el staff ya editó', () {
    Future<void> editedForm(WidgetTester tester) async {
      await _pumpForm(tester);
      await _pickDate(tester);
      await _pickBasket(tester, 'Despensa básica');
      // Faltó la avena ese día: la quita.
      await tester.tap(find.byTooltip('Quitar producto').last);
      await tester.pump();
      expect(_names(tester), ['Arroz']);
    }

    testWidgets('cambiar el número de despensas no lo pisa y avisa', (
      tester,
    ) async {
      await editedForm(tester);

      await _setPackages(tester, '3');

      expect(_names(tester), ['Arroz']);
      expect(_quantities(tester), ['1']);
      expect(find.text(StandardBasketSelector.staleMessage), findsOneWidget);
    });

    testWidgets('elegir otra despensa no lo pisa y avisa', (tester) async {
      await editedForm(tester);

      await _pickBasket(tester, 'Frescos');

      expect(_names(tester), ['Arroz']);
      expect(find.text(StandardBasketSelector.staleMessage), findsOneWidget);
    });

    testWidgets('cambiar la fecha no lo pisa y avisa', (tester) async {
      await editedForm(tester);

      await _pickDate(tester, day: _today.day == 15 ? 16 : 15);

      expect(_names(tester), ['Arroz']);
      expect(find.text(StandardBasketSelector.staleMessage), findsOneWidget);
    });

    testWidgets('"Reemplazar productos" lo vuelve a llenar', (tester) async {
      await editedForm(tester);
      await _setPackages(tester, '3');

      await tester.tap(find.text('Reemplazar productos'));
      await tester.pump();

      expect(_names(tester), ['Arroz', 'Avena']);
      expect(_quantities(tester), ['3', '1.2']);
      expect(find.text(StandardBasketSelector.staleMessage), findsNothing);
    });

    testWidgets('un producto escrito a mano antes de elegir se conserva', (
      tester,
    ) async {
      await _pumpForm(tester);
      await _pickDate(tester);
      await tester.enterText(
        find.byWidget(_nameField(tester, 0)),
        'Galletas',
      );
      await tester.pump();

      await _pickBasket(tester, 'Despensa básica');

      expect(_names(tester), ['Galletas']);
      expect(find.text(StandardBasketSelector.staleMessage), findsOneWidget);
    });

    testWidgets('quitar todas las despensas no borra lo editado', (
      tester,
    ) async {
      await editedForm(tester);

      await _pickBasket(tester, 'Despensa básica');

      expect(_names(tester), ['Arroz']);
      expect(find.text(StandardBasketSelector.staleMessage), findsNothing);
    });
  });

  group('deshacer lo que el staff editó', () {
    const llenadaPara1 =
        'Llenada con Despensa básica para 1 despensa (2 productos).';
    const llenadaPara2 =
        'Llenada con Despensa básica para 2 despensas (2 productos).';

    Future<void> filledForm(WidgetTester tester) async {
      await _pumpForm(tester);
      await _pickDate(tester);
      await _pickBasket(tester, 'Despensa básica');
    }

    testWidgets('con otro número de despensas sigue el aviso y se puede '
        'reemplazar', (tester) async {
      // Paso 1: llenada para 1 despensa.
      await filledForm(tester);
      expect(_quantities(tester), ['1', '0.4']);
      expect(find.text(StandardBasketSelector.staleMessage), findsNothing);
      expect(find.text(llenadaPara1), findsOneWidget);

      // Paso 2: el staff cambia la avena.
      await _setQuantity(tester, 1, '0.5');
      expect(_quantities(tester), ['1', '0.5']);
      expect(find.text(StandardBasketSelector.staleMessage), findsNothing);
      expect(find.text(llenadaPara1), findsNothing);

      // Paso 3: cambia el número de despensas; la lista no se toca y avisa.
      await _setPackages(tester, '2');
      expect(_quantities(tester), ['1', '0.5']);
      expect(find.text(StandardBasketSelector.staleMessage), findsOneWidget);
      expect(find.text('Reemplazar productos'), findsOneWidget);

      // Paso 4: deshace la avena. La lista vuelve a lo de 1 despensa, que no
      // es lo de 2: el aviso y el botón siguen.
      await _setQuantity(tester, 1, '0.4');
      expect(_quantities(tester), ['1', '0.4']);
      expect(find.text(StandardBasketSelector.staleMessage), findsOneWidget);
      expect(find.text('Reemplazar productos'), findsOneWidget);
      expect(find.text(llenadaPara1), findsNothing);
      expect(find.text(llenadaPara2), findsNothing);

      await tester.tap(find.text('Reemplazar productos'));
      await tester.pump();

      expect(_quantities(tester), ['2', '0.8']);
      expect(find.text(StandardBasketSelector.staleMessage), findsNothing);
      expect(find.text('Reemplazar productos'), findsNothing);
      expect(find.text(llenadaPara2), findsOneWidget);
    });

    testWidgets('con otra despensa elegida sigue el aviso y se puede '
        'reemplazar', (tester) async {
      await filledForm(tester);
      await _setQuantity(tester, 1, '0.5');
      await _pickBasket(tester, 'Frescos');
      expect(_names(tester), ['Arroz', 'Avena']);
      expect(find.text(StandardBasketSelector.staleMessage), findsOneWidget);

      await _setQuantity(tester, 1, '0.4');

      expect(_names(tester), ['Arroz', 'Avena']);
      expect(find.text(StandardBasketSelector.staleMessage), findsOneWidget);
      expect(find.text('Reemplazar productos'), findsOneWidget);

      await tester.tap(find.text('Reemplazar productos'));
      await tester.pump();

      expect(_names(tester), ['Arroz', 'Avena', 'Huevo']);
      expect(find.text(StandardBasketSelector.staleMessage), findsNothing);
    });

    testWidgets('si la lista vuelve a lo que toca, el aviso se quita y sale '
        'la nota', (tester) async {
      await filledForm(tester);
      await _setQuantity(tester, 1, '0.5');
      await _setPackages(tester, '2');
      expect(find.text(StandardBasketSelector.staleMessage), findsOneWidget);

      // Con la avena editada, volver a 1 despensa sigue sin coincidir.
      await _setPackages(tester, '1');
      expect(find.text(StandardBasketSelector.staleMessage), findsOneWidget);

      // Al deshacer la avena la lista es justo la de 1 despensa.
      await _setQuantity(tester, 1, '0.4');

      expect(_quantities(tester), ['1', '0.4']);
      expect(find.text(StandardBasketSelector.staleMessage), findsNothing);
      expect(find.text(llenadaPara1), findsOneWidget);
    });
  });

  group('el límite de productos', () {
    final huge = StandardBasket(
      basketId: 'huge',
      name: 'Enorme',
      description: '',
      items: [
        for (var i = 0; i <= Delivery.maxItems; i++)
          StandardBasketItem(
            productId: 'Producto $i',
            type: FoodType.other,
            quantity: 1,
            unit: FoodUnit.piece,
            shelfLifeDays: 30,
          ),
      ],
    );
    final full = StandardBasket(
      basketId: 'full',
      name: 'Completa',
      description: '',
      items: [
        for (var i = 0; i < Delivery.maxItems; i++)
          StandardBasketItem(
            productId: 'Producto $i',
            type: FoodType.other,
            quantity: 1,
            unit: FoodUnit.piece,
            shelfLifeDays: 30,
          ),
      ],
    );

    testWidgets('si las despensas pasan del límite no se llena y lo dice', (
      tester,
    ) async {
      await _pumpForm(tester, baskets: Stream.value([huge]));
      await _pickDate(tester);

      await _pickBasket(tester, 'Enorme');

      expect(_names(tester), ['']);
      expect(
        find.textContaining(
          'suman ${Delivery.maxItems + 1} productos; una entrega acepta hasta '
          '${Delivery.maxItems}',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('con la lista llena ya no deja agregar productos', (
      tester,
    ) async {
      await _pumpForm(tester, baskets: Stream.value([full]));
      await _pickDate(tester);

      await _pickBasket(tester, 'Completa');

      expect(_names(tester), hasLength(Delivery.maxItems));
      expect(
        find.text(
          'Una entrega acepta hasta ${Delivery.maxItems} productos. Quita uno '
          'para agregar otro.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Quitar producto').first);
      await tester.pump();

      expect(_names(tester), hasLength(Delivery.maxItems - 1));
      expect(find.textContaining('Una entrega acepta hasta'), findsNothing);
    });
  });

  group('sin despensas disponibles', () {
    testWidgets('mientras cargan se puede capturar a mano', (tester) async {
      final controller = StreamController<List<StandardBasket>>();
      addTearDown(controller.close);
      await _pumpForm(tester, baskets: controller.stream);

      expect(find.text('Cargando despensas estándar…'), findsOneWidget);
      await tester.tap(find.text('Agregar producto'));
      await tester.pump();

      expect(_names(tester), ['', '']);
    });

    testWidgets('si la carga falla lo dice y se puede capturar a mano', (
      tester,
    ) async {
      await _pumpForm(
        tester,
        baskets: Stream<List<StandardBasket>>.error(StateError('sin conexión')),
      );
      await tester.pump();

      expect(find.text(StandardBasketSelector.errorMessage), findsOneWidget);
      await tester.tap(find.text('Agregar producto'));
      await tester.pump();

      expect(_names(tester), ['', '']);
    });

    testWidgets('si no hay ninguna lo dice y se puede capturar a mano', (
      tester,
    ) async {
      await _pumpForm(tester, baskets: Stream.value(const []));

      expect(find.text(StandardBasketSelector.emptyMessage), findsOneWidget);
      await tester.tap(find.text('Agregar producto'));
      await tester.pump();

      expect(_names(tester), ['', '']);
    });
  });
}
