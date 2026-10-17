import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Si hay conexión. Sin red en el dispositivo (modo avión, sin wifi ni datos)
/// es "sin conexión" en cuanto el sistema lo avisa: Firestore tarda minutos en
/// notar que su conexión murió. Con red, decide Firestore según los metadatos
/// de un listener: cuando los datos solo vienen del caché no hay conexión, y
/// espera unos segundos antes de marcarlo para no parpadear al abrir.
class ConnectionStatus {
  ConnectionStatus._();

  static final instance = ConnectionStatus._();
  static const _offlineDelay = Duration(seconds: 3);

  final online = ValueNotifier<bool>(true);
  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _offlineTimer;
  bool _hasNetwork = true;
  bool _fromCache = false;

  /// Empieza a vigilar la conexión con el perfil del usuario con sesión.
  void watch(String userId) {
    final connectivity = Connectivity();
    listen(
      fromCache: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots(includeMetadataChanges: true)
          .map((snapshot) => snapshot.metadata.isFromCache),
      network: () async* {
        // El stream solo avisa cambios: el estado inicial se pide aparte.
        yield await connectivity.checkConnectivity();
        yield* connectivity.onConnectivityChanged;
      }(),
    );
  }

  /// [watch] con las dos fuentes inyectadas, para las pruebas.
  @visibleForTesting
  void listen({
    required Stream<bool> fromCache,
    required Stream<List<ConnectivityResult>> network,
  }) {
    stop();
    _subscriptions
      ..add(
        fromCache.listen((value) {
          _fromCache = value;
          _apply();
        }, onError: (_) {}),
      )
      ..add(
        network.listen((results) {
          _hasNetwork = results.any(
            (result) => result != ConnectivityResult.none,
          );
          _apply();
        }, onError: (_) {}),
      );
  }

  void stop() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _offlineTimer?.cancel();
    _offlineTimer = null;
    _hasNetwork = true;
    _fromCache = false;
    online.value = true;
  }

  void _apply() {
    if (!_hasNetwork) {
      _offlineTimer?.cancel();
      _offlineTimer = null;
      online.value = false;
    } else if (!_fromCache) {
      _offlineTimer?.cancel();
      _offlineTimer = null;
      online.value = true;
    } else {
      _offlineTimer ??= Timer(_offlineDelay, () {
        _offlineTimer = null;
        online.value = false;
      });
    }
  }
}
