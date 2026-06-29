#include <ESP8266WiFi.h>
#include <PubSubClient.h>
#include <ESP8266mDNS.h>
#include <WiFiUdp.h>
#include <ArduinoOTA.h>

// WiFi配置
const char* ssid = "xxxx";
const char* password = "xxxxxxx";

// MQTT配置
const char* mqttServer = "192.168.1.40";
const int mqttPort = 1883;
const char* mqttUser = "xxxx";
const char* mqttPassword = "xxxxxxxx";
const char* deviceId = "baomujian-sdj-40858013";  // 设备组ID
const char* unitId = "baomujian-sdj-40858013_kaiguan-2966";  // 设备单元ID

// WiFi和MQTT客户端
WiFiClient espClient;
PubSubClient client(espClient);

// 主题字符串（运行时构建）
String topicControl;
String topicState;

// 引脚定义
const int RELAY_PIN = 2;  // 继电器控制引脚

// 设备状态
String deviceState = "OFF";

// 连接WiFi
void setupWiFi() {
  delay(10);
  Serial.println();
  Serial.print("连接WiFi: ");
  Serial.println(ssid);
  
  WiFi.begin(ssid, password);
  
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  
  Serial.println("");
  Serial.println("WiFi连接成功");
  Serial.println("IP地址: ");
  Serial.println(WiFi.localIP());
}

// 构建主题字符串
void buildTopics() {
  topicControl = String("iotxxx/devicename/") + String(unitId) + "/control";
  topicState = String("iotxxx/devicename/") + String(unitId) + "/state";
}

// 重新连接MQTT
void reconnect() {
  while (!client.connected()) {
    Serial.print("尝试连接MQTT...");
    String clientId = "ESP8266-" + String(random(0xffff), HEX);
    
    if (client.connect(clientId.c_str(), mqttUser, mqttPassword)) {
      Serial.println("MQTT连接成功");
      
      // 订阅控制主题
      client.subscribe(topicControl.c_str());
      Serial.print("已订阅主题: ");
      Serial.println(topicControl);
    } else {
      Serial.print("连接失败, rc=");
      Serial.print(client.state());
      Serial.println(" 5秒后重试");
      delay(5000);
    }
  }
}

// MQTT消息回调
void callback(char* topic, byte* payload, unsigned int length) {
  Serial.print("收到消息 [");
  Serial.print(topic);
  Serial.print("] ");
  
  String message;
  for (int i = 0; i < length; i++) {
    message += (char)payload[i];
  }
  Serial.println(message);
  
  // 处理控制指令
  if (String(topic) == topicControl) {
    if (message == "ON") {
      digitalWrite(RELAY_PIN, HIGH);
      deviceState = "ON";
      Serial.println("继电器已打开");
    } else if (message == "OFF") {
      digitalWrite(RELAY_PIN, LOW);
      deviceState = "OFF";
      Serial.println("继电器已关闭");
    }
    
    // 上报状态
    publishState();
  }
}

// 发布状态
void publishState() {
  if (client.connected()) {
    client.publish(topicState.c_str(), deviceState.c_str());
    Serial.print("发布状态: ");
    Serial.println(deviceState);
  }
}

void setup() {
  // 初始化串口
  Serial.begin(115200);
  delay(10);
  
  // 初始化继电器引脚
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW);
  
  // 连接WiFi
  setupWiFi();
  
  // 构建主题字符串
  buildTopics();
  
  // 配置MQTT
  client.setServer(mqttServer, mqttPort);
  client.setCallback(callback);
  
  // OTA配置
  ArduinoOTA.onStart([]() {
    Serial.println("OTA更新开始");
    // 在OTA更新前关闭继电器
    digitalWrite(RELAY_PIN, LOW);
  });
  
  ArduinoOTA.onEnd([]() {
    Serial.println("\nOTA更新完成");
  });
  
  ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
    Serial.printf("OTA进度: %u%%\r", (progress / (total / 100)));
  });
  
  ArduinoOTA.onError([](ota_error_t error) {
    Serial.printf("OTA错误[%u]: ", error);
    if (error == OTA_AUTH_ERROR) Serial.println("认证失败");
    else if (error == OTA_BEGIN_ERROR) Serial.println("开始失败");
    else if (error == OTA_CONNECT_ERROR) Serial.println("连接失败");
    else if (error == OTA_RECEIVE_ERROR) Serial.println("接收失败");
    else if (error == OTA_END_ERROR) Serial.println("结束失败");
  });
  
  // 启动OTA
  ArduinoOTA.begin();
  
  Serial.println("OTA服务已启动");
  
  // 初始状态上报
  publishState();
}

void loop() {
  // OTA处理
  ArduinoOTA.handle();
  
  // 保持MQTT连接
  if (!client.connected()) {
    reconnect();
  }
  client.loop();
  
  // 定时上报状态（每60秒）
  static unsigned long lastPublish = 0;
  if (millis() - lastPublish > 60000) {
    lastPublish = millis();
    publishState();
  }
}
