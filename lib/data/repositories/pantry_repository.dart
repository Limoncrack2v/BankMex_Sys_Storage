import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/pantry_item.dart';

class PantryRepository {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _pantryItems(String familyId) =>
      _db.collection('families').doc(familyId).collection('pantryItems');

  PantryItem _parseOrThrow(DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      return PantryItem.fromFirestore(doc);
    } catch (e) {
      throw StateError(
        "Fallo el parseo del doc de PantryItem ${doc.id} en la colección family: $e",
      );
    }
  }

  Future<String> createPantryItem(String familyId, PantryItem item) async {
    final ref = await _pantryItems(familyId).add(item.toFirestore());
    return ref.id;
  }

  Future<PantryItem?> getPantryItem(
    String familyId,
    String pantryItemId,
  ) async {
    final doc = await _pantryItems(familyId).doc(pantryItemId).get();
    return doc.exists ? _parseOrThrow(doc) : null;
  }

  Future<void> updatePantryItem(
    String familyId,
    String pantryItemId,
    Map<String, dynamic> changes,
  ) => _pantryItems(familyId).doc(pantryItemId).update(changes);

  Future<void> deletePantryItem(String familyId, String pantryItemId) =>
      _pantryItems(familyId).doc(pantryItemId).delete();

  Stream<PantryItem?> watchPantryItem(String familyId, String pantryItemId) =>
      _pantryItems(familyId)
          .doc(pantryItemId)
          .snapshots()
          .map((doc) => doc.exists ? _parseOrThrow(doc) : null);

  Stream<List<PantryItem>> watchAllPantryItems(String familyId) =>
      _pantryItems(familyId)
          .snapshots()
          .map((snapshot) => snapshot.docs.map(_parseOrThrow).toList());
}
