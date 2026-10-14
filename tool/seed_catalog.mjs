// Escribe SOLO la collection recipes en la Firestore REAL (bank-storage-bamx).
// No toca users, families ni despensa.
//
// Uso: ./scripts/seed_catalog.sh

import { RECIPES } from './catalog_recipes.mjs';
import { PROJECT_ID, FirestoreError, setDocument } from './firestore_rest.mjs';

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
