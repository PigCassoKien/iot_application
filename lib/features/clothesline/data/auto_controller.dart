import 'dart:async';

import '../domain/predictor.dart';
import 'config.dart';
import 'firebase_service.dart';

/// AutoController listens to sensor updates and when in AUTO mode
/// it decides whether to change the clothesline position and writes
/// control commands + a notification entry.
class AutoController {
  static final AutoController _instance = AutoController._internal();
  factory AutoController() => _instance;
  AutoController._internal();

  final FirebaseService _fb = FirebaseService();
  StreamSubscription? _sub;
  StreamSubscription? _configSub;
  Config _config = const Config();

  void start() {
    // Prevent multiple starts
    if (_sub != null) return;
    // Listen to runtime config
    _configSub = _fb.configStream.listen((event) {
      final snapshot = event.snapshot;
      final data = snapshot.value;
      if (data != null && data is Map<Object?, Object?>) {
        _config = Config.fromMap(data);
      }
    });

    _sub = _fb.statusStream.listen((event) {
      final snapshot = event.snapshot;
      final data = snapshot.value;

      if (data == null || data is! Map<Object?, Object?>) return;
      final map = data;

      final mode = (map['mode'] as String?) ?? 'AUTO';
      final position = (map['position'] as String?) ?? 'IN';
      final isRaining = (map['rain'] as bool?) ?? false;
      final light = (map['light'] as num?)?.toInt() ?? 0;
      final temperature = (map['temperature'] as num?)?.toDouble() ?? 0.0;
      final humidity = (map['humidity'] as num?)?.toDouble() ?? 0.0;
      final wind = (map['wind'] as num?)?.toDouble() ?? 0.0;

      if (mode != 'AUTO') return;

      final decision = Predictor.decide(
        isRaining: isRaining,
        lightLux: light,
        temperatureC: temperature,
        humidityPercent: humidity,
        windMps: wind,
        minLightOut: _config.minLightOut,
        darkThreshold: _config.darkThreshold,
        maxWindForOut: _config.maxWindForOut,
        strongWindForIn: _config.strongWindForIn,
        humidityThreshold: _config.humidityThreshold,
        tempLowThreshold: _config.tempLowThreshold,
      );
      if (decision == null) return; // no change recommended

      if (decision != position) {
        // Push a reliable command into the command queue so the device can
        // acknowledge execution. This is preferred over directly writing
        // `control/position` because it supports ack/retry.
        final cmd = {
          'type': 'SET_POSITION',
          'position': decision,
          'source': 'auto',
        };
        _fb.pushControlCommand(cmd).then((cmdId) {
          // Optionally log cmdId somewhere or attach to notification payload
        }).catchError((e) {
          // If pushing command fails, fallback to direct setPosition
          _fb.setPosition(decision);
        });

        // write a notification entry for backend or other clients
        final title = 'Giàn phơi đang được ${decision == 'OUT' ? 'kéo ra' : 'kéo vào'}';
        final body = 'Tự động: hệ thống đã quyết định ${decision == 'OUT' ? 'kéo ra phơi' : 'kéo vào nhà'}.';
        _fb.sendNotification(title, body);
      }
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _configSub?.cancel();
    _configSub = null;
  }
}
