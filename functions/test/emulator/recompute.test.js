// Prueba el recálculo diario de nextDeliveryDate contra el emulador de
// Firestore (el de Functions no hace falta): npm run test:emulator --prefix functions
//
// Los triggers programados no se disparan solos en el emulador, así que se
// llama la lógica directo: recomputeStaleNextDeliveries con una hora fija y,
// para el cableado de index.js, el handler real de la función con .run().
// Corre en un proyecto propio de cada corrida: así las cuentas (scanned) son
// exactas y no se mezclan con las de otras pruebas ni dispara syncNextDelivery.
const test = require('node:test');
const assert = require('node:assert/strict');

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error(
    'Falta FIRESTORE_EMULATOR_HOST. Corre: firebase emulators:exec --only firestore ' +
    '--project bank-storage-bamx "npm run test:emulator --prefix functions"',
  );
}
process.env.GCLOUD_PROJECT = `daily-recompute-${Date.now()}`;

const { getFirestore } = require('firebase-admin/firestore');
const functions = require('../../index');
const { refreshNextDelivery, recomputeStaleNextDeliveries } = require('../../next_delivery_sync');

const db = getFirestore();

// Martes 10 de marzo de 2026, 12:00 en Guadalajara (UTC-6). Su medianoche es
// 06:00 UTC.
const NOW = new Date('2026-03-10T18:00:00Z');
const MIDNIGHT = new Date('2026-03-10T06:00:00.000Z');
/** [days] días respecto de hoy, a las [hour] de Guadalajara. */
const day = (days, hour = 12) => new Date(Date.UTC(2026, 2, 10 + days, hour + 6));

let counter = 0;
const nextId = (name) => `${name}-${++counter}`;

async function clear() {
  await db.recursiveDelete(db.collection('families'));
  await db.recursiveDelete(db.collection('deliveries'));
}

async function family(name, nextDeliveryDate) {
  const id = nextId(name);
  await db.collection('families').doc(id).set({
    name: 'Familia Prueba',
    ...(nextDeliveryDate ? { nextDeliveryDate } : {}),
  });
  return id;
}

async function delivery(familyId, status, deliveryDate) {
  await db.collection('deliveries').add({ familyId, status, deliveryDate });
}

async function read(familyId) {
  const snapshot = await db.collection('families').doc(familyId).get();
  // Sin entregas el campo se borra; guardar null sería otra cosa.
  assert.notEqual(snapshot.data().nextDeliveryDate, null, 'nextDeliveryDate quedó en null');
  return { next: snapshot.data().nextDeliveryDate?.toDate() ?? null, updateTime: snapshot.updateTime };
}

test.beforeEach(clear);
test.after(clear);

test('una familia cuya única programada ya pasó pierde el campo', { timeout: 60000 }, async () => {
  const id = await family('pasada', day(-1));
  await delivery(id, 'scheduled', day(-1));

  const result = await recomputeStaleNextDeliveries(db, NOW);

  assert.deepEqual(result, { scanned: 1, updated: 1, failed: 0 });
  assert.equal((await read(id)).next, null);
  const raw = (await db.collection('families').doc(id).get()).data();
  assert.ok(!('nextDeliveryDate' in raw), 'el campo debe borrarse, no quedar en null');
});

test('con una pasada y dos futuras, queda la futura más cercana', { timeout: 60000 }, async () => {
  const id = await family('futura', day(-2));
  await delivery(id, 'scheduled', day(-2));
  await delivery(id, 'scheduled', day(5));
  await delivery(id, 'scheduled', day(2));
  // No cuentan: otro estado, aunque sea más cercana, ni la de otra familia.
  await delivery(id, 'delivered', day(1));
  await delivery(id, 'cancelled', day(1));
  await delivery(id, 'reassigned', day(1));
  await delivery('otra-familia', 'scheduled', day(1));

  await recomputeStaleNextDeliveries(db, NOW);

  assert.deepEqual((await read(id)).next, day(2));
});

test('la programada de hoy más temprano cuenta como próxima', { timeout: 60000 }, async () => {
  const id = await family('hoy-temprano', day(-1));
  await delivery(id, 'scheduled', day(0, 8));
  await delivery(id, 'scheduled', day(-1));

  await recomputeStaleNextDeliveries(db, NOW);

  assert.deepEqual((await read(id)).next, day(0, 8));
});

test('con fecha pasada y sin entregas, el campo se borra', { timeout: 60000 }, async () => {
  const id = await family('sin-entregas', day(-3));

  const result = await recomputeStaleNextDeliveries(db, NOW);

  assert.equal(result.updated, 1);
  assert.equal((await read(id)).next, null);
});

test('las familias de hoy o más adelante, o sin fecha, no se leen ni se escriben', { timeout: 60000 }, async () => {
  const today = await family('hoy', day(0, 8));
  const tomorrow = await family('manana', day(1));
  const atMidnight = await family('medianoche', MIDNIGHT);
  const noField = await family('sin-campo');
  // Aunque sus entregas dirían otra cosa, si la fecha no es pasada no se toca.
  await delivery(today, 'scheduled', day(3));
  const before = await Promise.all([today, tomorrow, atMidnight, noField].map(read));

  const result = await recomputeStaleNextDeliveries(db, NOW);

  assert.deepEqual(result, { scanned: 0, updated: 0, failed: 0 });
  const after = await Promise.all([today, tomorrow, atMidnight, noField].map(read));
  assert.deepEqual(after, before);
});

test('frontera: ayer 23:59:59.999 es pasada; hoy 00:00 y hoy más temprano no', { timeout: 60000 }, async () => {
  const lastMs = await family('ultimo-ms', new Date(MIDNIGHT.getTime() - 1));
  const midnight = await family('medianoche', MIDNIGHT);
  const earlier = await family('temprano', day(0, 1));
  const yesterday = await family('ayer', day(-1, 23));
  const untouched = await Promise.all([midnight, earlier].map(read));

  const result = await recomputeStaleNextDeliveries(db, NOW);

  assert.deepEqual(result, { scanned: 2, updated: 2, failed: 0 });
  assert.equal((await read(lastMs)).next, null);
  assert.equal((await read(yesterday)).next, null);
  assert.deepEqual(await Promise.all([midnight, earlier].map(read)), untouched);
});

test('frontera de zona horaria: a las 20:00 del 9 en Guadalajara (02:00 UTC del 10) ayer a mediodía ya es pasada', { timeout: 60000 }, async () => {
  // En UTC ya sería el 10; en Guadalajara todavía es el 9, así que "hoy" es
  // el 9 y lo del 9 a mediodía no es pasado.
  const now = new Date('2026-03-10T02:00:00Z');
  const the8th = await family('del-8', day(-2));
  const the9th = await family('del-9', day(-1));
  const untouched = await read(the9th);

  const result = await recomputeStaleNextDeliveries(db, now);

  assert.deepEqual(result, { scanned: 1, updated: 1, failed: 0 });
  assert.equal((await read(the8th)).next, null);
  assert.deepEqual(await read(the9th), untouched);
});

test('correrlo dos veces seguidas no cambia nada la segunda vez', { timeout: 60000 }, async () => {
  const gone = await family('se-borra', day(-1));
  const moved = await family('se-mueve', day(-1));
  await delivery(moved, 'scheduled', day(4));

  assert.deepEqual(
    await recomputeStaleNextDeliveries(db, NOW),
    { scanned: 2, updated: 2, failed: 0 },
  );
  const afterFirst = await Promise.all([gone, moved].map(read));

  assert.deepEqual(
    await recomputeStaleNextDeliveries(db, NOW),
    { scanned: 0, updated: 0, failed: 0 },
  );
  assert.deepEqual(await Promise.all([gone, moved].map(read)), afterFirst);
});

test('varias páginas: todas las familias pasadas se recalculan', { timeout: 60000 }, async () => {
  const stale = [];
  for (let i = 0; i < 7; i++) {
    const id = await family('pagina', day(-1 - i));
    if (i % 2 === 0) await delivery(id, 'scheduled', day(1 + i));
    stale.push(id);
  }
  const fresh = await family('vigente', day(1));
  const freshBefore = await read(fresh);

  const result = await recomputeStaleNextDeliveries(db, NOW, { pageSize: 3, concurrency: 2 });

  assert.deepEqual(result, { scanned: 7, updated: 7, failed: 0 });
  for (const [i, id] of stale.entries()) {
    assert.deepEqual((await read(id)).next, i % 2 === 0 ? day(1 + i) : null);
  }
  assert.deepEqual(await read(fresh), freshBefore);
});

test('si una familia falla, las demás se recalculan y la siguiente corrida la completa', { timeout: 60000 }, async () => {
  const good1 = await family('buena', day(-1));
  const bad = await family('mala', day(-1));
  const good2 = await family('buena', day(-2));
  await delivery(bad, 'scheduled', day(2));

  // Una base que falla al escribir la familia "mala".
  const failing = {
    collection: (name) => db.collection(name),
    runTransaction: (update) => db.runTransaction((tx) => update({
      get: (ref) => tx.get(ref),
      update: (ref, data) => {
        if (ref.id === bad) throw new Error('falla de prueba');
        return tx.update(ref, data);
      },
    })),
  };
  const result = await recomputeStaleNextDeliveries(failing, NOW, { pageSize: 1 });

  assert.deepEqual(result, { scanned: 3, updated: 2, failed: 1 });
  assert.equal((await read(good1)).next, null);
  assert.equal((await read(good2)).next, null);
  assert.deepEqual((await read(bad)).next, day(-1), 'la que falló sigue como estaba');

  assert.deepEqual(
    await recomputeStaleNextDeliveries(db, NOW),
    { scanned: 1, updated: 1, failed: 0 },
  );
  assert.deepEqual((await read(bad)).next, day(2));
});

test('si una entrega se escribe mientras corre el recálculo, no queda un valor peor', { timeout: 60000 }, async () => {
  const id = await family('carrera', day(-1));
  await delivery(id, 'scheduled', day(5));

  // Justo después de que el recálculo lee las entregas, se programa una más
  // cercana y se corre el recálculo de syncNextDelivery, como haría el trigger.
  let concurrent;
  const racing = {
    collection: (name) => db.collection(name),
    runTransaction: (update) => db.runTransaction(async (tx) => {
      return update({
        get: async (target) => {
          const snapshot = await tx.get(target);
          if (typeof target.where === 'function' && !concurrent) {
            concurrent = (async () => {
              await delivery(id, 'scheduled', day(2));
              await refreshNextDelivery(db, id, NOW);
            })();
            // Da tiempo a que la escritura ajena choque con esta transacción.
            await new Promise((resolve) => setTimeout(resolve, 500));
          }
          return snapshot;
        },
        update: (ref, data) => tx.update(ref, data),
      });
    }),
  };
  await recomputeStaleNextDeliveries(racing, NOW);
  assert.ok(concurrent, 'la escritura concurrente no se hizo');
  await concurrent;

  assert.deepEqual((await read(id)).next, day(2));
});

test('refreshNextDelivery no crea la familia si no existe', { timeout: 60000 }, async () => {
  await delivery('fantasma', 'scheduled', day(1));

  assert.equal(await refreshNextDelivery(db, 'fantasma', NOW), false);

  assert.equal((await db.collection('families').doc('fantasma').get()).exists, false);
});

test('la función exportada: horario, región y reintentos', () => {
  const trigger = functions.recomputeStaleNextDelivery.__endpoint;

  assert.equal(trigger.scheduleTrigger.schedule, '15 0 * * *');
  assert.equal(trigger.scheduleTrigger.timeZone, 'America/Mexico_City');
  assert.deepEqual(trigger.region, ['us-south1']);
  assert.equal(trigger.scheduleTrigger.retryConfig.retryCount, 3);
  // Las de Firestore también: Cloud Functions no tiene northamerica-south1.
  assert.deepEqual(functions.syncNextDelivery.__endpoint.region, ['us-south1']);
  assert.deepEqual(functions.onDeliveryWritten.__endpoint.region, ['us-south1']);
});

test('la función exportada lanza error si alguna familia falla, para que Scheduler reintente', { timeout: 60000 }, async (t) => {
  const id = await family('falla', day(-1));
  t.mock.method(db, 'runTransaction', async () => {
    throw new Error('falla de prueba');
  });

  await assert.rejects(
    functions.recomputeStaleNextDelivery.run({ scheduleTime: new Date().toISOString() }),
    /1 familias sin recalcular/,
  );
  t.mock.restoreAll();

  // La familia sigue pendiente y la corrida que reintenta la completa.
  assert.deepEqual((await read(id)).next, day(-1));
  await functions.recomputeStaleNextDelivery.run({ scheduleTime: new Date().toISOString() });
  assert.equal((await read(id)).next, null);
});

test('la función exportada recalcula con la hora real',{ timeout: 60000 }, async () => {
  const hour = 60 * 60 * 1000;
  const past = new Date(Date.now() - 40 * hour);
  const future = new Date(Date.now() + 60 * hour);
  const gone = await family('real-borra', past);
  await delivery(gone, 'scheduled', past);
  const moved = await family('real-mueve', past);
  await delivery(moved, 'scheduled', past);
  await delivery(moved, 'scheduled', future);

  await functions.recomputeStaleNextDelivery.run({ scheduleTime: new Date().toISOString() });

  assert.equal((await read(gone)).next, null);
  assert.deepEqual((await read(moved)).next, future);
});
