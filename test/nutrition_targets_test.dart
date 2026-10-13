import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/domain/exclusion_list.dart';
import 'package:bank_storage_app/domain/nutrition_targets.dart';

Member person(
  String name,
  MemberType type, {
  int? age,
  MemberSex? sex,
  List<Allergy>? allergies,
  List<ChronicCondition>? conditions,
}) => Member(
  memberId: name,
  name: name,
  memberType: type,
  createdAt: DateTime(2026, 9, 1),
  age: age,
  sex: sex,
  allergies: allergies,
  chronicConditions: conditions,
);

void main() {
  group('NutritionTargets.forHousehold', () {
    test('adds up the kcal of every member', () {
      final targets = NutritionTargets.forHousehold([
        person('Ana', MemberType.adult),
        person('Beto', MemberType.child, age: 8, sex: MemberSex.male),
      ]);

      // 2700 (adulto sin edad ni peso) + 1830 (niño de 8 años).
      expect(targets.caloricTarget, 4530);
      expect(targets.householdSize, 2);
      expect(targets.unestimatedMembers, 0);
    });

    test('applies the obesity deficit to the target', () {
      final targets = NutritionTargets.forHousehold([
        person(
          'José',
          MemberType.adult,
          conditions: const [ChronicCondition.obesity],
        ),
      ]);

      expect(targets.caloricTarget, 2200);
    });

    test('counts the members it cannot estimate', () {
      final targets = NutritionTargets.forHousehold([
        person('Ana', MemberType.adult),
        person('Sofía', MemberType.child),
      ]);

      expect(targets.caloricTarget, 2700);
      expect(targets.householdSize, 2);
      expect(targets.unestimatedMembers, 1);
    });

    test('the exclusion list joins allergies and conditions', () {
      final members = [
        person('María', MemberType.adult, allergies: const [Allergy.dairy]),
        person(
          'José',
          MemberType.adult,
          conditions: const [ChronicCondition.highCholesterol],
        ),
      ];
      final targets = NutritionTargets.forHousehold(members);

      expect(targets.exclusionList, exclusionKeywords(members));
      expect(targets.exclusionList, containsAll(['leche', 'tocino']));
      // "crema" y "mantequilla" vienen de las dos listas: una sola vez.
      expect(targets.exclusionList.where((k) => k == 'crema'), hasLength(1));
      expect(
        targets.exclusionList,
        orderedEquals([...targets.exclusionList]..sort()),
      );
    });

    test('an empty household has no target and no exclusions', () {
      final targets = NutritionTargets.forHousehold(const []);

      expect(targets.caloricTarget, 0);
      expect(targets.householdSize, 0);
      expect(targets.exclusionList, isEmpty);
    });
  });

  test('toJson carries no names or health data', () {
    final targets = NutritionTargets.forHousehold([
      person(
        'María',
        MemberType.adult,
        allergies: const [Allergy.egg],
        conditions: const [ChronicCondition.diabetes],
      ),
    ]);
    final json = targets.toJson();

    expect(json.keys, {
      'caloricTarget',
      'householdSize',
      'unestimatedMembers',
      'exclusionList',
    });
    final text = json.toString();
    expect(text, isNot(contains('María')));
    expect(text, isNot(contains('diabetes')));
    expect(text, isNot(contains('egg')));
    expect(json['exclusionList'], contains('huevo'));
  });
}
