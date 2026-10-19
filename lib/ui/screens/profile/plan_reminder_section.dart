import 'package:flutter/material.dart';

import '../../../data/plan_reminder.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/option_button.dart';
import '../../widgets/pill.dart';

/// "Recordatorio del plan" del Perfil: la familia enciende un aviso al día en
/// este teléfono para revisar su plan de comidas y elige la hora
/// ([PlanReminder]). Se guarda por cuenta ([uid]).
class PlanReminderSection extends StatefulWidget {
  const PlanReminderSection({
    super.key,
    required this.uid,
    this.reminder,
    this.pickTime,
  });

  /// La cuenta de la familia (users/{uid}).
  final String uid;

  /// [PlanReminder.instance] si es null.
  final PlanReminder? reminder;

  /// Pide la hora a partir de `initial`; null si la familia cancela. Si es
  /// null, [showTimePicker].
  final Future<TimeOfDay?> Function(BuildContext context, TimeOfDay initial)?
  pickTime;

  @override
  State<PlanReminderSection> createState() => _PlanReminderSectionState();
}

class _PlanReminderSectionState extends State<PlanReminderSection>
    with WidgetsBindingObserver {
  PlanReminder get _reminder => widget.reminder ?? PlanReminder.instance;

  /// Mientras se leen los ajustes guardados.
  bool _loading = true;

  /// Mientras se enciende, se apaga o se cambia la hora.
  bool _busy = false;

  bool _on = false;
  ReminderTime _time = PlanReminder.defaultTime;

  /// Al encenderlo, el teléfono no dio permiso de notificaciones.
  bool _denied = false;

  /// El teléfono no deja que la app muestre notificaciones.
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // La familia puede volver de los ajustes del teléfono.
    if (state == AppLifecycleState.resumed) _recheckNotifications();
  }

  Future<void> _load() async {
    final settings = await _reminder.settingsFor(widget.uid);
    final allowed = !settings.on || await _reminder.notificationsAllowed();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _on = settings.on;
      _time = settings.time;
      _blocked = !allowed;
    });
  }

  /// Quita el aviso si el teléfono ya deja mostrar notificaciones, o lo
  /// muestra si las apagaron.
  Future<void> _recheckNotifications() async {
    if (!_on && !_denied) return;
    final allowed = await _reminder.notificationsAllowed();
    if (!mounted) return;
    setState(() {
      _blocked = !allowed;
      if (allowed) _denied = false;
    });
  }

  /// Una acción a la vez: mientras corre, los botones no responden.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _turnOn() async {
    if (!_on) await _run(() => _enable(_time));
  }

  Future<void> _turnOff() async {
    if (_on) await _run(_disable);
  }

  Future<void> _changeTime() => _run(() async {
    final picked = await (widget.pickTime ?? _showTimePicker)(
      context,
      TimeOfDay(hour: _time.hour, minute: _time.minute),
    );
    if (picked == null || !mounted) return;
    await _enable(ReminderTime(picked.hour, picked.minute));
  });

  /// Lo enciende a [time]; también sirve para cambiar la hora.
  Future<void> _enable(ReminderTime time) async {
    final result = await _reminder.enable(widget.uid, time);
    if (!mounted) return;
    setState(() {
      _denied = result == ReminderResult.permissionDenied;
      if (result == ReminderResult.scheduled) {
        _on = true;
        _time = time;
        _blocked = false;
      }
    });
    // La sección ya muestra si quedó encendido y a qué hora, y el aviso de
    // permisos dice qué hacer: solo el error va en un snackbar.
    if (result == ReminderResult.failed) {
      _showSnack('No se pudo guardar el recordatorio. Intenta de nuevo.');
    }
  }

  Future<void> _disable() async {
    await _reminder.disable(widget.uid);
    if (!mounted) return;
    setState(() {
      _on = false;
      _denied = false;
      _blocked = false;
    });
  }

  static Future<TimeOfDay?> _showTimePicker(
    BuildContext context,
    TimeOfDay initial,
  ) => showTimePicker(context: context, initialTime: initial);

  /// La hora como la escribe el teléfono (en es_MX, "9:00").
  String _format(ReminderTime time) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay(hour: time.hour, minute: time.minute),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_loading && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recordatorio del plan',
          style: AppText.nunito(15, 22.5, weight: FontWeight.w700),
        ),
        Text(
          'Te avisamos una vez al día para que revises tu plan de comidas. '
          'El aviso no muestra datos de tu familia.',
          style: AppText.nunito(14, 21, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        OptionButtonRow(
          options: [
            OptionButton(
              label: 'Apagado',
              selected: !_loading && !_on,
              onTap: enabled ? _turnOff : null,
            ),
            OptionButton(
              label: 'Encendido',
              selected: !_loading && _on,
              onTap: enabled ? _turnOn : null,
            ),
          ],
        ),
        if (_on) ...[const SizedBox(height: 8), _buildTime()],
        if (_denied)
          ..._buildSettingsBanner(
            'Para recibir el recordatorio, permite las notificaciones de la '
            'app en los ajustes de tu teléfono.',
            background: AppColors.dangerSoft,
            foreground: AppColors.dangerText,
          )
        else if (_on && _blocked)
          ..._buildSettingsBanner(
            'Las notificaciones de la app están apagadas en tu teléfono, así '
            'que el recordatorio no va a llegar.',
            background: AppColors.warningSoft,
            foreground: AppColors.warningText,
          ),
      ],
    );
  }

  /// La hora a la izquierda y "Cambiar hora" a la derecha; si no caben en un
  /// renglón (letra grande), el enlace baja.
  Widget _buildTime() {
    final time = _format(_time);
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Semantics(
            container: true,
            label: 'Hora del recordatorio: $time',
            excludeSemantics: true,
            child: Text(
              'Todos los días a las $time',
              style: AppText.nunito(15, 22.5),
            ),
          ),
          Semantics(
            container: true,
            button: true,
            label: 'Cambiar la hora del recordatorio',
            onTap: _changeTime,
            excludeSemantics: true,
            child: TextLinkButton(
              label: 'Cambiar hora',
              onPressed: _changeTime,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSettingsBanner(
    String message, {
    required Color background,
    required Color foreground,
  }) => [
    const SizedBox(height: 8),
    InfoBanner(
      message: message,
      background: background,
      foreground: foreground,
    ),
    const SizedBox(height: 8),
    // Como "Reintentar" debajo de un aviso (#51).
    SizedBox(
      width: double.infinity,
      child: SecondaryButton(
        label: 'Abrir ajustes',
        onPressed: _reminder.openSettings,
      ),
    ),
  ];
}
