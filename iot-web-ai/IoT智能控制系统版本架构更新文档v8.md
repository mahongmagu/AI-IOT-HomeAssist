
# IoT智能控制系统V8.2版本架构更新文档

## 1. 版本概述

本次更新增加了设备控制单元的"type"参数，区分"control"和"state"类型，进一步优化了内外网分离架构。

- **版本号**: V8.2
- **更新时间**: 2026年5月1日
- **主要变更**: 为设备单元添加"type"参数，控制型单元通过TCP发送指令，状态型单元通过WebSocket获取数据

## 2. 架构变更说明

### 2.1 旧架构 (V8.1)
- 所有设备单元默认为控制类型
- 统一的控制和状态处理逻辑

### 2.2 新架构 (V8.2)
- **控制类型(control)**: 通过TCP连接，内网IP 192.168.1.40
- **状态类型(state)**: 通过WebSocket连接，外网IP 10.70.33.218
- **前端访问**: 通过外网IP 10.70.33.218:6002
- **AI服务**: OLLAMA_HOST=http://192.168.1.51:11434

## 3. 技术实现细节

### 3.1 服务拆分
- `server-control-tcp.js`: 内网TCP控制服务（处理control类型单元）
- `server-status-ws.js`: 外网WebSocket状态服务（处理state类型单元）
- `index.html`: 前端界面，连接外网WebSocket，区分显示不同类型单元

### 3.2 网络配置
- **内网MQTT TCP服务器**: `mqtt://192.168.1.40:1883`
- **外网MQTT WebSocket服务器**: `ws://10.70.33.218:8083/mqtt`
- **外网WebSocket状态服务**: `ws://10.70.33.218:8084`
- **前端访问端口**: `http://10.70.33.218:6002`
- **AI服务端口**: `http://192.168.1.51:11434`

### 3.3 数据流向
```
Control Type Units:
ESP设备 ←→ EMQX (内网TCP) ←→ server-control-tcp.js (控制指令)

State Type Units:
ESP设备 → EMQX (外网WebSocket) → server-status-ws.js → 前端WebSocket (状态数据)

Frontend:
前端 ←→ 外网IP:3000 (HTTP) + 外网IP:8084 (WebSocket)
```

## 4. 设备类型说明

### 4.1 Control类型单元
- 用途：发送控制指令（ON/OFF）
- 通信方式：MQTT TCP Socket（内网）
- 主题格式：`iotxxx/devicename/{deviceType}/{deviceId}/{category}/{unitId}/control`
- 示例：继电器、开关、电机等

### 4.2 State类型单元
- 用途：获取状态或数据
- 通信方式：MQTT WebSocket（外网）
- 主题格式：`iotxxx/devicename/{deviceType}/{deviceId}/{category}/{unitId}/state`
- 示例：传感器、温湿度计、功率计等

## 5. 文件变更清单

### 5.1 新增文件
- `server-control-tcp.js`: 内网TCP控制服务
- `server-status-ws.js`: 外网WebSocket状态服务

### 5.2 修改文件
- `index.html`: 更新前端连接逻辑，增加设备类型显示
- `package.json`: 更新依赖和脚本配置
- `.env`: 添加内外网配置项和AI服务配置
- `devices.json`: 更新设备配置结构，支持type参数

## 6. 环境配置更新

### 6.1 .env配置文件
```bash
# 内网MQTT TCP服务器配置
MQTT_INTERNAL_SERVER=mqtt://192.168.1.40:1883
# 外网MQTT WebSocket服务器配置
MQTT_EXTERNAL_WS_SERVER=ws://10.70.33.218:8083/mqtt

# 认证信息
MQTT_USERNAME=username
MQTT_PASSWORD=your-mqtt-password
MQTT_TOPIC_PREFIX=iotxxx/devicename

# AI配置
OLLAMA_HOST=http://192.168.1.51:11434
AI_MODEL=qwen2.5:1.5b

# 端口配置
WEB_PORT=6002
WS_PORT=8084  # 外网WebSocket状态服务端口
```

### 6.2 devices.json配置示例
```json
{
  "light_group": {
    "name": "light",
    "displayName": "客厅灯光",
    "id": "esp001",
    "units": [
      {
        "id": "light_relay_1",
        "name": "客厅主灯",
        "status": "OFF",
        "type": "control"
      },
      {
        "id": "light_relay_2",
        "name": "客厅辅助灯",
        "status": "OFF",
        "type": "control"
      },
      {
        "id": "temperature_sensor",
        "name": "温度传感器",
        "status": "23.5",
        "type": "state"
      }
    ]
  },
  "socket_group": {
    "name": "socket",
    "displayName": "智能插座",
    "id": "esp002",
    "units": [
      {
        "id": "socket_relay_1",
        "name": "厨房插座",
        "status": "OFF",
        "type": "control"
      },
      {
        "id": "socket_relay_2",
        "name": "书房插座",
        "status": "ON",
        "type": "control"
      },
      {
        "id": "power_meter",
        "name": "功率计",
        "status": "45.2W",
        "type": "state"
      }
    ]
  }
}
```

## 7. 部署指南

### 7.1 安装依赖
```bash
npm install
```

### 7.2 启动服务
```bash
# 单独启动
npm run start  # 控制服务
npm run status # 状态服务

# 或并发启动
npm run dev
```

### 7.3 访问地址
- **前端界面**: `http://10.70.33.218:6002`
- **控制服务**: 内部使用，通过内网TCP通信
- **状态服务**: 外部WebSocket连接，端口8084

## 8. 性能优化

### 8.1 通信优化
- 消除了前端轮询机制，采用WebSocket实时推送
- 分离控制和状态通道，减少单点故障风险
- 内网控制保证低延迟，外网状态保证实时性
- 根据设备类型选择最合适的通信方式

### 8.2 安全增强
- 内外网分离，提高系统安全性
- 控制指令通过内网传输，更加安全可靠
- 状态反馈通过外网传输，便于远程监控
- 不同类型设备采用不同的安全策略

## 9. 前端界面更新

### 9.1 设备类型标识
- **控制类型**: 蓝色标识，支持ON/OFF操作
- **状态类型**: 绿色标识，显示实时数据，按钮禁用

### 9.2 用户体验改进
- 根据设备类型显示不同的操作界面
- 状态类型设备显示实时数据更新
- 控制类型设备支持交互操作

## 10. 测试验证

### 10.1 功能测试
- [ ] Control类型单元通过内网TCP正常下发指令
- [ ] State类型单元通过外网WebSocket正常推送数据
- [ ] 前端界面正确区分显示不同类型单元
- [ ] AI指令正常识别设备类型并处理
- [ ] WebSocket自动重连功能

### 10.2 性能测试
- [ ] 内网控制延迟 < 100ms
- [ ] 外网状态推送延迟 < 500ms
- [ ] 系统稳定性 > 99%
- [ ] 不同类型设备处理准确性

## 11. 故障排除

### 11.1 常见问题
1. **WebSocket连接失败**
   - 检查外网IP和端口是否可达
   - 确认EMQX WebSocket端口配置

2. **Control类型指令无法下发**
   - 检查内网MQTT服务器是否可达
   - 确认认证信息是否正确

3. **State类型数据不更新**
   - 检查外网WebSocket连接
   - 确认设备端状态发布正常

4. **AI指令处理错误**
   - 检查AI服务连接状态
   - 确认设备类型配置正确

### 11.2 日志监控
- 控制服务日志：关注TCP连接状态和control类型指令下发
- 状态服务日志：关注WebSocket连接和state类型数据推送
- EMQX日志：监控MQTT消息路由和设备类型处理

## 12. 后续计划

- [ ] 优化WebSocket连接池管理
- [ ] 增加设备状态历史记录功能
- [ ] 实现设备分组管理和权限控制
- [ ] 增加系统监控和告警功能
- [ ] 支持更多设备类型和通信协议

## 13. 总结

V8.2版本成功实现了设备控制单元的"type"参数功能，显著提升了系统的灵活性和适用性。通过将设备分为control和state两种类型，系统能够更好地处理不同类型的设备，控制型设备用于执行操作，状态型设备用于数据采集和监控。新架构为未来的功能扩展和系统优化奠定了良好的基础。
        