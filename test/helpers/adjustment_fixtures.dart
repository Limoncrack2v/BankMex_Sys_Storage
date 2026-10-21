import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:bank_storage_app/domain/models/recipe_adjustment.dart';
import 'package:bank_storage_app/domain/recipe_adjustment.dart';

/// Una receta publicada. Por omisión, la avena con leche de 2 porciones.
Recipe approvedRecipe(
  String id,
  String name, {
  int servings = 2,
  List<RecipeIngredient> ingredients = const [
    RecipeIngredient(productName: 'Avena', quantity: 0.1, unit: 'kg'),
    RecipeIngredient(productName: 'Leche entera', quantity: 0.5, unit: 'l'),
    RecipeIngredient(productName: 'Plátano', quantity: 2, unit: 'piece'),
  ],
  List<String> steps = const ['Calienta la leche.', 'Agrega la avena.'],
}) => Recipe(
  id: id,
  name: name,
  ingredients: ingredients,
  steps: steps,
  prepTimeMinutes: 10,
  caloriesPerServing: 180,
  status: RecipeStatus.approved,
  servings: servings,
);

final avenaConFruta = approvedRecipe('r1', 'Avena con fruta');

const portionsChange = AdjustmentChange(
  kind: AdjustmentChange.kindPortions,
  reason: 'tu hogar es de 4 integrantes; la receta rinde 2 porciones',
);
const oatsChange = AdjustmentChange(
  kind: AdjustmentChange.kindSubstitution,
  reason: 'alergia a gluten',
  from: 'Avena',
  to: 'Amaranto',
);
const milkChange = AdjustmentChange(
  kind: AdjustmentChange.kindSubstitution,
  reason: 'alergia a lácteos',
  from: 'Leche entera',
  to: 'Bebida de arroz',
);

const adaptedIngredients = [
  RecipeIngredient(productName: 'Amaranto', quantity: 0.15, unit: 'kg'),
  RecipeIngredient(productName: 'Bebida de arroz', quantity: 0.75, unit: 'l'),
  RecipeIngredient(productName: 'Plátano', quantity: 3, unit: 'piece'),
];

const adaptationSummary =
    'Porciones ajustadas a 3 para tu hogar de 4 integrantes; se sustituye '
    'avena por amaranto por alergia a gluten; se sustituye leche entera por '
    'bebida de arroz por alergia a lácteos';

/// Una adaptación pendiente de [recipe] como la guarda la familia famA: por
/// omisión, para un hogar de 4 con alergia a lácteos y al gluten.
RecipeAdjustment pendingAdjustment(
  Recipe recipe, {
  String? id,
  String? signature,
  int householdSize = 4,
  String householdKey = '4-dairy-gluten',
  int servings = 3,
  List<RecipeIngredient> ingredients = adaptedIngredients,
  List<AdjustmentChange> changes = const [
    portionsChange,
    oatsChange,
    milkChange,
  ],
  String summary = adaptationSummary,
  DateTime? createdAt,
}) {
  final baseSignature = signature ?? recipeSignature(recipe);
  return RecipeAdjustment(
    id: id ?? 'famA_${recipe.id}_${baseSignature}_$householdKey',
    familyId: 'famA',
    recipeId: recipe.id,
    baseSignature: baseSignature,
    householdSize: householdSize,
    householdKey: householdKey,
    servings: servings,
    ingredients: ingredients,
    changes: changes,
    summary: summary,
    status: AdjustmentStatus.pending,
    createdAt: createdAt,
  );
}
