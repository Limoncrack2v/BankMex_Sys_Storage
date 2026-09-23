import 'dart:math' as math;

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
import 'staff_sign_up_screen.dart';

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

  void _openStaffSignUp() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StaffSignUpScreen()),
    );
  }

  void _onFieldChanged(String _) => setState(() => _error = null);

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      backgroundColor: AppColors.surface,
      // El pie se encarga del espacio de abajo (ver AuthFooter).
      body: SafeArea(
        bottom: false,
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
            suffix: PasswordToggle(
              visible: !_obscurePassword,
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // El error aparece y desaparece empujando lo de abajo con una
        // transición corta, en vez de un salto.
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _error == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: AuthErrorMessage(_error!),
                ),
        ),
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
        const SizedBox(height: 16),
        Center(
          child: TextLinkButton(
            label: '¿Eres personal de BAMX? Regístrate',
            onPressed: _openStaffSignUp,
          ),
        ),
      ],
    );
  }
}

/// Botón del ojo para mostrar u ocultar la contraseña.
class PasswordToggle extends StatelessWidget {
  const PasswordToggle({
    super.key,
    required this.visible,
    required this.onPressed,
  });

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

/// Recuadro rojo con el error de inicio de sesión o de recuperación. El
/// mensaje va en un solo renglón: si no cabe a 15, baja de tamaño hasta 13
/// (los mensajes largos, que no caben ni así, sí se acomodan en varios).
class AuthErrorMessage extends StatelessWidget {
  const AuthErrorMessage(this.message, {super.key});

  /// Tamaños de letra, del preferido al más chico.
  static const sizes = [15.0, 14.0, 13.0];

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scaler = MediaQuery.textScalerOf(context);
            final size = fittingFontSize(
              sizes: sizes,
              available: constraints.maxWidth,
              measure: (size) => _width(_style(size), scaler),
            );
            final oneLine = size != null;
            return Text(
              message,
              maxLines: oneLine ? 1 : null,
              softWrap: !oneLine,
              style: _style(size ?? sizes.last),
            );
          },
        ),
      ),
    );
  }

  TextStyle _style(double size) => AppText.nunito(
    size,
    size * 1.5,
    weight: FontWeight.w700,
    color: AppColors.dangerText,
  );

  double _width(TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: message, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

/// El primer tamaño de [sizes] cuyo texto cabe en [available]; null si
/// ninguno cabe. [measure] regresa el ancho del texto en un renglón.
double? fittingFontSize({
  required List<double> sizes,
  required double available,
  required double Function(double size) measure,
}) {
  if (!available.isFinite) return sizes.first;
  for (final size in sizes) {
    if (measure(size) <= available) return size;
  }
  return null;
}

/// "← Volver a inicio de sesión" arriba de las pantallas que se abren desde
/// el inicio de sesión (recuperar contraseña, registro de staff).
class AuthBackLink extends StatelessWidget {
  const AuthBackLink({super.key, this.enabled = true});

  /// En false no responde (p. ej. mientras se crea la cuenta).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: enabled ? () => Navigator.of(context).pop() : null,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppIcon(AppIcons.arrowLeft, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Volver a inicio de sesión',
                    style: AppText.nunito(
                      16,
                      24,
                      weight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pie con borde superior de las pantallas de inicio de sesión. Mide lo mismo
/// que en el diseño (16 arriba, 20 abajo): donde el sistema reserva espacio
/// abajo (el indicador del iPhone), ese espacio hace de margen en lugar de
/// sumarse.
class AuthFooter extends StatelessWidget {
  const AuthFooter(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final systemBottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, 16, 24, math.max(20, systemBottom)),
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
