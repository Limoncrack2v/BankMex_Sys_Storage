import 'dart:async';

import 'package:bank_storage_app/data/plan_reminder.dart';

/// [ReminderScheduler] de mentira para `PlanReminder(scheduler: ...)`: anota
/// en [calls] lo que se le pide y guarda en [scheduled] lo programado.
class FakeReminderScheduler implements ReminderScheduler {
  /// Las llamadas en orden; scheduleDaily lleva la hora ('scheduleDaily 07:30').
  final calls = <String>[];

  /// Error que lanza cada método, por nombre ('init', 'scheduleDaily'...).
  final errors = <String, Object>{};

  /// Lo que contesta notificationsEnabled.
  bool enabled = true;

  /// Lo que contesta requestPermission; si es true también las enciende.
  bool grantPermission = true;

  /// Si no son null, init y cancel esperan a que se completen.
  Completer<void>? initGate;
  Completer<void>? cancelGate;

  /// La hora programada; null si no hay recordatorio.
  ReminderTime? scheduled;

  /// El callback que recibió init: llamarlo es tocar el recordatorio.
  void Function()? onOpenPlan;

  void _record(String method, [String? detail]) {
    calls.add(detail == null ? method : '$method $detail');
    final error = errors[method];
    if (error != null) throw error;
  }

  @override
  Future<void> init({required void Function() onOpenPlan}) async {
    _record('init');
    this.onOpenPlan = onOpenPlan;
    await initGate?.future;
  }

  @override
  Future<bool> notificationsEnabled() async {
    _record('notificationsEnabled');
    return enabled;
  }

  @override
  Future<bool> requestPermission() async {
    _record('requestPermission');
    if (grantPermission) enabled = true;
    return grantPermission;
  }

  @override
  Future<void> scheduleDaily(ReminderTime time) async {
    _record('scheduleDaily', time.toStorage());
    scheduled = time;
  }

  @override
  Future<void> cancel() async {
    _record('cancel');
    await cancelGate?.future;
    scheduled = null;
  }

  @override
  Future<void> openSettings() async => _record('openSettings');
}
