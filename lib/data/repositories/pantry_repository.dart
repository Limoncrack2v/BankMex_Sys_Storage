import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/pantry_item.dart';

/// Despensa de una familia. La app no crea productos: los crea la Cloud
/// Function onDeliveryWritten (functions/index.js) cuando una entrega queda
/// confirmada, y firestore.rules rechaza cualquier create desde un cliente.
/// Aquí solo se leen y se registra el consumo.
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

  /// Descuenta de la despensa lo que la familia consumió, en un solo batch.
  /// Si un producto llega a 0 se elimina. Cada cantidad debe ser mayor a 0 y
  /// no mayor a lo que queda. Regresa cuántos productos se actualizaron.
  ///
  /// El descuento parcial usa FieldValue.increment para que dos dispositivos
  /// de la misma familia no se pisen el consumo (cada uno resta lo suyo).
  Future<int> registerConsumption(
    String familyId,
    List<({PantryItem item, double amount})> consumed,
  ) async {
    final entries = consumed.where((c) => c.amount > 0).toList();
    if (entries.isEmpty) {
      throw ArgumentError('Indica cuánto consumiste de al menos un producto');
    }

    final collection = _pantryItems(familyId);
    final batch = _db.batch();

    for (final (:item, :amount) in entries) {
      if (!amount.isFinite || amount > item.quantity + _epsilon) {
        throw ArgumentError(
          'No puedes consumir más de lo que queda de ${item.productId}',
        );
      }
      final ref = collection.doc(item.pantryItemId);
      final remaining = remainingAfter(item.quantity, amount);
      if (remaining <= 0) {
        batch.delete(ref);
      } else {
        batch.update(ref, {'quantity': FieldValue.increment(-amount)});
      }
    }

    await batch.commit();
    return entries.length;
  }

  static const _epsilon = 1e-9;

  /// Cantidad que queda después de consumir [amount], redondeada a 3
  /// decimales para evitar residuos de punto flotante (2 - 0.1 * 3...).
  static double remainingAfter(double quantity, double amount) {
    final remaining = ((quantity - amount) * 1000).round() / 1000;
    return remaining < 0 ? 0 : remaining;
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

  /// Igual que [watchAllPantryItems], pero indica por producto si tiene
  /// cambios que siguen en el dispositivo (sin conexión) y aún no llegan al
  /// servidor.
  Stream<List<({PantryItem item, bool pendingSync})>> watchPantryWithSyncStatus(
    String familyId,
  ) => _pantryItems(familyId)
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            (
              item: _parseOrThrow(doc),
              pendingSync: doc.metadata.hasPendingWrites,
            ),
        ],
      );
}
