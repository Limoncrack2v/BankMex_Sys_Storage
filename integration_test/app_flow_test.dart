// Prueba de punta a punta de la app contra los emuladores de Firebase.
//
// Requisitos (en otra terminal, desde la raíz del proyecto):
//   npm --prefix functions install          (una vez)
//   firebase emulators:start --only auth,firestore,functions
//   node tool/seed_emulators.mjs            (antes de cada corrida)
//
// El emulador de Functions es obligatorio: la Cloud Function
// onDeliveryWritten es la que llena la despensa al registrar una entrega.
// El seed deja otra vez programada la entrega que esta prueba entrega.
//
// Correr en un emulador o teléfono Android:
//   flutter test integration_test -d <id del dispositivo>
//
// Con capturas de pantalla (se guardan en build/e2e_screenshots):
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/app_flow_test.dart -d <id> \
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

const _takeScreenshots = bool.fromEnvironment('E2E_SCREENSHOTS');

// Cuenta de staff creada por tool/seed_emulators.mjs.
const _staffEmail = 'staff@bamx.test';
const _password = 'bamx1234';
const _signInTitle = 'Inicia sesión en tu cuenta BAMX';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'staff registra una familia y su entrega; la familia consume y registra integrantes',
    (tester) async {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await connectToEmulatorsIfDebug(
        auth: FirebaseAuth.instance,
        firestore: FirebaseFirestore.instance,
      );
      await FirebaseAuth.instance.signOut();
      final semantics = tester.ensureSemantics();

      final stamp = DateTime.now().millisecondsSinceEpoch;
      final familyName = 'Familia E2E $stamp';
      final familyEmail = 'e2e.$stamp@bamx.test';

      var surfaceConverted = false;
      Future<void> shot(String name) async {
        if (!_takeScreenshots) return;
        if (!surfaceConverted) {
          await binding.convertFlutterSurfaceToImage();
          surfaceConverted = true;
        }
        await tester.pump(const Duration(milliseconds: 500));
        await binding.takeScreenshot(name);
      }

      await tester.pumpWidget(const MyApp());
      await _waitFor(tester, find.text(_signInTitle));

      // 1. Inicio de sesión con credenciales incorrectas y correctas.
      await _signIn(tester, _staffEmail, 'incorrecta');
      await _waitFor(
        tester,
        find.text('Correo o contraseña inválidos. Intenta de nuevo.'),
      );
      await shot('01_login_incorrecto');

      await _signIn(tester, _staffEmail, _password);
      await _waitFor(tester, find.text('BAMX Guadalajara'));
      await _waitFor(tester, find.text('Familia Ramírez'));
      await shot('02_staff_entregas');

      // 2. El staff registra la cuenta de una familia nueva.
      await _tap(tester, find.text('Registrar cuenta'));
      await _waitFor(tester, find.text('Tipo de cuenta'));
      await _enter(tester, _fieldWithHint('Familia Ramírez'), familyName);
      await _enter(
        tester,
        _fieldWithHint('Calle, número y colonia'),
        'Calle Prueba 1, Guadalajara',
      );
      await _enter(tester, _fieldWithHint('correo@ejemplo.com'), familyEmail);
      await _enter(tester, _passwordField(), _password);
      await shot('03_registrar_cuenta');
      await _tap(tester, _primaryButton('Crear cuenta'));
      await _waitFor(
        tester,
        find.text('Cuenta creada'),
        timeout: const Duration(seconds: 40),
      );
      await shot('04_cuenta_creada');
      await _tap(tester, find.text('Listo'));

      // 3. Entrega ya entregada con un producto y su caducidad.
      await _selectFamily(tester, stamp, familyName);

      await _tap(tester, _pickerIn('Fecha de entrega'));
      await _confirmDatePicker(tester);

      await _tap(tester, find.text('Entregada').first);
      await _enter(tester, _fieldWithHint('Ej. Arroz'), 'Arroz');
      await _enter(tester, _fieldWithHint('0').last, '2');
      await _tap(tester, find.text('Elige la fecha'));
      await _confirmDatePicker(tester, daysAhead: 5);
      await shot('05_entrega_formulario');

      await _tap(tester, _primaryButton('Registrar entrega'));
      await _waitFor(tester, find.text('Entrega registrada'));
      await shot('06_entrega_registrada');
      await _tap(tester, find.text('Listo'));
      await _waitFor(tester, find.text(familyName));

      // Una entrega programada que después se cancela: sus productos no
      // llegan a la despensa.
      await _selectFamily(tester, stamp, familyName);
      await _tap(tester, _pickerIn('Fecha de entrega'));
      await _confirmDatePicker(tester);
      await _enter(tester, _fieldWithHint('Ej. Arroz'), 'Frijol');
      await _enter(tester, _fieldWithHint('0').last, '1');
      await _tap(tester, find.text('Elige la fecha'));
      await _confirmDatePicker(tester, daysAhead: 5);
      await _tap(tester, _primaryButton('Registrar entrega'));
      await _waitFor(tester, find.text('Entrega registrada'));
      await _tap(tester, find.text('Listo'));

      await _tap(tester, find.text('Cancelar').first);
      await _waitFor(tester, _primaryButton('Cancelar entrega'));
      expect(find.textContaining(familyName), findsWidgets);
      await _tap(tester, _primaryButton('Cancelar entrega'));
      await _waitFor(tester, find.text('Entrega cancelada'));
      await _tap(tester, find.text('Listo'));
      await _waitFor(tester, find.text('Cancelada'));

      // La entrega programada del seed se entrega, con confirmación.
      await _tap(tester, find.text('Entregar').first);
      await _waitFor(tester, find.text('Entregar despensa'));
      await shot('07_confirmar_entrega');
      await _tap(tester, _primaryButton('Confirmar entrega'));
      await _waitFor(tester, find.text('Entrega completada'));
      await _tap(tester, find.text('Listo'));
      await shot('08_tabla_entregas');

      // 4. Cerrar sesión del staff.
      await _tap(tester, find.byTooltip('Cuenta'));
      await _waitFor(tester, find.text('Mi cuenta'));
      await shot('09_mi_cuenta');
      await _tap(tester, find.text('Cerrar sesión'));
      await _waitFor(tester, find.text(_signInTitle));

      // 5. Recuperar contraseña.
      await _tap(tester, find.text('¿Olvidaste tu contraseña?'));
      await _waitFor(tester, find.text('Recuperar contraseña'));
      await _enter(tester, find.byType(TextField), familyEmail);
      await _tap(tester, _primaryButton('Enviar instrucciones'));
      await _waitFor(tester, find.text('Instrucciones enviadas'));
      await shot('10_instrucciones_enviadas');
      await _tap(tester, find.text('Listo'));
      await _waitFor(tester, find.text(_signInTitle));

      // 6. La familia nueva ve su despensa y registra consumo.
      await _signIn(tester, familyEmail, _password);
      await _waitFor(tester, find.text('Arroz'));
      expect(find.text('Quedan 2 kg'), findsOneWidget);
      expect(find.text('Caduca en 5 días'), findsOneWidget);
      // La entrega cancelada no llegó a la despensa.
      expect(find.text('Frijol'), findsNothing);
      await shot('11_despensa_familia');

      await _tap(tester, _primaryButton('Registrar consumo'));
      await _waitFor(tester, find.text('Buscar producto…'));
      await _tap(tester, find.bySemanticsLabel('Agregar consumo de Arroz'));
      expect(find.text('0.5 kg'), findsOneWidget);
      await shot('12_registrar_consumo');
      await _tap(tester, _primaryButton('Guardar consumo'));
      await _waitFor(tester, find.text('Consumo registrado'));
      await _tap(tester, find.text('Listo'));
      await _waitFor(tester, find.text('Quedan 1.5 kg'));

      // 7. Integrantes con edad, peso y alergias.
      await _tap(tester, find.text('Perfil'));
      await _waitFor(tester, find.text(familyName));
      await _waitFor(tester, find.text('Aún no hay integrantes registrados.'));
      await _tap(tester, find.text('Agregar integrante'));
      await _waitFor(tester, find.text('Tipo de integrante'));
      await _enter(tester, _fieldWithHint('Nombre del integrante'), 'Ana');
      await _enter(tester, _fieldWithHint('0').first, '30');
      await _enter(tester, _fieldWithHint('0').last, '60.5');
      await _tap(tester, find.text('Adulto'));
      await _tap(tester, find.text('Gluten'));
      await shot('13_agregar_integrante');
      await _tap(tester, _primaryButton('Guardar integrante'));
      await _waitFor(tester, find.text('Integrante añadido'));
      await _tap(tester, find.text('Listo'));
      await _waitFor(tester, find.text('Alergias: Gluten'));
      expect(find.text('30 años'), findsOneWidget);
      expect(find.text('60.5 kg'), findsOneWidget);
      await shot('14_perfil');

      await _tap(tester, find.text('Ana'));
      await _waitFor(tester, find.text('Editar integrante'));
      await _enter(tester, find.widgetWithText(TextField, '30'), '31');
      await _tap(tester, find.text('Ninguna'));
      await _tap(tester, _primaryButton('Guardar cambios'));
      await _waitFor(tester, find.text('Cambios guardados'));
      await _tap(tester, find.text('Listo'));
      await _waitFor(tester, find.text('31 años'));
      expect(find.textContaining('Alergias:'), findsNothing);

      // Un integrante que se agrega por error y se elimina.
      await _tap(tester, find.text('Agregar integrante'));
      await _waitFor(tester, find.text('Tipo de integrante'));
      await _enter(tester, _fieldWithHint('Nombre del integrante'), 'Beto');
      await _enter(tester, _fieldWithHint('0').first, '5');
      await _tap(tester, find.text('Niño'));
      await _tap(tester, find.text('Ninguna'));
      await _tap(tester, _primaryButton('Guardar integrante'));
      await _waitFor(tester, find.text('Integrante añadido'));
      await _tap(tester, find.text('Listo'));
      await _waitFor(tester, find.text('Beto'));
      await _tap(tester, find.text('Beto'));
      await _waitFor(tester, find.text('Editar integrante'));
      await _tap(tester, find.text('Eliminar integrante'));
      await _waitFor(tester, find.textContaining('¿Eliminar a Beto'));
      await shot('15_eliminar_integrante');
      await _tap(tester, find.text('Eliminar'));
      await _waitFor(tester, find.text('Integrante eliminado'));
      await _tap(tester, find.text('Listo'));
      await _waitFor(tester, find.text('Ana'));
      expect(find.text('Beto'), findsNothing);

      // 8. Recetas con la despensa real y plan de comidas.
      await _tap(tester, find.text('Recetas'));
      await _waitFor(tester, find.text('Recetas con lo que hay en tu despensa'));
      await _waitFor(tester, find.text('No hay recetas con este filtro.'));
      await _tap(tester, find.text('Todas'));
      await _waitFor(tester, find.text('Arroz con atún'));
      await shot('16_recetas');
      await _tap(tester, find.text('Plan de comidas').last);
      await _waitFor(tester, find.text('Tu plan usa primero lo que caduca antes'));
      await _waitFor(tester, find.textContaining('Usa Arroz'));
      await shot('17_plan_de_comidas');

      // 9. Cerrar sesión de la familia.
      await _tap(tester, find.text('Perfil'));
      await _tap(tester, find.text('Cerrar sesión'));
      await _waitFor(tester, find.text(_signInTitle));

      semantics.dispose();
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
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

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _waitFor(tester, finder);
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(finder.first);
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _enter(WidgetTester tester, Finder finder, String text) async {
  await _waitFor(tester, finder);
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.enterText(finder.first, text);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _signIn(WidgetTester tester, String email, String password) async {
  await _enter(tester, find.byType(TextField).at(0), email);
  await _enter(tester, find.byType(TextField).at(1), password);
  await _tap(tester, _primaryButton('Iniciar sesión'));
}

Future<void> _selectFamily(
  WidgetTester tester,
  int stamp,
  String familyName,
) async {
  final search = _fieldWithHint('Buscar familia registrada…');
  await _tap(tester, search);
  await _enter(tester, search, 'E2E $stamp');
  // La opción de la lista (tocable), no la fila de la tabla de entregas
  // que también muestra el nombre.
  final option = find.ancestor(
    of: find.text(familyName),
    matching: find.byType(InkWell),
  );
  await _waitFor(tester, option);
  await _tap(tester, option);
}

Finder _fieldWithHint(String hint) => find.widgetWithText(TextField, hint);

Finder _passwordField() => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.obscureText,
);

Finder _primaryButton(String label) =>
    find.widgetWithText(PrimaryButton, label);

/// El campo tocable (fecha) dentro del LabeledField con ese título.
Finder _pickerIn(String label) => find
    .descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is LabeledField && widget.label == label,
      ),
      matching: find.byType(InkWell),
    )
    .first;

/// Acepta el selector de fecha, opcionalmente eligiendo un día posterior del
/// mismo mes.
Future<void> _confirmDatePicker(WidgetTester tester, {int daysAhead = 0}) async {
  await _waitFor(tester, find.byType(DatePickerDialog));
  final target = DateTime.now().add(Duration(days: daysAhead));
  if (daysAhead > 0 && target.month == DateTime.now().month) {
    await tester.tap(
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.text('${target.day}'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.tap(
    find.byWidgetPredicate(
      (widget) => widget is Text && widget.data?.toLowerCase() == 'aceptar',
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}
