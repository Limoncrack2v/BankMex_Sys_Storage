import '../domain/catalog_mappers.dart';
import '../domain/models/recipe.dart';
import '../ui/models/recipe.dart' as ui;
import 'repositories/recipe_repository.dart';

/// Recetas approved desde Firestore. Si la colección está vacía, la UI sigue
/// usando SampleData (el catálogo de Figma). La familia solo puede leer estas.
Stream<List<ui.Recipe>> watchApprovedCatalogRecipes() {
  return RecipeRepository()
      .watchByStatus(RecipeStatus.approved)
      .map((recipes) => recipes.map(CatalogMappers.recipeToUi).toList());
}

/// Catálogo completo para el staff (pending y approved).
Stream<List<ui.Recipe>> watchStaffCatalogRecipes() {
  return RecipeRepository()
      .watchAll()
      .map((recipes) => recipes.map(CatalogMappers.recipeToUi).toList());
}
