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

// Trigger when `/status` changes: create a pending notification so
// the existing `sendPendingNotification` function will forward it to FCM.
exports.onStatusChange = functions.database
  .ref('/status')
  .onWrite(async (change, context) => {
    const before = change.before.exists() ? change.before.val() : {};
    const after = change.after.exists() ? change.after.val() : {};

    // Determine if a meaningful notification should be emitted
    let title = 'Giàn phơi';
    let body = null;

    // Position changed
    if (before.position !== after.position) {
      if (after.position === 'OUT') {
        body = 'Giàn phơi đang kéo ra phơi.';
      } else if (after.position === 'IN') {
        body = 'Giàn phơi đã rút vào nhà.';
      }
    }

    // Rain started
    if (!before.rain && after.rain) {
      body = 'Trời bắt đầu mưa — giàn phơi đã rút vào trong.';
      title = 'Cảnh báo mưa';
    }

    // Optional: if rain stopped or other events, add more branches

    if (!body) {
      // nothing noteworthy to notify
      return null;
    }

    // Push a pending notification entry (Cloud Function `sendPendingNotification` will send it)
    try {
      const ref = admin.database().ref('/notifications/pending').push();
      await ref.set({
        title: title,
        body: body,
        timestamp: admin.database.ServerValue.TIMESTAMP,
        delivered: false,
        source: 'status-trigger'
      });
    } catch (err) {
      console.error('Failed to write pending notification:', err);
    }

    return null;
  });
