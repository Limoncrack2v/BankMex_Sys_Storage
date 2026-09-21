import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/member.dart';

Member buildMember({
  String name = 'Ana',
  MemberType type = MemberType.adult,
  int? age,
  double? weightKg,
  MemberSex? sex,
  List<Allergy>? allergies,
}) => Member(
  memberId: '',
  name: name,
  memberType: type,
  createdAt: DateTime(2026, 9, 21),
  age: age,
  weightKg: weightKg,
  sex: sex,
  allergies: allergies,
);

void main() {
  group('Member.validate', () {
    test('accepts a normal name', () {
      expect(buildMember().validate(), isNull);
    });

    test('rejects empty and whitespace-only names', () {
      expect(buildMember(name: '').validate(), isNotNull);
      expect(buildMember(name: '   ').validate(), isNotNull);
    });

    test('accepts exactly 100 characters, rejects 101', () {
      expect(buildMember(name: 'a' * 100).validate(), isNull);
      expect(buildMember(name: 'a' * 101).validate(), isNotNull);
    });

    test('measures length after trimming', () {
      expect(buildMember(name: '  ${'a' * 100}  ').validate(), isNull);
    });

    test('age must be between 0 and 120', () {
      expect(buildMember(age: 0).validate(), isNull);
      expect(buildMember(age: Member.maxAge).validate(), isNull);
      expect(buildMember(age: -1).validate(), isNotNull);
      expect(buildMember(age: Member.maxAge + 1).validate(), isNotNull);
    });

    test('weight must be greater than 0 and at most 500', () {
      expect(buildMember(weightKg: 0.1).validate(), isNull);
      expect(buildMember(weightKg: Member.maxWeightKg).validate(), isNull);
      expect(buildMember(weightKg: 0).validate(), isNotNull);
      expect(buildMember(weightKg: -5).validate(), isNotNull);
      expect(buildMember(weightKg: 500.1).validate(), isNotNull);
      expect(buildMember(weightKg: double.nan).validate(), isNotNull);
      expect(buildMember(weightKg: double.infinity).validate(), isNotNull);
    });

    test('rejects duplicate allergies, accepts none and distinct ones', () {
      expect(buildMember(allergies: const []).validate(), isNull);
      expect(
        buildMember(allergies: const [Allergy.egg, Allergy.soy]).validate(),
        isNull,
      );
      expect(
        buildMember(allergies: const [Allergy.egg, Allergy.egg]).validate(),
        isNotNull,
      );
    });
  });

  group('Member.toFirestore', () {
    test('writes exactly the fields the security rules allow', () {
      final data = buildMember(name: '  Ana  ', type: MemberType.child)
          .toFirestore();

      expect(data.keys.toSet(), {'name', 'memberType', 'createdAt'});
      expect(data['name'], 'Ana');
      expect(data['memberType'], 'child');
      expect(data['createdAt'], isA<Timestamp>());
    });

    test('writes the optional fields only when they are set', () {
      final data = buildMember(
        name: 'Lucía',
        type: MemberType.child,
        age: 9,
        weightKg: 28,
        sex: MemberSex.female,
        allergies: const [Allergy.gluten, Allergy.peanut],
      ).toFirestore();

      expect(data.keys.toSet(), {
        'name',
        'memberType',
        'createdAt',
        'age',
        'weightKg',
        'sex',
        'allergies',
      });
      expect(data['age'], 9);
      expect(data['weightKg'], 28.0);
      expect(data['sex'], 'female');
      expect(data['allergies'], ['gluten', 'peanut']);
    });

    test('writes an empty allergy list as "Ninguna"', () {
      final data = buildMember(allergies: const []).toFirestore();

      expect(data.containsKey('allergies'), isTrue);
      expect(data['allergies'], isEmpty);
      expect(data.containsKey('sex'), isFalse);
    });

    test('values match the formats the rules and fromFirestore expect', () {
      final member = buildMember(
        name: 'Diego',
        type: MemberType.child,
        age: 5,
        weightKg: 19.5,
        sex: MemberSex.male,
        allergies: const [Allergy.peanut, Allergy.egg],
      );
      final data = member.toFirestore();

      expect(data['age'], isA<int>());
      expect(data['weightKg'], isA<double>());
      expect(
        MemberType.values.byName(data['memberType'] as String),
        member.memberType,
      );
      expect(MemberSex.values.byName(data['sex'] as String), member.sex);
      expect(
        (data['allergies'] as List)
            .map((a) => Allergy.values.byName(a as String))
            .toList(),
        member.allergies,
      );
      expect((data['createdAt'] as Timestamp).toDate(), member.createdAt);
    });

    test('enum names match the values allowed by the rules', () {
      expect(MemberType.values.map((e) => e.name), ['adult', 'child']);
      expect(MemberSex.values.map((e) => e.name), ['male', 'female']);
      expect(Allergy.values.map((e) => e.name), [
        'dairy',
        'gluten',
        'peanut',
        'shellfish',
        'egg',
        'soy',
      ]);
    });
  });

  group('Member.copyWith', () {
    test('replaces only the memberId', () {
      final original = buildMember(
        age: 38,
        weightKg: 68,
        allergies: const [Allergy.dairy],
      );
      final copy = original.copyWith(memberId: 'm1');

      expect(copy.memberId, 'm1');
      expect(copy.name, original.name);
      expect(copy.age, original.age);
      expect(copy.weightKg, original.weightKg);
      expect(copy.allergies, original.allergies);
      expect(copy.createdAt, original.createdAt);
    });
  });
}
