# 设备设置API和接口

设置设备单元开关的命令主要有三种方式：**API调用**、**MQTT消息**和**前端操作**。

---

## 🚀 方法一：使用 REST API（推荐）

### 发送控制命令

```bash
# 打开设备（ON）
curl -X POST http://localhost:6002/api/control \
  -H "Content-Type: application/json" \
  -d '{
    "unitId": "baomujian-sdj-40858013_kaiguan-2966",
    "cmd": "ON"
  }'

# 关闭设备（OFF）
curl -X POST http://localhost:6002/api/control \
  -H "Content-Type: application/json" \
  -d '{
    "unitId": "baomujian-sdj-40858013_kaiguan-2966",
    "cmd": "OFF"
  }'
```

### 参数说明

| 参数     | 类型   | 说明                                               |
| -------- | ------ | -------------------------------------------------- |
| `unitId` | string | 设备单元ID，格式：`设备组ID_设备单元名称拼音-数字` |
| `cmd`    | string | 命令：`ON`（打开）或 `OFF`（关闭）                 |

### 响应示例

```json
{
  "code": 200,
  "msg": "控制命令已发送",
  "unitId": "baomujian-sdj-40858013_kaiguan-2966",
  "cmd": "ON"
}
```

---

## 🔌 方法二：使用 MQTT 协议

### 发布控制消息

```bash
# 使用 mosquitto_pub 发布命令
mosquitto_pub -h 192.168.1.40 -p 1883 -u "xxxx" -P "mqtt-password" \
  -t "iot/device/baomujian-sdj-40858013_kaiguan-2966/control" \
  -m '{"cmd":"ON"}'
```

### MQTT 主题格式

| 主题                          | 说明                        |
| ----------------------------- | --------------------------- |
| `iot/device/{unitId}/control` | 控制主题（服务端 → 设备端） |
| `iot/device/{unitId}/state`   | 状态主题（设备端 → 服务端） |

### 消息格式

```json
{
  "cmd": "ON"    // 或 "OFF"
}
```

---

## 🖥️ 方法三：前端界面操作

### 操作步骤

1. **进入设备详情页面**：点击设备组图标进入设备单元列表
2. **点击控制按钮**：
   - **绿色按钮**：打开设备（ON）
   - **红色按钮**：关闭设备（OFF）

### 示例截图

```
┌─────────────────────────────┐
│  设备单元：开关             │
├─────────────────────────────┤
│  当前状态：OFF              │
├─────────────────────────────┤
│  ┌──────────┐  ┌──────────┐ │
│  │   打开   │  │   关闭   │ │
│  │  (ON)    │  │  (OFF)   │ │
│  └──────────┘  └──────────┘ │
├─────────────────────────────┤
│  定时任务：                 │
│  • ON - 日任务 08:00       │
└─────────────────────────────┘
```

---

## 📋 常用命令汇总

### 获取设备列表

```bash
curl http://localhost:6002/api/config
```

### 获取设备状态

```bash
curl http://localhost:6002/api/status
```

### 批量控制（打开/关闭全部）

```bash
# 打开指定设备组的所有设备
curl -X POST http://localhost:6002/api/control/group \
  -H "Content-Type: application/json" \
  -d '{
    "groupName": "baomujian",
    "cmd": "ON"
  }'
```

---

## 🔑 设备单元ID格式说明

设备单元ID由两部分组成，用下划线分隔：

```
{设备组ID}_{设备单元名称拼音}-{4位数字}
```

**示例**：
- 设备组ID：`baomujian-sdj-40858013`
- 设备单元ID：`baomujian-sdj-40858013_kaiguan-2966`

---

## ✅ 完整操作示例

```bash
# 1. 获取设备配置，找到目标设备的 unitId
curl http://localhost:6002/api/config

# 2. 发送控制命令
curl -X POST http://localhost:6002/api/control \
  -H "Content-Type: application/json" \
  -d '{
    "unitId": "baomujian-sdj-40858013_kaiguan-2966",
    "cmd": "ON"
  }'

# 3. 验证状态
curl http://localhost:6002/api/status
```

> **提示**：确保控制服务（`npm run start`）已启动，并且设备已连接到 MQTT 服务器。





# AI相关的接口：


​          
项目中已经实现了两个 AI 接口！让我详细介绍：

---

## 🤖 AI 接口说明

### 接口列表

| 接口       | 路径                    | 说明                                     |
| ---------- | ----------------------- | ---------------------------------------- |
| **基础版** | `POST /api/ai`          | 简单的自然语言控制，支持基础设备控制指令 |
| **高级版** | `POST /api/ai-advanced` | 增强版AI交互，支持更复杂的指令解析       |

---

## 🚀 使用方法

### 1. 基础版接口 `/api/ai`

**功能**：解析自然语言指令，提取设备控制命令

```bash
# 发送AI指令
curl -X POST http://localhost:6002/api/ai \
  -H "Content-Type: application/json" \
  -d '{
    "text": "打开卧室的灯"
  }'
```

**响应示例**：

```json
{
  "code": 200,
  "cmd": "ON",
  "slot": "卧室",
  "unitType": "light",
  "msg": "解析成功",
  "targetDevices": [
    {
      "unitId": "woshi-light-001",
      "name": "卧室灯"
    }
  ],
  "executed": true
}
```

### 2. 高级版接口 `/api/ai-advanced`

**功能**：支持更复杂的对话和指令，返回详细的解析结果

```bash
curl -X POST http://localhost:6002/api/ai-advanced \
  -H "Content-Type: application/json" \
  -d '{
    "text": "请帮我打开客厅和卧室的空调，并设置温度为26度"
  }'
```

**响应示例**：

```json
{
  "code": 200,
  "msg": "指令解析成功",
  "intent": "设备控制",
  "entities": [
    {
      "type": "location",
      "value": "客厅"
    },
    {
      "type": "location",
      "value": "卧室"
    },
    {
      "type": "device",
      "value": "空调"
    },
    {
      "type": "temperature",
      "value": 26
    }
  ],
  "actions": [
    {
      "unitId": "keting-ac-001",
      "cmd": "ON",
      "params": { "temperature": 26 }
    },
    {
      "unitId": "woshi-ac-002",
      "cmd": "ON",
      "params": { "temperature": 26 }
    }
  ]
}
```

---



## ✅ 使用示例

### 1. 控制设备

```bash
# 关闭保姆间的扫地机
curl -X POST http://localhost:6002/api/ai-advanced \
  -H "Content-Type: application/json" \
  -d '{"text": "关闭保姆间的扫地机"}'

# 打开客厅的风扇
curl -X POST http://localhost:6002/api/ai-advanced \
  -H "Content-Type: application/json" \
  -d '{"text": "打开客厅的风扇"}'
```

### 2. 查询状态

```bash
# 查询设备状态
curl -X POST http://localhost:6002/api/ai-advanced \
  -H "Content-Type: application/json" \
  -d '{"text": "扫地机现在是什么状态"}'
```

### 3. 复杂指令

```bash
# 组合指令
curl -X POST http://localhost:6002/api/ai-advanced \
  -H "Content-Type: application/json" \
  -d '{"text": "关闭所有设备"}'
```

---

## 📌 提示

如果需要查看接口的详细实现，可以检查后端代码中 `/api/ai-advanced` 的逻辑，它通常会：

1. 获取当前设备配置作为上下文
2. 将设备配置信息传递给 AI 模型
3. AI 根据上下文进行更准确的设备匹配
4. 返回详细的解析结果和执行状态

> **建议**：使用高级接口 `/api/ai-advanced` 获得更好的解析效果和更详细的返回信息。



## 📝 支持的指令类型

### 基础控制指令
```
打开/关闭 + 位置 + 设备类型
例如：
- "打开卧室的灯"
- "关闭客厅空调"
- "打开厨房插座"
```

### 高级指令
```
自然语言描述的控制需求
例如：
- "帮我关掉所有灯"
- "设置客厅温度为25度"
- "明天早上8点打开窗帘"
```

---

## 🔧 配置说明

AI 接口使用 **Ollama** 作为后端模型服务，配置项在 `.env` 文件中：

```env
# AI 配置
OLLAMA_HOST=http://192.168.1.51:11434
AI_MODEL=qwen2.5:1.5b
```

### 环境变量说明

| 变量          | 默认值                      | 说明           |
| ------------- | --------------------------- | -------------- |
| `OLLAMA_HOST` | `http://192.168.1.51:11434` | Ollama服务地址 |
| `AI_MODEL`    | `qwen2.5:1.5b`              | 使用的AI模型   |

---

## 🚀 启动 AI 服务

### 1. 确保 Ollama 已安装并运行

```bash
# 启动 Ollama 服务
ollama serve

# 拉取模型（首次使用）
ollama pull qwen2.5:1.5b
```

### 2. 启动控制服务

```bash
npm run start
```

---

## ✅ 完整示例

```bash
# 1. 发送简单指令
curl -X POST http://localhost:6002/api/ai \
  -H "Content-Type: application/json" \
  -d '{"text": "打开卧室灯"}'

# 2. 发送复杂指令
curl -X POST http://localhost:6002/api/ai-advanced \
  -H "Content-Type: application/json" \
  -d '{"text": "晚上10点关闭所有电器"}'
```

---

## 📊 接口对比

| 特性     | `/api/ai` | `/api/ai-advanced` |
| -------- | --------- | ------------------ |
| 复杂度   | 简单      | 复杂               |
| 解析能力 | 基础指令  | 自然语言理解       |
| 返回格式 | 简洁      | 详细               |
| 适用场景 | 快速控制  | 智能对话           |

> **提示**：确保 Ollama 服务已在 `http://192.168.1.51:11434` 运行，并且已拉取 `qwen2.5:1.5b` 模型。



