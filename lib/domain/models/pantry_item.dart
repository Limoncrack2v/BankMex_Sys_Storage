import '../firestore_codec.dart';

enum PantryItemStatus {
  available,
  consumed,
  expiredUnused;

  String get firestoreValue {
    switch (this) {
      case PantryItemStatus.available:
        return 'available';
      case PantryItemStatus.consumed:
        return 'consumed';
      case PantryItemStatus.expiredUnused:
        return 'expired_unused';
    }
  }

  static PantryItemStatus fromFirestore(String? value) {
    switch (value) {
      case 'consumed':
        return PantryItemStatus.consumed;
      case 'expired_unused':
        return PantryItemStatus.expiredUnused;
      default:
        return PantryItemStatus.available;
    }
  }
}

class PantryItem {
  const PantryItem({
    required this.id,
    required this.familyId,
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.expirationDate,
    required this.category,
    required this.originalQuantity,
    required this.consumedQuantity,
    required this.status,
    this.consumedAt,
  });

  final String id;
  final String familyId;
  final String productId;
  final String name;
  final double quantity;
  final String unit;
  final DateTime expirationDate;
  final String category;

  /// Operational fields used by consumption / waste stats and meal-plan
  /// deductions. They are additive to the confirmed pantry schema.
  final double originalQuantity;
  final double consumedQuantity;
  final PantryItemStatus status;
  final DateTime? consumedAt;

  bool isExpired(DateTime now) => expirationDate.isBefore(now);

  bool isUsable(DateTime now) =>
      status == PantryItemStatus.available &&
      quantity > 0 &&
      !isExpired(now);

  factory PantryItem.fromMap(
    String id,
    String familyId,
    Map<String, dynamic> map,
  ) {
    final quantity = (map['quantity'] as num?)?.toDouble() ?? 0;
    return PantryItem(
      id: id,
      familyId: familyId,
      productId: map['productId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      quantity: quantity,
      unit: map['unit'] as String? ?? '',
      expirationDate: decodeDate(map['expirationDate']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      category: map['category'] as String? ?? '',
      originalQuantity: (map['originalQuantity'] as num?)?.toDouble() ?? quantity,
      consumedQuantity: (map['consumedQuantity'] as num?)?.toDouble() ?? 0,
      status: PantryItemStatus.fromFirestore(map['status'] as String?),
      consumedAt: decodeDate(map['consumedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'expirationDate': expirationDate,
        'category': category,
        'originalQuantity': originalQuantity,
        'consumedQuantity': consumedQuantity,
        'status': status.firestoreValue,
        if (consumedAt != null) 'consumedAt': consumedAt,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'productId': productId,
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'expirationDate': expirationDate.toIso8601String(),
        'category': category,
        'originalQuantity': originalQuantity,
        'consumedQuantity': consumedQuantity,
        'status': status.firestoreValue,
        'consumedAt': consumedAt?.toIso8601String(),
      };

  PantryItem copyWith({
    String? id,
    String? familyId,
    String? productId,
    String? name,
    double? quantity,
    String? unit,
    DateTime? expirationDate,
    String? category,
    double? originalQuantity,
    double? consumedQuantity,
    PantryItemStatus? status,
    DateTime? consumedAt,
    bool clearConsumedAt = false,
  }) {
    return PantryItem(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      productId: productId ?? this.productId,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      expirationDate: expirationDate ?? this.expirationDate,
      category: category ?? this.category,
      originalQuantity: originalQuantity ?? this.originalQuantity,
      consumedQuantity: consumedQuantity ?? this.consumedQuantity,
      status: status ?? this.status,
      consumedAt: clearConsumedAt ? null : (consumedAt ?? this.consumedAt),
    );
  }
}
