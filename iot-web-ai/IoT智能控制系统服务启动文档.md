# IoT智能控制系统服务启动操作文档

## 1. 系统架构

### 服务组件

| 服务名称 | 进程名 | 入口文件 | 默认端口 | 功能描述 |
|---------|--------|---------|---------|---------|
| 控制服务 | AI-CTL-server | server-control-tcp.js | 3002 | 设备控制指令处理、MQTT通信、AI指令解析 |
| 状态服务 | AI-STA-server | server-status-ws.js | 8090 | 设备状态监控、WebSocket广播、离线检测 |
| 配置服务 | AI-CFG-server | server-config.js | 3001 | 设备管理API、设备配置增删改查 |

### 依赖服务

| 服务 | 地址 | 说明 |
|------|------|------|
| MQTT Broker | mqtt://192.168.6.40:1883 | 内网TCP通信 |
| MQTT Broker (WS) | ws://192.168.6.40:8083/mqtt | 外网WebSocket通信 |
| Ollama | http://192.168.6.51:11434 | AI推理服务（可选） |

## 2. 环境准备

### 2.1 安装Node.js

```bash
node --version  # 要求 v14.0+
npm --version
```

### 2.2 安装PM2

```bash
npm install -g pm2
pm2 --version
```

### 2.3 安装依赖

```bash
cd iot-web-ai
npm install
```

### 2.4 配置环境变量

编辑 `.env` 文件：

```bash
# 服务器IP
SERVER_IP=192.168.6.149

# MQTT配置
MQTT_INTERNAL_SERVER=mqtt://192.168.6.40:1883
MQTT_EXTERNAL_WS_SERVER=ws://192.168.6.40:8083/mqtt
MQTT_USERNAME=mh
MQTT_PASSWORD=MaGu971204
MQTT_TOPIC_PREFIX=iot/device

# AI配置（可选）
OLLAMA_HOST=http://192.168.6.51:11434
AI_MODEL=qwen2.5:1.5b

# 端口配置
CONFIG_SERVICE_PORT=3001
CONTROL_SERVICE_PORT=3002
WS_PORT=8090

# 离线检测配置
OFFLINE_TIMEOUT=300000
CHECK_INTERVAL=30000
```

## 3. 服务启动

### 3.1 开发模式（单终端运行）

```bash
# 方式一：使用concurrently同时启动（开发调试用）
npm run home-assistant-AI

# 方式二：分别启动（需多个终端）
npm run start    # 控制服务
npm run status   # 状态服务
npm run config   # 配置服务
```

### 3.2 生产模式（PM2管理）

#### 启动所有服务

```bash
# 首次启动或重启所有服务
npm run pm2-iot

# 或使用PM2命令直接启动
pm2 start ecosystem.config.js
```

#### 单独启动服务

```bash
# 启动控制服务
npm run pm2-ctl

# 启动状态服务
npm run pm2-sta

# 启动配置服务
npm run pm2-cfg
```

#### PM2管理命令

```bash
# 查看进程状态
npm run pm2-list
# 或
pm2 list

# 查看日志
npm run pm2-logs
# 或查看指定服务日志
pm2 logs AI-CTL-server

# 停止所有服务
npm run pm2-stop

# 停止单个服务
npm run stop-ctl   # 控制服务
npm run stop-sta   # 状态服务
npm run stop-cfg   # 配置服务

# 重启服务
pm2 restart AI-CTL-server
pm2 restart ecosystem.config.js

# 重载服务（零停机重启）
pm2 reload ecosystem.config.js

# 查看进程详情
pm2 describe AI-CTL-server
```

### 3.3 PM2开机自启配置

```bash
# 生成开机自启脚本（首次配置）
pm2 startup

# 保存当前进程列表
pm2 save

# 查看PM2服务状态
systemctl status pm2-<用户名>

## 4. 服务验证

### 4.1 进程状态验证

```bash
pm2 list
```

正常状态应为 `online`，而非 `errored`。

### 4.2 服务健康检查

```bash
# 控制服务
curl http://localhost:3002/health

# 配置服务
curl http://localhost:3001/health

# 状态服务（WebSocket）
# 使用WebSocket客户端连接 ws://localhost:8090
```

### 4.3 MQTT连接验证

检查控制服务日志确认MQTT连接成功：

```bash
pm2 logs AI-CTL-server | grep "连接成功"
```

## 5. 日志管理

### 5.1 日志位置

```bash
# PM2主日志
/home/mh/.pm2/pm2.log

# 各服务日志
/home/mh/.pm2/logs/AI-CTL-server-out.log
/home/mh/.pm2/logs/AI-CTL-server-error.log
/home/mh/.pm2/logs/AI-STA-server-out.log
/home/mh/.pm2/logs/AI-STA-server-error.log
/home/mh/.pm2/logs/AI-CFG-server-out.log
/home/mh/.pm2/logs/AI-CFG-server-error.log
```

### 5.2 日志查看技巧

```bash
# 实时查看所有日志
pm2 logs

# 实时查看单个服务日志
pm2 logs AI-CTL-server

# 查看最近100行日志
pm2 logs --lines 100

# 搜索关键字
pm2 logs | grep "error"
pm2 logs AI-CTL-server | grep "MQTT"
```

## 6. 常见问题排查

### 6.1 PM2启动失败

**现象：** 进程状态为 `errored`，反复重启后被PM2停止。

**排查步骤：**

```bash
# 查看详细错误信息
pm2 describe AI-CTL-server

# 查看最近日志
pm2 logs AI-CTL-server --lines 50
```

**常见原因：**

| 错误信息 | 原因 | 解决方案 |
|---------|------|---------|
| `concurrently: Permission denied` | concurrently未正确安装或路径问题 | 使用PM2配置文件启动，避免concurrently |
| `Connection refused: Not authorized` | MQTT认证失败 | 检查.env中的MQTT_USERNAME和MQTT_PASSWORD |
| `Cannot find module` | 依赖未安装 | 执行 `npm install` |
| `EADDRINUSE` | 端口被占用 | 修改端口配置或关闭占用进程 |

### 6.2 MQTT认证失败

**错误信息：**
```
MQTT TCP控制客户端（内网）错误: ErrorWithReasonCode: Connection refused: Not authorized
```

**排查步骤：**

```bash
# 1. 测试MQTT连接
mosquitto_sub -h 192.168.6.40 -p 1883 -u "mh" -P "MaGu971204" -t "test" -v

# 2. 检查.env文件配置
cat .env | grep MQTT

# 3. 检查MQTT服务端用户配置
# 登录EMQX/Mosquitto管理界面确认用户存在且密码正确
```

### 6.3 服务端口未监听

**排查步骤：**

```bash
# 检查端口是否被占用
netstat -tlnp | grep 3002
ss -tlnp | grep 3002

# 检查防火墙
sudo ufw status
sudo firewall-cmd --list-ports

# 检查服务是否正常启动
pm2 status
```

### 6.4 PM2日志提示"too many unstable restarts"

**原因：** 进程频繁崩溃，PM2自动停止重启。

**解决步骤：**

```bash
# 1. 删除崩溃的进程
pm2 delete AI-iot-Server

# 2. 查看错误日志定位问题
pm2 logs AI-CTL-server --lines 100

# 3. 修复问题后重新启动
npm run pm2-iot
```

## 7. 紧急恢复流程

### 7.1 快速重启所有服务

```bash
# 停止所有服务
pm2 delete all

# 重新启动
npm run pm2-iot

# 验证状态
pm2 list
```

### 7.2 仅重启控制服务

```bash
pm2 restart AI-CTL-server
pm2 logs AI-CTL-server --lines 30
```

### 7.3 手动启动（调试用）

```bash
# 在前台启动，便于查看实时日志
node server-control-tcp.js
node server-status-ws.js
node server-config.js
```

按 `Ctrl+C` 停止。

## 8. PM2配置说明

PM2配置文件 [ecosystem.config.js](file:///d:/openclaw/workspace/iot-web-ai/v11/ecosystem.config.js) 包含以下关键配置：

| 配置项 | 值 | 说明 |
|-------|-----|------|
| name | AI-CTL-server | 进程名称 |
| script | server-control-tcp.js | 入口文件 |
| instances | 1 | 进程数（单例模式） |
| autorestart | true | 崩溃自动重启 |
| watch | false | 不监听文件变化 |
| max_memory_restart | 1G | 内存超过1G自动重启 |
| env.NODE_ENV | production | 生产环境标识 |

## 9. 安全建议

1. **修改默认密码**：更改.env中的MQTT_USERNAME和MQTT_PASSWORD
2. **防火墙规则**：只允许必要端口的外部访问
3. **日志监控**：定期检查服务日志
4. **依赖更新**：定期执行 `npm update`
5. **PM2安全**：限制PM2进程的权限

---

**版本：** v2.2.1  
**最后更新：** 2026-07-08  
**说明：** 本系统采用三服务架构，通过PM2进行进程管理，支持开机自启和自动重启。
