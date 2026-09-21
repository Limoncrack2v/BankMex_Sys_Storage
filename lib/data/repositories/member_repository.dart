import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/member.dart';

class MemberRepository {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _members(String familyId) =>
      _db.collection('families').doc(familyId).collection('members');

  Member _parseOrThrow(DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      return Member.fromFirestore(doc);
    } catch (e) {
      throw StateError(
        "Fallo el parseo del doc de Member ${doc.id} en la colección members: $e",
      );
    }
  }

  Future<String> createMember(String familyId, Member member) async {
    final error = member.validate();
    if (error != null) throw ArgumentError(error);

    final ref = await _members(familyId).add(member.toFirestore());
    return ref.id;
  }

  Future<Member?> getMember(String familyId, String memberId) async {
    final doc = await _members(familyId).doc(memberId).get();
    return doc.exists ? _parseOrThrow(doc) : null;
  }

  Future<void> updateMember(
    String familyId,
    String memberId, {
    String? name,
    MemberType? memberType,
  }) async {
    final changes = <String, dynamic>{};

    if (name != null) {
      final error = Member.validateName(name);
      if (error != null) throw ArgumentError(error);
      changes['name'] = name.trim();
    }
    if (memberType != null) changes['memberType'] = memberType.name;
    if (changes.isEmpty) throw ArgumentError('No hay cambios que guardar');

    await _members(familyId).doc(memberId).update(changes);
  }

  Future<void> deleteMember(String familyId, String memberId) =>
      _members(familyId).doc(memberId).delete();

  Stream<Member?> watchMember(String familyId, String memberId) =>
      _members(familyId)
          .doc(memberId)
          .snapshots()
          .map((doc) => doc.exists ? _parseOrThrow(doc) : null);

  Stream<List<Member>> watchAllMembers(String familyId) => _members(familyId)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(_parseOrThrow).toList());
}
