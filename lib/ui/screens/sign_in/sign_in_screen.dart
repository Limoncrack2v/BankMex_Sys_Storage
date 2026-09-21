import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../session_navigation.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/app_text_field.dart';
import 'password_reset_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _error;

  bool get _canSubmit =>
      _emailController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final AuthSession session;
    try {
      session = await AuthRepository().signIn(
        _emailController.text.trim(),
        _passwordController.text,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e is AuthException
            ? e.message
            : 'No se pudo iniciar sesión. Intenta de nuevo.';
      });
      return;
    }
    if (!mounted) return;

    openSessionHome(context, session);
  }

  void _openPasswordReset() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PasswordResetScreen()),
    );
  }

  void _onFieldChanged(String _) => setState(() => _error = null);

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
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
                'Tu cuenta fue creada por BAMX Guadalajara. Si aún no tienes '
                'los datos de inicio de sesión, acude a tu centro de '
                'distribución BAMX.',
              ),
          ],
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
            width: 256,
            height: 256,
            semanticsLabel: 'Banco de Alimentos BAMX Guadalajara',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Inicia sesión en tu cuenta BAMX',
          textAlign: TextAlign.center,
          style: AppText.baloo(24, 30, color: AppColors.primaryDark),
        ),
        const SizedBox(height: 24),
        LabeledField(
          label: 'Correo electrónico',
          child: AppTextField(
            controller: _emailController,
            hint: 'Tu correo electrónico',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            onChanged: _onFieldChanged,
          ),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Contraseña',
          child: AppTextField(
            controller: _passwordController,
            hint: 'Tu contraseña',
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onChanged: _onFieldChanged,
            onSubmitted: (_) => _submit(),
            suffix: _PasswordToggle(
              visible: !_obscurePassword,
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[
          AuthErrorMessage(_error!),
          const SizedBox(height: 16),
        ],
        PrimaryButton(
          label: 'Iniciar sesión',
          loading: _submitting,
          onPressed: _canSubmit ? _submit : null,
        ),
        const SizedBox(height: 16),
        Center(
          child: TextLinkButton(
            label: '¿Olvidaste tu contraseña?',
            onPressed: _openPasswordReset,
          ),
        ),
      ],
    );
  }
}

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

/// Recuadro rojo con el error de inicio de sesión o de recuperación.
class AuthErrorMessage extends StatelessWidget {
  const AuthErrorMessage(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.dangerSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message,
          style: AppText.nunito(
            15,
            22.5,
            weight: FontWeight.w700,
            color: AppColors.dangerText,
          ),
        ),
      ),
    );
  }
}

/// Pie con borde superior de las pantallas de inicio de sesión.
class AuthFooter extends StatelessWidget {
  const AuthFooter(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppText.nunito(14, 19.25, color: AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}
