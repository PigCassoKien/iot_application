class Config {
  final int minLightOut;              // lux threshold to consider 'bright'
  final int darkThreshold;            // lux threshold considered 'dark'
  final double maxWindForOut;         // m/s allowed for OUT
  final double strongWindForIn;       // m/s that forces IN
  final double humidityThreshold;     // percent above which prefer IN
  final double tempLowThreshold;      // deg C below which prefer IN

  const Config({
    this.minLightOut = 600,
    this.darkThreshold = 150,
    this.maxWindForOut = 8.0,
    this.strongWindForIn = 10.0,
    this.humidityThreshold = 85.0,
    this.tempLowThreshold = 2.0,
  });

  factory Config.fromMap(Map<Object?, Object?> map) {
    // ĐÃ ĐỔI TÊN HÀM: int → toInt, double → toDouble (an toàn tuyệt đối)
    int toInt(Object? v, int d) => v is num ? v.toInt() : d;
    double toDouble(Object? v, double d) => v is num ? v.toDouble() : d;

    return Config(
      minLightOut: toInt(map['minLightOut'], 600),
      darkThreshold: toInt(map['darkThreshold'], 150),
      maxWindForOut: toDouble(map['maxWindForOut'], 8.0),
      strongWindForIn: toDouble(map['strongWindForIn'], 10.0),
      humidityThreshold: toDouble(map['humidityThreshold'], 85.0),
      tempLowThreshold: toDouble(map['tempLowThreshold'], 2.0),
    );
  }
}