import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/meal_plan.dart';
import '../firestore_paths.dart';

class MealPlanRepository {
  MealPlanRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FirestorePaths.mealPlans);

  Future<MealPlan> create(MealPlan plan) async {
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
}
