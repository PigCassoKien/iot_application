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