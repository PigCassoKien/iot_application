// Enhanced IoT Simulator CLI
// - adds realistic sensor noise and timestamps
// - supports updating `/config` via --set-config or --config-file
// - supports device-id and custom DB URL/auth
// Usage examples:
// dart run tool/iot_simulator_enhanced.dart --scenario=sunny_out --interval=2 --count=5 --auth=YOUR_DB_SECRET
// dart run tool/iot_simulator_enhanced.dart --scenario=fluctuate --interval=1 --count=20 --auth=YOUR_DB_SECRET --device-id=device01 --noise=0.1
// dart run tool/iot_simulator_enhanced.dart --set-config='{"minLightOut":900,"maxWindForOut":6.0}' --auth=YOUR_DB_SECRET

import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

const String defaultDbUrl = 'https://clothesline-application-default-rtdb.asia-southeast1.firebasedatabase.app';

void printUsage() {
  print('''IoT Simulator (enhanced)

Usage:
  dart run tool/iot_simulator_enhanced.dart --scenario=<name> [--interval=<seconds>] [--count=<n>] [--auth=<token>] [--db=<dbUrl>] [--device-id=<id>] [--noise=<0.0-1.0>] [--set-config='<json>'] [--config-file=path]

Scenarios:
  sunny_out    -> bright, no rain, OUT
  raining_in   -> raining, dark, IN
  dark_in      -> dark, cold, IN
  manual_out   -> manual mode with OUT (no auto action)
  fluctuate    -> sequence of changing conditions to stress AUTO

Flags:
  --set-config   : JSON string to PUT to /config (applied before emitting status)
  --config-file  : path to JSON file to PUT to /config
  --device-id    : id of the simulated device (added to payload)
  --noise        : float 0..1, relative noise level added to sensors (default 0.05)

Examples:
  dart run tool/iot_simulator_enhanced.dart --scenario=fluctuate --interval=2 --count=20 --auth=YOUR_DB_SECRET --device-id=device01 --noise=0.08
  dart run tool/iot_simulator_enhanced.dart --set-config='{"minLightOut":900}' --auth=YOUR_DB_SECRET
''');
}

double _clampDouble(double v, double min, double max) => v < min ? min : (v > max ? max : v);

Map<String, dynamic> _applyNoise(Map<String, dynamic> base, double noise, Random rnd) {
  // noise: relative amount (0.0 - 1.0) to vary sensors
  final result = Map<String, dynamic>.from(base);
  if (base.containsKey('light')) {
    final v = (base['light'] as num).toDouble();
    final delta = (rnd.nextDouble() * 2 - 1) * noise * v;
    result['light'] = max(0, (v + delta).round());
  }
  if (base.containsKey('temperature')) {
    final v = (base['temperature'] as num).toDouble();
    final delta = (rnd.nextDouble() * 2 - 1) * noise * 5.0; // ±5°C * noise
    result['temperature'] = double.parse((_clampDouble(v + delta, -30, 60)).toStringAsFixed(1));
  }
  if (base.containsKey('humidity')) {
    final v = (base['humidity'] as num).toDouble();
    final delta = (rnd.nextDouble() * 2 - 1) * noise * 15.0; // ±15% * noise
    result['humidity'] = double.parse((_clampDouble(v + delta, 0, 100)).toStringAsFixed(1));
  }
  if (base.containsKey('wind')) {
    final v = (base['wind'] as num).toDouble();
    final delta = (rnd.nextDouble() * 2 - 1) * noise * 3.0; // ±3 m/s * noise
    result['wind'] = double.parse((_clampDouble(v + delta, 0.0, 60.0)).toStringAsFixed(2));
  }
  return result;
}

Map<String, dynamic>? _payloadForScenario(String scenario, int step, String deviceId, Random rnd) {
  switch (scenario) {
    case 'sunny_out':
      return {
        'deviceId': deviceId,
        'position': 'OUT',
        'mode': 'AUTO',
        'rain': false,
        'light': 900,
        'temperature': 28.0,
        'humidity': 45.0,
        'wind': 1.2,
        'timestamp': DateTime.now().toIso8601String(),
      };
    case 'raining_in':
      return {
        'deviceId': deviceId,
        'position': 'IN',
        'mode': 'AUTO',
        'rain': true,
        'light': 60,
        'temperature': 22.0,
        'humidity': 92.0,
        'wind': 2.5,
        'timestamp': DateTime.now().toIso8601String(),
      };
    case 'dark_in':
      return {
        'deviceId': deviceId,
        'position': 'IN',
        'mode': 'AUTO',
        'rain': false,
        'light': 30,
        'temperature': 4.0,
        'humidity': 80.0,
        'wind': 1.0,
        'timestamp': DateTime.now().toIso8601String(),
      };
    case 'manual_out':
      return {
        'deviceId': deviceId,
        'position': 'OUT',
        'mode': 'MANUAL',
        'rain': false,
        'light': 500,
        'temperature': 24.0,
        'humidity': 50.0,
        'wind': 0.8,
        'timestamp': DateTime.now().toIso8601String(),
      };
    case 'fluctuate':
      // A deterministic sequence varying rain/light/wind over time
      final cycle = step % 12;
      if (cycle < 3) {
        return {
          'deviceId': deviceId,
          'position': 'OUT',
          'mode': 'AUTO',
          'rain': false,
          'light': 800,
          'temperature': 26.0,
          'humidity': 50.0,
          'wind': 1.0,
          'timestamp': DateTime.now().toIso8601String(),
        };
      } else if (cycle < 6) {
        return {
          'deviceId': deviceId,
          'position': 'IN',
          'mode': 'AUTO',
          'rain': true,
          'light': 40,
          'temperature': 23.0,
          'humidity': 90.0,
          'wind': 2.0,
          'timestamp': DateTime.now().toIso8601String(),
        };
      } else if (cycle < 9) {
        return {
          'deviceId': deviceId,
          'position': 'OUT',
          'mode': 'AUTO',
          'rain': false,
          'light': 700,
          'temperature': 20.0,
          'humidity': 60.0,
          'wind': 3.5,
          'timestamp': DateTime.now().toIso8601String(),
        };
      } else {
        return {
          'deviceId': deviceId,
          'position': 'IN',
          'mode': 'AUTO',
          'rain': false,
          'light': 120,
          'temperature': 16.0,
          'humidity': 85.0,
          'wind': 6.0,
          'timestamp': DateTime.now().toIso8601String(),
        };
      }
    default:
      return null;
  }
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    printUsage();
    exit(0);
  }

  final Map<String, String> opts = {};
  for (final a in args) {
    if (!a.startsWith('--')) continue;
    final split = a.substring(2).split('=');
    if (split.length == 2) opts[split[0]] = split[1];
  }

  final scenario = opts['scenario'] ?? '';
  final intervalSec = int.tryParse(opts['interval'] ?? '2') ?? 2;
  final count = int.tryParse(opts['count'] ?? '10') ?? 10;
  final auth = opts['auth'];
  final dbUrl = opts['db'] ?? defaultDbUrl;
  final deviceId = opts['device-id'] ?? 'sim-device-01';
  final noise = double.tryParse(opts['noise'] ?? '0.05') ?? 0.05;
  final setConfigJson = opts['set-config'];
  final configFile = opts['config-file'];

  print('Using DB URL: $dbUrl');
  if (auth != null) print('Using auth token from --auth (not shown)');
  print('Device ID: $deviceId  noise: $noise');

  // If config set, apply it first
  if (setConfigJson != null || configFile != null) {
    String cfgJson = setConfigJson ?? '';
    if (configFile != null) {
      cfgJson = await File(configFile).readAsString();
    }
    try {
      final uri = Uri.parse('$dbUrl/config.json${auth != null ? '?auth=$auth' : ''}');
      final resp = await http.put(uri, headers: {'Content-Type': 'application/json'}, body: cfgJson);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        print('Updated /config successfully.');
      } else {
        print('Failed to update /config: HTTP ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      print('Error updating /config: $e');
    }
  }

  final rnd = Random();
  for (int i = 0; i < count; i++) {
    final base = _payloadForScenario(scenario, i, deviceId, rnd);
    if (base == null) {
      print('Unknown scenario: $scenario');
      printUsage();
      exit(1);
    }

    final payload = _applyNoise(base, noise, rnd);

    try {
      await sendStatus(dbUrl, payload, auth);
      final pretty = const JsonEncoder.withIndent('  ').convert(payload);
      print('[$i] Sent status:\n$pretty\n');
    } catch (e) {
      print('Error sending status: $e');
    }

    // After sending status, poll for pending commands and attempt to execute them.
    try {
      await fetchAndExecuteCommands(dbUrl, auth, deviceId);
    } catch (e) {
      print('Error fetching/executing commands: $e');
    }

    if (i < count - 1) {
      await Future.delayed(Duration(seconds: intervalSec));
    }
  }

  print('Done.');
}

Future<void> sendStatus(String dbUrl, Map<String, dynamic> payload, String? auth) async {
  final uri = Uri.parse('$dbUrl/status.json${auth != null ? '?auth=$auth' : ''}');
  final body = jsonEncode(payload);

  final resp = await http.put(uri, headers: {'Content-Type': 'application/json'}, body: body);
  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
  }
}

/// Fetch pending commands and execute them (simulation).
Future<void> fetchAndExecuteCommands(String dbUrl, String? auth, String deviceId) async {
  final uri = Uri.parse('$dbUrl/control/commands.json${auth != null ? '?auth=$auth' : ''}');
  final resp = await http.get(uri);
  if (resp.statusCode != 200) return;
  final data = jsonDecode(resp.body) as Map<String, dynamic>?;
  if (data == null) return;

  for (final entry in data.entries) {
    final cmdId = entry.key;
    final cmd = entry.value as Map<String, dynamic>?;
    if (cmd == null) continue;
    final status = (cmd['status'] as String?) ?? 'pending';
    if (status != 'pending') continue;

    final cmdType = cmd['type'] as String? ?? '';
    final position = cmd['position'] as String? ?? '';

    print('Found pending command $cmdId: $cmdType -> $position');

    // mark processing
    final procUri = Uri.parse('$dbUrl/control/commands/$cmdId.json${auth != null ? '?auth=$auth' : ''}');
    final procBody = jsonEncode({'status': 'processing', 'processorId': deviceId, 'processing_ts': DateTime.now().toIso8601String()});
    await http.patch(procUri, headers: {'Content-Type': 'application/json'}, body: procBody);

    // simulate executing: wait a bit
    await Future.delayed(const Duration(seconds: 2));

    // update device status (position)
    final statusUri = Uri.parse('$dbUrl/status.json${auth != null ? '?auth=$auth' : ''}');
    final newStatus = {
      'deviceId': deviceId,
      'position': position,
      'mode': 'MANUAL',
      'rain': false,
      'light': 500,
      'temperature': 24.0,
      'humidity': 50.0,
      'wind': 0.8,
      'timestamp': DateTime.now().toIso8601String(),
    };
    await http.put(statusUri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(newStatus));

    // mark command done
    final doneBody = jsonEncode({'status': 'done', 'done_ts': DateTime.now().toIso8601String(), 'position': position});
    await http.patch(procUri, headers: {'Content-Type': 'application/json'}, body: doneBody);

    print('Executed command $cmdId -> $position');
  }
}
