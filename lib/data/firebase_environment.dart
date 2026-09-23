import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// En debug, por defecto la app usa la Firestore real (bank-storage-bamx).
/// Para usar emuladores locales:
/// `flutter run --dart-define=USE_FIRESTORE_EMULATOR=true`
Future<void> connectToEmulatorsIfDebug({
  required FirebaseAuth auth,
  FirebaseFirestore? firestore,
}) async {
  if (!kDebugMode) return;
  const useEmulator = bool.fromEnvironment(
    'USE_FIRESTORE_EMULATOR',
    defaultValue: false,
  );
  if (!useEmulator) return;

  final host = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? '10.0.2.2'
      : 'localhost';
  firestore?.useFirestoreEmulator(host, 8080);
  await auth.useAuthEmulator(host, 9099);
}
