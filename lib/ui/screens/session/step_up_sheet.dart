import 'package:flutter/material.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/pill.dart';

/// Ya hay una revisión en curso: un segundo toque en el mismo botón no abre
/// otro sheet ni repite la escritura.
bool _asking = false;

/// Antes de una acción sensible del staff (crear cuentas, revisar solicitudes,
/// publicar recetas, cancelar o reasignar entregas): si el inicio de sesión ya
/// no es reciente pide la contraseña. Regresa false si no se confirmó (el
/// sheet se cerró); en ese caso no se debe escribir nada. Las reglas exigen lo
/// mismo (recentlySignedIn en firestore.rules).
Future<bool> ensureRecentSignIn(BuildContext context) async {
  if (_asking) return false;
  _asking = true;
  try {
    final repository = AuthRepository();
    if (await repository.hasRecentSignIn()) return true;
    if (!context.mounted) return false;
    final confirmed = await showAppBottomSheet<bool>(
      context,
      // Arrastrar para cerrar ignoraría AppSheet.busy mientras se confirma.
      enableDrag: false,
      builder: (_) => StepUpSheet(reauthenticate: repository.reauthenticate),
    );
    return confirmed ?? false;
  } finally {
    _asking = false;
  }
}

/// Pide la contraseña de quien tiene la sesión y cierra con true cuando
/// [reauthenticate] la acepta.
class StepUpSheet extends StatefulWidget {
  const StepUpSheet({super.key, required this.reauthenticate});

  /// AuthRepository.reauthenticate; las pruebas pasan uno falso.
  final Future<void> Function(String password) reauthenticate;

  @override
  State<StepUpSheet> createState() => _StepUpSheetState();
}

class _StepUpSheetState extends State<StepUpSheet> {
  final _password = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_password.text.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });

    String? error;
    try {
      await widget.reauthenticate(_password.text);
    } on AuthException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'No se pudo confirmar tu identidad. Intenta de nuevo.';
    }
    if (!mounted) return;

    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _checking = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;

    return AppSheet(
      title: 'Confirma tu identidad',
      busy: _checking,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Por seguridad, escribe tu contraseña para continuar.',
            style: AppText.nunito(15, 22.5),
          ),
          const SizedBox(height: 16),
          LabeledField(
            label: 'Contraseña',
            child: AppTextField(
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _confirm(),
            ),
          ),
        ],
      ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            Semantics(
              liveRegion: true,
              child: InfoBanner(
                message: error,
                background: AppColors.dangerSoft,
                foreground: AppColors.dangerText,
              ),
            ),
            const SizedBox(height: 12),
          ],
          PrimaryButton(
            label: 'Confirmar',
            icon: AppIcons.check,
            loading: _checking,
            onPressed: _password.text.isEmpty ? null : _confirm,
          ),
        ],
      ),
    );
  }
}
