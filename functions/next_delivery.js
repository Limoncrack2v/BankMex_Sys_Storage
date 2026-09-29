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

module.exports = { nextDeliveryDate };
