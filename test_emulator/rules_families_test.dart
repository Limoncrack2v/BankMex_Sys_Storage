// Pruebas de firestore.rules (colección families) contra el emulador de
// Firestore (127.0.0.1:8080). Portadas 1:1 de la suite de JavaScript.
//
// Uso: C:\src\flutter\bin\flutter.bat test test_emulator/rules_families_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'support/emulator.dart';

Map<String, Object?> now() => ts(DateTime.utc(2026, 9, 21, 12));

/// Perfil de users/{uid}; [extra] agrega o reemplaza campos.
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

/// Hogar nuevo de families/{uid}; [extra] agrega o reemplaza campos.
Map<String, Map<String, Object?>> family(
  String authUid, [
  Map<String, Map<String, Object?>> extra = const {},
]) => {
  'name': str('Familia N'),
  'address': str('Calle 9'),
  'registrationDate': now(),
  'recoveryQuotaDefault': nul(),
  'authUid': str(authUid),
  'appliances': arr([]),
  ...extra,
};

/// Los datos que la suite de JS prepara en cada beforeEach (solo los que
/// necesita este grupo), escritos saltándose las reglas.
Future<void> seedFixtures() async {
  final admin = Db.admin();
  await admin.setDoc('users/staff1', profile('staff'));
  await admin.setDoc('users/fam1', profile('family'));
  await admin.setDoc('users/fam2', profile('family'));
  await admin.setDoc('families/famA', {
    'name': str('Familia A'),
    'address': str('Calle 1'),
    'registrationDate': now(),
    'recoveryQuotaDefault': nul(),
    'authUid': str('fam1'),
    'appliances': arr([]),
  });
  await admin.setDoc('families/famB', {
    'name': str('Familia B'),
    'address': str('Calle 2'),
    'registrationDate': now(),
    'recoveryQuotaDefault': nul(),
    'authUid': str('fam2'),
    'appliances': arr([]),
  });
}

Db staff() => Db.user('staff1');
Db fam1() => Db.user('fam1');
Db fam2() => Db.user('fam2');
Db newbie() => Db.user('newbie');

void main() {
  useProject('demo-bamx-families');

  setUpAll(requireEmulator);
  setUp(() async {
    await clearFirestore();
    await seedFixtures();
  });

  group('families', () {
    test('familia lee su hogar', () async {
      await assertAllowed(fam1().getDoc('families/famA'));
    });

    test('familia no lee hogares ajenos', () async {
      await assertDenied(fam2().getDoc('families/famA'));
    });

    test('staff lee cualquier hogar', () async {
      await assertAllowed(staff().getDoc('families/famA'));
    });

    test('staff lista todas las familias', () async {
      await assertAllowed(staff().listDocs('families'));
    });

    test('familia busca su hogar por authUid', () async {
      // La familia solo puede listar si la consulta ya filtra por su cuenta.
      await assertAllowed(
        fam1().listDocs(
          'families',
          where: ('authUid', str('fam1')),
          limit: 1,
        ),
      );
    });

    test('familia no puede listar todas las familias', () async {
      await assertDenied(fam1().listDocs('families'));
    });

    test('una cuenta ya no puede crear su propio hogar', () async {
      await assertDenied(
        newbie().setDoc('families/newbie', family('newbie')),
      );
    });

    // El hogar y su perfil van en el mismo batch: la regla usa getAfter sobre
    // users/{uid}, así que el perfil tiene que quedar escrito en la misma
    // operación.
    test('staff crea perfil + hogar (id = uid) en un batch', () async {
      await assertAllowed(
        staff().commit([
          setWrite('users/newbie', profile('family')),
          setWrite('families/newbie', family('newbie')),
        ]),
      );
    });

    test('staff no crea hogar sin perfil de familia', () async {
      await assertDenied(staff().setDoc('families/newbie', family('newbie')));
    });

    test('staff no crea hogar con id distinto al uid', () async {
      await assertDenied(
        staff().commit([
          setWrite('users/newbie', profile('family')),
          setWrite('families/otro', family('newbie')),
        ]),
      );
    });

    test('hogar sin dirección rechazado', () async {
      final noAddress = {...family('newbie')}..remove('address');
      await assertDenied(
        staff().commit([
          setWrite('users/newbie', profile('family')),
          setWrite('families/newbie', noAddress),
        ]),
      );
    });

    test('hogar con campo extra rechazado', () async {
      await assertDenied(
        staff().commit([
          setWrite('users/newbie', profile('family')),
          setWrite('families/newbie', family('newbie', {'hack': boolean(true)})),
        ]),
      );
    });

    test('la familia cambia sus electrodomésticos', () async {
      await assertAllowed(
        fam1().updateDoc('families/famA', {
          'appliances': arr([str('estufa')]),
        }),
      );
    });

    test('la familia no cambia su nombre', () async {
      await assertDenied(
        fam1().updateDoc('families/famA', {'name': str('Familia B')}),
      );
    });

    test('la familia no borra su dirección', () async {
      await assertDenied(
        fam1().updateDoc('families/famA', {'address': deleteField}),
      );
    });

    test('staff corrige nombre y dirección', () async {
      await assertAllowed(
        staff().updateDoc('families/famA', {
          'name': str('Familia A2'),
          'address': str('Calle 3'),
        }),
      );
    });

    test('staff no cambia la cuenta dueña', () async {
      await assertDenied(
        staff().updateDoc('families/famA', {'authUid': str('fam2')}),
      );
    });

    test('staff borra un hogar', () async {
      await assertAllowed(staff().deleteDoc('families/famB'));
    });

    test('la familia no borra su hogar', () async {
      await assertDenied(fam1().deleteDoc('families/famA'));
    });
  });
}
