import 'package:flutter/material.dart';
import '../../data/weather_service.dart';

class ForecastPanel extends StatelessWidget {
  final List<WeatherDay> forecast;
  final DateTime? updatedAt;
  final VoidCallback onRefresh;
  final Future<Map<String, double>?> Function()? onChangeCoords;
  final void Function(WeatherDay day) onShowHourly;

  const ForecastPanel({
    super.key,
    required this.forecast,
    required this.updatedAt,
    required this.onRefresh,
    required this.onChangeCoords,
    required this.onShowHourly,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Dự báo 7 ngày', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Row(children: [IconButton(icon: const Icon(Icons.refresh), onPressed: onRefresh), IconButton(icon: const Icon(Icons.place), onPressed: () async { if (onChangeCoords != null) await onChangeCoords!(); })]),
          ]),
          const SizedBox(height: 8),
          if (forecast.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Không có dữ liệu thời tiết', style: TextStyle(color: Colors.grey[700])))
          else
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: forecast.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final day = forecast[i];
                  return InkWell(
                    onTap: () => onShowHourly(day),
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
          if (updatedAt != null) Text('Cập nhật: ${updatedAt.toString()}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ]),
      ),
    );
  }
}
