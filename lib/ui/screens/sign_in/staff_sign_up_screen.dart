import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/models/staff_request.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/app_text_field.dart';
import 'sign_in_screen.dart';

/// "Registro de Staff": una persona del equipo de BAMX Guadalajara solicita
/// su cuenta. La cuenta queda pendiente hasta que un staff la aprueba (ver
/// AuthRepository.requestStaffAccount).
class StaffSignUpScreen extends StatefulWidget {
  const StaffSignUpScreen({super.key});

  static const int minPasswordLength = 8;

  @override
  State<StaffSignUpScreen> createState() => _StaffSignUpScreenState();
}

class _StaffSignUpScreenState extends State<StaffSignUpScreen> {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _obscurePassword = true;

  /// Los errores de cada campo se muestran hasta el primer intento de envío.
  bool _attempted = false;
  bool _submitting = false;
  String? _error;
  bool _sent = false;

  bool get _nameValid => _name.text.trim().isNotEmpty;
  bool get _emailValid => _emailPattern.hasMatch(_email.text.trim());
  bool get _passwordValid =>
      _password.text.length >= StaffSignUpScreen.minPasswordLength;
  bool get _confirmationValid =>
      _confirmation.text.isNotEmpty && _confirmation.text == _password.text;
  bool get _valid =>
      _nameValid && _emailValid && _passwordValid && _confirmationValid;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _attempted = true);
    if (!_valid) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await AuthRepository().requestStaffAccount(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e is AuthException
            ? e.message
            : 'No se pudo enviar tu solicitud. Intenta de nuevo.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _sent = true;
    });
  }

  void _onFieldChanged(String _) => setState(() => _error = null);

  @override
  Widget build(BuildContext context) {
    if (_sent) return const _SentScreen();

    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    // Mientras se crea la cuenta no se puede salir: la cuenta de Auth ya
    // existe y el registro termina cerrando su sesión.
    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AuthBackLink(enabled: !_submitting),
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 56),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: AutofillGroup(child: _buildForm()),
                    ),
                  ),
                ),
              ),
              if (!keyboardOpen)
                const AuthFooter(
                  'Usa tu correo institucional de BAMX Guadalajara. Un staff '
                  'revisará tu solicitud antes de que puedas iniciar sesión.',
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: SvgPicture.asset(
            AppImages.bamxLogo,
            width: 160,
            height: 160,
            semanticsLabel: 'Banco de Alimentos BAMX Guadalajara',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Registro de Staff',
          textAlign: TextAlign.center,
          style: AppText.baloo(24, 30, color: AppColors.primaryDark),
        ),
        const SizedBox(height: 8),
        Text(
          'Crea tu cuenta como parte del equipo de BAMX Guadalajara.',
          textAlign: TextAlign.center,
          style: AppText.nunito(16, 22, color: AppColors.textMuted),
        ),
        const SizedBox(height: 24),
        _Field(
          label: 'Nombre completo',
          error: _attempted && !_nameValid ? 'Escribe tu nombre completo' : null,
          child: AppTextField(
            controller: _name,
            hint: 'Ej. María González',
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            maxLength: StaffRequest.maxNameLength,
            autofillHints: const [AutofillHints.name],
            onChanged: _onFieldChanged,
          ),
        ),
        const SizedBox(height: 16),
        _Field(
          label: 'Correo institucional',
          error: _attempted && !_emailValid ? 'Ingresa un correo válido' : null,
          child: AppTextField(
            controller: _email,
            hint: 'tucorreo@bamx.org.mx',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            onChanged: _onFieldChanged,
          ),
        ),
        const SizedBox(height: 16),
        _Field(
          label: 'Contraseña',
          error: _attempted && !_passwordValid
              ? 'La contraseña debe tener al menos '
                    '${StaffSignUpScreen.minPasswordLength} caracteres'
              : null,
          child: AppTextField(
            controller: _password,
            hint: 'Mínimo ${StaffSignUpScreen.minPasswordLength} caracteres',
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            onChanged: _onFieldChanged,
            suffix: PasswordToggle(
              visible: !_obscurePassword,
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _Field(
          label: 'Confirmar contraseña',
          error: _attempted && !_confirmationValid
              ? 'Las contraseñas no coinciden'
              : null,
          child: AppTextField(
            controller: _confirmation,
            hint: 'Repite tu contraseña',
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            onChanged: _onFieldChanged,
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[
          AuthErrorMessage(_error!),
          const SizedBox(height: 16),
        ],
        PrimaryButton(
          label: 'Crear cuenta',
          loading: _submitting,
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// Campo con etiqueta y, debajo, su error de validación.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.error});

  final String label;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabeledField(label: label, child: child),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error,
            style: AppText.nunito(
              14,
              21,
              weight: FontWeight.w600,
              color: AppColors.dangerText,
            ),
          ),
        ],
      ],
    );
  }
}

/// Confirmación después de enviar la solicitud.
class _SentScreen extends StatelessWidget {
  const _SentScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 56, 24, 56),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      color: AppColors.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const AppIcon(AppIcons.checkLarge, size: 40),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Solicitud enviada',
                    textAlign: TextAlign.center,
                    style: AppText.baloo(22, 33, color: AppColors.primaryDark),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      'Tu solicitud para unirte al equipo de BAMX Guadalajara '
                      'quedó registrada. Podrás iniciar sesión con tu correo '
                      'institucional cuando un staff la apruebe.',
                      textAlign: TextAlign.center,
                      style: AppText.nunito(
                        15,
                        22.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Ir a inicio de sesión',
                    icon: AppIcons.check,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
