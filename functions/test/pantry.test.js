// Pruebas de pantry.js (sin emuladores): node --test test/pantry.test.js
const assert = require('node:assert/strict');
const { describe, test } = require('node:test');

const { DEVICE_ID, calendarDay, invalidReason, pantryItemsFor, pantryItemId } = require('../pantry');

// Guadalajara está en UTC-6 todo el año (sin horario de verano desde 2022).
const gdl = (iso) => new Date(`${iso}-06:00`);
const item = (extra = {}) => ({
  productId: 'Arroz',
  type: 'grain',
  quantity: 2,
  unit: 'kg',
  expirationDate: gdl('2026-09-26T00:00:00'),
  ...extra,
});
// Como lo regresa el Admin SDK: un Timestamp con toDate().
const timestamp = (date) => ({ toDate: () => date });

describe('calendarDay', () => {
  test('usa el día de Guadalajara, no el de UTC', () => {
    // 23:30 del 21 en Guadalajara ya es el 22 en UTC.
    assert.equal(calendarDay(gdl('2026-09-21T23:30:00')), calendarDay(gdl('2026-09-21T00:00:00')));
    assert.equal(calendarDay(gdl('2026-09-22T00:00:00')) - calendarDay(gdl('2026-09-21T23:59:59')), 1);
  });

  test('cuenta días de calendario a través de fin de mes y de año', () => {
    assert.equal(calendarDay(gdl('2026-10-01T08:00:00')) - calendarDay(gdl('2026-09-30T20:00:00')), 1);
    assert.equal(calendarDay(gdl('2027-01-01T01:00:00')) - calendarDay(gdl('2026-12-31T23:00:00')), 1);
  });
});

describe('pantryItemsFor', () => {
  const deliveredAt = gdl('2026-09-21T10:00:00');

  test('arma el PantryItem con los mismos campos que PantryItem.toFirestore', () => {
    const { items, expired, invalid } = pantryItemsFor(
      { items: [item({ productId: '  Arroz  ', expirationDate: timestamp(gdl('2026-09-26T00:00:00')) })] },
      'entrega-1',
      deliveredAt,
    );

    assert.equal(expired, 0);
    assert.deepEqual(invalid, []);
    assert.deepEqual(items, [
      {
        index: 0,
        data: {
          productId: 'Arroz',
          deliveryId: 'entrega-1',
          type: 'grain',
          quantity: 2,
          unit: 'kg',
          daysUntilExpiration: 5,
          synchronized: true,
          deviceId: DEVICE_ID,
          localTimestamp: deliveredAt,
        },
      },
    ]);
  });

  test('el día de caducidad todavía entra (0 días); el día siguiente ya no', () => {
    const sameDay = pantryItemsFor({ items: [item({ expirationDate: gdl('2026-09-21T00:00:00') })] }, 'e', deliveredAt);
    assert.equal(sameDay.items[0].data.daysUntilExpiration, 0);

    const lateNight = pantryItemsFor(
      { items: [item({ expirationDate: gdl('2026-09-21T00:00:00') })] },
      'e',
      gdl('2026-09-21T23:45:00'),
    );
    assert.equal(lateNight.items.length, 1);

    const nextDay = pantryItemsFor(
      { items: [item({ expirationDate: gdl('2026-09-21T00:00:00') })] },
      'e',
      gdl('2026-09-22T00:05:00'),
    );
    assert.equal(nextDay.items.length, 0);
    assert.equal(nextDay.expired, 1);
  });

  test('omite los caducados y conserva la posición de los demás', () => {
    const { items, expired } = pantryItemsFor(
      {
        items: [
          item({ productId: 'Leche', expirationDate: gdl('2026-09-20T00:00:00') }),
          item({ productId: 'Frijol', expirationDate: gdl('2026-10-21T00:00:00') }),
        ],
      },
      'e',
      deliveredAt,
    );
    assert.equal(expired, 1);
    assert.deepEqual(items.map(({ index, data }) => [index, data.productId, data.daysUntilExpiration]), [
      [1, 'Frijol', 30],
    ]);
  });

  test('omite productos inválidos en vez de crear documentos que la app no puede leer', () => {
    const { items, invalid } = pantryItemsFor(
      {
        items: [
          item({ type: 'candy' }),
          item({ unit: 'box' }),
          item({ quantity: 0 }),
          item({ quantity: '2' }),
          item({ productId: '   ' }),
          item({ expirationDate: 'mañana' }),
          null,
          item(),
        ],
      },
      'e',
      deliveredAt,
    );
    assert.deepEqual(invalid.map(({ index }) => index), [0, 1, 2, 3, 4, 5, 6]);
    assert.deepEqual(items.map(({ index }) => index), [7]);
  });

  test('una entrega sin lista de productos no agrega nada', () => {
    assert.deepEqual(pantryItemsFor({}, 'e', deliveredAt), { items: [], expired: 0, invalid: [] });
  });
});

describe('invalidReason', () => {
  test('acepta los tipos y unidades de la app', () => {
    for (const type of ['grain', 'legume', 'canned', 'dairy', 'produce', 'protein', 'beverage', 'other']) {
      assert.equal(invalidReason(item({ type })), null);
    }
    for (const unit of ['kg', 'g', 'l', 'ml', 'piece', 'can', 'pack']) {
      assert.equal(invalidReason(item({ unit })), null);
    }
  });

  test('respeta los límites de nombre y cantidad del modelo', () => {
    assert.equal(invalidReason(item({ productId: 'a'.repeat(100) })), null);
    assert.notEqual(invalidReason(item({ productId: 'a'.repeat(101) })), null);
    assert.equal(invalidReason(item({ quantity: 1000000 })), null);
    assert.notEqual(invalidReason(item({ quantity: 1000001 })), null);
    assert.notEqual(invalidReason(item({ quantity: Number.NaN })), null);
  });
});

describe('pantryItemId', () => {
  test('es fijo por entrega y producto', () => {
    assert.equal(pantryItemId('abc', 0), 'abc-1');
    assert.equal(pantryItemId('abc', 9), 'abc-10');
  });
});
