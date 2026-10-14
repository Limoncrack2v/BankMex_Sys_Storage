import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/models/member.dart' as data;
import '../data/models/pantry_item.dart' as data;
import '../ui/models/recipe.dart' as ui;
import '../ui/theme/app_assets.dart';
import 'models/child_profile.dart';
import 'models/family_profile.dart';
import 'recipe_adjustment.dart';
import 'models/pantry_item.dart' as domain;
import 'models/recipe.dart' as domain;

/// Pasa los modelos de Firestore del equipo a la lógica de catálogo/plan.
abstract final class CatalogMappers {
  static domain.PantryItem pantryToDomain(
    data.PantryItem item, {
    required String familyId,
  }) {
    return domain.PantryItem(
      id: item.pantryItemId,
      familyId: familyId,
      productId: item.productId,
      name: item.productId,
      quantity: item.quantity,
      unit: item.unit.name,
      // daysUntilExpiration se cuenta desde que la familia recibió el
      // producto (localTimestamp), no desde hoy.
      expirationDate: item.localTimestamp.add(
        Duration(days: item.daysUntilExpiration),
      ),
      category: item.type.name,
      originalQuantity: item.quantity,
      consumedQuantity: 0,
      status: domain.PantryItemStatus.available,
    );
  }

  /// Un documento de families/{id}/consumptionLogs para las estadísticas.
  /// Con `reason: 'expired'` es desperdicio: cuenta como lo que caducó en la
  /// despensa, con la fecha en que se desechó. Sin `reason` (registros
  /// anteriores) o con 'consumed' es consumo.
  static domain.PantryItem consumptionLogToDomain(
    String logId,
    Map<String, dynamic> log, {
    required String familyId,
    DateTime? now,
  }) {
    final productId = log['productId'] as String? ?? '';
    final quantity = (log['quantity'] as num?)?.toDouble() ?? 0;
    final at = (log['at'] as Timestamp?)?.toDate() ?? now ?? DateTime.now();
    final wasted = log['reason'] == 'expired';
    return domain.PantryItem(
      id: logId,
      familyId: familyId,
      productId: productId,
      name: productId,
      quantity: wasted ? quantity : 0,
      unit: log['unit'] as String? ?? 'g',
      expirationDate: at,
      category: log['category'] as String? ?? '',
      originalQuantity: quantity,
      consumedQuantity: wasted ? 0 : quantity,
      status: wasted
          ? domain.PantryItemStatus.expiredUnused
          : domain.PantryItemStatus.consumed,
      consumedAt: wasted ? null : at,
    );
  }

  static FamilyProfile familyProfile({
    required String familyId,
    required String authUid,
    required List<data.Member> members,
  }) {
    final adults =
        members.where((m) => m.memberType == data.MemberType.adult).length;
    final children = members
        .where((m) => m.memberType == data.MemberType.child)
        .map(
          (m) => ChildProfile(
            age: m.age ?? 8,
            weight: m.weightKg ?? 25,
          ),
        )
        .toList();
    return FamilyProfile(
      id: familyId,
      authUid: authUid,
      adults: members.isEmpty ? 1 : adults,
      children: children,
      dietaryRestrictions: {
        for (final m in members) ...[
          for (final a in m.allergies ?? const <data.Allergy>[]) a.name,
          for (final c
              in m.chronicConditions ?? const <data.ChronicCondition>[])
            c.name,
        ],
      }.toList(),
    );
  }

  static ui.Recipe recipeToUi(domain.Recipe recipe) {
    return ui.Recipe(
      id: recipe.id,
      signature: recipeSignature(recipe),
      name: recipe.name,
      image: recipe.image.isEmpty ? AppImages.sopaDeLentejas : recipe.image,
      minutes: recipe.prepTimeMinutes,
      servings: recipe.servings,
      kcalPerServing: recipe.caloriesPerServing,
      ingredients: [
        for (final ingredient in recipe.ingredients)
          ui.RecipeIngredient(
            ingredient.productName,
            ingredient.quantity,
            _unit(ingredient.unit),
          ),
      ],
      steps: recipe.steps,
    );
  }

  /// La unidad de un ingrediente de receta (acepta "lata", "pieza", ...).
  static data.FoodUnit foodUnit(String unit) => _unit(unit);

  static data.FoodUnit _unit(String unit) {
    final key = unit.trim().toLowerCase();
    for (final value in data.FoodUnit.values) {
      if (value.name == key) return value;
    }
    switch (key) {
      case 'lata':
      case 'latas':
        return data.FoodUnit.can;
      case 'pieza':
      case 'piezas':
      case 'pza':
      case 'pzas':
        return data.FoodUnit.piece;
      case 'paquete':
      case 'paquetes':
        return data.FoodUnit.pack;
      case 'litro':
      case 'litros':
      case 'lt':
        return data.FoodUnit.l;
      case 'gramo':
      case 'gramos':
      case 'gr':
        return data.FoodUnit.g;
      default:
        return data.FoodUnit.kg;
    }
  }
}
