// Pruebas de startOfDay y su relación con nextDeliveryDate. No necesitan
// emuladores: npm test --prefix functions
const test = require('node:test');
const assert = require('node:assert/strict');

const { nextDeliveryDate, startOfDay } = require('../next_delivery');
const { calendarDay } = require('../pantry');

// Guadalajara está en UTC-6 todo el año desde 2022 (ya no hay horario de
// verano), así que su medianoche es 06:00 UTC.
const iso = (text) => new Date(text);

test('startOfDay: a media mañana es la medianoche de ese día en Guadalajara', () => {
  assert.deepEqual(startOfDay(iso('2026-01-15T15:30:00Z')), iso('2026-01-15T06:00:00Z'));
});

test('startOfDay: en verano también es 06:00 UTC', () => {
  assert.deepEqual(startOfDay(iso('2026-07-15T20:00:00Z')), iso('2026-07-15T06:00:00Z'));
});

test('startOfDay: justo a la medianoche es esa misma medianoche', () => {
  assert.deepEqual(startOfDay(iso('2026-01-15T06:00:00.000Z')), iso('2026-01-15T06:00:00Z'));
});

test('startOfDay: un milisegundo antes de la medianoche sigue en el día anterior', () => {
  assert.deepEqual(startOfDay(iso('2026-01-15T05:59:59.999Z')), iso('2026-01-14T06:00:00Z'));
});

test('startOfDay: usa el día de Guadalajara y no el de UTC', () => {
  // 02:00 UTC del 15 todavía es 20:00 del 14 en Guadalajara.
  assert.deepEqual(startOfDay(iso('2026-01-15T02:00:00Z')), iso('2026-01-14T06:00:00Z'));
});

test('startOfDay: una fecha es anterior a hoy si y solo si es menor que él', () => {
  const now = iso('2026-03-10T18:00:00Z');
  const start = startOfDay(now);
  const before = (date) => date < start;
  const stale = (date) => calendarDay(date) < calendarDay(now);

  const dates = [
    '2026-03-09T00:00:00Z',
    '2026-03-09T18:00:00Z',
    '2026-03-10T05:59:59.999Z', // 23:59:59.999 de ayer
    '2026-03-10T06:00:00.000Z', // medianoche de hoy
    '2026-03-10T06:00:00.001Z',
    '2026-03-10T07:00:00Z', // 01:00 de hoy
    '2026-03-10T18:00:00Z', // ahora
    '2026-03-11T05:59:59.999Z', // 23:59:59.999 de hoy
    '2026-03-11T06:00:00Z', // medianoche de mañana
  ].map(iso);
  for (const date of dates) {
    assert.equal(before(date), stale(date), date.toISOString());
  }
  assert.deepEqual(dates.map(before), [
    true, true, true, false, false, false, false, false, false,
  ]);
});

test('startOfDay: coincide con calendarDay también en días de 23 y 25 horas', () => {
  // Hasta 2022 Guadalajara tenía horario de verano. startOfDay busca con
  // calendarDay, así que sigue siendo exacto en esos días.
  const instants = [
    '2022-04-03T12:00:00Z', // día que se adelantó la hora (23 horas)
    '2022-10-30T20:00:00Z', // día que se atrasó la hora (25 horas)
    '2022-10-30T05:30:00Z',
  ].map(iso);
  for (const now of instants) {
    const start = startOfDay(now);
    assert.equal(calendarDay(start), calendarDay(now), now.toISOString());
    assert.ok(
      calendarDay(new Date(start.getTime() - 1)) < calendarDay(now),
      now.toISOString(),
    );
  }
});

test('nextDeliveryDate: una programada de hoy a las 00:00 todavía cuenta', () => {
  // La misma frontera que startOfDay: lo que no es anterior a hoy se queda.
  const now = iso('2026-03-10T18:00:00Z');
  const midnight = iso('2026-03-10T06:00:00Z');
  const justBefore = iso('2026-03-10T05:59:59.999Z');
  assert.deepEqual(
    nextDeliveryDate([{ status: 'scheduled', deliveryDate: midnight }], now),
    midnight,
  );
  assert.equal(
    nextDeliveryDate([{ status: 'scheduled', deliveryDate: justBefore }], now),
    null,
  );
});
