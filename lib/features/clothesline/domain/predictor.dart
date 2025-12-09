// Simple rule-based predictor for deciding whether to pull the clothesline IN or OUT.
class Predictor {
  /// Decide the desired position based on sensor inputs.
  /// Returns 'OUT' to pull out, 'IN' to pull in, or null to keep current.
  ///
  /// Optional thresholds can be provided (from Config). If omitted,
  /// sensible defaults are used.
  static String? decide({
    required bool isRaining,
    required int lightLux,
    required double temperatureC,
    required double humidityPercent,
    required double windMps,
    int minLightOut = 600,
    int darkThreshold = 150,
    double maxWindForOut = 8.0,
    double strongWindForIn = 10.0,
    double humidityThreshold = 85.0,
    double tempLowThreshold = 2.0,
  }) {
    // Highest priority: rain
    if (isRaining) return 'IN';

    // Strong wind safety: if wind >= strongWindForIn, pull IN
    if (windMps >= strongWindForIn) return 'IN';

    // If very dark, pull IN
    if (lightLux < darkThreshold) return 'IN';

    // If very bright and mild conditions, prefer OUT
    if (lightLux >= minLightOut && windMps < maxWindForOut) return 'OUT';

    // Temperature/humidity influence: if very humid and warm (higher chance of rain), pull IN
    if (humidityPercent > humidityThreshold && temperatureC >= 18.0) return 'IN';

    // If temperature very low (frost risk), pull IN
    if (temperatureC <= tempLowThreshold) return 'IN';

    // Default: no strong action
    return null;
  }
}
