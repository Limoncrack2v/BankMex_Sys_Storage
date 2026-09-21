import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/app_text_field.dart';
import 'sign_in_screen.dart';

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _emailController = TextEditingController();
  bool _sending = false;
  String? _error;

  bool get _canSubmit => _emailController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit || _sending) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await AuthRepository().sendPasswordReset(_emailController.text.trim());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e is AuthException
            ? e.message
            : 'No se pudo enviar el correo. Intenta de nuevo.';
      });
      return;
    }
    if (!mounted) return;
    setState(() => _sending = false);

    await showAppBottomSheet<void>(
      context,
      builder: (context) => AppSheet(
        title: 'Instrucciones enviadas',
        body: _SentContent(onDone: () => Navigator.of(context).pop()),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
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
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 32, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _BackLink(),
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
                'Si no tienes cuenta o no recuerdas tu correo registrado, '
                'acude a tu centro de distribución BAMX.',
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
          'Recuperar contraseña',
          textAlign: TextAlign.center,
          style: AppText.baloo(24, 30, color: AppColors.primaryDark),
        ),
        const SizedBox(height: 8),
        Text(
          'Ingresa el correo con el que te registraron en tu centro de '
          'distribución BAMX y te enviaremos instrucciones para restablecer '
          'tu contraseña.',
          textAlign: TextAlign.center,
          style: AppText.nunito(16, 22, color: AppColors.textMuted),
        ),
        const SizedBox(height: 24),
        LabeledField(
          label: 'Correo electrónico',
          child: AppTextField(
            controller: _emailController,
            hint: 'tucorreo@ejemplo.com',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.send,
            autofillHints: const [AutofillHints.email],
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
          label: 'Enviar instrucciones',
          loading: _sending,
          onPressed: _canSubmit ? _submit : null,
        ),
      ],
    );
  }
}

class _BackLink extends StatelessWidget {
  const _BackLink();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(),
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
    );
  }
}

class _SentContent extends StatelessWidget {
  const _SentContent({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Si el correo está registrado, recibirás un mensaje con los pasos '
          'para restablecer tu contraseña.',
          style: AppText.nunito(16, 22),
        ),
        const SizedBox(height: 16),
        PrimaryButton(label: 'Listo', onPressed: onDone),
      ],
    );
  }
}
