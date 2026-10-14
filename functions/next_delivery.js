// Próxima entrega programada de una familia. Sin dependencias de Firebase.

const { calendarDay, toDate } = require('./pantry');

/**
 * La entrega programada más próxima de hoy en adelante (días en calendario en tiempo de Guadalajara),
 * o null si no hay.
 * @param {Array<{status: string, deliveryDate: any}>} deliveries de una familia
 * @param {Date} now
 * @returns {Date|null}
 */
function nextDeliveryDate(deliveries, now) {
  const today = calendarDay(now);

  const deliveryDates = deliveries.filter((d) => d.status === 'scheduled')
    .map((d) => toDate(d.deliveryDate))
    .filter((date) => date !== null)
    .filter((date) => calendarDay(date) >= today);

  if (deliveryDates.length === 0) return null;

  return deliveryDates.reduce((a, b) => (b < a ? b : a));
}

/**
 * El primer instante del día de calendario de [now] en Guadalajara: una fecha
 * es anterior a hoy exactamente cuando es menor que este instante, o sea,
 * cuando calendarDay(fecha) < calendarDay(now), la misma cuenta de
 * nextDeliveryDate. Se busca con calendarDay (búsqueda binaria dentro de las
 * últimas 26 horas) en vez de restar la hora local, así no depende de que la
 * zona tenga o no horario de verano.
 * @param {Date} now
 * @returns {Date}
 */
function startOfDay(now) {
  const today = calendarDay(now);
  // Invariante: low cae en un día anterior a hoy y high ya es de hoy.
  let low = now.getTime() - 26 * 60 * 60 * 1000;
  let high = now.getTime();
  while (high - low > 1) {
    const middle = Math.floor((low + high) / 2);
    if (calendarDay(new Date(middle)) < today) low = middle;
    else high = middle;
  }
  return new Date(high);
}

module.exports = { nextDeliveryDate, startOfDay };
