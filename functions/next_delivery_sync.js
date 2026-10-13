// Escribe families/{familyId}.nextDeliveryDate. Recibe la base de datos (db)
// en vez de importarla para poder probarlo con node --test contra el emulador
// (test/emulator/); index.js solo lo conecta con los triggers.

const { FieldValue } = require('firebase-admin/firestore');
const { logger } = require('firebase-functions');

const { nextDeliveryDate, startOfDay } = require('./next_delivery');

// Familias que se piden a Firestore por página y familias que se recalculan a
// la vez. Cada recálculo es una transacción de dos lecturas y una escritura.
const PAGE_SIZE = 200;
const CONCURRENCY = 10;

/**
 * Deja en la familia la próxima entrega programada de hoy en adelante, o
 * borra el campo si no hay; no hace nada si la familia no existe.
 *
 * Va en una transacción: lee la familia y sus entregas programadas y escribe
 * con lo que leyó. Si otra escritura de esas entregas (o de la familia) se
 * cruza, Firestore reintenta la transacción con datos nuevos; así, dos
 * recálculos de la misma familia, el del trigger syncNextDelivery y el diario,
 * no pueden dejar un valor calculado con entregas viejas encima de uno más
 * nuevo.
 * @returns {Promise<boolean>} si la familia existía y se escribió
 */
async function refreshNextDelivery(db, familyId, now = new Date()) {
  return db.runTransaction(async (tx) => {
    const familyRef = db.collection('families').doc(familyId);
    if (!(await tx.get(familyRef)).exists) return false;

    const deliveries = await tx.get(
      db.collection('deliveries')
        .where('familyId', '==', familyId)
        .where('status', '==', 'scheduled'),
    );
    const nextDate = nextDeliveryDate(deliveries.docs.map((doc) => doc.data()), now);

    tx.update(familyRef, { nextDeliveryDate: nextDate ?? FieldValue.delete() });
    return true;
  });
}

/**
 * Recalcula nextDeliveryDate de las familias que lo tienen antes de hoy
 * (días en Guadalajara): una entrega programada cuyo día pasó sin marcarse
 * como entregada ni cancelada no vuelve a disparar syncNextDelivery, y la
 * familia se quedaba con esa fecha. La consulta trae solo esas familias; el
 * resto no se lee. Después del recálculo la familia tiene una fecha de hoy en
 * adelante o ninguna, así que deja de salir en la consulta y correrlo dos
 * veces seguidas no cambia nada la segunda vez.
 *
 * Una familia que falla no detiene a las demás: se cuenta en failed y la
 * siguiente corrida la vuelve a intentar.
 * @returns {Promise<{scanned: number, updated: number, failed: number}>}
 */
async function recomputeStaleNextDeliveries(
  db,
  now = new Date(),
  { pageSize = PAGE_SIZE, concurrency = CONCURRENCY } = {},
) {
  const startOfToday = startOfDay(now);
  const result = { scanned: 0, updated: 0, failed: 0 };

  // Se pagina con un cursor y no volviendo a consultar hasta que no salga
  // nada: una familia que falla siempre seguiría saliendo y nunca terminaría.
  let cursor;
  for (;;) {
    let query = db.collection('families')
      .where('nextDeliveryDate', '<', startOfToday)
      .orderBy('nextDeliveryDate')
      .select('nextDeliveryDate')
      .limit(pageSize);
    if (cursor) query = query.startAfter(cursor);

    const page = await query.get();
    result.scanned += page.size;

    for (let i = 0; i < page.docs.length; i += concurrency) {
      const outcomes = await Promise.allSettled(
        page.docs.slice(i, i + concurrency).map((doc) => refreshNextDelivery(db, doc.id, now)),
      );
      outcomes.forEach((outcome, offset) => {
        if (outcome.status === 'fulfilled') {
          if (outcome.value) result.updated += 1;
          return;
        }
        result.failed += 1;
        logger.error('No se pudo recalcular nextDeliveryDate', {
          familyId: page.docs[i + offset].id,
          error: outcome.reason?.message ?? String(outcome.reason),
        });
      });
    }

    if (page.size < pageSize) return result;
    cursor = page.docs[page.docs.length - 1];
  }
}

module.exports = { refreshNextDelivery, recomputeStaleNextDeliveries };
