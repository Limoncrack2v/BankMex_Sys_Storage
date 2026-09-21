import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// En debug la app usa los emuladores de Firebase (Firestore 8080, Auth 9099).
/// Se llama para la app principal y para la instancia secundaria que se usa
/// al registrar cuentas.
Future<void> connectToEmulatorsIfDebug({
  required FirebaseAuth auth,
  FirebaseFirestore? firestore,
}) async {
  if (!kDebugMode) return;

  final host = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? '10.0.2.2'
      : 'localhost';
  firestore?.useFirestoreEmulator(host, 8080);
  await auth.useAuthEmulator(host, 9099);
}
