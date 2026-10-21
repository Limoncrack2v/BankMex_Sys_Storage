// Cloud Functions de BAMX Guadalajara.
//
// Según el data model, ningún cliente (ni el staff) crea documentos en
// families/{familyId}/pantryItems: firestore.rules lo prohíbe y solo esta
// función los crea, con el Admin SDK, cuando una entrega queda confirmada.
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { logger } = require('firebase-functions');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');

const { pantryItemsFor, pantryItemId, handoverTime, TIME_ZONE } = require('./pantry');
const { refreshNextDelivery, recomputeStaleNextDeliveries } = require('./next_delivery_sync');
const { EXPIRY_BODY } = require('./push');
const { sendToUser } = require('./push_send');
const { sendExpiryAlerts } = require('./expiry_alert');

initializeApp();
const db = getFirestore();

// Con retry activado, un error que no se arregla solo se reintentaría
// durante días; después de este tiempo se deja de intentar.
const MAX_EVENT_AGE_MS = 24 * 60 * 60 * 1000;

/**
 * Cuando una entrega (deliveries/{deliveryId}) queda como entregada, ya sea
 * al registrarla así o al marcar una programada, agrega sus productos a la
 * despensa de la familia.
 */
exports.onDeliveryWritten = onDocumentWritten(
  {
    document: 'deliveries/{deliveryId}',
    // Cloud Functions no tiene northamerica-south1, la región de la base de
    // datos. El trigger sí queda ahí (firebase deploy le pone la región de
    // Firestore); la función corre en us-south1 (Dallas), la más cercana.
    region: 'us-south1',
    // Reintentar es seguro: stockDelivery no duplica productos.
    retry: true,
  },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    const delivery = after.data();
    // La escritura de pantryStockedAt vuelve a disparar la función; aquí se
    // detiene.
    if (delivery.status !== 'delivered' || delivery.pantryStockedAt) return;

    const age = Date.now() - Date.parse(event.time);
    if (age > MAX_EVENT_AGE_MS) {
      logger.error('Entrega sin agregar a la despensa: el evento es muy viejo para reintentarlo', {
        deliveryId: after.id,
        eventTime: event.time,
      });
      return;
    }

    const result = await stockDelivery(after.ref, new Date(event.time));
    if (result) logger.info('Productos agregados a la despensa', { deliveryId: after.id, ...result });
  },
);

/**
 * En una transacción: crea los PantryItem de la entrega que no habían
 * caducado a la hora de entrega y marca la entrega con pantryStockedAt. Si la
 * entrega ya tenía la marca, no hace nada; así, un reintento o un segundo
 * evento no duplica productos. Regresa cuántos agregó y omitió, o null si no
 * hizo nada.
 */
async function stockDelivery(deliveryRef, serverTime) {
  return db.runTransaction(async (tx) => {
    const snapshot = await tx.get(deliveryRef);
    if (!snapshot.exists) return null;
    const delivery = snapshot.data();
    if (delivery.status !== 'delivered' || delivery.pantryStockedAt) return null;

    if (typeof delivery.familyId !== 'string' || !delivery.familyId) {
      logger.error('Entrega sin familyId válido', { deliveryId: snapshot.id });
      return null;
    }
    const familyRef = db.collection('families').doc(delivery.familyId);
    const family = await tx.get(familyRef);
    if (!family.exists) {
      logger.error('La familia de la entrega ya no existe', {
        deliveryId: snapshot.id,
        familyId: delivery.familyId,
      });
      return null;
    }

    const receivedAt = handoverTime(delivery, serverTime);
    const { items, expired, invalid } = pantryItemsFor(delivery, snapshot.id, receivedAt);
    if (invalid.length) {
      logger.error('Productos inválidos omitidos', { deliveryId: snapshot.id, invalid });
    }

    const pantry = familyRef.collection('pantryItems');
    for (const { index, data } of items) {
      tx.create(pantry.doc(pantryItemId(snapshot.id, index)), data);
    }
    tx.update(deliveryRef, {
      pantryStockedAt: serverTime,
      pantryItemsAdded: items.length,
      pantryItemsSkipped: expired + invalid.length,
    });

    return { added: items.length, expired, invalid: invalid.length };
  });
}

/**
 * Mantiene families/{familyId}.nextDeliveryDate: la fecha de la próxima
 * entrega programada de la familia.
 * Si no hay, el campo se borra.
 * Las familias no pueden leer deliveries (tienen cuotas, justificaciones 
 * y notas del staff); por eso se copia solo la fecha.
 * Solo corre al escribir una entrega; si el día de una programada pasa sin
 * que se escriba, lo corrige recomputeStaleNextDelivery (abajo).
 */
exports.syncNextDelivery = onDocumentWritten(
  {
    document: 'deliveries/{deliveryId}',
    region: 'us-south1',
    retry: true,
  },
  async (event) => {
    const beforeSnapshot = event.data?.before;
    const afterSnapshot = event.data?.after;

    const before = beforeSnapshot?.exists ? beforeSnapshot.data() : undefined;
    const after = afterSnapshot?.exists ? afterSnapshot.data() : undefined;

    if (before && after &&
      before.familyId === after.familyId &&
      before.status === after.status &&
      before.deliveryDate?.isEqual?.(after.deliveryDate)) {
      return;
    }

    const familyIds = new Set([before?.familyId, after?.familyId].filter(Boolean));

    for (const familyId of familyIds) {
      await refreshNextDelivery(db, familyId);
    }
  },
);

/**
 * Todos los días a las 00:15 de Guadalajara recalcula nextDeliveryDate de las
 * familias que lo tienen antes de hoy: syncNextDelivery solo corre cuando se
 * escribe una entrega, así que si el día de una programada pasa sin marcarla
 * entregada ni cancelada, la familia se quedaba con esa fecha.
 *
 * Región: us-south1 (Dallas), como las de arriba. Cloud Scheduler tampoco
 * está en northamerica-south1, y firebase deploy crea el job de Scheduler en
 * la región de la función; us-south1 es la más cercana a Guadalajara.
 *
 * Reintentos: la función es idempotente (solo toca familias que siguen con
 * fecha pasada), así que reintentar es seguro. Si alguna familia falla se
 * lanza un error al final para que Scheduler reintente; el reintento solo
 * trabaja con las que quedaron pendientes. Termina antes de la corrida de
 * mañana: 3 reintentos con 1 a 10 minutos de espera.
 */
exports.recomputeStaleNextDelivery = onSchedule(
  {
    schedule: '15 0 * * *',
    timeZone: TIME_ZONE,
    region: 'us-south1',
    // Scheduler espera la respuesta hasta timeoutSeconds (mínimo 180 s).
    timeoutSeconds: 300,
    retryCount: 3,
    minBackoffSeconds: 60,
    maxBackoffSeconds: 600,
  },
  async () => {
    const result = await recomputeStaleNextDeliveries(db, new Date());
    logger.info('nextDeliveryDate recalculado', result);
    if (result.failed > 0) {
      throw new Error(`${result.failed} familias sin recalcular nextDeliveryDate`);
    }
  },
);

/**
 * Todos los días a las 9:00 de Guadalajara avisa a las familias que tienen
 * productos por caducar en los próximos 3 días: un push genérico por familia
 * ("Tienes productos por caducar"), sin nombres, fechas ni cantidades.
 *
 * Región: us-south1, como recomputeStaleNextDelivery (Cloud Scheduler no
 * existe en northamerica-south1).
 *
 * Sin reintentos: enviar no es idempotente y un reintento mandaría el mismo
 * push dos veces. Una familia que falla se cuenta en failed y se registra; la
 * corrida de mañana la vuelve a intentar.
 */
exports.expiryAlert = onSchedule(
  {
    schedule: '0 9 * * *',
    timeZone: TIME_ZONE,
    region: 'us-south1',
    timeoutSeconds: 300,
    retryCount: 0,
  },
  async () => {
    const messaging = getMessaging();
    const result = await sendExpiryAlerts(db, new Date(), (uid) =>
      sendToUser(db, messaging, uid, EXPIRY_BODY));
    logger.info('alertas de caducidad', result);
  },
);
