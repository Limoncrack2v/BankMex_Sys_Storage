import 'package:bank_storage_app/data/device_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('generates a 32-character hexadecimal ID', () async {
    final id = await DeviceIdentity().id;
    expect(id, matches(RegExp(r'^[0-9a-f]{32}')));
  });

  test('returns the same ID on every call', () async {
    final identity = DeviceIdentity();
    final first = await identity.id;
    final second = await identity.id;
    expect(first, second);
  });

  test('reuses the previously stored ID', () async {
    SharedPreferences.setMockInitialValues({'device_id': 'abc'});
    final identityId = await DeviceIdentity().id;
    expect(identityId, 'abc');
  });
}
