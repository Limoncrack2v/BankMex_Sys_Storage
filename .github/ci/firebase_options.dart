// Configuración de Firebase solo para CI.
//
// El archivo real, lib/firebase_options.dart, está en .gitignore y lo genera
// `flutterfire configure`. Los workflows copian este en su lugar para que
// `flutter analyze` y las pruebas compilen. Los valores no son de ningún
// proyecto: las pruebas de CI no se conectan a Firebase, solo a los
// emuladores.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => ci;

  static const FirebaseOptions ci = FirebaseOptions(
    apiKey: 'ci-api-key',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'bank-storage-bamx',
  );
}
