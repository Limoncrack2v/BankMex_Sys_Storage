// Borra SOLO recipes, mealPlans y consumptionLogs en la Firestore REAL
// (bank-storage-bamx). No toca users, families, members, pantryItems ni deliveries.
//
// Uso: ./scripts/reset_catalog.sh

import {
  PROJECT_ID,
  FirestoreError,
  listDocumentPaths,
  deletePath,
} from './firestore_rest.mjs';

async function reset() {
  const recipePaths = await listDocumentPaths('recipes');
  const planPaths = await listDocumentPaths('mealPlans');
  const familyPaths = await listDocumentPaths('families');
  const logPaths = [];
  for (const familyPath of familyPaths) {
    logPaths.push(...(await listDocumentPaths(`${familyPath}/consumptionLogs`)));
  }

  for (const path of [...recipePaths, ...planPaths, ...logPaths]) {
    await deletePath(path);
  }

  console.log(`Reset del catálogo en la BD real (${PROJECT_ID}):`);
  console.log(`  recipes:          ${recipePaths.length} documento(s) borrados`);
  console.log(`  mealPlans:        ${planPaths.length} documento(s) borrados`);
  console.log(`  consumptionLogs:  ${logPaths.length} documento(s) borrados`);
  console.log('  Sin tocar: users, families, members, pantryItems, deliveries, Auth');
}

try {
  await reset();
} catch (error) {
  if (error instanceof FirestoreError) {
    console.error(`Error: ${error.message}`);
  } else {
    console.error('Error inesperado al resetear el catálogo:', error);
  }
  process.exit(1);
}
