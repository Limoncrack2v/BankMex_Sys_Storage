import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Id aleatorio de esta instalación de la app (no del hardware, por
/// privacidad). Se guarda en el dispositivo; reinstalar la app genera uno
/// nuevo (esto hace que se pierda la cola offline de Firestore).
class DeviceIdentity {
  static final instance = DeviceIdentity();

  static const _key = 'device_id';

  Future<String>? _id;

  Future<String> get id {
    return _id ??= _load();
  }

  Future<String> _load() async {
    final prefs = await SharedPreferences.getInstance();

    final String? keyValue = prefs.getString(_key);

    if (keyValue != null) {
      return keyValue;
    }

    final String newId = _generate();

    await prefs.setString(_key, newId);

    return newId;
  }

  String _generate() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
