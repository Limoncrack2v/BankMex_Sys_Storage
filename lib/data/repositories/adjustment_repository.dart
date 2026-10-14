import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/recipe_adjustment.dart';
import '../firestore_paths.dart';

/// Las adaptaciones de recetas (adjustments). La familia crea las sugerencias
/// pendientes de su hogar y lee las suyas; el nutriólogo las lee todas y las
/// aprueba o rechaza; nadie edita su contenido (firestore.rules).
class AdjustmentRepository {
  AdjustmentRepository([FirebaseFirestore? firestore])
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FirestorePaths.adjustments);

  DocumentReference<Map<String, dynamic>> _familyRef(String familyId) =>
      _db.doc(FirestorePaths.familyDoc(familyId));

  /// Guarda una sugerencia pendiente de [adjustment.familyId], con el id
  /// [RecipeAdjustment.documentKey] que exigen las reglas: si ya existe una
  /// igual (de esa familia, receta, versión y tamaño de hogar), Firestore la
  /// rechaza.
  Future<RecipeAdjustment> create(RecipeAdjustment adjustment) async {
    final ref = _col.doc(adjustment.documentKey);
    await ref.set({
      ...adjustment.toMap(),
      'familyId': _familyRef(adjustment.familyId),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return RecipeAdjustment(
      id: ref.id,
      familyId: adjustment.familyId,
      recipeId: adjustment.recipeId,
      baseSignature: adjustment.baseSignature,
      householdSize: adjustment.householdSize,
      servings: adjustment.servings,
      ingredients: adjustment.ingredients,
      changes: adjustment.changes,
      summary: adjustment.summary,
      status: adjustment.status,
    );
  }

  /// Las adaptaciones de la familia de una receta, en cualquier estado.
  Future<List<RecipeAdjustment>> listForRecipe(
    String familyId,
    String recipeId,
  ) async {
    final snapshot = await _col
        .where('familyId', isEqualTo: _familyRef(familyId))
        .where('recipeId', isEqualTo: recipeId)
        .get();
    return [
      for (final doc in snapshot.docs)
        RecipeAdjustment.fromMap(doc.id, doc.data()),
    ];
  }

  /// Las adaptaciones aprobadas de la familia: las que ve en sus recetas.
  Stream<List<RecipeAdjustment>> watchApproved(String familyId) => _col
      .where('familyId', isEqualTo: _familyRef(familyId))
      .where('status', isEqualTo: AdjustmentStatus.approved.name)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            RecipeAdjustment.fromMap(doc.id, doc.data()),
        ],
      );

  /// Las que esperan al nutriólogo, de todas las familias. Solo él puede
  /// leerlas todas.
  Stream<List<RecipeAdjustment>> watchPending() => _col
      .where('status', isEqualTo: AdjustmentStatus.pending.name)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            RecipeAdjustment.fromMap(doc.id, doc.data()),
        ],
      );

  /// Del nutriólogo, con inicio de sesión reciente: solo escribe status y quién
  /// la aprobó y cuándo.
  Future<void> approve(String adjustmentId, {required String reviewerUid}) =>
      _col.doc(adjustmentId).update({
        'status': AdjustmentStatus.approved.name,
        'reviewedBy': reviewerUid,
        'reviewedAt': FieldValue.serverTimestamp(),
      });

  /// Del nutriólogo, con inicio de sesión reciente: el rechazo lleva su motivo.
  Future<void> reject(
    String adjustmentId, {
    required String reviewerUid,
    required String reason,
  }) => _col.doc(adjustmentId).update({
    'status': AdjustmentStatus.rejected.name,
    'rejectionReason': reason,
    'reviewedBy': reviewerUid,
    'reviewedAt': FieldValue.serverTimestamp(),
  });

  /// La familia retira una sugerencia suya que sigue pendiente (porque quedó
  /// vieja: la receta o su hogar cambiaron).
  Future<void> delete(String adjustmentId) => _col.doc(adjustmentId).delete();
}
