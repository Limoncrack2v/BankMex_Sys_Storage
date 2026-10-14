// Las estadísticas del staff se leen del servidor: sin conexión la carga falla
// (y la pestaña muestra el aviso) en lugar de dar como totales lo que haya en
// la caché.
//
// Mismos requisitos que app_flow_test.dart: emuladores de Auth, Firestore y
// Functions corriendo y `node tool/seed_emulators.mjs` antes de la corrida.
//
//   flutter test integration_test/stats_offline_test.dart -d <id del dispositivo>
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bank_storage_app/data/firebase_environment.dart';
import 'package:bank_storage_app/data/repositories/auth_repository.dart';
import 'package:bank_storage_app/firebase_options.dart';
import 'package:bank_storage_app/ui/screens/staff/stats_screen.dart';

// Cuenta de staff creada por tool/seed_emulators.mjs.
const _staffEmail = 'staff@bamx.test';
const _password = 'bamx1234';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await connectToEmulatorsIfDebug(
      auth: FirebaseAuth.instance,
      firestore: FirebaseFirestore.instance,
    );
    await FirebaseAuth.instance.signOut();
  });

  testWidgets('sin conexión la carga falla en lugar de usar la caché', (
    tester,
  ) async {
    final auth = AuthRepository();
    await auth.signIn(_staffEmail, _password);
    final db = FirebaseFirestore.instance;

    // Con conexión carga, y lo que leyó queda en la caché: la familia del
    // seed tiene una entrega entregada hace 2 días.
    final online = await loadProgramStats();
    expect(online.familiesServed + online.familiesServedBefore, greaterThan(0));

    await db.disableNetwork();
    var offline = true;
    addTearDown(() async {
      if (offline) await db.enableNetwork();
    });

    // Las lecturas van en paralelo, así que el error de Firestore llega
    // envuelto en un ParallelWaitError (su texto incluye el primero).
    await expectLater(
      loadProgramStats(),
      throwsA(
        predicate(
          (Object error) => '$error'.contains('cloud_firestore/unavailable'),
          'un error unavailable de Firestore',
        ),
      ),
    );

    await db.enableNetwork();
    offline = false;
    await auth.signOut();
  });
}
