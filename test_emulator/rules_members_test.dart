// Pruebas de firestore.rules para families/{familyId}/members contra el
// emulador de Firestore (127.0.0.1:8080).
//
// Port 1:1 del grupo describe('members') de rules.test.mjs: mismos nombres,
// mismas aserciones y en el mismo orden.
//
// Uso: flutter test test_emulator/rules_members_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'support/emulator.dart';

/// Proyecto propio de este archivo, para que otros archivos de pruebas puedan
/// correr al mismo tiempo sin borrarse los datos entre ellos.
const _project = 'demo-bamx-members';

Map<String, Object?> now() => ts(DateTime.utc(2026, 9, 21, 12));

// ---------------------------------------------------------------------------
// Constructores de documentos (los mismos valores por omisión que en JS; el
// mapa [extra] reemplaza campos, como el spread `...extra`).
// ---------------------------------------------------------------------------

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

Map<String, Map<String, Object?>> member([
  Map<String, Map<String, Object?>> extra = const {},
]) => {
  'name': str('Ana'),
  'memberType': str('adult'),
  'createdAt': now(),
  ...extra,
};

Map<String, Map<String, Object?>> family(
  String name,
  String address,
  String authUid,
) => {
  'name': str(name),
  'address': str(address),
  'registrationDate': now(),
  'recoveryQuotaDefault': nul(),
  'authUid': str(authUid),
  'appliances': arr([]),
};

// Sesiones, como en el JS.
Db staff() => Db.user('staff1');
Db fam1() => Db.user('fam1');
Db fam2() => Db.user('fam2');

/// El integrante nuevo que intentan crear las pruebas.
const m = 'families/famA/members/new';

/// El integrante que ya existe (para las de edición).
const m1 = 'families/famA/members/m1';

void main() {
  useProject(_project);

  setUpAll(requireEmulator);

  setUp(() async {
    await clearFirestore();
    final admin = Db.admin();
    await admin.setDoc('users/staff1', profile('staff'));
    await admin.setDoc('users/fam1', profile('family'));
    // users/fam2 existe para que el rechazo venga de la regla (no es staff ni
    // dueña de famA) y no de un get() sobre un documento inexistente.
    await admin.setDoc('users/fam2', profile('family'));
    await admin.setDoc('families/famA', family('Familia A', 'Calle 1', 'fam1'));
    await admin.setDoc(m1, member({'age': integer(30)}));
  });

  group('members', () {
    test('familia registra integrante con todos los campos', () async {
      await assertAllowed(
        fam1().setDoc(
          m,
          member({
            'memberType': str('child'),
            'sex': str('female'),
            'age': integer(9),
            'weightKg': number(28.5),
            'allergies': arr([str('gluten'), str('egg')]),
          }),
        ),
      );
    });

    test('integrante mínimo (formato anterior) sigue siendo válido', () async {
      await assertAllowed(fam1().setDoc(m, member()));
    });

    test('alergias vacías ("Ninguna") válidas', () async {
      await assertAllowed(fam1().setDoc(m, member({'allergies': arr([])})));
    });

    test('edad 121 rechazada', () async {
      await assertDenied(fam1().setDoc(m, member({'age': integer(121)})));
    });

    test('edad decimal rechazada', () async {
      // `data.age is int`: un doubleValue no pasa aunque valga 9.5.
      await assertDenied(fam1().setDoc(m, member({'age': number(9.5)})));
    });

    test('edad como texto rechazada', () async {
      await assertDenied(fam1().setDoc(m, member({'age': str('9')})));
    });

    test('peso 0 rechazado', () async {
      await assertDenied(fam1().setDoc(m, member({'weightKg': integer(0)})));
    });

    test('peso 501 rechazado', () async {
      await assertDenied(fam1().setDoc(m, member({'weightKg': integer(501)})));
    });

    test('sexo inválido rechazado', () async {
      await assertDenied(fam1().setDoc(m, member({'sex': str('x')})));
    });

    test('alergia desconocida rechazada', () async {
      await assertDenied(
        fam1().setDoc(
          m,
          member({
            'allergies': arr([str('nuts')]),
          }),
        ),
      );
    });

    test('campo extra rechazado', () async {
      await assertDenied(fam1().setDoc(m, member({'foo': integer(1)})));
    });

    test('otra familia no registra integrantes aquí', () async {
      await assertDenied(fam2().setDoc(m, member()));
    });

    test('staff registra integrantes', () async {
      await assertAllowed(staff().setDoc(m, member()));
    });

    test('editar sin cambiar createdAt', () async {
      await assertAllowed(
        fam1().updateDoc(m1, {'age': integer(31), 'weightKg': integer(70)}),
      );
    });

    test('borrar un campo opcional al editar', () async {
      await assertAllowed(fam1().updateDoc(m1, {'age': deleteField}));
    });

    test('cambiar createdAt rechazado', () async {
      await assertDenied(
        fam1().updateDoc(m1, {'createdAt': ts(DateTime.utc(2020, 1, 1))}),
      );
    });

    test('otra familia no lee integrantes', () async {
      await assertDenied(fam2().listDocs('members', parent: 'families/famA'));
    });

    test('la familia lee sus integrantes', () async {
      await assertAllowed(fam1().listDocs('members', parent: 'families/famA'));
    });
  });
}
