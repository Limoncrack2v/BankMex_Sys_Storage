import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/models/app_user.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/option_button.dart';
import '../../widgets/pill.dart';

/// Alta de cuentas por el staff: familias (con su hogar) o staff. Después de
/// crearla, el mismo sheet muestra la confirmación. No se puede cerrar
/// mientras se crea la cuenta (sin arrastre y con [AppSheet.busy]).
Future<void> showRegisterAccountSheet(BuildContext context) {
  return showAppBottomSheet<void>(
    context,
    enableDrag: false,
    builder: (_) => const RegisterAccountSheet(),
  );
}

enum _AccountKind { family, staff }

class RegisterAccountSheet extends StatefulWidget {
  const RegisterAccountSheet({super.key});

  @override
  State<RegisterAccountSheet> createState() => _RegisterAccountSheetState();
}

class _RegisterAccountSheetState extends State<RegisterAccountSheet> {
  static const _minPasswordLength = 6;
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Si el alta tarda más que esto (p. ej. Firestore sin conexión después de
  /// crear la cuenta de Auth), el sheet ya se puede cerrar y el resultado se
  /// avisa con un SnackBar.
  static const _slowAfter = Duration(seconds: 15);

  final _familyName = TextEditingController();
  final _address = TextEditingController();
  final _staffName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  _AccountKind _kind = _AccountKind.family;
  bool _obscurePassword = true;
  bool _saving = false;
  bool _slow = false;
  Timer? _slowTimer;
  String? _error;
  String? _successMessage;

  bool get _isFamily => _kind == _AccountKind.family;

  TextEditingController get _name => _isFamily ? _familyName : _staffName;

  bool get _emailValid => _emailPattern.hasMatch(_email.text.trim());

  bool get _passwordValid => _password.text.length >= _minPasswordLength;

  bool get _canSave =>
      _name.text.trim().isNotEmpty &&
      (!_isFamily || _address.text.trim().isNotEmpty) &&
      _emailValid &&
      _passwordValid;

  @override
  void dispose() {
    _slowTimer?.cancel();
    _familyName.dispose();
    _address.dispose();
    _staffName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _onChanged(String _) => setState(() => _error = null);

  void _selectKind(_AccountKind kind) => setState(() {
    _kind = kind;
    _error = null;
  });

  Future<void> _submit() async {
    if (!_canSave || _saving) return;
    FocusScope.of(context).unfocus();

    final messenger = ScaffoldMessenger.of(context);
    final isFamily = _isFamily;
    final name = _name.text.trim();
    final email = _email.text.trim();
    final successMessage = isFamily
        ? '$name ya puede iniciar sesión con $email.'
        : '$name ya puede iniciar sesión como staff con $email.';
    setState(() {
      _saving = true;
      _slow = false;
      _error = null;
    });
    _slowTimer = Timer(_slowAfter, () {
      if (mounted && _saving) setState(() => _slow = true);
    });

    String? error;
    try {
      await AuthRepository().registerAccount(
        role: isFamily ? AppUser.roleFamily : AppUser.roleStaff,
        name: name,
        email: email,
        password: _password.text,
        address: isFamily ? _address.text.trim() : null,
      );
    } on AuthException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'No se pudo crear la cuenta. Intenta de nuevo.';
    }
    _slowTimer?.cancel();

    if (!mounted) {
      // Solo pasa si tardó más de [_slowAfter] y el staff cerró el sheet.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              error == null
                  ? 'Cuenta creada. $successMessage'
                  : 'No se creó la cuenta de $name. $error',
            ),
          ),
        );
      return;
    }

    setState(() {
      _saving = false;
      _slow = false;
      _error = error;
      if (error == null) _successMessage = successMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    final successMessage = _successMessage;
    if (successMessage != null) {
      return AppSheet(
        title: 'Registrar cuenta',
        body: SuccessContent(
          heading: 'Cuenta creada',
          message: successMessage,
          onDone: () => Navigator.of(context).pop(),
        ),
      );
    }

    return AppSheet(
      title: 'Registrar cuenta',
      busy: _saving && !_slow,
      body: IgnorePointer(ignoring: _saving, child: _buildForm()),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_saving && _slow) ...[
            Semantics(
              liveRegion: true,
              child: const InfoBanner(
                message:
                    'Está tardando más de lo normal. Puedes cerrar esta '
                    'ventana; te avisaremos cuando termine.',
                background: AppColors.warningSoft,
                foreground: AppColors.warningText,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_error != null) ...[
            Semantics(
              liveRegion: true,
              child: InfoBanner(
                message: _error!,
                background: AppColors.dangerSoft,
                foreground: AppColors.dangerText,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'Todos los campos son obligatorios.',
            style: AppText.nunito(14, 21, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Crear cuenta',
            icon: AppIcons.check,
            loading: _saving,
            onPressed: _canSave ? _submit : null,
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    final showEmailError = _email.text.trim().isNotEmpty && !_emailValid;
    final showPasswordError = _password.text.isNotEmpty && !_passwordValid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabeledField(
          label: 'Tipo de cuenta',
          child: Row(
            children: [
              Expanded(
                child: OptionButton(
                  label: 'Familia',
                  selected: _isFamily,
                  onTap: () => _selectKind(_AccountKind.family),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OptionButton(
                  label: 'Staff',
                  selected: !_isFamily,
                  onTap: () => _selectKind(_AccountKind.staff),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_isFamily) ...[
          LabeledField(
            label: 'Nombre de la familia',
            required: true,
            child: AppTextField(
              key: const ValueKey('familyName'),
              controller: _familyName,
              hint: 'Familia Ramírez',
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: 100,
              onChanged: _onChanged,
            ),
          ),
          const SizedBox(height: 16),
          LabeledField(
            label: 'Dirección',
            required: true,
            child: AppTextField(
              controller: _address,
              hint: 'Calle, número y colonia',
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.streetAddress,
              maxLength: 200,
              onChanged: _onChanged,
            ),
          ),
        ] else
          LabeledField(
            label: 'Nombre completo',
            required: true,
            child: AppTextField(
              key: const ValueKey('staffName'),
              controller: _staffName,
              hint: 'Nombre y apellidos',
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: 100,
              onChanged: _onChanged,
            ),
          ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Correo electrónico',
          required: true,
          child: AppTextField(
            controller: _email,
            hint: 'correo@ejemplo.com',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            maxLength: 254,
            onChanged: _onChanged,
          ),
        ),
        if (showEmailError) ...[
          const SizedBox(height: 6),
          const _HelperText(
            'Escribe un correo válido, p. ej. nombre@correo.com.',
            color: AppColors.dangerText,
          ),
        ],
        const SizedBox(height: 16),
        LabeledField(
          label: 'Contraseña',
          required: true,
          child: AppTextField(
            controller: _password,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onChanged: _onChanged,
            onSubmitted: (_) => _submit(),
            suffix: _PasswordToggle(
              visible: !_obscurePassword,
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // «Mínimo 6 caracteres.» se pone en rojo mientras es más corta.
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Mínimo $_minPasswordLength caracteres. ',
                style: showPasswordError
                    ? const TextStyle(color: AppColors.dangerText)
                    : null,
              ),
              TextSpan(
                text: _isFamily
                    ? 'Compártela con la familia; después puede cambiarla '
                          'con «¿Olvidaste tu contraseña?».'
                    : 'Compártela con la persona; después puede cambiarla '
                          'con «¿Olvidaste tu contraseña?».',
              ),
            ],
          ),
          style: AppText.nunito(14, 21, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _HelperText extends StatelessWidget {
  const _HelperText(this.text, {this.color = AppColors.textMuted});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppText.nunito(14, 21, color: color));
  }
}

/// Mismo botón de ojo que el inicio de sesión.
class _PasswordToggle extends StatelessWidget {
  const _PasswordToggle({required this.visible, required this.onPressed});

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: visible ? 'Ocultar contraseña' : 'Mostrar contraseña',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: 40,
          child: Center(
            child: AppIcon(
              AppIcons.eye,
              size: 20,
              color: visible ? AppColors.primary : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
