import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:google_fonts/google_fonts.dart';

class DashboardPanel extends StatelessWidget {
  final bool isOutside;
  final bool isRaining;
  final double temperature;
  final double humidity;
  final String position;
  final String mode;
  final String? locationName;
  final String advice;
  final String forecastSummary;
  final VoidCallback onRefreshForecast;
  final VoidCallback onAddReminder;
  final Future<void> Function(String title, String body) onSendNotification;

  const DashboardPanel({
    super.key,
    required this.isOutside,
    required this.isRaining,
    required this.temperature,
    required this.humidity,
    required this.position,
    required this.mode,
    this.locationName,
    this.advice = '',
    this.forecastSummary = '',
    required this.onRefreshForecast,
    required this.onAddReminder,
    required this.onSendNotification,
  });

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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _smallMetric(Icons.umbrella, isRaining ? 'Mưa' : 'Tạnh', isRaining ? Colors.red : Colors.green),
              _smallMetric(Icons.water_drop, '${humidity.toStringAsFixed(0)} %', const Color.fromARGB(255, 20, 111, 230)),
              _smallMetric(Icons.thermostat, '${temperature.toStringAsFixed(1)}°C', Colors.redAccent),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Expanded(child: Text('Lời khuyên thời tiết', style: TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Flexible(child: Wrap(alignment: WrapAlignment.end, spacing: 8, children: [TextButton.icon(onPressed: onRefreshForecast, icon: const Icon(Icons.refresh), label: const Text('Cập nhật')), TextButton.icon(onPressed: onAddReminder, icon: const Icon(Icons.add_alert), label: const Text('Thêm nhắc nhở'))]))
              ]),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(advice.isNotEmpty ? advice : 'Thời tiết hiện tại — xem chi tiết để biết lời khuyên', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    if (forecastSummary.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(forecastSummary, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                    ]
                  ])),
                ]),
              )
            ]),
          ),
        ),
      ],
    );
  }
}
