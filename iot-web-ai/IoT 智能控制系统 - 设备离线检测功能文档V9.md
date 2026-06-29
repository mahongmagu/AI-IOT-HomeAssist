
# IoT 智能控制系统 - 设备离线检测功能文档

---

## 文档版本

| 版本 | 日期       | 作者     | 变更说明 |
| ---- | ---------- | -------- | -------- |
| V1.0 | 2026-05-11 | IoT Team | 初始版本 |

---

## 1. 功能概述

### 1.1 功能背景

在 IoT 智能控制系统中，设备可能因为网络故障、电源断开等原因离线。为了提升用户体验，需要实时检测设备在线状态，并在前端直观展示。

### 1.2 功能描述

当控制设备超过指定时间（默认5分钟）未发送 MQTT 状态信息时：
- 系统自动标记设备为离线状态
- 前端设备组图标显示为灰色（灰度化效果）
- 显示离线提示标识
- API 接口返回设备在线状态信息

### 1.3 功能目标

| 目标     | 描述                            |
| -------- | ------------------------------- |
| 实时检测 | 每30秒检查一次设备活跃状态      |
| 超时标记 | 超过5分钟无状态更新则标记离线   |
| 前端展示 | 离线设备组图标显示灰色          |
| 状态同步 | 通过 WebSocket 实时同步离线状态 |

---

## 2. 技术方案

### 2.1 架构设计

```
┌─────────────────────────────────────────────────────────────────┐
│                        系统架构                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  前端 (index.html)                                              │
│  ├── WebSocket连接 → server-status-ws.js                       │
│  └── HTTP API → server-control-tcp.js                          │
│                                                                 │
│  后端服务                                                       │
│  ├── server-status-ws.js (外网WebSocket状态服务)                │
│  │   ├── 订阅MQTT状态主题                                       │
│  │   ├── 记录设备活跃时间                                       │
│  │   ├── 定时检查离线设备                                       │
│  │   └── 广播离线状态到前端                                     │
│  │                                                              │
│  └── server-control-tcp.js (内网控制服务)                       │
│      ├── 记录设备活跃时间                                       │
│      ├── 定时检查离线设备                                       │
│      └── API返回在线状态                                       │
│                                                                 │
│  MQTT Broker (EMQX)                                            │
│  ├── 端口 1883 (TCP) - 内网                                    │
│  └── 端口 8083 (WebSocket) - 外网                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 核心流程

```
设备发送MQTT状态 ──> updateDeviceActive() 记录时间戳
                          │
                          ▼
              每30秒 checkOfflineDevices() 定时检查
                          │
                          ▼
              超过OFFLINE_TIMEOUT？
                ├── 是 ──> 标记为OFFLINE ──> 广播到WebSocket
                │
                └── 否 ──> 保持在线状态
                          │
                          ▼
              前端更新设备组显示
                ├── 在线 ──> 正常颜色(绿/橙/黑)
                └── 离线 ──> 灰色(灰度化+透明度降低)
```

### 2.3 数据结构

#### 2.3.1 设备活跃时间记录

```javascript
// 内存缓存结构
deviceLastActive = {
  "baomujian-sdj-40858013_kaiguan-2966": 1715401200000,  // timestamp
  "keting-shg-64771774_fengshan-0838": 1715401230000
};
```

#### 2.3.2 离线状态消息格式

```json
{
  "type": "state-update",
  "device": {
    "type": "sdj",
    "id": "baomujian-sdj-40858013",
    "category": "relay",
    "unit": "baomujian-sdj-40858013_kaiguan-2966",
    "unitType": "control",
    "online": false
  },
  "state": "OFFLINE",
  "topic": "iotxxx/devicename/baomujian-sdj-40858013_kaiguan-2966/state",
  "timestamp": "2026-05-11T10:30:00.000Z"
}
```

#### 2.3.3 API 响应格式

```json
{
  "code": 200,
  "mqttConnected": true,
  "states": {
    "baomujian-sdj-40858013_kaiguan-2966": "ON",
    "keting-shg-64771774_fengshan-0838": "OFFLINE"
  },
  "online": {
    "baomujian-sdj-40858013_kaiguan-2966": true,
    "keting-shg-64771774_fengshan-0838": false
  },
  "configs": { ... }
}
```

---

## 3. 配置说明

### 3.1 环境变量配置

| 配置项            | 默认值 | 说明                            |
| ----------------- | ------ | ------------------------------- |
| `OFFLINE_TIMEOUT` | 300000 | 离线超时时间（毫秒），默认5分钟 |
| `CHECK_INTERVAL`  | 30000  | 定时检查间隔（毫秒），默认30秒  |

### 3.2 .env 文件示例

```bash
# .env
SERVER_IP=192.168.1.40
WS_PORT=9090

# MQTT配置
MQTT_INTERNAL_SERVER=mqtt://192.168.1.40:1883
MQTT_EXTERNAL_WS_SERVER=ws://192.168.1.40:8083/mqtt
MQTT_USERNAME=username
MQTT_PASSWORD=your-mqtt-pawword
MQTT_TOPIC_PREFIX=iotxxx/devicename

# 设备离线检测配置
OFFLINE_TIMEOUT=300000  # 5分钟
CHECK_INTERVAL=30000    # 30秒

# 端口配置
CONTROL_SERVICE_PORT=6002
CONFIG_SERVICE_PORT=6001
```

---

## 4. 代码变更

### 4.1 变更文件清单

| 文件                    | 变更类型 | 说明                           |
| ----------------------- | -------- | ------------------------------ |
| `.env`                  | 新增配置 | 添加离线检测超时时间和检查间隔 |
| `server-status-ws.js`   | 新增功能 | 离线检测逻辑 + WebSocket广播   |
| `server-control-tcp.js` | 新增功能 | 离线检测逻辑 + API状态返回     |
| `index.html`            | 新增功能 | 离线设备灰色显示样式和逻辑     |

### 4.2 server-status-ws.js 关键代码

```javascript
// 设备活跃时间记录
let deviceLastActive = {};
const OFFLINE_TIMEOUT = parseInt(process.env.OFFLINE_TIMEOUT) || 300000;
const CHECK_INTERVAL = parseInt(process.env.CHECK_INTERVAL) || 30000;

// 更新设备活跃时间
function updateDeviceActive(unitId) {
  deviceLastActive[unitId] = Date.now();
}

// 检查离线设备
function checkOfflineDevices() {
  const now = Date.now();
  for (const [unitId, lastActive] of Object.entries(deviceLastActive)) {
    if (now - lastActive > OFFLINE_TIMEOUT) {
      broadcastOfflineStatus(unitId);
    }
  }
}

// 定时检查
setInterval(checkOfflineDevices, CHECK_INTERVAL);
```

### 4.3 server-control-tcp.js 关键代码

```javascript
// 修改 /api/status 接口
app.get('/api/status', async (req, res) => {
  const devices = await dataManager.getDevices();
  const now = Date.now();
  
  // 构建在线状态
  const onlineStatus = {};
  for (const [unitId, lastActive] of Object.entries(deviceLastActive)) {
    onlineStatus[unitId] = now - lastActive <= OFFLINE_TIMEOUT;
  }
  
  res.json({
    code: 200,
    mqttConnected: mqttConnected,
    states: cachedStates,
    online: onlineStatus,  // 新增在线状态字段
    configs: devices
  });
});
```

### 4.4 index.html 关键代码

```css
/* 离线设备样式 */
.device-icon.offline {
  background: linear-gradient(135deg, #6c757d 0%, #495057 100%);
  filter: grayscale(100%);
}
.device-card.offline { opacity: 0.6; }
```

---

## 5. 部署指南

### 5.1 部署步骤

1. **更新配置文件**
   ```bash
   # 编辑 .env 文件，确保包含以下配置
   OFFLINE_TIMEOUT=300000
   CHECK_INTERVAL=30000
   ```

2. **安装依赖**
   ```bash
   npm install
   ```

3. **启动服务**
   ```bash
   # 方式1：启动全部服务
   npm run home-assistant-AI
   
   # 方式2：单独启动
   npm run start    # 控制服务
   npm run status   # WebSocket状态服务
   npm run config   # 配置服务
   ```

4. **验证启动**
   ```bash
   # 查看日志确认离线检测已启动
   npm run pm2-logs
   # 期望输出：设备离线检测已启动 - 超时时间: 300秒, 检查间隔: 30秒
   ```

### 5.2 服务端口说明

| 服务     | 端口 | 说明                         |
| -------- | ---- | ---------------------------- |
| 控制服务 | 6002 | HTTP API，提供控制和状态查询 |
| 状态服务 | 9090 | WebSocket，实时推送状态      |
| 配置服务 | 6001 | HTTP API，提供设备配置       |

---

## 6. 测试验证

### 6.1 测试用例

| 测试场景     | 步骤                           | 预期结果                         |
| ------------ | ------------------------------ | -------------------------------- |
| 设备正常在线 | 启动服务，设备正常发送MQTT消息 | 设备组图标显示正常颜色           |
| 设备离线检测 | 断开设备网络，等待5分钟        | 设备组图标变为灰色，显示"⚠️ 离线" |
| 设备恢复在线 | 重新连接设备网络，发送状态消息 | 设备组图标恢复正常颜色           |
| API状态查询  | 调用 GET /api/status           | 返回 online 字段包含设备在线状态 |

### 6.2 测试命令

```bash
# 测试API接口
curl http://localhost:3002/api/status | python3 -m json.tool

# 测试WebSocket连接
wscat -c ws://localhost:8090
```

### 6.3 显示效果对比

| 状态     | 图标颜色 | 透明度  | 提示信息   |
| -------- | -------- | ------- | ---------- |
| 全部开启 | 绿色     | 100%    | 无         |
| 部分开启 | 橙色     | 100%    | 无         |
| 全部关闭 | 黑色     | 100%    | 无         |
| **离线** | **灰色** | **60%** | **⚠️ 离线** |

---

## 7. 故障排查

### 7.1 常见问题

| 问题              | 可能原因                 | 解决方案             |
| ----------------- | ------------------------ | -------------------- |
| 设备不显示离线    | OFFLINE_TIMEOUT 配置过大 | 检查 .env 配置       |
| WebSocket连接失败 | 端口未开放               | 检查防火墙和端口映射 |
| 离线状态不同步    | MQTT连接异常             | 检查MQTT Broker状态  |

### 7.2 日志查看

```bash
# 查看PM2日志
npm run pm2-logs

# 查看特定服务日志
pm2 logs AI-STA-server  # WebSocket状态服务
pm2 logs AI-CTL-server  # 控制服务
```

---

## 8. 扩展建议

### 8.1 功能扩展

- **离线告警**：设备离线时发送邮件/短信通知
- **历史记录**：记录设备离线/在线时间戳
- **超时配置**：支持按设备类型设置不同超时时间
- **设备分组离线**：设备组内所有设备离线时标记整组离线

### 8.2 性能优化

- **批量更新**：减少频繁的状态更新广播
- **缓存策略**：优化内存缓存管理
- **超时优化**：动态调整检查间隔

---

## 附录：代码变更对比

### A.1 .env 变更

```diff
+ OFFLINE_TIMEOUT=300000
+ CHECK_INTERVAL=30000
```

### A.2 server-status-ws.js 变更

```diff
+ let deviceLastActive = {};
+ const OFFLINE_TIMEOUT = parseInt(process.env.OFFLINE_TIMEOUT) || 300000;
+ const CHECK_INTERVAL = parseInt(process.env.CHECK_INTERVAL) || 30000;

+ function updateDeviceActive(unitId) { ... }
+ function checkOfflineDevices() { ... }
+ function broadcastOfflineStatus(unitId) { ... }
+ setInterval(checkOfflineDevices, CHECK_INTERVAL);
```

### A.3 server-control-tcp.js 变更

```diff
+ let deviceLastActive = {};
+ const OFFLINE_TIMEOUT = parseInt(process.env.OFFLINE_TIMEOUT) || 300000;
+ const CHECK_INTERVAL = parseInt(process.env.CHECK_INTERVAL) || 30000;

+ function updateDeviceActive(unitId) { ... }
+ function checkOfflineDevices() { ... }
+ setInterval(checkOfflineDevices, CHECK_INTERVAL);

app.get('/api/status', async (req, res) => {
  ...
+ const onlineStatus = {};
+ for (const [unitId, lastActive] of Object.entries(deviceLastActive)) {
+   onlineStatus[unitId] = now - lastActive <= OFFLINE_TIMEOUT;
+ }
  
  res.json({
    code: 200,
    mqttConnected: mqttConnected,
    states: cachedStates,
+   online: onlineStatus,
    configs: devices
  });
});
```

---

**文档结束**
        