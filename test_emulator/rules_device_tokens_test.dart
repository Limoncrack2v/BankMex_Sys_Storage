// Pruebas de firestore.rules para /deviceTokens/{tokenId} contra el emulador
// de Firestore (127.0.0.1:8080).
//
// Uso: flutter test test_emulator/rules_device_tokens_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'support/emulator.dart';

const _project = 'demo-bamx-device-tokens';

Map<String, Object?> now() => ts(DateTime.utc(2026, 9, 21, 12));

Map<String, Map<String, Object?>> profile(String role) => {
  'name': str('Nombre'),
  'email': str('x@y.com'),
  'role': str(role),
  'createdAt': now(),
};

Map<String, Map<String, Object?>> family(String authUid) => {
  'address': str('Calle 1'),
  'registrationDate': now(),
  'authUid': str(authUid),
  'appliances': arr([]),
};

Future<int> saveToken(
  Db db,
  String uid,
  String token, {
  String? docId,
  Map<String, Map<String, Object?>> extra = const {},
}) => db.commit([
  setWrite(
    'users/$uid/deviceTokens/${docId ?? token}',
    {'token': str(token), 'platform': str('android'), ...extra},
    requestTimeFields: ['updatedAt'],
  ),
]);

Db staff() => Db.user('staff1');
Db fam1() => Db.user('fam1');
Db fam2() => Db.user('fam2');

void main() {
  useProject(_project);

  setUpAll(requireEmulator);

  setUp(() async {
    await clearFirestore();
    final admin = Db.admin();
    await admin.setDoc('users/staff1', profile('staff'));
    await admin.setDoc('families/fam1', family('fam1'));
  });

  test('la familia guarda su token', () async {
    await assertAllowed(saveToken(fam1(), 'fam1', 't1'));
  });

  test('lo vuelve a guardar', () async {
    await assertAllowed(saveToken(fam1(), 'fam1', 't1'));
    await assertAllowed(saveToken(fam1(), 'fam1', 't1'));
  });

  test('no lo guarda en otra cuenta', () async {
    await assertDenied(saveToken(fam1(), 'fam2', 't1'));
  });

  test('staff no guarda tokens', () async {
    await assertDenied(saveToken(staff(), 'staff1', 't1'));
  });

  test('el id tiene que ser el token', () async {
    await assertDenied(saveToken(fam1(), 'fam1', 't1', docId: 'otro'));
  });

  test('sin campos de más', () async {
    await assertDenied(
      saveToken(fam1(), 'fam1', 't1', extra: {'familyName': str('Ramírez')}),
    );
  });

  test('solo android', () async {
    await assertDenied(
      saveToken(fam1(), 'fam1', 't1', extra: {'platform': str('ios')}),
    );
  });

  test('la hora es la del servidor', () async {
    await assertDenied(
      fam1().setDoc('users/fam1/deviceTokens/t1', {
        'token': str('t1'),
        'platform': str('android'),
        'updatedAt': now(),
      }),
    );
  });

  test('la familia borra el suyo', () async {
    await saveToken(fam1(), 'fam1', 't1');
    await assertAllowed(fam1().deleteDoc('users/fam1/deviceTokens/t1'));
  });

  test('otro no lo borra', () async {
    await saveToken(fam1(), 'fam1', 't1');
    await assertDenied(fam2().deleteDoc('users/fam1/deviceTokens/t1'));
  });

  test('nadie lo lee', () async {
    await saveToken(fam1(), 'fam1', 't1');
    await assertDenied(fam1().getDoc('users/fam1/deviceTokens/t1'));
  });
}
