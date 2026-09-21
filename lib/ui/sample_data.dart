import '../data/models/pantry_item.dart';
import 'models/recipe.dart';
import 'theme/app_assets.dart';

/// Catálogo de recetas de ejemplo tomado del Figma. Se usa mientras no exista
/// en backend; la disponibilidad de ingredientes, las porciones, las alergias
/// y el plan de comidas sí se calculan con la despensa y los integrantes
/// reales de la familia (ver models/recipe.dart).
abstract final class SampleData {
  static const sopaDeLentejas = Recipe(
    name: 'Sopa de lentejas',
    image: AppImages.sopaDeLentejas,
    minutes: 40,
    servings: 4,
    kcalPerServing: 230,
    ingredients: [
      RecipeIngredient('Lenteja', 0.25, FoodUnit.kg),
      RecipeIngredient('Jitomate', 0.5, FoodUnit.kg),
      RecipeIngredient('Zanahoria', 0.3, FoodUnit.kg),
      RecipeIngredient('Aceite vegetal', 0.05, FoodUnit.l),
    ],
    steps: [
      'Enjuaga las lentejas y ponlas a cocer en agua durante 25 minutos.',
      'Pica el jitomate y la zanahoria en cubos pequeños.',
      'Sofríe las verduras en un poco de aceite hasta que suavicen.',
      'Agrega las verduras a las lentejas y sazona al gusto.',
      'Deja hervir 10 minutos más y sirve caliente.',
    ],
  );

  static const arrozConAtun = Recipe(
    name: 'Arroz con atún',
    image: AppImages.arrozConAtun,
    minutes: 30,
    servings: 4,
    kcalPerServing: 310,
    ingredients: [
      RecipeIngredient('Arroz', 0.3, FoodUnit.kg),
      RecipeIngredient('Atún en lata', 2, FoodUnit.can),
      RecipeIngredient('Jitomate', 0.2, FoodUnit.kg),
      RecipeIngredient('Aceite vegetal', 0.03, FoodUnit.l),
    ],
    steps: [
      'Enjuaga el arroz y fríelo en un poco de aceite hasta que se dore.',
      'Agrega el jitomate picado y sofríe un par de minutos.',
      'Añade 2 tazas de agua, tapa y cocina a fuego bajo 20 minutos.',
      'Escurre el atún y mézclalo con el arroz ya cocido.',
    ],
  );

  static const avenaConFruta = Recipe(
    name: 'Avena con fruta',
    image: AppImages.avenaConFruta,
    minutes: 10,
    servings: 2,
    kcalPerServing: 180,
    ingredients: [
      RecipeIngredient('Avena', 0.15, FoodUnit.kg),
      RecipeIngredient('Leche entera', 0.5, FoodUnit.l),
      RecipeIngredient('Plátano', 2, FoodUnit.piece),
    ],
    steps: [
      'Calienta la leche en una olla a fuego medio.',
      'Agrega la avena y cocina 5 minutos sin dejar de mover.',
      'Rebana el plátano y sírvelo sobre la avena.',
    ],
  );

  static const frijolesDeLaOlla = Recipe(
    name: 'Frijoles de la olla',
    image: AppImages.frijolesDeLaOlla,
    minutes: 90,
    servings: 6,
    kcalPerServing: 200,
    ingredients: [RecipeIngredient('Frijol', 0.5, FoodUnit.kg)],
    steps: [
      'Limpia y enjuaga los frijoles.',
      'Ponlos a cocer en una olla con 2 litros de agua.',
      'Cocina a fuego bajo 90 minutos, agregando agua si hace falta.',
      'Sazona con sal al gusto y sirve.',
    ],
  );

  static const sandwichDeJamonYQueso = Recipe(
    name: 'Sándwich de jamón y queso',
    image: AppImages.sandwichJamonQueso,
    minutes: 8,
    servings: 2,
    kcalPerServing: 260,
    ingredients: [
      RecipeIngredient('Pan de caja', 4, FoodUnit.piece),
      RecipeIngredient('Jamón de pavo', 0.1, FoodUnit.kg),
      RecipeIngredient('Queso panela', 0.1, FoodUnit.kg),
      RecipeIngredient('Jitomate', 0.1, FoodUnit.kg),
    ],
    steps: [
      'Rebana el jitomate y el queso.',
      'Arma los sándwiches con jamón, queso y jitomate.',
      'Calienta en un sartén 2 minutos por lado y sirve.',
    ],
  );

  static const sopaDePastaConVerduras = Recipe(
    name: 'Sopa de pasta con verduras',
    image: AppImages.sopaDePastaConVerduras,
    minutes: 35,
    servings: 5,
    kcalPerServing: 190,
    ingredients: [
      RecipeIngredient('Pasta para sopa', 0.2, FoodUnit.kg),
      RecipeIngredient('Jitomate', 0.3, FoodUnit.kg),
      RecipeIngredient('Zanahoria', 0.2, FoodUnit.kg),
      RecipeIngredient('Aceite vegetal', 0.03, FoodUnit.l),
    ],
    steps: [
      'Licúa el jitomate con un poco de agua.',
      'Fríe la pasta en el aceite hasta que se dore.',
      'Agrega el jitomate licuado y la zanahoria picada.',
      'Añade 1 litro de agua y cocina 20 minutos.',
    ],
  );

  static const recipes = <Recipe>[
    sopaDeLentejas,
    arrozConAtun,
    avenaConFruta,
    frijolesDeLaOlla,
    sandwichDeJamonYQueso,
    sopaDePastaConVerduras,
  ];
}
