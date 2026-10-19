// Cerrar sesión borra la caché local de Firestore (MASVS-STORAGE-1) y cancela
// el recordatorio del plan.
//
// Mismos requisitos que app_flow_test.dart: emuladores de Auth y Firestore
// corriendo y `node tool/seed_emulators.mjs` antes de la corrida.
//
//   flutter test integration_test/sign_out_cache_test.dart -d <id del dispositivo>
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bank_storage_app/data/firebase_environment.dart';
import 'package:bank_storage_app/data/plan_reminder.dart';
import 'package:bank_storage_app/data/repositories/auth_repository.dart';
import 'package:bank_storage_app/firebase_options.dart';

// Cuenta de familia creada por tool/seed_emulators.mjs.
const _familyEmail = 'familia.ramirez@bamx.test';
const _password = 'bamx1234';

const _fromCache = GetOptions(source: Source.cache);

/// La lectura desde la caché falla porque el documento ya no está ahí.
final _notInCache = throwsA(
  isA<FirebaseException>().having((e) => e.code, 'code', 'unavailable'),
);

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

  testWidgets('cerrar sesión borra la caché y Firestore sigue funcionando', (
    tester,
  ) async {
    final auth = AuthRepository();
    final session = await auth.signIn(_familyEmail, _password);
    final db = FirebaseFirestore.instance;
    final profile = db.collection('users').doc(session.user.userId);
    final family = db.collection('families').doc(session.family!.familyId);

    // Al iniciar sesión se leyeron el perfil y el hogar: están en la caché.
    expect((await profile.get(_fromCache)).exists, isTrue);
    expect((await family.get(_fromCache)).exists, isTrue);

    await auth.signOut();

    await expectLater(profile.get(_fromCache), _notInCache);
    await expectLater(family.get(_fromCache), _notInCache);

    // Firestore se vuelve a crear solo y sigue usando el emulador: la familia
    // puede volver a entrar.
    final again = await auth.signIn(_familyEmail, _password);
    expect(again.family?.familyId, session.family!.familyId);
    await auth.signOut();
  });

  testWidgets('sin conexión cierra la sesión y deja en cola lo que no se '
      'subió', (tester) async {
    final auth = AuthRepository();
    final session = await auth.signIn(_familyEmail, _password);
    final db = FirebaseFirestore.instance;
    final profile = db.collection('users').doc(session.user.userId);
    final member = db
        .collection('families')
        .doc(session.family!.familyId)
        .collection('members')
        .doc();

    await db.disableNetwork();
    var offline = true;
    addTearDown(() async {
      if (offline) await db.enableNetwork();
    });
    // Sin conexión la escritura no termina: se queda pendiente en la caché.
    member.set({
      'name': 'Sin subir',
      'memberType': 'adult',
      'createdAt': Timestamp.now(),
    }).ignore();
    final pending = await member
        .snapshots(includeMetadataChanges: true)
        .firstWhere((snapshot) => snapshot.exists)
        .timeout(const Duration(seconds: 10));
    expect(pending.metadata.hasPendingWrites, isTrue);

    final elapsed = Stopwatch()..start();
    await auth.signOut();
    // Solo espera los 5 s que se dan a las escrituras pendientes.
    expect(elapsed.elapsed, lessThan(const Duration(seconds: 15)));

    // La caché no se borró: el perfil leído al iniciar sesión sigue ahí.
    expect((await profile.get(_fromCache)).exists, isTrue);

    // La misma cuenta vuelve a entrar con conexión y la escritura en cola se
    // sube.
    await db.enableNetwork();
    offline = false;
    await auth.signIn(_familyEmail, _password);
    await db.waitForPendingWrites().timeout(const Duration(seconds: 10));
    final uploaded = await member.get(const GetOptions(source: Source.server));
    expect(uploaded.data()?['name'], 'Sin subir');
    await member.delete();

    // Con conexión, el siguiente cierre de sesión sí borra la caché.
    await auth.signOut();
    await expectLater(profile.get(_fromCache), _notInCache);
  });

  testWidgets('cerrar sesión cancela el recordatorio del plan, con y sin '
      'conexión', (tester) async {
    final auth = AuthRepository();
    final notifications = FlutterLocalNotificationsPlugin();
    // Se programa con el plugin, igual que la app, pero sin
    // PlanReminder.enable: su diálogo de permiso no se puede contestar aquí.
    final scheduler = LocalReminderScheduler();
    await scheduler.init(onOpenPlan: () {});
    addTearDown(notifications.cancelAll);

    await auth.signIn(_familyEmail, _password);
    await scheduler.scheduleDaily(PlanReminder.defaultTime);
    expect(await notifications.pendingNotificationRequests(), hasLength(1));
    await auth.signOut();
    expect(await notifications.pendingNotificationRequests(), isEmpty);

    // Sin conexión también se cancela.
    await auth.signIn(_familyEmail, _password);
    await scheduler.scheduleDaily(PlanReminder.defaultTime);
    expect(await notifications.pendingNotificationRequests(), hasLength(1));
    final db = FirebaseFirestore.instance;
    await db.disableNetwork();
    var offline = true;
    addTearDown(() async {
      if (offline) await db.enableNetwork();
    });
    await auth.signOut();
    expect(await notifications.pendingNotificationRequests(), isEmpty);
    await db.enableNetwork();
    offline = false;
  });
}
