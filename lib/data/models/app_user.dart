import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  static const roleStaff = 'staff';
  static const roleFamily = 'family';

  final String userId;
  final String name;
  final String email;
  final String role;
  final DateTime createdAt;

  AppUser({
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    required this.createdAt
  });

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return AppUser(
      userId: doc.id, 
      name: data['name'] as String, 
      email: data['email'] as String, 
      role: data['role'] as String, 
      createdAt: (data['createdAt'] as Timestamp).toDate()
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'email': email,
    'role': role,
    'createdAt': Timestamp.fromDate(createdAt)
  };
}