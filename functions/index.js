const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

// Trigger when a notification is written to /notifications/pending
exports.sendPendingNotification = functions.database
  .ref('/notifications/pending/{pushId}')
  .onCreate(async (snap, context) => {
    const data = snap.val();
    if (!data) return null;

    const title = data.title || 'Thông báo từ hệ thống';
    const body = data.body || '';

    // read device tokens
    const tokensSnap = await admin.database().ref('/device_tokens').once('value');
    const tokensRaw = tokensSnap.val() || {};
    const tokens = Object.keys(tokensRaw).map(k => tokensRaw[k].token).filter(Boolean);

    if (!tokens.length) {
      await snap.ref.update({ delivered: false, reason: 'no_tokens' });
      return null;
    }

    const message = {
      notification: {
        title: title,
        body: body,
      },
      tokens: tokens,
    };

    try {
      const resp = await admin.messaging().sendMulticast(message);
      await snap.ref.update({ delivered: true, results: resp });
      // optionally cleanup invalid tokens
      const failures = resp.responses
        .map((r, i) => ({ ok: r.successful, index: i }))
        .filter(r => !r.ok)
        .map(r => tokens[r.index]);
      if (failures.length) {
        console.log('Failed tokens:', failures);
      }
    } catch (err) {
      console.error('FCM send error', err);
      await snap.ref.update({ delivered: false, reason: String(err) });
    }

    return null;
  });
