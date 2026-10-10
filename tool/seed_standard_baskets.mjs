// Escribe SOLO la collection standardBaskets en la Firestore REAL
// (bank-storage-bamx), con el contenido de tool/standard_baskets.mjs.
// Sobrescribe cada despensa por su id; no toca entregas ni despensas de
// familias.
//
// Uso: ./scripts/seed_standard_baskets.sh

import { PROJECT_ID, FirestoreError, setDocument } from './firestore_rest.mjs';
import { STANDARD_BASKETS, basketFields } from './standard_baskets.mjs';

async function seed() {
  for (const basket of STANDARD_BASKETS) {
    await setDocument(`standardBaskets/${basket.id}`, basketFields(basket));
  }

  console.log(`Despensas estándar escritas en la BD real (${PROJECT_ID}):`);
  for (const basket of STANDARD_BASKETS) {
    console.log(`  standardBaskets/${basket.id}: ${basket.name}, ${basket.items.length} productos`);
  }
  console.log('  No se modificaron deliveries, families ni pantryItems');
}

try {
  await seed();
} catch (error) {
  if (error instanceof FirestoreError) {
    console.error(`Error: ${error.message}`);
  } else {
    console.error('Error inesperado al cargar las despensas estándar:', error);
  }
  process.exit(1);
}
