import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/staff_request.dart';

/// Solicitudes de cuenta de staff. Las crea la persona (ver
/// AuthRepository.requestStaffAccount) y las revisa un staff.
class StaffRequestRepository {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('staffRequests');

  /// Solicitudes pendientes, de la más antigua a la más reciente. Se ordenan
  /// aquí para no necesitar un índice compuesto (status + createdAt).
  Stream<List<StaffRequest>> watchPending() => _requests
      .where('status', isEqualTo: StaffRequestStatus.pending.name)
      .snapshots()
      .map(
        (snapshot) =>
            [for (final doc in snapshot.docs) ?_tryParse(doc)]
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      );

  Future<StaffRequest?> getRequest(String uid) async {
    final doc = await _requests.doc(uid).get();
    return doc.exists ? StaffRequest.fromFirestore(doc) : null;
  }

  /// Aprueba la solicitud: en un solo batch crea el perfil users/{uid} con
  /// rol staff y marca la solicitud como aprobada (las reglas exigen ambas
  /// escrituras juntas).
  Future<void> approve(StaffRequest request, {required String reviewerUid}) {
    final batch = _db.batch();
    batch.set(
      _db.collection('users').doc(request.uid),
      AppUser(
        userId: request.uid,
        name: request.name.trim(),
        email: request.email,
        role: AppUser.roleStaff,
        createdAt: DateTime.now(),
      ).toFirestore(),
    );
    batch.update(_requests.doc(request.uid), _review(
      StaffRequestStatus.approved,
      reviewerUid,
    ));
    return batch.commit();
  }

  /// Rechaza la solicitud; la cuenta sigue sin perfil y no puede entrar.
  Future<void> reject(StaffRequest request, {required String reviewerUid}) =>
      _requests
          .doc(request.uid)
          .update(_review(StaffRequestStatus.rejected, reviewerUid));

  Map<String, dynamic> _review(StaffRequestStatus status, String reviewerUid) =>
      {
        'status': status.name,
        'reviewedBy': reviewerUid,
        'reviewedAt': FieldValue.serverTimestamp(),
      };

  StaffRequest? _tryParse(DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      return StaffRequest.fromFirestore(doc);
    } catch (_) {
      return null;
    }
  }
}
