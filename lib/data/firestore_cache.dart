import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Cierra la sesión de [auth] y borra la caché local de [firestore]
/// (MASVS-STORAGE-1).
///
/// En Android/iOS Firestore guarda en el teléfono los documentos que se
/// leyeron (datos de las familias) y las escrituras que aún no se suben. Al
/// cerrar sesión se borran, para que no queden ahí para la siguiente persona
/// que use el teléfono:
/// 1. Espera hasta [pendingWritesTimeout] a que se suban las escrituras
///    pendientes. Sin conexión no alcanzan a subirse y se pierden con la
///    caché.
/// 2. Cierra la sesión de Auth.
/// 3. terminate() detiene Firestore y clearPersistence() borra sus archivos.
///    La siguiente llamada a Firestore crea otra instancia con la misma
///    configuración (en debug, la del emulador).
///
/// Si la caché no se puede borrar, la sesión queda cerrada igual y el error
/// no se lanza, para que la pantalla de salida no se quede esperando.
///
/// En web solo cierra la sesión: ahí la caché vive en memoria (la app no
/// activa la persistencia) y FlutterFire web no vuelve a crear la instancia
/// después de terminate().
Future<void> signOutAndClearCache({
  required FirebaseAuth auth,
  required FirebaseFirestore firestore,
  bool isWeb = kIsWeb,
  Duration pendingWritesTimeout = const Duration(seconds: 5),
}) async {
  if (isWeb) {
    await auth.signOut();
    return;
  }

  try {
    // Solo espera las del usuario con sesión; por eso va antes de cerrarla.
    await firestore.waitForPendingWrites().timeout(pendingWritesTimeout);
  } catch (_) {
    // Sin conexión (TimeoutException) o con error: se cierra la sesión igual.
  }

  await auth.signOut();

  try {
    await firestore.terminate();
    await firestore.clearPersistence();
  } catch (_) {
    // La sesión ya está cerrada; la caché se borra en el siguiente cierre.
  }
}
