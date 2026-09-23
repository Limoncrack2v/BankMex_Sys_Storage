import 'package:flutter/material.dart';

import '../../../data/models/app_user.dart';
import '../../../data/models/staff_request.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/staff_request_repository.dart';
import '../../session_navigation.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/coming_soon.dart';
import '../../widgets/pill.dart';
import 'deliveries_screen.dart';
import 'register_account_sheet.dart';
import 'staff_requests_sheet.dart';

/// Panel del staff: Entregas, con acceso a la cuenta (alta de cuentas,
/// solicitudes de staff y cerrar sesión) desde el header. Si hay solicitudes
/// de staff por revisar, un aviso arriba lleva a ellas.
class StaffHomeScreen extends StatefulWidget {
  const StaffHomeScreen({super.key, required this.session});

  final AuthSession session;

  @override
  State<StaffHomeScreen> createState() => _StaffHomeScreenState();
}

class _StaffHomeScreenState extends State<StaffHomeScreen> {
  late final Stream<List<StaffRequest>> _pendingRequests;

  AuthSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _pendingRequests = StaffRequestRepository().watchPending();
  }

  void _openStaffRequests() =>
      showStaffRequestsSheet(context, session: _session);

  void _openAccountSheet() {
    showAppBottomSheet<void>(
      context,
      builder: (sheetContext) => AppSheet(
        title: 'Mi cuenta',
        body: _AccountDetails(
          user: _session.user,
          onStaffRequests: () {
            Navigator.of(sheetContext).pop();
            _openStaffRequests();
          },
          onRegisterAccount: () {
            Navigator.of(sheetContext).pop();
            showRegisterAccountSheet(context);
          },
          onSignOut: () {
            Navigator.of(sheetContext).pop();
            // Solo navega; el cierre de sesión ocurre en la pantalla de
            // salida, así que aquí no hay error que mostrar.
            signOutAndReturnToSignIn(context);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          AppHeader(
            title: 'BAMX Guadalajara',
            horizontalPadding: 24,
            trailing: _AccountButton(onPressed: _openAccountSheet),
          ),
          StreamBuilder<List<StaffRequest>>(
            stream: _pendingRequests,
            builder: (context, snapshot) {
              final count = snapshot.data?.length ?? 0;
              if (snapshot.hasError || count == 0) {
                return const SizedBox.shrink();
              }
              return _StaffRequestsBanner(
                count: count,
                onPressed: _openStaffRequests,
              );
            },
          ),
          Expanded(
            child: DeliveriesScreen(
              session: _session,
              onRegisterAccount: () => showRegisterAccountSheet(context),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        items: AppBottomNav.staffItems,
        currentIndex: 0,
        onTap: (index) {
          if (index != 0) showComingSoon(context);
        },
      ),
    );
  }
}

/// Aviso de solicitudes de cuenta de staff por revisar.
class _StaffRequestsBanner extends StatelessWidget {
  const _StaffRequestsBanner({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final style = AppText.nunito(
      15,
      22.5,
      weight: FontWeight.w700,
      color: AppColors.primaryDark,
    );
    return Material(
      color: AppColors.primarySoft,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  count == 1
                      ? '1 solicitud de cuenta de staff por revisar'
                      : '$count solicitudes de cuenta de staff por revisar',
                  style: style,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Revisar',
                style: style.copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.primaryDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reemplaza el selector de 3 íconos del diseño: un solo botón de cuenta
/// dentro de la misma píldora con borde.
class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const ShapeDecoration(
        color: AppColors.surface,
        shape: StadiumBorder(
          side: BorderSide(color: AppColors.border, width: 2),
        ),
      ),
      child: Tooltip(
        message: 'Cuenta',
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: const SizedBox.square(
              dimension: 40,
              child: Center(child: AppIcon(AppIcons.person, size: 20)),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountDetails extends StatelessWidget {
  const _AccountDetails({
    required this.user,
    required this.onStaffRequests,
    required this.onRegisterAccount,
    required this.onSignOut,
  });

  final AppUser user;
  final VoidCallback onStaffRequests;
  final VoidCallback onRegisterAccount;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Column(
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
                    style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Align(
          alignment: Alignment.centerLeft,
          child: Pill.success(label: 'Staff', withIcon: false),
        ),
        const SizedBox(height: 24),
        SecondaryButton(
          label: 'Solicitudes de staff',
          icon: AppIcons.person,
          onPressed: onStaffRequests,
        ),
        const SizedBox(height: 12),
        SecondaryButton(
          label: 'Registrar cuenta',
          icon: AppIcons.plus,
          onPressed: onRegisterAccount,
        ),
        const SizedBox(height: 16),
        Center(
          child: TextLinkButton(label: 'Cerrar sesión', onPressed: onSignOut),
        ),
      ],
    );
  }
}
