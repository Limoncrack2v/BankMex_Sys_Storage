// Convierte los productos de una entrega en documentos de
// families/{familyId}/pantryItems. Sin dependencias de Firebase para poder
// probarlo con node --test (test/pantry.test.js).

// Las fechas de caducidad se capturan en Guadalajara: los días se cuentan
// con el calendario de esa zona, igual que en la app.
const TIME_ZONE = 'America/Mexico_City';
const DAY_MS = 24 * 60 * 60 * 1000;

// deviceId de las entregas sin un deviceId válido (fallback).
const DEVICE_ID = 'cloud-function';

// Mismos valores que FoodType, FoodUnit y PantryItem.maxQuantity de
// lib/data/models/pantry_item.dart y DeliveryItem.maxNameLength.
const FOOD_TYPES = ['grain', 'legume', 'canned', 'dairy', 'produce', 'protein', 'beverage', 'other'];
const FOOD_UNITS = ['kg', 'g', 'l', 'ml', 'piece', 'can', 'pack'];
const MAX_QUANTITY = 1000000;
const MAX_NAME_LENGTH = 100;

const dayParts = new Intl.DateTimeFormat('en-US', {
  timeZone: TIME_ZONE,
  year: 'numeric',
  month: 'numeric',
  day: 'numeric',
});

/** Día de calendario de [date] en Guadalajara, en días desde 1970-01-01. */
function calendarDay(date) {
  const parts = Object.fromEntries(
    dayParts.formatToParts(date).map(({ type, value }) => [type, value]),
  );
  return Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day)) / DAY_MS;
}

/** Acepta un Timestamp de Firestore o un Date; null si no es fecha. */
function toDate(value) {
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (value && typeof value.toDate === 'function') return value.toDate();
  return null;
}

// Límites para creerle al reloj del dispositivo del staff (localTimestamp).
const MAX_HANDOVER_LAG_MS = 7 * DAY_MS;

// Igual que el margen de validTrace en firestore.rules.
const MAX_CLOCK_AHEAD_MS = 5 * 60 * 1000;

/**
 * Cuándo recibió la familia la entrega: la hora del dispositivo del staff al
 * marcarla (localTimestamp) si es creíble; si falta o no es creíble, la hora
 * del servidor [serverTime].
 */
function handoverTime(delivery, serverTime) {
  const local = toDate(delivery.localTimestamp);

  if (local === null) return serverTime;

  const lag = serverTime.getTime() - local.getTime();

  if (lag > MAX_HANDOVER_LAG_MS || lag < -MAX_CLOCK_AHEAD_MS) return serverTime;

  return local;
}

/** Motivo por el que un producto de la entrega no es válido, o null. */
function invalidReason(item) {
  if (!item || typeof item !== 'object') return 'no es un objeto';
  const name = typeof item.productId === 'string' ? item.productId.trim() : '';
  if (!name || name.length > MAX_NAME_LENGTH) return 'productId inválido';
  if (!FOOD_TYPES.includes(item.type)) return `type inválido (${item.type})`;
  if (!FOOD_UNITS.includes(item.unit)) return `unit inválida (${item.unit})`;
  const { quantity } = item;
  if (typeof quantity !== 'number' || !Number.isFinite(quantity) || quantity <= 0 || quantity > MAX_QUANTITY) {
    return `quantity inválida (${quantity})`;
  }
  if (!toDate(item.expirationDate)) return 'expirationDate inválida';
  return null;
}

/**
 * Productos de [delivery] que entran a la despensa si se entregó en
 * [deliveredAt]. Los que ya caducaron ese día (el día de caducidad todavía
 * cuenta) y los inválidos se omiten.
 *
 * Regresa { items: [{ index, data }], expired, invalid }. index es la
 * posición del producto en delivery.items; data es el documento del
 * PantryItem (mismos campos que PantryItem.toFirestore).
 */
function pantryItemsFor(delivery, deliveryId, deliveredAt) {
  const deliveredDay = calendarDay(deliveredAt);
  const items = [];
  let expired = 0;
  const invalid = [];

  const source = Array.isArray(delivery.items) ? delivery.items : [];
  const deviceId = 
    typeof delivery.deviceId === 'string' && delivery.deviceId ? delivery.deviceId : DEVICE_ID;
  source.forEach((item, index) => {
    const reason = invalidReason(item);
    if (reason) {
      invalid.push({ index, reason });
      return;
    }
    const days = calendarDay(toDate(item.expirationDate)) - deliveredDay;
    if (days < 0) {
      expired++;
      return;
    }
    items.push({
      index,
      data: {
        productId: item.productId.trim(),
        deliveryId,
        type: item.type,
        quantity: item.quantity,
        unit: item.unit,
        daysUntilExpiration: days,
        deviceId: deviceId,
        localTimestamp: deliveredAt,
      },
    });
  });

  return { items, expired, invalid };
}

/**
 * Id fijo del PantryItem que sale del producto [index] de la entrega: si la
 * función corriera dos veces, el segundo create fallaría en vez de duplicar.
 */
function pantryItemId(deliveryId, index) {
  return `${deliveryId}-${index + 1}`;
}

module.exports = {
  DEVICE_ID,
  TIME_ZONE,
  calendarDay,
  invalidReason,
  pantryItemsFor,
  pantryItemId,
  handoverTime,
};
