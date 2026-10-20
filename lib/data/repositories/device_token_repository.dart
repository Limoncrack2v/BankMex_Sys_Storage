import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firestore_paths.dart';

/// El token de FCM de este teléfono, en users/{uid}/deviceTokens/{token}.
/// La familia lo guarda al abrir su inicio y lo borra al cerrar sesión; solo
/// el servidor lo lee para mandar las alertas (firestore.rules).
class DeviceTokenRepository {
  /// [firestore] y [messaging] son para las pruebas.
  DeviceTokenRepository({this._firestore, this._messaging});

  static final instance = DeviceTokenRepository();

  /// Lo más que se espera a FCM: sin conexión, cerrar sesión no se queda
  /// esperando.
  static const _timeout = Duration(seconds: 3);

  final FirebaseFirestore? _firestore;
  final FirebaseMessaging? _messaging;

  // Al usarlos y no al crear la instancia: las pruebas de pantallas no
  // inicializan Firebase.
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  FirebaseMessaging get _fcm => _messaging ?? FirebaseMessaging.instance;

  StreamSubscription<String>? _refresh;

  /// Pide permiso y guarda el token de [uid]. Sin permiso, borra el que
  /// hubiera. No lanza errores.
  Future<void> register(String uid) async {
    // shortcut: solo Android; web necesita VAPID y un service worker, e iOS
    // APNs. Agregarlos si las familias usan esas plataformas.
    if (kIsWeb) return;
    try {
      final settings = await _fcm.requestPermission();
      final status = settings.authorizationStatus;
      if (status != AuthorizationStatus.authorized &&
          status != AuthorizationStatus.provisional) {
        // shortcut: sin interruptor en la app; negar el permiso de
        // notificaciones es la forma de no recibirlas.
        await unregister(uid);
        return;
      }
      final token = await _fcm.getToken();
      if (token != null) _save(uid, token);
      _refresh ??= _fcm.onTokenRefresh.listen((token) => _save(uid, token));
    } catch (_) {
      // Sin red o sin Google Play: se intenta otra vez en el siguiente inicio.
    }
  }

  /// Borra el token de [uid] de Firestore y de FCM. Va antes de cerrar la
  /// sesión, mientras las reglas todavía reconocen a [uid]. No lanza errores.
  Future<void> unregister(String uid) async {
    await _refresh?.cancel();
    _refresh = null;
    try {
      final token = await _fcm.getToken().timeout(_timeout);
      // Sin await: queda en cola y signOutAndClearCache espera a que suba.
      if (token != null) {
        _db.doc(FirestorePaths.deviceTokenDoc(uid, token)).delete().ignore();
      }
      await _fcm.deleteToken().timeout(_timeout);
    } catch (_) {
      // shortcut: sin conexión el token sigue vivo en FCM hasta que
      // SessionGate lo borra al abrir la app sin sesión; el servidor también
      // borra los tokens muertos al enviar.
    }
  }

  /// Sin await: sin conexión el set no termina hasta subir, y la pantalla no
  /// espera.
  void _save(String uid, String token) {
    _db.doc(FirestorePaths.deviceTokenDoc(uid, token)).set({
      'token': token,
      'platform': 'android',
      'updatedAt': FieldValue.serverTimestamp(),
    }).ignore();
  }
}
