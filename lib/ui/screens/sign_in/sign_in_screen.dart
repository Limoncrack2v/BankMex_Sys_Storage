import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/repositories/user_repository.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/coming_soon.dart';
import '../home/home_screen.dart';

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

  /// Único punto de contacto con el backend de autenticación.
  /// Regresa null si el login fue exitoso, o el mensaje de error a mostrar.
  /// Basado en _loginStaff de main.dart; reemplazar aquí el submit final.
  Future<String?> _signIn(String email, String password) async {
    try {
      final userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = await UserRepository().getUserProfile(userCred.user!.uid);

      if (user == null) {
        await FirebaseAuth.instance.signOut();
        return 'No se pudo iniciar sesión. Contacta a tu centro de BAMX para más información';
      }
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'invalid-credential':
        case 'invalid-email':
        case 'user-not-found':
        case 'wrong-password':
          return 'Correo o contraseña inválidos. Intenta de nuevo';
        case 'too-many-requests':
          return 'Demasiados intentos. Espera un momento e intenta de nuevo';
        case 'network-request-failed':
          return 'Sin conexión. Revisa tu internet e intenta de nuevo';
        default:
          return 'No se pudo iniciar sesión. Intenta de nuevo';
      }
    } catch (_) {
      return 'No se pudo iniciar sesión. Intenta de nuevo';
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await _signIn(
      _emailController.text.trim(),
      _passwordController.text,
    );
    if (!mounted) return;

    if (error != null) {
      setState(() {
        _submitting = false;
        _error = error;
      });
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
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
            if (!keyboardOpen) const _Footer(),
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
          label: 'Usuario o correo',
          child: AppTextField(
            controller: _emailController,
            hint: 'Tu usuario o correo',
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
          _ErrorMessage(_error!),
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
            onPressed: () => showComingSoon(context),
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

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage(this.message);

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

class _Footer extends StatelessWidget {
  const _Footer();

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
            'Tu cuenta fue creada por BAMX Guadalajara. Si aún no tienes los '
            'datos de Inicio de Sesión, acude a tu centro de distribución BAMX.',
            textAlign: TextAlign.center,
            style: AppText.nunito(14, 19.25, color: AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}
