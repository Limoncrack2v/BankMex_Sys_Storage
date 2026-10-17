import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/firebase_environment.dart';

class _FakeApp extends Fake implements FirebaseApp {
  _FakeApp(this.name);

  @override
  final String name;
}

/// FirebaseAuth de mentira; anota a qué emulador lo conectan.
class _FakeAuth extends Fake implements FirebaseAuth {
  _FakeAuth(this.app, this.calls);

  @override
  final FirebaseApp app;

  final List<String> calls;

  @override
  Future<void> useAuthEmulator(
    String host,
    int port, {
    bool automaticHostMapping = true,
  }) async {
    calls.add('useAuthEmulator $port');
  }
}

void main() {
  // En web, si el emulador quedó guardado de antes de F5, useAuthEmulator no
  // conecta el Auth nuevo y este se queda en producción.
  test('olvida el emulador guardado antes de conectar Auth', () async {
    final calls = <String>[];
    await connectToEmulatorsIfDebug(
      auth: _FakeAuth(_FakeApp('[DEFAULT]'), calls),
      forgetSavedEmulator: (appName) => calls.add('forget $appName'),
    );
    expect(calls, ['forget [DEFAULT]', 'useAuthEmulator 9099']);
  });

  test('usa el nombre de la instancia secundaria del registro', () async {
    final calls = <String>[];
    await connectToEmulatorsIfDebug(
      auth: _FakeAuth(_FakeApp('registro-1'), calls),
      forgetSavedEmulator: (appName) => calls.add('forget $appName'),
    );
    expect(calls, ['forget registro-1', 'useAuthEmulator 9099']);
  });
}
