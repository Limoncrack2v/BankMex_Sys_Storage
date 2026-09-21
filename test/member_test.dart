import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/member.dart';

Member buildMember({String name = 'Ana', MemberType type = MemberType.adult}) =>
    Member(
      memberId: '',
      name: name,
      memberType: type,
      createdAt: DateTime(2026, 9, 21),
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
  });
}
