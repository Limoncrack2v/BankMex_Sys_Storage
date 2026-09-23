import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/firestore_paths.dart';
import '../data/models/pantry_item.dart';
import '../data/repositories/family_repository.dart';
import '../data/repositories/meal_plan_repository.dart';
import '../data/repositories/member_repository.dart';
import '../data/repositories/pantry_repository.dart';
import '../data/repositories/recipe_repository.dart';
import '../domain/catalog_mappers.dart';
import '../domain/consumption_stats.dart';
import '../domain/meal_plan_generator.dart';
import '../domain/models/consumption_waste_stats.dart';
import '../domain/models/family_profile.dart';
import '../domain/models/pantry_item.dart' as domain;
import '../domain/models/recipe.dart';
import '../domain/name_normalizer.dart';
import '../domain/pantry_recipe_filter.dart';
import '../domain/portion_adjuster.dart';
import '../domain/recipe_catalog.dart';
import '../domain/recipe_on_demand.dart';
import '../domain/unit_converter.dart';

/// Orquesta el catálogo y el plan sobre los repos del equipo.
///
/// Contrato para la UI de staff (no hay HTTP):
/// [publishRecipe], [updateRecipe], [deleteRecipe], [watchStaffRecipes].
/// [submitRecipe] deja pending; [approveRecipe] la publica.
/// La familia lee approved y [filterRecipesByPantry].
class BankStorageFacade {
  BankStorageFacade({
    FamilyRepository? families,
    PantryRepository? pantry,
    MemberRepository? members,
    RecipeRepository? recipes,
    MealPlanRepository? mealPlans,
    FirebaseFirestore? firestore,
  })  : families = families ?? FamilyRepository(),
        pantry = pantry ?? PantryRepository(),
        members = members ?? MemberRepository(),
        _db = firestore ?? FirebaseFirestore.instance {
    this.recipes = recipes ?? RecipeRepository(_db);
    this.mealPlans = mealPlans ?? MealPlanRepository(_db);
  }

  final FamilyRepository families;
  final PantryRepository pantry;
  final MemberRepository members;
  late final RecipeRepository recipes;
  late final MealPlanRepository mealPlans;
  final FirebaseFirestore _db;

  Future<FamilyProfile> _profile(String familyId) async {
    final family = await families.getFamily(familyId);
    if (family == null) throw StateError('Family $familyId not found');
    final memberList = await members.watchAllMembers(familyId).first;
    return CatalogMappers.familyProfile(
      familyId: familyId,
      authUid: family.authUid,
      members: memberList,
    );
  }

  Future<List<domain.PantryItem>> _domainPantry(String familyId) async {
    final items = await pantry.watchAllPantryItems(familyId).first;
    return items
        .map((item) => CatalogMappers.pantryToDomain(item, familyId: familyId))
        .toList();
  }

  Future<Recipe> submitRecipe({
    String id = '',
    required String name,
    required List<RecipeIngredient> ingredients,
    required List<String> steps,
    required int prepTimeMinutes,
    required int caloriesPerServing,
    List<String> dietaryTags = const [],
    String image = '',
    int servings = 4,
  }) {
    final pending = RecipeCatalog.submitRecipe(
      id: id,
      name: name,
      ingredients: ingredients,
      steps: steps,
      prepTimeMinutes: prepTimeMinutes,
      caloriesPerServing: caloriesPerServing,
      dietaryTags: dietaryTags,
    ).copyWith(image: image, servings: servings);
    return recipes.create(pending);
  }

  /// Alta del staff: queda approved y la familia ya la puede ver.
  Future<Recipe> publishRecipe({
    String id = '',
    required String name,
    required List<RecipeIngredient> ingredients,
    required List<String> steps,
    required int prepTimeMinutes,
    required int caloriesPerServing,
    List<String> dietaryTags = const [],
    String image = '',
    int servings = 4,
  }) {
    final published = RecipeCatalog.publishRecipe(
      id: id,
      name: name,
      ingredients: ingredients,
      steps: steps,
      prepTimeMinutes: prepTimeMinutes,
      caloriesPerServing: caloriesPerServing,
      dietaryTags: dietaryTags,
    ).copyWith(image: image, servings: servings);
    return recipes.create(published);
  }

  Future<Recipe> updateRecipe(Recipe recipe) {
    if (recipe.id.isEmpty) {
      throw ArgumentError('updateRecipe requires an id');
    }
    return recipes.update(recipe);
  }

  Future<void> deleteRecipe(String recipeId) => recipes.delete(recipeId);

  Stream<List<Recipe>> watchStaffRecipes() => recipes.watchAll();

  Future<Recipe> approveRecipe(String recipeId) async {
    final existing = await recipes.getById(recipeId);
    if (existing == null) {
      throw StateError('Recipe $recipeId not found');
    }
    return recipes.update(RecipeCatalog.approveRecipe(existing));
  }

  Future<List<Recipe>> filterRecipesByPantry(String familyId) async {
    final items = await _domainPantry(familyId);
    final catalog = await recipes.listByStatus(RecipeStatus.approved);
    return PantryRecipeFilter.filterRecipesByPantry(
      pantryItems: items,
      recipes: catalog,
    );
  }

  Future<ConsumptionWasteStats> getConsumptionWasteStats({
    String? familyId,
    String? category,
    DateRange? dateRange,
  }) async {
    final familyIds = <String>[];
    if (familyId != null) {
      familyIds.add(familyId);
    } else {
      final all = await families.watchAllFamilies().first;
      familyIds.addAll(all.map((family) => family.familyId));
    }

    final items = <domain.PantryItem>[];
    for (final id in familyIds) {
      items.addAll(await _domainPantry(id));
      final logs = await _db
          .collection(FirestorePaths.families)
          .doc(id)
          .collection(FirestorePaths.consumptionLogs)
          .get();
      for (final doc in logs.docs) {
        final data = doc.data();
        items.add(
          domain.PantryItem(
            id: doc.id,
            familyId: id,
            productId: data['productId'] as String? ?? '',
            name: data['productId'] as String? ?? '',
            quantity: 0,
            unit: data['unit'] as String? ?? 'g',
            expirationDate: DateTime.now(),
            category: data['category'] as String? ?? '',
            originalQuantity: (data['quantity'] as num?)?.toDouble() ?? 0,
            consumedQuantity: (data['quantity'] as num?)?.toDouble() ?? 0,
            status: domain.PantryItemStatus.consumed,
            consumedAt: (data['at'] as Timestamp?)?.toDate() ?? DateTime.now(),
          ),
        );
      }
    }
    return ConsumptionStatsCalculator.getConsumptionWasteStats(
      pantryItems: items,
      category: category,
      dateRange: dateRange,
    );
  }

  Future<Recipe> adjustPortions(Recipe recipe, FamilyProfile family) async {
    return PortionAdjuster.adjustPortions(recipe, family);
  }

  Future<FamilyProfile> familyProfile(String familyId) => _profile(familyId);

  Future<Recipe?> getSingleRecipeOnDemand(String familyId) async {
    final profile = await _profile(familyId);
    final items = await _domainPantry(familyId);
    final catalog = await recipes.listByStatus(RecipeStatus.approved);
    return RecipeOnDemand.getSingleRecipeOnDemand(
      family: profile,
      pantryItems: items,
      recipes: catalog,
    );
  }

  Future<MealPlanGeneration> generateMealPlan({
    required String familyId,
    required int days,
  }) async {
    final profile = await _profile(familyId);
    final items = await _domainPantry(familyId);
    final catalog = await recipes.listByStatus(RecipeStatus.approved);
    final generated = MealPlanGenerator.generateMealPlan(
      family: profile,
      pantryItems: items,
      recipes: catalog,
      days: days,
    );
    final saved = await mealPlans.create(generated.plan);
    return MealPlanGeneration(
      plan: saved,
      updatedPantry: generated.updatedPantry,
      requestedDays: generated.requestedDays,
      filledDays: generated.filledDays,
    );
  }

  /// Descuenta ingredientes con [PantryRepository.registerConsumption]
  /// (las rules no permiten create en pantryItems).
  Future<void> completeRecipe({
    required String familyId,
    required Recipe recipe,
  }) async {
    final profile = await _profile(familyId);
    final adjusted = PortionAdjuster.adjustPortions(recipe, profile);
    final current = await pantry.watchAllPantryItems(familyId).first;
    final now = DateTime.now();
    final consumed = <({PantryItem item, double amount})>[];

    for (final ingredient in adjusted.ingredients) {
      var needed = UnitConverter.toBase(ingredient.quantity, ingredient.unit);
      final matches = current.where((item) {
        return NameNormalizer.matches(item.productId, ingredient.productName) &&
            UnitConverter.compatible(item.unit.name, ingredient.unit);
      }).toList()
        ..sort((a, b) => a.daysUntilExpiration.compareTo(b.daysUntilExpiration));

      for (final item in matches) {
        if (needed <= 0) break;
        final available = UnitConverter.toBase(item.quantity, item.unit.name);
        final take = needed < available ? needed : available;
        final takeInUnit = UnitConverter.fromBase(take, item.unit.name);
        if (takeInUnit <= 0) continue;
        consumed.add((item: item, amount: takeInUnit));
        needed -= take;
        await _db
            .collection(FirestorePaths.families)
            .doc(familyId)
            .collection(FirestorePaths.consumptionLogs)
            .add({
          'productId': item.productId,
          'quantity': takeInUnit,
          'unit': item.unit.name,
          'category': item.type.name,
          'at': Timestamp.fromDate(now),
        });
      }
    }

    if (consumed.isNotEmpty) {
      final byId = <String, ({PantryItem item, double amount})>{};
      for (final row in consumed) {
        final previous = byId[row.item.pantryItemId];
        byId[row.item.pantryItemId] = (
          item: row.item,
          amount: (previous?.amount ?? 0) + row.amount,
        );
      }
      await pantry.registerConsumption(familyId, byId.values.toList());
    }
  }
}
