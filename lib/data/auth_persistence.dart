import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Cómo guarda la sesión Firebase Auth.
///
/// En Android/iOS siempre se guarda en el dispositivo (es personal) y no se
/// puede cambiar. En web se usa SESSION: la sesión sobrevive a recargar la
/// página, pero se cierra al cerrar la pestaña, para que en una computadora
/// compartida del banco la siguiente persona no entre con la cuenta del staff
/// anterior.
Future<void> configureAuthPersistence(
  FirebaseAuth auth, {
  bool isWeb = kIsWeb,
}) async {
  if (!isWeb) {
    return;
  }

  await auth.setPersistence(Persistence.SESSION);
}
