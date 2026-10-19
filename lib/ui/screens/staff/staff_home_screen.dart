import 'package:flutter/material.dart';

import '../../../data/models/staff_request.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/staff_request_repository.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/app_header.dart';
import '../session/account_sheet.dart';
import 'deliveries_screen.dart';
import 'families_sheet.dart';
import 'recipe_catalog_screen.dart';
import 'register_account_sheet.dart';
import 'staff_requests_sheet.dart';
import 'stats_screen.dart';

/// Panel del staff: Entregas, con acceso a la cuenta (alta de cuentas,
/// familias, solicitudes de staff y cerrar sesión) desde el header. Si hay solicitudes
/// de staff por revisar, un aviso arriba lleva a ellas.
class StaffHomeScreen extends StatefulWidget {
  const StaffHomeScreen({super.key, required this.session});

  final AuthSession session;

  @override
  State<StaffHomeScreen> createState() => _StaffHomeScreenState();
}

class _StaffHomeScreenState extends State<StaffHomeScreen> {
  late final Stream<List<StaffRequest>> _pendingRequests;

  /// Pestaña abierta: 0 Entregas, 1 Estadísticas, 2 Catálogo de recetas.
  int _tab = 0;

  AuthSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _pendingRequests = StaffRequestRepository().watchPending();
  }

  void _openStaffRequests() =>
      showStaffRequestsSheet(context, session: _session);

  void _openAccountSheet() => showAccountSheet(
    context,
    user: _session.user,
    actions: [
      (
        label: 'Solicitudes de staff',
        icon: AppIcons.person,
        onPressed: _openStaffRequests,
      ),
      (
        label: 'Registrar cuenta',
        icon: AppIcons.plus,
        onPressed: () => showRegisterAccountSheet(context),
      ),
      (
        label: 'Familias',
        icon: AppIcons.home,
        onPressed: () => showFamiliesSheet(context),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          AppHeader(
            title: 'BAMX Guadalajara',
            horizontalPadding: 24,
            onAccount: _openAccountSheet,
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
            child: switch (_tab) {
              1 => const StatsScreen(),
              2 => const RecipeCatalogScreen(),
              _ => DeliveriesScreen(
                session: _session,
                onRegisterAccount: () => showRegisterAccountSheet(context),
              ),
            },
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        items: AppBottomNav.staffItems,
        currentIndex: _tab,
        onTap: (index) {
          if (index != _tab) setState(() => _tab = index);
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
