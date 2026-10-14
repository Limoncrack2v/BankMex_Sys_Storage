import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/app_user.dart';
import 'package:bank_storage_app/data/models/family.dart';
import 'package:bank_storage_app/data/repositories/auth_repository.dart';
import 'package:bank_storage_app/ui/screens/home/home_screen.dart';
import 'package:bank_storage_app/ui/screens/nutritionist/nutritionist_home_screen.dart';
import 'package:bank_storage_app/ui/screens/staff/staff_home_screen.dart';
import 'package:bank_storage_app/ui/session_navigation.dart';

AuthSession session(String role, {Family? family}) => AuthSession(
  user: AppUser(
    userId: 'u1',
    name: 'Nombre',
    email: 'x@y.com',
    role: role,
    createdAt: DateTime(2026, 10, 12),
  ),
  family: family,
);

void main() {
  test('cada rol abre su pantalla', () {
    expect(homeFor(session(AppUser.roleStaff)), isA<StaffHomeScreen>());
    expect(
      homeFor(session(AppUser.roleNutritionist)),
      isA<NutritionistHomeScreen>(),
    );
    final family = Family(
      familyId: 'u1',
      address: 'Calle 13',
      registrationDate: DateTime(2026, 9, 1),
      authUid: 'u1',
      appliances: const [],
    );
    expect(
      homeFor(session(AppUser.roleFamily, family: family)),
      isA<HomeScreen>(),
    );
  });
}
