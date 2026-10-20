// Alerta diaria de caducidad. expiringSoon no usa Firebase; sendExpiryAlerts
// lee Firestore y recibe cómo enviar, así se prueba sin FCM.

const { logger } = require('firebase-functions');

const { calendarDay, toDate } = require('./pantry');

// El mismo umbral que "Urgente" en la app (expiration_urgency.dart).
const ALERT_DAYS = 3;

/**
 * true si algún producto con cantidad caduca de hoy a [days] días (días de
 * calendario en Guadalajara). Lo ya caducado no cuenta: la alerta es para lo
 * que todavía se puede usar.
 * @param {Array<{quantity: number, localTimestamp: any, daysUntilExpiration: number}>} items
 * @param {Date} now
 */
function expiringSoon(items, now, days = ALERT_DAYS) {
  const today = calendarDay(now);
  return items.some((item) => {
    const received = toDate(item.localTimestamp);
    if (!received || !(item.quantity > 0) || !Number.isFinite(item.daysUntilExpiration)) {
      return false;
    }
    const left = calendarDay(received) + item.daysUntilExpiration - today;
    return left >= 0 && left <= days;
  });
}

/**
 * Llama a [send] con cada cuenta que tiene tokens y algo por caducar en su
 * despensa. Una familia que falla no detiene a las demás.
 * @param {(uid: string) => Promise<unknown>} send
 * @returns {Promise<{scanned: number, alerted: number, failed: number}>}
 */
async function sendExpiryAlerts(db, now, send) {
  const tokens = await db.collectionGroup('deviceTokens').get();
  // users/{uid}/deviceTokens/{token}: el uid de una familia es su familyId.
  const uids = [...new Set(tokens.docs.map((doc) => doc.ref.parent.parent.id))];
  const result = { scanned: uids.length, alerted: 0, failed: 0 };

  // shortcut: una familia a la vez; con miles, en lotes como
  // recomputeStaleNextDeliveries.
  for (const uid of uids) {
    try {
      const pantry = await db.collection('families').doc(uid).collection('pantryItems').get();
      if (!expiringSoon(pantry.docs.map((doc) => doc.data()), now)) continue;
      await send(uid);
      result.alerted += 1;
    } catch (error) {
      result.failed += 1;
      logger.error('No se pudo enviar la alerta de caducidad', {
        familyId: uid,
        error: error?.message ?? String(error),
      });
    }
  }
  return result;
}

module.exports = { ALERT_DAYS, expiringSoon, sendExpiryAlerts };
