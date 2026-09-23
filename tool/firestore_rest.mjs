import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';

export const PROJECT_ID = process.env.GCLOUD_PROJECT ?? 'bank-storage-bamx';

export class FirestoreError extends Error {}

export function documentsBase() {
  return `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
}

export async function accessToken() {
  const require = createRequire(import.meta.url);
  const root = execSync('npm root -g', { encoding: 'utf8' }).trim();
  const auth = require(`${root}/firebase-tools/lib/auth.js`);
  const scopes = require(`${root}/firebase-tools/lib/scopes.js`);
  const account = auth.getGlobalDefaultAccount();
  if (!account?.tokens?.refresh_token) {
    throw new FirestoreError(
      'No hay sesión de Firebase CLI. Corre: firebase login',
    );
  }
  const tokens = await auth.getAccessToken(account.tokens.refresh_token, [
    scopes.CLOUD_PLATFORM,
    scopes.FIREBASE_PLATFORM,
  ]);
  const token = tokens?.access_token;
  if (!token) {
    throw new FirestoreError('No se pudo obtener un access token. Corre: firebase login');
  }
  return token;
}

export async function firestoreRequest(path, { method = 'GET', body } = {}) {
  const token = await accessToken();
  const url = path.startsWith('http') ? path : `${documentsBase()}/${path}`;
  let response;
  try {
    response = await fetch(url, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(20000),
    });
  } catch (error) {
    throw new FirestoreError(`No se pudo conectar con Firestore (${error.message})`);
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

export async function listDocumentPaths(collectionPath) {
  const paths = [];
  let pageToken;
  do {
    const url = new URL(`${documentsBase()}/${collectionPath}`);
    url.searchParams.set('pageSize', '300');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const response = await firestoreRequest(url.toString());
    if (!response.ok && response.status !== 404) {
      const detail =
        response.json?.error?.message ?? JSON.stringify(response.json);
      throw new FirestoreError(
        `No se pudo listar ${collectionPath} (HTTP ${response.status}): ${detail}`,
      );
    }
    for (const doc of response.json.documents ?? []) {
      const marker = '/documents/';
      const index = doc.name.indexOf(marker);
      paths.push(index >= 0 ? doc.name.slice(index + marker.length) : doc.name);
    }
    pageToken = response.json.nextPageToken;
  } while (pageToken);
  return paths;
}

export async function deletePath(path) {
  const response = await firestoreRequest(path, { method: 'DELETE' });
  if (!response.ok && response.status !== 404) {
    const detail =
      response.json?.error?.message ?? JSON.stringify(response.json);
    throw new FirestoreError(
      `No se pudo borrar ${path} (HTTP ${response.status}): ${detail}`,
    );
  }
}

export async function setDocument(path, fields) {
  const response = await firestoreRequest(path, {
    method: 'PATCH',
    body: { fields },
  });
  if (!response.ok) {
    const detail =
      response.json?.error?.message ?? JSON.stringify(response.json);
    throw new FirestoreError(
      `No se pudo escribir ${path} (HTTP ${response.status}): ${detail}`,
    );
  }
}
