// lib/features/clothesline/presentation/pages/home_page.dart

// lib/features/clothesline/presentation/pages/home_page.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../data/firebase_service.dart';
import '../../data/weather_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseService _fb = FirebaseService();

  // Weather
  final WeatherService _weatherService = WeatherService();
  List<WeatherDay> _forecast = [];
  List<WeatherHour> _hourly = [];
  double _forecastLat = 21.0278;
  double _forecastLon = 105.8342;
  DateTime? _forecastUpdatedAt;
  String? _locationName;
  Duration _forecastInterval = const Duration(minutes: 15);
  Timer? _weatherTimer;

  String position = 'IN';
  String mode = 'AUTO';
  bool isRaining = false;
  int light = 0;
  double temperature = 0.0;
  double humidity = 0.0;
  double wind = 0.0;
  String? _lastPosition;
  final Map<String, StreamSubscription> _cmdSubs = {};
  bool _isCommandRunning = false;

  @override
  void initState() {
    super.initState();

    _fb.statusStream.listen((event) {
      final DataSnapshot snapshot = event.snapshot;
      final data = snapshot.value;

      if (!mounted) return;
      if (data == null || data is! Map<Object?, Object?>) {
        setState(() {
          position = 'IN';
          mode = 'AUTO';
          isRaining = false;
          light = 0;
        });
        return;
      }

      final map = data;
      final newPosition = (map['position'] as String?) ?? 'IN';
      final newMode = (map['mode'] as String?) ?? 'AUTO';
      final newRain = (map['rain'] as bool?) ?? false;
      final newLight = (map['light'] as num?)?.toInt() ?? 0;
      final newTemp = (map['temperature'] as num?)?.toDouble() ?? 0.0;
      final newHumidity = (map['humidity'] as num?)?.toDouble() ?? 0.0;
      final newWind = (map['wind'] as num?)?.toDouble() ?? 0.0;

      final oldPosition = position;
      setState(() {
        position = newPosition;
        mode = newMode;
        isRaining = newRain;
        light = newLight;
        temperature = newTemp;
        humidity = newHumidity;
        wind = newWind;
      });

      _lastPosition ??= oldPosition;
      if (_lastPosition != position) {
        final msg = position == 'OUT' ? 'Đang kéo ra phơi' : 'Đang kéo vào nhà';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        _lastPosition = position;
      }
    });

    _loadForecast();
    _weatherTimer = Timer.periodic(_forecastInterval, (_) => _loadForecast());
  }

  @override
  void dispose() {
    _weatherTimer?.cancel();
    for (final sub in _cmdSubs.values) {
      sub.cancel();
    }
    _cmdSubs.clear();
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
  }

  Future<void> _pushCommand(String pos) async {
    if (_isCommandRunning) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang có lệnh khác, vui lòng chờ')));
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
      final cmdId = await _fb.pushControlCommand({'type': 'SET_POSITION', 'position': pos, 'source': 'app'});
      final ref = FirebaseDatabase.instance.ref('control/commands/$cmdId');
      final sub = ref.onValue.listen((event) {
        final snap = event.snapshot;
        final v = snap.value;
        if (v == null || v is! Map) return;
        final status = (v['status'] as String?) ?? 'pending';
        if (status == 'processing') {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thiết bị đang thực hiện lệnh...')));
        } else if (status == 'done') {
          final newPos = (v['position'] as String?) ?? pos;
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

  @override
  Widget build(BuildContext context) {
    final bool isOutside = position == 'OUT';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('Giàn Phơi Thông Minh', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(_locationName ?? 'Hà Nội', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.indigo[600],
        elevation: 0,
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth > 760;
          return Container(
            padding: const EdgeInsets.all(16),
            color: isOutside ? Colors.orange[25] : Colors.blueGrey[25],
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 6,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Lottie.asset(isOutside ? 'assets/lottie/clothesline_out.json' : 'assets/lottie/clothesline_in.json', height: 260, fit: BoxFit.contain, repeat: true),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 4,
                          child: Column(
                            children: [
                              Card(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 4,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                                  child: Column(
                                    children: [
                                      Text(isOutside ? 'ĐANG PHƠI NGOÀI TRỜI' : 'ĐÃ KÉO VÀO TRONG NHÀ', style: GoogleFonts.kanit(fontSize: 22, fontWeight: FontWeight.bold, color: isOutside ? Colors.orange[800] : Colors.indigo[800])),
                                      const SizedBox(height: 12),
                                      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                                        _smallMetric(Icons.umbrella, isRaining ? 'Mưa' : 'Tạnh', isRaining ? Colors.red : Colors.green),
                                        _smallMetric(Icons.wb_sunny, '$light lx', Colors.orange),
                                        _smallMetric(Icons.thermostat, '${temperature.toStringAsFixed(1)}°C', Colors.redAccent),
                                      ]),
                                      const SizedBox(height: 12),
                                      Row(children: [Expanded(child: ElevatedButton.icon(onPressed: () => _fb.sendNotification('Yêu cầu', 'Vui lòng kiểm tra thiết bị'), icon: const Icon(Icons.notifications), label: const Text('Gửi thông báo')))]),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Card(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 3,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    children: [
                                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Cập nhật cảm biến', style: TextStyle(fontWeight: FontWeight.w600)), Text(mode, style: const TextStyle(color: Colors.grey))]),
                                      const SizedBox(height: 8),
                                      Wrap(spacing: 8, runSpacing: 8, children: [_chipMetric('Gió', '${wind.toStringAsFixed(1)} m/s'), _chipMetric('Độ ẩm', '${humidity.toStringAsFixed(0)} %'), _chipMetric('Vị trí', position)]),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 6,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                Lottie.asset(isOutside ? 'assets/lottie/clothesline_out.json' : 'assets/lottie/clothesline_in.json', height: 220),
                                const SizedBox(height: 8),
                                Text(isOutside ? 'ĐANG PHƠI NGOÀI TRỜI' : 'ĐÃ KÉO VÀO TRONG NHÀ', style: GoogleFonts.kanit(fontSize: 20, fontWeight: FontWeight.bold, color: isOutside ? Colors.orange[800] : Colors.indigo[800])),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_smallMetric(Icons.umbrella, isRaining ? 'Mưa' : 'Tạnh', isRaining ? Colors.red : Colors.green), _smallMetric(Icons.wb_sunny, '$light lx', Colors.orange), _smallMetric(Icons.thermostat, '${temperature.toStringAsFixed(1)}°C', Colors.redAccent)]),
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 18),

                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Dự báo 7 ngày', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              Row(
                                children: [
                                  IconButton(icon: const Icon(Icons.refresh), onPressed: _loadForecast),
                                  IconButton(icon: const Icon(Icons.place), onPressed: () async {
                                    final res = await showDialog<Map<String, double>?>(
                                      context: context,
                                      builder: (ctx) {
                                        final latCtrl = TextEditingController(text: _forecastLat.toString());
                                        final lonCtrl = TextEditingController(text: _forecastLon.toString());
                                        return AlertDialog(
                                          title: const Text('Thay đổi tọa độ'),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              TextField(controller: latCtrl, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Latitude')),
                                              TextField(controller: lonCtrl, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Longitude')),
                                            ],
                                          ),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Hủy')),
                                            ElevatedButton(onPressed: () { final lat = double.tryParse(latCtrl.text); final lon = double.tryParse(lonCtrl.text); if (lat == null || lon == null) return; Navigator.pop(ctx, {'lat': lat, 'lon': lon}); }, child: const Text('Lưu')),
                                          ],
                                        );
                                      },
                                    );
                                    if (res != null) {
                                      setState(() { _forecastLat = res['lat']!; _forecastLon = res['lon']!; });
                                      await _loadForecast();
                                    }
                                  }),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_forecast.isEmpty)
                            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Không có dữ liệu thời tiết', style: TextStyle(color: Colors.grey[700])))
                          else
                            SizedBox(
                              height: 110,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _forecast.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 8),
                                itemBuilder: (ctx, i) {
                                  final day = _forecast[i];
                                  return InkWell(
                                    onTap: () => _showHourlyForDay(day),
                                    child: Container(
                                      width: 110,
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                        Text(day.niceDate, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 6),
                                        Text('${day.tempMax.toStringAsFixed(0)}°/${day.tempMin.toStringAsFixed(0)}°', style: const TextStyle(fontSize: 14)),
                                        const SizedBox(height: 6),
                                        Text('Mưa ${day.precipitationProbability.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.blue)),
                                      ]),
                                    ),
                                  );
                                },
                              ),
                            ),
                          const SizedBox(height: 8),
                          if (_forecastUpdatedAt != null) Text('Cập nhật: ${_forecastUpdatedAt.toString()}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

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
                    Row(children: [Expanded(child: _bigButton('KÉO RA PHƠI', Icons.wb_sunny, Colors.orange, () => _pushCommand('OUT'))), const SizedBox(width: 12), Expanded(child: _bigButton('KÉO VÀO NHÀ', Icons.home, Colors.indigo, () => _pushCommand('IN')))])
                  else
                    Card(color: Colors.green[50], elevation: 2, child: Padding(padding: const EdgeInsets.all(16), child: Text('Chế độ TỰ ĐỘNG đang hoạt động — Giàn phơi tự động điều chỉnh', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)))),

                  const SizedBox(height: 18),

                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _sensorTile(Icons.umbrella, 'Thời tiết', isRaining ? 'Mưa' : 'Tạnh', isRaining ? Colors.red : Colors.green),
                          _sensorTile(Icons.thermostat, 'Nhiệt độ', '${temperature.toStringAsFixed(1)} °C', Colors.redAccent),
                          _sensorTile(Icons.water_drop, 'Độ ẩm', '${humidity.toStringAsFixed(0)} %', Colors.blueAccent),
                          _sensorTile(Icons.air, 'Gió', '${wind.toStringAsFixed(1)} m/s', Colors.teal),
                          _sensorTile(Icons.wb_sunny, 'Ánh sáng', '$light lx', light > 600 ? Colors.orange : Colors.grey[700]!),
                          _sensorTile(Icons.location_on, 'Vị trí', position, Colors.indigo),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 26),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _smallMetric(IconData icon, String label, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _chipMetric(String label, String value) {
    return Chip(label: Text('$label: $value'));
  }

  Widget _sensorTile(IconData icon, String title, String value, Color color) {
    return SizedBox(
      width: 160,
      child: Row(
        children: [
          CircleAvatar(radius: 20, backgroundColor: color.withOpacity(0.12), child: Icon(icon, color: color)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)), const SizedBox(height: 4), Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color))])),
        ],
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
                          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.invert_colors, color: Colors.blue, size: 18), const SizedBox(height: 4), Text('${h.precipitationProbability.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.blue))]),
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
 