// Carga datos de prueba en los emuladores LOCALES de Firebase
// (proyecto bank-storage-bamx). No toca el proyecto real.
//
// Uso (Node 18 o más reciente, sin dependencias):
//   1. firebase emulators:start --only auth,firestore,functions
//   2. node tool/seed_emulators.mjs
//
// Se puede correr las veces que sea: reutiliza las cuentas si ya existen y
// sobrescribe los documentos con ids fijos (seed-...). Los datos que se
// agregaron desde la app no se borran, salvo los productos que la Cloud
// Function agregó a la despensa al entregar seed-delivery-2: esa entrega
// vuelve a quedar programada y, si se conservaran, se duplicarían al
// entregarla otra vez.
//
// Cuentas que deja listas:
//   Staff:   staff@bamx.test / bamx1234
//   Familia: familia.ramirez@bamx.test / bamx1234
//   Solicitud de staff pendiente de aprobar: solicitud.staff@bamx.test / bamx1234

const PROJECT_ID = 'bank-storage-bamx';
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9099';
const FIRESTORE_HOST = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';
const FUNCTIONS_HOST = process.env.FUNCTIONS_EMULATOR_HOST ?? '127.0.0.1:5001';

const AUTH_URL = `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1`;
const DOCUMENTS_URL = `http://${FIRESTORE_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

const PASSWORD = 'bamx1234';
const FAMILY_ID = 'seed-familia-ramirez';
const FAMILY_NAME = 'Familia Ramírez';
const DEVICE_ID = 'seed';
const DAY_MS = 24 * 60 * 60 * 1000;

const STAFF = { email: 'staff@bamx.test', name: 'Staff BAMX' };
const STAFF_REQUEST = { email: 'solicitud.staff@bamx.test', name: 'Laura Méndez' };
const FAMILY = {
  email: 'familia.ramirez@bamx.test',
  name: FAMILY_NAME,
  address: 'Av. Siempre Viva 123, Guadalajara',
};

const MEMBERS = [
  { name: 'María', memberType: 'adult', age: 38, weightKg: 68, allergies: ['dairy'] },
  { name: 'José', memberType: 'adult', age: 41, weightKg: 79, allergies: [] },
  { name: 'Lucía', memberType: 'child', age: 9, weightKg: 28, sex: 'female', allergies: ['gluten'] },
  { name: 'Diego', memberType: 'child', age: 5, weightKg: 19, sex: 'male', allergies: ['peanut', 'egg'] },
];

// [producto, tipo, cantidad, unidad, días para caducar]
const PANTRY = [
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

class SeedError extends Error {}

// Valores tipados de la API REST de Firestore.
const str = (value) => ({ stringValue: value });
const int = (value) => ({ integerValue: String(value) });
const dbl = (value) => ({ doubleValue: value });
const bool = (value) => ({ booleanValue: value });
const ts = (date) => ({ timestampValue: date.toISOString() });
const nul = () => ({ nullValue: null });
const arr = (values) => ({ arrayValue: values.length ? { values } : {} });
const map = (fields) => ({ mapValue: { fields } });

const addDays = (date, days) => new Date(date.getTime() + days * DAY_MS);

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
        'Inícialos primero con: firebase emulators:start --only auth,firestore,functions',
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

/** Crea o reemplaza el documento completo (PATCH sin updateMask). */
async function setDocument(path, fields) {
  const response = await request(`${DOCUMENTS_URL}/${path}`, {
    method: 'PATCH',
    body: { fields },
    admin: true,
  });
  if (!response.ok) throw fail(`No se pudo escribir ${path}`, response);
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
  };
}

function pantryItemFields([productId, type, quantity, unit, days], now) {
  return {
    productId: str(productId),
    deliveryId: str('seed-delivery-1'),
    type: str(type),
    quantity: dbl(quantity),
    unit: str(unit),
    daysUntilExpiration: int(days),
    synchronized: bool(true),
    deviceId: str(DEVICE_ID),
    localTimestamp: ts(now),
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

async function seed() {
  await checkEmulators();

  const now = new Date();
  const registeredAt = addDays(now, -30);

  const staff = await ensureAuthUser(STAFF);
  const family = await ensureAuthUser(FAMILY);

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

  await setDocument(`families/${FAMILY_ID}`, {
    name: str(FAMILY.name),
    address: str(FAMILY.address),
    registrationDate: ts(registeredAt),
    recoveryQuotaDefault: nul(),
    authUid: str(family.uid),
    appliances: arr([str('refrigerador'), str('estufa')]),
  });

  // Un minuto entre integrantes para que el orden por createdAt sea estable.
  for (const [index, member] of MEMBERS.entries()) {
    await setDocument(
      `families/${FAMILY_ID}/members/seed-member-${index + 1}`,
      memberFields(member, new Date(registeredAt.getTime() + index * 60000)),
    );
  }

  for (const [index, item] of PANTRY.entries()) {
    await setDocument(
      `families/${FAMILY_ID}/pantryItems/seed-item-${index + 1}`,
      pantryItemFields(item, now),
    );
  }

  const deliveredAt = addDays(now, -2);
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
  });

  // La entrega vuelve a quedar programada: se quitan de la despensa los
  // productos que un 'Entregar' anterior agregó, para no duplicarlos.
  const removedItems = await deletePantryItemsOfDelivery('seed-delivery-2');

  const scheduledFor = addDays(now, 5);
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
  });

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
  console.log(`  Solicitud de staff pendiente: ${STAFF_REQUEST.email} / ${PASSWORD}`);
  console.log('');
  console.log(`  families/${FAMILY_ID}: ${FAMILY.name}, ${FAMILY.address}`);
  console.log(`  ${MEMBERS.length} integrantes, ${PANTRY.length} productos en la despensa, 2 entregas`);
  console.log('  (1 entregada hace 2 días y 1 programada en 5 días con cuota de $25).');
  if (removedItems) {
    console.log(
      `  Se quitaron de la despensa ${removedItems} producto(s) de una entrega anterior de seed-delivery-2.`,
    );
  }
  if (!functionsRunning) {
    console.warn('');
    console.warn(
      `Aviso: no se encontró el emulador de Functions (${FUNCTIONS_HOST}). Sin él, las entregas no ` +
        'agregan productos a la despensa. Inicia los emuladores con: ' +
        'firebase emulators:start --only auth,firestore,functions',
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
