import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';

class UserRepository {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  Future<void> createUserProfile(AppUser user) async {
    await _users.doc(user.userId).set(user.toFirestore());
  }

  Future<AppUser?> getUserProfile(String userId) async {
    final doc = await _users.doc(userId).get();
    return doc.exists ? AppUser.fromFirestore(doc) : null;
  }
}