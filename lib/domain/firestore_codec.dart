import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? decodeDate(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// Reads a document id from either a [DocumentReference] or a plain string.
String? decodeRefId(dynamic value) {
  if (value == null) return null;
  if (value is DocumentReference) return value.id;
  return value.toString();
}

double roundQuantity(double value) =>
    double.parse(value.toStringAsFixed(2));
