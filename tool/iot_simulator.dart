// IoT Simulator CLI
// Usage examples:
// dart run tool/iot_simulator.dart --scenario=sunny_out --interval=2 --count=5
// dart run tool/iot_simulator.dart --scenario=fluctuate --interval=1 --count=20 --auth=FIREBASE_DB_SECRET

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

const String defaultDbUrl = 'https://clothesline-application-default-rtdb.asia-southeast1.firebasedatabase.app';

void printUsage() {
  print('''IoT Simulator

Usage:
  dart run tool/iot_simulator.dart --scenario=<name> [--interval=<seconds>] [--count=<n>] [--auth=<token>]

Scenarios:
  sunny_out    -> mode:AUTO, rain:false, light:800, position:OUT
  raining_in   -> mode:AUTO, rain:true, light:50, position:IN
  dark_in      -> mode:AUTO, rain:false, light:30, position:IN
  manual_out   -> mode:MANUAL, rain:false, light:500, position:OUT
  fluctuate    -> sequence that toggles rain and light to test AUTO behavior

Examples:
  dart run tool/iot_simulator.dart --scenario=fluctuate --interval=2 --count=20
''');
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

  if (scenario.isEmpty) {
    print('Error: missing --scenario');
    printUsage();
    exit(1);
  }

  print('Using DB URL: $dbUrl');
  if (auth != null) print('Using auth token from --auth (not shown)');

  for (int i = 0; i < count; i++) {
    final payload = _payloadForScenario(scenario, i);
    if (payload == null) {
      print('Unknown scenario: $scenario');
      printUsage();
      exit(1);
    }

    try {
      await sendStatus(dbUrl, payload, auth);
      final pretty = const JsonEncoder.withIndent('  ').convert(payload);
      print('[$i] Sent status:\n$pretty\n');
    } catch (e) {
      print('Error sending status: $e');
    }

    if (i < count - 1) {
      await Future.delayed(Duration(seconds: intervalSec));
    }
  }

  print('Done.');
}

Map<String, dynamic>? _payloadForScenario(String scenario, int step) {
  switch (scenario) {
    case 'sunny_out':
      return {
        'position': 'OUT',
        'mode': 'AUTO',
        'rain': false,
        'temperature': 30.0,
        'humidity': 40.0,
        
      };
    case 'raining_in':
      return {
        'position': 'IN',
        'mode': 'AUTO',
        'rain': true,
        'temperature': 22.0,
        'humidity': 95.0,
        
      };
    case 'dark_in':
      return {
        'position': 'IN',
        'mode': 'AUTO',
        'rain': false,
        'temperature': 18.0,
        'humidity': 70.0,
        
      };
    case 'manual_out':
      return {
        'position': 'OUT',
        'mode': 'MANUAL',
        'rain': false,
        'temperature': 25.0,
        'humidity': 50.0,
        
      };
    case 'fluctuate':
      // Simulate changing conditions over time
      final cycle = step % 6;
      if (cycle == 0) {
        return {
          'position': 'OUT',
          'mode': 'AUTO',
          'rain': false,
          'temperature': 28.0,
          'humidity': 45.0,
          
        };
      } else if (cycle == 1) {
        return {
          'position': 'OUT',
          'mode': 'AUTO',
          'rain': false,
          'temperature': 26.0,
          'humidity': 55.0,
          
        };
      } else if (cycle == 2) {
        return {
          'position': 'IN',
          'mode': 'AUTO',
          'rain': true,
          'temperature': 21.0,
          'humidity': 92.0,
          
        };
      } else if (cycle == 3) {
        return {
          'position': 'IN',
          'mode': 'AUTO',
          'rain': true,
          'temperature': 20.0,
          'humidity': 94.0,
          
        };
      } else if (cycle == 4) {
        return {
          'position': 'OUT',
          'mode': 'AUTO',
          'rain': false,
          'temperature': 27.0,
          'humidity': 48.0,
          
        };
      }
      return {
        'position': 'IN',
        'mode': 'AUTO',
        'rain': false,
        'temperature': 16.0,
        'humidity': 80.0,
        
      };
    default:
      return null;
  }
}

Future<void> sendStatus(String dbUrl, Map<String, dynamic> payload, String? auth) async {
  final uri = Uri.parse('$dbUrl/status.json${auth != null ? '?auth=$auth' : ''}');
  final body = jsonEncode(payload);

  final resp = await http.put(uri, headers: {'Content-Type': 'application/json'}, body: body);
  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
  }
}
