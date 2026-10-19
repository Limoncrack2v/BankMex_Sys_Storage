import 'dart:js_interop';

@JS('sessionStorage')
external _Storage get _sessionStorage;

extension type _Storage._(JSObject _) implements JSObject {
  external void removeItem(String key);
}

/// Borra el emulador de Auth que firebase_auth_web guardó para [appName] en el
/// sessionStorage de la pestaña (clave `<app>-firebaseEmulatorOrigin`).
void forgetSavedAuthEmulator(String appName) =>
    _sessionStorage.removeItem('$appName-firebaseEmulatorOrigin');
