// Pruebas del mensaje y de los tokens muertos. No necesitan emuladores:
// npm test --prefix functions
const test = require('node:test');
const assert = require('node:assert/strict');

const { EXPIRY_BODY, TITLE, buildMessage, staleTokens } = require('../push');

test('buildMessage: solo los tokens, el título y el texto genérico', () => {
  assert.deepEqual(buildMessage(['a', 'b'], EXPIRY_BODY), {
    tokens: ['a', 'b'],
    notification: { title: TITLE, body: EXPIRY_BODY },
  });
});

test('staleTokens: solo los que FCM dio por muertos, en orden', () => {
  const tokens = ['ok', 'gone', 'busy', 'bad'];
  const response = {
    responses: [
      { success: true },
      { success: false, error: { code: 'messaging/registration-token-not-registered' } },
      { success: false, error: { code: 'messaging/internal-error' } },
      { success: false, error: { code: 'messaging/invalid-registration-token' } },
    ],
  };
  assert.deepEqual(staleTokens(tokens, response), ['gone', 'bad']);
});
