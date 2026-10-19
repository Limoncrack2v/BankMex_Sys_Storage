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

  /// Cambia solo los electrodomésticos del hogar, el único campo que la
  /// familia puede editar de su documento (firestore.rules). [keep] son ids
  /// ya guardados que esta versión de la app no conoce.
  Future<void> updateAppliances(
    String familyId,
    List<String> appliances, {
    Set<String> keep = const {},
  }) async {
    final error = Appliance.validateIds(appliances, keep: keep);
    if (error != null) throw ArgumentError(error);
    await updateFamily(familyId, {'appliances': appliances});
  }

  /// El staff corrige el nombre, la dirección o la cuota de recuperación de
  /// [family]. Solo escribe los campos que cambian (firestore.rules no deja
  /// cambiar authUid ni nextDeliveryDate). Lanza [ArgumentError] con el
  /// mensaje si un valor no cumple validFamily.
  Future<void> updateFamilyDetails(
    Family family, {
    required String name,
    required String address,
    required double? recoveryQuotaDefault,
  }) async {
    final error = Family.validateDetails(
      name: name,
      address: address,
      recoveryQuotaDefault: recoveryQuotaDefault,
    );
    if (error != null) throw ArgumentError(error);
    final changes = family.detailChanges(
      name: name,
      address: address,
      recoveryQuotaDefault: recoveryQuotaDefault,
    );
    if (changes.isEmpty) return;
    await updateFamily(family.familyId, changes);
  }

  Future<void> deleteFamily(String familyId) =>
      _families.doc(familyId).delete();

  Stream<Family?> watchFamily(String familyId) => _families
      .doc(familyId)
      .snapshots()
      .map((doc) => doc.exists ? Family.fromFirestore(doc) : null);

  /// Igual que [watchFamily], pero indica si el documento tiene cambios que
  /// siguen en el dispositivo (sin conexión) y aún no llegan al servidor.
  Stream<({Family? family, bool pendingSync})> watchFamilyWithSyncStatus(
    String familyId,
  ) => _families
      .doc(familyId)
      .snapshots(includeMetadataChanges: true)
      .map(
        (doc) => (
          family: doc.exists ? Family.fromFirestore(doc) : null,
          pendingSync: doc.metadata.hasPendingWrites,
        ),
      );

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

  /// Todas las familias registradas, leídas una vez del servidor (sin orden).
  /// Solo staff. Sin conexión falla en lugar de regresar las que haya en la
  /// caché. Un documento que no se pueda leer se omite.
  Future<List<Family>> getAllFamilies() async {
    final snapshot = await _families.get(
      const GetOptions(source: Source.server),
    );
    return [for (final doc in snapshot.docs) ?_tryParse(doc)];
  }

  Family? _tryParse(DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      return Family.fromFirestore(doc);
    } catch (_) {
      return null;
    }
  }
}
