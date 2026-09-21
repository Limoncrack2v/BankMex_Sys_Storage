import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Si hay conexión con Firestore, según los metadatos de un listener: cuando
/// los datos solo vienen del caché del dispositivo no hay conexión. Espera
/// unos segundos antes de marcar "sin conexión" para no parpadear al abrir.
class ConnectionStatus {
  ConnectionStatus._();

  static final instance = ConnectionStatus._();
  static const _offlineDelay = Duration(seconds: 3);

  final online = ValueNotifier<bool>(true);
  StreamSubscription<Object?>? _subscription;
  Timer? _offlineTimer;

  /// Empieza a vigilar la conexión con el perfil del usuario con sesión.
  void watch(String userId) {
    stop();
    _subscription = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) => _update(fromCache: snapshot.metadata.isFromCache),
          onError: (_) {},
        );
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _offlineTimer?.cancel();
    online.value = true;
  }

  void _update({required bool fromCache}) {
    if (!fromCache) {
      _offlineTimer?.cancel();
      online.value = true;
    } else {
      _offlineTimer ??= Timer(_offlineDelay, () {
        _offlineTimer = null;
        online.value = false;
      });
    }
  }
}
