// Crea (o reutiliza) una cuenta de familia en el proyecto REAL
// bank-storage-bamx, con el mismo shape que el alta desde staff:
// Auth + users/{uid} + families/{uid}.
//
// No toca recetas, despensa ni entregas.
//
// Uso: node tool/create_family_user.mjs

import {
  PROJECT_ID,
  FirestoreError,
  accessToken,
  setDocument,
} from './firestore_rest.mjs';

const EMAIL = 'familia@prueba.com';
const PASSWORD = 'Prueba1234';
const NAME = 'Familia Prueba';
const ADDRESS = 'Dirección de prueba, Guadalajara';

const str = (value) => ({ stringValue: value });
const ts = (date) => ({ timestampValue: date.toISOString() });
const nul = () => ({ nullValue: null });
const arr = (values) => ({ arrayValue: values.length ? { values } : {} });

async function identityRequest(path, body) {
  const token = await accessToken();
  const url = `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}${path}`;
  let response;
  try {
    response = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(20000),
    });
  } catch (error) {
    throw new FirestoreError(`No se pudo conectar con Auth (${error.message})`);
  }
  const json = await response.json().catch(() => ({}));
  return { ok: response.ok, status: response.status, json };
}

async function lookupUid() {
  const response = await identityRequest('/accounts:lookup', { email: [EMAIL] });
  if (!response.ok) {
    const detail = response.json?.error?.message ?? JSON.stringify(response.json);
    throw new FirestoreError(
      `No se pudo buscar ${EMAIL} (HTTP ${response.status}): ${detail}`,
    );
  }
  const uid = response.json.users?.[0]?.localId;
  if (!uid) {
    throw new FirestoreError(`Auth no devolvió uid para ${EMAIL}`);
  }
  return uid;
}

async function ensureAuthUser() {
  const created = await identityRequest('/accounts', {
    email: EMAIL,
    password: PASSWORD,
    displayName: NAME,
    emailVerified: true,
    disabled: false,
  });
  if (created.ok && created.json.localId) {
    return { uid: created.json.localId, created: true };
  }

  const message = created.json?.error?.message ?? '';
  if (created.status === 400 && String(message).includes('EMAIL_EXISTS')) {
    return { uid: await lookupUid(), created: false };
  }

  const detail = message || JSON.stringify(created.json);
  throw new FirestoreError(
    `No se pudo crear la cuenta ${EMAIL} (HTTP ${created.status}): ${detail}`,
  );
}

async function main() {
  const { uid, created } = await ensureAuthUser();
  const now = new Date();

  await setDocument(`users/${uid}`, {
    name: str(NAME),
    email: str(EMAIL),
    role: str('family'),
    createdAt: ts(now),
  });
  await setDocument(`families/${uid}`, {
    name: str(NAME),
    address: str(ADDRESS),
    registrationDate: ts(now),
    recoveryQuotaDefault: nul(),
    authUid: str(uid),
    appliances: arr([]),
  });

  console.log(created ? 'Cuenta de familia creada.' : 'La cuenta ya existía; se actualizó el perfil.');
  console.log(`email:    ${EMAIL}`);
  console.log(`password: ${PASSWORD}`);
  console.log(`role:     family`);
  console.log(`uid:      ${uid}`);
}

main().catch((error) => {
  console.error(error instanceof FirestoreError ? error.message : error);
  process.exit(1);
});
