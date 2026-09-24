import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/ui/formatting.dart';

PantryItem buildItem({
  required DateTime localTimestamp,
  required int daysUntilExpiration,
}) => PantryItem(
  pantryItemId: 'p1',
  productId: 'Leche entera',
  deliveryId: 'entrega-1',
  type: FoodType.dairy,
  quantity: 2,
  unit: FoodUnit.l,
  daysUntilExpiration: daysUntilExpiration,
  deviceId: 'device-1',
  localTimestamp: localTimestamp,
);

Member buildMember({MemberType type = MemberType.child, MemberSex? sex}) =>
    Member(
      memberId: 'm1',
      name: 'Lucía',
      memberType: type,
      createdAt: DateTime(2026, 9, 21),
      sex: sex,
    );

void main() {
  group('formatNumber', () {
    test('drops the decimals of whole numbers', () {
      expect(formatNumber(2.0), '2');
      expect(formatNumber(0), '0');
      expect(formatNumber(1000000), '1000000');
    });

    test('keeps only the needed decimals', () {
      expect(formatNumber(2.5), '2.5');
      expect(formatNumber(0.25), '0.25');
      expect(formatNumber(1.125), '1.125');
    });

    test('hides floating point residue', () {
      expect(formatNumber(0.1 + 0.2), '0.3');
      expect(formatNumber(2 - 0.1 * 3), '1.7');
    });
  });

  group('units', () {
    test('countable units use singular only for exactly one', () {
      expect(unitLabel(FoodUnit.piece, 1), 'pieza');
      expect(unitLabel(FoodUnit.piece, 2), 'piezas');
      expect(unitLabel(FoodUnit.piece, 0.5), 'piezas');
      expect(unitLabel(FoodUnit.can, 1), 'lata');
      expect(unitLabel(FoodUnit.can, 3), 'latas');
      expect(unitLabel(FoodUnit.pack, 1), 'paquete');
      expect(unitLabel(FoodUnit.pack, 4), 'paquetes');
    });

    test('measure units are abbreviations', () {
      expect(unitLabel(FoodUnit.kg, 1), 'kg');
      expect(unitLabel(FoodUnit.g, 250), 'g');
      expect(unitLabel(FoodUnit.l, 2), 'L');
      expect(unitLabel(FoodUnit.ml, 500), 'ml');
    });

    test('formatAmount joins the number and the unit', () {
      expect(formatAmount(2, FoodUnit.l), '2 L');
      expect(formatAmount(0.5, FoodUnit.kg), '0.5 kg');
      expect(formatAmount(1, FoodUnit.piece), '1 pieza');
      expect(formatAmount(3, FoodUnit.can), '3 latas');
    });

    test('every unit and food type has a Spanish name', () {
      expect(unitName(FoodUnit.kg), 'Kilogramos (kg)');
      expect(foodTypeLabel(FoodType.dairy), 'Lácteos');
      for (final unit in FoodUnit.values) {
        expect(unitName(unit), isNotEmpty);
      }
      for (final type in FoodType.values) {
        expect(foodTypeLabel(type), isNotEmpty);
      }
    });
  });

  group('productDisplayName', () {
    test('turns slugs into readable names', () {
      expect(productDisplayName('arroz'), 'Arroz');
      expect(productDisplayName('leche_entera'), 'Leche entera');
      expect(productDisplayName('pan-de-caja'), 'Pan de caja');
    });

    test('keeps names that are already readable', () {
      expect(productDisplayName('  Atún en lata '), 'Atún en lata');
      expect(productDisplayName('Jamón de pavo'), 'Jamón de pavo');
      expect(productDisplayName(''), '');
    });
  });

  group('expiration', () {
    final today = DateTime(2026, 9, 21, 8);

    test('daysLeft subtracts the days since the item was registered', () {
      final item = buildItem(
        localTimestamp: DateTime(2026, 9, 18, 22),
        daysUntilExpiration: 5,
      );
      expect(daysLeft(item, today: today), 2);
    });

    test('daysLeft is the stored value on the day it was registered', () {
      final item = buildItem(
        localTimestamp: DateTime(2026, 9, 21, 23),
        daysUntilExpiration: 4,
      );
      expect(daysLeft(item, today: today), 4);
    });

    test('daysLeft is negative once the item expired', () {
      final item = buildItem(
        localTimestamp: DateTime(2026, 9, 10),
        daysUntilExpiration: 5,
      );
      expect(daysLeft(item, today: today), -6);
    });

    test('expirationDate adds the days to the registration date', () {
      final item = buildItem(
        localTimestamp: DateTime(2026, 9, 18, 10),
        daysUntilExpiration: 5,
      );
      expect(expirationDate(item), DateTime(2026, 9, 23, 10));
    });

    test('expirationLabel', () {
      expect(expirationLabel(-2), 'Caducado');
      expect(expirationLabel(0), 'Caduca hoy');
      expect(expirationLabel(1), 'Caduca mañana');
      expect(expirationLabel(3), 'Caduca en 3 días');
    });

    test('daysShortLabel', () {
      expect(daysShortLabel(-1), 'Caducado');
      expect(daysShortLabel(0), 'Hoy');
      expect(daysShortLabel(1), '1 día');
      expect(daysShortLabel(12), '12 días');
    });
  });

  group('dates', () {
    test('formatDateShort is dd/MM/yy', () {
      expect(formatDateShort(DateTime(2026, 9, 10)), '10/09/26');
      expect(formatDateShort(DateTime(2027, 1, 5)), '05/01/27');
    });

    test('formatDateLong uses Spanish month abbreviations', () {
      expect(formatDateLong(DateTime(2026, 9, 10)), '10 sep 2026');
      expect(formatDateLong(DateTime(2026, 1, 15)), '15 ene 2026');
      expect(formatDateLong(DateTime(2025, 12, 31)), '31 dic 2025');
    });
  });

  group('formatRecoveryFee', () {
    test('null means exempt', () {
      expect(formatRecoveryFee(null), 'Exenta');
    });

    test('shows the amount in pesos', () {
      expect(formatRecoveryFee(25), '\$25');
      expect(formatRecoveryFee(12.5), '\$12.50');
      expect(formatRecoveryFee(0), '\$0');
    });
  });

  group('formatMoney', () {
    test('whole amounts without decimals, fractions with two', () {
      expect(formatMoney(25), '\$25');
      expect(formatMoney(25.5), '\$25.50');
      expect(formatMoney(0.05), '\$0.05');
      expect(formatMoney(19.999), '\$20');
    });

    test('thousands separator', () {
      expect(formatMoney(1500), '\$1,500');
      expect(formatMoney(1234567.8), '\$1,234,567.80');
      expect(formatMoney(999), '\$999');
    });
  });

  group('remainingLabel', () {
    test('singular verb only for exactly 1', () {
      expect(remainingLabel(1, FoodUnit.piece), 'Queda 1 pieza');
      expect(remainingLabel(1, FoodUnit.kg), 'Queda 1 kg');
      expect(remainingLabel(2, FoodUnit.kg), 'Quedan 2 kg');
      expect(remainingLabel(1.5, FoodUnit.l), 'Quedan 1.5 L');
      expect(remainingLabel(0.5, FoodUnit.kg), 'Quedan 0.5 kg');
    });
  });

  group('members', () {
    test('memberKindLabel', () {
      expect(memberKindLabel(buildMember(type: MemberType.adult)), 'Adulto');
      expect(memberKindLabel(buildMember(sex: MemberSex.male)), 'Niño');
      expect(memberKindLabel(buildMember(sex: MemberSex.female)), 'Niña');
      expect(memberKindLabel(buildMember()), 'Niña o niño');
    });

    test('formatAge', () {
      expect(formatAge(0), '0 años');
      expect(formatAge(1), '1 año');
      expect(formatAge(38), '38 años');
    });

    test('formatWeight', () {
      expect(formatWeight(68), '68 kg');
      expect(formatWeight(19.5), '19.5 kg');
    });

    test('every allergy has a Spanish label', () {
      expect(allergyLabel(Allergy.dairy), 'Lácteos');
      expect(allergyLabel(Allergy.peanut), 'Cacahuate');
      expect(
        Allergy.values.map(allergyLabel).toSet(),
        hasLength(Allergy.values.length),
      );
    });
  });
}
