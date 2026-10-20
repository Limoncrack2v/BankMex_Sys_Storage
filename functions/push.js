// Mensajes push de FCM. Sin dependencias de Firebase: se prueba con node --test.

const TITLE = 'BAMX Guadalajara';
// Texto genérico: la pantalla bloqueada la ve cualquiera (MASVS-PLATFORM-3).
const EXPIRY_BODY = 'Tienes productos por caducar';

// Errores de FCM que dicen que el token ya no sirve: la app se desinstaló o
// llamó a deleteToken().
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

/**
 * El mensaje para sendEachForMulticast: solo título y texto, sin datos de la
 * familia.
 * @param {string[]} tokens
 * @param {string} body
 */
function buildMessage(tokens, body) {
  return { tokens, notification: { title: TITLE, body } };
}

/**
 * Los tokens que FCM dio por muertos, en el orden de [tokens].
 * @param {string[]} tokens
 * @param {{responses: Array<{success: boolean, error?: {code: string}}>}} response
 *   lo que regresa sendEachForMulticast, en el mismo orden que [tokens]
 * @returns {string[]}
 */
function staleTokens(tokens, response) {
  return tokens.filter((_, i) => DEAD_TOKEN_CODES.has(response.responses[i].error?.code));
}

module.exports = { TITLE, EXPIRY_BODY, buildMessage, staleTokens };
