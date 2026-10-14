import 'package:flutter/material.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../session_navigation.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/pill.dart';

class NutritionistHomeScreen extends StatelessWidget {
  const NutritionistHomeScreen({super.key, required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          AppHeader(title: 'BAMX Guadalajara', horizontalPadding: 24),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.user.name, style: AppText.baloo(20, 30)),
                const SizedBox(height: 12),
                Pill.success(label: 'Nutriólogo', withIcon: false),
                const SizedBox(height: 24),
                Text(
                  'La revisión de recetas estará disponible pronto.',
                  style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextLinkButton(
                    label: 'Cerrar sesión',
                    onPressed: () => signOutAndReturnToSignIn(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
