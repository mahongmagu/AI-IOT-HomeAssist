import mqtt from '@ohos/mqtt';
import { BusinessError } from '@ohos.base';

@Entry
@Component
struct IotControlPage {
  // 状态绑定
  @State connectStatus: string = "离线";
  @State deviceStatus: string = "关闭";
  private mqttClient: mqtt.MqttClient | null = null;

  // MQTT配置
  private mqttConfig = {
    host: "你的MQTT服务器公网IP",
    port: 1883,
    username: "iot_admin",
    password: "iot_123456",
    clientId: "HARMONY_APP_" + Date.now(),
    subTopic: "iot/device/001/state",
    pubTopic: "iot/device/001/control"
  }

  build() {
    Column({ space: 30 }) {
      // 连接状态
      Text(`MQTT连接状态：${this.connectStatus}`)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.connectStatus === "在线" ? "#00b42a" : "#ff4d4f")
        .margin({ top: 40 });

      // 设备状态
      Text(`设备状态：${this.deviceStatus}`)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.deviceStatus === "开启" ? "#00b42a" : "#ff4d4f");

      // 控制按钮
      Button("开启设备")
        .width(280)
        .height(70)
        .backgroundColor("#00b42a")
        .fontSize(22)
        .onClick(() => this.sendControlCmd("ON"));

      Button("关闭设备")
        .width(280)
        .height(70)
        .backgroundColor("#ff4d4f")
        .fontSize(22)
        .onClick(() => this.sendControlCmd("OFF"));

      // 语音控制按钮
      Button("语音控制")
        .width(280)
        .height(70)
        .backgroundColor("#1677FF")
        .fontSize(22)
        .onClick(() => this.startVoiceControl());
    }
    .width('100%')
    .padding(20)
    .backgroundColor('#f5f5f5')
    .onAppear(() => this.connectMqttServer());
  }

  // 连接MQTT服务器
  connectMqttServer(): void {
    const options: mqtt.MqttOptions = {
      username: this.mqttConfig.username,
      password: this.mqttConfig.password,
      clientId: this.mqttConfig.clientId
    };

    try {
      this.mqttClient = mqtt.connectMqtt(`mqtt://${this.mqttConfig.host}:${this.mqttConfig.port}`, options);
      
      // 连接成功回调
      this.mqttClient.on('connect', () => {
        this.connectStatus = "在线";
        // 订阅状态主题
        this.mqttClient?.subscribe(this.mqttConfig.subTopic, 0);
      });

      // 接收消息回调
      this.mqttClient.on('message', (topic: string, message: Uint8Array) => {
        const msgStr = String.fromCharCode(...message);
        this.deviceStatus = msgStr === "ON" ? "开启" : "关闭";
      });

      // 连接断开回调
      this.mqttClient.on('close', () => {
        this.connectStatus = "离线";
      });
    } catch (error) {
      console.error("MQTT连接失败", (error as BusinessError).message);
    }
  }

  // 发送控制指令
  sendControlCmd(cmd: string): void {
    if (this.mqttClient && this.connectStatus === "在线") {
      this.mqttClient.publish(this.mqttConfig.pubTopic, new Uint8Array(...cmd.split('').map(item => item.charCodeAt(0))));
    }
  }

  // 语音控制（鸿蒙语音识别）
  startVoiceControl(): void {
    // 鸿蒙语音识别API，需在配置文件开启权限
    try {
      // 语音识别逻辑，识别到关键词后执行对应指令
      // 开启：调用sendControlCmd("ON")
      // 关闭：调用sendControlCmd("OFF")
    } catch (error) {
      console.error("语音识别失败", (error as BusinessError).message);
    }
  }

  // 页面销毁断开连接
  onDisappear(): void {
    this.mqttClient?.disconnect();
    this.mqttClient = null;
  }
}