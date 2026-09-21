import 'package:flutter/material.dart';

import '../../../data/models/family.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_bottom_nav.dart';
import '../meal_plan/meal_plan_screen.dart';
import '../pantry/pantry_screen.dart';
import '../profile/profile_screen.dart';
import '../recipes/recipes_screen.dart';

/// App del beneficiario: las 4 pestañas de la barra inferior.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.family});

  final Family family;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final familyId = widget.family.familyId;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _index,
        children: [
          PantryScreen(familyId: familyId),
          RecipesScreen(familyId: familyId),
          MealPlanScreen(familyId: familyId),
          ProfileScreen(family: widget.family),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _index,
        onTap: (index) => setState(() => _index = index),
      ),
    );
  }
}
