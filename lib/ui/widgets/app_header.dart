import 'package:flutter/material.dart';

import '../connection_status.dart';
import '../theme/app_assets.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'app_icon.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.title,
    this.trailing = const ConnectionChip(),
    this.horizontalPadding = 16,
  });

  final String title;
  final Widget trailing;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            32,
            horizontalPadding,
            16,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.baloo(22, 33, color: AppColors.primaryDark),
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip de estado de conexión del header ("En línea" / "Sin conexión").
class ConnectionChip extends StatelessWidget {
  const ConnectionChip({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectionStatus.instance.online,
      builder: (context, online, _) {
        final foreground = online
            ? AppColors.primaryDark
            : AppColors.warningText;

        return Semantics(
          liveRegion: true,
          child: Container(
            height: 33,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: ShapeDecoration(
              color: online ? AppColors.primarySoft : AppColors.warningSoft,
              shape: const StadiumBorder(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(AppIcons.wifi, size: 16, color: foreground),
                const SizedBox(width: 6),
                Text(
                  online ? 'En línea' : 'Sin conexión',
                  style: AppText.nunito(
                    14,
                    21,
                    weight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
