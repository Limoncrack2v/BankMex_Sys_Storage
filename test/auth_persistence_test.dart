import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/auth_persistence.dart';

/// FirebaseAuth de mentira; solo recuerda qué persistencia le pidieron.
class _FakeAuth extends Fake implements FirebaseAuth {
  Persistence? persistence;

  @override
  Future<void> setPersistence(Persistence persistence) async {
    this.persistence = persistence;
  }
}

void main() {
  test('en web la sesión dura solo mientras la pestaña esté abierta', () async {
    final auth = _FakeAuth();
    await configureAuthPersistence(auth, isWeb: true);
    expect(auth.persistence, Persistence.SESSION);
  });

  test('en Android/iOS no cambia la persistencia', () async {
    final auth = _FakeAuth();
    await configureAuthPersistence(auth, isWeb: false);
    expect(auth.persistence, isNull);
  });
}
