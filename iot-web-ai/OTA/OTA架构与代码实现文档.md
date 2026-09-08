# ESP12F AC01 OTA 架构、流程与代码实现文档

## 一、系统概述

### 1.1 设计背景

ESP12F 运行在 DeepSleep 低功耗模式，睡眠期间 CPU 和射频完全断电，无法进行任何网络通信。OTA（Over-The-Air）固件升级只能利用每次唤醒后的短暂在线窗口完成。本系统设计了两种互补的 OTA 机制：

| 机制 | 触发方式 | 适用场景 |
|---|---|---|
| 方式一：HTTP 自动拉取 | 每次唤醒自动检查版本 | 日常迭代、批量升级、无人值守 |
| 方式二：MQTT 触发 ArduinoOTA | 手动发布 retained `OTA` 指令 | 现场调试、无固件服务器时临时升级 |

### 1.2 架构总览

```
┌──────────────────────────────────────────────────────────────┐
│                    iot-web-ai/v11 服务端                      │
│                                                              │
│  server-control-tcp.js (端口6002)  server-config.js (端口6001)│
│        │                                  │                  │
│        └──────────┬───────────────────────┘                  │
│                   │ app.use(require('./OTA/ota-routes'))      │
│                   ▼                                          │
│          OTA/ota-routes.js （共享路由模块）                    │
│          ├─ GET /ota/:deviceGroupId/version     返回版本号    │
│          └─ GET /ota/:deviceGroupId/firmware.bin 返回固件文件 │
│                                                              │
│  OTA/firmware/<设备组ID>/                                    │
│    ├─ firmware.bin   固件文件（Arduino IDE 导出）             │
│    └─ version        版本号文件（纯文本，如 1.4.0）           │
└──────────────────────────────────────────────────────────────┘
          ▲                              ▲
          │ HTTP GET                     │ MQTT retained "OTA"
          │ (每次唤醒自动)                │ (手动触发)
┌─────────┴──────────────────────────────┴─────────────────────┐
│                   ESP12F (AC01) 设备端                        │
│                                                              │
│  唤醒 → connectWifi → checkHttpOta() ──→ 方式一自动升级       │
│              │           │                                   │
│              │     无更新则继续                               │
│              ▼                                               │
│         connectMqtt → callback收到"OTA" → enterOtaMode()     │
│                                    ──→ 方式二手动升级         │
│              │                                               │
│              ▼                                               │
│         正常温控流程 → DeepSleep                              │
└──────────────────────────────────────────────────────────────┘
```

---

## 二、服务端实现

### 2.1 目录结构

```
iot-web-ai/v11/
├─ server-config.js         配置服务（端口6001），挂载OTA路由
├─ server-control-tcp.js    控制服务（端口6002），挂载OTA路由 ★设备使用
├─ .env                     端口配置: CONTROL_SERVICE_PORT=6002, SERVER_IP=192.168.1.149
└─ OTA/
   ├─ ota-routes.js         共享Express路由模块
   └─ firmware/
      └─ keting-AC-23343313/              按设备组ID建立子目录
         ├─ firmware.bin                  固件文件（统一命名firmware.bin）
         └─ version                       版本号文件（如 1.4.0）
```

> **设计要点**：固件按**设备组ID**（如 `keting-AC-23343313`）建立独立子目录，bin 文件统一命名为 `firmware.bin`。新增设备只需在 `firmware/` 下创建对应设备组ID目录并放入 `firmware.bin` + `version` 文件，服务端零改动。

### 2.2 ota-routes.js 路由模块

独立的 Express Router 模块，被两个服务文件共同挂载，避免代码重复。

**源文件**：[ota-routes.js](file:///d:/.openclaw/workspace/iot-web-ai/v11/OTA/ota-routes.js)

| 接口 | 方法 | 路径 | 返回 | 代码行 |
|---|---|---|---|---|
| 版本检查 | GET | `/ota/:deviceGroupId/version` | 纯文本版本号（如 `1.4.0`） | [L39-53](file:///d:/.openclaw/workspace/iot-web-ai/v11/OTA/ota-routes.js#L39-L53) |
| 固件下载 | GET | `/ota/:deviceGroupId/firmware.bin` | 二进制流（application/octet-stream） | [L56-72](file:///d:/.openclaw/workspace/iot-web-ai/v11/OTA/ota-routes.js#L56-L72) |

**安全防护**：

| 防护 | 实现 | 代码行 |
|---|---|---|
| 路径穿越攻击 | `isValidDeviceGroupId()` 正则校验 `/^[A-Za-z0-9_-]+$/`，拒绝含 `../` 的恶意路径 | [L34-36](file:///d:/.openclaw/workspace/iot-web-ai/v11/OTA/ota-routes.js#L34-L36) |
| 大文件流式传输 | `fs.createReadStream().pipe(res)`，避免内存中加载完整固件 | [L70](file:///d:/.openclaw/workspace/iot-web-ai/v11/OTA/ota-routes.js#L70) |
| Content-Length 头 | 预先 `fs.stat()` 获取文件大小，设置 Content-Length 供设备进度显示 | [L68-69](file:///d:/.openclaw/workspace/iot-web-ai/v11/OTA/ota-routes.js#L68-L69) |

### 2.3 服务挂载

两个服务文件各用一行代码挂载同一路由模块：

| 服务文件 | 挂载代码 | 端口 |
|---|---|---|
| [server-config.js](file:///d:/.openclaw/workspace/iot-web-ai/v11/server-config.js#L766) | `app.use(require('./OTA/ota-routes'))` | 6001（CONFIG_SERVICE_PORT） |
| [server-control-tcp.js](file:///d:/.openclaw/workspace/iot-web-ai/v11/server-control-tcp.js#L604) | `app.use(require('./OTA/ota-routes'))` | 6002（CONTROL_SERVICE_PORT）★ |

> 设备端默认使用 6002 端口（控制服务），因控制服务常驻运行且与设备交互最密切。6001 端口同样可用，作为备用。

---

## 三、设备端实现

### 3.1 配置参数

**源文件**：[ESP12_IoT_AC01.ino](file:///d:/.openclaw/workspace/ESP/ESP12_IoT_AC01/ESP12_IoT_AC01.ino)

| 参数 | 值 | 说明 | 代码行 |
|---|---|---|---|
| `FW_VERSION` | `"1.4.0"` | 当前固件版本号，发布新固件时需同步递增 | [L61](file:///d:/.openclaw/workspace/ESP/ESP12_IoT_AC01/ESP12_IoT_AC01.ino#L61) |
| `otaVersionUrl` | `http://192.168.1.149:6002/ota/keting-AC-23343313/version` | 版本检查接口（使用设备组ID） | [L62](file:///d:/.openclaw/workspace/ESP/ESP12_IoT_AC01/ESP12_IoT_AC01.ino#L62) |
| `otaBinUrl` | `http://192.168.1.149:6002/ota/keting-AC-23343313/firmware.bin` | 固件下载地址（使用设备组ID） | [L63](file:///d:/.openclaw/workspace/ESP/ESP12_IoT_AC01/ESP12_IoT_AC01.ino#L63) |
| `OTA_HOLD_TIMEOUT_MS` | `180000`（3分钟） | 方式二保持唤醒的超时时间 | — |

> URL 中的 IP（192.168.1.149）取自 `.env` 的 `SERVER_IP`，端口（6002）取自 `.env` 的 `CONTROL_SERVICE_PORT`。URL 路径中的 `keting-AC-23343313` 为**设备组ID**（非单元ID）。

### 3.2 方式一：HTTP 自动拉取升级

**核心函数**：`checkHttpOta()`

**调用位置**：setup() 步骤 4（WiFi 连接成功后、MQTT 连接之前）

**流程**：

```
checkHttpOta()
  │
  ├─ HTTP GET otaVersionUrl
  │    ├─ 服务器不可达(非200) → 打印日志，跳过检查，继续正常流程
  │    └─ 返回版本号字符串（如 "1.4.0"）
  │
  ├─ compareVersion(remoteVersion, FW_VERSION)
  │    ├─ remoteVersion <= FW_VERSION → "已是最新版本"，跳过
  │    └─ remoteVersion >  FW_VERSION → 发现新版本
  │
  └─ ESPhttpUpdate.update(wc, otaBinUrl)
       ├─ HTTP_UPDATE_OK    → 下载+写入Flash+自动重启（不执行后续代码）
       ├─ HTTP_UPDATE_FAILED → 打印错误，继续正常流程
       └─ HTTP_UPDATE_NO_UPDATES → 继续正常流程
```

**版本号比较函数**：`compareVersion()`

支持 `x.y.z` 格式的语义化版本比较，用 `sscanf` 解析三段整数逐段比较。

**容错设计**：

| 异常场景 | 处理方式 |
|---|---|
| OTA服务器未启动 | HTTP GET 返回连接失败，打印日志后跳过，温控不受影响 |
| version文件不存在 | HTTP 404，跳过 |
| firmware.bin不存在 | ESPhttpUpdate 返回 HTTP_UPDATE_FAILED，继续正常流程 |
| 下载中断 | ESP8266 双分区机制，旧固件完好，下次唤醒重试 |
| 版本号相同 | 跳过，耗时约1秒 |
| bin文件版本号与FW_VERSION不一致 | 设备刷入旧固件后重启，compareVersion仍判定需升级 → 无限循环。**必须确保bin是最新源码编译的** |

### 3.3 方式二：MQTT 触发 ArduinoOTA 手动升级

**触发机制**：通过 MQTT retained 消息传递 OTA 指令，设备睡觉时指令不会丢失。

**指令接收**：MQTT callback

```cpp
} else if (message == "OTA") {
    // 收到OTA指令：清除retained命令 + 标记OTA模式
    client.publish(topicKg01Control.c_str(), "", true);  // 发布空payload清除retained
    g_otaMode = true;
}
```

**核心函数**：`enterOtaMode()`

**调用位置**：setup() 步骤 12（RTC保存之后、DeepSleep之前）

**流程**：

```
MQTTX发布 retained "OTA" 到 kg01/control
  │
  └─ 设备下次唤醒 → connectMqtt → 订阅kg01/control → 立即收到retained消息
       │
       ├─ callback: message=="OTA"
       │    ├─ 发布空payload清除retained（防止下次唤醒重复进入）
       │    └─ g_otaMode = true
       │
       └─ setup步骤12: g_otaMode==true → enterOtaMode()
            │
            ├─ 发布kg01状态"OTA"（前端可见设备处于升级模式）
            ├─ ArduinoOTA.setHostname("esp12f-ac01")
            ├─ 注册 onStart/onProgress/onEnd/onError 回调
            ├─ ArduinoOTA.begin()
            │
            ├─ 循环3分钟:
            │    ├─ ArduinoOTA.handle()  等待Arduino IDE上传
            │    └─ client.loop()        保持MQTT在线
            │
            ├─ Arduino IDE上传完成 → 自动重启加载新固件
            └─ 3分钟超时 → 发布kg01状态"OFF" → 继续进入DeepSleep
```

**ArduinoOTA 回调说明**：

| 回调 | 功能 |
|---|---|
| `onStart` | 区分 U_FLASH（程序固件）和 U_FS（文件系统），串口打印 |
| `onProgress` | 实时打印上传百分比 |
| `onEnd` | 打印完成消息，设备自动重启 |
| `onError` | 5种错误类型中文提示（认证/开始/连接/接收/结束） |

---

## 四、设备端固件升级代码示例详解

本章对设备端 OTA 升级的完整代码进行逐段解析，可作为移植到其他 ESP 设备的参考模板。

### 4.1 头文件引入与配置

```cpp
#include <ESP8266HTTPClient.h>   // HTTP客户端，用于GET版本号接口
#include <ESP8266httpUpdate.h>   // HTTP OTA升级核心库，负责下载+写入Flash+重启
#include <ArduinoOTA.h>          // Arduino IDE网络端口直传（方式二）
```

配置常量：

```cpp
// OTA地址 = .env的SERVER_IP + CONTROL_SERVICE_PORT
// URL路径使用设备组ID（如 keting-AC-23343313），不是单元ID
const char* FW_VERSION    = "1.4.0";  // 当前固件版本号，发布新固件时递增
const char* otaVersionUrl = "http://192.168.1.149:6002/ota/keting-AC-23343313/version";
const char* otaBinUrl     = "http://192.168.1.149:6002/ota/keting-AC-23343313/firmware.bin";
```

> `FW_VERSION` 必须与服务器 `version` 文件保持同步：发布新固件时两者一起递增，否则设备每次唤醒都会重复下载同一固件。

### 4.2 版本号比较函数

采用语义化版本（Semantic Versioning）的 `x.y.z` 格式比较，逐段解析三段整数：

```cpp
// 版本号比较: a>b返回1, a==b返回0, a<b返回-1（支持x.y.z格式）
int compareVersion(const String& a, const String& b) {
  int av[3] = {0}, bv[3] = {0};
  sscanf(a.c_str(), "%d.%d.%d", &av[0], &av[1], &av[2]);
  sscanf(b.c_str(), "%d.%d.%d", &bv[0], &bv[1], &bv[2]);
  for (int i = 0; i < 3; i++) {
    if (av[i] != bv[i]) return (av[i] > bv[i]) ? 1 : -1;
  }
  return 0;
}
```

| 调用 | 返回 | 含义 |
|---|---|---|
| `compareVersion("1.4.0", "1.2.0")` | 1 | 服务器版本更高，需要升级 |
| `compareVersion("1.4.0", "1.4.0")` | 0 | 版本相同，跳过 |
| `compareVersion("1.2.0", "1.4.0")` | -1 | 本地版本更高（异常情况），跳过 |

### 4.3 方式一：HTTP 自动拉取完整代码

每次唤醒时调用，检查服务器固件版本，发现新版本自动下载升级。设计为**全容错**——任何异常都静默跳过，不影响正常温控流程。

```cpp
void checkHttpOta() {
  WiFiClient wc;
  HTTPClient http;

  // 第1步：请求版本号接口
  Serial.print("检查固件版本...");
  if (!http.begin(wc, otaVersionUrl)) {
    Serial.println("URL无效，跳过OTA检查");
    return;
  }
  int code = http.GET();
  if (code != 200) {
    http.end();
    Serial.printf("服务器不可达(%d)，跳过OTA检查\n", code);
    return;
  }
  String remoteVersion = http.getString();
  remoteVersion.trim();
  http.end();

  // 第2步：版本比对
  Serial.print("服务器版本 ");
  Serial.print(remoteVersion);
  Serial.print("，本地版本 ");
  Serial.println(FW_VERSION);

  if (compareVersion(remoteVersion, FW_VERSION) <= 0) {
    Serial.println("已是最新版本，无需升级");
    return;
  }

  // 第3步：下载固件并写入Flash
  Serial.println("发现新版本，开始下载固件升级...");
  t_httpUpdate_return ret = ESPhttpUpdate.update(wc, otaBinUrl);
  // ⚠️ 升级成功时ESP8266httpUpdate直接重启，以下代码不会执行

  // 第4步：处理升级失败的情况
  switch (ret) {
    case HTTP_UPDATE_FAILED:
      Serial.printf("固件下载失败: %s，继续正常流程\n",
                    ESPhttpUpdate.getLastErrorString().c_str());
      break;
    case HTTP_UPDATE_NO_UPDATES:
      Serial.println("服务器无可用更新，继续正常流程");
      break;
    case HTTP_UPDATE_OK:
      Serial.println("升级成功，重启中...");
      break;
  }
}
```

**关键设计解读**：

| 设计点 | 原因 |
|---|---|
| `http.end()` 在 GET 后立即调用 | 版本检查只需返回体字符串，后续下载是独立的 HTTP 连接，及时释放避免连接泄漏 |
| `remoteVersion.trim()` | version 文件末尾可能有换行符，不 trim 会导致 sscanf 解析异常 |
| `compareVersion() <= 0` 而非 `== 0` | 同时处理"版本相同"和"服务器版本更低"（异常情况），都跳过不降级 |
| `ESPhttpUpdate.update()` 后的 switch | 升级成功时函数内部直接 `ESP.restart()`，switch 只处理失败分支 |
| 所有异常路径都 `return` | 保证 checkHttpOta 不影响后续 MQTT 连接和温控流程 |

### 4.4 方式二：MQTT 触发 ArduinoOTA 完整代码

#### 4.4.1 MQTT 回调：接收 OTA 指令

```cpp
if (topicStr == topicKg01Control) {
  if (message == "QUERY") {
    Serial.println("收到QUERY指令，上报kg01当前状态");
  } else if (message == "OTA") {
    Serial.println("收到OTA指令，本唤醒周期将保持在线等待固件上传");
    client.publish(topicKg01Control.c_str(), "", true);  // 清除retained
    g_otaMode = true;
  }
}
```

**为什么要清除 retained**：MQTT retained 消息会一直存储在 broker 中，每次新订阅都会收到。如果不清除，设备每次唤醒都会进入 OTA 模式，无法正常温控。发布**空 payload + retained=true** 是 MQTT 协议规定的清除 retained 消息标准方法。

#### 4.4.2 enterOtaMode 函数：保持唤醒等待上传

```cpp
#define OTA_HOLD_TIMEOUT_MS 180000UL  // 3分钟超时

void enterOtaMode() {
  Serial.println("\n==== 进入OTA模式，保持唤醒3分钟等待固件上传 ====");
  Serial.print("OTA主机名: esp12f-ac01  IP: ");
  Serial.println(WiFi.localIP());
  Serial.println("请在Arduino IDE 工具->端口 选择网络端口上传固件");

  publishKg01State("OTA");

  ArduinoOTA.setHostname("esp12f-ac01");

  ArduinoOTA.onStart([]() {
    String type = (ArduinoOTA.getCommand() == U_FLASH) ? "程序固件" : "文件系统";
    Serial.println("OTA开始上传: " + type);
  });

  ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
    Serial.printf("OTA进度: %u%%\r", (progress * 100) / total);
  });

  ArduinoOTA.onEnd([]() {
    Serial.println("\nOTA上传完成，重启加载新固件...");
  });

  ArduinoOTA.onError([](ota_error_t error) {
    Serial.printf("\nOTA错误[%u]: ", error);
    if (error == OTA_AUTH_ERROR)    Serial.println("认证失败");
    else if (error == OTA_BEGIN_ERROR)   Serial.println("开始失败");
    else if (error == OTA_CONNECT_ERROR) Serial.println("连接失败");
    else if (error == OTA_RECEIVE_ERROR) Serial.println("接收失败");
    else if (error == OTA_END_ERROR)     Serial.println("结束失败");
  });

  ArduinoOTA.begin();

  unsigned long start = millis();
  while (millis() - start < OTA_HOLD_TIMEOUT_MS) {
    ArduinoOTA.handle();
    client.loop();
    delay(10);
  }

  Serial.println("\nOTA窗口超时，未收到固件");
  publishKg01State("OFF");
}
```

**关键设计解读**：

| 设计点 | 原因 |
|---|---|
| `ArduinoOTA.handle()` 在 while 循环中频繁调用 | OTA 库基于 mDNS+TCP，需要频繁处理网络事件 |
| `client.loop()` 与 `ArduinoOTA.handle()` 并行 | 保持 MQTT 连接，前端可实时看到设备"OTA"状态 |
| `delay(10)` 而非 `delay(100)` | OTA 上传对实时性要求高，10ms 是经验值 |
| `onProgress` 用 `\r` 不换行 | 串口终端中同一行刷新百分比，形成进度条效果 |
| 超时后 `publishKg01State("OFF")` | 前端状态从"OTA"恢复为"OFF" |

### 4.5 心跳发布与失败重试

固件 1.4.0 新增了 `publishKg01State` 返回值检查和心跳重试机制，确保每次唤醒都能刷新服务端活跃时间：

```cpp
// 发布kg01状态（返回是否成功；失败时输出失败原因用于调试）
bool publishKg01State(const String& state) {
  if (!client.connected()) {
    Serial.printf("发布kg01状态失败: MQTT未连接 (state=%d)\n", client.state());
    return false;
  }
  bool ok = client.publish(topicKg01State.c_str(), state.c_str());
  if (ok) {
    Serial.print("发布kg01状态: ");
    Serial.println(state);
  } else {
    Serial.printf("发布kg01状态失败: publish返回false (state=%d, buffer剩余=%u)\n",
                  client.state(), client.getBufferSize());
  }
  return ok;
}
```

心跳发布（setup 步骤 7.5，每周期执行）：

```cpp
// 7.5 心跳：每周期发布kg01状态，刷新服务端活跃时间
// 状态跟随triggerState：TRIG_HIGH=ON，其他=OFF
// 失败时重试2次（PubSubClient偶发返回false）
{
  const char* heartbeatState = (manualMode == MODE_MANUAL_ON || triggerState == TRIG_HIGH) ? "ON" : "OFF";
  bool hbOk = false;
  for (int attempt = 0; attempt < 3 && !hbOk; attempt++) {
    if (attempt > 0) {
      Serial.printf("心跳发布重试 %d/2...\n", attempt);
      client.loop();
      delay(50);
    }
    hbOk = publishKg01State(heartbeatState);
  }
  if (!hbOk) {
    Serial.println("⚠️ 心跳发布失败，本次唤醒无法刷新在线状态（下周期再试）");
  }
}
```

> **设计原因**：PubSubClient 的 `publish()` 偶发返回 false（前序数据包未 flush），不加返回值检查会误以为发布成功。重试 2 次覆盖瞬时失败，3 次全失败则静默跳过等待下个唤醒周期。

### 4.6 setup 主流程中的调用位置

```cpp
void setup() {
  // ... 恢复RTC、构建主题 ...

  // 步骤3：连接WiFi
  if (!connectWifi()) { goto enterSleep; }

  // ★ 步骤4：方式一 - HTTP自动拉取（WiFi之后、MQTT之前）
  checkHttpOta();  // 升级成功直接重启；无更新则继续

  // 步骤5：连接MQTT
  if (!connectMqtt()) { goto enterSleep; }

  // 步骤6-7：参数同步、发布参数
  // ★ 步骤7.5：心跳发布（每周期发布kg01状态保持在线）
  // 步骤8-10：温度查询、滞回温控、舵机动作
  // 步骤11：保存RTC

  // ★ 步骤12：方式二 - MQTT触发的ArduinoOTA
  if (g_otaMode) { enterOtaMode(); }

  // 步骤13-14：关闭WiFi、进入DeepSleep
}
```

**两种机制的触发时序对比**：

| 维度 | 方式一 checkHttpOta() | 方式二 enterOtaMode() |
|---|---|---|
| 触发位置 | 步骤4（MQTT之前） | 步骤12（DeepSleep之前） |
| 触发条件 | 每次唤醒无条件执行 | g_otaMode==true（MQTT收到OTA指令） |
| 依赖 | 仅需WiFi | 需WiFi + MQTT |
| 耗时 | 约1秒（无更新时） | 3分钟（等待上传） |
| 成功后行为 | 直接重启 | 直接重启 |
| 失败后行为 | 继续正常流程 | 继续进入DeepSleep |

### 4.7 串口日志示例

#### 方式一：发现新版本并升级

```
==== AC01 DeepSleep Wakeup ====
从RTC内存恢复参数成功，当前模式: 自动温控
连接WiFi................................ 成功
检查固件版本...服务器版本 1.4.0，本地版本 1.2.0
发现新版本，开始下载固件升级...
（设备自动重启，串口可能短暂中断）

==== AC01 DeepSleep Wakeup ====
从RTC内存恢复参数成功，当前模式: 自动温控
连接WiFi................................ 成功
检查固件版本...服务器版本 1.4.0，本地版本 1.4.0
已是最新版本，无需升级
连接MQTT... 成功
（继续正常温控流程）
```

#### 方式一：服务器不可达（静默跳过）

```
检查固件版本...服务器不可达(-1)，跳过OTA检查
连接MQTT... 成功
（继续正常温控流程，不受影响）
```

#### 方式一：firmware.bin 不存在（404）

```
检查固件版本...服务器版本 1.4.0，本地版本 1.2.0
发现新版本，开始下载固件升级...
固件下载失败: HTTP Response Error (404)，继续正常流程
连接MQTT... 成功
（继续正常温控流程）
```

#### 方式二：MQTT触发手动升级

```
==== AC01 DeepSleep Wakeup ====
（步骤1-11正常执行...）
收到消息 [iot/device/keting-AC-23343313_kg01-6432/control] OTA
收到OTA指令，本唤醒周期将保持在线等待固件上传
参数已保存到RTC内存

==== 进入OTA模式，保持唤醒3分钟等待固件上传 ====
OTA主机名: esp12f-ac01  IP: 192.168.1.142
请在Arduino IDE 工具->端口 选择网络端口上传固件
（Arduino IDE点击上传后...）
OTA开始上传: 程序固件
OTA进度: 10%
OTA进度: 45%
OTA进度: 78%
OTA进度: 100%
OTA上传完成，重启加载新固件...
（设备自动重启）
```

#### 心跳发布失败重试

```
已发布所有参数到MQTT服务端
发布kg01状态失败: publish返回false (state=3, buffer剩余=256)
心跳发布重试 1/2...
发布kg01状态: OFF
（重试成功，继续正常流程）
```

---

## 五、完整工作流程

### 5.1 唤醒周期主流程（含OTA + 心跳）

```
==== AC01 DeepSleep Wakeup ====
  │
  ├─ 1. restoreFromRtc()           从RTC内存恢复参数（含上次触发状态）
  ├─ 2. buildTopics()              构建MQTT主题字符串
  ├─ 3. connectWifi()              连接WiFi（10秒超时）
  │     └─ 失败 → goto enterSleep
  │
  ├─ 4. checkHttpOta()             ★ 方式一：HTTP自动拉取检查
  │     ├─ 发现新版本 → 下载升级 → 自动重启（流程终止）
  │     └─ 无更新/不可达 → 继续
  │
  ├─ 5. connectMqtt()              连接MQTT并订阅所有主题
  │     └─ 失败 → closeWifi → goto enterSleep
  │
  ├─ 6. processMqttMessages(2000)  等待2秒接收参数retained消息
  ├─ 7. publishAllParams()         发布参数到MQTT同步前端
  ├─ 7.5. 心跳发布kg01状态          ★ 每周期刷新服务端活跃时间
  │       └─ 失败重试2次，全失败则下周期再试
  ├─ 8. publish("QUERY")           发送温度查询指令
  ├─ 9. processMqttMessages(5000)  等待5秒接收温度响应
  ├─ 10. 温度判断 → 舵机动作        滞回控制逻辑（>=上限/<=下限）
  ├─ 11. saveToRtc()               保存参数到RTC内存
  │
  ├─ 12. if(g_otaMode)             ★ 方式二：MQTT触发的手动OTA
  │     └─ enterOtaMode()          保持唤醒3分钟等待上传
  │          ├─ 上传完成 → 自动重启
  │          └─ 超时 → 继续
  │
  ├─ 13. closeWifi()               关闭WiFi降低功耗
  └─ 14. ESP.deepSleep()           进入DeepSleep，下个周期唤醒
```

### 5.2 方式一：发布新固件操作流程（全自动）

```
步骤1: Arduino IDE → 项目 → 导出已编译的二进制文件 → 得到 .bin

步骤2: 复制bin文件到固件目录（按设备组ID建子目录，bin统一命名firmware.bin）:
  OTA/firmware/keting-AC-23343313/firmware.bin

步骤3: 递增版本号文件:
  OTA/firmware/keting-AC-23343313/version
  内容从 1.4.0 改为 1.5.0

步骤4: 同步设备端代码的 FW_VERSION 为 1.5.0（防止下轮重复升级）

步骤5: 重启Node服务（确保OTA路由加载最新目录结构）

步骤6: 等待设备唤醒（最迟一个唤醒周期，默认≤5分钟）

设备串口预期输出:
  检查固件版本...服务器版本 1.5.0，本地版本 1.4.0
  发现新版本，开始下载固件升级...
  （自动重启）
  ==== AC01 DeepSleep Wakeup ====
  检查固件版本...服务器版本 1.5.0，本地版本 1.5.0
  已是最新版本，无需升级
```

### 5.3 方式二：MQTT触发手动升级操作流程

```
步骤1: MQTTX发布（勾选Retain）:
  主题: iot/device/keting-AC-23343313_kg01-6432/control
  消息: OTA

步骤2: 等待设备唤醒（最迟一个唤醒周期）
  设备串口输出:
  收到消息 [...] OTA
  收到OTA指令，本唤醒周期将保持在线等待固件上传
  ==== 进入OTA模式，保持唤醒3分钟等待固件上传 ====
  OTA主机名: esp12f-ac01  IP: 192.168.x.x

步骤3: Arduino IDE → 工具 → 端口 → 选择网络端口 "esp12f-ac01" → 上传

步骤4: 上传完成自动重启，串口输出:
  OTA进度: 100%
  OTA上传完成，重启加载新固件...
```

---

## 六、两种方式对比

| 维度 | 方式一：HTTP 自动拉取 | 方式二：MQTT 触发 ArduinoOTA |
|---|---|---|
| 触发方式 | 每次唤醒自动检查 | 手动发布 retained `OTA` 指令 |
| 固件来源 | 服务端 firmware.bin 文件 | Arduino IDE 网络端口直传 |
| 人工干预 | 仅放文件+改版本号 | 需守着 IDE 点击上传 |
| 升级延迟 | ≤1个唤醒周期 | ≤1个唤醒周期+上传时间 |
| 在线时长 | 检查约1秒，无额外功耗 | 保持唤醒3分钟，功耗较高 |
| 适用场景 | 日常迭代、批量设备 | 现场调试、临时升级 |
| 依赖服务 | Node服务必须运行 | Arduino IDE + 网络可达 |
| 版本管理 | version文件 + FW_VERSION | IDE直接上传，无版本号 |
| URL路径 | 使用设备组ID | 使用单元ID（MQTT主题） |

---

## 七、依赖与库

### 7.1 服务端依赖

| 依赖 | 说明 |
|---|---|
| express | ota-routes.js 使用 Express Router |
| fs | 文件读取和流式传输 |
| path | 路径拼接 |

均已在项目 `package.json` 中安装，无新增依赖。

### 7.2 设备端依赖

| 库 | 来源 | 用途 |
|---|---|---|
| `ESP8266HTTPClient` | ESP8266 Arduino内核自带 | HTTP GET 请求版本号接口 |
| `ESP8266httpUpdate` | ESP8266 Arduino内核自带 | HTTP下载固件+写入Flash+重启 |
| `ArduinoOTA` | ESP8266 Arduino内核自带 | Arduino IDE网络端口上传 |

均为 ESP8266 Arduino 内核自带，无需额外安装。

---

## 八、新增设备 OTA 配置指南

为新的 ESP 设备配置 OTA 升级，只需 3 步：

### 步骤1：创建固件目录

在 `OTA/firmware/` 下按**设备组ID**创建子目录，放入 `firmware.bin` 和 `version` 文件：

```
OTA/firmware/<新设备组ID>/
  ├─ firmware.bin    （统一命名，从Arduino IDE导出）
  └─ version          内容: 1.0.0
```

### 步骤2：设备端代码配置

在 .ino 文件中配置 3 个常量（URL 路径使用**设备组ID**）：

```cpp
const char* FW_VERSION    = "1.0.0";
const char* otaVersionUrl = "http://192.168.1.149:6002/ota/<新设备组ID>/version";
const char* otaBinUrl     = "http://192.168.1.149:6002/ota/<新设备组ID>/firmware.bin";
```

### 步骤3：复制 checkHttpOta() 函数

将 `checkHttpOta()` 和 `compareVersion()` 函数复制到新设备代码，在 WiFi 连接成功后调用。

> 服务端**零改动**，两个服务文件已挂载通用路由。

---

## 九、故障排查

| 现象 | 可能原因 | 排查方法 |
|---|---|---|
| 设备串口显示"服务器不可达" | Node服务未启动 / IP错误 / 端口被防火墙拦截 | 浏览器访问 `http://192.168.1.149:6002/ota/keting-AC-23343313/version`，应返回版本号 |
| 设备串口显示"已是最新版本"但固件未更新 | version文件和FW_VERSION相同 | 确认version文件内容 > 代码中的FW_VERSION |
| 设备串口显示"固件下载失败: 404" | bin文件不存在 / 文件名不是firmware.bin / 目录用了单元ID而非设备组ID | 确认路径为 `OTA/firmware/<设备组ID>/firmware.bin` |
| OTA服务日志GET version SUCCESS但GET firmware FAILED | version文件在正确位置但bin文件不在 | 检查bin文件名是否为 `firmware.bin`（不是 `<unitId>.bin`） |
| 升级后仍重复下载（无限循环） | bin文件不是最新源码编译的，FW_VERSION未更新 | 重新从Arduino IDE导出bin，确认FW_VERSION与version文件一致 |
| 方式二设备未收到OTA指令 | retained消息未成功发布 / 主题错误 | MQTTX订阅 `iot/device/<单元ID>/control`，确认能收到retained消息 |
| 方式二Arduino IDE找不到网络端口 | 设备未进入OTA模式 / 不在同一网段 | 串口确认"进入OTA模式"已打印，IDE和设备在同一WiFi |
| 升级后RTC参数丢失 | 断电重启（RTC仅跨DeepSleep保留，不跨断电） | 正常现象，设备会用默认参数重新运行 |
| 升级后无限循环重启 | 新固件有致命bug导致启动崩溃 | 方式一：删除bin文件让设备跳过升级；方式二：USB烧录旧固件 |
| OTA服务器日志无访问记录 | 设备URL配置错误 / 设备未连接WiFi | 检查设备串口的WiFi连接状态和URL字符串 |
| 设备显示离线但心跳正常 | server-status-ws.js的MQTT订阅断线后未自动重订阅 | 重启Node服务：`npm run pm2-restart` |
| 离线日志每30秒重复刷屏 | 离线去重逻辑未生效（旧代码） | 重启Node服务加载最新代码 |

---

## 十、安全注意事项

| 风险 | 防护措施 | 代码位置 |
|---|---|---|
| 路径穿越攻击 | `isValidDeviceGroupId()` 正则校验设备组ID | [ota-routes.js L34-36](file:///d:/.openclaw/workspace/iot-web-ai/v11/OTA/ota-routes.js#L34-L36) |
| 敏感文件泄露 | 前置中间件拦截 `.env`/`.json`/`.js`/`.sh` 等 | [server-config.js L121-132](file:///d:/.openclaw/workspace/iot-web-ai/v11/server-config.js#L121-L132)、[server-control-tcp.js L588-598](file:///d:/.openclaw/workspace/iot-web-ai/v11/server-control-tcp.js#L588-L598) |
| 隐藏文件访问 | `express.static` 设置 `dotfiles: 'deny'` | [server-config.js L135](file:///d:/.openclaw/workspace/iot-web-ai/v11/server-config.js#L135)、[server-control-tcp.js L601](file:///d:/.openclaw/workspace/iot-web-ai/v11/server-control-tcp.js#L601) |
| 固件版本回退 | `compareVersion()` 仅在 remoteVersion > FW_VERSION 时升级，不降级 | [ESP12_IoT_AC01.ino L285](file:///d:/.openclaw/workspace/ESP/ESP12_IoT_AC01/ESP12_IoT_AC01.ino#L285) |
| retained指令重复触发 | 收到OTA指令后立即发布空payload清除retained | [ESP12_IoT_AC01.ino](file:///d:/.openclaw/workspace/ESP/ESP12_IoT_AC01/ESP12_IoT_AC01.ino) |
| OTA窗口超时耗电 | 3分钟超时后自动恢复DeepSleep | [ESP12_IoT_AC01.ino](file:///d:/.openclaw/workspace/ESP/ESP12_IoT_AC01/ESP12_IoT_AC01.ino) |

---

## 十一、版本发布检查清单

发布新固件前逐项确认：

- [ ] Arduino IDE 导出 .bin 文件（确认源码中 FW_VERSION 已递增）
- [ ] bin 文件命名为 `firmware.bin` 并覆盖到 `OTA/firmware/<设备组ID>/` 目录
- [ ] 递增 `OTA/firmware/<设备组ID>/version` 文件内容（与 FW_VERSION 一致）
- [ ] 确认 bin 文件是最新源码编译的（防止无限循环升级）
- [ ] 确认 Node 服务正在运行（6002端口可访问）
- [ ] 浏览器访问 `http://<SERVER_IP>:6002/ota/<设备组ID>/version` 确认返回正确版本号
- [ ] 浏览器访问 `http://<SERVER_IP>:6002/ota/<设备组ID>/firmware.bin` 确认能下载文件
- [ ] 等待设备下个唤醒周期，观察串口日志确认升级成功
- [ ] 升级后验证设备温控功能正常
- [ ] 升级后验证心跳正常（前端不再显示离线）

---

## 十二、版本历史

| 版本 | 日期 | 变更内容 |
|---|---|---|
| 1.0.0 | 2026-08-30 | 初始版本：HTTP自动拉取 + MQTT触发ArduinoOTA双机制 |
| 1.1.0 | 2026-08-31 | 新增手动ON/OFF/AUTO控制 + retained指令 + lowPower标记 |
| 1.2.0 | 2026-08-31 | 新增心跳：每周期发布kg01状态刷新在线检测 |
| 1.3.0 | 2026-08-31 | publishKg01State返回值检查 + 心跳3次重试 |
| 1.4.0 | 2026-09-01 | 滞回控制修复：>=/<=边界触发 + 舵机往返(start→end→start) + 状态保持 + OTA路径改用设备组ID + bin统一命名firmware.bin |
