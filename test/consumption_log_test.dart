import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/data/repositories/pantry_repository.dart';
import 'package:bank_storage_app/domain/catalog_mappers.dart';
import 'package:bank_storage_app/domain/consumption_stats.dart';
import 'package:bank_storage_app/domain/models/pantry_item.dart' as domain;

/// Recibido el 21 de septiembre; caduca [days] días después.
PantryItem item({
  String productId = 'Leche entera',
  int days = 10,
  FoodType type = FoodType.dairy,
  FoodUnit unit = FoodUnit.l,
}) => PantryItem(
  pantryItemId: 'item-1',
  productId: productId,
  deliveryId: 'entrega-001',
  type: type,
  quantity: 2,
  unit: unit,
  daysUntilExpiration: days,
  deviceId: 'cloud-function',
  localTimestamp: DateTime(2026, 9, 21, 15),
);

// Solo se usan los métodos estáticos: el constructor de PantryRepository
// necesita Firebase.
void main() {
  group('PantryItem.daysLeftOn', () {
    test('counts calendar days since it was received', () {
      final leche = item(days: 10);

      expect(leche.daysLeftOn(DateTime(2026, 9, 21, 23)), 10);
      expect(leche.daysLeftOn(DateTime(2026, 9, 30, 8)), 1);
      expect(leche.daysLeftOn(DateTime(2026, 10, 1)), 0);
      expect(leche.daysLeftOn(DateTime(2026, 10, 2)), -1);
    });
  });

  group('PantryRepository.consumptionLog', () {
    final at = DateTime(2026, 9, 25, 14, 30);

    test('has the fields of the pantry item and the amount', () {
      final log = PantryRepository.consumptionLog(
        item: item(),
        amount: 0.5,
        at: at,
        deviceId: 'phone-1',
      );

      expect(log, {
        'productId': 'Leche entera',
        'quantity': 0.5,
        'unit': 'l',
        'category': 'dairy',
        'at': Timestamp.fromDate(at),
        'deviceId': 'phone-1',
        'reason': 'consumed',
      });
    });

    test('an item used on its last day is still consumed', () {
      final log = PantryRepository.consumptionLog(
        item: item(days: 4),
        amount: 1,
        at: at,
        deviceId: 'phone-1',
      );

      expect(log['reason'], 'consumed');
    });

    test('an item taken out after it expired is waste', () {
      final log = PantryRepository.consumptionLog(
        item: item(days: 3),
        amount: 2,
        at: at,
        deviceId: 'phone-1',
      );

      expect(log['reason'], 'expired');
    });
  });

  group('CatalogMappers.consumptionLogToDomain', () {
    final now = DateTime(2026, 9, 30);

    Map<String, dynamic> log(String reason, {double quantity = 1}) =>
        PantryRepository.consumptionLog(
          item: item(days: reason == 'expired' ? 1 : 30),
          amount: quantity,
          at: DateTime(2026, 9, 25),
          deviceId: 'phone-1',
        );

    test('a consumed log counts as consumption', () {
      final mapped = CatalogMappers.consumptionLogToDomain(
        'log-1',
        log('consumed', quantity: 0.5),
        familyId: 'fam',
      );

      expect(mapped.status, domain.PantryItemStatus.consumed);
      expect(mapped.consumedQuantity, 0.5);
      expect(mapped.quantity, 0);
      expect(mapped.consumedAt, DateTime(2026, 9, 25));
    });

    test('an expired log counts as waste', () {
      final mapped = CatalogMappers.consumptionLogToDomain(
        'log-2',
        log('expired', quantity: 2),
        familyId: 'fam',
      );

      expect(mapped.status, domain.PantryItemStatus.expiredUnused);
      expect(mapped.quantity, 2);
      expect(mapped.consumedQuantity, 0);
    });

    test('a log written before reason existed is consumption', () {
      final old = log('consumed')..remove('reason');

      final mapped = CatalogMappers.consumptionLogToDomain(
        'log-3',
        old,
        familyId: 'fam',
      );

      expect(mapped.status, domain.PantryItemStatus.consumed);
    });

    test('the stats split consumed and wasted logs by category', () {
      final stats = ConsumptionStatsCalculator.getConsumptionWasteStats(
        pantryItems: [
          CatalogMappers.consumptionLogToDomain(
            'a',
            log('consumed', quantity: 0.5),
            familyId: 'fam',
          ),
          CatalogMappers.consumptionLogToDomain(
            'b',
            log('expired', quantity: 2),
            familyId: 'fam',
          ),
        ],
        now: now,
      );

      expect(stats.consumedItemCount, 1);
      expect(stats.consumedByCategory['dairy'], 0.5);
      expect(stats.wastedItemCount, 1);
      expect(stats.wastedByCategory['dairy'], 2);
    });
  });
}
