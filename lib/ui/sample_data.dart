import 'models/expiration_urgency.dart';
import 'models/household_member.dart';
import 'models/pantry_product.dart';
import 'models/recipe.dart';
import 'theme/app_assets.dart';

/// Datos de ejemplo tomados del Figma. Las pantallas los usan mientras no
/// existan en backend los productos, recetas, plan de comidas e integrantes.
abstract final class SampleData {
  static const familyName = 'Familia Ramírez';

  static const members = <HouseholdMember>[
    HouseholdMember(
      name: 'María',
      age: 38,
      weightKg: 68,
      type: MemberType.adulto,
      allergies: ['Lácteos'],
    ),
    HouseholdMember(name: 'José', age: 41, weightKg: 79, type: MemberType.adulto),
    HouseholdMember(
      name: 'Lucía',
      age: 9,
      weightKg: 28,
      type: MemberType.nina,
      allergies: ['Gluten'],
    ),
    HouseholdMember(
      name: 'Diego',
      age: 5,
      weightKg: 19,
      type: MemberType.nino,
      allergies: ['Cacahuate', 'Huevo'],
    ),
  ];

  static const pantry = <PantryProduct>[
    PantryProduct(
      name: 'Leche entera',
      category: 'Carne, embutidos y lácteos',
      remaining: '2 L',
      daysUntilExpiration: 1,
      synchronized: false,
    ),
    PantryProduct(
      name: 'Yogurt natural',
      category: 'Carne, embutidos y lácteos',
      remaining: '1 kg',
      daysUntilExpiration: 2,
      synchronized: true,
    ),
    PantryProduct(
      name: 'Plátano',
      category: 'Fruta y verdura',
      remaining: '8 piezas',
      daysUntilExpiration: 2,
      synchronized: false,
    ),
    PantryProduct(
      name: 'Jamón de pavo',
      category: 'Carne, embutidos y lácteos',
      remaining: '250 g',
      daysUntilExpiration: 3,
      synchronized: false,
    ),
    PantryProduct(
      name: 'Pan de caja',
      category: 'Abarrotes',
      remaining: '1 pieza',
      daysUntilExpiration: 4,
      synchronized: true,
    ),
    PantryProduct(
      name: 'Jitomate',
      category: 'Fruta y verdura',
      remaining: '3.5 kg',
      daysUntilExpiration: 5,
      synchronized: true,
    ),
    PantryProduct(
      name: 'Queso panela',
      category: 'Carne, embutidos y lácteos',
      remaining: '400 g',
      daysUntilExpiration: 6,
      synchronized: true,
    ),
    PantryProduct(
      name: 'Salchicha',
      category: 'Carne, embutidos y lácteos',
      remaining: '500 g',
      daysUntilExpiration: 8,
      synchronized: true,
    ),
    PantryProduct(
      name: 'Zanahoria',
      category: 'Fruta y verdura',
      remaining: '3.5 kg',
      daysUntilExpiration: 12,
      synchronized: true,
    ),
    PantryProduct(
      name: 'Naranja',
      category: 'Fruta y verdura',
      remaining: '3.5 kg',
      daysUntilExpiration: 18,
      synchronized: true,
    ),
    PantryProduct(
      name: 'Cereal de maíz',
      category: 'Abarrotes',
      remaining: '500 g',
      daysUntilExpiration: 60,
      synchronized: true,
    ),
    PantryProduct(
      name: 'Avena',
      category: 'Canasta básica',
      remaining: '1 kg',
      daysUntilExpiration: 90,
      synchronized: true,
    ),
    PantryProduct(
      name: 'Pasta para sopa',
      category: 'Canasta básica',
      remaining: '500 g',
      daysUntilExpiration: 120,
      synchronized: true,
    ),
    PantryProduct(
      name: 'Aceite vegetal',
      category: 'Canasta básica',
      remaining: '1 L',
      daysUntilExpiration: 150,
      synchronized: true,
    ),
    PantryProduct(
      name: 'Lenteja',
      category: 'Canasta básica',
      remaining: '1 kg',
      daysUntilExpiration: 180,
      synchronized: true,
    ),
    PantryProduct(
      name: 'Arroz',
      category: 'Canasta básica',
      remaining: '2 kg',
      daysUntilExpiration: 210,
      synchronized: false,
    ),
    PantryProduct(
      name: 'Frijol',
      category: 'Canasta básica',
      remaining: '2 kg',
      daysUntilExpiration: 240,
      synchronized: true,
    ),
    PantryProduct(
      name: 'Atún en lata',
      category: 'Abarrotes',
      remaining: '3 latas',
      daysUntilExpiration: 300,
      synchronized: false,
    ),
  ];

  static const sopaDeLentejas = Recipe(
    name: 'Sopa de lentejas',
    image: AppImages.sopaDeLentejas,
    minutes: 40,
    servings: 4,
    kcalPerServing: 230,
    ingredients: [
      RecipeIngredient('Lenteja', '0.25 kg'),
      RecipeIngredient('Jitomate', '0.5 kg'),
      RecipeIngredient('Zanahoria', '0.3 kg'),
      RecipeIngredient('Aceite vegetal', '0.05 L'),
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
      RecipeIngredient('Arroz', '0.3 kg'),
      RecipeIngredient('Atún en lata', '2 latas'),
      RecipeIngredient('Jitomate', '0.2 kg'),
      RecipeIngredient('Aceite vegetal', '0.03 L'),
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
      RecipeIngredient('Avena', '0.15 kg'),
      RecipeIngredient('Leche entera', '0.5 L'),
      RecipeIngredient('Plátano', '2 piezas'),
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
    ingredients: [RecipeIngredient('Frijol', '0.5 kg')],
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
      RecipeIngredient('Pan de caja', '4 rebanadas'),
      RecipeIngredient('Jamón de pavo', '0.1 kg'),
      RecipeIngredient('Queso panela', '0.1 kg'),
      RecipeIngredient('Jitomate', '0.1 kg'),
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
      RecipeIngredient('Pasta para sopa', '0.2 kg'),
      RecipeIngredient('Jitomate', '0.3 kg'),
      RecipeIngredient('Zanahoria', '0.2 kg'),
      RecipeIngredient('Aceite vegetal', '0.03 L'),
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

  static const mealPlan = <MealPlanEntry>[
    MealPlanEntry(
      day: 'Lun',
      recipe: avenaConFruta,
      reason: 'Usa leche y plátano (caducan en 1–2 días)',
      urgency: ExpirationUrgency.urgent,
    ),
    MealPlanEntry(
      day: 'Mar',
      recipe: sandwichDeJamonYQueso,
      reason: 'Jamón caduca en 3 días',
      urgency: ExpirationUrgency.urgent,
    ),
    MealPlanEntry(
      day: 'Mié',
      recipe: sopaDePastaConVerduras,
      reason: 'Aprovecha jitomate (5 días)',
      urgency: ExpirationUrgency.soon,
    ),
    MealPlanEntry(
      day: 'Jue',
      recipe: sopaDeLentejas,
      reason: 'Zanahoria y lenteja en buen estado',
      urgency: ExpirationUrgency.fresh,
    ),
    MealPlanEntry(
      day: 'Vie',
      recipe: arrozConAtun,
      reason: 'Despensa de larga duración',
      urgency: ExpirationUrgency.fresh,
    ),
    MealPlanEntry(
      day: 'Sáb',
      recipe: frijolesDeLaOlla,
      reason: 'Despensa de larga duración',
      urgency: ExpirationUrgency.fresh,
    ),
    MealPlanEntry(
      day: 'Dom',
      recipe: arrozConAtun,
      reason: 'Sobrantes de la semana',
      urgency: ExpirationUrgency.fresh,
    ),
  ];
}
