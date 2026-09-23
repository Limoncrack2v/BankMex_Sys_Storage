import 'package:cloud_firestore/cloud_firestore.dart';

enum StaffRequestStatus { pending, approved, rejected }

/// Solicitud de cuenta de staff (staffRequests/{uid}) que la persona envía
/// desde "Registro de Staff". No puede entrar a la app hasta que un staff la
/// aprueba; al aprobarla se crea su perfil users/{uid} con rol staff.
class StaffRequest {
  static const int maxNameLength = 100;

  /// uid de la cuenta de Auth que la envió (también el id del documento).
  final String uid;
  final String name;
  final String email;
  final StaffRequestStatus status;
  final DateTime createdAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;

  StaffRequest({
    required this.uid,
    required this.name,
    required this.email,
    required this.status,
    required this.createdAt,
    this.reviewedBy,
    this.reviewedAt,
  });

  factory StaffRequest.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return StaffRequest(
      uid: doc.id,
      name: data['name'] as String,
      email: data['email'] as String,
      status: StaffRequestStatus.values.byName(data['status'] as String),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      reviewedBy: data['reviewedBy'] as String?,
      reviewedAt: (data['reviewedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Documento al crear la solicitud: solo estos campos (validStaffRequest).
  /// La revisión (reviewedBy, reviewedAt) la escribe el staff después.
  Map<String, dynamic> toFirestore() => {
    'name': name.trim(),
    'email': email,
    'status': status.name,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}
