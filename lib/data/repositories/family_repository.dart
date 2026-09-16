import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/family.dart';

class FamilyRepository {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _families =>
      _db.collection('families');

  Future<String> createFamily(Family family) async {
    final ref = await _families.add(family.toFirestore());
    return ref.id;
  }

  Future<Family?> getFamily(String familyId) async {
    final doc = await _families.doc(familyId).get();
    return doc.exists ? Family.fromFirestore(doc) : null;
  }

  Future<void> updateFamily(String familyId, Map<String, dynamic> changes) =>
      _families.doc(familyId).update(changes);

  Future<void> deleteFamily(String familyId) =>
      _families.doc(familyId).delete();

  Stream<Family?> watchFamily(String familyId) => _families
      .doc(familyId)
      .snapshots()
      .map((doc) => doc.exists ? Family.fromFirestore(doc) : null);
}
