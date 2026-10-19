import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bank_storage_app/data/plan_reminder.dart';
import 'package:bank_storage_app/ui/screens/profile/plan_reminder_section.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/option_button.dart';
import 'package:bank_storage_app/ui/widgets/pill.dart';

import 'helpers/fake_reminder_scheduler.dart';
import 'helpers/large_text.dart';

const _uid = 'familia-1';

const _deniedMessage =
    'Para recibir el recordatorio, permite las notificaciones de la app en '
    'los ajustes de tu teléfono.';
const _blockedMessage =
    'Las notificaciones de la app están apagadas en tu teléfono, así que el '
    'recordatorio no va a llegar.';

/// La sección en es_MX, como en la app (la hora sale "9:00").
Future<void> _pumpSection(
  WidgetTester tester,
  PlanReminder reminder, {
  Future<TimeOfDay?> Function(BuildContext context, TimeOfDay initial)?
  pickTime,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: AppTheme.locale,
      supportedLocales: const [AppTheme.locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(
        body: PlanReminderSection(
          uid: _uid,
          reminder: reminder,
          pickTime: pickTime,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Como en el Perfil: en una lista con 16 de margen, en es_MX.
Widget _inProfile(PlanReminder reminder) => Localizations(
  locale: AppTheme.locale,
  delegates: GlobalMaterialLocalizations.delegates,
  child: ListView(
    padding: const EdgeInsets.all(16),
    children: [PlanReminderSection(uid: _uid, reminder: reminder)],
  ),
);

OptionButton _option(WidgetTester tester, String label) =>
    tester.widget<OptionButton>(find.widgetWithText(OptionButton, label));

/// Lo que avisa el teléfono cuando la familia sale de la app (p. ej. a los
/// ajustes) y regresa.
Future<void> _leaveAndComeBack(WidgetTester tester) async {
  for (final state in [AppLifecycleState.paused, AppLifecycleState.resumed]) {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage(state.toString()),
      (_) {},
    );
  }
}

void main() {
  late FakeReminderScheduler scheduler;
  late PlanReminder reminder;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    scheduler = FakeReminderScheduler();
    reminder = PlanReminder(scheduler: scheduler, isWeb: false);
  });

  testWidgets('is off by default and does not touch the phone', (tester) async {
    await _pumpSection(tester, reminder);

    expect(_option(tester, 'Apagado').selected, isTrue);
    expect(_option(tester, 'Encendido').selected, isFalse);
    expect(find.textContaining('Todos los días'), findsNothing);
    expect(find.byType(InfoBanner), findsNothing);
    expect(scheduler.calls, isEmpty);
  });

  testWidgets('turning it on schedules it at 9:00 and shows the time', (
    tester,
  ) async {
    await _pumpSection(tester, reminder);

    await tester.tap(find.text('Encendido'));
    await tester.pumpAndSettle();

    expect(scheduler.scheduled, const ReminderTime(9, 0));
    expect(_option(tester, 'Encendido').selected, isTrue);
    expect(find.text('Todos los días a las 9:00'), findsOneWidget);
    expect(
      find.text('Te recordaremos tu plan todos los días a las 9:00.'),
      findsOneWidget,
    );
    expect(await reminder.settingsFor(_uid), (
      on: true,
      time: const ReminderTime(9, 0),
    ));
  });

  testWidgets('turning it on again uses the time it had', (tester) async {
    await reminder.enable(_uid, const ReminderTime(7, 30));
    await reminder.disable(_uid);
    await _pumpSection(tester, reminder);
    expect(_option(tester, 'Apagado').selected, isTrue);

    await tester.tap(find.text('Encendido'));
    await tester.pumpAndSettle();

    expect(scheduler.scheduled, const ReminderTime(7, 30));
    expect(find.text('Todos los días a las 7:30'), findsOneWidget);
  });

  testWidgets('shows a reminder that is already on without asking again', (
    tester,
  ) async {
    await reminder.enable(_uid, const ReminderTime(18, 45));
    scheduler.calls.clear();
    await _pumpSection(tester, reminder);

    expect(_option(tester, 'Encendido').selected, isTrue);
    expect(find.text('Todos los días a las 18:45'), findsOneWidget);
    expect(find.byType(InfoBanner), findsNothing);
    // Solo revisa si el teléfono deja mostrar notificaciones.
    expect(scheduler.calls, ['notificationsEnabled']);
  });

  testWidgets('a denied permission shows the banner and stays off', (
    tester,
  ) async {
    scheduler
      ..enabled = false
      ..grantPermission = false;
    await _pumpSection(tester, reminder);

    await tester.tap(find.text('Encendido'));
    await tester.pumpAndSettle();

    expect(scheduler.calls, [
      'init',
      'notificationsEnabled',
      'requestPermission',
    ]);
    expect(find.text(_deniedMessage), findsOneWidget);
    expect(find.text('Abrir ajustes'), findsOneWidget);
    expect(_option(tester, 'Apagado').selected, isTrue);
    expect(find.textContaining('Todos los días'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect((await reminder.settingsFor(_uid)).on, isFalse);
  });

  testWidgets('"Abrir ajustes" opens the phone settings', (tester) async {
    scheduler
      ..enabled = false
      ..grantPermission = false;
    await _pumpSection(tester, reminder);
    await tester.tap(find.text('Encendido'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Abrir ajustes'));
    await tester.pump();

    expect(scheduler.calls.last, 'openSettings');
  });

  testWidgets('hides the permission banner once the phone allows them', (
    tester,
  ) async {
    scheduler
      ..enabled = false
      ..grantPermission = false;
    await _pumpSection(tester, reminder);
    await tester.tap(find.text('Encendido'));
    await tester.pumpAndSettle();
    expect(find.text(_deniedMessage), findsOneWidget);

    // En los ajustes del teléfono permite las notificaciones y regresa.
    scheduler.enabled = true;
    await _leaveAndComeBack(tester);
    await tester.pumpAndSettle();

    expect(find.text(_deniedMessage), findsNothing);
    // No se enciende solo: la familia lo vuelve a encender.
    expect(_option(tester, 'Apagado').selected, isTrue);
  });

  testWidgets('"Cambiar hora" asks for the time and reschedules', (
    tester,
  ) async {
    await reminder.enable(_uid, const ReminderTime(9, 0));
    final asked = <TimeOfDay>[];
    await _pumpSection(
      tester,
      reminder,
      pickTime: (context, initial) async {
        asked.add(initial);
        return const TimeOfDay(hour: 20, minute: 15);
      },
    );

    await tester.tap(find.text('Cambiar hora'));
    await tester.pumpAndSettle();

    expect(asked, [const TimeOfDay(hour: 9, minute: 0)]);
    expect(scheduler.scheduled, const ReminderTime(20, 15));
    expect(find.text('Todos los días a las 20:15'), findsOneWidget);
    expect(
      find.text('Te recordaremos tu plan todos los días a las 20:15.'),
      findsOneWidget,
    );
    expect(await reminder.settingsFor(_uid), (
      on: true,
      time: const ReminderTime(20, 15),
    ));
  });

  testWidgets('opens the clock at the saved time; cancelling changes '
      'nothing', (tester) async {
    await reminder.enable(_uid, const ReminderTime(18, 45));
    scheduler.calls.clear();
    await _pumpSection(tester, reminder);

    await tester.tap(find.text('Cambiar hora'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TimePickerDialog>(find.byType(TimePickerDialog))
          .initialTime,
      const TimeOfDay(hour: 18, minute: 45),
    );

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsNothing);
    expect(scheduler.calls, ['notificationsEnabled']);
    expect(find.text('Todos los días a las 18:45'), findsOneWidget);
  });

  testWidgets('turning it off cancels it and keeps the time', (tester) async {
    await reminder.enable(_uid, const ReminderTime(20, 15));
    await _pumpSection(tester, reminder);

    await tester.tap(find.text('Apagado'));
    await tester.pumpAndSettle();

    expect(scheduler.calls.last, 'cancel');
    expect(scheduler.scheduled, isNull);
    expect(_option(tester, 'Apagado').selected, isTrue);
    expect(find.textContaining('Todos los días'), findsNothing);
    expect(find.text('Apagaste el recordatorio del plan.'), findsOneWidget);
    expect(await reminder.settingsFor(_uid), (
      on: false,
      time: const ReminderTime(20, 15),
    ));
  });

  testWidgets('warns when the phone blocks the notifications', (tester) async {
    await reminder.enable(_uid, const ReminderTime(9, 0));
    scheduler.enabled = false;
    await _pumpSection(tester, reminder);

    expect(_option(tester, 'Encendido').selected, isTrue);
    expect(find.text(_blockedMessage), findsOneWidget);
    expect(find.text(_deniedMessage), findsNothing);

    await tester.tap(find.text('Abrir ajustes'));
    await tester.pump();
    expect(scheduler.calls.last, 'openSettings');
  });

  testWidgets('checks the phone again when the family comes back', (
    tester,
  ) async {
    await reminder.enable(_uid, const ReminderTime(9, 0));
    scheduler.enabled = false;
    await _pumpSection(tester, reminder);
    expect(find.text(_blockedMessage), findsOneWidget);

    scheduler.enabled = true;
    await _leaveAndComeBack(tester);
    await tester.pumpAndSettle();

    expect(find.text(_blockedMessage), findsNothing);
    expect(_option(tester, 'Encendido').selected, isTrue);
  });

  testWidgets('a failure keeps it off and says so', (tester) async {
    scheduler.errors['scheduleDaily'] = StateError('sin alarmas');
    await _pumpSection(tester, reminder);

    await tester.tap(find.text('Encendido'));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo guardar el recordatorio. Intenta de nuevo.'),
      findsOneWidget,
    );
    expect(_option(tester, 'Apagado').selected, isTrue);
    expect((await reminder.settingsFor(_uid)).on, isFalse);
  });

  testWidgets('ignores taps while it is turning on', (tester) async {
    scheduler.initGate = Completer<void>();
    await _pumpSection(tester, reminder);

    await tester.tap(find.text('Encendido'));
    await tester.pump();
    expect(_option(tester, 'Apagado').onTap, isNull);
    expect(_option(tester, 'Encendido').onTap, isNull);
    await tester.tap(find.text('Encendido'));
    await tester.pump();

    scheduler.initGate!.complete();
    await tester.pumpAndSettle();

    expect(scheduler.calls.where((call) => call == 'init'), hasLength(1));
    expect(_option(tester, 'Encendido').selected, isTrue);
    expect(_option(tester, 'Apagado').onTap, isNotNull);
  });

  testWidgets('nothing is selected or tappable while the settings load', (
    tester,
  ) async {
    final preferences = Completer<SharedPreferences>();
    await _pumpSection(
      tester,
      PlanReminder(
        scheduler: scheduler,
        preferences: () => preferences.future,
        isWeb: false,
      ),
    );

    expect(_option(tester, 'Apagado').selected, isFalse);
    expect(_option(tester, 'Encendido').selected, isFalse);
    expect(_option(tester, 'Encendido').onTap, isNull);

    preferences.complete(await SharedPreferences.getInstance());
    await tester.pumpAndSettle();

    expect(_option(tester, 'Apagado').selected, isTrue);
    expect(_option(tester, 'Encendido').onTap, isNotNull);
  });

  testWidgets('reads the time and the change link with clear labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await reminder.enable(_uid, const ReminderTime(9, 0));
    var asked = 0;
    await _pumpSection(
      tester,
      reminder,
      pickTime: (context, initial) async {
        asked++;
        return null;
      },
    );

    expect(
      find.bySemanticsLabel('Hora del recordatorio: 9:00'),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('Cambiar la hora del recordatorio'),
      ),
      isSemantics(isButton: true, hasTapAction: true),
    );

    // TalkBack lo puede activar.
    tester.semantics.tap(
      find.semantics.byLabel('Cambiar la hora del recordatorio'),
    );
    await tester.pumpAndSettle();
    expect(asked, 1);
    semantics.dispose();
  });

  group('large text at 360 dp', () {
    setUpAll(loadAppFonts);

    for (final scale in [1.3, 2.0]) {
      testWidgets('the time and the phone warning fit at ${scale}x', (
        tester,
      ) async {
        await reminder.enable(_uid, const ReminderTime(21, 30));
        scheduler.enabled = false;
        await pumpWithTextScale(tester, _inProfile(reminder), textScale: scale);

        expect(find.text('Todos los días a las 21:30'), findsOneWidget);
        expect(find.text(_blockedMessage), findsOneWidget);
        expect(tester.takeException(), isNull);
        expectNoBrokenWords(tester);
      });

      testWidgets('the permission banner fits at ${scale}x', (tester) async {
        scheduler
          ..enabled = false
          ..grantPermission = false;
        await pumpWithTextScale(tester, _inProfile(reminder), textScale: scale);

        await tester.tap(find.text('Encendido'));
        await tester.pumpAndSettle();

        expect(find.text(_deniedMessage), findsOneWidget);
        expect(tester.takeException(), isNull);
        expectNoBrokenWords(tester);
      });
    }
  });
}
