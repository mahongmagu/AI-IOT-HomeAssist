# IoT Web AI 项目文档

> **版本**: v11.1 | **更新日期**: 2026-09-07 | **初始版本**: v2.2.1 (2026-05-07)
>
> 本文档自 2026-05-07 起累计更新了以下重大变化：低功耗设备（lowPower）支持、设备离线检测（3倍唤醒周期）、手动/自动模式切换、HTTP OTA 自动升级、MQTT retained 策略统一、鸿蒙 App 状态值类型扩展、静态资源安全修复、**场景自动化引擎（条件组合触发动作）** 等。

---

## 一、架构和功能说明

### 1.1 系统架构

#### 1.1.1 整体架构图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           系统架构 (v11)                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────────┐      │
│  │  H5 前端     │  │  鸿蒙 App    │  │  ESP 设备端                  │      │
│  │  index.html  │  │  ArkTS       │  │  AC01/wdj/ktd/sdj/...        │      │
│  └──────┬───────┘  └──────┬───────┘  └──────────────┬───────────────┘      │
│         │ HTTP/Ws          │ HTTP/Ws                 │ MQTT                 │
│         ↓                  ↓                         ↓                      │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                         服务端 (Node.js)                             │   │
│  │  ┌────────────┐  ┌──────────────────┐  ┌───────────────────────┐    │   │
│  │  │配置服务    │  │控制服务          │  │状态服务               │    │   │
│  │  │server-     │  │server-control-   │  │server-status-ws.js    │    │   │
│  │  │config.js   │  │tcp.js            │  │                       │    │   │
│  │  │端口:6001   │  │端口:6002         │  │端口:8090(WebSocket)  │    │   │
│  │  │            │  │+OTA路由          │  │                       │    │   │
│  │  │•设备CRUD   │  │•控制指令下发     │  │•MQTT状态订阅          │    │   │
│  │  │•lowPower   │  │•lowPower retained│  │•JSON.parse值类型保留  │    │   │
│  │  │ 解析       │  │•离线检测(动态)   │  │•离线检测(3倍唤醒周期) │    │   │
│  │  │•静态资源   │  │•datasetting/     │  │•WebSocket广播         │    │   │
│  │  │ 安全过滤   │  │ textsetting      │  │•设备在线状态推送      │    │   │
│  │  │            │  │  (retain:true)   │  │                       │    │   │
│  │  │            │  │•/ota/:id/version │  │                       │    │   │
│  │  │            │  │•/ota/:id/bin     │  │                       │    │   │
│  │  │            │  │•场景自动化引擎   │  │                       │    │   │
│  │  │            │  │ server-auto.js   │  │                       │    │   │
│  │  │+场景CRUD   │  │+场景CRUD         │  │                       │    │   │
│  │  │+手动触发   │  │+自动评估引擎    │  │                       │    │   │
│  │  └────────────┘  └──────────────────┘  └───────────────────────┘    │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                      │                                      │
│                              MQTT TCP/WS                                    │
│                                      ↓                                      │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    EMQX MQTT Broker                                  │   │
│  │                  192.168.xxx.xxx                                        │   │
│  │                  TCP: 1883 / WS: 8084                                │   │
│  │  主题: iot/device/{unitId}/control | state | datasetting | textsetting│   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 1.1.2 服务组件

| 服务 | 文件 | 端口 | 功能 |
| --- | --- | --- | --- |
| 配置服务 | `server-config.js` | 6001 | 设备配置管理（CRUD）、lowPower 字段解析、静态资源安全过滤、OTA 路由、**场景 CRUD + 手动触发** |
| 控制服务 | `server-control-tcp.js` | 6002 | MQTT 控制指令下发、离线检测、datasetting/textsetting 下发、OTA 路由、**场景 CRUD + 自动评估引擎** |
| 状态服务 | `server-status-ws.js` | 8090 | WebSocket 实时状态推送、MQTT 状态订阅、离线检测广播、值类型保留 |

> **变更说明**（自 2026-05-07）：状态服务端口从 8084 调整为 8090；控制服务新增 OTA 路由挂载；配置服务新增 lowPower 字段解析和静态资源安全过滤；**v11.1 新增场景自动化模块 `server-auto.js`，挂载于配置服务（CRUD）和控制服务（CRUD + 引擎）**。

#### 1.1.3 数据流

```
用户操作 → 前端/App → 控制服务 → MQTT服务器 → 设备端
                                    ↓
                              状态上报 → MQTT服务器 → 状态服务 → WebSocket → 前端/App
                                    ↓
                              离线检测 ← 每30秒检查 → 标记离线 → WebSocket推送
```

**新增数据流**（2026-05-07 后）：
- **lowPower 设备**：控制指令以 retained 发布 → 设备唤醒后订阅接收 → 执行后清除 retained
- **OTA 升级**：设备唤醒 → HTTP 检查版本 → 下载固件 → 重启升级
- **手动/自动模式**：前端点"恢复自动" → 控制服务发布 AUTO 指令 → 设备切换模式 → 上报控制模式状态
- **场景自动化**：设备状态变化 → MQTT → 控制服务引擎订阅 → 条件评估 → 满足则执行动作 → MQTT 下发控制/参数指令 → 设备执行

### 1.2 核心功能

#### 1.2.1 设备管理

| 功能 | 说明 |
| --- | --- |
| 设备组管理 | 创建、编辑、删除设备组 |
| 设备单元管理 | 添加、编辑、删除设备单元 |
| 自动 ID 生成 | 设备组和单元 ID 自动生成（支持中文转拼音） |
| 位置字段 | 设备组支持可选位置字段 |
| **lowPower 标记** | **[新增]** 设备组可标记 `lowPower: true`，启用低功耗模式（DeepSleep 定时唤醒） |

#### 1.2.2 设备控制

| 设备类型 | 控制方式 | 说明 |
| --- | --- | --- |
| control | ON/OFF/QUERY/AUTO/OTA | 控制型设备，支持远程开关和查询 |
| state | 只读 + QUERY 查询 | 状态型设备，传感器数据只读 |
| text | 文本编辑 | 文本型设备 |
| data | 数值编辑 | 数据型设备 |

> **变更说明**：control 类型新增 `AUTO`（恢复自动模式）和 `OTA`（触发升级）指令；state 类型新增 QUERY 主动查询功能。

#### 1.2.3 实时状态同步

- **WebSocket 实时推送**：状态变化即时更新
- **MQTT 主题订阅**：支持 state/textsetting/datasetting 主题
- **初始状态加载**：连接建立时同步所有设备状态
- **[新增] 值类型保留**：状态服务通过 `JSON.parse` 保留 number/boolean/string/object 原始类型，不再强制转字符串
- **[新增] 离线状态推送**：设备超时后通过 WebSocket 推送 `online: false` 离线状态

#### 1.2.4 [新增] 设备离线检测

| 设备类型 | 检测对象 | 超时规则 | 说明 |
| --- | --- | --- | --- |
| control（常在线） | control 单元的 state 消息 | 固定 5 分钟 | `OFFLINE_TIMEOUT` 环境变量可调 |
| control（lowPower） | control 单元的 state 消息 | 唤醒周期 × 3 | 从 devices.json 的"唤醒时间"单元读取 |
| state / data / text | 不检测 | — | 不参与离线检测 |

- 每 30 秒检查一次设备活跃状态
- 离线设备组图标显示灰色（灰度化 + 透明度 60%）
- 通过 WebSocket 实时同步离线状态到前端/App

#### 1.2.5 [新增] 手动/自动模式切换

- 适用于 lowPower 设备（如 AC01 空调控制器）
- 手动模式（ON/OFF）：舵机执行往返动作，自动温控挂起
- 自动模式（AUTO）：恢复滞回温控逻辑
- 控制模式状态通过独立 data 单元（"控制模式"）retained 上报
- 前端/App 根据"控制模式"值联动"恢复自动"按钮启用/禁用

#### 1.2.6 [新增] OTA 固件升级

| 升级方式 | 触发方式 | 说明 |
| --- | --- | --- |
| HTTP 自动拉取（默认） | 设备每次唤醒自动检查 | 发现新版本自动下载升级并重启 |
| MQTT 触发 ArduinoOTA（备用） | 前端发布 retained "OTA" 指令 | 设备保持唤醒 3 分钟，Arduino IDE 网络端口上传 |

- OTA 路由同时挂载在配置服务（6001）和控制服务（6002）
- 固件存放路径：`OTA/firmware/{设备组ID}/firmware.bin` + `version` 文件

#### 1.2.8 [新增] 场景自动化

基于设备单元状态/值的组合条件，自动触发对其他设备单元的动作。

| 能力 | 说明 |
| --- | --- |
| 条件组合 | 支持多设备单元条件，条件之间 AND/OR 链式组合（从左到右求值） |
| 操作符 | `> >= < <= == !=`（数值比较自动浮点转换，ON/OFF 大小写不敏感） |
| 动作类型 | control（ON/OFF）、data（数值设置）、text（文本设置）、scene（调用其他场景） |
| 自动触发 | MQTT 订阅 `iot/device/+/state`，状态变化时实时评估，边沿触发（不满足→满足才执行，不重复） |
| 手动触发 | 前端"执行"按钮直接触发，跳过条件检查 |
| 场景嵌套 | 场景动作可调用其他场景，最大嵌套 5 层，循环引用自动检测 |
| 启用/禁用 | 每个场景可独立启用/禁用，禁用时引擎跳过评估 |
| 前端管理 | config.html 顶部"场景自动化"菜单，支持场景列表、创建、编辑、删除、执行 |

#### 1.2.9 AI 指令解析

- **基础 AI 接口**：`POST /api/ai`
- **高级 AI 接口**：`POST /api/ai-advanced`
- **AI 定时任务**：`POST /api/ai-schedule`
- **指令格式**：自然语言指令（如"打开插座1"）

### 1.3 MQTT 主题设计

| 主题格式 | 用途 | 方向 | retain 策略 |
| --- | --- | --- | --- |
| `iot/device/{unitId}/control` | 控制指令 | 服务端→设备端 | lowPower: `retain:true`；常在线: `retain:false` |
| `iot/device/{unitId}/state` | 状态上报 | 设备端→服务端 | 开关/模式: `retain:true`；瞬态传感数据: `retain:false` |
| `iot/device/{unitId}/datasetting` | 数值参数 | 双向 | **[变更]** 一律 `retain:true` |
| `iot/device/{unitId}/textsetting` | 文本参数 | 双向 | **[变更]** 一律 `retain:true` |

> **retain 策略变更说明**（2026-09-02）：datasetting/textsetting 从 `retain:false` 改为 `retain:true`，确保低功耗设备唤醒后能从 broker 获取最新参数。

---

## 二、安装部署和操作

### 2.1 环境要求

| 项目 | 要求 |
| --- | --- |
| Node.js | >= 14.0.0 |
| npm | >= 6.0.0 |
| MQTT Broker | EMQX 4.x 或兼容服务 |
| **[新增] pinyin** | **中文转拼音库（`npm install pinyin`）** |

### 2.2 安装步骤

#### 2.2.1 克隆项目

```bash
git clone <repository-url>
cd iot-web-ai/v11
```

#### 2.2.2 安装依赖

```bash
npm install
npm install pinyin  # 拼音转换库
```

#### 2.2.3 配置环境变量

创建 `.env` 文件：

```env
# 服务器配置
SERVER_IP=192.168.1.149
WS_PORT=8090

# MQTT服务器配置
MQTT_EXTERNAL_WS_SERVER=ws://192.168.1.40:8084/mqtt
MQTT_INTERNAL_SERVER=mqtt://192.168.1.40:1883
MQTT_TOPIC_PREFIX=iot/device
MQTT_USERNAME=xxxx
MQTT_PASSWORD=xxxxxxxx

# 服务端口配置
CONFIG_SERVICE_PORT=6001
CONTROL_SERVICE_PORT=6002

# [新增] 设备离线检测配置
OFFLINE_TIMEOUT=300000    # 常在线设备超时，5分钟（毫秒）
CHECK_INTERVAL=30000      # 定时检查间隔，30秒（毫秒）
```

### 2.3 启动服务

#### 2.3.1 启动配置服务

```bash
npm run config
# 输出示例：
# 配置服务启动：http://192.168.1.149:6001
```

#### 2.3.2 启动控制服务

```bash
npm run start
# 输出示例：
# 控制服务启动：http://192.168.1.149:6002
# MQTT TCP控制客户端（内网）连接成功
# 设备离线检测已启动 - 普通设备超时: 300秒, lowPower设备: 3倍唤醒周期, 检查间隔: 30秒
```

#### 2.3.3 启动状态服务

```bash
npm run status
# 输出示例：
# WebSocket状态服务（外网）启动: ws://192.168.1.149:8090
# MQTT WebSocket状态客户端（外网）连接成功
```

### 2.4 访问方式

| 服务 | URL |
| --- | --- |
| 设备控制页面 | `http://<server-ip>:6002/index.html` |
| 配置管理页面 | `http://<server-ip>:6001/config.html` |
| 鸿蒙 App | 通过 DevEco Studio 编译安装 |

### 2.5 设备端配置

#### 2.5.1 订阅主题

设备端需要订阅以下主题：

```bash
# 控制指令
iot/device/+/control

# [新增] 文本设置（retain:true）
iot/device/+/textsetting

# [新增] 数据设置（retain:true）
iot/device/+/datasetting
```

#### 2.5.2 状态上报

设备执行操作后，需要上报状态到：

```bash
iot/device/{unitId}/state
```

**[新增] retain 策略**：
- 开关/模式状态：`retain: true`（持久运行状态，确保前端可见）
- 传感器数据：`retain: false`（瞬态值，避免过期数据误导）

---

## 三、服务端详细说明

### 3.1 配置服务 (server-config.js, 端口 6001)

#### 3.1.1 核心功能

| 功能 | 说明 |
| --- | --- |
| 设备组 CRUD | 创建/读取/修改/删除设备组 |
| 设备单元 CRUD | 创建/读取/修改/删除设备单元 |
| 自动 ID 生成 | 中文转拼音 + 随机数字后缀 |
| lowPower 字段解析 | **[新增]** 创建设备组时解析 `payload.lowPower` 并写入配置 |
| 静态资源安全过滤 | **[新增]** 过滤 `.env` 等敏感文件访问 |
| OTA 路由 | **[新增]** 挂载 OTA 路由，提供固件版本检查和下载 |

#### 3.1.2 [新增] 静态资源安全修复

```javascript
// 过滤敏感文件访问
app.use((req, res, next) => {
  const requestedFile = path.basename(req.path);
  const sensitiveFiles = ['.env', 'devices.json', 'package.json', 'package-lock.json'];
  if (sensitiveFiles.includes(requestedFile)) {
    return res.status(403).send('禁止访问');
  }
  next();
});
```

### 3.2 控制服务 (server-control-tcp.js, 端口 6002)

#### 3.2.1 核心功能

| 功能 | 说明 | 关键代码位置 |
| --- | --- | --- |
| 控制指令下发 | 按 lowPower 决定 retain 策略 | L762-L829 |
| 简化控制接口 | `/api/control-slot` | L832 |
| 文本参数下发 | textsetting，retain:true | L960-L1013 |
| 数值参数下发 | datasetting，retain:true | L1016-L1080 |
| 离线检测 | 动态超时（lowPower 3倍唤醒周期） | L346-L413 |
| 状态查询 | `/api/status` 返回在线状态 | L1081 |
| OTA 路由挂载 | `app.use(require('./OTA/ota-routes'))` | L686 |

#### 3.2.2 [新增] lowPower retained 指令

```javascript
// /api/control 接口中按 lowPower 决定 retain
let retain = false;
for (const group of Object.values(devices)) {
  if (group && Array.isArray(group.units) && group.units.some(u => u.id === unitId)) {
    retain = !!group.lowPower;
    break;
  }
}
const success = sendMqttControl(cmd, unitId, retain);
```

#### 3.2.3 [变更] datasetting/textsetting retain 策略

```javascript
// datasetting 和 textsetting 统一 retain: true
// 确保低功耗设备唤醒后能从 broker 获取最新参数
function sendMqttDataSetting(value, unitId) {
  // ...
  mqttClient.publish(topic, value.toString(), { retain: true });  // 原为 false
}

function sendMqttTextSetting(value, unitId) {
  // ...
  mqttClient.publish(topic, value, { retain: true });  // 原为 false
}
```

#### 3.2.4 [新增] 离线检测（动态超时）

```javascript
function getOfflineTimeout(unitId) {
  for (const [groupName, groupConfig] of Object.entries(cachedDevices)) {
    if (groupName === 'lastUpdated' || !groupConfig?.units) continue;
    if (groupConfig.lowPower === true) {
      const unit = groupConfig.units.find(u => u.id === unitId);
      if (unit) {
        const wakeupUnit = groupConfig.units.find(u =>
          u.name === '唤醒时间' || u.id.includes('huanxingshijian')
        );
        if (wakeupUnit && wakeupUnit.status) {
          const wakeMinutes = parseInt(wakeupUnit.status) || 5;
          return wakeMinutes * 3 * 60 * 1000; // 3倍唤醒周期
        }
        return OFFLINE_TIMEOUT * 3; // 兜底3倍默认超时
      }
    }
  }
  return OFFLINE_TIMEOUT; // 普通设备5分钟
}
```

### 3.3 状态服务 (server-status-ws.js, 端口 8090)

#### 3.3.1 核心功能

| 功能 | 说明 | 关键代码位置 |
| --- | --- | --- |
| MQTT 状态订阅 | `iot/device/+/state` | L293 |
| 值类型保留 | JSON.parse 保留原始类型 | L361-L367 |
| WebSocket 广播 | state-update 消息推送 | L463 |
| 离线检测 | 3倍唤醒周期 + 30秒检查 | L207-L303 |
| 离线状态广播 | online:false + state:OFFLINE | L264-L298 |

#### 3.3.2 [新增] 值类型保留

```javascript
let stateValue;
try {
  stateValue = JSON.parse(message.toString());  // 尝试解析为原始类型
} catch {
  stateValue = message.toString();              // 解析失败则保留字符串
}
```

#### 3.3.3 [新增] 离线检测与广播

```javascript
function broadcastOfflineStatus(unitId) {
  const offlineUpdate = {
    type: 'state-update',
    device: { /* ... */ online: false },
    state: 'OFFLINE',
    topic: `iot/device/${unitId}/state`,
    timestamp: new Date().toISOString()
  };
  broadcastToWebSockets(offlineUpdate);
}
```

### 3.4 [新增] OTA 路由模块 (OTA/ota-routes.js)

```javascript
// 同时挂载在配置服务（6001）和控制服务（6002）
// 版本检查：GET /ota/:deviceGroupId/version → 返回版本号文本
// 固件下载：GET /ota/:deviceGroupId/firmware.bin → 返回二进制固件
// 固件存放：OTA/firmware/{设备组ID}/firmware.bin + version
// 路径安全：设备组ID只允许字母数字下划线连字符，防止路径穿越
```

### 3.5 [新增] 场景自动化模块 (server-auto.js)

场景自动化模块以 Express 路由形式挂载在配置服务（6001）和控制服务（6002）两个进程，共享 `data/scenes.json` 数据文件。

#### 3.5.1 挂载方式

```javascript
// 配置服务 server-config.js（仅 CRUD + 手动触发）
app.use(require('./server-auto').router);

// 控制服务 server-control-tcp.js（CRUD + 自动评估引擎）
const sceneAutomation = require('./server-auto');
app.use(sceneAutomation.router);
sceneAutomation.startEngine();  // 引擎仅在此进程运行
```

> **设计说明**：自动评估引擎仅在控制服务进程启动（`startEngine()`），避免两个进程重复订阅 MQTT、重复触发场景动作。配置服务进程仅提供 CRUD 路由和手动触发（手动触发时懒加载 MQTT 连接发布指令）。

#### 3.5.2 数据结构

场景数据存储于 `data/scenes.json`：

```json
{
  "scenes": {
    "scene_1788766409705_fbc7": {
      "id": "scene_1788766409705_fbc7",
      "name": "高温自动通风",
      "enabled": true,
      "conditions": [
        {
          "id": "c1",
          "unitId": "keting-wdj-46716033_wdcgq-8684",
          "unitName": "温度传感器",
          "unitType": "state",
          "operator": ">=",
          "value": "25",
          "logic": "AND"
        },
        {
          "id": "c2",
          "unitId": "keting-shg-64771774_gaoshuiweichuanganqi-5209",
          "unitName": "高水位传感器",
          "unitType": "control",
          "operator": "==",
          "value": "OFF",
          "logic": "OR"
        }
      ],
      "actions": [
        {
          "id": "a1",
          "type": "control",
          "unitId": "keting-shg-64771774_fengshan-0838",
          "unitName": "风扇",
          "value": "ON"
        },
        {
          "id": "a2",
          "type": "scene",
          "unitId": "",
          "unitName": "子场景",
          "value": "scene_other_id"
        }
      ],
      "createdAt": "2026-09-07T07:33:29.705Z",
      "updatedAt": "2026-09-07T07:33:29.705Z",
      "lastTriggered": null
    }
  },
  "lastUpdated": "2026-09-07T07:33:29.705Z"
}
```

**字段说明**：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | string | 场景 ID，格式 `scene_{时间戳}_{随机}` |
| `name` | string | 场景名称（必填） |
| `enabled` | boolean | 是否启用自动触发（默认 true） |
| `conditions` | array | 条件列表（至少 1 条） |
| `conditions[].id` | string | 条件 ID，格式 `c_{时间戳}_{随机}` |
| `conditions[].unitId` | string | 设备单元 ID |
| `conditions[].unitName` | string | 设备单元名称（冗余存储，方便前端展示） |
| `conditions[].unitType` | string | 设备单元类型（control/state/data/text） |
| `conditions[].operator` | string | 比较操作符：`> >= < <= == !=` |
| `conditions[].value` | string | 比较值（数值或 ON/OFF 等字符串） |
| `conditions[].logic` | string | 与上一条件的关系：`AND`（默认）或 `OR`；首条忽略 |
| `actions` | array | 动作列表（至少 1 条） |
| `actions[].id` | string | 动作 ID，格式 `a_{时间戳}_{随机}` |
| `actions[].type` | string | 动作类型：`control` / `data` / `text` / `scene` |
| `actions[].unitId` | string | 目标设备单元 ID（scene 类型为空） |
| `actions[].unitName` | string | 目标设备单元名称（scene 类型为目标场景名称） |
| `actions[].value` | string | 动作值（control: ON/OFF，data/text: 具体值，scene: 目标场景 ID） |
| `createdAt` | ISO 8601 | 创建时间 |
| `updatedAt` | ISO 8601 | 最后修改时间 |
| `lastTriggered` | ISO 8601 / null | 最后一次触发时间（自动触发或手动触发均更新） |

#### 3.5.3 条件评估引擎

```javascript
// 引擎启动时订阅 MQTT 状态主题
// iot/device/+/state → 状态变化触发评估

// 单条件评估
function evalCondition(cond, valueProvider) {
  const raw = valueProvider(cond.unitId);  // 优先 MQTT 实时缓存，兜底 devices.json
  if (raw === undefined || raw === 'OFFLINE') return false;

  if (['>', '>=', '<', '<='].includes(cond.operator)) {
    // 数值比较：自动浮点转换
    const a = parseFloat(raw), b = parseFloat(cond.value);
    if (isNaN(a) || isNaN(b)) return false;
    // 按操作符比较...
  }
  // == / != 字符串比较，ON/OFF 大小写不敏感
}

// 多条件链式评估（从左到右，AND/OR 组合）
// 例：条件1 AND 条件2 OR 条件3
//   = ((条件1) AND (条件2)) OR (条件3)
function evalSceneConditions(scene, valueProvider) {
  let result = evalCondition(conds[0]);
  for (let i = 1; i < conds.length; i++) {
    result = conds[i].logic === 'OR'
      ? (result || evalCondition(conds[i]))
      : (result && evalCondition(conds[i]));
  }
  return result;
}
```

**边沿触发**：仅在条件由"不满足"→"满足"时触发，已满足状态下重复收到相同状态不会再次触发：

```javascript
// 引擎内部状态
const prevSatisfied = {};  // sceneId -> 上一轮是否满足

if (satisfied && !wasSatisfied) {
  // 满足且上一轮不满足 → 执行动作
  executeScene(sceneId, { source: 'auto' });
}
prevSatisfied[sceneId] = satisfied;
```

**兜底评估**：引擎每 30 秒定时评估一次所有启用场景，覆盖"场景刚创建/启用时条件已满足"的情况。

#### 3.5.4 动作执行

| 动作类型 | 执行方式 | MQTT 主题 | retain |
| --- | --- | --- | --- |
| `control` | 发布 ON/OFF 指令 | `{prefix}/{unitId}/control` | lowPower 设备 retained，常在线不 retained |
| `data` | 发布数值参数 | `{prefix}/{unitId}/datasetting` | retained |
| `text` | 发布文本参数 | `{prefix}/{unitId}/textsetting` | retained |
| `scene` | 递归调用 `executeScene` | — | 递归调用，含循环引用检测和嵌套深度限制 |

**场景嵌套保护**：

```javascript
const MAX_SCENE_DEPTH = 5;  // 最大嵌套 5 层

async function executeScene(sceneId, ctx) {
  if (ctx.visited.has(sceneId)) return { ok: false, msg: '场景循环引用' };
  if (ctx.depth > MAX_SCENE_DEPTH) return { ok: false, msg: '场景嵌套过深' };
  ctx.visited.add(sceneId);
  // 执行所有动作...
  // scene 类型动作递归调用 executeScene(act.value, { depth: ctx.depth + 1, visited: ctx.visited })
}
```

#### 3.5.5 API 接口

| 接口 | 方法 | 功能 | 说明 |
| --- | --- | --- | --- |
| `/api/scenes` | GET | 获取所有场景 | 返回 `{ code: 200, data: { scenes... } }` |
| `/api/scenes` | POST | 创建场景 | body: `{ name, enabled, conditions, actions }`，校验至少 1 条件 1 动作 |
| `/api/scenes/:sceneId` | GET | 获取单个场景 | — |
| `/api/scenes/:sceneId` | PUT | 修改场景 | 支持修改名称、条件、动作、启用状态 |
| `/api/scenes/:sceneId` | DELETE | 删除场景 | — |
| `/api/scenes/:sceneId/trigger` | POST | 手动触发场景 | 跳过条件检查直接执行所有动作，返回执行结果 |

---

## 四、鸿蒙 App 端详细说明

### 4.1 数据模型变更

#### 4.1.1 DeviceUnit.status 类型扩展

```typescript
// 修改前（v2.2.1）
@Trace status: string = '';

// 修改后（v11）
@Trace status: string | number | boolean | object = '';
```

> **变更原因**：服务端状态值支持 number/boolean/string/object，App 需对应扩展类型。

#### 4.1.2 WebSocketService 消息模型

```typescript
interface StateUpdateMessage {
  // 修改前：state: string
  // 修改后：
  state: string | number | boolean | object;
  // ...
}
```

`isValidStateUpdateMessage()` 只校验 `state` 是否存在，不限制具体类型。

### 4.2 [新增] 手动/自动模式按钮联动

#### 4.2.1 DeviceDetail.ets 中的"恢复自动"按钮

```typescript
if (this.deviceGroup.lowPower === true) {
  const modeUnit = this.deviceUnits.find((u: DeviceUnit): boolean => u.name === '控制模式');
  let modeStatus = '自动';
  if (modeUnit) {
    modeStatus = typeof modeUnit.status === 'object'
      ? JSON.stringify(modeUnit.status) : String(modeUnit.status);
  }
  const isManual = modeStatus.startsWith('手动');

  Button() {
    Text('恢复自动')
      .fontSize(12)
      .fontWeight(FontWeight.Bold)
  }
  .enabled(isManual)  // 仅手动模式时可点击
  .onClick(() => {
    this.restoreAuto(unit);
  })
}
```

**联动逻辑**：
- 设备处于自动模式 → "控制模式"值为"自动" → `isManual = false` → 按钮 disabled
- 设备处于手动模式 → "控制模式"值为"手动" → `isManual = true` → 按钮 enabled
- 数据来源：WebSocket state-update 推送的"控制模式"单元状态

#### 4.2.2 API 服务适配

```typescript
// ApiService.ets
async addDeviceUnit(groupName: string, unit: DeviceUnit): Promise<boolean> {
  // status 参数类型：string | number | boolean
  const body = { ...unit, status: unit.status };
  // ...
}
```

### 4.3 App 端适配变更汇总

| 服务端特性 | App 适配 | 状态 |
| --- | --- | --- |
| MQTT 实时状态值（数字/字符串） | status 支持任意类型 | 已适配 |
| QUERY 命令查询 | 通过 WebSocket 接收响应 | 已适配 |
| 离线状态推送 | 通过 message.device.online 判断 | 已适配 |
| 值类型保留 | 不强制转为字符串 | 已适配 |
| 手动/自动模式联动 | "恢复自动"按钮 enabled/disabled | 已适配 |

---

## 五、设备端详细说明

### 5.1 ESP12_IoT_AC01（空调控制器，lowPower 设备）

#### 5.1.1 核心特性

| 特性 | 说明 |
| --- | --- |
| DeepSleep 低功耗 | GPIO16→RST 定时唤醒，休眠电流 20-30μA |
| RTC 持久化 | 参数、触发状态、手动模式保存在 RTC 内存 |
| 滞回控制 | 双阈值状态机，避免温度抖动导致舵机频繁动作 |
| 手动/自动模式 | ON/OFF/AUTO 指令，retained 发布确保离线不丢失 |
| HTTP OTA | 每次唤醒检查服务器版本，自动下载升级 |
| MQTT OTA | retained "OTA" 指令触发 ArduinoOTA 保持唤醒窗口 |

#### 5.1.2 [新增] 手动/自动模式切换

```cpp
enum ManualMode {
  MODE_AUTO        = 0,  // 自动温控模式
  MODE_MANUAL_ON   = 1,  // 手动开启模式
  MODE_MANUAL_OFF  = 2   // 手动关闭模式
};

void handleManualCommand() {
  if (g_manualCmd == CMD_ON) {
    publishKg01State("ON");                    // 先发布开关状态
    servoAction(startAngle, endAngle);         // 完整往返一次（起始→终止→起始）
    servoAction(endAngle, startAngle);
    manualMode = MODE_MANUAL_ON;
    publishKg01Mode("手动");                   // retained 上报控制模式
  } else if (g_manualCmd == CMD_OFF) {
    publishKg01State("OFF");
    servoAction(startAngle, endAngle);
    servoAction(endAngle, startAngle);
    manualMode = MODE_MANUAL_OFF;
    publishKg01Mode("手动");
  } else if (g_manualCmd == CMD_AUTO) {
    manualMode = MODE_AUTO;
    publishKg01State("OFF");                   // 复位前端显示
    publishKg01Mode("自动");
  }
  g_manualCmd = CMD_NONE;
  // 收到指令后清除 retained 防止重复执行
}
```

#### 5.1.3 [新增] 控制模式数据单元上报

```cpp
const char* modeId = "keting-AC-23343313_kongzhimoshi-5321";

void publishKg01Mode(const char* mode) {
  client.publish(topicModeState.c_str(), mode, true);  // retained
}
```

- 上报时机：手动 ON、手动 OFF、恢复 AUTO、每次唤醒心跳
- 前端/App 根据该值联动"恢复自动"按钮状态

#### 5.1.4 [新增] HTTP OTA 自动升级

```cpp
const char* FW_VERSION    = "1.5.4";
const char* otaVersionUrl = "http://192.168.6.140:6002/ota/keting-AC-23343313/version";
const char* otaBinUrl     = "http://192.168.6.140:6002/ota/keting-AC-23343313/firmware.bin";

void checkOtaUpdate() {
  // HTTP GET 版本号 → 比对本地版本 → 不同则 ESPhttpUpdate.update(otaBinUrl)
}
```

#### 5.1.5 [变更] state retain 策略

| state 主题 | retain | 说明 |
| --- | --- | --- |
| kg01/state（ON/OFF） | `true` | **[变更]** 从 false 改为 true，持久运行状态 |
| kongzhimoshi/state（自动/手动） | `true` | 保持不变 |
| wdcgq/state（温度，wdj 设备） | `false` | **[变更]** 从 true 改为 false，瞬态传感数据 |

### 5.2 ESP8266_IoT_wdj（温度传感器）

| 特性 | 说明 |
| --- | --- |
| DS18B20 温度采集 | 保留 1 位小数 |
| 定时上报 | 可配置发送间隔（data 单元） |
| **[变更] state retain** | **从 `true` 改为 `false`**，温度是瞬态值，retained 会误导前端 |

### 5.3 ESP8266_IoT_switch_01 / switch_USB-01（多路开关）

| 特性 | 说明 |
| --- | --- |
| 多路继电器控制 | 支持多个 unitId 独立控制 |
| state retain | `true`（已是，无需修改） |
| ON/OFF 指令 | 标准 control 类型 |

### 5.4 其他控制设备（lyws/ktd/sdj/kqyws/duoji/8266_IoT）

| 设备 | 用途 | **[变更] state retain** |
| --- | --- | --- |
| lyws（鲤鱼喂食） | 喂食器控制 | **从 false 改为 true** |
| ktd（客厅灯） | 继电器灯控 | **从 false 改为 true** |
| sdj（扫地机） | 继电器控制 | **从 false 改为 true** |
| kqyws（孔雀鱼喂食） | 喂食器控制 | **从 false 改为 true** |
| duoji（舵机） | 舵机控制 | **从 false 改为 true** |
| 8266_IoT（通用开关） | 继电器控制 | **从 false 改为 true** |

> **变更原因**：开关/继电器状态是持久运行状态，retained 确保设备重启/服务重启后状态可恢复。

### 5.5 设备端 retain 策略总结

| 设备类型 | state 主题 | retain | 原因 |
| --- | --- | --- | --- |
| AC01 kg01（开关） | kg01/state | `true` | 持久运行状态 |
| AC01 控制模式 | kongzhimoshi/state | `true` | 持久运行状态 |
| wdj 温度传感器 | wdcgq/state | `false` | 瞬态传感数据 |
| 各开关设备 | state | `true` | 持久运行状态 |
| AC01 OTA 瞬时状态 | kg01/state | `true` | 超时后 OFF 覆盖，升级后正常状态覆盖 |

---

## 六、OTA 升级详细说明

### 6.1 OTA 架构

```
┌──────────────┐  HTTP GET version  ┌──────────────────┐
│  AC01 设备   │ ─────────────────→ │ 控制服务 (6002)  │
│  每次唤醒    │ ←───────────────── │ /ota/:id/version │
│              │                    └──────────────────┘
│              │  HTTP GET bin      ┌──────────────────┐
│              │ ─────────────────→ │ 控制服务 (6002)  │
│              │ ←───────────────── │ /ota/:id/bin     │
│  下载固件    │                    │ 固件存放:        │
│  ESPhttpUpdate│                   │ OTA/firmware/    │
│  自动重启    │                    │  {设备组ID}/     │
└──────────────┘                    │  firmware.bin    │
                                    │  version         │
                                    └──────────────────┘
```

### 6.2 方式一：HTTP 自动拉取（默认）

| 步骤 | 说明 |
| --- | --- |
| 1. 唤醒检查 | 设备每次唤醒 HTTP GET 版本号 |
| 2. 版本比对 | 服务器版本 > 本地版本 → 触发升级 |
| 3. 下载固件 | ESPhttpUpdate.update(otaBinUrl) |
| 4. 自动重启 | 升级成功后自动重启，RTC 参数保留 |
| 5. 失败处理 | 升级失败进入 DeepSleep，下次唤醒重试 |

### 6.3 方式二：MQTT 触发 ArduinoOTA（备用）

| 步骤 | 说明 |
| --- | --- |
| 1. 发布指令 | 前端/App 发布 retained "OTA" 到 control 主题 |
| 2. 设备唤醒 | 设备唤醒订阅收到 "OTA"，清除 retained |
| 3. 保持唤醒 | 启动 ArduinoOTA，保持唤醒 3 分钟 |
| 4. IDE 上传 | Arduino IDE → 工具→端口→网络端口 esp12f-ac01 |
| 5. 自动重启 | 上传完成自动重启 |
| 6. 超时恢复 | 3 分钟未收到固件 → 恢复 DeepSleep |

### 6.4 固件存放规范

```
iot-web-ai/v11/OTA/
├── ota-routes.js                          # OTA 路由模块
└── firmware/
    └── keting-AC-23343313/                # 按设备组 ID 建子目录
        ├── firmware.bin                   # 固件二进制文件
        └── version                        # 版本号文本文件（如 "1.5.3"）
```

---

## 七、测试步骤和内容

### 7.1 功能测试

#### 7.1.1 设备组管理测试

| 测试项 | 步骤 | 预期结果 |
| --- | --- | --- |
| 创建设备组 | 填写名称、显示名称、位置、设备单元 | 设备组创建成功，ID 自动生成 |
| **[新增] 创建 lowPower 设备组** | **勾选 lowPower，添加"唤醒时间"单元** | **设备组带 lowPower:true 标记** |
| 编辑设备组 | 修改名称、显示名称、位置 | 修改成功 |
| 删除设备组 | 点击删除按钮 | 删除成功 |

#### 7.1.2 设备控制测试

| 测试项 | 步骤 | 预期结果 |
| --- | --- | --- |
| 控制型设备 | 点击打开/关闭按钮 | MQTT 消息发送成功，设备状态变化 |
| **[新增] lowPower 设备控制** | **点击打开/关闭** | **retained 发布，设备唤醒后执行** |
| **[新增] 恢复自动** | **手动模式下点击"恢复自动"** | **设备切换到自动模式，按钮变 disabled** |
| 状态型设备 | 点击查询状态按钮 | 状态刷新 |
| **[新增] 值类型测试** | **发布数字/字符串/布尔值** | **前端正确显示原始类型** |

#### 7.1.3 [新增] 离线检测测试

| 测试场景 | 步骤 | 预期结果 |
| --- | --- | --- |
| 常在线设备离线 | 断开设备网络，等待 5 分钟 | 设备组图标变灰色 |
| lowPower 设备正常 | 每 5 分钟唤醒上报 | 始终在线，不误判 |
| lowPower 设备离线 | 连续 3 次唤醒无上报（15 分钟） | 标记离线 |
| 设备恢复 | 重新连接并上报状态 | 图标恢复正常颜色 |

#### 7.1.4 [新增] OTA 升级测试

| 测试场景 | 步骤 | 预期结果 |
| --- | --- | --- |
| HTTP 自动升级 | 服务器放置新版本固件 | 设备唤醒后自动下载升级 |
| 版本相同 | 服务器版本与本地一致 | 跳过升级，正常进入主流程 |
| MQTT OTA | 发布 "OTA" 指令 | 设备保持唤醒，等待 IDE 上传 |

### 7.2 接口测试

#### 7.2.1 设备组接口

| 接口 | 方法 | 说明 |
| --- | --- | --- |
| `/api/devices` | GET | 返回所有设备组 |
| `/api/devices` | POST | 创建设备组（支持 lowPower 字段） |
| `/api/devices/{name}` | GET/PUT/DELETE | 设备组详情/修改/删除 |
| `/api/devices/{name}/units` | GET/POST | 单元列表/添加单元 |
| `/api/devices/{name}/units/{unitId}` | GET/PUT/DELETE | 单元详情/修改/删除 |
| `/api/all-units` | GET | 所有单元列表 |

#### 7.2.2 控制接口

| 接口 | 方法 | 测试数据 | 预期结果 |
| --- | --- | --- | --- |
| `/api/control` | POST | `{"cmd":"ON","unitType":"control",...}` | 控制指令发送（lowPower 自动 retained） |
| `/api/control-slot` | POST | `{"slot":"unit-id","cmd":"ON"}` | 简化控制 |
| `/api/set-text` | POST | `{"slot":"unit-id","value":"test"}` | 文本设置（retain:true） |
| `/api/set-data` | POST | `{"slot":"unit-id","value":100}` | 数据设置（retain:true） |
| `/api/status` | GET | — | 返回 states + online 在线状态 |
| **[新增]** `/ota/:id/version` | GET | — | 返回版本号 |
| **[新增]** `/ota/:id/firmware.bin` | GET | — | 返回固件二进制 |

### 7.3 状态同步测试

#### 7.3.1 WebSocket 连接测试

| 测试项 | 步骤 | 预期结果 |
| --- | --- | --- |
| 连接建立 | 打开设备控制页面 | 状态连接显示"已连接" |
| 状态推送 | 设备上报状态变化 | 页面实时更新显示 |
| **[新增] 离线推送** | **设备超时离线** | **WebSocket 推送 online:false** |
| **[新增] 模式联动** | **设备切换手动/自动** | **"恢复自动"按钮状态实时变化** |

#### 7.3.2 MQTT 消息测试

```bash
# 订阅状态主题
mosquitto_sub -t "iot/device/+/state" -h 192.168.1.40 -p 1883 -u xx -P xxxxxxxx

# 发布测试消息（数字类型）
mosquitto_pub -h 192.168.1.40 -p 1883 -u xx -P xxxxxxxx \
  -t "iot/device/test-unit/state" -m "25.5"

# [新增] 测试 retained datasetting
mosquitto_pub -h 192.168.1.40 -p 1883 -u xx -P xxxxxxxx \
  -t "iot/device/test-unit/datasetting" -m "28" -r
```

---

## 八、优化建议

### 8.1 架构优化

#### 8.1.1 服务分离

**现状**：三个服务独立运行，需要手动启动

**建议**：使用 Docker Compose 编排服务，一键启动

#### 8.1.2 数据库集成

**现状**：使用 JSON 文件存储配置

**建议**：集成 SQLite 或 MongoDB，支持更复杂的查询和事务

### 8.2 功能优化

| 优化项 | 说明 |
| --- | --- |
| 用户认证 | 添加 JWT 认证，保护 API 接口 |
| 操作日志 | 完善操作日志系统，记录所有设备操作 |
| 设备发现 | 支持 MQTT 自动发现协议，设备自动注册 |
| **离线告警** | **[待实现]** 设备离线时发送邮件/短信通知 |
| **state 类型检测** | **[待实现]** 支持 state 类型设备的离线检测 |

### 8.3 安全性优化

| 优化项 | 说明 | 状态 |
| --- | --- | --- |
| 输入验证 | 使用 Joi 进行严格的输入验证 | 待实现 |
| HTTPS 支持 | 配置 HTTPS，使用 Let's Encrypt 证书 | 待实现 |
| **静态资源安全** | **过滤 .env 等敏感文件访问** | **已实现** |

---

## 九、附录

### 9.1 文件结构

```
iot-web-ai/v11/
├── .env                    # 环境变量配置
├── package.json            # 项目依赖
├── data-manager.js         # 数据持久化管理
├── devices.json            # 设备配置文件
├── server-config.js        # 配置服务 (6001)
├── server-control-tcp.js   # 控制服务 (6002)
├── server-status-ws.js     # 状态服务 (8090)
├── index.html              # 设备控制页面
├── config.html             # 配置管理页面
└── OTA/                    # [新增] OTA 升级模块
    ├── ota-routes.js       # OTA 路由
    └── firmware/           # 固件存放目录
        └── {设备组ID}/
            ├── firmware.bin
            └── version
```

### 9.2 设备数据结构

```json
{
  "设备组名称": {
    "name": "设备组名称",
    "displayName": "显示名称",
    "id": "设备组ID",
    "location": "位置",
    "lowPower": false,
    "units": [
      {
        "id": "设备单元ID",
        "name": "设备单元名称",
        "type": "control|state|text|data",
        "status": "状态值",
        "customIcon": "可选图标"
      }
    ]
  },
  "lastUpdated": "ISO 8601 时间"
}
```

### 9.3 [新增] 变更历史摘要

| 日期 | 变更内容 |
| --- | --- |
| 2026-05-07 | 初始版本 v2.2.1 |
| 2026-08-31 | 新增 lowPower 低功耗设备离线检测（3倍唤醒周期） |
| 2026-08-31 | 新增 lowPower retained 控制指令 |
| 2026-08-31 | 新增 AC01 手动/自动模式切换 |
| 2026-08-31 | 新增 AC01 控制模式数据单元上报 |
| 2026-08-31 | 新增 AC01 HTTP OTA 自动升级 |
| 2026-08-31 | 新增 AC01 MQTT OTA 备用升级 |
| 2026-08-31 | 新增 OTA 路由模块挂载到控制服务 |
| 2026-08-31 | 新增配置服务静态资源安全过滤 |
| 2026-08-31 | 鸿蒙 App status 类型扩展为 string\|number\|boolean\|object |
| 2026-08-31 | 鸿蒙 App"恢复自动"按钮状态联动 |
| 2026-09-02 | datasetting/textsetting 统一改为 retain:true |
| 2026-09-02 | 所有开关设备 state 改为 retain:true |
| 2026-09-02 | wdj 温度传感器 state 改为 retain:false |
| 2026-09-02 | AC01 kg01 state 改为 retain:true |

### 9.4 常见问题

| 问题 | 原因 | 解决方案 |
| --- | --- | --- |
| 状态连接显示"未知" | WebSocket 连接未建立 | 检查状态服务是否启动，端口 8090 |
| MQTT 消息发送成功但设备无响应 | 设备未订阅对应主题 | 检查设备端订阅配置 |
| **lowPower 设备频繁离线** | **唤醒时间单元 status 值不正确** | **检查 devices.json 中"唤醒时间"的值** |
| **lowPower 设备永不离线** | **lowPower 标记未设置** | **检查 devices.json 中设备组有 lowPower:true** |
| **前端改参数设备不生效** | **datasetting 未 retained** | **确认服务端已更新为 retain:true 并重启** |
| **"恢复自动"按钮不可点击** | **设备处于自动模式** | **属正常行为，手动模式时才可点击** |
| 端口冲突 | 端口被占用 | 修改 .env 中的端口配置 |

---

**文档版本**: v11.0  
**初始生成日期**: 2026-05-07  
**最后更新日期**: 2026-09-02  
**项目版本**: IoT Web AI v11
