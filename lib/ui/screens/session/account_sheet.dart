import 'package:flutter/material.dart';

import '../../../data/models/app_user.dart';
import '../../session_navigation.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/pill.dart';

/// Un botón extra de "Mi cuenta". Solo Staff tiene ("Solicitudes de staff",
/// "Registrar cuenta", "Familias").
typedef AccountAction = ({String label, String icon, VoidCallback onPressed});

/// "Mi cuenta", el mismo para los tres roles: nombre, correo, rol y "Cerrar
/// sesión". El sheet se cierra antes de llamar a cada una de [actions].
Future<void> showAccountSheet(
  BuildContext context, {
  required AppUser user,
  List<AccountAction> actions = const [],
}) {
  return showAppBottomSheet<void>(
    context,
    builder: (_) => AccountSheet(user: user, actions: actions),
  );
}

@visibleForTesting
class AccountSheet extends StatefulWidget {
  const AccountSheet({super.key, required this.user, this.actions = const []});

  final AppUser user;
  final List<AccountAction> actions;

  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  bool _signingOut = false;

  /// signOutAndReturnToSignIn navega primero (eso también quita este sheet) y
  /// cierra la sesión después. La bandera evita un segundo toque durante la
  /// transición.
  void _signOut() {
    if (_signingOut) return;
    _signingOut = true;
    signOutAndReturnToSignIn(context);
  }

  static String _roleLabel(String role) => switch (role) {
    AppUser.roleStaff => 'Staff',
    AppUser.roleNutritionist => 'Nutriólogo',
    _ => 'Familia',
  };

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return AppSheet(
      title: 'Mi cuenta',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: const AppIcon(
                  AppIcons.person,
                  size: 24,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: AppText.baloo(20, 30)),
                    Text(
                      user.email,
                      style: AppText.nunito(
                        15,
                        22.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Pill.success(label: _roleLabel(user.role), withIcon: false),
          ),
          const SizedBox(height: 24),
          for (final action in widget.actions) ...[
            SecondaryButton(
              label: action.label,
              icon: action.icon,
              onPressed: () {
                Navigator.of(context).pop();
                action.onPressed();
              },
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          PrimaryButton(
            label: 'Cerrar sesión',
            danger: true,
            onPressed: _signOut,
          ),
        ],
      ),
    );
  }
}
