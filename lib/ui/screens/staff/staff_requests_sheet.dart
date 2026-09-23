import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../../data/models/staff_request.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/staff_request_repository.dart';
import '../../formatting.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/pill.dart';

/// Sin conexión el commit no termina hasta sincronizar; pasado este tiempo
/// se da por guardado (igual que en Entregas).
const _saveTimeout = Duration(seconds: 4);
const _pendingSyncNote = 'Se sincronizará cuando haya conexión.';

/// Solicitudes de cuenta de staff pendientes ("Registro de Staff"), para
/// aprobarlas o rechazarlas.
Future<void> showStaffRequestsSheet(
  BuildContext context, {
  required AuthSession session,
}) {
  return showAppBottomSheet<void>(
    context,
    // Arrastrar para cerrar ignoraría AppSheet.busy mientras se guarda.
    enableDrag: false,
    builder: (_) => _StaffRequestsSheet(reviewerUid: session.user.userId),
  );
}

enum _Review { approve, reject }

class _StaffRequestsSheet extends StatefulWidget {
  const _StaffRequestsSheet({required this.reviewerUid});

  final String reviewerUid;

  @override
  State<_StaffRequestsSheet> createState() => _StaffRequestsSheetState();
}

class _StaffRequestsSheetState extends State<_StaffRequestsSheet> {
  late final Stream<List<StaffRequest>> _pending;

  /// Solicitud que se está confirmando; null muestra la lista.
  StaffRequest? _selected;
  _Review _review = _Review.approve;
  bool _saving = false;
  String? _error;

  /// Otro staff ya la revisó: reintentar no serviría.
  bool _alreadyReviewed = false;
  ({String heading, String message})? _success;

  @override
  void initState() {
    super.initState();
    _pending = StaffRequestRepository().watchPending();
  }

  void _ask(StaffRequest request, _Review review) {
    setState(() {
      _selected = request;
      _review = review;
      _error = null;
      _alreadyReviewed = false;
    });
  }

  void _backToList() {
    if (_saving) return;
    setState(() {
      _selected = null;
      _success = null;
      _error = null;
    });
  }

  Future<void> _confirm() async {
    final request = _selected;
    if (request == null || _saving || _alreadyReviewed) return;
    final approve = _review == _Review.approve;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });

    final repository = StaffRequestRepository();
    final save = approve
        ? repository.approve(request, reviewerUid: widget.reviewerUid)
        : repository.reject(request, reviewerUid: widget.reviewerUid);
    final bool synced;
    try {
      synced = await _awaitSave(
        save,
        onLateError: (error) => _showSnack(
          messenger,
          _isAlreadyReviewed(error)
              ? 'La solicitud de ${request.name} ya se había revisado desde '
                    'otro dispositivo.'
              : 'No se pudo sincronizar la revisión de la solicitud de '
                    '${request.name}. Revisa las solicitudes e intenta de '
                    'nuevo.',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final alreadyReviewed = _isAlreadyReviewed(e);
      setState(() {
        _saving = false;
        _alreadyReviewed = alreadyReviewed;
        _error = alreadyReviewed
            ? 'Esta solicitud ya se revisó desde otro dispositivo.'
            : 'No se pudo guardar. Revisa tu conexión e intenta de nuevo.';
      });
      return;
    }
    if (!mounted) return;

    var message = approve
        ? '${request.name} ya puede iniciar sesión como staff.'
        : 'La solicitud de ${request.name} se rechazó.';
    if (!synced) message = '$message $_pendingSyncNote';
    setState(() {
      _saving = false;
      _selected = null;
      _success = (
        heading: approve ? 'Solicitud aprobada' : 'Solicitud rechazada',
        message: message,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final success = _success;
    if (success != null) {
      return AppSheet(
        title: 'Solicitudes de staff',
        body: SuccessContent(
          heading: success.heading,
          message: success.message,
          onDone: _backToList,
        ),
      );
    }

    final selected = _selected;
    if (selected != null) return _buildConfirmation(selected);

    return AppSheet(
      title: 'Solicitudes de staff',
      body: StreamBuilder<List<StaffRequest>>(
        stream: _pending,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const InfoBanner(
              message: 'No se pudieron cargar las solicitudes. Revisa tu '
                  'conexión.',
              background: AppColors.dangerSoft,
              foreground: AppColors.dangerText,
            );
          }
          final requests = snapshot.data;
          if (requests == null) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            );
          }
          if (requests.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No hay solicitudes pendientes.',
                textAlign: TextAlign.center,
                style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, request) in requests.indexed) ...[
                if (index > 0) const SizedBox(height: 12),
                _RequestCard(
                  request: request,
                  onApprove: () => _ask(request, _Review.approve),
                  onReject: () => _ask(request, _Review.reject),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildConfirmation(StaffRequest request) {
    final approve = _review == _Review.approve;
    final error = _error;

    return AppSheet(
      title: approve ? 'Aprobar solicitud' : 'Rechazar solicitud',
      busy: _saving,
      body: Text(
        approve
            ? '¿Aprobar a ${request.name} como staff? Podrá registrar cuentas '
                  'y entregas y ver los datos de todas las familias.'
            : '¿Rechazar la solicitud de ${request.name}? No podrá iniciar '
                  'sesión en la app.',
        style: AppText.nunito(15, 22.5),
      ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            Semantics(
              liveRegion: true,
              child: InfoBanner(
                message: error,
                background: AppColors.dangerSoft,
                foreground: AppColors.dangerText,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (approve)
            PrimaryButton(
              label: 'Aprobar solicitud',
              icon: AppIcons.check,
              loading: _saving,
              onPressed: _alreadyReviewed ? null : _confirm,
            )
          else
            _DangerButton(
              label: 'Rechazar solicitud',
              loading: _saving,
              onPressed: _alreadyReviewed ? null : _confirm,
            ),
          const SizedBox(height: 8),
          Center(
            child: Opacity(
              opacity: _saving ? 0.4 : 1,
              child: TextLinkButton(label: 'Volver', onPressed: _backToList),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  final StaffRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            request.name,
            style: AppText.nunito(16, 24, weight: FontWeight.w700),
          ),
          Text(
            request.email,
            style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
          ),
          Text(
            'Solicitada el ${formatDateLong(request.createdAt)}',
            style: AppText.nunito(14, 21, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Aprobar',
                  icon: AppIcons.check,
                  onPressed: onApprove,
                ),
              ),
              const SizedBox(width: 8),
              _DangerLinkButton(label: 'Rechazar', onPressed: onReject),
            ],
          ),
        ],
      ),
    );
  }
}

/// Botón rojo de ancho completo para confirmar el rechazo. Misma forma y
/// tamaño que [PrimaryButton]; con [onPressed] nulo se ve deshabilitado.
class _DangerButton extends StatelessWidget {
  const _DangerButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
  );

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final foreground = enabled ? Colors.white : AppColors.textMuted;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: enabled ? AppColors.danger : AppColors.border,
        shape: _shape,
        child: InkWell(
          onTap: loading ? null : onPressed,
          customBorder: _shape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              child: Center(
                child: loading
                    ? SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: foreground,
                        ),
                      )
                    : Text(
                        label,
                        textAlign: TextAlign.center,
                        style: AppText.nunito(
                          17,
                          25.5,
                          weight: FontWeight.w700,
                          color: foreground,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Enlace rojo subrayado, como [TextLinkButton], para rechazar.
class _DangerLinkButton extends StatelessWidget {
  const _DangerLinkButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Text(
          label,
          style: AppText.nunito(
            15,
            22.5,
            weight: FontWeight.w700,
            color: AppColors.dangerText,
          ).copyWith(
            decoration: TextDecoration.underline,
            decorationColor: AppColors.dangerText,
          ),
        ),
      ),
    );
  }
}

/// Otro staff ya la aprobó o rechazó: las reglas solo dejan revisar una
/// solicitud pendiente.
bool _isAlreadyReviewed(Object error) =>
    error is FirebaseException && error.code == 'permission-denied';

/// Espera a que Firestore confirme [save]. Regresa false si pasado
/// [_saveTimeout] sigue pendiente (sin conexión el cambio ya quedó en el
/// dispositivo); si después falla al sincronizar, llama a [onLateError].
Future<bool> _awaitSave(
  Future<void> save, {
  required void Function(Object error) onLateError,
}) async {
  try {
    await save.timeout(_saveTimeout);
    return true;
  } on TimeoutException {
    unawaited(save.then<void>((_) {}, onError: onLateError));
    return false;
  }
}

void _showSnack(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
