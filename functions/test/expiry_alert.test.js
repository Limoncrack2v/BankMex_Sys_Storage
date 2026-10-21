// Pruebas de expiringSoon. No necesitan emuladores: npm test --prefix functions
const test = require('node:test');
const assert = require('node:assert/strict');

const { expiringSoon } = require('../expiry_alert');

// Martes 10 de marzo de 2026, 12:00 en Guadalajara (UTC-6).
const NOW = new Date('2026-03-10T18:00:00Z');
/** Un producto recibido hoy al mediodía que caduca en [days] días. */
const item = (days, extra = {}) => ({
  quantity: 1,
  localTimestamp: NOW,
  daysUntilExpiration: days,
  ...extra,
});

test('caduca en 3 días: avisa', () => {
  assert.equal(expiringSoon([item(3)], NOW), true);
});

test('caduca en 4 días: no avisa', () => {
  assert.equal(expiringSoon([item(4)], NOW), false);
});

test('caduca hoy: avisa', () => {
  assert.equal(expiringSoon([item(0)], NOW), true);
});

test('caducó ayer: no avisa', () => {
  assert.equal(expiringSoon([item(-1)], NOW), false);
});

test('sin cantidad: no avisa', () => {
  assert.equal(expiringSoon([item(2, { quantity: 0 })], NOW), false);
});

test('cuenta desde el día de Guadalajara en que se recibió', () => {
  // 23:30 del 6 de marzo en Guadalajara (05:30 UTC del 7). Con 7 días caduca
  // el 13: en 3 días. Contando el día UTC serían 4 y no avisaría.
  const late = item(7, { localTimestamp: new Date('2026-03-07T05:30:00Z') });
  assert.equal(expiringSoon([late], NOW), true);
});