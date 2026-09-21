import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'app_buttons.dart';
import 'app_icon.dart';

/// [enableDrag] en false para los sheets con formulario: arrastrar para
/// cerrar ignora [AppSheet.busy] (usa Navigator.pop directo).
Future<T?> showAppBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: enableDrag,
    backgroundColor: AppColors.surface,
    barrierColor: AppColors.scrim,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      side: BorderSide(color: AppColors.border),
    ),
    builder: builder,
  );
}

/// Muestra un sheet de confirmación con palomita y botón "Listo".
Future<void> showSuccessSheet(
  BuildContext context, {
  required String title,
  required String heading,
  required String message,
}) {
  return showAppBottomSheet<void>(
    context,
    builder: (context) => AppSheet(
      title: title,
      body: SuccessContent(
        heading: heading,
        message: message,
        onDone: () => Navigator.of(context).pop(),
      ),
    ),
  );
}

/// Estructura común de los bottom sheets del diseño: header con título y
/// botón de cerrar, cuerpo con scroll y un pie opcional.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.title,
    required this.body,
    this.footer,
    this.busy = false,
  });

  final String title;
  final Widget body;
  final Widget? footer;

  /// Mientras se guarda no se puede cerrar (ni con la X, ni con atrás, ni
  /// tocando fuera), para no perder el resultado.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !busy,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    return LayoutBuilder(
        builder: (context, constraints) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(0.0, constraints.maxHeight - 56),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SheetHeader(title: title, closeEnabled: !busy),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: body,
                ),
              ),
              if (footer != null)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: footer,
                ),
            ],
          ),
        ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, required this.closeEnabled});

  final String title;
  final bool closeEnabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(title, style: AppText.baloo(20, 30))),
          Tooltip(
            message: 'Cerrar',
            child: Opacity(
              opacity: closeEnabled ? 1 : 0.4,
              child: InkWell(
                onTap: closeEnabled ? () => Navigator.of(context).pop() : null,
                customBorder: const CircleBorder(),
                child: const SizedBox.square(
                  dimension: 40,
                  child: Center(child: AppIcon(AppIcons.close, size: 24)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SuccessContent extends StatelessWidget {
  const SuccessContent({
    super.key,
    required this.heading,
    required this.message,
    required this.onDone,
  });

  final String heading;
  final String message;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const AppIcon(AppIcons.checkLarge, size: 40),
          ),
          const SizedBox(height: 16),
          Text(
            heading,
            textAlign: TextAlign.center,
            style: AppText.baloo(22, 33, color: AppColors.primaryDark),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: 'Listo', icon: AppIcons.check, onPressed: onDone),
        ],
      ),
    );
  }
}
