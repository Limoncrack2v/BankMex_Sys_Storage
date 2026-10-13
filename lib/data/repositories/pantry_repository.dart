import 'package:cloud_firestore/cloud_firestore.dart';

import '../device_identity.dart';
import '../firestore_paths.dart';
import '../models/consumption_log.dart';
import '../models/pantry_item.dart';

/// Despensa de una familia. La app no crea productos: los crea la Cloud
/// Function onDeliveryWritten (functions/index.js) cuando una entrega queda
/// confirmada, y firestore.rules rechaza cualquier create desde un cliente.
/// Aquí solo se leen y se registra el consumo.
class PantryRepository {
  PantryRepository({DeviceIdentity? device})
    : _device = device ?? DeviceIdentity.instance;

  final _db = FirebaseFirestore.instance;
  final DeviceIdentity _device;

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
  ///
  /// En el mismo batch deja un documento en consumptionLogs por producto
  /// ([consumptionLog]), así que sin conexión ambos quedan en la cola de
  /// Firestore y se sincronizan juntos. Es el único lugar que escribe esos
  /// registros.
  Future<int> registerConsumption(
    String familyId,
    List<({PantryItem item, double amount})> consumed, {
    DateTime? now,
  }) async {
    final entries = consumed.where((c) => c.amount > 0).toList();
    if (entries.isEmpty) {
      throw ArgumentError('Indica cuánto consumiste de al menos un producto');
    }

    final at = now ?? DateTime.now();
    final deviceId = await _device.id;
    final collection = _pantryItems(familyId);
    final logs = _db
        .collection(FirestorePaths.families)
        .doc(familyId)
        .collection(FirestorePaths.consumptionLogs);
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
      batch.set(
        logs.doc(),
        consumptionLog(item: item, amount: amount, at: at, deviceId: deviceId),
      );
    }

    await batch.commit();
    return entries.length;
  }

  static const _epsilon = 1e-9;

  /// Documento de consumptionLogs por sacar [amount] de [item] en [at]. Si
  /// el producto ya había caducado ese día, cuenta como desperdicio
  /// ([ConsumptionReason.expired]), igual que las estadísticas cuentan lo
  /// que caduca en la despensa.
  static Map<String, dynamic> consumptionLog({
    required PantryItem item,
    required double amount,
    required DateTime at,
    required String deviceId,
  }) => {
    'productId': item.productId,
    'quantity': amount,
    'unit': item.unit.name,
    'category': item.type.name,
    'at': Timestamp.fromDate(at),
    'deviceId': deviceId,
    'reason':
        (item.daysLeftOn(at) < 0
                ? ConsumptionReason.expired
                : ConsumptionReason.consumed)
            .name,
  };

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

  /// La despensa de una familia, leída una vez (para las estadísticas del
  /// staff). Un producto que no se pueda leer se omite.
  Future<List<PantryItem>> getPantryItems(String familyId) async {
    final snapshot = await _pantryItems(familyId).get();
    return [
      for (final doc in snapshot.docs)
        ?_tryParse(doc, PantryItem.fromFirestore),
    ];
  }

  /// Los registros de consumptionLogs de una familia desde [since]. Un
  /// registro que no se pueda leer se omite en lugar de romper las
  /// estadísticas.
  Future<List<ConsumptionLog>> getConsumptionLogs(
    String familyId, {
    required DateTime since,
  }) async {
    final snapshot = await _db
        .collection(FirestorePaths.families)
        .doc(familyId)
        .collection(FirestorePaths.consumptionLogs)
        .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .get();
    return [
      for (final doc in snapshot.docs)
        ?_tryParse(doc, ConsumptionLog.fromFirestore),
    ];
  }

  static T? _tryParse<T>(
    DocumentSnapshot<Map<String, dynamic>> doc,
    T Function(DocumentSnapshot<Map<String, dynamic>>) parse,
  ) {
    try {
      return parse(doc);
    } catch (_) {
      return null;
    }
  }

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
