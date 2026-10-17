import 'package:bank_storage_app/data/models/family.dart';
import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/domain/models/meal_plan.dart';
import 'package:bank_storage_app/domain/models/recipe_adjustment.dart';
import 'package:bank_storage_app/ui/models/recipe.dart';
import 'package:bank_storage_app/ui/screens/meal_plan/meal_plan_screen.dart';
import 'package:flutter/material.dart';

/// Arma [MealPlanView] a partir de streams, como lo hace [MealPlanScreen] con
/// Firestore, para probar la pantalla del plan sin Firebase. Lo que se
/// guarda, edita o borra no hace nada.
class MealPlanHarness extends StatelessWidget {
  const MealPlanHarness({
    super.key,
    required this.familyId,
    required this.pantry,
    required this.members,
    required this.catalog,
    required this.family,
    this.adjustments,
    this.plans,
    this.onSave,
  });

  final String familyId;
  final Stream<List<PantryItem>> pantry;
  final Stream<List<Member>> members;
  final Stream<List<Recipe>> catalog;
  final Stream<Family?> family;
  final Stream<List<RecipeAdjustment>>? adjustments;
  final Stream<SavedPlans>? plans;
  final Future<void> Function(MealPlan plan)? onSave;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Recipe>>(
      stream: catalog,
      builder: (context, catalogSnapshot) => StreamBuilder<Family?>(
        stream: family,
        builder: (context, familySnapshot) => StreamBuilder<List<Member>>(
          stream: members,
          builder: (context, membersSnapshot) =>
              StreamBuilder<List<PantryItem>>(
                stream: pantry,
                builder: (context, pantrySnapshot) => StreamBuilder<SavedPlans>(
                  stream: plans ?? Stream<SavedPlans>.value(const []),
                  builder: (context, plansSnapshot) =>
                      StreamBuilder<List<RecipeAdjustment>>(
                        stream:
                            adjustments ??
                            Stream<List<RecipeAdjustment>>.value(const []),
                        builder: (context, adjustmentsSnapshot) => MealPlanView(
                          familyId: familyId,
                          catalog: catalogSnapshot,
                          family: familySnapshot,
                          members: membersSnapshot,
                          pantry: pantrySnapshot,
                          plans: plansSnapshot,
                          adjustments: adjustmentsSnapshot,
                          onSave: onSave ?? (_) async {},
                          onSaveMeals: (_) async {},
                          onDelete: (_) async {},
                        ),
                      ),
                ),
              ),
        ),
      ),
    );
  }
}
