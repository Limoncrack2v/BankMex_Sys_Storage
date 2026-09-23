// Pruebas de firestore.rules para las solicitudes de cuenta de staff
// (pantalla "Registro de Staff"), contra el emulador de Firestore
// (127.0.0.1:8080).
//
// Uso: flutter test test_emulator/rules_staff_requests_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'support/emulator.dart';

// ---------------------------------------------------------------------------
// Datos de ejemplo (los mismos del suite de Node)
// ---------------------------------------------------------------------------

Map<String, Object?> now() => ts(DateTime.utc(2026, 9, 21, 12));

Map<String, Map<String, Object?>> profile(
  String role, [
  Map<String, Map<String, Object?>> extra = const {},
]) => {
  'name': str('Nombre'),
  'email': str('x@y.com'),
  'role': str(role),
  'createdAt': now(),
  ...extra,
};

Map<String, Map<String, Object?>> solicitud([
  Map<String, Map<String, Object?>> extra = const {},
]) => {
  'name': str('Nueva Staff'),
  'email': str('nueva@bamx.test'),
  'status': str('pending'),
  'createdAt': now(),
  ...extra,
};

// Sesiones. La de "nueva" lleva su correo en el token porque la regla de
// creación lo compara con el de la solicitud.
Db staff() => Db.user('staff1');
Db fam1() => Db.user('fam1');
Db nueva() => Db.user('nueva', email: 'nueva@bamx.test');
Db anon() => Db.anonymous();

/// Datos que existen antes de cada caso (el beforeEach del suite de Node, solo
/// con lo que necesita este grupo).
Future<void> seed() async {
  final db = Db.admin();
  await db.setDoc('users/staff1', profile('staff'));
  await db.setDoc('users/fam1', profile('family'));
}

/// Una solicitud pendiente ya guardada, sin pasar por las reglas.
Future<void> seedRequest() =>
    Db.admin().setDoc('staffRequests/nueva', solicitud());

void main() {
  useProject('demo-bamx-staff-requests');

  setUpAll(requireEmulator);
  setUp(() async {
    await clearFirestore();
    await seed();
  });

  group('solicitudes de staff (Registro de Staff)', () {
    // Aprobar es un batch: el perfil users/{uid} con rol staff + la solicitud
    // marcada como aprobada (la regla usa getAfter sobre el perfil).
    Future<int> approve(
      Db db, [
      String uid = 'staff1',
      String profileRole = 'staff',
    ]) => db.commit([
      setWrite(
        'users/nueva',
        profile(profileRole, {
          'name': str('Nueva Staff'),
          'email': str('nueva@bamx.test'),
        }),
      ),
      updateWrite('staffRequests/nueva', {
        'status': str('approved'),
        'reviewedBy': str(uid),
        'reviewedAt': serverTimestamp,
      }),
    ]);

    test('la persona crea su propia solicitud', () async {
      await assertAllowed(nueva().setDoc('staffRequests/nueva', solicitud()));
    });

    test('no puede crear la solicitud de otra cuenta', () async {
      await assertDenied(nueva().setDoc('staffRequests/otra', solicitud()));
    });

    test('el correo debe ser el de su cuenta', () async {
      await assertDenied(
        nueva().setDoc(
          'staffRequests/nueva',
          solicitud({'email': str('otro@bamx.test')}),
        ),
      );
    });

    test('no puede crearla ya aprobada', () async {
      await assertDenied(
        nueva().setDoc(
          'staffRequests/nueva',
          solicitud({'status': str('approved')}),
        ),
      );
    });

    test('campo extra rechazado (p. ej. role)', () async {
      await assertDenied(
        nueva().setDoc(
          'staffRequests/nueva',
          solicitud({'role': str('staff')}),
        ),
      );
    });

    test('sin sesión no se crea', () async {
      await assertDenied(anon().setDoc('staffRequests/nueva', solicitud()));
    });

    test('la persona sigue sin poder crearse su perfil de staff', () async {
      await assertDenied(nueva().setDoc('users/nueva', profile('staff')));
    });

    test('una cuenta que ya tiene perfil no puede solicitar', () async {
      await assertDenied(
        fam1().setDoc(
          'staffRequests/fam1',
          solicitud({'email': str('x@y.com')}),
        ),
      );
    });

    test('la persona lee su solicitud', () async {
      await seedRequest();
      await assertAllowed(nueva().getDoc('staffRequests/nueva'));
    });

    test('otra cuenta no la lee', () async {
      await seedRequest();
      await assertDenied(fam1().getDoc('staffRequests/nueva'));
    });

    test('el staff lista las pendientes', () async {
      await seedRequest();
      await assertAllowed(
        staff().listDocs('staffRequests', where: ('status', str('pending'))),
      );
    });

    test('la persona no puede aprobarse', () async {
      await seedRequest();
      await assertDenied(
        nueva().updateDoc('staffRequests/nueva', {
          'status': str('approved'),
          'reviewedBy': str('nueva'),
          'reviewedAt': serverTimestamp,
        }),
      );
    });

    test(
      'staff aprueba: perfil de staff + solicitud aprobada en un batch',
      () async {
        await seedRequest();
        await assertAllowed(approve(staff()));
      },
    );

    test('aprobar sin crear el perfil rechazado', () async {
      await seedRequest();
      await assertDenied(
        staff().updateDoc('staffRequests/nueva', {
          'status': str('approved'),
          'reviewedBy': str('staff1'),
          'reviewedAt': serverTimestamp,
        }),
      );
    });

    test('aprobar creando un perfil de familia rechazado', () async {
      await seedRequest();
      await assertDenied(approve(staff(), 'staff1', 'family'));
    });

    test('reviewedBy debe ser quien revisa', () async {
      await seedRequest();
      await assertDenied(approve(staff(), 'otro'));
    });

    test('staff rechaza una solicitud', () async {
      await seedRequest();
      await assertAllowed(
        staff().updateDoc('staffRequests/nueva', {
          'status': str('rejected'),
          'reviewedBy': str('staff1'),
          'reviewedAt': serverTimestamp,
        }),
      );
    });

    test('una rechazada ya no se aprueba', () async {
      await seedRequest();
      await assertAllowed(
        staff().updateDoc('staffRequests/nueva', {
          'status': str('rejected'),
          'reviewedBy': str('staff1'),
          'reviewedAt': serverTimestamp,
        }),
      );
      await assertDenied(approve(staff()));
    });

    test('la familia no revisa solicitudes', () async {
      await seedRequest();
      await assertDenied(
        fam1().updateDoc('staffRequests/nueva', {
          'status': str('rejected'),
          'reviewedBy': str('fam1'),
          'reviewedAt': serverTimestamp,
        }),
      );
    });

    test('nadie borra solicitudes', () async {
      await seedRequest();
      await assertDenied(staff().deleteDoc('staffRequests/nueva'));
    });
  });
}
