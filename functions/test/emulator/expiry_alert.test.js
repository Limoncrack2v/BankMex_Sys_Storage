// Prueba sendExpiryAlerts contra el emulador de Firestore (el de Functions no
// hace falta): npm run test:emulator --prefix functions
//
// Corre en un proyecto propio de cada corrida: no ve los datos de desarrollo
// ni los de recompute.test.js, que corre al mismo tiempo y borra families.
const test = require('node:test');
const assert = require('node:assert/strict');

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error(
    'Falta FIRESTORE_EMULATOR_HOST. Corre: firebase emulators:exec --only firestore ' +
    '"npm run test:emulator --prefix functions"',
  );
}

const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { sendExpiryAlerts } = require('../../expiry_alert');

const db = getFirestore(initializeApp({ projectId: `expiry-alert-${Date.now()}` }));

// Martes 10 de marzo de 2026, 12:00 en Guadalajara.
const NOW = new Date('2026-03-10T18:00:00Z');

/** Una familia con un token y un producto que caduca en [days] días. */
async function familyWith(uid, days) {
  await db.doc(`users/${uid}/deviceTokens/token-${uid}`).set({
    token: `token-${uid}`,
    platform: 'android',
    updatedAt: NOW,
  });
  await db.doc(`families/${uid}/pantryItems/item-1`).set({
    quantity: 1,
    localTimestamp: NOW,
    daysUntilExpiration: days,
  });
}

test('solo avisa a la familia con algo por caducar', { timeout: 60000 }, async () => {
  await familyWith('soon', 2);
  await familyWith('later', 10);
  const sent = [];

  const result = await sendExpiryAlerts(db, NOW, async (uid) => sent.push(uid));

  assert.deepEqual(sent, ['soon']);
  assert.deepEqual(result, { scanned: 2, alerted: 1, failed: 0 });
});
