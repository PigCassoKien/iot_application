// lib/features/clothesline/data/firebase_service.dart
import 'package:firebase_database/firebase_database.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  // ĐÚNG: Không cần type cụ thể, để Stream<dynamic> ngầm định
  Stream get statusStream => _db.child("status").onValue;

  /// Stream of config changes at `/config`.
  Stream get configStream => _db.child('config').onValue;

  Future<void> setPosition(String value) async {
    // Deprecated: do not write `control/position` directly. Map a requested
    // position into a numeric stepper command (1 = OUT, 0 = IN) so devices
    // observe `/control/stepper` which they act upon. Also record a command
    // entry for history.
    final desired = (value.toUpperCase() == 'OUT') ? 1 : 0;
    await pushStepperCommand(desired);
    await pushControlCommand({'type': 'STEPPER', 'position': desired, 'source': 'app'});
  }

  Future<void> setMode(String value) async {
    await _db.child("control/mode").set(value);
  }

  /// Writes a notification record under `/notifications/pending/`.
  /// This can be consumed by a backend or cloud function to deliver
  /// platform push notifications (FCM). The app also writes this so
  /// other clients can display message history.
  Future<void> sendNotification(String title, String body) async {
    final ref = _db.child('notifications/pending').push();
    await ref.set({
      'title': title,
      'body': body,
      'timestamp': ServerValue.timestamp,
      'delivered': false,
    });
  }

  Future<void> registerDeviceToken(String token, {String? userId}) async {
    final id = userId ?? 'anonymous';
    await _db.child('device_tokens').child(id).set({
      'token': token,
      'ts': ServerValue.timestamp,
    });
  }

  /// Stream of the whole `control` node (includes `hasClothes`, `stepper`, etc.)
  Stream get controlStream => _db.child('control').onValue;

  /// Read the current `hasClothes` flag (defaults to false).
  Future<bool> getHasClothes() async {
    final snap = await _db.child('control/hasClothes').get();
    if (!snap.exists) return false;
    final v = snap.value;
    return v == true || v == 'true' || v == 1;
  }

  /// Set the `hasClothes` flag under `/control/hasClothes`.
  Future<void> setHasClothes(bool has) async {
    await _db.child('control/hasClothes').set(has);
    // Also write a small audit entry under /commands for history
    final ref = _db.child('commands').push();
    await ref.set({
      'type': 'SET_HAS_CLOTHES',
      'value': has,
      'source': 'app',
      'timestamp': ServerValue.timestamp,
      'status': 'done',
    });
  }

  /// Set the numeric `control/stepper` value (1 or -1). Also create a
  /// command record under `/commands` so devices can pick it up.
  Future<void> pushStepperCommand(int step) async {
    // write the direct control value (device can watch this node)
    await _db.child('control/stepper').set(step);

    // Only write the `control/stepper` value — the device will act and
    // update `/status/rackPosition` itself. Keep `/control` small.

    // also push a command entry for history and for simulators/devices to consume
    final ref = _db.child('commands').push();
    final payload = {
      'type': 'STEPPER',
      'step': step,
      'source': 'app',
      'timestamp': ServerValue.timestamp,
      'status': 'pending',
    };
    await ref.set(payload);
  }

  /// Ensure `/control/stepper` is set to 0 (idle). This is useful at
  /// app startup so devices see a neutral value until the user requests
  /// a movement (1 or -1). This does not create a `/commands` entry.
  Future<void> ensureStepperZero() async {
    await _db.child('control/stepper').set(0);
  }

  /// Reminders: stream of `/reminders` node (useful for UI list)
  Stream get remindersStream => _db.child('reminders').orderByChild('when').onValue;

  /// Stream of `/sensor` node (contains `humidity`, `temp` etc.)
  Stream get sensorStream => _db.child('sensor').onValue;

  /// One-time read of `/sensor` as a Map<String, dynamic>? (safe conversion).
  Future<Map<String, dynamic>?> getSensorOnce() async {
    final snap = await _db.child('sensor').get();
    return snapshotToMap(snap);
  }

  /// Add a reminder entry under `/reminders`.
  /// `when` should be a unix-millis timestamp or ISO string; we store as ServerValue if null.
  Future<String> addReminder({required String title, required int whenMillis, String? note}) async {
    final ref = _db.child('reminders').push();
    final payload = {
      'title': title,
      'when': whenMillis,
      'note': note ?? '',
      'createdAt': ServerValue.timestamp,
      'done': false,
    };
    await ref.set(payload);
    return ref.key ?? '';
  }

  /// Safely convert a [DataSnapshot] value to a Map<String, dynamic> if possible.
  /// Returns null when the snapshot is null or not a map.
  Map<String, dynamic>? snapshotToMap(DataSnapshot snap) {
    final v = snap.value;
    if (v == null) return null;
    if (v is Map) {
      final out = <String, dynamic>{};
      v.forEach((k, val) {
        out[k.toString()] = val;
      });
      return out;
    }
    return null;
  }

  /// One-time read of `/status` as a Map<String, dynamic>? (safe conversion).
  Future<Map<String, dynamic>?> getStatusOnce() async {
    final snap = await _db.child('status').get();
    return snapshotToMap(snap);
  }

  /// One-time read of `/control` as a Map<String, dynamic>? (safe conversion).
  Future<Map<String, dynamic>?> getControlOnce() async {
    final snap = await _db.child('control').get();
    return snapshotToMap(snap);
  }

  Future<String> pushControlCommand(Map<String, dynamic> cmd) async {
    final ref = _db.child('commands').push();
    final payload = Map<String, dynamic>.from(cmd);

    // Extract comment (if any) to avoid storing large free-text inside the
    // commands node which is frequently read by clients.
    final comment = payload.remove('comment');

    payload['timestamp'] = ServerValue.timestamp;
    payload['status'] = 'pending';

    await ref.set(payload);

    if (comment != null && comment is String && comment.trim().isNotEmpty) {
      await _db.child('comments').child(ref.key ?? '').set({
        'cmdId': ref.key,
        'text': comment,
        'source': payload['source'] ?? 'app',
        'timestamp': ServerValue.timestamp,
      });
    }

    return ref.key ?? '';
  }

  Future<void> updateCommandStatus(String cmdId, Map<String, dynamic> update) async {
    await _db.child('commands').child(cmdId).update(update);
  }
}