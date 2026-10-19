import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_10y.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Hora del día del recordatorio, en formato de 24 horas.
@immutable
class ReminderTime {
  const ReminderTime(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24),
      assert(minute >= 0 && minute < 60);

  final int hour;
  final int minute;

  /// Lee una hora guardada con [toStorage] ('HH:mm'); null si no es válida.
  static ReminderTime? tryParse(String value) {
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(value);
    if (match == null) return null;
    return ReminderTime(int.parse(match[1]!), int.parse(match[2]!));
  }

  /// 'HH:mm' con ceros a la izquierda, por ejemplo '09:05'.
  String toStorage() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is ReminderTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => 'ReminderTime(${toStorage()})';
}

/// La siguiente vez que toca el recordatorio: hoy a [time] si todavía no
/// pasa, si no mañana a esa hora, en la zona horaria de [now].
tz.TZDateTime nextReminderAt(tz.TZDateTime now, ReminderTime time) {
  final today = tz.TZDateTime(
    now.location,
    now.year,
    now.month,
    now.day,
    time.hour,
    time.minute,
  );
  if (today.isAfter(now)) return today;
  // Por fecha y no sumando 24 horas, para que un cambio de horario no la mueva.
  return tz.TZDateTime(
    now.location,
    now.year,
    now.month,
    now.day + 1,
    time.hour,
    time.minute,
  );
}

/// Lo que el recordatorio le pide al teléfono. [LocalReminderScheduler] es el
/// real; las pruebas usan uno de mentira.
abstract interface class ReminderScheduler {
  /// Prepara las notificaciones (una sola vez). [onOpenPlan] se llama cuando
  /// la familia toca el recordatorio, también si la app se abrió con él.
  Future<void> init({required void Function() onOpenPlan});

  /// Pide permiso para mostrar notificaciones; true si lo dieron.
  Future<bool> requestPermission();

  /// Si el teléfono deja que la app muestre notificaciones.
  Future<bool> notificationsEnabled();

  /// Programa el recordatorio todos los días a [time] y reemplaza al
  /// anterior. Va después de [init].
  Future<void> scheduleDaily(ReminderTime time);

  /// Quita el recordatorio programado y el que ya se mostró.
  Future<void> cancel();

  /// Abre los ajustes de notificaciones de la app en el teléfono.
  Future<void> openSettings();
}

/// [ReminderScheduler] con flutter_local_notifications: una notificación
/// local que programa el teléfono, sin servidor, sin FCM y sin tokens.
class LocalReminderScheduler implements ReminderScheduler {
  /// [plugin] es para las pruebas.
  LocalReminderScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Siempre el mismo id: programarlo otra vez reemplaza al anterior.
  static const _id = 1;
  static const _payload = 'plan';

  /// res/drawable/ic_stat_plan_reminder.xml. Dart lo pide solo por nombre:
  /// res/raw/keep_bank_storage_app.xml evita que el build release lo borre.
  static const _icon = 'ic_stat_plan_reminder';
  static const _fallbackZone = 'America/Mexico_City';

  Future<void>? _ready;

  @override
  Future<void> init({required void Function() onOpenPlan}) async {
    final ready = _ready ??= _init(onOpenPlan);
    try {
      await ready;
    } catch (_) {
      // Se vuelve a intentar en la siguiente llamada.
      if (identical(_ready, ready)) _ready = null;
      rethrow;
    }
  }

  Future<void> _init(void Function() onOpenPlan) async {
    tz_data.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      // Sin el plugin (pruebas) o con una zona que no está en la base.
      tz.setLocalLocation(tz.getLocation(_fallbackZone));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_icon),
        // En iOS no pide permiso al abrir la app: se pide al encenderlo.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == _payload) onOpenPlan();
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if ((launch?.didNotificationLaunchApp ?? false) &&
        launch?.notificationResponse?.payload == _payload) {
      onOpenPlan();
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> requestPermission() async {
    final android = _android;
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return await _ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  @override
  Future<bool> notificationsEnabled() async {
    final android = _android;
    if (android != null) return await android.areNotificationsEnabled() ?? true;
    final ios = _ios;
    if (ios != null) return (await ios.checkPermissions())?.isEnabled ?? true;
    return true;
  }

  @override
  Future<void> scheduleDaily(ReminderTime time) => _plugin.zonedSchedule(
    id: _id,
    // Texto fijo: ni recetas ni datos de la familia en la pantalla bloqueada
    // (MASVS-PLATFORM-3).
    title: 'BAMX Guadalajara',
    body: 'Revisa tu plan de comidas de hoy',
    payload: _payload,
    scheduledDate: nextReminderAt(tz.TZDateTime.now(tz.local), time),
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'plan_reminder',
        'Recordatorio del plan',
        channelDescription: 'Un aviso al día para revisar tu plan de comidas',
        icon: _icon,
      ),
      iOS: DarwinNotificationDetails(),
    ),
    // Inexacta: no necesita el permiso de alarmas exactas; puede llegar unos
    // minutos tarde.
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    matchDateTimeComponents: DateTimeComponents.time,
  );

  @override
  Future<void> cancel() => _plugin.cancelAll();

  @override
  Future<void> openSettings() async {
    await _plugin.openAppNotificationSettings();
  }
}

/// Cómo terminó [PlanReminder.enable].
enum ReminderResult {
  /// Quedó programado y guardado.
  scheduled,

  /// El teléfono no dio permiso de notificaciones; no cambió nada.
  permissionDenied,

  /// Algo falló al programarlo; se queda como estaba.
  failed,
}

/// Recordatorio diario del plan de comidas, solo para familias y nunca en
/// web: una notificación local con un texto genérico (MASVS-PLATFORM-3,
/// OWASP Mobile M6). Cada cuenta lo enciende y elige la hora en su teléfono;
/// se vuelve a programar al abrir su sesión y se cancela al cerrarla.
class PlanReminder {
  PlanReminder({
    ReminderScheduler? scheduler,
    Future<SharedPreferences> Function()? preferences,
    this._isWeb = kIsWeb,
  }) : _scheduler = scheduler ?? LocalReminderScheduler(),
       _preferences = preferences ?? SharedPreferences.getInstance;

  static final instance = PlanReminder();

  /// La hora mientras la familia no elige otra.
  static const defaultTime = ReminderTime(9, 0);

  /// Lo más que se espera al sistema para cancelar: cerrar sesión no se
  /// queda esperando.
  static const _cancelTimeout = Duration(seconds: 2);

  final ReminderScheduler _scheduler;
  final Future<SharedPreferences> Function() _preferences;
  final bool _isWeb;

  /// true cuando la familia toca el recordatorio. La pantalla de inicio de la
  /// familia abre el plan y lo regresa a false.
  final ValueNotifier<bool> openPlanPending = ValueNotifier(false);

  /// La última operación con el teléfono que se pidió; null cuando ya
  /// terminaron todas.
  Future<void>? _last;

  /// false en web: ahí no hay recordatorio y los métodos no hacen nada.
  bool get isSupported => !_isWeb;

  // Por cuenta (uid), nunca con nombres. Se quedan al cerrar sesión: el
  // recordatorio vuelve si la misma familia entra otra vez en este teléfono.
  static String _onKey(String uid) => 'plan_reminder_on.$uid';
  static String _timeKey(String uid) => 'plan_reminder_time.$uid';

  /// Si [uid] lo tiene encendido y a qué hora. Sin nada guardado (o si no se
  /// puede leer, o en web): apagado, a las [defaultTime].
  Future<({bool on, ReminderTime time})> settingsFor(String uid) async {
    if (!_isWeb) {
      try {
        return await _read(uid);
      } catch (_) {
        // Se muestra apagado; encenderlo lo vuelve a guardar.
      }
    }
    return (on: false, time: defaultTime);
  }

  /// Lo enciende para [uid] a [time], o le cambia la hora. Si el teléfono no
  /// deja mostrar notificaciones, primero pide permiso. No lanza errores; en
  /// web regresa [ReminderResult.failed].
  Future<ReminderResult> enable(String uid, ReminderTime time) async {
    if (_isWeb) return ReminderResult.failed;
    return _serial(() async {
      try {
        await _init();
        if (!await _scheduler.notificationsEnabled() &&
            !await _scheduler.requestPermission()) {
          return ReminderResult.permissionDenied;
        }
        // Primero se programa: si falla, lo guardado no cambia.
        await _scheduler.scheduleDaily(time);
        final prefs = await _preferences();
        await prefs.setBool(_onKey(uid), true);
        await prefs.setString(_timeKey(uid), time.toStorage());
        return ReminderResult.scheduled;
      } catch (_) {
        return ReminderResult.failed;
      }
    });
  }

  /// Lo apaga para [uid]; la hora se queda guardada para cuando lo vuelva a
  /// encender. No lanza errores.
  Future<void> disable(String uid) async {
    if (_isWeb) return;
    try {
      await _serial(() async {
        await (await _preferences()).setBool(_onKey(uid), false);
        await _cancel();
      });
    } catch (_) {
      // Ya quedó apagado: restoreFor lo vuelve a cancelar al abrir la sesión.
    }
  }

  /// Al abrir la sesión de la familia [uid]: lo vuelve a programar si lo
  /// tiene encendido (sin pedir permiso), si no lo cancela. No lanza errores.
  Future<void> restoreFor(String uid) async {
    if (_isWeb) return;
    try {
      await _serial(() async {
        final settings = await _read(uid);
        if (settings.on) {
          await _init();
          await _scheduler.scheduleDaily(settings.time);
        } else {
          await _cancel();
        }
      });
    } catch (_) {
      // La sesión se abre igual; se vuelve a intentar en la siguiente.
    }
  }

  /// Cancela el recordatorio de este teléfono, sea de la cuenta que sea. Es
  /// para cerrar sesión: también funciona sin conexión, espera a lo más 2 s y
  /// no lanza errores (ni sin el plugin, como en las pruebas).
  Future<void> cancelAll() async {
    openPlanPending.value = false;
    if (_isWeb) return;
    try {
      await _serial(_cancel).timeout(_cancelTimeout);
    } catch (_) {
      // Cerrar sesión sigue aunque no se haya podido cancelar.
    }
  }

  /// Si el teléfono deja que la app muestre notificaciones. true si no se
  /// sabe (y en web), para no avisar de más.
  Future<bool> notificationsAllowed() async {
    if (_isWeb) return true;
    try {
      return await _scheduler.notificationsEnabled();
    } catch (_) {
      return true;
    }
  }

  /// Abre los ajustes de notificaciones de la app en el teléfono.
  Future<void> openSettings() async {
    if (_isWeb) return;
    try {
      await _scheduler.openSettings();
    } catch (_) {
      // No hay ajustes que abrir; el aviso en pantalla ya dice qué hacer.
    }
  }

  Future<({bool on, ReminderTime time})> _read(String uid) async {
    final prefs = await _preferences();
    final time = prefs.getString(_timeKey(uid));
    return (
      on: prefs.getBool(_onKey(uid)) ?? false,
      time: (time == null ? null : ReminderTime.tryParse(time)) ?? defaultTime,
    );
  }

  Future<void> _init() =>
      _scheduler.init(onOpenPlan: () => openPlanPending.value = true);

  Future<void> _cancel() => _scheduler.cancel().timeout(_cancelTimeout);

  /// Corre [operation] cuando terminan las que se pidieron antes. Así un
  /// restoreFor que tarda no vuelve a programar el recordatorio después de un
  /// cancelAll que se pidió más tarde.
  Future<T> _serial<T>(Future<T> Function() operation) {
    final previous = _last;
    // Sin nada pendiente empieza ya, sin esperar a un Future que ya terminó
    // (en las pruebas puede ser de otra zona y no avisar nunca).
    final result = previous == null
        ? Future.sync(operation)
        : previous.then((_) => operation());
    late final Future<void> last;
    last = result.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_last, last)) _last = null;
    });
    _last = last;
    return result;
  }
}
