// Cloud Functions de BAMX Guadalajara.
//
// Según el data model, ningún cliente (ni el staff) crea documentos en
// families/{familyId}/pantryItems: firestore.rules lo prohíbe y solo esta
// función los crea, con el Admin SDK, cuando una entrega queda confirmada.
const { initializeApp } = require('firebase-admin/app');
const { FieldValue, getFirestore } = require('firebase-admin/firestore');
const { logger } = require('firebase-functions');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');

const { pantryItemsFor, pantryItemId, handoverTime } = require('./pantry');
const { nextDeliveryDate } = require('./next_delivery');

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
    // Los triggers de Firestore deben estar en la región de la base de datos.
    region: 'northamerica-south1',
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
 */
exports.syncNextDelivery = onDocumentWritten(
  {
    document: 'deliveries/{deliveryId}',
    region: 'northamerica-south1',
  },
  async (event) => {
    const beforeSnapshot = event.data?.before;
    const afterSnapshot = event.data?.after;

    const before = beforeSnapshot?.exists ? beforeSnapshot.data() : undefined;
    const after = afterSnapshot?.exists ? afterSnapshot.data() : undefined;

    if (before && after &&
      before.familyId === after.familyId &&
      before.status === after.status &&
      before.deliveryDate.isEqual(after.deliveryDate))
      return;

    const familyIds = new Set([before?.familyId, after?.familyId].filter(Boolean));

    for (const familyId of familyIds)
      await refreshNextDelivery(familyId);
  },
);

async function refreshNextDelivery(familyId) {
  const deliveries = await db.collection('deliveries')
    .where('familyId', '==', familyId)
    .where('status', '==', 'scheduled')
    .get();

  const deliveryDates = deliveries.docs.map((doc) => doc.data());
  const nextDate = nextDeliveryDate(deliveryDates, new Date());

  const familyRef = db.collection('families').doc(familyId);

  if (!(await familyRef.get()).exists) return;

  await familyRef.update({ nextDeliveryDate: nextDate ?? FieldValue.delete() });
}
