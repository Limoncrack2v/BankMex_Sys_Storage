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

  /// Guarda el plan vigente de la familia: si [plan] ya tiene id (el del plan
  /// que se leyó con [getCurrent]) lo reemplaza; si no, crea el documento. Así
  /// la familia tiene un plan vigente y no acumula uno nuevo cada vez. El id
  /// no es el de la familia: otra familia podría crear ese documento antes y
  /// dejarla sin poder guardar su plan.
  Future<MealPlan> save(MealPlan plan) => create(plan);

  /// El plan vigente de [familyId]: el que empieza más tarde, o null si aún no
  /// tiene.
  Future<MealPlan?> getCurrent(String familyId) async {
    final plans = await listByFamily(familyId);
    if (plans.isEmpty) return null;
    plans.sort((a, b) => b.dateRangeStart.compareTo(a.dateRangeStart));
    return plans.first;
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
}
