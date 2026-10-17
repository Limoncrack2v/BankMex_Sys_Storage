import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/meal_plan.dart';
import '../firestore_paths.dart';

class MealPlanRepository {
  MealPlanRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FirestorePaths.mealPlans);

  /// Lanza ArgumentError, sin escribir nada, si alguna comida del plan o el
  /// plan no cumplen los límites de firestore.rules (MealPlan.validate).
  Future<MealPlan> create(MealPlan plan) async {
    final error = plan.validate();
    if (error != null) throw ArgumentError(error);
    final ref = plan.id.isEmpty ? _col.doc() : _col.doc(plan.id);
    final data = plan.toMap();
    data['familyId'] = _db.doc(FirestorePaths.familyDoc(plan.familyId));
    await ref.set(data);
    return MealPlan(
      id: ref.id,
      familyId: plan.familyId,
      dateRangeStart: plan.dateRangeStart,
      dateRangeEnd: plan.dateRangeEnd,
      meals: plan.meals,
    );
  }

  Future<MealPlan?> getById(String planId) async {
    final snap = await _col.doc(planId).get();
    if (!snap.exists || snap.data() == null) return null;
    return MealPlan.fromMap(snap.id, snap.data()!);
  }

  Future<List<MealPlan>> listByFamily(String familyId) async {
    final familyRef = _db.doc(FirestorePaths.familyDoc(familyId));
    final snap = await _col.where('familyId', isEqualTo: familyRef).get();
    return snap.docs.map((doc) => MealPlan.fromMap(doc.id, doc.data())).toList();
  }

  /// Planes de la familia en vivo y si cada uno tiene cambios que siguen en
  /// el dispositivo (sin conexión) y aún no llegan al servidor. Filtra por
  /// familyId, como piden las reglas para listar, y no ordena, para no
  /// necesitar un índice.
  Stream<List<({MealPlan plan, bool pendingSync})>> watchByFamily(
    String familyId,
  ) {
    final familyRef = _db.doc(FirestorePaths.familyDoc(familyId));
    return _col
        .where('familyId', isEqualTo: familyRef)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs)
              (
                plan: MealPlan.fromMap(doc.id, doc.data()),
                pendingSync: doc.metadata.hasPendingWrites,
              ),
          ],
        );
  }

  /// Guarda las comidas de [plan]; el resto del documento no cambia (las
  /// reglas no dejan cambiar la familia y el rango no se edita). Lanza
  /// ArgumentError, sin escribir nada, si el plan no tiene id o si sus
  /// comidas no se pueden guardar (MealPlan.validate).
  Future<void> updateMeals(MealPlan plan) async {
    if (plan.id.isEmpty) throw ArgumentError('El plan no tiene id');
    final error = plan.validate();
    if (error != null) throw ArgumentError(error);
    await _col.doc(plan.id).update({
      'meals': [for (final meal in plan.meals) meal.toMap()],
    });
  }

  Future<void> delete(String planId) => _col.doc(planId).delete();
}
