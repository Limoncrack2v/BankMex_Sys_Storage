// Manda un push a los teléfonos de una cuenta y borra sus tokens muertos.
// Recibe db y messaging en vez de importarlos, como next_delivery_sync.js;
// index.js los conecta.

const { buildMessage, staleTokens } = require('./push');

/**
 * @returns {Promise<{sent: number, removed: number}>}
 */
async function sendToUser(db, messaging, uid, body) {
  const devices = db.collection('users').doc(uid).collection('deviceTokens');
  const snapshot = await devices.get();
  if (snapshot.empty) return { sent: 0, removed: 0 };

  // El id del documento es el token (firestore.rules: validDeviceToken).
  const tokens = snapshot.docs.map((doc) => doc.id);
  const response = await messaging.sendEachForMulticast(buildMessage(tokens, body));
  const stale = staleTokens(tokens, response);
  await Promise.all(stale.map((token) => devices.doc(token).delete()));
  return { sent: response.successCount, removed: stale.length };
}

module.exports = { sendToUser };
