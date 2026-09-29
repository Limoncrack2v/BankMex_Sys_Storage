import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/domain/energy_requirement.dart';
import 'package:bank_storage_app/ui/formatting.dart';

Member person(MemberType type, {int? age, double? weightKg, MemberSex? sex}) =>
    Member(
      memberId: 'm',
      name: 'Prueba',
      memberType: type,
      createdAt: DateTime(2026, 9, 1),
      age: age,
      weightKg: weightKg,
      sex: sex,
    );

void main() {
  group('EnergyRequirement.dailyKcal', () {
    test('children use the FAO/WHO table by age and sex', () {
      const child = MemberType.child;
      expect(
        EnergyRequirement.dailyKcal(person(child, age: 8, sex: MemberSex.male)),
        1830,
      );
      expect(
        EnergyRequirement.dailyKcal(
          person(child, age: 8, sex: MemberSex.female),
        ),
        1700,
      );
      // Sin sexo: promedio de 1830 y 1698.
      expect(EnergyRequirement.dailyKcal(person(child, age: 8)), 1760);
      expect(
        EnergyRequirement.dailyKcal(
          person(child, age: 17, sex: MemberSex.male),
        ),
        3410,
      );
    });

    test('infants use kcal per kg, or a default without weight', () {
      const child = MemberType.child;
      expect(
        EnergyRequirement.dailyKcal(person(child, age: 0, weightKg: 8)),
        640,
      );
      expect(EnergyRequirement.dailyKcal(person(child, age: 0)), 700);
    });

    test('adults use Schofield BMR x 1.75, averaged by sex', () {
      const adult = MemberType.adult;
      expect(
        EnergyRequirement.dailyKcal(person(adult, age: 25, weightKg: 60)),
        2600,
      );
      // Sin edad ni peso: 30-59 años y 70 kg.
      expect(EnergyRequirement.dailyKcal(person(adult)), 2700);
    });

    test('a child without age cannot be estimated', () {
      expect(
        EnergyRequirement.dailyKcal(person(MemberType.child, weightKg: 20)),
        isNull,
      );
    });
  });

  test('household adds up members and counts the missing ones', () {
    final result = EnergyRequirement.household([
      person(MemberType.adult),
      person(MemberType.child, age: 8, sex: MemberSex.male),
      person(MemberType.child),
    ]);

    expect(result.kcal, 4530);
    expect(result.missing, 1);
    expect(formatDailyKcal(result.kcal), '≈ 4,530 kcal/día');
  });
}
