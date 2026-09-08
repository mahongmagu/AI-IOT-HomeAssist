# IoT 智能控制系统 - 设备定义说明文档

> 本文档定义 IoT 智能控制系统中 `devices.json` 的完整格式规范，包括设备组与设备单元的字段定义、四种单元类型的业务用途、MQTT 消息格式、retain 策略以及不同类型对应的 API 调用接口。

---

## 一、设备定义格式

### 1.1 顶层结构

```json
{
  "<设备组标识>": { <设备组对象> },
  "lastUpdated": "<最后更新时间 ISO 8601>"
}
```

- 顶层是一个 JSON 对象，key 为**设备组标识**（英文短名，如 `"AC01"`、`"wdj"`），value 为设备组对象
- 固定保留一个 `"lastUpdated"` key，记录配置文件最后修改时间

### 1.2 设备组对象格式

```json
{
  "name": "AC01",
  "displayName": "空调一",
  "id": "keting-AC-23343313",
  "location": "客厅",
  "lowPower": true,
  "units": [ <设备单元对象>, ... ]
}
```

### 1.3 设备单元对象格式

```json
{
  "id": "keting-AC-23343313_kg01-6432",
  "name": "kg01",
  "status": "ON",
  "type": "control",
  "customIcon": "🐟"
}
```

---

## 二、字段描述和说明

### 2.1 设备组字段

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `name` | string | 是 | 设备组标识，与顶层 key 一致，英文短名 |
| `displayName` | string | 是 | 设备组显示名称，支持中文，前端/App 展示用 |
| `id` | string | 是 | 设备组唯一 ID，格式为 `位置拼音-英文短名-8位数字`（如 `keting-AC-23343313`） |
| `location` | string | 否 | 设备物理位置，如"客厅""保姆间" |
| `lowPower` | boolean | 否 | 是否为低功耗设备（DeepSleep 模式）。`true` 时启用 3 倍唤醒周期离线检测，control 指令以 retained 发布 |
| `units` | array | 是 | 设备单元数组，至少包含一个单元 |

#### lowPower 字段详解

| 影响范围 | lowPower: true | lowPower: false / 缺省 |
| --- | --- | --- |
| **离线检测** | 超时 = 唤醒周期 × 3（如 5 分钟唤醒 → 15 分钟超时） | 超时 = 固定 5 分钟 |
| **control 指令 retain** | `retain: true`（设备睡眠期间指令保留在 broker，唤醒后接收） | `retain: false`（实时下发，不保留） |
| **唤醒时间单元** | 设备组内应有 `name: "唤醒时间"` 的 data 单元，status 为唤醒周期（分钟） | 不需要 |

### 2.2 设备单元字段

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | string | 是 | 设备单元唯一 ID，格式为 `设备组ID_单元名拼音-4位数字`（如 `keting-AC-23343313_kg01-6432`） |
| `name` | string | 是 | 设备单元名称，支持中文（如"温度上限""开关"） |
| `status` | string/number/boolean | 是 | 设备单元当前状态值，初始值在 devices.json 中定义，运行时由 MQTT 消息动态更新 |
| `type` | string | 是 | 设备单元类型，取值：`control` / `state` / `data` / `text` |
| `customIcon` | string | 否 | 自定义图标（Emoji），前端/App 展示用，如 `"🐟"` |

#### id 命名规则

```
设备组ID_单元名拼音-4位随机数字
示例：keting-AC-23343313_wendushangxian-6735
      └── 设备组ID ──┘ └─ 单元名拼音 ─┘ └随机数┘
```

- **单元名拼音**：中文名称转拼音，去除空格和特殊字符（由配置服务自动生成）
- **4 位随机数字**：防止同名单元冲突
- 特殊约定：系统通过 `unit.name === '唤醒时间'` 或 `unit.id.includes('huanxingshijian')` 识别唤醒时间单元

---

## 三、设备类型及业务用途

### 3.1 类型总览

| 类型 | 中文名 | 业务用途 | 消息方向 | 离线检测 | 前端交互方式 |
| --- | --- | --- | --- | --- | --- |
| `control` | 控制型 | 开关类设备（继电器、舵机），可远程控制 ON/OFF | 服务端→设备端（control）/ 设备端→服务端（state） | ✅ 参与 | ON/OFF 按钮 |
| `state` | 状态型 | 传感器数据（温度、水位），只读不可控 | 设备端→服务端（state） | ❌ 不参与 | 查询按钮（QUERY） |
| `data` | 数据型 | 数值参数（温度上限、唤醒时间），可读写 | 双向（datasetting） | ❌ 不参与 | 数值编辑框 |
| `text` | 文本型 | 文本参数（备注、描述），可读写 | 双向（textsetting） | ❌ 不参与 | 文本编辑框 |

### 3.2 各类型详细说明

#### control（控制型）

**业务用途**：远程控制开关类设备，如继电器、舵机、灯控开关。

**设备行为**：
- 设备订阅 `iot/device/{unitId}/control` 接收控制指令
- 设备执行后发布 `iot/device/{unitId}/state` 上报当前状态
- 离线检测基于该类型的 state 消息活跃时间

**特殊指令**：
| 指令 | 说明 | 适用设备 |
| --- | --- | --- |
| `ON` | 开启 | 所有 control 设备 |
| `OFF` | 关闭 | 所有 control 设备 |
| `QUERY` | 查询当前状态（设备收到后上报 state） | 所有 control 设备 |
| `AUTO` | 恢复自动模式 | 仅 lowPower 设备（如 AC01） |
| `OTA` | 触发 OTA 升级窗口 | 仅 lowPower 设备（如 AC01） |

**离线检测**：
- 常在线设备：5 分钟无 state 消息 → 标记离线
- lowPower 设备：3 × 唤醒周期无 state 消息 → 标记离线

**实际示例**：
```json
{
  "id": "baomujian-sdj-40858013_kaiguan-2966",
  "name": "开关",
  "status": "OFF",
  "type": "control"
}
```

#### state（状态型）

**业务用途**：只读传感器数据，如温度、水位、湿度。设备端主动上报，前端不可控制。

**设备行为**：
- 设备定时发布 `iot/device/{unitId}/state` 上报传感器数据
- 前端可通过 QUERY 指令主动查询（需对应设备支持）
- 不参与离线检测

**值类型**：支持任意类型（number、string、boolean、object），服务端通过 `JSON.parse` 保留原始类型。

**实际示例**：
```json
{
  "id": "keting-wdj-46716033_wdcgq-8684",
  "name": "温度传感器",
  "status": "25",
  "type": "state"
}
```

#### data（数据型）

**业务用途**：数值参数配置，如温度上限/下限、起始角度、唤醒时间。前端可编辑，设备端可读取。

**设备行为**：
- 服务端通过 `iot/device/{unitId}/datasetting` 下发参数（retain: true）
- 设备唤醒/连接时订阅该主题，获取最新参数
- 设备可反向发布该主题同步本地参数到服务端

**特殊约定**：
- lowPower 设备组中 `name: "唤醒时间"` 的 data 单元被系统用于计算离线检测超时
- AC01 的 `name: "控制模式"` 的 data 单元用于联动前端"恢复自动"按钮状态

**实际示例**：
```json
{
  "id": "keting-AC-23343313_wendushangxian-6735",
  "name": "温度上限",
  "status": "28",
  "type": "data"
}
```

#### text（文本型）

**业务用途**：文本类参数，如设备备注、描述信息。前端可编辑，设备端可读取。

**设备行为**：
- 服务端通过 `iot/device/{unitId}/textsetting` 下发文本（retain: true）
- 设备订阅该主题获取最新文本

**实际示例**：
```json
{
  "id": "keting-ktd-60614408_beizhu-1234",
  "name": "备注",
  "status": "客厅主灯",
  "type": "text"
}
```

---

## 四、消息格式定义

### 4.1 MQTT 主题设计

所有主题统一前缀为 `iot/device`，格式为 `iot/device/{unitId}/{主题类型}`。

| 主题格式 | 用途 | 消息方向 | retain 策略 |
| --- | --- | --- | --- |
| `iot/device/{unitId}/control` | 控制指令 | 服务端 → 设备端 | lowPower: `retain: true`；常在线: `retain: false` |
| `iot/device/{unitId}/state` | 状态上报 | 设备端 → 服务端 | 开关/模式状态: `retain: true`；瞬态传感数据: `retain: false` |
| `iot/device/{unitId}/datasetting` | 数值参数设置 | 双向（服务端↔设备端） | `retain: true`（一律保留） |
| `iot/device/{unitId}/textsetting` | 文本参数设置 | 双向（服务端↔设备端） | `retain: true`（一律保留） |

### 4.2 消息 Payload 格式

#### control 消息

```
主题：iot/device/keting-AC-23343313_kg01-6432/control
Payload：ON          ← 纯文本，无引号
```

| 指令 | Payload | 说明 |
| --- | --- | --- |
| 开启 | `ON` | 大写纯文本 |
| 关闭 | `OFF` | 大写纯文本 |
| 查询 | `QUERY` | 大写纯文本 |
| 自动 | `AUTO` | 仅 lowPower 设备 |
| 升级 | `OTA` | 仅 lowPower 设备 |

#### state 消息

```
主题：iot/device/keting-wdj-46716033_wdcgq-8684/state
Payload：25.5         ← 数字（JSON.parse → number）

主题：iot/device/baomujian-sdj-40858013_kaiguan-2966/state
Payload：ON           ← 字符串（JSON.parse 失败 → 保留 string）
```

| 值类型 | Payload 示例 | 解析结果类型 | 说明 |
| --- | --- | --- | --- |
| 数字 | `25.5` | `number` | 温度、湿度等 |
| 整数 | `80` | `number` | 湿度、计数等 |
| 字符串 | `ON` | `string` | 开关状态 |
| 布尔值 | `true` | `boolean` | 传感器触发状态 |
| JSON | `{"temp":25,"hum":60}` | `object` | 复合数据 |

**服务端解析逻辑**：
```javascript
let stateValue;
try {
  stateValue = JSON.parse(message.toString());  // 尝试解析为原始类型
} catch {
  stateValue = message.toString();              // 解析失败则保留字符串
}
```

#### datasetting 消息

```
主题：iot/device/keting-AC-23343313_wendushangxian-6735/datasetting
Payload：28            ← 纯数字文本
```

#### textsetting 消息

```
主题：iot/device/keting-ktd-60614408_beizhu-1234/textsetting
Payload：客厅主灯      ← 纯文本
```

### 4.3 WebSocket 推送消息格式

#### state-update（状态更新推送）

```json
{
  "type": "state-update",
  "device": {
    "type": "AC01",
    "id": "keting-AC-23343313",
    "category": "relay",
    "unit": "keting-AC-23343313_kg01-6432",
    "unitType": "control",
    "online": true
  },
  "state": "ON",
  "topic": "iot/device/keting-AC-23343313_kg01-6432/state",
  "timestamp": "2026-09-02T10:30:00.000Z"
}
```

#### offline-update（离线状态推送）

```json
{
  "type": "state-update",
  "device": {
    "type": "AC01",
    "id": "keting-AC-23343313",
    "category": "relay",
    "unit": "keting-AC-23343313_kg01-6432",
    "unitType": "control",
    "online": false
  },
  "state": "OFFLINE",
  "topic": "iot/device/keting-AC-23343313_kg01-6432/state",
  "timestamp": "2026-09-02T10:30:00.000Z"
}
```

---

## 五、不同类型的设备 API 调用接口

### 5.1 服务端口总览

| 服务 | 文件 | 端口 | 功能 |
| --- | --- | --- | --- |
| 配置服务 | `server-config.js` | 3001 | 设备配置管理 CRUD |
| 控制服务 | `server-control-tcp.js` | 3002 | 控制指令下发、参数设置、状态查询 |
| 状态服务 | `server-status-ws.js` | 8090 | WebSocket 实时状态推送 |

### 5.2 control 类型 API

#### 发送控制指令

```http
POST /api/control
Content-Type: application/json

{
  "cmd": "ON",
  "deviceType": "AC01",
  "deviceId": "keting-AC-23343313",
  "category": "relay",
  "unitId": "keting-AC-23343313_kg01-6432",
  "unitType": "control"
}
```

| 参数 | 说明 |
| --- | --- |
| `cmd` | 指令：`ON` / `OFF` / `QUERY` / `AUTO` / `OTA` |
| `deviceType` | 设备组标识（如 `AC01`） |
| `deviceId` | 设备组 ID |
| `category` | 设备类别（如 `relay`） |
| `unitId` | 设备单元 ID |
| `unitType` | 固定 `control` |

**响应**：
```json
{
  "code": 200,
  "msg": "指令 ON 已通过内网TCP下发到 keting-AC-23343313_kg01-6432 (type: control, retained)"
}
```

**retain 策略**：服务端自动查询设备组是否 `lowPower: true`，是则 retained 发布。

#### 简化控制接口

```http
POST /api/control-slot
Content-Type: application/json

{
  "slot": "keting-AC-23343313_kg01-6432",
  "cmd": "ON"
}
```

### 5.3 state 类型 API

#### 查询状态

state 类型设备通过 WebSocket 实时接收状态推送，也可通过 control 接口发送 QUERY 指令主动查询：

```http
POST /api/control-slot
Content-Type: application/json

{
  "slot": "keting-wdj-46716033_wdcgq-8684",
  "cmd": "QUERY"
}
```

**响应流程**：
1. 服务端通过 MQTT 发送 `QUERY` 到 `iot/device/{unitId}/control`
2. 设备收到后发布 `state` 到 `iot/device/{unitId}/state`
3. 状态服务订阅后通过 WebSocket 推送 `state-update` 消息
4. 前端监听 WebSocket 消息获取实时值（5 秒超时回退缓存值）

#### 获取所有设备状态

```http
GET /api/status
```

**响应**：
```json
{
  "code": 200,
  "mqttConnected": true,
  "states": {
    "keting-AC-23343313_kg01-6432": "ON",
    "baomujian-sdj-40858013_kaiguan-2966": "OFFLINE"
  },
  "online": {
    "keting-AC-23343313_kg01-6432": true,
    "baomujian-sdj-40858013_kaiguan-2966": false
  },
  "configs": { ... }
}
```

### 5.4 data 类型 API

#### 设置数值参数

```http
POST /api/set-data
Content-Type: application/json

{
  "slot": "keting-AC-23343313_wendushangxian-6735",
  "value": 28
}
```

**响应**：
```json
{
  "code": 200,
  "msg": "数据设置成功，目标：插槽 keting-AC-23343313_wendushangxian-6735，值：28"
}
```

**MQTT 消息**：服务端发布到 `iot/device/{unitId}/datasetting`，`retain: true`。

### 5.5 text 类型 API

#### 设置文本参数

```http
POST /api/set-text
Content-Type: application/json

{
  "slot": "keting-ktd-60614408_beizhu-1234",
  "value": "客厅主灯"
}
```

**响应**：
```json
{
  "code": 200,
  "msg": "文本设置成功，目标：插槽 keting-ktd-60614408_beizhu-1234，值：客厅主灯"
}
```

**MQTT 消息**：服务端发布到 `iot/device/{unitId}/textsetting`，`retain: true`。

### 5.6 设备配置管理 API（配置服务 3001 端口）

#### 设备组管理

| 接口 | 方法 | 说明 |
| --- | --- | --- |
| `/api/devices` | GET | 获取所有设备组 |
| `/api/devices` | POST | 创建设备组 |
| `/api/devices/{groupName}` | GET | 获取单个设备组详情 |
| `/api/devices/{groupName}` | PUT | 修改设备组 |
| `/api/devices/{groupName}` | DELETE | 删除设备组 |
| `/api/all-units` | GET | 获取所有设备单元列表 |

#### 设备单元管理

| 接口 | 方法 | 说明 |
| --- | --- | --- |
| `/api/devices/{groupName}/units` | GET | 获取设备组所有单元 |
| `/api/devices/{groupName}/units` | POST | 添加设备单元 |
| `/api/devices/{groupName}/units/{unitId}` | GET | 获取单个单元 |
| `/api/devices/{groupName}/units/{unitId}` | PUT | 修改单元 |
| `/api/devices/{groupName}/units/{unitId}` | DELETE | 删除单元 |

**创建设备单元示例**：
```http
POST /api/devices/AC01/units
Content-Type: application/json

{
  "name": "湿度上限",
  "type": "data",
  "status": "60"
}
```

---

## 六、其它描述和说明

### 6.1 retain 策略总结

| 主题类型 | 发布方 | retain | 说明 |
| --- | --- | --- | --- |
| `datasetting` / `textsetting` | 服务端 → broker | ✅ 一律 `true` | 参数是持久配置，最后写入者获胜；设备重启/唤醒能从 broker 恢复最新值 |
| `control` | 服务端 → broker | 按 lowPower 区分 | lowPower: `true`（离线缓冲）；常在线: `false`（防重复触发） |
| `state`（开关/模式） | 设备 → broker | ✅ `true` | 持久运行状态，前端打开应看到最后状态 |
| `state`（传感器数据） | 设备 → broker | ❌ `false` | 瞬态值，retained 会让过期数据误导前端 |

### 6.2 离线检测机制

| 设备类型 | 检测对象 | 超时规则 | 说明 |
| --- | --- | --- | --- |
| control（常在线） | control 单元的 state 消息 | 固定 5 分钟 | `OFFLINE_TIMEOUT` 环境变量可调 |
| control（lowPower） | control 单元的 state 消息 | 唤醒周期 × 3 | 从 devices.json 的"唤醒时间"单元读取 |
| state / data / text | 不检测 | — | 不参与离线检测 |

**超时计算示例**：

| 设备 | lowPower | 唤醒时间 | 离线超时 |
| --- | --- | --- | --- |
| AC01 | true | 5 分钟 | 15 分钟 |
| AC01（修改后） | true | 10 分钟 | 30 分钟 |
| kqyws 喂食器 | 无 | — | 5 分钟 |
| ktd 客厅灯 | 无 | — | 5 分钟 |

### 6.3 设备组前端显示规则

| 状态 | 图标颜色 | 透明度 | 说明 |
| --- | --- | --- | --- |
| 全部 control 单元 ON | 绿色 | 100% | 所有设备开启 |
| 部分 control 单元 ON | 橙色 | 100% | 部分设备开启 |
| 全部 control 单元 OFF | 黑色 | 100% | 所有设备关闭 |
| 任一 control 单元离线 | 灰色 | 60% | 灰度化 + 透明度降低 |

### 6.4 devices.json 完整示例

```json
{
  "AC01": {
    "name": "AC01",
    "displayName": "空调一",
    "id": "keting-AC-23343313",
    "location": "客厅",
    "lowPower": true,
    "units": [
      {
        "id": "keting-AC-23343313_kg01-6432",
        "name": "kg01",
        "status": "OFF",
        "type": "control"
      },
      {
        "id": "keting-AC-23343313_kongzhimoshi-5321",
        "name": "控制模式",
        "status": "自动",
        "type": "data"
      },
      {
        "id": "keting-AC-23343313_wendushangxian-6735",
        "name": "温度上限",
        "status": "28",
        "type": "data"
      },
      {
        "id": "keting-AC-23343313_wenduxiaxian-5249",
        "name": "温度下限",
        "status": "20",
        "type": "data"
      },
      {
        "id": "keting-AC-23343313_qishijiaodu-9064",
        "name": "起始角度",
        "status": "0",
        "type": "data"
      },
      {
        "id": "keting-AC-23343313_zhongzhijiaodu-1986",
        "name": "终止角度",
        "status": "60",
        "type": "data"
      },
      {
        "id": "keting-AC-23343313_huanxingshijian-7645",
        "name": "唤醒时间",
        "status": "5",
        "type": "data"
      }
    ]
  },
  "wdj": {
    "name": "wdj",
    "displayName": "温度计",
    "id": "keting-wdj-46716033",
    "location": "客厅",
    "units": [
      {
        "id": "keting-wdj-46716033_wdcgq-8684",
        "name": "温度传感器",
        "status": "25",
        "type": "state"
      },
      {
        "id": "keting-wdj-46716033_fasongjiange-6920",
        "name": "发送间隔",
        "status": "30",
        "type": "data"
      }
    ]
  },
  "sdj": {
    "name": "sdj",
    "displayName": "扫地机",
    "id": "baomujian-sdj-40858013",
    "location": "保姆间",
    "units": [
      {
        "id": "baomujian-sdj-40858013_kaiguan-2966",
        "name": "开关",
        "status": "OFF",
        "type": "control"
      }
    ]
  },
  "shg": {
    "name": "shg",
    "displayName": "珊瑚缸",
    "id": "keting-shg-64771774",
    "location": "客厅",
    "units": [
      {
        "id": "keting-shg-64771774_fengshan-0838",
        "name": "风扇",
        "status": "OFF",
        "type": "control"
      },
      {
        "id": "keting-shg-64771774_yangqi-0041",
        "name": "氧气",
        "status": "ON",
        "type": "control"
      },
      {
        "id": "keting-shg-64771774_weishi-3278",
        "name": "喂食",
        "status": "ON",
        "type": "control"
      },
      {
        "id": "keting-shg-64771774_gongshui-5747",
        "name": "供水",
        "status": "ON",
        "type": "control"
      },
      {
        "id": "keting-shg-64771774_gaoshuiweichuanganqi-5209",
        "name": "高水位传感器",
        "status": "ON",
        "type": "state"
      },
      {
        "id": "keting-shg-64771774_dishuiweichuanganqi-9611",
        "name": "低水位传感器",
        "status": "ON",
        "type": "state"
      },
      {
        "id": "keting-shg-64771774_wenduchuanganqi-5906",
        "name": "温度传感器",
        "status": "35",
        "type": "state"
      },
      {
        "id": "keting-shg-64771774_wendushangxianzhi-3641",
        "name": "温度上限值",
        "status": "31",
        "type": "data"
      },
      {
        "id": "keting-shg-64771774_wenduxiaxianzhi-1602",
        "name": "温度下线值",
        "status": "26",
        "type": "data"
      }
    ]
  },
  "kqyws": {
    "name": "kqyws",
    "displayName": "孔雀鱼喂食",
    "id": "keting-kqyws-30616007",
    "location": "客厅",
    "units": [
      {
        "id": "keting-kqyws-30616007_weishiqi-0344",
        "name": "喂食器",
        "status": "OFF",
        "type": "control",
        "customIcon": "🐟"
      },
      {
        "id": "keting-kqyws-30616007_weishisudu-8389",
        "name": "喂食速度",
        "status": "20",
        "type": "data"
      }
    ]
  },
  "lastUpdated": "2026-09-02T08:12:54.449Z"
}
```

### 6.5 新增设备组流程

1. **通过配置 API 创建**：
   ```http
   POST /api/devices
   {
     "name": "wsj",
     "displayName": "卫生间灯",
     "location": "卫生间",
     "units": [
       {
         "name": "开关",
         "type": "control",
         "status": "OFF"
       }
     ]
   }
   ```
2. 系统自动生成设备组 ID 和单元 ID（拼音转换 + 随机数字后缀）
3. 写入 `devices.json` 并更新 `lastUpdated`
4. 状态服务和控制服务检测到文件变化后自动刷新缓存

### 6.6 lowPower 设备组配置要点

新增 lowPower 设备组时需注意：

1. **设备组级别**添加 `"lowPower": true`
2. **必须包含**一个唤醒时间 data 单元：
   ```json
   {
     "name": "唤醒时间",
     "status": "5",
     "type": "data"
   }
   ```
   - `name` 为"唤醒时间"或 `id` 含 `huanxingshijian`
   - `status` 为唤醒周期（分钟），整数字符串
3. **control 单元的指令**会自动以 retained 模式发布
4. **离线超时**自动按 `唤醒时间 × 3` 计算

### 6.7 已知限制

| 限制 | 说明 |
| --- | --- |
| 仅 control 类型参与离线检测 | state/data/text 类型设备不显示离线状态 |
| 唤醒时间需手动维护 | 修改唤醒时间后需同步更新 devices.json 和固件中的值 |
| 配置文件存储 | 使用 JSON 文件存储，非数据库，高并发场景需考虑文件锁 |
| state 消息 retain 需设备端配合 | 服务端不发布 state，retain 策略由设备端 publish 代码决定 |

---

**文档版本**: v1.0  
**生成日期**: 2026-09-02  
**适用版本**: IoT Web AI v11
