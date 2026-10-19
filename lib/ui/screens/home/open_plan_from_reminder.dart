import 'package:flutter/widgets.dart';

import '../../../data/plan_reminder.dart';

/// Para la pantalla de inicio de la familia: abre el plan cuando la familia
/// toca el recordatorio ([PlanReminder.openPlanPending]). Si lo tocó antes de
/// que la pantalla exista (la app se abrió con él), empieza en el plan. Cada
/// toque se atiende una vez: la bandera vuelve a false.
mixin OpenPlanFromReminder<T extends StatefulWidget> on State<T> {
  ValueNotifier<bool> get _pending => PlanReminder.instance.openPlanPending;

  /// Cambia a la pestaña del plan. Al abrir la pantalla se llama antes del
  /// primer build; después, dentro de setState.
  void showPlan();

  @override
  void initState() {
    super.initState();
    if (_takePending()) showPlan();
    _pending.addListener(_openPlan);
  }

  @override
  void dispose() {
    _pending.removeListener(_openPlan);
    super.dispose();
  }

  void _openPlan() {
    if (_takePending()) setState(showPlan);
  }

  /// true si la familia tocó el recordatorio; la bandera vuelve a false.
  bool _takePending() {
    if (!_pending.value) return false;
    _pending.value = false;
    return true;
  }
}
