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
    await _db.child("control/position").set(value);
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
    // Also write a small audit entry under control/commands for history
    final ref = _db.child('control/commands').push();
    await ref.set({
      'type': 'SET_HAS_CLOTHES',
      'value': has,
      'source': 'app',
      'timestamp': ServerValue.timestamp,
      'status': 'done',
    });
  }

  /// Set the numeric `control/stepper` value (1 or -1). Also create a
  /// command record under `/control/commands` so devices can pick it up.
  Future<void> pushStepperCommand(int step) async {
    // write the direct control value (device can watch this node)
    await _db.child('control/stepper').set(step);

    // also push a command entry for history and for simulators/devices to consume
    final ref = _db.child('control/commands').push();
    final payload = {
      'type': 'STEPPER',
      'step': step,
      'source': 'app',
      'timestamp': ServerValue.timestamp,
      'status': 'pending',
    };
    await ref.set(payload);
  }

  /// Reminders: stream of `/reminders` node (useful for UI list)
  Stream get remindersStream => _db.child('reminders').orderByChild('when').onValue;

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

  /// Pushes a control command into `/control/commands` and returns the
  /// generated command id. The command should contain at least:
  /// { 'type': 'SET_POSITION', 'position': 'IN'|'OUT', 'source': 'app'|'auto', ... }
  Future<String> pushControlCommand(Map<String, dynamic> cmd) async {
    final ref = _db.child('control/commands').push();
    final payload = Map<String, dynamic>.from(cmd);
    payload['timestamp'] = ServerValue.timestamp;
    payload['status'] = 'pending';
    await ref.set(payload);
    return ref.key ?? '';
  }

  /// Helper to update a command's status/result.
  Future<void> updateCommandStatus(String cmdId, Map<String, dynamic> update) async {
    await _db.child('control/commands').child(cmdId).update(update);
  }
}