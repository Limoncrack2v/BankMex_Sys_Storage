import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/firestore_cache.dart';

/// FirebaseAuth de mentira; anota en [log] cuando se cierra la sesión.
class _FakeAuth extends Fake implements FirebaseAuth {
  _FakeAuth(this.log);

  final List<String> log;

  @override
  Future<void> signOut() async => log.add('signOut');
}

/// FirebaseFirestore de mentira; anota en [log] lo que se le pide.
class _FakeFirestore extends Fake implements FirebaseFirestore {
  _FakeFirestore(this.log, {this.pendingWrites, this.terminateError});

  final List<String> log;

  /// Lo que tarda en subir las escrituras pendientes; null = no hay.
  final Future<void>? pendingWrites;
  final Object? terminateError;

  @override
  Future<void> waitForPendingWrites() {
    log.add('waitForPendingWrites');
    return pendingWrites ?? Future.value();
  }

  @override
  Future<void> terminate() async {
    log.add('terminate');
    if (terminateError case final error?) throw error;
  }

  @override
  Future<void> clearPersistence() async => log.add('clearPersistence');
}

void main() {
  test('en Android/iOS espera las escrituras, cierra la sesión y después '
      'borra la caché', () async {
    final log = <String>[];
    await signOutAndClearCache(
      auth: _FakeAuth(log),
      firestore: _FakeFirestore(log),
      isWeb: false,
    );
    expect(log, [
      'waitForPendingWrites',
      'signOut',
      'terminate',
      'clearPersistence',
    ]);
  });

  test('sin conexión no se queda esperando y deja la caché con las escrituras '
      'en cola', () async {
    final log = <String>[];
    await signOutAndClearCache(
      auth: _FakeAuth(log),
      // Nunca se suben.
      firestore: _FakeFirestore(log, pendingWrites: Completer<void>().future),
      isWeb: false,
      pendingWritesTimeout: const Duration(milliseconds: 10),
    );
    expect(log, ['waitForPendingWrites', 'signOut']);
  });

  test('si falla la espera de las escrituras, cierra la sesión y deja la '
      'caché', () async {
    final log = <String>[];
    await signOutAndClearCache(
      auth: _FakeAuth(log),
      firestore: _FakeFirestore(
        log,
        pendingWrites: Future.error(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
      ),
      isWeb: false,
    );
    expect(log, ['waitForPendingWrites', 'signOut']);
  });

  test('si la caché no se puede borrar, la sesión se cierra igual', () async {
    final log = <String>[];
    await signOutAndClearCache(
      auth: _FakeAuth(log),
      firestore: _FakeFirestore(
        log,
        terminateError: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unknown',
        ),
      ),
      isWeb: false,
    );
    expect(log, ['waitForPendingWrites', 'signOut', 'terminate']);
  });

  test('en web solo cierra la sesión', () async {
    final log = <String>[];
    await signOutAndClearCache(
      auth: _FakeAuth(log),
      firestore: _FakeFirestore(log),
      isWeb: true,
    );
    expect(log, ['signOut']);
  });
}
