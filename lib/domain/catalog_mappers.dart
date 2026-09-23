import '../data/models/member.dart' as data;
import '../data/models/pantry_item.dart' as data;
import '../ui/models/recipe.dart' as ui;
import '../ui/theme/app_assets.dart';
import 'models/child_profile.dart';
import 'models/family_profile.dart';
import 'models/pantry_item.dart' as domain;
import 'models/recipe.dart' as domain;

/// Pasa los modelos de Firestore del equipo a la lógica de catálogo/plan.
abstract final class CatalogMappers {
  static domain.PantryItem pantryToDomain(
    data.PantryItem item, {
    required String familyId,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);
    return domain.PantryItem(
      id: item.pantryItemId,
      familyId: familyId,
      productId: item.productId,
      name: item.productId,
      quantity: item.quantity,
      unit: item.unit.name,
      expirationDate: today.add(Duration(days: item.daysUntilExpiration)),
      category: item.type.name,
      originalQuantity: item.quantity,
      consumedQuantity: 0,
      status: domain.PantryItemStatus.available,
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
      dietaryRestrictions: members
          .expand((m) => m.allergies ?? const <data.Allergy>[])
          .map((a) => a.name)
          .toSet()
          .toList(),
    );
  }

  static ui.Recipe recipeToUi(domain.Recipe recipe) {
    return ui.Recipe(
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
