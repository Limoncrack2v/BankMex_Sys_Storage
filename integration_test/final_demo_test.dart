// Demo de la presentación final (22 de octubre).
//
// Recorre la demo en vivo en el mismo orden que el guion del video de
// respaldo, contra los emuladores con el seed, y guarda una captura por paso
// (demo_NN_..., en build/e2e_screenshots) para las láminas. Si pasa, el seed
// alcanza para cada paso de la demo.
//
// Necesita emuladores recién iniciados, sin --import (crea la cuenta de la
// Familia Navarro con un correo fijo), y el seed (en otra terminal, desde la
// raíz del proyecto):
//   firebase emulators:start --only auth,firestore,functions
//   node tool/seed_emulators.mjs
//
// Correr en el emulador de Android (capturas en build/e2e_screenshots):
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/final_demo_test.dart -d emulator-5554 \
//     --dart-define=E2E_SCREENSHOTS=true
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bank_storage_app/data/firebase_environment.dart';
import 'package:bank_storage_app/firebase_options.dart';
import 'package:bank_storage_app/main.dart';
import 'package:bank_storage_app/ui/widgets/app_buttons.dart';
import 'package:bank_storage_app/ui/widgets/app_text_field.dart';
import 'package:bank_storage_app/ui/widgets/option_button.dart';

const _takeScreenshots = bool.fromEnvironment('E2E_SCREENSHOTS');

// Cuentas creadas por tool/seed_emulators.mjs.
const _password = 'bamx1234';
const _staffEmail = 'staff@bamx.test';
const _ramirezEmail = 'familia.ramirez@bamx.test';
const _nutritionistEmail = 'nutriologo@bamx.test';
const _requestEmail = 'solicitud.staff@bamx.test';

// La cuenta que crea la demo. El seed ya tiene una Familia Hernández (sin
// cuenta), así que la familia nueva usa un apellido que no está ahí.
const _newFamilyName = 'Familia Navarro';
const _newFamilyEmail = 'familia.navarro@bamx.test';

const _signInTitle = 'Inicia sesión en tu cuenta BAMX';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('demo de la presentación final', (tester) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await connectToEmulatorsIfDebug(
      auth: FirebaseAuth.instance,
      firestore: FirebaseFirestore.instance,
    );
    await FirebaseAuth.instance.signOut();
    final semantics = tester.ensureSemantics();

    var surfaceConverted = false;
    Future<void> shot(String name) async {
      if (!_takeScreenshots) return;
      if (!surfaceConverted) {
        await binding.convertFlutterSurfaceToImage();
        surfaceConverted = true;
      }
      // Varios frames: la captura toma lo último dibujado, y una animación
      // recién empezada (o una imagen que apenas cargó) saldría a medias.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      await binding.takeScreenshot(name);
    }

    await tester.pumpWidget(const MyApp());
    await _waitFor(tester, find.text(_signInTitle));

    // 1. Staff: el error de inicio de sesión no dice qué estuvo mal.
    await _signIn(tester, _staffEmail, 'incorrecta');
    await _waitFor(
      tester,
      find.text('Correo o contraseña inválidos. Intenta de nuevo.'),
    );
    await shot('demo_01_wrong_password');
    await _signIn(tester, _staffEmail, _password);
    await _retryIfSignInFailed(tester);
    await _waitFor(
      tester,
      find.textContaining('de cuenta de staff por revisar'),
    );
    await shot('demo_02_staff_home');

    // 2. Aprueba la solicitud de staff del seed (Laura Méndez).
    await _tap(tester, find.text('Revisar'));
    await _waitFor(tester, find.text(_requestEmail));
    await shot('demo_03_staff_requests');
    final requestCard = find.ancestor(
      of: find.text(_requestEmail),
      matching: find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_RequestCard',
      ),
    );
    await _tap(
      tester,
      find.descendant(of: requestCard, matching: find.text('Aprobar')),
    );
    await _tapButton(tester, _primaryButton('Aprobar solicitud'));
    await _confirmIdentityIfAsked(tester, _password);
    await _waitFor(tester, find.text('Solicitud aprobada'));
    await _tap(tester, find.text('Listo'));
    await _waitFor(tester, find.text('Solicitudes de staff'));
    await _tap(tester, find.byTooltip('Cerrar'));

    // 3. Las familias no se registran solas: el staff crea su cuenta.
    await _tap(tester, find.text('Registrar cuenta'));
    await _waitFor(tester, find.text('Tipo de cuenta'));
    await _enter(tester, _fieldWithHint('Familia Ramírez'), _newFamilyName);
    await _enter(
      tester,
      _fieldWithHint('Calle, número y colonia'),
      'Calle Robles 45, Tlaquepaque',
    );
    await _enter(tester, _fieldWithHint('correo@ejemplo.com'), _newFamilyEmail);
    await _enter(tester, _passwordField(), _password);
    await shot('demo_04_register_family');
    await _tapButton(tester, _primaryButton('Crear cuenta'));
    await _confirmIdentityIfAsked(tester, _password);
    await _waitFor(
      tester,
      find.text('Cuenta creada'),
      timeout: const Duration(seconds: 40),
    );
    await _tap(tester, find.text('Listo'));

    // 4. Entrega de hoy para los Ramírez: el formulario propone su cuota
    // ($250, pide justificación) y las dos despensas llenan los 16 productos.
    final search = _fieldWithHint('Buscar familia registrada…');
    await _tap(tester, search);
    await _enter(tester, search, 'Ramírez');
    final ramirezOption = find.ancestor(
      of: find.text('Familia Ramírez'),
      matching: find.byType(InkWell),
    );
    await _waitFor(tester, ramirezOption);
    await _tap(tester, ramirezOption);
    await _enter(tester, _justificationField(), 'Cuota estándar');
    await _tap(tester, _pickerIn('Fecha de entrega'));
    await _confirmDatePicker(tester);
    await _tap(tester, _basket('Despensa básica'));
    await _tap(tester, _basket('Frescos'));
    await _waitFor(tester, find.widgetWithText(TextField, 'Huevo'));
    await _tap(tester, find.text('Entregada').first);
    await tester.ensureVisible(_basket('Frescos'));
    await shot('demo_05_delivery_baskets');
    await _tapButton(tester, _primaryButton('Registrar entrega'));
    await _waitFor(tester, find.text('Entrega registrada'));
    await shot('demo_06_delivery_registered');
    await _tap(tester, find.text('Listo'));

    // 5. Estadísticas del programa: consumido contra desperdiciado.
    await _tap(tester, find.text('Estadísticas'));
    await _waitFor(tester, find.text('Kg aprovechados'));
    await shot('demo_07_stats');
    await _scrollTo(tester, find.text('Tendencias de consumo'));
    await shot('demo_08_stats_trends');

    await _tap(tester, find.byTooltip('Cuenta'));
    await _tap(tester, find.text('Cerrar sesión'));
    await _waitFor(tester, find.text(_signInTitle));

    // 6. La familia: la Cloud Function ya llenó su despensa con la entrega.
    await _signIn(tester, _ramirezEmail, _password);
    await _retryIfSignInFailed(tester);
    // La cebolla solo viene en "Frescos": prueba que la Cloud Function llenó
    // la despensa. Después se regresa arriba para la captura.
    final banner = find.text('Tu próxima entrega');
    await _scrollDownTo(tester, find.text('Cebolla'), list: banner);
    // Arrastrar y no ensureVisible: este alinea el aviso al borde y corta el
    // margen de arriba de la lista.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 5000));
    await _waitFor(tester, banner);
    await shot('demo_09_pantry');

    // 7. Tocar un producto abre "Registrar consumo" con ese producto.
    await _tap(tester, find.text('Leche entera'));
    await _waitFor(tester, _primaryButton('Guardar consumo'));
    await _tap(
      tester,
      find.bySemanticsLabel('Agregar consumo de Leche entera'),
    );
    await shot('demo_10_consumption');
    await _tapButton(tester, _primaryButton('Guardar consumo'));
    await _waitFor(tester, find.text('Consumo registrado'));
    await _tap(tester, find.text('Listo'));

    // 8. El plan guardado: cambiar un día solo ofrece recetas sin alérgenos.
    await _tap(tester, find.text('Plan de comidas').last);
    await _waitFor(tester, find.text('Cambiar'));
    await shot('demo_11_saved_plan');
    await _tap(tester, find.text('Cambiar'));
    await _waitFor(tester, find.text('Dejar este día libre'));
    await shot('demo_12_change_day');
    await _tap(tester, find.text('Dejar este día libre'));
    await _waitFor(tester, find.text('Día libre'));
    await _scrollDownTo(
      tester,
      find.text('Lo que te sobra'),
      list: find.text('Día libre'),
    );
    await shot('demo_13_leftovers');

    // 9. Recetas con lo que hay, porciones del hogar y "Pedir una receta".
    await _tap(tester, find.text('Recetas').last);
    await _waitFor(
      tester,
      find.text('Recetas con lo que hay en tu despensa'),
    );
    final requestRecipe = _primaryButton('Pedir una receta');
    await _waitFor(tester, requestRecipe);
    await shot('demo_14_recipes');
    await _tapButton(tester, requestRecipe);
    await _waitFor(tester, find.text('Te sugerimos'));
    await shot('demo_15_request_recipe');
    await _tap(tester, find.textContaining('Volver'));
    // Las recetas van debajo de "Pedir una receta" y los filtros.
    await _scrollDownTo(
      tester,
      find.text('Sopa de lentejas'),
      list: requestRecipe,
    );
    await _tap(tester, find.text('Sopa de lentejas'));
    await _waitFor(tester, find.text('Adaptado al tamaño de tu hogar'));
    await shot('demo_16_recipe_detail');
    await _tap(tester, find.textContaining('Volver'));

    // 10. Perfil: integrantes con alergias y enfermedades crónicas.
    await _tap(tester, find.text('Perfil'));
    await _waitFor(tester, find.text('María'));
    await shot('demo_17_profile');
    await _scrollDownTo(
      tester,
      find.text('Electrodomésticos'),
      list: find.text('María'),
    );
    await shot('demo_18_appliances');
    await _tap(tester, find.text('Cerrar sesión'));
    await _waitFor(tester, find.text(_signInTitle));

    // 11. El nutriólogo entra a su propia pantalla.
    await _signIn(tester, _nutritionistEmail, _password);
    await _retryIfSignInFailed(tester);
    await _waitFor(tester, find.text('Nutriólogo'));
    await shot('demo_19_nutritionist');
    await _tap(tester, find.text('Cerrar sesión'));
    await _waitFor(tester, find.text(_signInTitle));

    semantics.dispose();
  }, timeout: const Timeout(Duration(minutes: 6)));
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('No apareció en pantalla: $finder');
}

/// Toca un botón: primero cierra el teclado, porque con él abierto la
/// pantalla sigue moviéndose y el toque cae donde el botón ya no está.
Future<void> _tapButton(WidgetTester tester, Finder finder) async {
  final focus = FocusManager.instance.primaryFocus;
  if (focus != null && focus.hasFocus) {
    focus.unfocus();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }
  await _tap(tester, finder);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _scrollTo(tester, finder);
  await tester.tap(finder.first);
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await _waitFor(tester, finder);
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Baja por la lista que contiene [list] hasta construir [finder]: las listas
/// largas son perezosas y lo que no se ve todavía no existe.
Future<void> _scrollDownTo(
  WidgetTester tester,
  Finder finder, {
  required Finder list,
}) async {
  await _waitFor(tester, list);
  // El elemento de la lista, no un finder relativo a [list]: al bajar, [list]
  // sale de pantalla y deja de existir.
  final scrollable = find
      .ancestor(of: list.first, matching: find.byType(Scrollable))
      .evaluate()
      .first;
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byElementPredicate(
      (element) => identical(element, scrollable),
    ),
  );
  await _scrollTo(tester, finder);
}

Future<void> _enter(WidgetTester tester, Finder finder, String text) async {
  await _waitFor(tester, finder);
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.enterText(finder.first, text);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _signIn(WidgetTester tester, String email, String password) async {
  await _enter(tester, find.byType(TextField).at(0), email);
  await _enter(tester, find.byType(TextField).at(1), password);
  await _tapButton(tester, _primaryButton('Iniciar sesión'));
}

/// Contra el emulador de Auth, un inicio de sesión a veces falla con
/// "unexpected end of stream": Android reusa una conexión que el emulador ya
/// cerró. Se reintenta una vez, como lo haría quien presenta la demo.
Future<void> _retryIfSignInFailed(WidgetTester tester) async {
  final failed = find.text('No se pudo iniciar sesión. Intenta de nuevo.');
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (find.text(_signInTitle).evaluate().isEmpty) return;
    if (failed.evaluate().isNotEmpty) {
      await _tapButton(tester, _primaryButton('Iniciar sesión'));
      return;
    }
  }
}

/// Las acciones sensibles del staff piden la contraseña cuando el inicio de
/// sesión ya tiene 4 minutos o más. Si apareció el sheet, lo confirma.
Future<void> _confirmIdentityIfAsked(
  WidgetTester tester,
  String password,
) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  if (find.text('Confirma tu identidad').evaluate().isEmpty) return;
  await _enter(tester, _passwordField().last, password);
  await _tapButton(tester, _primaryButton('Confirmar'));
}

Finder _fieldWithHint(String hint) => find.widgetWithText(TextField, hint);

Finder _justificationField() =>
    _fieldWithHint('Motivo del monto (nivel de ingreso, tipo de entrega…)');

Finder _passwordField() => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.obscureText,
);

Finder _primaryButton(String label) =>
    find.widgetWithText(PrimaryButton, label);

Finder _basket(String name) => find.widgetWithText(OptionButton, name);

/// El campo tocable (fecha) dentro del LabeledField con ese título.
Finder _pickerIn(String label) => find
    .descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is LabeledField && widget.label == label,
      ),
      matching: find.byType(InkWell),
    )
    .first;

Future<void> _confirmDatePicker(WidgetTester tester) async {
  await _waitFor(tester, find.byType(DatePickerDialog));
  await tester.tap(
    find.byWidgetPredicate(
      (widget) => widget is Text && widget.data?.toLowerCase() == 'aceptar',
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}
