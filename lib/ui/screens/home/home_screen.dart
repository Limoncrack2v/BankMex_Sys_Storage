import 'package:flutter/material.dart';

import '../../../data/models/app_user.dart';
import '../../../data/models/family.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_bottom_nav.dart';
import '../meal_plan/meal_plan_screen.dart';
import '../pantry/pantry_screen.dart';
import '../profile/profile_screen.dart';
import '../recipes/recipes_screen.dart';
import '../session/account_sheet.dart';
import 'open_plan_from_reminder.dart';

/// App del beneficiario: las 4 pestañas de la barra inferior.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.family, required this.user});

  final Family family;

  /// La cuenta de la familia (users/{uid}), para "Mi cuenta".
  final AppUser user;

  @override
  State<HomeScreen> createState() => _HomeScreenState();

  /// La pestaña "Plan de comidas": la abre el recordatorio del plan.
  static const planTab = 2;
}

class _HomeScreenState extends State<HomeScreen> with OpenPlanFromReminder {
  int _index = 0;

  @override
  void showPlan() => _index = HomeScreen.planTab;

  @override
  Widget build(BuildContext context) {
    final familyId = widget.family.familyId;
    void openAccount() => showAccountSheet(context, user: widget.user);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _index,
        children: [
          PantryScreen(familyId: familyId, onAccount: openAccount),
          RecipesScreen(familyId: familyId, onAccount: openAccount),
          MealPlanScreen(familyId: familyId, onAccount: openAccount),
          ProfileScreen(family: widget.family, onAccount: openAccount),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _index,
        onTap: (index) => setState(() => _index = index),
      ),
    );
  }
}
