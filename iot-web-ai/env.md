
使用 `.env` 文件管理敏感配置是**最佳实践**，可以避免将密码、密钥等敏感信息硬编码到代码中，提高安全性。

---

## 🚀 基本概念

### 什么是 .env 文件？
`.env` 是一个环境变量配置文件，用于存储敏感信息和配置参数，格式为 `KEY=VALUE`。

### 为什么使用 .env？
- ✅ **安全性**：敏感信息不会提交到版本控制
- ✅ **灵活性**：不同环境可以使用不同配置
- ✅ **简洁性**：集中管理所有配置

---

## 🔧 使用步骤

### 1. 创建 .env 文件

在项目根目录创建 `.env` 文件：

```bash
touch .env
```

### 2. 配置敏感信息

```env
# ============ 服务器配置 ============
SERVER_IP=192.168.1.40
WS_PORT=8090

# ============ MQTT 服务器配置 ============
MQTT_EXTERNAL_WS_SERVER=ws://192.168.1.40:8083/mqtt
MQTT_INTERNAL_SERVER=mqtt://192.168.1.40:1883
MQTT_USERNAME=username
MQTT_PASSWORD=your-mqtt-password
MQTT_TOPIC_PREFIX=iotdomianname/devicename

# ============ 服务端口配置 ============
CONFIG_SERVICE_PORT=8001
CONTROL_SERVICE_PORT=8002

# ============ AI 配置 ============
OLLAMA_HOST=http://192.168.1.51:11434
AI_MODEL=qwen2.5:1.5b

# ============ 数据库配置（如果使用） ============
DB_HOST=localhost
DB_PORT=5432
DB_NAME=iot_db
DB_USER=admin
DB_PASSWORD=your-db-password```

### 3. 安装 dotenv 依赖

```bash
npm install dotenv --save
```

### 4. 在代码中加载 .env

在 Node.js 服务文件开头添加：

```javascript
// server-control-tcp.js
require('dotenv').config();  // 加载 .env 文件

// 使用环境变量
const mqttServer = process.env.MQTT_INTERNAL_SERVER;
const mqttUsername = process.env.MQTT_USERNAME;
const mqttPassword = process.env.MQTT_PASSWORD;
```

### 5. 配置多个环境（可选）

创建不同环境的配置文件：

```bash
# 开发环境
.env.development

# 测试环境
.env.test

# 生产环境
.env.production
```

加载指定环境的配置：

```javascript
require('dotenv').config({ path: `.env.${process.env.NODE_ENV}` });
```

启动时指定环境：

```bash
NODE_ENV=production npm run start
```

---

## 📝 在代码中使用环境变量

### 示例 1：配置 MQTT 连接

```javascript
// server-control-tcp.js
require('dotenv').config();

const mqtt = require('mqtt');

const client = mqtt.connect(process.env.MQTT_INTERNAL_SERVER, {
  username: process.env.MQTT_USERNAME,
  password: process.env.MQTT_PASSWORD,
  clientId: 'iot-control-server'
});
```

### 示例 2：配置服务端口

```javascript
// server-config.js
require('dotenv').config();

const express = require('express');
const app = express();

const PORT = process.env.CONFIG_SERVICE_PORT || 6001;

app.listen(PORT, () => {
  console.log(`配置服务启动: http://${process.env.SERVER_IP}:${PORT}`);
});
```

### 示例 3：配置 API 接口

```javascript
// index.html (前端)
<script>
const api = '/api';
const wsUrl = `ws://${window.location.hostname}:${process.env.WS_PORT || 9084}`;
</script>
```

---

## 🛡️ 安全注意事项

### 1. 必须添加到 .gitignore

**创建或修改 `.gitignore` 文件**：

```gitignore
# 环境变量文件
.env
.env.local
.env.*.local

# PM2 配置
.pm2/

# 日志文件
logs/
*.log

# 数据文件
data/
```

### 2. 设置正确的文件权限

```bash
# 限制文件访问权限（仅所有者可读）
chmod 600 .env
```

### 3. 不要在前端暴露敏感信息

**错误做法**：
```javascript
// ❌ 不要在前端代码中使用敏感配置
const apiKey = process.env.API_KEY;  // 会暴露给用户
```

**正确做法**：
- 敏感配置只在后端使用
- 前端只使用非敏感配置（如端口号、API地址）

### 4. 使用配置模板

创建 `.env.example` 文件作为模板：

```env
# .env.example - 配置模板
SERVER_IP=your-server-ip
WS_PORT=9084
MQTT_USERNAME=your-mqtt-username
MQTT_PASSWORD=your-mqtt-password
```

---

## ✅ 最佳实践

### 1. 使用统一的命名规范

```env
# 推荐：使用大写字母和下划线
DB_HOST=localhost
DB_PORT=5432

# 不推荐：使用小写或连字符
db-host=localhost  # ❌
dbPort=5432        # ❌
```

### 2. 添加注释说明

```env
# MQTT 服务器配置
MQTT_SERVER=mqtt://localhost:1883  # MQTT broker 地址
MQTT_USERNAME=admin                # 认证用户名
MQTT_PASSWORD=secret               # 认证密码（生产环境使用强密码）
```

### 3. 设置默认值

```javascript
// 在代码中设置默认值，防止配置缺失
const port = process.env.PORT || 6000;
const debug = process.env.DEBUG || 'false';
```

### 4. 使用配置验证

```javascript
// 验证必要的配置项
const requiredEnvVars = ['MQTT_SERVER', 'MQTT_USERNAME', 'MQTT_PASSWORD'];

requiredEnvVars.forEach(varName => {
  if (!process.env[varName]) {
    console.error(`❌ 缺少必要配置: ${varName}`);
    process.exit(1);
  }
});
```

### 5. 使用配置管理工具（高级）

对于复杂项目，可以使用专业的配置管理工具：

| 工具              | 说明           |
| ----------------- | -------------- |
| **dotenv-expand** | 支持变量引用   |
| **config**        | 支持多环境配置 |
| **joi**           | 配置验证       |

```javascript
// 使用 joi 验证配置
const Joi = require('joi');

const schema = Joi.object({
  MQTT_SERVER: Joi.string().required(),
  MQTT_PORT: Joi.number().default(1883),
  MQTT_USERNAME: Joi.string().required(),
  MQTT_PASSWORD: Joi.string().required()
});

const { error, value } = schema.validate(process.env);
if (error) {
  console.error('配置验证失败:', error.message);
  process.exit(1);
}
```

---

## 📋 配置文件示例

### 完整的 .env 文件

```env
# ==============================================================================
# IoT Web AI - 环境变量配置文件
# ==============================================================================

# ------------------------------
# 服务器基础配置
# ------------------------------
SERVER_IP=192.168.6.40          # 服务器IP地址
NODE_ENV=production              # 运行环境: development / test / production

# ------------------------------
# 服务端口配置
# ------------------------------
CONFIG_SERVICE_PORT=6001         # 配置服务端口
CONTROL_SERVICE_PORT=6002        # 控制服务端口
WS_PORT=9090                     # WebSocket状态服务端口

# ------------------------------
# MQTT 服务器配置
# ------------------------------
MQTT_INTERNAL_SERVER=mqtt://192.168.6.40:1883       # 内网MQTT TCP地址
MQTT_EXTERNAL_WS_SERVER=ws://192.168.6.40:8083/mqtt # 外网MQTT WebSocket地址
MQTT_USERNAME=username                                     # MQTT认证用户名
MQTT_PASSWORD=your-mqtt-password                          # MQTT认证密码
MQTT_TOPIC_PREFIX=iotxxx/devicename                        # MQTT主题前缀

# ------------------------------
# AI 配置
# ------------------------------
OLLAMA_HOST=http://192.168.1.51:11434  # Ollama服务地址
AI_MODEL=qwen2.5:1.5b                  # 默认AI模型

# ------------------------------
# 日志配置
# ------------------------------
LOG_LEVEL=info                         # 日志级别: debug / info / warn / error
LOG_FILE=./logs/app.log                # 日志文件路径

# ------------------------------
# 安全配置
# ------------------------------
JWT_SECRET=your-jwt-secret-key         # JWT密钥（用于API认证）
CORS_ORIGIN=http://localhost:8080      # 允许的跨域来源

# ------------------------------
# 数据库配置（如使用）
# ------------------------------
# DB_HOST=localhost
# DB_PORT=5432
# DB_NAME=iot_db
# DB_USER=admin
# DB_PASSWORD=your-db-password
```

---

## 🚀 启动服务

```bash
# 开发环境
npm run start

# 生产环境（指定环境变量）
NODE_ENV=production npm run pm2-iot
```

---

## 📌 总结

| 步骤 | 操作                | 说明                   |
| ---- | ------------------- | ---------------------- |
| 1    | 创建 `.env`         | 存储敏感配置           |
| 2    | 安装 dotenv         | 加载环境变量           |
| 3    | 代码中使用          | `process.env.VAR_NAME` |
| 4    | 更新 `.gitignore`   | 防止泄露敏感信息       |
| 5    | 创建 `.env.example` | 提供配置模板           |

> **提示**：定期轮换敏感密码，使用强密码策略，并确保只有授权人员能够访问服务器上的 `.env` 文件。