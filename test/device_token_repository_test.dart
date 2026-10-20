import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/repositories/device_token_repository.dart';

/// Permiso con el estado [authorizationStatus].
class _FakeSettings extends Fake implements NotificationSettings {
  _FakeSettings(this.authorizationStatus);

  @override
  final AuthorizationStatus authorizationStatus;
}

/// FCM de mentira; anota en [log] lo que se le pide.
class _FakeMessaging extends Fake implements FirebaseMessaging {
  _FakeMessaging(this.log, this.status);

  final List<String> log;
  final AuthorizationStatus status;

  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool sound = true,
    bool providesAppNotificationSettings = false,
  }) async => _FakeSettings(status);

  @override
  Future<String?> getToken({
    String? vapidKey,
    String? serviceWorkerScriptPath,
  }) async => 't1';

  @override
  Future<void> deleteToken() async => log.add('deleteToken');

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
}

/// Firestore de mentira; anota en [log] cada escritura con su ruta.
class _FakeFirestore extends Fake implements FirebaseFirestore {
  _FakeFirestore(this.log);

  final List<String> log;

  @override
  DocumentReference<Map<String, dynamic>> doc(String path) =>
      _FakeDoc(log, path);
}

// cloud_firestore no trae un doble de DocumentReference; solo para la prueba.
// ignore: subtype_of_sealed_class
class _FakeDoc extends Fake implements DocumentReference<Map<String, dynamic>> {
  _FakeDoc(this.log, this.path);

  final List<String> log;

  @override
  final String path;

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async =>
      log.add('set $path');

  @override
  Future<void> delete() async => log.add('delete $path');
}

void main() {
  test('sin permiso no guarda el token y borra el que había', () async {
    final log = <String>[];
    final repository = DeviceTokenRepository(
      firestore: _FakeFirestore(log),
      messaging: _FakeMessaging(log, AuthorizationStatus.denied),
    );

    await repository.register('fam1');

    expect(log, ['delete users/fam1/deviceTokens/t1', 'deleteToken']);
  });

  test('con permiso guarda el token de la familia', () async {
    final log = <String>[];
    final repository = DeviceTokenRepository(
      firestore: _FakeFirestore(log),
      messaging: _FakeMessaging(log, AuthorizationStatus.authorized),
    );

    await repository.register('fam1');

    expect(log, ['set users/fam1/deviceTokens/t1']);
  });
}
