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
      final map = _fb.snapshotToMap(snapshot);
      if (map != null) {
        _config = Config.fromMap(map);
      }
    });


    _sub = _fb.statusStream.listen((event) {
      final snapshot = event.snapshot;
      final map = _fb.snapshotToMap(snapshot);
      if (map == null) return;

      // Robust readers to accept nested sensor.* or alternate key names
      num? _readNum(Map<String, dynamic> m, List<String> keys) {
        for (final k in keys) {
          if (k.contains('.')) {
            final parts = k.split('.');
            var cur = m;
            dynamic val;
            for (var i = 0; i < parts.length; i++) {
              final p = parts[i];
              if (cur[p] is Map) {
                cur = Map<String, dynamic>.from(cur[p]);
                continue;
              } else {
                val = cur[p];
                break;
              }
            }
            if (val is num) return val;
            if (val is String) return num.tryParse(val);
          } else {
            final val = m[k];
            if (val is num) return val;
            if (val is String) return num.tryParse(val);
          }
        }
        return null;
      }

      final mode = (map['mode'] as String?) ?? 'AUTO';
      final position = (map['position'] as String?) ?? 'IN';
      final rainVal = map['rain'] ?? map['isRaining'] ?? (map['sensor'] is Map ? map['sensor']['rain'] : null);
      final isRaining = (rainVal == true) || (rainVal is String && (rainVal == 'true' || rainVal == '1')) || (rainVal is num && rainVal != 0);
      final light = _readNum(map, ['light', 'sensor.light', 'lux'])?.toInt() ?? 0;
      final temperature = _readNum(map, ['temperature', 'temp', 'sensor.temperature', 'sensor.temp'])?.toDouble() ?? 0.0;
      final humidity = _readNum(map, ['humidity', 'sensor.humidity', 'sensor.hum'])?.toDouble() ?? 0.0;
      final wind = _readNum(map, ['wind', 'sensor.wind'])?.toDouble() ?? 0.0;

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
        // Optimistically update the position in DB so UI and other clients reflect the change.
        // Fire-and-forget write; catch async errors to avoid unhandled futures
        _fb.setPosition(decision).catchError((_) {});
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
          // If pushing command fails, ensure position is written
          _fb.setPosition(decision).catchError((_) {});
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
