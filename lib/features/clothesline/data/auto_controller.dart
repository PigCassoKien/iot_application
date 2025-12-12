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
      num? readNum(Map<String, dynamic> m, List<String> keys) {
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
      // Prefer numeric rackPosition (device-reported) if present
      final rpRaw = map['rackPosition'] ?? map['rackposition'];
      String position;
      if (rpRaw != null) {
        if (rpRaw is num) {
          position = (rpRaw == 1) ? 'OUT' : (rpRaw == 0 ? 'IN' : 'IN');
        } else if (rpRaw is String) {
          final asNum = num.tryParse(rpRaw);
          if (asNum != null) position = (asNum == 1) ? 'OUT' : (asNum == 0 ? 'IN' : 'IN');
          else position = (rpRaw.toUpperCase() == 'OUT') ? 'OUT' : 'IN';
        } else {
          position = (map['position'] as String?) ?? 'IN';
        }
      } else {
        position = (map['position'] as String?) ?? 'IN';
      }
      final rainVal = map['rain'] ?? map['isRaining'] ?? (map['sensor'] is Map ? map['sensor']['rain'] : null);
      final isRaining = (rainVal == true) || (rainVal is String && (rainVal == 'true' || rainVal == '1')) || (rainVal is num && rainVal != 0);
      final light = readNum(map, ['light', 'sensor.light', 'lux'])?.toInt() ?? 0;
      final temperature = readNum(map, ['temperature', 'temp', 'sensor.temperature', 'sensor.temp'])?.toDouble() ?? 0.0;
      final humidity = readNum(map, ['humidity', 'sensor.humidity', 'sensor.hum'])?.toDouble() ?? 0.0;
      final wind = readNum(map, ['wind', 'sensor.wind'])?.toDouble() ?? 0.0;

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
        // In this setup the device listens to `/control/stepper`.
        // Send a stepper command (1 = OUT, -1 = IN) and record a command.
        final step = (decision == 'OUT') ? 1 : -1;
        _fb.pushStepperCommand(step).catchError((_) {});
        final cmd = {
          'type': 'STEPPER',
          'step': step,
          'source': 'auto',
        };
        _fb.pushControlCommand(cmd).then((cmdId) {}).catchError((_) {});

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
