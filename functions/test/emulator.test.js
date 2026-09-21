// Prueba onDeliveryWritten contra los emuladores LOCALES (Firestore 8080 y
// Functions). No toca el proyecto real: el Admin SDK se conecta solo al
// emulador.
//
// Uso, con `firebase emulators:start --only auth,firestore,functions`
// corriendo:
//   npm run test:emulators
process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';

const assert = require('node:assert/strict');
const { after, before, describe, test } = require('node:test');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

const PROJECT_ID = 'bank-storage-bamx';
const DAY_MS = 24 * 60 * 60 * 1000;
const run = `emu-${Date.now()}`;
const familyId = `${run}-familia`;

let app;
let db;
const createdDeliveries = [];

const inDays = (days) => Timestamp.fromDate(new Date(Date.now() + days * DAY_MS));
const deliveryItem = (productId, days, extra = {}) => ({
  productId,
  type: 'grain',
  quantity: 2,
  unit: 'kg',
  expirationDate: inDays(days),
  ...extra,
});

async function writeDelivery(id, status, items) {
  createdDeliveries.push(id);
  await db.doc(`deliveries/${id}`).set({
    familyId,
    familyName: 'Familia Emulador',
    deliveryDate: Timestamp.now(),
    packages: 1,
    status,
    items,
    createdAt: Timestamp.now(),
  });
}

const pantryOf = async (deliveryId) =>
  (await db.collection(`families/${familyId}/pantryItems`).where('deliveryId', '==', deliveryId).get()).docs;

/** Espera a que [check] regrese algo distinto de null/false. */
async function waitFor(check, what, timeoutMs = 30000) {
  const end = Date.now() + timeoutMs;
  for (;;) {
    const value = await check();
    if (value) return value;
    if (Date.now() > end) throw new Error(`Tiempo agotado esperando: ${what}`);
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
}

const stockedMark = (deliveryId) =>
  waitFor(async () => {
    const data = (await db.doc(`deliveries/${deliveryId}`).get()).data();
    return data?.pantryStockedAt ? data : null;
  }, `pantryStockedAt en ${deliveryId} (¿está corriendo el emulador de Functions?)`);

before(async () => {
  app = initializeApp({ projectId: PROJECT_ID }, run);
  db = getFirestore(app);
  await db.doc(`families/${familyId}`).set({
    name: 'Familia Emulador',
    address: 'Calle 1',
    registrationDate: Timestamp.now(),
    recoveryQuotaDefault: null,
    authUid: familyId,
    appliances: [],
  });
});

after(async () => {
  const pantry = await db.collection(`families/${familyId}/pantryItems`).get();
  await Promise.all(pantry.docs.map((doc) => doc.ref.delete()));
  await Promise.all(createdDeliveries.map((id) => db.doc(`deliveries/${id}`).delete()));
  await db.doc(`families/${familyId}`).delete();
  await deleteApp(app);
});

describe('onDeliveryWritten', () => {
  test('una entrega registrada como entregada llena la despensa, sin los caducados', async () => {
    const id = `${run}-entregada`;
    await writeDelivery(id, 'delivered', [
      deliveryItem('Arroz', 5),
      deliveryItem('Leche', -3, { type: 'dairy', unit: 'l' }),
      deliveryItem('Frijol', 30, { type: 'legume', quantity: 1.5 }),
    ]);

    const mark = await stockedMark(id);
    assert.equal(mark.pantryItemsAdded, 2);
    assert.equal(mark.pantryItemsSkipped, 1);

    const docs = await pantryOf(id);
    const byName = Object.fromEntries(docs.map((doc) => [doc.data().productId, doc]));
    assert.deepEqual(Object.keys(byName).sort(), ['Arroz', 'Frijol']);
    assert.equal(byName.Arroz.id, `${id}-1`);
    assert.equal(byName.Frijol.id, `${id}-3`);

    const arroz = byName.Arroz.data();
    assert.equal(arroz.deliveryId, id);
    assert.equal(arroz.type, 'grain');
    assert.equal(arroz.quantity, 2);
    assert.equal(arroz.unit, 'kg');
    assert.equal(arroz.daysUntilExpiration, 5);
    assert.equal(arroz.synchronized, true);
    assert.equal(arroz.deviceId, 'cloud-function');
    assert.ok(arroz.localTimestamp instanceof Timestamp);
    assert.equal(byName.Frijol.data().quantity, 1.5);
  });

  test('una programada no llena la despensa hasta que se marca como entregada', async () => {
    const id = `${run}-programada`;
    await writeDelivery(id, 'scheduled', [deliveryItem('Avena', 90)]);

    await new Promise((resolve) => setTimeout(resolve, 3000));
    assert.equal((await pantryOf(id)).length, 0);
    assert.equal((await db.doc(`deliveries/${id}`).get()).data().pantryStockedAt, undefined);

    await db.doc(`deliveries/${id}`).update({ status: 'delivered' });
    const mark = await stockedMark(id);
    assert.equal(mark.pantryItemsAdded, 1);
    assert.equal((await pantryOf(id)).length, 1);
  });

  test('otra escritura sobre una entrega ya surtida no duplica productos', async () => {
    const id = `${run}-sin-duplicar`;
    await writeDelivery(id, 'delivered', [deliveryItem('Lenteja', 60)]);
    await stockedMark(id);

    await db.doc(`deliveries/${id}`).update({ notes: 'otra escritura' });
    await new Promise((resolve) => setTimeout(resolve, 3000));
    assert.equal((await pantryOf(id)).length, 1);
  });

  test('una cancelada no llena la despensa', async () => {
    const id = `${run}-cancelada`;
    await writeDelivery(id, 'scheduled', [deliveryItem('Atún', 300)]);
    await db.doc(`deliveries/${id}`).update({ status: 'cancelled' });

    await new Promise((resolve) => setTimeout(resolve, 3000));
    assert.equal((await pantryOf(id)).length, 0);
  });
});
