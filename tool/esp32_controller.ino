#include &lt;WiFi.h&gt;
// #include &lt;HTTPClient.h&gt;
// #include &lt;ArduinoJson.h&gt;
#include &lt;Firebase_ESP_Client.h&gt;
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"
#include "DHT.h"

#define DHTPIN 4
#define DHTTYPE DHT11
DHT dht(DHTPIN, DHTTYPE);

//================ WIFI &amp; FIREBASE ==================
// #define WIFI_SSID       "TP-Link_E100"
// #define WIFI_PASSWORD   "88888888"

#define WIFI_SSID       "!"
#define WIFI_PASSWORD   "870325188"

#define API_KEY         "AIzaSyDvu_3J6hlQ1JEMcXloVc0E_mHOfVacHw0"
#define DATABASE_URL    "https://clothesline-application-default-rtdb.asia-southeast1.firebasedatabase.app"
#define USER_EMAIL      "hieu@gmail.com"
#define USER_PASSWORD   "123456"

//================ PIN DEFINITIONS ==================
#define LED_PIN         2
#define RAIN_SENSOR_PIN 34      // Chân analog cảm biến mưa (GPIO34 = ADC1_CH6)
#define BUTTON_PIN      19       // Nút bấm vật lý để toggle "có quần áo" (GPIO19)
#define BUTTON_CONTROL  18
//================ STEPPER 28BYJ-48 =================
const int IN1 = 14;
const int IN2 = 12;
const int IN3 = 13;
const int IN4 = 15;
int stepDelay = 4;

const int stepsCount = 8;
const uint8_t stepSeq[stepsCount][4] = {
  {1,0,0,0}, {1,1,0,0}, {0,1,0,0}, {0,1,1,0},
  {0,0,1,0}, {0,0,1,1}, {0,0,0,1}, {1,0,0,1}
};

//================ BIẾN TRẠNG THÁI ==================
bool ledState = false;

bool hasClothes = false;        // &lt;&lt;&lt;&lt; MỚI: Có quần áo trên giá không (người dùng set)
bool isRaining = false;         // Trạng thái mưa hiện tại
unsigned long lastRainCheck = 0;
const long rainCheckInterval = 1000;  // Kiểm tra mưa mỗi 1 giây (ưu tiên cao)
int rackPosition = 0;

// Ngưỡng cảm biến mưa (tùy cảm biến FC-37 hoặc module mưa giọt nước)
// Giá trị analog càng nhỏ → càng ướt
const int RAIN_THRESHOLD = 1500;   // &lt; 2000 = có mưa (bạn test thực tế rồi chỉnh lại)

//================ FIREBASE OBJECTS =================
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

// Weather API (giữ nguyên)
float lat = 10.8231;
float lon = 106.6297;
String weatherURL = "https://api.open-meteo.com/v1/forecast?latitude=" + String(lat) + "&longitude=" + String(lon) +
                    "&current=temperature_2m,relative_humidity_2m";

void setup() {
  Serial.begin(115200);
  dht.begin();

  pinMode(LED_PIN, OUTPUT);
  pinMode(BUTTON_PIN, INPUT_PULLUP);     // Nút bấm có pull-up
  pinMode(BUTTON_CONTROL, INPUT_PULLUP);
  pinMode(RAIN_SENSOR_PIN, INPUT);

  // Stepper pins
  pinMode(IN1, OUTPUT); pinMode(IN2, OUTPUT);
  pinMode(IN3, OUTPUT); pinMode(IN4, OUTPUT);
  allCoilsOff();

  // WiFi &amp; Firebase (giữ nguyên)
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting WiFi");
  while (WiFi.status() != WL_CONNECTED) { Serial.print("."); delay(300); }
  Serial.println("\nWiFi OK IP: " + WiFi.localIP().toString());
config.api_key = API_KEY;
  config.database_url = DATABASE_URL;
  auth.user.email = USER_EMAIL;
  auth.user.password = USER_PASSWORD;

  configTime(7 * 3600, 0, "pool.ntp.org", "time.nist.gov");

  Serial.print("Đợi thời gian NTP...");
  struct tm timeinfo;
  while (!getLocalTime(&timeinfo)) {
    Serial.print(".");
    delay(500);
  }
  Serial.println("OK!");
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  // Đợi đăng nhập Firebase
  while (auth.token.uid == "") { Serial.print("."); delay(500); }
  Serial.println("Firebase OK");

  // Bắt stream từ node /control
  if (!Firebase.RTDB.beginStream(&fbdo, "/control"))
    Serial.println("Stream begin failed!");

  // Khởi tạo giá trị ban đầu trên Firebase
  Firebase.RTDB.setBool(&fbdo, "/control/hasClothes", false);
  Firebase.RTDB.setBool(&fbdo, "/status/isRaining", false);
  Firebase.RTDB.setInt(&fbdo, "/control/stepper", 0);
  Firebase.RTDB.setBool(&fbdo, "/control/led", false);
  Firebase.RTDB.setInt(&fbdo, "/status/rackPosition", rackPosition);
}


void loop() {
  unsigned long now = millis();

  // ================== ƯU TIÊN CAO NHẤT: KIỂM TRA MƯA ==================
  if (now - lastRainCheck >= rainCheckInterval) {
    lastRainCheck = now;
    int rainValue = analogRead(RAIN_SENSOR_PIN);
    bool currentlyRaining = (rainValue > RAIN_THRESHOLD);

    if (currentlyRaining != isRaining) {
      isRaining = currentlyRaining;
      Serial.printf("Cảm biến mưa: %d -> %s\n", rainValue, isRaining ? "CÓ MƯA!" : "KHÔNG MƯA");
      Firebase.RTDB.setBool(&fbdo, "/status/isRaining", isRaining);

      // ==== ƯU TIÊN CAO NHẤT: CÓ MƯA → THU GIÁ VÀO NGAY ====
      if (isRaining && hasClothes && rackPosition == 1) {
        Serial.println("!!! PHÁT HIỆN MƯA - TỰ ĐỘNG THU GIÁ PHƠI VÀO !!!");
        stepMotor(-1, 512 * 15);              // Thu vào 15 vòng (tùy bạn chỉnh)
        rackPosition = 0;
        Firebase.RTDB.setInt(&fbdo, "/status/rackPosition", rackPosition);
        Firebase.RTDB.setInt(&fbdo, "/control/stepper", rackPosition);
      }
      if (!isRaining && hasClothes && rackPosition == 0) {
        Serial.println("!!! TẠNH MƯA - TỰ ĐỘNG PHƠI !!!");
        stepMotor(1, 512 * 15);              // Thu vào 15 vòng (tùy bạn chỉnh)
        rackPosition = 1;
        Firebase.RTDB.setInt(&fbdo, "/status/rackPosition", rackPosition);
        Firebase.RTDB.setInt(&fbdo, "/control/stepper", rackPosition);
      }
    }
  }

  // ================== NÚT BẤM VẬT LÝ TOGGLE "CÓ QUẦN ÁO" ==================
  static bool lastButtonState = HIGH;
  bool buttonState = digitalRead(BUTTON_PIN);
  if (lastButtonState == HIGH && buttonState == LOW) {  // Nhấn nút
    delay(50);  // Debounce
    if (digitalRead(BUTTON_PIN) == LOW) {
      hasClothes = !hasClothes;
      Serial.printf("Nút bấm: Có quần áo = %s\n", hasClothes ? "CÓ" : "KHÔNG");
Firebase.RTDB.setBool(&fbdo, "/control/hasClothes", hasClothes);
    }
  }
  lastButtonState = buttonState;

  // ================== NÚT BẤM VẬT LÝ DIỀU KHIỂN ==================
  static bool lastControlState = HIGH;
  bool buttonControl = digitalRead(BUTTON_CONTROL);
  if (lastControlState == HIGH && buttonControl == LOW) {  // Nhấn nút
    delay(50);  // Debounce
    if (digitalRead(BUTTON_CONTROL) == LOW) {
      if (isRaining && hasClothes && rackPosition == 0) {
        Serial.printf("Đang mưa không được cho quần áo ra\n");
      }
      if (rackPosition == 1) {
        stepMotor(-1, 512 * 15);   // Thu vaof
        rackPosition = 0;
        Firebase.RTDB.setInt(&fbdo, "/status/rackPosition", rackPosition);
        Firebase.RTDB.setInt(&fbdo, "/control/stepper", rackPosition);
      }
      if (rackPosition == 0 && hasClothes && !isRaining) {
        stepMotor(1, 512 * 15);   // Thu vaof
        rackPosition = 1;
        Serial.printf("Đã phơi quần áo ra\n");
        Firebase.RTDB.setInt(&fbdo, "/status/rackPosition", rackPosition);
        Firebase.RTDB.setInt(&fbdo, "/control/stepper", rackPosition);
      }
    }
  }
  lastControlState = buttonControl;

  // ================== FIREBASE STREAM ==================
  if (!Firebase.RTDB.readStream(&fbdo)) {
    Serial.println("Stream error: " + fbdo.errorReason());
  }

  if (fbdo.streamAvailable()) {
    String path = fbdo.dataPath();

    // LED
    if (path == "/led") {
      ledState = fbdo.boolData();
      digitalWrite(LED_PIN, ledState);
      Serial.printf("LED -> %s\n", ledState ? "ON" : "OFF");
    }

    // Người dùng bấm nút trên App để set có quần áo không
    if (path == "/hasClothes") {
      hasClothes = fbdo.boolData();
      Firebase.RTDB.setBool(&fbdo, "/status/hasClothes", hasClothes); // đồng bộ lại node status
      Serial.printf("App set: Có quần áo = %s\n", hasClothes ? "CÓ" : "KHÔNG");
    }

    // Lệnh vị trí mong muốn từ App (0 = thu vào, 1 = đưa ra)
    if (path == "/stepper") {
      int desiredPosition = fbdo.intData();
      if (desiredPosition != rackPosition) {
        if (desiredPosition == 1 && rackPosition == 0) {
          if (!hasClothes) {
            Serial.println("Không có quần áo trên giá, không cho đưa ra!");
            Firebase.RTDB.setInt(&fbdo, "/control/stepper", rackPosition);
          } else if (isRaining) {
            Serial.println("Đang mưa! Bỏ qua lệnh thủ công.");
            Firebase.RTDB.setInt(&fbdo, "/control/stepper", rackPosition);
          } else {
            stepMotor(1, 512 * 15);   // Đưa ra
            rackPosition = 1;
            Firebase.RTDB.setInt(&fbdo, "/status/rackPosition", rackPosition);
            Firebase.RTDB.setInt(&fbdo, "/control/stepper", rackPosition);
          }
        } else if (desiredPosition == 0 && rackPosition == 1) {
          stepMotor(-1, 512 * 15);   // Thu vào
          rackPosition = 0;
          Firebase.RTDB.setInt(&fbdo, "/status/rackPosition", rackPosition);
          Firebase.RTDB.setInt(&fbdo, "/control/stepper", rackPosition);
        } else {
          // Vị trí không hợp lệ hoặc đã ở vị trí đó
          Firebase.RTDB.setInt(&fbdo, "/control/stepper", rackPosition);
        }
      } else {
        // Đã ở vị trí mong muốn
        Firebase.RTDB.setInt(&fbdo, "/control/stepper", rackPosition);
      }
    }
  }

  // ================== DHT11 &amp; Weather (giữ nguyên) ==================
  static unsigned long lastDHT = 0;
  if (now - lastDHT > 5000) {
    lastDHT = now;
    float t = dht.readTemperature();
    float h = dht.readHumidity();
    if (!isnan(t) && !isnan(h)) {
      Firebase.RTDB.setFloat(&fbdo, "/sensor/temp", t);
      Firebase.RTDB.setFloat(&fbdo, "/sensor/humidity", h);
    }
  }

  // static unsigned long lastWeather = 0;
  // if (now - lastWeather > 600000) {
  //   lastWeather = now;
  //   getWeatherAndUpload();
  // }
}

// ====================== STEPPER FUNCTIONS ======================
void allCoilsOff() {
  digitalWrite(IN1, LOW); digitalWrite(IN2, LOW);
  digitalWrite(IN3, LOW); digitalWrite(IN4, LOW);
}

void doStep(int idx) {
  digitalWrite(IN1, stepSeq[idx][0]);
  digitalWrite(IN2, stepSeq[idx][1]);
  digitalWrite(IN3, stepSeq[idx][2]);
  digitalWrite(IN4, stepSeq[idx][3]);
}

void stepMotor(int dir, int steps) {
  if (dir == 0) return;
  int idx = 0;
  for (int i = 0; i < steps; i++) {
    doStep(idx);
    idx = (idx + (dir > 0 ? 1 : -1) + stepsCount) % stepsCount;
    delay(stepDelay);
  }
  allCoilsOff();
}

// ====================== WEATHER API ======================
// void getWeatherAndUpload() {
//   HTTPClient http;
//   http.begin(weatherURL);
//   int code = http.GET();
//   if (code == 200) {
//     DynamicJsonDocument doc(2048);
//     deserializeJson(doc, http.getString());
//     float temp = doc["current"]["temperature_2m"];
//     float hum = doc["current"]["relative_humidity_2m"];
//     Firebase.RTDB.setFloat(&fbdo, "/weather/temp", temp);
//     Firebase.RTDB.setFloat(&fbdo, "/weather/humidity", hum);
//   }
//   http.end();
// }