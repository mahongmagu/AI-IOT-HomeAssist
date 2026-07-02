
# IoT智能控制系统安装部署操作文档

## 1. 系统要求

### 硬件要求
- 一台能够运行Node.js的计算机（Windows、Linux或macOS）
- ESP8266开发板（用于物联网设备）
- MQTT Broker服务器（如Mosquitto）
- 网络连接

### 软件要求
- Node.js v14.0或更高版本
- npm（随Node.js安装）
- Git（可选，用于克隆项目）
- Ollama（用于AI功能）

## 2. 环境准备

### 2.1 安装Node.js
访问 https://nodejs.org 下载并安装Node.js LTS版本。

验证安装：
```bash
node --version
npm --version
```

### 2.2 安装Ollama（可选）
如果需要AI语音控制功能，需要安装Ollama：
- 访问 https://ollama.ai 下载并安装Ollama
- 安装模型：`ollama pull qwen2.5:1.5b`

### 2.3 安装MQTT Broker
推荐使用Mosquitto作为MQTT Broker：
- Windows: 下载安装包并安装
- Linux: `sudo apt install mosquitto mosquitto-clients`
- macOS: `brew install mosquitto`

## 3. 项目部署

### 3.1 克隆项目
```bash
git clone <your-repository-url>
cd iot-web-ai
```

或者直接下载ZIP文件并解压。

### 3.2 安装依赖
```bash
cd iot-web-ai
npm install
```

### 3.3 配置环境变量
创建 `.env` 文件：
```bash
MQTT_USERNAME=username
MQTT_PASSWORD=your-mqtt-password
MQTT_SERVER=mqtt://192.168.1.40:1883
OLLAMA_HOST=http://192.168.1.51:11434
WEB_PORT=6002
DEVICE_CONTROL_TOPIC=iot/device/001/control
DEVICE_STATE_TOPIC=iot/device/001/state
AI_MODEL=qwen2.5:1.5b
CONFIG_PORT=6001
```

根据实际环境修改以下参数：
- `MQTT_SERVER`: MQTT服务器地址和端口
- `MQTT_USERNAME/MQTT_PASSWORD`: MQTT认证信息
- `OLLAMA_HOST`: Ollama服务器地址
- `WEB_PORT`: 操作服务器端口（默认6001）
- `CONFIG_PORT`: 配置服务器端口（默认6002）

### 3.4 创建数据文件
在项目根目录创建 `devices.json` 文件：
```json
{
  "devices": {
    "socket_slot": {
      "name": "socket_slot",
      "displayName": "四孔插座",
      "units": [
        {
          "id": "socket_slot_1",
          "name": "socket_slot_1",
          "displayName": "插座1",
          "status": "OFF"
        },
        {
          "id": "socket_slot_2",
          "name": "socket_slot_2",
          "displayName": "插座2",
          "status": "OFF"
        },
        {
          "id": "socket_slot_3",
          "name": "socket_slot_3",
          "displayName": "插座3",
          "status": "OFF"
        },
        {
          "id": "socket_slot_4",
          "name": "socket_slot_4",
          "displayName": "插座4",
          "status": "OFF"
        }
      ]
    }
  },
  "lastUpdated": "2026-04-28T00:00:00.000Z"
}
```

## 4. ESP8266固件烧录

### 4.1 硬件连接
- ESP8266通过USB连接到电脑
- 确保驱动程序已安装

### 4.2 烧录固件
1. 打开Arduino IDE
2. 安装ESP8266开发板支持
3. 打开 `ESP8266_IoT.ino` 文件
4. 修改WiFi和MQTT配置参数
5. 选择正确的开发板和端口
6. 点击上传

## 5. 启动服务

### 5.1 启动MQTT Broker
```bash
# Windows (如果使用Mosquitto)
mosquitto -c mosquitto.conf

# Linux/macOS
sudo systemctl start mosquitto
# 或者
mosquitto -v
```

### 5.2 启动Ollama（可选）
```bash
ollama serve
```

### 5.3 启动IoT系统服务

#### 方法一：分别启动两个服务
```bash
# 启动操作服务器（端口6000）
npm run operation

# 在另一个终端启动配置服务器（端口6001）
npm run config
```

#### 方法二：同时启动两个服务
```bash
npm run dev
```

## 6. 服务验证

### 6.1 操作服务器验证
访问：`http://localhost:6000`
- 应能看到设备操作界面
- 检查健康状态：`http://localhost:6000/health`

### 6.2 配置服务器验证
访问：`http://localhost:6001`
- 应能看到设备配置界面
- 检查健康状态：`http://localhost:6001/health`

### 6.3 MQTT连接验证
- 检查控制台日志确认MQTT连接成功
- 可使用MQTT客户端工具测试发布/订阅

## 7. 系统使用

### 7.1 设备配置
1. 访问配置页面：`http://localhost:6001`
2. 添加设备和控制单元
3. 设置设备名称和显示名称
4. 配置的设备信息将保存到 `devices.json` 文件中

### 7.2 设备操作
1. 访问操作页面：`http://localhost:6000`
2. 查看设备状态（从 `devices.json` 读取）
3. 通过按钮或AI语音控制设备
4. 设备状态变化会实时保存到 `devices.json` 文件中

### 7.3 AI语音控制
- 在AI控制框输入自然语言指令
- 例如："打开插座1"、"关闭四孔插座的第二个插槽"

## 8. 数据同步机制

### 8.1 共享数据存储
- 两个服务器都使用同一个 `devices.json` 文件
- 配置服务器负责设备配置管理
- 操作服务器负责设备控制和状态管理

### 8.2 实时同步
- 配置页面的修改会立即保存到 `devices.json`
- 操作页面会从 `devices.json` 读取最新的设备配置
- 设备状态变化会实时更新到 `devices.json`

### 8.3 持久化存储
- 设备配置和状态在服务器重启后依然保留
- `devices.json` 文件作为单一数据源

## 9. 故障排除

### 9.1 常见问题

#### 问题：MQTT连接失败
**解决方案：**
- 检查MQTT服务器是否运行
- 验证`.env`文件中的MQTT配置
- 检查防火墙设置

#### 问题：端口被占用
**解决方案：**
- 修改`.env`文件中的端口设置
- 关闭占用端口的其他进程

#### 问题：AI功能不可用
**解决方案：**
- 确认Ollama服务正在运行
- 检查模型是否已下载
- 验证OLLAMA_HOST配置

#### 问题：数据不同步
**解决方案：**
- 确认两个服务器都在使用相同的 `devices.json` 文件
- 检查文件权限是否允许读写
- 验证服务器是否都已重启以加载最新配置

### 9.2 日志查看
- 操作服务器日志：控制台输出
- 配置服务器日志：控制台输出
- MQTT日志：MQTT Broker日志
- `devices.json`：设备配置和状态的持久化存储

## 10. 维护和升级

### 10.1 系统备份
定期备份以下内容：
- `.env`配置文件
- `devices.json`数据文件
- 自定义配置

### 10.2 版本升级
```bash
# 拉取最新代码
git pull origin main

# 更新依赖
npm install

# 重启服务
npm run dev
```

## 11. 安全建议

1. 更改默认的MQTT用户名和密码
2. 使用安全的网络连接
3. 定期更新依赖包
4. 监控系统日志
5. 限制API访问频率
6. 保护 `devices.json` 文件的访问权限

## 12. 系统架构说明

### 12.1 微服务架构
- **操作服务器 (6000)**：处理设备控制和状态监控
- **配置服务器 (6001)**：处理设备配置管理
- **共享数据存储**：`devices.json` 文件
- **MQTT Broker**：设备通信中间件
- **Ollama**：AI推理服务

### 12.2 通信协议
- HTTP/HTTPS：Web界面通信
- MQTT：设备通信协议
- 文件系统：数据持久化

## 13. 性能优化

1. 调整速率限制参数
2. 优化数据管理模块性能
3. 使用负载均衡（高并发场景）
4. 配置CDN（静态资源加速）

---

**注意：** 本系统仍在开发阶段，建议在测试环境中使用。生产环境部署前请进行充分测试。

**重要更新：** 系统现在使用 `devices.json` 作为共享数据源，确保配置服务器和操作服务器之间的实时同步。删除设备或修改设备配置后，更改会立即在两个服务之间同步。
        