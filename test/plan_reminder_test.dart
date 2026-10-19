import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_10y.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:bank_storage_app/data/models/app_user.dart';
import 'package:bank_storage_app/data/plan_reminder.dart';

import 'helpers/fake_reminder_scheduler.dart';

/// Lo que recibió zonedSchedule.
typedef _Scheduled = ({
  int id,
  String? title,
  String? body,
  String? payload,
  tz.TZDateTime date,
  NotificationDetails details,
  AndroidScheduleMode mode,
  DateTimeComponents? repeat,
});

/// Plugin de notificaciones de mentira; anota lo que se le pide.
class _FakePlugin extends Fake implements FlutterLocalNotificationsPlugin {
  int initialized = 0;

  /// Si no es null, la siguiente inicialización falla con este error.
  Object? initializeError;
  InitializationSettings? settings;
  DidReceiveNotificationResponseCallback? onResponse;
  NotificationAppLaunchDetails? launch;
  final scheduled = <_Scheduled>[];
  int cancelled = 0;
  int settingsOpened = 0;
  _FakeAndroid? android;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    initialized++;
    if (initializeError case final error?) {
      initializeError = null;
      throw error;
    }
    this.settings = settings;
    onResponse = onDidReceiveNotificationResponse;
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => launch;

  @override
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    scheduled.add((
      id: id,
      title: title,
      body: body,
      payload: payload,
      date: scheduledDate,
      details: notificationDetails,
      mode: androidScheduleMode,
      repeat: matchDateTimeComponents,
    ));
  }

  @override
  Future<void> cancelAll() async => cancelled++;

  @override
  Future<bool?> openAppNotificationSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  T? resolvePlatformSpecificImplementation<
    T extends FlutterLocalNotificationsPlatform
  >() {
    final Object? implementation = android;
    return implementation is T ? implementation : null;
  }
}

/// La parte de Android del plugin, con las respuestas del teléfono.
class _FakeAndroid extends Fake
    implements AndroidFlutterLocalNotificationsPlugin {
  _FakeAndroid({this.granted, this.enabled});

  final bool? granted;
  final bool? enabled;

  @override
  Future<bool?> requestNotificationsPermission() async => granted;

  @override
  Future<bool?> areNotificationsEnabled() async => enabled;
}

const _tapOnReminder = NotificationResponse(
  notificationResponseType: NotificationResponseType.selectedNotification,
  payload: 'plan',
);

const _onKey = 'plan_reminder_on.fam1';
const _timeKey = 'plan_reminder_time.fam1';

/// Todo lo que quedó guardado en las preferencias del teléfono.
Future<Map<String, Object?>> _saved() async {
  final prefs = await SharedPreferences.getInstance();
  return {for (final key in prefs.getKeys()) key: prefs.get(key)};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('nextReminderAt', () {
    late tz.Location guadalajara;

    setUpAll(() {
      tz_data.initializeTimeZones();
      guadalajara = tz.getLocation('America/Mexico_City');
    });

    tz.TZDateTime at(
      int year,
      int month,
      int day,
      int hour,
      int minute, [
      int second = 0,
    ]) => tz.TZDateTime(guadalajara, year, month, day, hour, minute, second);

    test('is today while the time has not passed', () {
      expect(
        nextReminderAt(at(2026, 10, 18, 8, 30), const ReminderTime(9, 0)),
        at(2026, 10, 18, 9, 0),
      );
    });

    test('is tomorrow once the time has passed, even by a second', () {
      const nine = ReminderTime(9, 0);
      expect(
        nextReminderAt(at(2026, 10, 18, 9, 0), nine),
        at(2026, 10, 19, 9, 0),
      );
      expect(
        nextReminderAt(at(2026, 10, 18, 9, 0, 1), nine),
        at(2026, 10, 19, 9, 0),
      );
      expect(
        nextReminderAt(at(2026, 10, 18, 21, 0), nine),
        at(2026, 10, 19, 9, 0),
      );
    });

    test('crosses midnight', () {
      const tenPastMidnight = ReminderTime(0, 10);
      expect(
        nextReminderAt(at(2026, 10, 18, 23, 50), tenPastMidnight),
        at(2026, 10, 19, 0, 10),
      );
      expect(
        nextReminderAt(at(2026, 10, 19, 0, 5), tenPastMidnight),
        at(2026, 10, 19, 0, 10),
      );
    });

    test('rolls over the end of the month and the year', () {
      expect(
        nextReminderAt(at(2026, 10, 31, 21, 0), const ReminderTime(7, 30)),
        at(2026, 11, 1, 7, 30),
      );
      expect(
        nextReminderAt(at(2026, 12, 31, 22, 0), const ReminderTime(9, 0)),
        at(2027, 1, 1, 9, 0),
      );
      expect(
        nextReminderAt(at(2028, 2, 28, 10, 0), const ReminderTime(9, 0)),
        at(2028, 2, 29, 9, 0),
      );
    });

    test('keeps the time zone of now', () {
      final next = nextReminderAt(
        at(2026, 10, 18, 8, 0),
        const ReminderTime(9, 0),
      );
      expect(next.location, guadalajara);
      // Guadalajara es UTC−6 todo el año.
      expect(next.toUtc(), DateTime.utc(2026, 10, 18, 15, 0));
    });
  });

  group('ReminderTime', () {
    test('is stored as zero-padded HH:mm and read back', () {
      expect(const ReminderTime(9, 5).toStorage(), '09:05');
      expect(const ReminderTime(21, 30).toStorage(), '21:30');
      for (final time in const [
        ReminderTime(0, 0),
        ReminderTime(9, 5),
        ReminderTime(23, 59),
      ]) {
        expect(ReminderTime.tryParse(time.toStorage()), time);
      }
    });

    test('rejects anything that is not a valid HH:mm', () {
      for (final value in [
        '',
        '9:00',
        '24:00',
        '12:60',
        '12-30',
        'ab:cd',
        '12:30:00',
        ' 09:00',
      ]) {
        expect(ReminderTime.tryParse(value), isNull, reason: value);
      }
    });

    test('compares by value', () {
      expect(const ReminderTime(9, 0), ReminderTime(9, 0));
      expect(ReminderTime(9, 0).hashCode, const ReminderTime(9, 0).hashCode);
      expect(const ReminderTime(9, 0), isNot(const ReminderTime(9, 1)));
    });
  });

  group('PlanReminder', () {
    late FakeReminderScheduler scheduler;
    late PlanReminder reminder;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      scheduler = FakeReminderScheduler();
      reminder = PlanReminder(scheduler: scheduler, isWeb: false);
    });

    test('is off at 9:00 until the family turns it on', () async {
      expect(reminder.isSupported, isTrue);
      expect(await reminder.settingsFor('fam1'), (
        on: false,
        time: const ReminderTime(9, 0),
      ));
      expect(PlanReminder.defaultTime, const ReminderTime(9, 0));
    });

    test('turning it on schedules it and saves only the switch and the '
        'time', () async {
      final result = await reminder.enable('fam1', const ReminderTime(7, 30));

      expect(result, ReminderResult.scheduled);
      expect(scheduler.calls, [
        'init',
        'notificationsEnabled',
        'scheduleDaily 07:30',
      ]);
      expect(scheduler.scheduled, const ReminderTime(7, 30));
      expect(await reminder.settingsFor('fam1'), (
        on: true,
        time: const ReminderTime(7, 30),
      ));
      expect(await _saved(), {_onKey: true, _timeKey: '07:30'});
    });

    test('asks for permission when notifications are off and schedules '
        'once granted', () async {
      scheduler.enabled = false;

      final result = await reminder.enable('fam1', const ReminderTime(7, 30));

      expect(result, ReminderResult.scheduled);
      expect(scheduler.calls, [
        'init',
        'notificationsEnabled',
        'requestPermission',
        'scheduleDaily 07:30',
      ]);
    });

    test('stays off and saves nothing when permission is denied', () async {
      scheduler
        ..enabled = false
        ..grantPermission = false;

      final result = await reminder.enable('fam1', const ReminderTime(7, 30));

      expect(result, ReminderResult.permissionDenied);
      expect(scheduler.calls, [
        'init',
        'notificationsEnabled',
        'requestPermission',
      ]);
      expect(scheduler.scheduled, isNull);
      expect(await _saved(), isEmpty);
    });

    test('reports a failure and keeps what was saved', () async {
      await reminder.enable('fam1', const ReminderTime(7, 30));
      scheduler.errors['scheduleDaily'] = PlatformException(code: 'error');

      final result = await reminder.enable('fam1', const ReminderTime(8, 0));

      expect(result, ReminderResult.failed);
      expect(await reminder.settingsFor('fam1'), (
        on: true,
        time: const ReminderTime(7, 30),
      ));
    });

    test('a failure while it is off leaves it off', () async {
      scheduler.errors['init'] = PlatformException(code: 'invalid_icon');

      final result = await reminder.enable('fam1', const ReminderTime(7, 30));

      expect(result, ReminderResult.failed);
      expect(await _saved(), isEmpty);
    });

    test('changing the time reschedules it', () async {
      await reminder.enable('fam1', const ReminderTime(7, 30));
      await reminder.enable('fam1', const ReminderTime(20, 15));

      expect(scheduler.scheduled, const ReminderTime(20, 15));
      expect(await _saved(), {_onKey: true, _timeKey: '20:15'});
    });

    test('turning it off cancels it and keeps the time', () async {
      await reminder.enable('fam1', const ReminderTime(7, 30));

      await reminder.disable('fam1');

      expect(scheduler.calls.last, 'cancel');
      expect(scheduler.scheduled, isNull);
      expect(await reminder.settingsFor('fam1'), (
        on: false,
        time: const ReminderTime(7, 30),
      ));
    });

    test('turning it off never throws', () async {
      scheduler.errors['cancel'] = PlatformException(code: 'error');

      await reminder.disable('fam1');

      expect(await _saved(), {_onKey: false});
    });

    test('restoreFor schedules the saved time without asking for '
        'permission', () async {
      SharedPreferences.setMockInitialValues({_onKey: true, _timeKey: '06:45'});
      // Aunque el teléfono tenga las notificaciones apagadas.
      scheduler.enabled = false;

      await reminder.restoreFor('fam1');

      expect(scheduler.calls, ['init', 'scheduleDaily 06:45']);
      expect(scheduler.scheduled, const ReminderTime(6, 45));
    });

    test('restoreFor cancels when the reminder is off', () async {
      SharedPreferences.setMockInitialValues({
        _onKey: false,
        _timeKey: '06:45',
      });
      scheduler.scheduled = const ReminderTime(6, 45);

      await reminder.restoreFor('fam1');

      expect(scheduler.calls, ['cancel']);
      expect(scheduler.scheduled, isNull);
    });

    test('restoreFor never throws', () async {
      SharedPreferences.setMockInitialValues({_onKey: true, _timeKey: '06:45'});
      scheduler.errors['init'] = PlatformException(code: 'error');

      await reminder.restoreFor('fam1');

      expect(scheduler.calls, ['init']);
    });

    test('a family session brings its reminder back; a staff or '
        'nutritionist session on the same phone cancels it', () async {
      SharedPreferences.setMockInitialValues({
        _onKey: true,
        _timeKey: '06:45',
        // Solo las familias lo reciben, aunque otra cuenta tenga algo guardado.
        'plan_reminder_on.user1': true,
        'plan_reminder_time.user1': '07:00',
      });

      for (final role in [AppUser.roleStaff, AppUser.roleNutritionist]) {
        await reminder.sessionStarted('fam1', role: AppUser.roleFamily);
        expect(scheduler.scheduled, const ReminderTime(6, 45));

        await reminder.sessionStarted('user1', role: role);
        expect(scheduler.scheduled, isNull, reason: role);
      }
    });

    test(
      'unreadable preferences show it off and restore does nothing',
      () async {
        final broken = PlanReminder(
          scheduler: scheduler,
          preferences: () async => throw PlatformException(code: 'error'),
          isWeb: false,
        );

        expect(await broken.settingsFor('fam1'), (
          on: false,
          time: const ReminderTime(9, 0),
        ));
        await broken.restoreFor('fam1');
        expect(scheduler.calls, isEmpty);
      },
    );

    test('each account has its own reminder', () async {
      await reminder.enable('famA', const ReminderTime(7, 30));
      expect(await reminder.settingsFor('famB'), (
        on: false,
        time: const ReminderTime(9, 0),
      ));

      // La familia A cierra sesión y la B entra en el mismo teléfono: la B no
      // recibe el recordatorio de la A.
      await reminder.cancelAll();
      await reminder.restoreFor('famB');
      expect(scheduler.scheduled, isNull);

      // La A vuelve a entrar y su recordatorio regresa.
      await reminder.cancelAll();
      await reminder.restoreFor('famA');
      expect(scheduler.scheduled, const ReminderTime(7, 30));
      expect(await _saved(), {
        'plan_reminder_on.famA': true,
        'plan_reminder_time.famA': '07:30',
      });
    });

    test('tapping the reminder asks to open the plan; cancelAll clears it '
        'and the reminder', () async {
      await reminder.enable('fam1', const ReminderTime(7, 30));

      scheduler.onOpenPlan!();
      expect(reminder.openPlanPending.value, isTrue);

      await reminder.cancelAll();
      expect(reminder.openPlanPending.value, isFalse);
      expect(scheduler.scheduled, isNull);
      // Cerrar sesión no borra lo que eligió la familia.
      expect(await reminder.settingsFor('fam1'), (
        on: true,
        time: const ReminderTime(7, 30),
      ));
    });

    test('cancelAll swallows errors', () async {
      scheduler.errors['cancel'] = PlatformException(code: 'error');

      await reminder.cancelAll();

      expect(scheduler.calls, ['cancel']);
    });

    test('cancelAll does not throw without the notifications plugin', () async {
      // Como en las pruebas unitarias de cerrar sesión: el plugin real no está
      // registrado.
      await PlanReminder(isWeb: false).cancelAll();
    });

    // En testWidgets el reloj es de mentira: pump hace pasar los 2 s al
    // instante. Las llamadas no se esperan con await: si algo se quedara
    // colgado, la prueba falla en vez de quedarse esperando.
    testWidgets('cancelAll gives up after 2 seconds and the next call still '
        'runs', (tester) async {
      scheduler.cancelGate = Completer<void>(); // El teléfono nunca contesta.
      var returned = false;
      unawaited(reminder.cancelAll().then((_) => returned = true));

      await tester.pump(const Duration(milliseconds: 1999));
      expect(returned, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      expect(returned, isTrue);

      SharedPreferences.setMockInitialValues({_onKey: true, _timeKey: '06:45'});
      unawaited(reminder.restoreFor('fam1'));
      await tester.pump();
      expect(scheduler.scheduled, const ReminderTime(6, 45));
    });

    testWidgets('cancelAll waits at most 2 seconds for an earlier call and '
        'cancels as soon as it ends', (tester) async {
      SharedPreferences.setMockInitialValues({_onKey: true, _timeKey: '06:45'});
      scheduler.initGate = Completer<void>(); // El teléfono tarda en contestar.
      unawaited(reminder.restoreFor('fam1'));
      await tester.pump();
      expect(scheduler.calls, ['init']);

      // Cerrar sesión no se queda esperando...
      var returned = false;
      unawaited(reminder.cancelAll().then((_) => returned = true));
      await tester.pump(const Duration(seconds: 2));
      expect(returned, isTrue);
      expect(scheduler.calls, ['init']);

      // ...y el recordatorio que se programó tarde se cancela de todos modos.
      scheduler.initGate!.complete();
      await tester.pump();
      expect(scheduler.calls, ['init', 'scheduleDaily 06:45', 'cancel']);
      expect(scheduler.scheduled, isNull);
    });

    test('a cancelAll requested after restoreFor runs after it', () async {
      SharedPreferences.setMockInitialValues({_onKey: true, _timeKey: '06:45'});
      scheduler.initGate = Completer<void>();

      // La sesión se abre y el teléfono tarda en contestar...
      final restore = reminder.restoreFor('fam1');
      await pumpEventQueue();
      expect(scheduler.calls, ['init']);

      // ...y la familia cierra sesión mientras tanto: cancelar espera su turno.
      final signOut = reminder.cancelAll();
      await pumpEventQueue();
      expect(scheduler.calls, ['init']);

      scheduler.initGate!.complete();
      await restore;
      await signOut;
      expect(scheduler.calls, ['init', 'scheduleDaily 06:45', 'cancel']);
      expect(scheduler.scheduled, isNull);
    });

    test('does nothing on web', () async {
      final web = PlanReminder(scheduler: scheduler, isWeb: true);

      expect(web.isSupported, isFalse);
      expect(
        await web.enable('fam1', const ReminderTime(7, 30)),
        ReminderResult.failed,
      );
      await web.disable('fam1');
      await web.restoreFor('fam1');
      await web.cancelAll();
      await web.openSettings();
      expect(await web.notificationsAllowed(), isTrue);
      expect(await web.settingsFor('fam1'), (
        on: false,
        time: const ReminderTime(9, 0),
      ));
      expect(scheduler.calls, isEmpty);
      expect(await _saved(), isEmpty);
    });

    test('notificationsAllowed and openSettings ask the phone, with safe '
        'defaults on error', () async {
      scheduler.enabled = false;
      expect(await reminder.notificationsAllowed(), isFalse);
      await reminder.openSettings();
      expect(scheduler.calls, ['notificationsEnabled', 'openSettings']);

      scheduler.errors
        ..['notificationsEnabled'] = PlatformException(code: 'error')
        ..['openSettings'] = PlatformException(code: 'error');
      expect(await reminder.notificationsAllowed(), isTrue);
      await reminder.openSettings();
    });
  });

  group('LocalReminderScheduler', () {
    late _FakePlugin plugin;
    late LocalReminderScheduler scheduler;

    setUp(() {
      plugin = _FakePlugin();
      scheduler = LocalReminderScheduler(plugin: plugin);
    });

    test('initializes once, with the white icon and no permission '
        'prompt', () async {
      await scheduler.init(onOpenPlan: () {});
      await scheduler.init(onOpenPlan: () {});

      expect(plugin.initialized, 1);
      expect(plugin.settings!.android!.defaultIcon, 'ic_stat_plan_reminder');
      final ios = plugin.settings!.iOS!;
      expect(ios.requestAlertPermission, isFalse);
      expect(ios.requestBadgePermission, isFalse);
      expect(ios.requestSoundPermission, isFalse);
    });

    test('tries again after a failed initialization', () async {
      plugin.initializeError = PlatformException(code: 'invalid_icon');

      await expectLater(
        scheduler.init(onOpenPlan: () {}),
        throwsA(isA<PlatformException>()),
      );
      await scheduler.init(onOpenPlan: () {});

      expect(plugin.initialized, 2);
    });

    test('opens the plan when the reminder launched the app or is '
        'tapped', () async {
      var opened = 0;
      plugin.launch = const NotificationAppLaunchDetails(
        true,
        notificationResponse: _tapOnReminder,
      );

      await scheduler.init(onOpenPlan: () => opened++);
      expect(opened, 1);

      plugin.onResponse!(_tapOnReminder);
      expect(opened, 2);

      plugin.onResponse!(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: 'otra',
        ),
      );
      expect(opened, 2);
    });

    test('does not open the plan on a normal start', () async {
      var opened = 0;
      plugin.launch = const NotificationAppLaunchDetails(false);

      await scheduler.init(onOpenPlan: () => opened++);

      expect(opened, 0);
    });

    test('schedules one daily reminder with generic text only', () async {
      await scheduler.init(onOpenPlan: () {});
      await scheduler.scheduleDaily(const ReminderTime(7, 30));
      await scheduler.scheduleDaily(const ReminderTime(20, 15));

      // El mismo id: el segundo reemplaza al primero.
      expect(plugin.scheduled.map((s) => s.id), [1, 1]);
      final reminder = plugin.scheduled.last;
      expect(reminder.title, 'BAMX Guadalajara');
      expect(reminder.body, 'Revisa tu plan de comidas de hoy');
      expect(reminder.payload, 'plan');
      expect(reminder.mode, AndroidScheduleMode.inexactAllowWhileIdle);
      expect(reminder.repeat, DateTimeComponents.time);
      expect(reminder.details.android!.channelId, 'plan_reminder');
      expect(reminder.details.android!.icon, 'ic_stat_plan_reminder');
      expect(reminder.details.iOS, isNotNull);
      // Sin el plugin de la zona horaria (pruebas) usa la de Guadalajara.
      expect(reminder.date.location.name, 'America/Mexico_City');
      expect((reminder.date.hour, reminder.date.minute), (20, 15));
      expect(reminder.date.isAfter(tz.TZDateTime.now(tz.local)), isTrue);
    });

    test('cancel removes every notification and openSettings opens the '
        'app settings', () async {
      await scheduler.cancel();
      await scheduler.openSettings();

      expect(plugin.cancelled, 1);
      expect(plugin.settingsOpened, 1);
    });

    test('reads the permission answers; unknown counts as not granted but '
        'allowed', () async {
      expect(await scheduler.requestPermission(), isFalse);
      expect(await scheduler.notificationsEnabled(), isTrue);

      plugin.android = _FakeAndroid(granted: true, enabled: false);
      expect(await scheduler.requestPermission(), isTrue);
      expect(await scheduler.notificationsEnabled(), isFalse);

      plugin.android = _FakeAndroid();
      expect(await scheduler.requestPermission(), isFalse);
      expect(await scheduler.notificationsEnabled(), isTrue);
    });
  });
}
