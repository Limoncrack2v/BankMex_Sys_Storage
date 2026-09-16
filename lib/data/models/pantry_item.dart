import 'package:cloud_firestore/cloud_firestore.dart';

class PantryItem {
  final String pantryItemId;
  final String productId;
  final String deliveryId;
  final int quantity;
  final int daysUntilExpiration;
  final bool synchronized;
  final String deviceId;
  final DateTime localTimestamp;

  PantryItem({
    required this.pantryItemId,
    required this.productId,
    required this.deliveryId,
    required this.quantity,
    required this.daysUntilExpiration,
    required this.synchronized,
    required this.deviceId,
    required this.localTimestamp,
  });

  factory PantryItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    return PantryItem(
      pantryItemId: doc.id,
      productId: data['productId'] as String,
      deliveryId: data['deliveryId'] as String,
      quantity: (data['quantity'] as num).toInt(),
      daysUntilExpiration: (data['daysUntilExpiration'] as num).toInt(),
      synchronized: data['synchronized'] as bool? ?? false,
      deviceId: data['deviceId'] as String,
      localTimestamp: (data['localTimestamp'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'productId': productId,
    'deliveryId': deliveryId,
    'quantity': quantity,
    'daysUntilExpiration': daysUntilExpiration,
    'synchronized': synchronized,
    'deviceId': deviceId,
    'localTimestamp': Timestamp.fromDate(localTimestamp),
  };
}
