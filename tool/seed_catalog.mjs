// Escribe SOLO la collection recipes en la Firestore REAL (bank-storage-bamx).
// No toca users, families ni despensa.
//
// Uso: ./scripts/seed_catalog.sh

import { PROJECT_ID, FirestoreError, setDocument } from './firestore_rest.mjs';

const IMG = 'assets/images/recipes';

const str = (value) => ({ stringValue: value });
const int = (value) => ({ integerValue: String(value) });
const dbl = (value) => ({ doubleValue: value });
const arr = (values) => ({ arrayValue: values.length ? { values } : {} });
const map = (fields) => ({ mapValue: { fields } });

function ingredient(productName, quantity, unit) {
  return map({
    productName: str(productName),
    quantity: dbl(quantity),
    unit: str(unit),
  });
}

function recipeFields({
  name,
  image,
  minutes,
  servings,
  kcal,
  ingredients,
  steps,
  status = 'approved',
}) {
  return {
    name: str(name),
    image: str(image),
    prepTimeMinutes: int(minutes),
    servings: int(servings),
    caloriesPerServing: int(kcal),
    status: str(status),
    dietaryTags: arr([]),
    ingredients: arr(ingredients),
    steps: arr(steps.map(str)),
  };
}

const RECIPES = [
  [
    'rec_sopa_lentejas',
    recipeFields({
      name: 'Sopa de lentejas',
      image: `${IMG}/sopa_de_lentejas.jpg`,
      minutes: 40,
      servings: 4,
      kcal: 230,
      ingredients: [
        ingredient('Lenteja', 0.25, 'kg'),
        ingredient('Jitomate', 0.5, 'kg'),
        ingredient('Zanahoria', 0.3, 'kg'),
        ingredient('Aceite vegetal', 0.05, 'l'),
      ],
      steps: [
        'Enjuaga las lentejas y ponlas a cocer en agua durante 25 minutos.',
        'Pica el jitomate y la zanahoria en cubos pequeños.',
        'Sofríe las verduras en un poco de aceite hasta que suavicen.',
        'Agrega las verduras a las lentejas y sazona al gusto.',
        'Deja hervir 10 minutos más y sirve caliente.',
      ],
    }),
  ],
  [
    'rec_arroz_atun',
    recipeFields({
      name: 'Arroz con atún',
      image: `${IMG}/arroz_con_atun.jpg`,
      minutes: 30,
      servings: 4,
      kcal: 310,
      ingredients: [
        ingredient('Arroz', 0.3, 'kg'),
        ingredient('Atún en lata', 2, 'can'),
        ingredient('Jitomate', 0.2, 'kg'),
        ingredient('Aceite vegetal', 0.03, 'l'),
      ],
      steps: [
        'Enjuaga el arroz y fríelo en un poco de aceite hasta que se dore.',
        'Agrega el jitomate picado y sofríe un par de minutos.',
        'Añade 2 tazas de agua, tapa y cocina a fuego bajo 20 minutos.',
        'Escurre el atún y mézclalo con el arroz ya cocido.',
      ],
    }),
  ],
  [
    'rec_avena_fruta',
    recipeFields({
      name: 'Avena con fruta',
      image: `${IMG}/avena_con_fruta.jpg`,
      minutes: 10,
      servings: 2,
      kcal: 180,
      ingredients: [
        ingredient('Avena', 0.15, 'kg'),
        ingredient('Leche entera', 0.5, 'l'),
        ingredient('Plátano', 2, 'piece'),
      ],
      steps: [
        'Calienta la leche en una olla a fuego medio.',
        'Agrega la avena y cocina 5 minutos sin dejar de mover.',
        'Rebana el plátano y sírvelo sobre la avena.',
      ],
    }),
  ],
  [
    'rec_frijoles',
    recipeFields({
      name: 'Frijoles de la olla',
      image: `${IMG}/frijoles_de_la_olla.jpg`,
      minutes: 90,
      servings: 6,
      kcal: 200,
      ingredients: [ingredient('Frijol', 0.5, 'kg')],
      steps: [
        'Limpia y enjuaga los frijoles.',
        'Ponlos a cocer en una olla con 2 litros de agua.',
        'Cocina a fuego bajo 90 minutos, agregando agua si hace falta.',
        'Sazona con sal al gusto y sirve.',
      ],
    }),
  ],
  [
    'rec_sandwich',
    recipeFields({
      name: 'Sándwich de jamón y queso',
      image: `${IMG}/sandwich_jamon_queso.jpg`,
      minutes: 8,
      servings: 2,
      kcal: 260,
      ingredients: [
        ingredient('Pan de caja', 4, 'piece'),
        ingredient('Jamón de pavo', 0.1, 'kg'),
        ingredient('Queso panela', 0.1, 'kg'),
        ingredient('Jitomate', 0.1, 'kg'),
      ],
      steps: [
        'Rebana el jitomate y el queso.',
        'Arma los sándwiches con jamón, queso y jitomate.',
        'Calienta en un sartén 2 minutos por lado y sirve.',
      ],
    }),
  ],
  [
    'rec_sopa_pasta',
    recipeFields({
      name: 'Sopa de pasta con verduras',
      image: `${IMG}/sopa_de_pasta_con_verduras.jpg`,
      minutes: 35,
      servings: 5,
      kcal: 190,
      ingredients: [
        ingredient('Pasta para sopa', 0.2, 'kg'),
        ingredient('Jitomate', 0.3, 'kg'),
        ingredient('Zanahoria', 0.2, 'kg'),
        ingredient('Aceite vegetal', 0.03, 'l'),
      ],
      steps: [
        'Licúa el jitomate con un poco de agua.',
        'Fríe la pasta en el aceite hasta que se dore.',
        'Agrega el jitomate licuado y la zanahoria picada.',
        'Añade 1 litro de agua y cocina 20 minutos.',
      ],
    }),
  ],
  [
    'rec_nopal_prueba',
    recipeFields({
      name: 'Tacos de nopal PRUEBA-EMULADOR',
      image: `${IMG}/sopa_de_lentejas.jpg`,
      minutes: 15,
      servings: 4,
      kcal: 140,
      ingredients: [
        ingredient('Nopal PRUEBA-EMULADOR', 4, 'piece'),
        ingredient('Jitomate', 0.2, 'kg'),
      ],
      steps: [
        'Esta receta se insertó en el emulador para ver el catálogo en Firestore.',
        'Asa el nopal y sirve con jitomate.',
      ],
    }),
  ],
  [
    'rec_pending_demo',
    recipeFields({
      name: 'Ensalada de naranja (pendiente)',
      image: `${IMG}/avena_con_fruta.jpg`,
      minutes: 10,
      servings: 2,
      kcal: 90,
      status: 'pending',
      ingredients: [ingredient('Naranja', 0.4, 'kg')],
      steps: ['Pela y sirve.'],
    }),
  ],
];

async function seed() {
  for (const [id, fields] of RECIPES) {
    await setDocument(`recipes/${id}`, fields);
  }

  const approved = RECIPES.filter(([, fields]) => fields.status.stringValue === 'approved').length;
  console.log(`Catálogo escrito en la BD real (${PROJECT_ID}):`);
  console.log(`  recipes/: ${approved} approved, 1 pending (Ensalada de naranja)`);
  console.log('  Incluye Tacos de nopal PRUEBA-EMULADOR');
  console.log('  No se modificaron users, families ni pantryItems');
  console.log('  Consola: https://console.firebase.google.com/project/bank-storage-bamx/firestore');
}

try {
  await seed();
} catch (error) {
  if (error instanceof FirestoreError) {
    console.error(`Error: ${error.message}`);
  } else {
    console.error('Error inesperado al cargar el catálogo:', error);
  }
  process.exit(1);
}
