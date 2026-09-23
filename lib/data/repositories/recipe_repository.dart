import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/recipe.dart';
import '../firestore_paths.dart';

class RecipeRepository {
  RecipeRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FirestorePaths.recipes);

  Future<Recipe> create(Recipe recipe) async {
    final ref = recipe.id.isEmpty ? _col.doc() : _col.doc(recipe.id);
    await ref.set(recipe.toMap());
    return recipe.copyWith(id: ref.id);
  }

  Future<Recipe?> getById(String recipeId) async {
    final snap = await _col.doc(recipeId).get();
    if (!snap.exists || snap.data() == null) return null;
    return Recipe.fromMap(snap.id, snap.data()!);
  }

  Future<Recipe> update(Recipe recipe) async {
    if (recipe.id.isEmpty) {
      throw ArgumentError('Recipe.update requires an id');
    }
    await _col.doc(recipe.id).set(recipe.toMap(), SetOptions(merge: true));
    return recipe;
  }

  Future<void> delete(String recipeId) => _col.doc(recipeId).delete();

  Future<List<Recipe>> list() async {
    final snap = await _col.get();
    return snap.docs.map((doc) => Recipe.fromMap(doc.id, doc.data())).toList();
  }

  Future<List<Recipe>> listByStatus(RecipeStatus status) async {
    final snap =
        await _col.where('status', isEqualTo: status.firestoreValue).get();
    return snap.docs.map((doc) => Recipe.fromMap(doc.id, doc.data())).toList();
  }

  Stream<List<Recipe>> watchByStatus(RecipeStatus status) {
    return _col
        .where('status', isEqualTo: status.firestoreValue)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Recipe.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  /// Staff: pending y approved. La familia no debe consultar esto.
  Stream<List<Recipe>> watchAll() {
    return _col.snapshots().map(
          (snap) => snap.docs
              .map((doc) => Recipe.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }
}
