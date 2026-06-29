
# IoT Web AI 项目更新文档

## 版本信息

| 项目     | 说明       |
| -------- | ---------- |
| 项目名称 | IoT Web AI |
| 版本     | v2.2.1     |
| 更新日期 | 2026-05-07 |

---

## 一、设备单元ID格式更新

### 修改内容

**旧格式**：`{位置}-{设备组名称}-{设备单元名称}-{4位数字}`

**新格式**：`{设备组ID}_{设备单元名称拼音}-{4位数字}`

### 修改文件

| 文件               | 位置        | 修改说明                 |
| ------------------ | ----------- | ------------------------ |
| `server-config.js` | 第208-212行 | 创建设备组时的单元ID生成 |
| `server-config.js` | 第469-474行 | 添加设备单元API的ID生成  |

### 示例

```json
// 设备组ID: baomujian-sdj-69506931
// 设备单元ID: baomujian-sdj-69506931_kaiguan-4647
```

---

## 二、MQTT主题格式更新

### 修改内容

**控制主题**：`iotxxx/devicename/{unitId}/control`

**状态主题**：`iotxxx/devicename/{unitId}/state`

**文本设置主题**：`iotxxx/devicename/{unitId}/textsetting`

**数据设置主题**：`iotxxx/devicename/{unitId}/datasetting`

### 修改文件

| 文件                    | 修改说明                              |
| ----------------------- | ------------------------------------- |
| `server-control-tcp.js` | 简化 `sendMqttControl` 函数签名       |
| `server-status-ws.js`   | 添加 textsetting/datasetting 主题订阅 |

### 主题用途

| 主题        | 方向          | 用途                   |
| ----------- | ------------- | ---------------------- |
| control     | 服务端→设备端 | 控制指令下发（ON/OFF） |
| state       | 设备端→服务端 | 设备状态上报           |
| textsetting | 双向          | 文本设置指令/反馈      |
| datasetting | 双向          | 数据设置指令/反馈      |

---

## 三、新增功能

### 3.1 文本设置（textsetting）

**API接口**：`POST /api/set-text`

**参数**：
| 参数  | 类型   | 说明       |
| ----- | ------ | ---------- |
| slot  | string | 设备单元ID |
| value | string | 文本值     |

**MQTT主题**：`iotxxx/devicename/{unitId}/textsetting`

### 3.2 数据设置（datasetting）

**API接口**：`POST /api/set-data`

**参数**：
| 参数  | 类型   | 说明       |
| ----- | ------ | ---------- |
| slot  | string | 设备单元ID |
| value | number | 数值       |

**MQTT主题**：`iotxxx/devicename/{unitId}/datasetting`

### 3.3 配置API接口

**API接口**：`GET /api/config`

**返回**：
```json
{
  "wsPort": 8084,
  "apiBase": "/api"
}
```

---

## 四、服务端优化

### 4.1 自动获取服务器IP

**文件**：`server-status-ws.js`

**功能**：启动时自动检测服务器IP地址

**优先级**：环境变量 `SERVER_IP` > 自动获取 > 默认值 `127.0.0.1`

### 4.2 配置加载错误处理优化

**文件**：`server-status-ws.js`

**改进**：配置文件写入不完整时不重置缓存，保持原有配置继续运行

### 4.3 dotenv环境变量支持

**文件**：`server-status-ws.js`

**改进**：添加 `require('dotenv').config()` 支持从 `.env` 文件读取配置

---

## 五、前端优化

### 5.1 WebSocket地址自动推断

**文件**：`index.html`

**功能**：前端自动使用当前页面所在服务器地址

```javascript
function getWsUrl() {
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const hostname = window.location.hostname;
  const port = 8084;
  return `${protocol}//${hostname}:${port}`;
}
```

### 5.2 状态来源显示

**功能**：显示状态来源主题类型（state/textsetting/datasetting）

**显示效果**：
```
状态: ENABLE_PIN (来源: textsetting)
```

### 5.3 设备类型操作按钮

| 类型    | 按钮      | 功能                     |
| ------- | --------- | ------------------------ |
| control | 打开/关闭 | 发送控制指令             |
| state   | 查询状态  | 刷新状态                 |
| text    | 编辑文本  | 弹出文本输入框           |
| data    | 编辑数值  | 弹出数值输入框（带验证） |

---

## 六、设备类型定义

| 类型    | 变量类型 | 状态输入方式     | 说明       |
| ------- | -------- | ---------------- | ---------- |
| control | 布尔     | 下拉选择(ON/OFF) | 控制型设备 |
| state   | 字符串   | 文本输入框       | 状态型设备 |
| text    | 字符串   | 文本输入框       | 文本型设备 |
| data    | 数字     | 数字输入框       | 数据型设备 |

---

## 七、环境变量配置

```env
# 服务器配置
SERVER_IP=192.168.1.149
WS_PORT=8084

# MQTT服务器配置
MQTT_EXTERNAL_WS_SERVER=ws://192.168.1.40:8083/mqtt
MQTT_INTERNAL_SERVER=mqtt://192.168.1.40:1883
MQTT_TOPIC_PREFIX=iotxxx/devicename
MQTT_USERNAME=username
MQTT_PASSWORD=your-mqtt-password

# 服务端口配置
CONFIG_SERVICE_PORT=6001
CONTROL_SERVICE_PORT=6002
```

---

## 八、服务启动命令

| 命令             | 服务     | 端口 |
| ---------------- | -------- | ---- |
| `npm run config` | 配置服务 | 6001 |
| `npm run start`  | 控制服务 | 6002 |
| `npm run status` | 状态服务 | 8084 |

---

## 九、数据流架构

```
前端浏览器
    ↓ (WebSocket: ws://{server}:8084)
server-status-ws.js (状态服务)
    ↓ (MQTT over WebSocket: ws://mqtt:8083/mqtt)
EMQX MQTT服务器
    ↓ (MQTT: tcp://mqtt:1883)
server-control-tcp.js (控制服务)
    ↓ (MQTT: tcp://mqtt:1883)
设备端
```

---

## 十、修复的问题

| 问题                 | 文件                                | 修复说明                                         |
| -------------------- | ----------------------------------- | ------------------------------------------------ |
| 端口冲突             | `.env`                              | 分离 CONFIG_SERVICE_PORT 和 CONTROL_SERVICE_PORT |
| 设备单元ID格式不一致 | `server-config.js`                  | 统一为设备组ID_设备单元名称拼音-数字             |
| 状态订阅不完整       | `server-status-ws.js`               | 添加 textsetting/datasetting 主题订阅            |
| 配置加载失败         | `server-status-ws.js`               | 添加错误处理，保持缓存                           |
| IP硬编码             | `server-status-ws.js`、`index.html` | 自动获取服务器IP                                 |
| 重复变量声明         | `server-status-ws.js`               | 删除重复的 SERVER_IP 声明                        |

---

## 十一、依赖安装

```bash
# 安装核心依赖
npm install

# 安装拼音转换库
npm install pinyin
```

---

## 十二、注意事项

1. **设备端需要更新订阅**：确保设备订阅新格式的主题 `iotxxx/devicename/+/control`
2. **状态反馈**：设备执行指令后需要通过 `state` 主题上报状态
3. **配置文件**：首次启动前确保 `.env` 文件配置正确
4. **端口权限**：确保使用 >1024 的端口避免权限问题
        