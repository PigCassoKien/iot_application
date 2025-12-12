// lib/features/clothesline/presentation/pages/home_page.dart

// lib/features/clothesline/presentation/pages/home_page.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import '../../data/firebase_service.dart';
import '../../data/weather_service.dart';
import 'dashboard_panel.dart';
import 'forecast_panel.dart';
import 'reminders_panel.dart';
import 'controls_panel.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Services
  final FirebaseService _fb = FirebaseService();
  final WeatherService _weatherService = WeatherService();

  // Forecast data
  List<WeatherDay> _forecast = [];
  List<WeatherHour> _hourly = [];
  final double _forecastLat = 21.0278;
  final double _forecastLon = 105.8342;
  DateTime? _forecastUpdatedAt;
  String? _locationName;

  // Device/status
  String position = 'IN';
  String mode = 'AUTO';
  bool isRaining = false;
  double temperature = 0.0;
  double humidity = 0.0;

  // Current control.stepper value (0 = idle, 1 = moving out, -1 = moving in)
  int _controlStepper = 0;
  DateTime? _lastAppStepperAt;
  static const Duration _appActionGrace = Duration(seconds: 60);

  // App state
  bool _hasClothes = false;
  List<Map<String, dynamic>> _reminders = [];
  final Map<String, StreamSubscription> _cmdSubs = {};
  bool _isCommandRunning = false;
  String _advice = '';
  String _forecastSummary = '';

  StreamSubscription? _statusSub;
  StreamSubscription? _controlSub;
  StreamSubscription? _remindersSub;
  StreamSubscription? _sensorSub;

  @override
  void initState() {
    super.initState();
    // Initial fetch
    _loadForecast();

    // Subscribe to realtime status to update UI values
    _statusSub = _fb.statusStream.listen((event) {
      final snap = event.snapshot;
      final map = _fb.snapshotToMap(snap);
      if (map == null) return;
      _applyStatusMap(map);
    });

    // Listen to control node for hasClothes and stepper etc
    _controlSub = _fb.controlStream.listen((event) {
      final snap = event.snapshot;
      final map = _fb.snapshotToMap(snap);
      if (map == null) return;
      _applyControlMap(map);
    });

    // Reminders stream
    _remindersSub = _fb.remindersStream.listen((event) {
      final snap = event.snapshot;
      final m = _fb.snapshotToMap(snap);
      if (m == null) return setState(() => _reminders = []);
      final List<Map<String, dynamic>> list = [];
      m.forEach((k, v) {
        if (v is Map) {
          final r = Map<String, dynamic>.from(v.cast<String, dynamic>());
          r['id'] = k;
          list.add(r);
        }
      });
      // sort by when
      list.sort((a, b) => (a['when'] as int? ?? 0).compareTo(b['when'] as int? ?? 0));
      setState(() => _reminders = list);
    });

    // Listen to sensor node directly (`/sensor`) for primary humidity/temp readings
    _sensorSub = _fb.sensorStream.listen((event) {
      final snap = event.snapshot;
      final map = _fb.snapshotToMap(snap);
      if (map == null) return;

      double? parseDouble(dynamic v) {
        if (v == null) return null;
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v);
        return null;
      }

      final t = parseDouble(map['temp'] ?? map['temperature'] ?? map['temperatureC'] ?? map['tempC']);
      final h = parseDouble(map['humidity'] ?? map['hum'] ?? map['h']);

      if (!mounted) return;
      setState(() {
        temperature = t ?? temperature;
        humidity = h ?? humidity;
      });
    });

    // Ensure stepper defaults to 0 (idle) at app startup. The device will
    // only act when user sets stepper to 1 or -1.
    _fb.ensureStepperZero().catchError((_) {});

    // Perform one-time initial reads so UI shows current DB immediately
    _fb.getStatusOnce().then((m) {
      if (m != null) _applyStatusMap(m);
    }).catchError((_) {});

    _fb.getControlOnce().then((m) {
      if (m != null) _applyControlMap(m);
    }).catchError((_) {});

    // One-time read of sensor node to populate UI immediately
    _fb.getSensorOnce().then((m) {
      if (m == null) return;
      double? parseDouble(dynamic v) {
        if (v == null) return null;
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v);
        return null;
      }
      final t = parseDouble(m['temp'] ?? m['temperature'] ?? m['tempC']);
      final h = parseDouble(m['humidity'] ?? m['hum']);
      if (!mounted) return;
      setState(() {
        temperature = t ?? temperature;
        humidity = h ?? humidity;
      });
    }).catchError((_) {});
  }

  void _applyStatusMap(Map<String, dynamic> map) {
    // Helper to read numeric values from multiple possible keys
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

    final tempVal = readNum(map, ['temperature', 'temp', 'sensor.temperature', 'sensor.temp']);
    final humVal = readNum(map, ['humidity', 'sensor.humidity', 'sensor.hum']);

    final rainVal = map['rain'] ?? map['isRaining'] ?? map['raining'] ?? (map['sensor'] is Map ? (map['sensor']['rain'] ?? map['sensor']['isRaining']) : null);

    if (!mounted) return;
    // Determine if rackPosition changed compared to current `position`
    final oldPosition = position;
    String posFromRack = position;
    final rpRaw = map['rackPosition'] ?? map['rackposition'];
    if (rpRaw != null) {
      if (rpRaw is num) {
        // Arduino uses 1 = OUT, 0 = IN
        posFromRack = (rpRaw == 1) ? 'OUT' : (rpRaw == 0 ? 'IN' : position);
      } else if (rpRaw is String) {
        final asNum = num.tryParse(rpRaw);
        if (asNum != null) posFromRack = (asNum == 1) ? 'OUT' : (asNum == 0 ? 'IN' : position);
        else posFromRack = (rpRaw.toUpperCase() == 'OUT') ? 'OUT' : ((rpRaw.toUpperCase() == 'IN') ? 'IN' : position);
      }
    }
    setState(() {
      temperature = tempVal?.toDouble() ?? temperature;
      humidity = humVal?.toDouble() ?? humidity;


      isRaining = (rainVal == true) || (rainVal is String && (rainVal == 'true' || rainVal == '1')) || (rainVal is num && rainVal != 0);
      position = posFromRack;
      mode = (map['mode'] as String?) ?? mode;
    });
    final newPosition = position;
    // If position changed as reported by device, show success message
    if (oldPosition != newPosition) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Giàn phơi đã được ${newPosition == 'OUT' ? 'kéo ra' : 'thu về'} thành công.')));
      });
      // Ensure control.stepper is cleared when device reports a new rackPosition
      // so the DB/UI reflect an idle device state.
      _fb.ensureStepperZero().catchError((_) {});
      // If device reports we are now IN (retracted) and conditions are OK,
      // and the retraction was NOT initiated recently by the app, then
      // in AUTO mode request an OUT movement so the clothesline returns out.
      if (newPosition == 'IN') {
        if (mode == 'AUTO' && _hasClothes && !isRaining) {
          final now = DateTime.now();
          final recentApp = _lastAppStepperAt != null && now.difference(_lastAppStepperAt!) < _appActionGrace;
          if (!recentApp && _controlStepper == 0) {
            // trigger automatic pull-out
            _lastAppStepperAt = null; // mark as not-app-initiated
            _fb.pushStepperCommand(1);
            _fb.pushControlCommand({'type': 'STEPPER', 'position': 1, 'source': 'auto'});
          }
        }
      }
    }

    // Recompute advice when sensors/status change
    _computeAdvice();
  }

  void _applyControlMap(Map<String, dynamic> map) {
    final hc = map['hasClothes'];
    if (hc == null) return;
    bool val = false;
    if (hc is bool) {
      val = hc;
    } else if (hc is num) val = hc != 0;
    else if (hc is String) val = hc == 'true' || hc == '1';
    // Update hasClothes first
    if (!mounted) return;
    setState(() => _hasClothes = val);

    // Also observe control.stepper for in-progress movement
    final sp = map['stepper'];
    int stepperVal = 0;
    if (sp is num) stepperVal = sp.toInt();
    else if (sp is String) stepperVal = int.tryParse(sp) ?? 0;

    if (stepperVal != _controlStepper) {
      // Moving started
      if (stepperVal != 0) {
        setState(() => _controlStepper = stepperVal);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Giàn phơi đang được ${stepperVal == 1 ? 'kéo ra' : 'thu về'}...')));
        });
      } else {
        // Moved back to idle
        setState(() => _controlStepper = 0);
      }
    }
  }

  @override
  void dispose() {
    for (final s in _cmdSubs.values) {
      try { s.cancel(); } catch (_) {}
    }
    try { _statusSub?.cancel(); } catch (_) {}
    try { _controlSub?.cancel(); } catch (_) {}
    try { _remindersSub?.cancel(); } catch (_) {}
    try { _sensorSub?.cancel(); } catch (_) {}
    super.dispose();
  }

  Future<void> _loadForecast() async {
    final res = await _weatherService.fetchDetailedForecast(latitude: _forecastLat, longitude: _forecastLon, days: 7);
    if (!mounted) return;
    setState(() {
      _forecast = res?.daily ?? [];
      _hourly = res?.hourly ?? [];
      _locationName = res?.locationName;
      _forecastUpdatedAt = DateTime.now();
    });

    // Recompute advice after loading forecast
    // Also compute a short human-readable forecast summary for the dashboard
    if (_forecast.isNotEmpty) {
      final next = _forecast.first;
      _forecastSummary = 'Ngày mai: ${next.tempMax.toStringAsFixed(0)}°/${next.tempMin.toStringAsFixed(0)}° • Mưa ${next.precipitationProbability.toStringAsFixed(0)}% • ${next.precipitationSum.toStringAsFixed(1)} mm';
    } else {
      _forecastSummary = '';
    }
    _computeAdvice();
  }

  void _computeAdvice() {
    // Advice must be based on forecast data when available (user request).
    String advice = '';
    if (_forecast.isNotEmpty) {
      final next = _forecast.first;
      final pProb = next.precipitationProbability; // percent 0..100
      final pSum = next.precipitationSum;

      if (pProb >= 60 || pSum >= 1.0) {
        advice = 'Ngày mai có khả năng mưa (${pProb.toStringAsFixed(0)}%) — khuyến nghị: mang đi sấy hoặc phơi trong nhà.';
      } else if (pProb >= 30) {
        advice = 'Có khả năng mưa nhẹ (${pProb.toStringAsFixed(0)}%) — cân nhắc phơi trong nhà hoặc theo dõi thời tiết.';
      } else {
        // Good day if low precip probability and reasonable max temp
        if (next.precipitationProbability < 30 && next.tempMax >= 12) {
          advice = 'Thời tiết ngày mai thuận lợi — nên phơi ngoài trời.';
        } else {
          advice = 'Thời tiết ngày mai không có mưa — cân nhắc phơi nếu cần.';
        }
      }
    } else {
      // No forecast available — fall back to sensor hints
      if (humidity >= 85.0) {
        advice = 'Không có dữ liệu dự báo — độ ẩm cao, cân nhắc sấy.';
      } else if (isRaining) advice = 'Không có dữ liệu dự báo và đang mưa — mang đi sấy.';
      else advice = 'Không có dữ liệu dự báo — theo dõi thời tiết trước khi phơi.';
    }

    if (!mounted) return;
    setState(() => _advice = advice);
  }


  Future<void> _showAddReminderDialog() async {
    final titleCtrl = TextEditingController();
    DateTime chosen = DateTime.now().add(const Duration(hours: 1));
    final picked = await showDialog<DateTime?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setState2) {
          return AlertDialog(
            title: const Text('Thêm nhắc nhở'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Tiêu đề')), const SizedBox(height: 8), Text('Thời gian: ${chosen.toLocal().toString().split('.').first}'), Row(children: [TextButton(onPressed: () async { final d = await showDatePicker(context: ctx2, initialDate: chosen, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365))); if (d != null) { chosen = DateTime(d.year, d.month, d.day, chosen.hour, chosen.minute); setState2(() {}); } }, child: const Text('Chọn ngày')), TextButton(onPressed: () async { final t = await showTimePicker(context: ctx2, initialTime: TimeOfDay.fromDateTime(chosen)); if (t != null) { chosen = DateTime(chosen.year, chosen.month, chosen.day, t.hour, t.minute); setState2(() {}); } }, child: const Text('Chọn giờ'))])]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx2, null), child: const Text('Hủy')),
              ElevatedButton(onPressed: () {
                if (titleCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx2, DateTime.fromMillisecondsSinceEpoch(chosen.millisecondsSinceEpoch));
              }, child: const Text('Lưu')),
            ],
          );
        });
      },
    );
    if (picked != null) {
      try {
        await _fb.addReminder(title: titleCtrl.text.trim(), whenMillis: picked.millisecondsSinceEpoch);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã thêm nhắc nhở')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Thêm nhắc nhở thất bại: $e')));
      }
    }
  }

  Future<void> _markReminderDone(String id) async {
    try {
      await FirebaseDatabase.instance.ref('reminders/$id').update({'done': true});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã đánh dấu hoàn thành')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không thể cập nhật nhắc nhở: $e')));
    }
  }

  Future<void> _pushCommand(String pos) async {
    if (_isCommandRunning) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang có lệnh khác, vui lòng chờ')));
      return;
    }
    if (_controlStepper != 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thiết bị đang di chuyển, vui lòng chờ')));
      return;
    }

    // Optimistic UI update: show requested position immediately
    final previousPosition = position;
    setState(() {
      position = pos;
      _isCommandRunning = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gửi lệnh đến thiết bị...')));

    try {
      // Send stepper position (1 = OUT, 0 = IN). Device listens to `/control/stepper`.
      final desiredPosition = (pos == 'OUT') ? 1 : 0;
      _lastAppStepperAt = DateTime.now();
      await _fb.pushStepperCommand(desiredPosition);

      final cmdId = await _fb.pushControlCommand({'type': 'STEPPER', 'position': desiredPosition, 'source': 'app'});

      // Send a user-visible notification about manual action
      try {
        final title = 'Yêu cầu tay: ${pos == 'OUT' ? 'Kéo ra phơi' : 'Kéo vào nhà'}';
        final body = 'Người dùng đã yêu cầu ${pos == 'OUT' ? 'kéo quần áo ra phơi' : 'kéo quần áo vào nhà'}.';
        await _fb.sendNotification(title, body);
      } catch (_) {}
      final ref = FirebaseDatabase.instance.ref('commands/$cmdId');
      final sub = ref.onValue.listen((event) {
        final snap = event.snapshot;
        final v = snap.value;
        if (v == null || v is! Map) return;
        final status = (v['status'] as String?) ?? 'pending';
        if (status == 'processing') {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thiết bị đang thực hiện lệnh...')));
        } else if (status == 'done') {
          // Accept numeric (1/0) or string position from command result.
          final dynPos = v['position'];
          String newPos = pos;
          if (dynPos is num) newPos = (dynPos == 1) ? 'OUT' : 'IN';
          else if (dynPos is String) {
            final asNum = int.tryParse(dynPos);
            if (asNum != null) newPos = (asNum == 1) ? 'OUT' : 'IN';
            else newPos = (dynPos.toUpperCase() == 'OUT') ? 'OUT' : ((dynPos.toUpperCase() == 'IN') ? 'IN' : pos);
          }
          // Confirmed by device
          setState(() => position = newPos);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lệnh đã thực hiện xong')));
          _cmdSubs[cmdId]?.cancel();
          _cmdSubs.remove(cmdId);
          setState(() => _isCommandRunning = false);
        } else if (status == 'failed') {
          final err = (v['error'] as String?) ?? 'Không xác định';
          // Revert optimistic update on failure
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lệnh thất bại: $err')));
          setState(() => position = previousPosition);
          _cmdSubs[cmdId]?.cancel();
          _cmdSubs.remove(cmdId);
          setState(() => _isCommandRunning = false);
        }
      });
      _cmdSubs[cmdId] = sub;
    } catch (e) {
      // Push failed — revert optimistic update
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gửi lệnh thất bại: $e')));
      setState(() {
        position = previousPosition;
        _isCommandRunning = false;
      });
    }
  }

  Future<void> _toggleHasClothes() async {
    final newVal = !_hasClothes;
    try {
      await _fb.setHasClothes(newVal);
      setState(() => _hasClothes = newVal);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(newVal ? 'Đã đặt: Có quần áo trên giá' : 'Đã đặt: Không có quần áo trên giá')));

      // Per UX: when user marks clothes present, request stepper=1 to pull out
      if (newVal) {
        // if raining, warn user and don't trigger
        if (isRaining) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cảnh báo: Trời đang mưa — không kéo ra')));
        } else {
          _lastAppStepperAt = DateTime.now();
          // await _fb.pushStepperCommand(0);
        }
      } else {
        // When user marks removed, request stepper 0 to retract
        _lastAppStepperAt = DateTime.now();
        // await _fb.pushStepperCommand(0);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không thể cập nhật trạng thái: $e')));
    }
  }

  Future<void> _sendStepper(int step) async {
    if (_controlStepper != 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thiết bị đang di chuyển, vui lòng chờ')));
      return;
    }
    // Guard: if trying to pull OUT but no clothes or raining, block
    if (step == 1) {
      if (!_hasClothes) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không có quần áo để kéo ra.')));
        return;
      }
      if (isRaining) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trời đang mưa — không thực hiện kéo ra.')));
        return;
      }
    }
    try {
      _lastAppStepperAt = DateTime.now();
      await _fb.pushStepperCommand(step);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gửi lệnh điều khiển stepper...')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gửi lệnh thất bại: $e')));
    }
  }

  Future<void> _confirmStepper(int step) async {
    final actionText = step == 1 ? 'kéo ra' : 'thu về';
    final title = step == 1 ? 'Xác nhận: Kéo ra' : 'Xác nhận: Thu về';

    // Quick guard: prevent attempting when not allowed
    if (step == 1 && (isRaining || !_hasClothes)) {
      final msg = isRaining ? 'Trời đang mưa — không thể kéo ra.' : 'Không có quần áo để kéo ra.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text('Bạn có chắc muốn $actionText không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xác nhận')),
        ],
      ),
    );

    if (confirmed == true) {
      await _sendStepper(step);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isOutside = position == 'OUT';

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('Giàn Phơi Thông Minh', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(_locationName ?? 'Hà Nội', style: const TextStyle(fontSize: 20, color: Color.fromARGB(179, 57, 15, 15))),
            ],
          ),
          centerTitle: true,
          backgroundColor: const Color.fromARGB(255, 9, 164, 102),
          elevation: 0,
          bottom: const TabBar(tabs: [Tab(text: 'Tổng quan', icon: Icon(Icons.dashboard)), Tab(text: 'Điều khiển', icon: Icon(Icons.settings))]),
        ),
        body: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            return Container(
              padding: const EdgeInsets.all(16),
              color: isOutside ? Colors.orange[25] : Colors.blueGrey[25],
              child: TabBarView(children: [
                // Tab 1: Overview — Dashboard + Forecast
                SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    DashboardPanel(
                      isOutside: isOutside,
                      isRaining: isRaining,
                      temperature: temperature,
                      humidity: humidity,
                      position: position,
                      mode: mode,
                      locationName: _locationName,
                      advice: _advice,
                      forecastSummary: _forecastSummary,
                      onRefreshForecast: _loadForecast,
                      onAddReminder: _showAddReminderDialog,
                      onSendNotification: (t, b) => _fb.sendNotification(t, b),
                    ),
                    const SizedBox(height: 12),
                    ForecastPanel(
                      forecast: _forecast,
                      updatedAt: _forecastUpdatedAt,
                      onRefresh: _loadForecast,
                      onChangeCoords: () async {
                        final res = await showDialog<Map<String, double>?>(
                          context: context,
                          builder: (ctx) {
                            final latCtrl = TextEditingController(text: _forecastLat.toString());
                            final lonCtrl = TextEditingController(text: _forecastLon.toString());
                            return AlertDialog(
                              title: const Text('Thay đổi tọa độ'),
                              content: Column(mainAxisSize: MainAxisSize.min, children: [
                                TextField(controller: latCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Latitude')),
                                TextField(controller: lonCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Longitude')),
                              ]),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Hủy')),
                                ElevatedButton(onPressed: () { final lat = double.tryParse(latCtrl.text); final lon = double.tryParse(lonCtrl.text); if (lat == null || lon == null) return; Navigator.pop(ctx, {'lat': lat, 'lon': lon}); }, child: const Text('Lưu')),
                              ],
                            );
                          },
                        );
                        return res;
                      },
                      onShowHourly: _showHourlyForDay,
                    ),
                    const SizedBox(height: 12),
                    RemindersPanel(reminders: _reminders, onAddReminder: _showAddReminderDialog, onMarkDone: _markReminderDone),
                    const SizedBox(height: 26),
                  ]),
                ),

                // Tab 2: Controls — Mode, Manual action, ControlsPanel
                SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SizedBox(height: 4),
                    Center(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'AUTO', label: Text('TỰ ĐỘNG'), icon: Icon(Icons.auto_mode)),
                          ButtonSegment(value: 'MANUAL', label: Text('THỦ CÔNG'), icon: Icon(Icons.handyman)),
                        ],
                        selected: {mode},
                        onSelectionChanged: (newMode) {
                          setState(() { mode = newMode.first; });
                          _fb.setMode(newMode.first);
                        },
                      ),
                    ),

                    const SizedBox(height: 18),

                    if (mode == 'MANUAL')
                      (position == 'OUT'
                          ? _bigButton('KÉO VÀO NHÀ', Icons.home, Colors.indigo, () async {
                              await _pushCommand('IN');
                            })
                          : _bigButton('KÉO RA PHƠI', Icons.wb_sunny, Colors.orange, () async {
                              if (isRaining) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trời đang mưa: Không nên kéo quần áo ra phơi')));
                                return;
                              }
                              await _pushCommand('OUT');
                            }))
                    else
                      Card(color: Colors.green[50], elevation: 2, child: const Padding(padding: EdgeInsets.all(16), child: Text('Chế độ TỰ ĐỘNG đang hoạt động — Giàn phơi tự động điều chỉnh', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)))),

                    const SizedBox(height: 18),

                    ControlsPanel(
                      hasClothes: _hasClothes,
                      isRaining: isRaining,
                      temperature: temperature,
                      humidity: humidity,
                      position: position,
                      mode: mode,
                      stepperCommand: _controlStepper,
                      onToggleHasClothes: _toggleHasClothes,
                      onConfirmStepper: (s) => _confirmStepper(s),
                    ),

                    const SizedBox(height: 26),
                  ]),
                ),
              ]),
            );
          }),
        ),
      ),
    );
  }

  

  Widget _bigButton(String text, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 28),
      label: Text(text, style: const TextStyle(fontSize: 16)),
      style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 6),
    );
  }

  void _showHourlyForDay(WeatherDay day) {
    final dayStart = DateTime(day.date.year, day.date.month, day.date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final hours = _hourly.where((h) => h.dateTime.isAfter(dayStart.subtract(const Duration(seconds: 1))) && h.dateTime.isBefore(dayEnd)).toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          maxChildSize: 0.92,
          builder: (context, scrollCtrl) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(height: 4, width: 48, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)))),
                  Text('${day.niceDate} — Chi tiết giờ', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollCtrl,
                      itemCount: hours.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (c, i) {
                        final h = hours[i];
                        return ListTile(
                          leading: Text(h.niceHour, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          title: Text('${h.temperature.toStringAsFixed(0)}°', style: const TextStyle(fontSize: 16)),
                          subtitle: Text('Mưa: ${h.precipitationProbability.toStringAsFixed(0)} % — ${h.precipitation.toStringAsFixed(1)} mm'),
                          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.invert_colors, color: Colors.blue, size: 18), const SizedBox(height: 4), Text('${h.precipitationProbability.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.blue))]),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
 