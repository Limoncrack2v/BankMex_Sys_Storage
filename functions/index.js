// Cloud Functions de BAMX Guadalajara.
//
// Según el data model, ningún cliente (ni el staff) crea documentos en
// families/{familyId}/pantryItems: firestore.rules lo prohíbe y solo esta
// función los crea, con el Admin SDK, cuando una entrega queda confirmada.
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { logger } = require('firebase-functions');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');

const { pantryItemsFor, pantryItemId } = require('./pantry');

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
 * En una transacción: crea los PantryItem de la entrega (los que no han
 * caducado en [deliveredAt]) y marca la entrega con pantryStockedAt. Si la
 * entrega ya tenía la marca no hace nada, así que un reintento o un segundo
 * evento no duplica productos. Regresa cuántos agregó y omitió, o null si no
 * hizo nada.
 */
async function stockDelivery(deliveryRef, deliveredAt) {
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

    const { items, expired, invalid } = pantryItemsFor(delivery, snapshot.id, deliveredAt);
    if (invalid.length) {
      logger.error('Productos inválidos omitidos', { deliveryId: snapshot.id, invalid });
    }

    const pantry = familyRef.collection('pantryItems');
    for (const { index, data } of items) {
      tx.create(pantry.doc(pantryItemId(snapshot.id, index)), data);
    }
    tx.update(deliveryRef, {
      pantryStockedAt: deliveredAt,
      pantryItemsAdded: items.length,
      pantryItemsSkipped: expired + invalid.length,
    });

    return { added: items.length, expired, invalid: invalid.length };
  });
}
