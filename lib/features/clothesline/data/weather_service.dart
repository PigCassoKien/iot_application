import 'dart:convert';
import 'package:http/http.dart' as http;

/// Enhanced weather client using Open-Meteo (no API key required).
/// - reverse geocoding to get a human-readable location name
/// - hourly and daily forecast (temperatures, precipitation, precipitation_probability)
///
class WeatherService {
  /// Reverse geocode coordinates to a short place name using Open-Meteo Geocoding
  /// Returns null on failure.
  Future<String?> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final uri = Uri.parse(
          'https://geocoding-api.open-meteo.com/v1/reverse?latitude=$latitude&longitude=$longitude&count=1');
      final resp = await http.get(uri);
      if (resp.statusCode != 200) return null;
      final Map<String, dynamic> json = jsonDecode(resp.body);
      final results = json['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;
      final r = results.first as Map<String, dynamic>;
      // Prefer locality -> name
      return (r['name'] as String?) ?? (r['country'] as String?);
    } catch (_) {
      return null;
    }
  }

  /// Fetch detailed forecast including hourly and daily data.
  /// Returns null on failure.
  Future<ForecastResult?> fetchDetailedForecast({
    required double latitude,
    required double longitude,
    int days = 7,
    String timezone = 'auto',
  }) async {
    try {
      final dailyFields = ['temperature_2m_max', 'temperature_2m_min', 'precipitation_sum', 'weathercode'].join(',');
      final hourlyFields = ['temperature_2m', 'precipitation_probability', 'precipitation'].join(',');

      final uri = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=$latitude&longitude=$longitude&daily=$dailyFields&hourly=$hourlyFields&timezone=$timezone&forecast_days=$days');

      final resp = await http.get(uri);
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      // parse hourly
      final hourly = data['hourly'] as Map<String, dynamic>?;
      final hourlyTimes = (hourly?['time'] as List<dynamic>?)?.cast<String>() ?? [];
      final hourlyTemp = (hourly?['temperature_2m'] as List<dynamic>?)?.cast<num>() ?? [];
      final hourlyProb = (hourly?['precipitation_probability'] as List<dynamic>?)?.cast<num>() ?? [];
      final hourlyPrecip = (hourly?['precipitation'] as List<dynamic>?)?.cast<num>() ?? [];

      final hours = <WeatherHour>[];
      for (var i = 0; i < hourlyTimes.length; i++) {
        final dt = DateTime.tryParse(hourlyTimes[i]) ?? DateTime.now();
        hours.add(WeatherHour(
          dateTime: dt,
          temperature: i < hourlyTemp.length ? hourlyTemp[i].toDouble() : double.nan,
          precipitationProbability: i < hourlyProb.length ? hourlyProb[i].toDouble() : 0.0,
          precipitation: i < hourlyPrecip.length ? hourlyPrecip[i].toDouble() : 0.0,
        ));
      }

      // parse daily
      final daily = data['daily'] as Map<String, dynamic>?;
      final dailyTimes = (daily?['time'] as List<dynamic>?)?.cast<String>() ?? [];
      final tmax = (daily?['temperature_2m_max'] as List<dynamic>?)?.cast<num>() ?? [];
      final tmin = (daily?['temperature_2m_min'] as List<dynamic>?)?.cast<num>() ?? [];
      final precipSum = (daily?['precipitation_sum'] as List<dynamic>?)?.cast<num>() ?? [];
      final codes = (daily?['weathercode'] as List<dynamic>?)?.cast<int>() ?? [];

      // Compute per-day precipitation probability from hourly probabilities: use max per day
      final daysList = <WeatherDay>[];
      for (var di = 0; di < dailyTimes.length; di++) {
        final dayDate = DateTime.tryParse(dailyTimes[di]) ?? DateTime.now();
        // collect hours that match this day (UTC/timezone already applied by API)
        final hoursOfDay = hours.where((h) => h.dateTime.year == dayDate.year && h.dateTime.month == dayDate.month && h.dateTime.day == dayDate.day).toList();
        double dayProb = 0.0;
        if (hoursOfDay.isNotEmpty) {
          dayProb = hoursOfDay.map((h) => h.precipitationProbability).reduce((a, b) => a > b ? a : b);
        }

        daysList.add(WeatherDay(
          date: dayDate,
          tempMax: di < tmax.length ? tmax[di].toDouble() : double.nan,
          tempMin: di < tmin.length ? tmin[di].toDouble() : double.nan,
          precipitationSum: di < precipSum.length ? precipSum[di].toDouble() : 0.0,
          precipitationProbability: dayProb,
          weatherCode: di < codes.length ? codes[di] : 0,
        ));
      }

      // reverse geocode name (best-effort)
      String? place = await reverseGeocode(latitude: latitude, longitude: longitude);

      return ForecastResult(locationName: place, daily: daysList, hourly: hours);
    } catch (_) {
      return null;
    }
  }
}

class ForecastResult {
  final String? locationName;
  final List<WeatherDay> daily;
  final List<WeatherHour> hourly;

  ForecastResult({required this.locationName, required this.daily, required this.hourly});
}

class WeatherDay {
  final DateTime date;
  final double tempMax;
  final double tempMin;
  final double precipitationSum;
  final double precipitationProbability; // percent 0..100
  final int weatherCode;

  WeatherDay({
    required this.date,
    required this.tempMax,
    required this.tempMin,
    required this.precipitationSum,
    required this.precipitationProbability,
    required this.weatherCode,
  });

  String get niceDate => '${date.day}/${date.month}';
}

class WeatherHour {
  final DateTime dateTime;
  final double temperature;
  final double precipitationProbability; // percent
  final double precipitation;

  WeatherHour({required this.dateTime, required this.temperature, required this.precipitationProbability, required this.precipitation});

  String get niceHour => '${dateTime.hour.toString().padLeft(2, '0')}:00';
}
