import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'app_icon.dart';

class AppNavItem {
  const AppNavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final String icon;
  final String activeIcon;
}

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    this.items = familyItems,
    required this.currentIndex,
    required this.onTap,
  });

  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// App del beneficiario.
  static const familyItems = [
    AppNavItem(
      label: 'Despensa',
      icon: AppIcons.navDespensa,
      activeIcon: AppIcons.navDespensaActive,
    ),
    AppNavItem(
      label: 'Recetas',
      icon: AppIcons.navRecetas,
      activeIcon: AppIcons.navRecetasActive,
    ),
    AppNavItem(
      label: 'Plan de comidas',
      icon: AppIcons.navPlan,
      activeIcon: AppIcons.navPlanActive,
    ),
    AppNavItem(
      label: 'Perfil',
      icon: AppIcons.navPerfil,
      activeIcon: AppIcons.navPerfilActive,
    ),
  ];

  /// Panel del staff.
  static const staffItems = [
    AppNavItem(
      label: 'Entregas',
      icon: AppIcons.navEntregasActive,
      activeIcon: AppIcons.navEntregasActive,
    ),
    AppNavItem(
      label: 'Estadísticas',
      icon: AppIcons.navEstadisticas,
      activeIcon: AppIcons.navEstadisticas,
    ),
    AppNavItem(
      label: 'Catálogo de recetas',
      icon: AppIcons.navCatalogo,
      activeIcon: AppIcons.navCatalogo,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 368),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _NavItem(
                        label: items[i].label,
                        icon: i == currentIndex
                            ? items[i].activeIcon
                            : items[i].icon,
                        selected: i == currentIndex,
                        onTap: () => onTap(i),
                      ),
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        // Alto mínimo (no fijo) para que con letra grande el texto no se
        // desborde.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  decoration: selected
                      ? const ShapeDecoration(
                          color: AppColors.primarySoft,
                          shape: StadiumBorder(),
                        )
                      : null,
                  child: AppIcon(icon, size: 24),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: AppText.nunito(
                    12,
                    15,
                    weight: FontWeight.w700,
                    color: selected
                        ? AppColors.primaryDark
                        : AppColors.textMuted,
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
