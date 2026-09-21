import 'package:cloud_firestore/cloud_firestore.dart';

enum MemberType { adult, child }

class Member {
  static const int maxNameLength = 100;

  final String memberId;
  final String name;
  final MemberType memberType;
  final DateTime createdAt;

  Member({
    required this.memberId,
    required this.name,
    required this.memberType,
    required this.createdAt,
  });

  factory Member.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    return Member(
      memberId: doc.id,
      name: data['name'] as String,
      memberType: MemberType.values.byName(data['memberType'] as String),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name.trim(),
    'memberType': memberType.name,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  static String? validateName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'El nombre no puede estar vacío';
    if (trimmed.length > maxNameLength) {
      return 'El nombre no puede tener más de $maxNameLength caracteres';
    }
    return null;
  }

  String? validate() => validateName(name);
}
