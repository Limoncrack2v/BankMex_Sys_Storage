import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Driver para `flutter drive`: guarda las capturas de la prueba de punta a
/// punta en build/e2e_screenshots.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('build/e2e_screenshots/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
