import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_assets.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'app_icon.dart';

/// Etiqueta redondeada (badges de caducidad, "Tienes todos los ingredientes",
/// etc.).
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
    this.iconSize = 16,
    this.gap = 6,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.fontSize = 14,
    this.lineHeight = 21,
  });

  /// Pill verde con palomita, usado en recetas.
  const Pill.success({super.key, required this.label, bool withIcon = true})
    : background = AppColors.primarySoft,
      foreground = AppColors.primaryDark,
      icon = withIcon ? AppIcons.checkBadge : null,
      iconSize = 16,
      gap = 6,
      padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      fontSize = 14,
      lineHeight = 21;

  final String label;
  final Color background;
  final Color foreground;
  final String? icon;
  final double iconSize;
  final double gap;
  final EdgeInsets padding;
  final double fontSize;
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: ShapeDecoration(
        color: background,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            AppIcon(icon!, size: iconSize, color: foreground),
            SizedBox(width: gap),
          ],
          // Si la píldora es más angosta que la etiqueta (letra grande), esta
          // baja de renglón en vez de desbordarse.
          Flexible(
            child: Text(
              label,
              style: AppText.nunito(
                fontSize,
                lineHeight,
                weight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un Row con [leading] en Expanded y [trailing] (una [Pill]) a la derecha;
/// si la palabra más larga de [leading] no cabe al lado, [trailing] baja.
class PillRow extends MultiChildRenderObjectWidget {
  PillRow({
    super.key,
    required Widget leading,
    required Widget trailing,
    this.gap = 8,
    this.runSpacing = 8,
  }) : super(children: [leading, trailing]);

  /// Espacio entre [leading] y [trailing] en el mismo renglón.
  final double gap;

  /// Espacio arriba de [trailing] cuando baja debajo de [leading].
  final double runSpacing;

  @override
  RenderPillRow createRenderObject(BuildContext context) => RenderPillRow(
    gap: gap,
    runSpacing: runSpacing,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderPillRow renderObject) {
    renderObject
      ..gap = gap
      ..runSpacing = runSpacing
      ..textDirection = Directionality.of(context);
  }
}

class _PillRowParentData extends ContainerBoxParentData<RenderBox> {}

/// El render de [PillRow].
class RenderPillRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PillRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PillRowParentData> {
  RenderPillRow({
    required this._gap,
    required this._runSpacing,
    required this._textDirection,
  });

  double get gap => _gap;
  double _gap;
  set gap(double value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  double get runSpacing => _runSpacing;
  double _runSpacing;
  set runSpacing(double value) {
    if (_runSpacing == value) return;
    _runSpacing = value;
    markNeedsLayout();
  }

  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  RenderBox get _leading => firstChild!;
  RenderBox get _trailing => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PillRowParentData) {
      child.parentData = _PillRowParentData();
    }
  }

  /// Ancho de [trailing] si [leading] cabe a su lado; null si tiene que bajar.
  double? _besideWidth(double maxWidth) {
    final trailingWidth = _trailing.getMaxIntrinsicWidth(double.infinity);
    final longestWord = _leading.getMinIntrinsicWidth(double.infinity);
    return longestWord + gap + trailingWidth <= maxWidth ? trailingWidth : null;
  }

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _leading.getMinIntrinsicWidth(height),
    _trailing.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _leading.getMaxIntrinsicWidth(height) +
      gap +
      _trailing.getMaxIntrinsicWidth(height);

  double _intrinsicHeight(double width) {
    if (!width.isFinite) {
      return math.max(
        _leading.getMaxIntrinsicHeight(width),
        _trailing.getMaxIntrinsicHeight(width),
      );
    }
    final beside = _besideWidth(width);
    if (beside != null) {
      return math.max(
        _leading.getMaxIntrinsicHeight(math.max(0, width - gap - beside)),
        _trailing.getMaxIntrinsicHeight(beside),
      );
    }
    return _leading.getMaxIntrinsicHeight(width) +
        runSpacing +
        _trailing.getMaxIntrinsicHeight(width);
  }

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsicHeight(width);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layout(constraints, ChildLayoutHelper.dryLayoutChild, null);

  @override
  void performLayout() {
    size = _layout(
      constraints,
      ChildLayoutHelper.layoutChild,
      (child, offset) =>
          (child.parentData! as _PillRowParentData).offset = offset,
    );
  }

  Size _layout(
    BoxConstraints constraints,
    ChildLayouter layoutChild,
    void Function(RenderBox child, Offset offset)? place,
  ) {
    final maxWidth = constraints.maxWidth;
    final rtl = textDirection == TextDirection.rtl;
    // Sin ancho máximo (no pasa en las tarjetas): los dos en un renglón.
    if (!maxWidth.isFinite) {
      final loose = BoxConstraints(maxHeight: constraints.maxHeight);
      final leading = layoutChild(_leading, loose);
      final trailing = layoutChild(_trailing, loose);
      final width = leading.width + gap + trailing.width;
      place?.call(_leading, Offset(rtl ? width - leading.width : 0, 0));
      place?.call(_trailing, Offset(rtl ? 0 : width - trailing.width, 0));
      return constraints.constrain(
        Size(width, math.max(leading.height, trailing.height)),
      );
    }

    final beside = _besideWidth(maxWidth);
    if (beside != null) {
      final trailing = layoutChild(
        _trailing,
        BoxConstraints(maxWidth: maxWidth, maxHeight: constraints.maxHeight),
      );
      final leadingWidth = math.max(0.0, maxWidth - gap - trailing.width);
      final leading = layoutChild(
        _leading,
        BoxConstraints(
          minWidth: leadingWidth,
          maxWidth: leadingWidth,
          maxHeight: constraints.maxHeight,
        ),
      );
      place?.call(_leading, Offset(rtl ? maxWidth - leadingWidth : 0, 0));
      place?.call(_trailing, Offset(rtl ? 0 : maxWidth - trailing.width, 0));
      return constraints.constrain(
        Size(maxWidth, math.max(leading.height, trailing.height)),
      );
    }

    final leading = layoutChild(
      _leading,
      BoxConstraints(minWidth: maxWidth, maxWidth: maxWidth),
    );
    final trailing = layoutChild(_trailing, BoxConstraints(maxWidth: maxWidth));
    place?.call(_leading, Offset.zero);
    place?.call(
      _trailing,
      Offset(rtl ? maxWidth - trailing.width : 0, leading.height + runSpacing),
    );
    return constraints.constrain(
      Size(maxWidth, leading.height + runSpacing + trailing.height),
    );
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}

/// Aviso de ancho completo con fondo de color (p. ej. "7 productos caducan
/// pronto").
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    required this.background,
    required this.foreground,
  });

  final String message;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: AppText.nunito(
          15,
          22.5,
          weight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}
