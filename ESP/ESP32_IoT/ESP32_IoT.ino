#include <ESP8266WiFi.h>
#include <PubSubClient.h>
#include <WiFiManager.h>

const char* mqttServer = "你的公网IP";
const int mqttPort = 1883;
const char* mqttUser = "iot_admin";
const char* mqttPwd = "iot_123456";
const char* mqttClientId = "ESP8266_DEVICE_001";
const char* subTopic = "iot/device/001/control";
const char* pubTopic = "iot/device/001/state";

WiFiClient espClient;
PubSubClient client(espClient);
WiFiManager wm;
#define RELAY_PIN D4

void callback(char* topic, byte* payload, unsigned int length) {
  String cmd = "";
  for (int i = 0; i < length; i++) cmd += (char)payload[i];
  cmd.trim();
  if (cmd == "ON") {
    digitalWrite(RELAY_PIN, LOW);
    client.publish(pubTopic, "ON");
  } else if (cmd == "OFF") {
    digitalWrite(RELAY_PIN, HIGH);
    client.publish(pubTopic, "OFF");
  }
}

void reconnect() {
  while (!client.connected()) {
    if (client.connect(mqttClientId, mqttUser, mqttPwd)) {
      client.subscribe(subTopic);
    } else {
      delay(5000);
    }
  }
}

void setup() {
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, HIGH);
  Serial.begin(115200);
  if (!wm.autoConnect("IoTConfig")) ESP.restart();
  client.setServer(mqttServer, mqttPort);
  client.setCallback(callback);
}

void loop() {
  if (!client.connected()) reconnect();
  client.loop();
}