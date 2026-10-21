// Carga datos de prueba en los emuladores LOCALES de Firebase
// (proyecto bank-storage-bamx). No toca el proyecto real.
//
// Uso (Node 18 o más reciente, sin dependencias):
//   1. firebase emulators:start --only auth,firestore,functions --import=exported-dev-data --export-on-exit=exported-dev-data
//   2. node tool/seed_emulators.mjs
//
// Se puede correr las veces que sea: reutiliza las cuentas si ya existen y
// sobrescribe los documentos con ids fijos (seed-...). Los datos que se
// agregaron desde la app no se borran, salvo los productos que la Cloud
// Function agregó a la despensa al entregar seed-delivery-2 o seed-delivery-3:
// esas entregas vuelven a quedar programadas y, si se conservaran, se
// duplicarían al entregarlas otra vez.
//
// Cuentas que deja listas:
//   Staff:   staff@bamx.test / bamx1234
//   Nutriólogo: nutriologo@bamx.test / bamx1234
//   Familia: familia.ramirez@bamx.test / bamx1234
//   Solicitud de staff pendiente de aprobar: solicitud.staff@bamx.test / bamx1234
//
// Qué deja para probar:
//   - El catálogo de recetas (tool/catalog_recipes.mjs) con una receta
//     pendiente para el nutriólogo y para "Publicar para las familias".
//   - La próxima entrega de la Familia Ramírez a 9 días, así que su plan es de
//     14 días con productos que caducan a la mitad (plan día por día) y uno
//     ya caducado en la despensa.
//   - Una entrega programada con los 16 productos de las despensas básica y
//     de frescos y la cuota estándar con justificación (el máximo de las
//     reglas, para entregarla o reasignarla).
//   - Un plan de comidas guardado (mealPlans) dentro de los límites de
//     validMeal.
//   - 27 familias más, sin cuenta, con entregas de este mes y del anterior y
//     6 meses de consumptionLogs, para la pestaña "Estadísticas" del staff.

import { RECIPES } from './catalog_recipes.mjs';
import { STANDARD_BASKETS, basketFields } from './standard_baskets.mjs';

const PROJECT_ID = 'bank-storage-bamx';
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9099';
const FIRESTORE_HOST = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';
const FUNCTIONS_HOST = process.env.FUNCTIONS_EMULATOR_HOST ?? '127.0.0.1:5001';

const AUTH_URL = `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1`;
const DOCUMENT_ROOT = `projects/${PROJECT_ID}/databases/(default)/documents`;
const DOCUMENTS_URL = `http://${FIRESTORE_HOST}/v1/${DOCUMENT_ROOT}`;

const PASSWORD = 'bamx1234';
const FAMILY_ID = 'seed-familia-ramirez';
const FAMILY_NAME = 'Familia Ramírez';
const DEVICE_ID = 'seed';
const DAY_MS = 24 * 60 * 60 * 1000;
// Guadalajara está en UTC-6 todo el año (sin horario de verano desde 2022).
const GUADALAJARA_OFFSET_HOURS = 6;
// Igual que Family.standardRecoveryQuota (lib/data/models/family.dart), en MXN.
const STANDARD_RECOVERY_QUOTA = 250;

const STAFF = { email: 'staff@bamx.test', name: 'Staff BAMX' };
const STAFF_REQUEST = { email: 'solicitud.staff@bamx.test', name: 'Laura Méndez' };
const NUTRITIONIST = { email: 'nutriologo@bamx.test', name: 'Nutriólogo BAMX' };
const FAMILY = {
  email: 'familia.ramirez@bamx.test',
  name: FAMILY_NAME,
  address: 'Av. Siempre Viva 123, Guadalajara',
};

const MEMBERS = [
  { name: 'María', memberType: 'adult', age: 38, weightKg: 68, allergies: ['dairy'], chronicConditions: [] },
  { name: 'José', memberType: 'adult', age: 41, weightKg: 98, allergies: [], chronicConditions: ['hypertension', 'obesity'] },
  { name: 'Lucía', memberType: 'child', age: 9, weightKg: 28, sex: 'female', allergies: ['gluten'], chronicConditions: [] },
  { name: 'Diego', memberType: 'child', age: 5, weightKg: 19, sex: 'male', allergies: ['peanut', 'egg'], chronicConditions: [] },
];

// [producto, tipo, cantidad, unidad, días para caducar]; la crema caducó ayer.
const PANTRY = [
  ['Crema', 'dairy', 0.5, 'l', -1],
  ['Leche entera', 'dairy', 2, 'l', 1],
  ['Yogurt natural', 'dairy', 1, 'kg', 2],
  ['Plátano', 'produce', 8, 'piece', 2],
  ['Jamón de pavo', 'protein', 250, 'g', 3],
  ['Pan de caja', 'grain', 1, 'piece', 4],
  ['Jitomate', 'produce', 3.5, 'kg', 5],
  ['Queso panela', 'dairy', 400, 'g', 6],
  ['Salchicha', 'protein', 500, 'g', 8],
  ['Zanahoria', 'produce', 3.5, 'kg', 12],
  ['Avena', 'grain', 1, 'kg', 90],
  ['Pasta para sopa', 'grain', 500, 'g', 120],
  ['Aceite vegetal', 'other', 1, 'l', 150],
  ['Lenteja', 'legume', 1, 'kg', 180],
  ['Arroz', 'grain', 2, 'kg', 210],
  ['Frijol', 'legume', 2, 'kg', 240],
  ['Atún en lata', 'canned', 3, 'can', 300],
];

// Familias sin cuenta (authUid que no existe en Auth): solo alimentan las
// estadísticas y las listas del staff. Nadie puede iniciar sesión con ellas.
const STATS_FAMILIES = [
  'García', 'Hernández', 'Martínez', 'López', 'González', 'Pérez', 'Rodríguez',
  'Sánchez', 'Flores', 'Gómez', 'Díaz', 'Torres', 'Cruz', 'Morales', 'Reyes',
  'Ortiz', 'Gutiérrez', 'Chávez', 'Ramos', 'Ruiz', 'Mendoza', 'Aguilar',
  'Vázquez', 'Castillo', 'Jiménez', 'Romero', 'Herrera',
].map((surname, index) => ({
  id: `seed-stats-family-${String(index + 1).padStart(2, '0')}`,
  name: `Familia ${surname}`,
  address: `Calle ${index + 1} #${100 + index * 7}, Guadalajara`,
}));

// Consumo de cada familia por día de registro: [producto, tipo, unidad,
// cantidad base, cambio de este mes contra el anterior]. Litros, piezas y
// latas también, para la nota de lo que no tiene peso.
const STATS_CONSUMPTION = [
  ['Arroz', 'grain', 'kg', 1.2, 1.27],
  ['Jitomate', 'produce', 'kg', 1.3, 1.27],
  ['Lenteja', 'legume', 'kg', 0.8, 1.27],
  ['Avena', 'grain', 'kg', 0.7, 0.9],
  ['Frijol', 'legume', 'kg', 1.1, 0.9],
  ['Leche entera', 'dairy', 'l', 0.9, 0.9],
  ['Atún en lata', 'canned', 'can', 1, 1],
  ['Plátano', 'produce', 'piece', 3, 1],
];
// Días del mes con consumo y con desperdicio (siempre a mediodía).
const CONSUMPTION_DAYS = [3, 12];
const WASTE_DAY = 20;

class SeedError extends Error { }

// Valores tipados de la API REST de Firestore.
const str = (value) => ({ stringValue: value });
const int = (value) => ({ integerValue: String(value) });
const dbl = (value) => ({ doubleValue: value });
const ts = (date) => ({ timestampValue: date.toISOString() });
const arr = (values) => ({ arrayValue: values.length ? { values } : {} });
const map = (fields) => ({ mapValue: { fields } });
const ref = (path) => ({ referenceValue: `${DOCUMENT_ROOT}/${path}` });

const addDays = (date, days) => new Date(date.getTime() + days * DAY_MS);
const round2 = (value) => Math.round(value * 100) / 100;

/** El año, mes (0-11) y día de [date] en Guadalajara. */
function guadalajaraDay(date) {
  const local = new Date(date.getTime() - GUADALAJARA_OFFSET_HOURS * 3600000);
  return { year: local.getUTCFullYear(), month: local.getUTCMonth(), day: local.getUTCDate() };
}

/** El instante de esa hora en Guadalajara; mes y día pueden desbordarse. */
const guadalajaraTime = (year, month, day, hour = 0) =>
  new Date(Date.UTC(year, month, day, hour + GUADALAJARA_OFFSET_HOURS));

async function request(url, { method = 'GET', body, admin = false } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (admin) headers.Authorization = 'Bearer owner';

  let response;
  try {
    response = await fetch(url, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(10000),
    });
  } catch (error) {
    throw new SeedError(`No se pudo conectar con ${url} (${error.cause?.code ?? error.message})`);
  }

  const text = await response.text();
  let json = {};
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    json = { raw: text };
  }
  return { ok: response.ok, status: response.status, json };
}

function fail(what, response) {
  const detail = response.json?.error?.message ?? JSON.stringify(response.json);
  return new SeedError(`${what} (HTTP ${response.status}): ${detail}`);
}

async function checkEmulators() {
  const targets = [
    ['Auth', `http://${AUTH_HOST}/`],
    ['Firestore', `http://${FIRESTORE_HOST}/`],
  ];
  const missing = [];
  for (const [name, url] of targets) {
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(3000) });
      if (!response.ok) missing.push(`${name} (${url} respondió ${response.status})`);
    } catch {
      missing.push(`${name} (${url})`);
    }
  }
  if (missing.length) {
    throw new SeedError(
      `No se encontraron los emuladores de Firebase: ${missing.join(', ')}.\n` +
      'Inícialos primero con: firebase emulators:start --only auth,firestore,functions --import=exported-dev-data --export-on-exit=exported-dev-data',
    );
  }
}

/** El seed no lo necesita, pero la app sí (agrega productos a la despensa). */
async function isFunctionsEmulatorRunning() {
  try {
    await fetch(`http://${FUNCTIONS_HOST}/`, { signal: AbortSignal.timeout(3000) });
    return true;
  } catch {
    return false;
  }
}

/** Regresa el uid de la cuenta; la crea si no existe. */
async function ensureAuthUser({ email, name }) {
  const credentials = { email, password: PASSWORD, returnSecureToken: true };

  const signIn = await request(
    `${AUTH_URL}/accounts:signInWithPassword?key=fake-api-key`,
    { method: 'POST', body: credentials },
  );
  if (signIn.ok) return { uid: signIn.json.localId, created: false };

  const signUp = await request(`${AUTH_URL}/accounts:signUp?key=fake-api-key`, {
    method: 'POST',
    body: { ...credentials, displayName: name },
  });
  if (signUp.ok) return { uid: signUp.json.localId, created: true };

  // La cuenta existe pero con otra contraseña: se restablece a la de prueba.
  if (signUp.json?.error?.message === 'EMAIL_EXISTS') {
    const lookup = await request(`${AUTH_URL}/projects/${PROJECT_ID}/accounts:lookup`, {
      method: 'POST',
      body: { email: [email] },
      admin: true,
    });
    const uid = lookup.json?.users?.[0]?.localId;
    if (!lookup.ok || !uid) throw fail(`No se pudo buscar la cuenta ${email}`, lookup);

    const update = await request(`${AUTH_URL}/projects/${PROJECT_ID}/accounts:update`, {
      method: 'POST',
      body: { localId: uid, password: PASSWORD, displayName: name },
      admin: true,
    });
    if (!update.ok) throw fail(`No se pudo restablecer la contraseña de ${email}`, update);
    return { uid, created: false };
  }

  throw fail(`No se pudo crear la cuenta ${email}`, signUp);
}

/**
 * Como ensureAuthUser, pero con el uid [uid]. Una familia real tiene
 * familyId == uid (las reglas lo exigen al crearla), y la app guarda cosas
 * con uno o con otro (p. ej. users/{uid}/deviceTokens). Si una corrida
 * anterior creó la cuenta con otro uid, la borra junto con su perfil.
 */
async function ensureAuthUserWithUid({ email, name }, uid) {
  const lookup = await request(`${AUTH_URL}/projects/${PROJECT_ID}/accounts:lookup`, {
    method: 'POST',
    body: { email: [email] },
    admin: true,
  });
  if (!lookup.ok) throw fail(`No se pudo buscar la cuenta ${email}`, lookup);
  const oldUid = lookup.json?.users?.[0]?.localId;
  if (oldUid === uid) return ensureAuthUser({ email, name });

  if (oldUid) {
    const removed = await request(`${AUTH_URL}/projects/${PROJECT_ID}/accounts:delete`, {
      method: 'POST',
      body: { localId: oldUid },
      admin: true,
    });
    if (!removed.ok) throw fail(`No se pudo borrar la cuenta anterior de ${email}`, removed);
    await deleteDocument(`users/${oldUid}`);
  }

  const created = await request(`${AUTH_URL}/projects/${PROJECT_ID}/accounts`, {
    method: 'POST',
    body: { localId: uid, email, password: PASSWORD, displayName: name },
    admin: true,
  });
  if (!created.ok) throw fail(`No se pudo crear la cuenta ${email}`, created);
  return { uid, created: true };
}

/** Crea o reemplaza el documento completo (PATCH sin updateMask). */
async function setDocument(path, fields) {
  const response = await request(`${DOCUMENTS_URL}/${path}`, {
    method: 'PATCH',
    body: { fields },
    admin: true,
  });
  if (!response.ok) throw fail(`No se pudo escribir ${path}`, response);
}

/** Escribe muchos documentos completos, de 500 en 500 (límite de :commit). */
async function setDocuments(documents) {
  for (let start = 0; start < documents.length; start += 500) {
    const writes = documents.slice(start, start + 500).map(([path, fields]) => ({
      update: { name: `${DOCUMENT_ROOT}/${path}`, fields },
    }));
    const response = await request(`${DOCUMENTS_URL}:commit`, {
      method: 'POST',
      body: { writes },
      admin: true,
    });
    if (!response.ok) throw fail(`No se pudieron escribir ${writes.length} documentos`, response);
  }
}

/** Borra un documento; si ya no existe no es error. */
async function deleteDocument(path) {
  const response = await request(`${DOCUMENTS_URL}/${path}`, {
    method: 'DELETE',
    admin: true,
  });
  if (!response.ok && response.status !== 404) {
    throw fail(`No se pudo borrar ${path}`, response);
  }
}

/**
 * Borra de la despensa de la familia los productos que agregó la entrega
 * [deliveryId] y regresa cuántos borró.
 */
async function deletePantryItemsOfDelivery(deliveryId) {
  const response = await request(`${DOCUMENTS_URL}/families/${FAMILY_ID}:runQuery`, {
    method: 'POST',
    admin: true,
    body: {
      structuredQuery: {
        from: [{ collectionId: 'pantryItems' }],
        where: {
          fieldFilter: {
            field: { fieldPath: 'deliveryId' },
            op: 'EQUAL',
            value: str(deliveryId),
          },
        },
      },
    },
  });
  if (!response.ok) throw fail(`No se pudo consultar la despensa de ${FAMILY_ID}`, response);

  const ids = response.json
    .filter((row) => row.document)
    .map((row) => row.document.name.split('/').pop());
  for (const id of ids) {
    await deleteDocument(`families/${FAMILY_ID}/pantryItems/${encodeURIComponent(id)}`);
  }
  return ids.length;
}

/** Otras familias ligadas a la misma cuenta harían ambiguo el inicio de sesión. */
async function otherFamiliesOf(authUid) {
  const response = await request(`${DOCUMENTS_URL}:runQuery`, {
    method: 'POST',
    admin: true,
    body: {
      structuredQuery: {
        from: [{ collectionId: 'families' }],
        where: {
          fieldFilter: {
            field: { fieldPath: 'authUid' },
            op: 'EQUAL',
            value: str(authUid),
          },
        },
      },
    },
  });
  if (!response.ok) throw fail('No se pudieron consultar las familias', response);
  return response.json
    .filter((row) => row.document)
    .map((row) => row.document.name.split('/').pop())
    .filter((id) => id !== FAMILY_ID);
}

function memberFields(member, createdAt) {
  return {
    name: str(member.name),
    memberType: str(member.memberType),
    createdAt: ts(createdAt),
    age: int(member.age),
    weightKg: dbl(member.weightKg),
    ...(member.sex ? { sex: str(member.sex) } : {}),
    allergies: arr(member.allergies.map(str)),
    chronicConditions: arr(member.chronicConditions.map(str)),
  };
}

// localTimestamp es cuándo recibió la familia el producto (la entrega
// seed-delivery-1, hace [daysAgo] días) y daysUntilExpiration se cuenta desde
// ese día, igual que en la Cloud Function; así caduca [days] días después de hoy.
function pantryItemFields([productId, type, quantity, unit, days], receivedAt, daysAgo) {
  return {
    productId: str(productId),
    deliveryId: str('seed-delivery-1'),
    type: str(type),
    quantity: dbl(quantity),
    unit: str(unit),
    daysUntilExpiration: int(days + daysAgo),
    deviceId: str(DEVICE_ID),
    localTimestamp: ts(receivedAt),
  };
}

function deliveryItem([productId, type, quantity, unit], expirationDate) {
  return map({
    productId: str(productId),
    type: str(type),
    quantity: dbl(quantity),
    unit: str(unit),
    expirationDate: ts(expirationDate),
  });
}

const byName = (name) => PANTRY.find(([productId]) => productId === name);

/**
 * Las familias de STATS_FAMILIES, sus entregas de este mes y de los mismos
 * días del anterior, y 6 meses de consumptionLogs de todas las familias
 * (también la Ramírez), como [ruta, campos]. Lo que lee ProgramStats.
 */
function statsDocuments(now) {
  const today = guadalajaraDay(now);
  const lastDayBefore = new Date(Date.UTC(today.year, today.month, 0)).getUTCDate();
  const items = STANDARD_BASKETS[0].items.slice(0, 3);
  const documents = [];

  const delivered = (id, family, date, packages) => [`deliveries/${id}`, {
    familyId: str(family.id),
    familyName: str(family.name),
    deliveryDate: ts(date),
    packages: int(packages),
    status: str('delivered'),
    // Sin productos en su despensa: la marca evita que la Cloud Function la llene.
    pantryStockedAt: ts(date),
    pantryItemsAdded: int(items.length),
    pantryItemsSkipped: int(0),
    items: arr(items.map((item) => deliveryItem(item, addDays(date, item[4])))),
    createdAt: ts(date),
    deviceId: str(DEVICE_ID),
    localTimestamp: ts(date),
  }];

  for (const [index, family] of STATS_FAMILIES.entries()) {
    const n = index + 1;
    documents.push([`families/${family.id}`, {
      name: str(family.name),
      address: str(family.address),
      registrationDate: ts(addDays(now, -200)),
      // La mitad con la cuota estándar y la otra mitad exentas.
      ...(n % 2 === 0 ? { recoveryQuotaDefault: dbl(STANDARD_RECOVERY_QUOTA) } : {}),
      authUid: str(`${family.id}-sin-cuenta`),
      appliances: arr([str('estufa')]),
    }]);
    // Todas reciben este mes (del día 1 a hoy, nunca en el futuro) y 24 de 27
    // en los mismos días del mes anterior.
    const day = 1 + ((n * 5) % today.day);
    const deliveredAt = Math.min(guadalajaraTime(today.year, today.month, day, 11).getTime(), now.getTime());
    documents.push(delivered(`seed-stats-delivery-${n}-now`, family, new Date(deliveredAt), 1 + (n % 2)));
    if (n % 7 !== 0) {
      const dayBefore = 1 + ((n * 5) % Math.min(today.day, lastDayBefore));
      documents.push(delivered(
        `seed-stats-delivery-${n}-before`,
        family,
        guadalajaraTime(today.year, today.month - 1, dayBefore, 11),
        n % 3 === 0 ? 2 : 1,
      ));
    }
  }

  const families = [{ id: FAMILY_ID }, ...STATS_FAMILIES];
  for (const [f, family] of families.entries()) {
    const size = 0.7 + (f % 5) * 0.15;
    for (let m = 0; m < 6; m++) {
      // Crece cada mes; el actual repite el anterior con el cambio de cada producto.
      const growth = 0.75 + 0.06 * Math.min(m, 4);
      const log = (day, key, [productId, type, unit], quantity, reason) => {
        const at = guadalajaraTime(today.year, today.month - 5 + m, day, 12);
        if (at > now) return;
        const { year, month } = guadalajaraDay(at);
        const id = `seed-log-${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}-${key}`;
        documents.push([`families/${family.id}/consumptionLogs/${id}`, {
          productId: str(productId),
          quantity: dbl(quantity),
          unit: str(unit),
          category: str(type),
          at: ts(at),
          deviceId: str(DEVICE_ID),
          reason: str(reason),
        }]);
      };
      for (const day of CONSUMPTION_DAYS) {
        for (const [key, product] of STATS_CONSUMPTION.entries()) {
          const [, , unit, base, change] = product;
          const amount = base * size * growth * (m === 5 ? change : 1);
          const counted = unit === 'piece' || unit === 'can';
          log(day, key, product, counted ? Math.max(1, Math.round(amount)) : round2(amount), 'consumed');
        }
      }
      log(WASTE_DAY, 'caducado', ['Jitomate', 'produce', 'kg'], round2(0.4 * size), 'expired');
    }
  }
  return documents;
}

async function seed() {
  await checkEmulators();

  const now = new Date();
  const registeredAt = addDays(now, -30);
  // A más de 7 días: el plan de comidas de la familia es de 14 (MealPlanLength).
  const scheduledFor = addDays(now, 9);

  const staff = await ensureAuthUser(STAFF);
  const family = await ensureAuthUserWithUid(FAMILY, FAMILY_ID);
  const nutritionist = await ensureAuthUser(NUTRITIONIST);

  await setDocument(`users/${staff.uid}`, {
    name: str(STAFF.name),
    email: str(STAFF.email),
    role: str('staff'),
    createdAt: ts(registeredAt),
  });
  await setDocument(`users/${family.uid}`, {
    name: str(FAMILY.name),
    email: str(FAMILY.email),
    role: str('family'),
    createdAt: ts(registeredAt),
  });
  await setDocument(`users/${nutritionist.uid}`, {
    name: str(NUTRITIONIST.name),
    email: str(NUTRITIONIST.email),
    role: str('nutritionist'),
    createdAt: ts(registeredAt),
  });

  await setDocument(`families/${FAMILY_ID}`, {
    name: str(FAMILY.name),
    address: str(FAMILY.address),
    registrationDate: ts(registeredAt),
    recoveryQuotaDefault: dbl(STANDARD_RECOVERY_QUOTA),
    authUid: str(family.uid),
    appliances: arr([str('refrigerador'), str('estufa')]),
    // Lo mismo que escribe syncNextDelivery (la entrega programada más
    // próxima, seed-delivery-2); aquí también sirve sin el emulador de Functions.
    nextDeliveryDate: ts(scheduledFor),
  });

  // Un minuto entre integrantes para que el orden por createdAt sea estable.
  for (const [index, member] of MEMBERS.entries()) {
    await setDocument(
      `families/${FAMILY_ID}/members/seed-member-${index + 1}`,
      memberFields(member, new Date(registeredAt.getTime() + index * 60000)),
    );
  }

  const deliveredDaysAgo = 2;
  const deliveredAt = addDays(now, -deliveredDaysAgo);
  for (const [index, item] of PANTRY.entries()) {
    await setDocument(
      `families/${FAMILY_ID}/pantryItems/seed-item-${index + 1}`,
      pantryItemFields(item, deliveredAt, deliveredDaysAgo),
    );
  }

  await setDocument('deliveries/seed-delivery-1', {
    familyId: str(FAMILY_ID),
    familyName: str(FAMILY.name),
    deliveryDate: ts(deliveredAt),
    packages: int(1),
    status: str('delivered'),
    // Sus productos ya están arriba (seed-item-...): la marca evita que la
    // Cloud Function los agregue otra vez.
    pantryStockedAt: ts(deliveredAt),
    pantryItemsAdded: int(5),
    pantryItemsSkipped: int(0),
    items: arr(
      ['Leche entera', 'Jitomate', 'Arroz', 'Frijol', 'Atún en lata'].map((name) => {
        const item = byName(name);
        return deliveryItem(item, addDays(now, item[4]));
      }),
    ),
    createdAt: ts(deliveredAt),
    deviceId: str(DEVICE_ID),
    localTimestamp: ts(deliveredAt),
  });

  // Las entregas vuelven a quedar programadas: se quitan de la despensa los
  // productos que un 'Entregar' anterior agregó, para no duplicarlos.
  const removedItems =
    (await deletePantryItemsOfDelivery('seed-delivery-2')) +
    (await deletePantryItemsOfDelivery('seed-delivery-3'));

  await setDocument('deliveries/seed-delivery-2', {
    familyId: str(FAMILY_ID),
    familyName: str(FAMILY.name),
    deliveryDate: ts(scheduledFor),
    packages: int(2),
    recoveryFee: dbl(25),
    justification: str('Nivel de ingreso medio'),
    status: str('scheduled'),
    items: arr([
      deliveryItem(['Leche entera', 'dairy', 2, 'l'], addDays(scheduledFor, 10)),
      deliveryItem(['Arroz', 'grain', 2, 'kg'], addDays(scheduledFor, 210)),
    ]),
    createdAt: ts(now),
    deviceId: str(DEVICE_ID),
    localTimestamp: ts(now),
  });

  // Las despensas básica y de frescos juntas: 16 productos, el máximo de las
  // reglas (validDeliveryItems, Delivery.maxItems), con la cuota estándar.
  const fullDeliveryOn = addDays(now, 16);
  await setDocument('deliveries/seed-delivery-3', {
    familyId: str(FAMILY_ID),
    familyName: str(FAMILY.name),
    deliveryDate: ts(fullDeliveryOn),
    packages: int(1),
    recoveryFee: dbl(STANDARD_RECOVERY_QUOTA),
    justification: str('Cuota estándar'),
    status: str('scheduled'),
    items: arr(
      STANDARD_BASKETS.flatMap((basket) => basket.items).map((item) =>
        deliveryItem(item, addDays(fullDeliveryOn, item[4])),
      ),
    ),
    // Un segundo después de seed-delivery-2: la tabla del staff ordena por
    // createdAt y un empate no tiene orden fijo.
    createdAt: ts(new Date(now.getTime() + 1000)),
    deviceId: str(DEVICE_ID),
    localTimestamp: ts(now),
  });

  for (const basket of STANDARD_BASKETS) {
    await setDocument(`standardBaskets/${basket.id}`, basketFields(basket, now));
  }

  for (const [id, fields] of RECIPES) {
    await setDocument(`recipes/${id}`, fields);
  }
  // Receta de prueba que ya no está en el catálogo; los emuladores con
  // --import todavía la tienen.
  await deleteDocument('recipes/rec_nopal_prueba');

  // Un plan guardado de 7 días desde hoy (medianoche en Guadalajara), dentro
  // de los límites de validMeal: cada fecha dentro del rango y porciones > 0.
  // Solo recetas sin alérgenos de los Ramírez (lácteos, gluten, cacahuate y
  // huevo): la app nunca guardaría otras (filtro de alérgenos de "Cambiar").
  const today = guadalajaraDay(now);
  const planStart = guadalajaraTime(today.year, today.month, today.day);
  const safeRecipeIds = ['rec_sopa_lentejas', 'rec_arroz_atun', 'rec_frijoles'];
  await setDocument('mealPlans/seed-meal-plan-1', {
    familyId: ref(`families/${FAMILY_ID}`),
    dateRangeStart: ts(planStart),
    dateRangeEnd: ts(addDays(planStart, 7)),
    meals: arr(
      Array.from({ length: 7 }, (_, offset) => map({
        date: ts(addDays(planStart, offset)),
        recipeId: str(safeRecipeIds[offset % safeRecipeIds.length]),
        servings: dbl(3.5),
      })),
    ),
  });

  const stats = statsDocuments(now);
  await setDocuments(stats);

  // Solicitud de "Registro de Staff" pendiente. Si una corrida anterior la
  // aprobó, se borra el perfil para que vuelva a quedar pendiente.
  const requester = await ensureAuthUser(STAFF_REQUEST);
  await deleteDocument(`users/${requester.uid}`);
  await setDocument(`staffRequests/${requester.uid}`, {
    name: str(STAFF_REQUEST.name),
    email: str(STAFF_REQUEST.email),
    status: str('pending'),
    createdAt: ts(addDays(now, -1)),
  });

  const duplicates = await otherFamiliesOf(family.uid);
  const functionsRunning = await isFunctionsEmulatorRunning();

  const accountState = (user) => (user.created ? 'creada' : 'ya existía');
  console.log(`Emuladores listos con datos de prueba (proyecto ${PROJECT_ID}).`);
  console.log('');
  console.log(`  Staff:   ${STAFF.email} / ${PASSWORD}  (cuenta ${accountState(staff)})`);
  console.log(`  Familia: ${FAMILY.email} / ${PASSWORD}  (cuenta ${accountState(family)})`);
  console.log(`  Nutriólogo: ${NUTRITIONIST.email} / ${PASSWORD}  (cuenta ${accountState(nutritionist)})`);
  console.log(`  Solicitud de staff pendiente: ${STAFF_REQUEST.email} / ${PASSWORD}`);
  console.log('');
  console.log(`  families/${FAMILY_ID}: ${FAMILY.name}, ${FAMILY.address}`);
  console.log(`  ${MEMBERS.length} integrantes, ${PANTRY.length} productos en la despensa (1 caducado), 3 entregas:`);
  console.log('  1 entregada hace 2 días, 1 programada en 9 días con cuota de $25 (plan de 14 días)');
  console.log(`  y 1 programada en 16 días con 16 productos y cuota de $${STANDARD_RECOVERY_QUOTA}.`);
  console.log('  1 plan de comidas guardado (mealPlans/seed-meal-plan-1, 7 días).');
  console.log(`  ${RECIPES.length} recetas (1 pendiente para el nutriólogo).`);
  console.log(`  ${STANDARD_BASKETS.length} despensas estándar (${STANDARD_BASKETS.map((b) => b.name).join(', ')}).`);
  console.log(
    `  Estadísticas: ${STATS_FAMILIES.length} familias más sin cuenta, con entregas de este mes y del anterior; ` +
    `${stats.filter(([path]) => path.includes('/consumptionLogs/')).length} consumptionLogs de 6 meses.`,
  );
  if (removedItems) {
    console.log(
      `  Se quitaron de la despensa ${removedItems} producto(s) de una entrega anterior de seed-delivery-2 o seed-delivery-3.`,
    );
  }
  if (!functionsRunning) {
    console.warn('');
    console.warn(
      `Aviso: no se encontró el emulador de Functions (${FUNCTIONS_HOST}). Sin él, las entregas no ` +
      'agregan productos a la despensa. Inicia los emuladores con: ' +
      'firebase emulators:start --only auth,firestore,functions --import=exported-dev-data --export-on-exit=exported-dev-data',
    );
  }
  if (duplicates.length) {
    console.warn('');
    console.warn(
      `Aviso: la cuenta de la familia también está ligada a families/${duplicates.join(', families/')}. ` +
      'Bórralas desde la UI de los emuladores (http://127.0.0.1:4000/firestore) para que la app abra ' +
      `families/${FAMILY_ID}.`,
    );
  }
}

try {
  await seed();
} catch (error) {
  if (error instanceof SeedError) {
    console.error(`Error: ${error.message}`);
  } else {
    console.error('Error inesperado al cargar los datos de prueba:', error);
  }
  process.exit(1);
}
