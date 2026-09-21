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

  /// Familia cuya cuenta es [authUid]. Se consulta filtrando por authUid (y
  /// no con un get directo) para que la regla de lectura del dueño permita la
  /// consulta también para hogares registrados antes de usar el uid como id.
  Future<Family?> getFamilyByAuthUid(String authUid) async {
    final snapshot = await _families
        .where('authUid', isEqualTo: authUid)
        .limit(1)
        .get();
    return snapshot.docs.isEmpty
        ? null
        : Family.fromFirestore(snapshot.docs.first);
  }

  /// Todas las familias registradas, ordenadas por nombre. Solo staff. Un
  /// documento que no se pueda leer se omite en lugar de romper la lista.
  Stream<List<Family>> watchAllFamilies() => _families.snapshots().map(
    (snapshot) =>
        [
          for (final doc in snapshot.docs) ?_tryParse(doc),
        ]..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        ),
  );

  Family? _tryParse(DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      return Family.fromFirestore(doc);
    } catch (_) {
      return null;
    }
  }
}
