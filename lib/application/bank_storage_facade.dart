import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/firestore_paths.dart';
import '../data/models/family.dart';
import '../data/models/pantry_item.dart';
import '../data/repositories/adjustment_repository.dart';
import '../data/repositories/family_repository.dart';
import '../data/repositories/meal_plan_repository.dart';
import '../data/repositories/member_repository.dart';
import '../data/repositories/pantry_repository.dart';
import '../data/repositories/recipe_repository.dart';
import '../domain/catalog_mappers.dart';
import '../domain/consumption_stats.dart';
import '../domain/meal_plan_generator.dart';
import '../domain/meal_plan_length.dart';
import '../domain/models/consumption_waste_stats.dart';
import '../domain/models/family_profile.dart';
import '../domain/models/pantry_item.dart' as domain;
import '../domain/models/recipe_adjustment.dart';
import '../domain/models/recipe.dart';
import '../domain/name_normalizer.dart';
import '../domain/nutrition_targets.dart';
import '../domain/pantry_recipe_filter.dart';
import '../domain/portion_adjuster.dart';
import '../domain/recipe_catalog.dart';
import '../domain/recipe_planner.dart';
import '../domain/unit_converter.dart';

/// Orquesta el catálogo y el plan sobre los repos del equipo.
///
/// Contrato para la UI de staff (no hay HTTP):
/// [submitRecipe], [updateRecipe], [deleteRecipe], [watchStaffRecipes].
/// Staff deja las recetas en draft o pending; [approveRecipe] la publica y
/// [rejectRecipe] la regresa a draft, y las dos son del nutriólogo
/// (firestore.rules). Las familias solo ven las approved.
/// La familia lee approved y [filterRecipesByPantry].
class BankStorageFacade {
  BankStorageFacade({
    FamilyRepository? families,
    PantryRepository? pantry,
    MemberRepository? members,
    RecipeRepository? recipes,
    MealPlanRepository? mealPlans,
    AdjustmentRepository? adjustments,
    FirebaseFirestore? firestore,
    RecipePlanner? planner,
  }) : families = families ?? FamilyRepository(),
       planner = planner ?? const RuleBasedRecipePlanner(),
       pantry = pantry ?? PantryRepository(),
       members = members ?? MemberRepository(),
       _db = firestore ?? FirebaseFirestore.instance {
    this.recipes = recipes ?? RecipeRepository(_db);
    this.mealPlans = mealPlans ?? MealPlanRepository(_db);
    this.adjustments = adjustments ?? AdjustmentRepository(_db);
  }

  final FamilyRepository families;
  final PantryRepository pantry;
  final MemberRepository members;
  final RecipePlanner planner;
  late final RecipeRepository recipes;
  late final MealPlanRepository mealPlans;
  late final AdjustmentRepository adjustments;
  final FirebaseFirestore _db;

  Future<Family> _family(String familyId) async {
    final family = await families.getFamily(familyId);
    if (family == null) throw StateError('Family $familyId not found');
    return family;
  }

  Future<FamilyProfile> _profile(String familyId) async =>
      _profileOf(await _family(familyId));

  Future<FamilyProfile> _profileOf(Family family) async {
    final memberList = await members.watchAllMembers(family.familyId).first;
    return CatalogMappers.familyProfile(
      familyId: family.familyId,
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
    List<String> nutritionalTags = const [],
    List<String> requiredEquipment = const [],
    String image = '',
    int servings = 4,
    RecipeStatus status = RecipeStatus.pending,
  }) async {
    final pending = RecipeCatalog.submitRecipe(
      id: id,
      name: name,
      ingredients: ingredients,
      steps: steps,
      prepTimeMinutes: prepTimeMinutes,
      caloriesPerServing: caloriesPerServing,
      dietaryTags: dietaryTags,
      nutritionalTags: nutritionalTags,
      requiredEquipment: requiredEquipment,
      status: status,
    ).copyWith(image: image, servings: servings);
    return recipes.create(pending);
  }

  /// [previous] es la receta guardada antes de editarla: sus etiquetas y
  /// electrodomésticos se conservan aunque esta versión no los conozca. Es
  /// obligatoria para que nadie la olvide al llamar desde el formulario.
  ///
  /// Los tres métodos que guardan son async para que un error de validación
  /// llegue como Future fallido y el formulario lo muestre.
  Future<Recipe> updateRecipe(
    Recipe recipe, {
    required Recipe previous,
  }) async {
    if (recipe.id.isEmpty) {
      throw ArgumentError('updateRecipe requires an id');
    }
    if (recipe.status == RecipeStatus.approved) {
      throw ArgumentError('Solo el nutriólogo deja una receta aprobada');
    }
    RecipeCatalog.validateLimits(
      ingredients: recipe.ingredients,
      steps: recipe.steps,
      dietaryTags: recipe.dietaryTags,
    );
    RecipeCatalog.validateTags(
      nutritionalTags: recipe.nutritionalTags,
      requiredEquipment: recipe.requiredEquipment,
      previous: previous,
    );
    return recipes.update(recipe);
  }

  Future<void> deleteRecipe(String recipeId) => recipes.delete(recipeId);

  Stream<List<Recipe>> watchStaffRecipes() => recipes.watchAll();

  /// Solo el nutriólogo, con inicio de sesión reciente: las reglas no dejan
  /// que nadie más pase una receta de pending a approved. [reviewerUid] es su
  /// uid.
  Future<Recipe> approveRecipe(
    String recipeId, {
    required String reviewerUid,
  }) async {
    final existing = await _pending(recipeId);
    await recipes.approve(recipeId, reviewerUid: reviewerUid);
    return RecipeCatalog.approveRecipe(
      existing,
      approvedBy: reviewerUid,
      at: DateTime.now(),
    );
  }

  /// Regresa la receta a draft con el [note] del rechazo (obligatorio). Mismas
  /// reglas que [approveRecipe].
  Future<Recipe> rejectRecipe(
    String recipeId, {
    required String reviewerUid,
    required String note,
  }) async {
    final error = RecipeCatalog.validateReviewNote(note);
    if (error != null) throw ArgumentError(error);
    final existing = await _pending(recipeId);
    await recipes.reject(recipeId, reviewerUid: reviewerUid, note: note.trim());
    return RecipeCatalog.rejectRecipe(
      existing,
      rejectedBy: reviewerUid,
      note: note,
      at: DateTime.now(),
    );
  }

  Future<Recipe> _pending(String recipeId) async {
    final existing = await recipes.getById(recipeId);
    if (existing == null) {
      throw StateError('Recipe $recipeId not found');
    }
    if (existing.status != RecipeStatus.pending) {
      throw StateError('Recipe $recipeId is not pending review');
    }
    return existing;
  }

  /// Sugiere cómo adaptar [recipeId] (aprobada) al hogar de [familyId]: la
  /// guarda como una adaptación pendiente que solo el nutriólogo puede aprobar.
  /// No hace nada si ya hay una igual (pendiente, aprobada o rechazada) o si
  /// no hay nada que cambiar. Una pendiente vieja (la receta o el hogar
  /// cambiaron) se retira. Regresa la que creó, o null.
  Future<RecipeAdjustment?> suggestAdjustment({
    required String familyId,
    required String recipeId,
  }) async {
    final recipe = await recipes.getById(recipeId);
    if (recipe == null || recipe.status != RecipeStatus.approved) return null;
    final profile = await _profile(familyId);
    final suggestion = await planner.suggestAdjustment(
      family: profile,
      recipe: recipe,
    );
    final existing = await adjustments.listForRecipe(familyId, recipeId);

    bool isCurrent(RecipeAdjustment a) =>
        suggestion != null &&
        a.baseSignature == suggestion.baseSignature &&
        a.householdSize == suggestion.householdSize &&
        a.summary == suggestion.summary;
    for (final old in existing) {
      if (old.status == AdjustmentStatus.pending && !isCurrent(old)) {
        await adjustments.delete(old.id);
      }
    }
    if (suggestion == null || existing.any(isCurrent)) return null;
    return adjustments.create(
      RecipeAdjustment.pending(familyId: familyId, suggestion: suggestion),
    );
  }

  /// Solo el nutriólogo, con inicio de sesión reciente (firestore.rules).
  Future<void> approveAdjustment(
    String adjustmentId, {
    required String reviewerUid,
  }) => adjustments.approve(adjustmentId, reviewerUid: reviewerUid);

  /// Solo el nutriólogo, con inicio de sesión reciente. El motivo es
  /// obligatorio.
  Future<void> rejectAdjustment(
    String adjustmentId, {
    required String reviewerUid,
    required String reason,
  }) {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Escribe el motivo del rechazo');
    }
    if (trimmed.length > RecipeAdjustment.maxReasonLength) {
      throw ArgumentError(
        'El motivo lleva máximo ${RecipeAdjustment.maxReasonLength} caracteres',
      );
    }
    return adjustments.reject(
      adjustmentId,
      reviewerUid: reviewerUid,
      reason: trimmed,
    );
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
        items.add(
          CatalogMappers.consumptionLogToDomain(
            doc.id,
            doc.data(),
            familyId: id,
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

  /// caloricTarget y exclusionList del hogar, para el motor de recetas. No
  /// lleva nombres, edades ni pesos, pero exclusionList sale de las alergias
  /// y enfermedades del hogar (ver [NutritionTargets]).
  Future<NutritionTargets> nutritionTargets(String familyId) async =>
      NutritionTargets.forHousehold(
        await members.watchAllMembers(familyId).first,
      );

  Future<Recipe?> getSingleRecipeOnDemand(String familyId) async {
    final profile = await _profile(familyId);
    final items = await _domainPantry(familyId);
    final catalog = await recipes.listByStatus(RecipeStatus.approved);
    return planner.suggestRecipe(
      family: profile,
      pantryItems: items,
      recipes: catalog,
    );
  }

  /// Sin [days], el plan es semanal o quincenal según la próxima entrega de
  /// la familia (ver [MealPlanLength]).
  Future<MealPlanGeneration> generateMealPlan({
    required String familyId,
    int? days,
  }) async {
    final family = await _family(familyId);
    final profile = await _profileOf(family);
    final items = await _domainPantry(familyId);
    final catalog = await recipes.listByStatus(RecipeStatus.approved);
    final generated = await planner.planDays(
      family: profile,
      pantryItems: items,
      recipes: catalog,
      days:
          days ?? MealPlanLength.daysFor(nextDelivery: family.nextDeliveryDate),
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
  /// (las rules no permiten create en pantryItems), que también deja los
  /// registros de consumptionLogs.
  Future<void> completeRecipe({
    required String familyId,
    required Recipe recipe,
  }) async {
    final profile = await _profile(familyId);
    final adjusted = PortionAdjuster.adjustPortions(recipe, profile);
    final current = await pantry.watchAllPantryItems(familyId).first;
    final consumed = <({PantryItem item, double amount})>[];

    for (final ingredient in adjusted.ingredients) {
      var needed = UnitConverter.toBase(ingredient.quantity, ingredient.unit);
      final matches =
          current.where((item) {
            return NameNormalizer.matches(
                  item.productId,
                  ingredient.productName,
                ) &&
                UnitConverter.compatible(item.unit.name, ingredient.unit);
          }).toList()..sort(
            (a, b) => a.daysUntilExpiration.compareTo(b.daysUntilExpiration),
          );

      for (final item in matches) {
        if (needed <= 0) break;
        final available = UnitConverter.toBase(item.quantity, item.unit.name);
        final take = needed < available ? needed : available;
        final takeInUnit = UnitConverter.fromBase(take, item.unit.name);
        if (takeInUnit <= 0) continue;
        consumed.add((item: item, amount: takeInUnit));
        needed -= take;
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
