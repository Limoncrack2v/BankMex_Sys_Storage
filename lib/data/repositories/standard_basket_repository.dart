import 'package:cloud_firestore/cloud_firestore.dart';

import '../firestore_paths.dart';
import '../models/standard_basket.dart';

/// Despensas estándar (solo lectura: las escriben los scripts de tool/).
class StandardBasketRepository {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _baskets =>
      _db.collection(FirestorePaths.standardBaskets);

  Future<StandardBasket?> getStandardBasket(String basketId) async {
    final doc = await _baskets.doc(basketId).get();
    return doc.exists ? StandardBasket.fromFirestore(doc) : null;
  }

  /// Todas las despensas, por nombre.
  Stream<List<StandardBasket>> watchStandardBaskets() => _baskets
      .orderBy('name')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map(StandardBasket.fromFirestore).toList(),
      );
}
