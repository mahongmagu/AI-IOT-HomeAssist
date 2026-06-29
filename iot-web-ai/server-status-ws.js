// server-status-ws.js - WebSocket状态推送服务（外网）
require('dotenv').config();
const WebSocket = require('ws');
const mqtt = require('mqtt');
const fs = require('fs');
const path = require('path');

// 为所有日志添加时间戳
const originalConsoleLog = console.log.bind(console);
const originalConsoleWarn = console.warn.bind(console);
const originalConsoleError = console.error.bind(console);
function logWithTimestamp(logger, args) {
  const prefix = `[${new Date().toLocaleString('zh-CN')}]`;
  logger(prefix, ...args);
}
console.log = (...args) => logWithTimestamp(originalConsoleLog, args);
console.warn = (...args) => logWithTimestamp(originalConsoleWarn, args);
console.error = (...args) => logWithTimestamp(originalConsoleError, args);

// 外网MQTT WebSocket服务器配置
const MQTT_EXTERNAL_WS_SERVER = process.env.MQTT_EXTERNAL_WS_SERVER || 'ws://192.168.1.40:8083/mqtt'; // EMQX WebSocket端口

// 自动获取服务器IP
function getServerIP() {
  try {
    const os = require('os');
    const interfaces = os.networkInterfaces();
    
    for (const name of Object.keys(interfaces)) {
      for (const iface of interfaces[name]) {
        // 跳过IPv6和本地回环地址
        if (iface.family === 'IPv4' && !iface.internal) {
          return iface.address;
        }
      }
    }
  } catch (error) {
    console.warn('无法自动获取服务器IP:', error.message);
  }
  return '127.0.0.1'; // 回退到本地地址
}

// 配置优先级：环境变量 > 自动获取 > 默认值
const SERVER_IP = process.env.SERVER_IP || getServerIP();
const WS_PORT = parseInt(process.env.WS_PORT) || 8084; // 外网WebSocket状态服务端口

// 设备配置缓存
let deviceConfigs = {};

// 加载设备配置
function loadDeviceConfigs() {
  try {
    const data = fs.readFileSync(path.join(__dirname, 'devices.json'), 'utf8');
    
    // 检查文件是否为空或不完整
    if (!data || data.trim() === '') {
      console.warn('设备配置文件为空，使用上次缓存的配置');
      return; // 保持原有配置不变
    }
    
    const parsed = JSON.parse(data);
    // 支持两种数据结构
    deviceConfigs = parsed.devices || parsed;
    console.log('设备配置加载完成');
  } catch (error) {
    console.error('加载设备配置失败:', error.message);
    console.warn('使用上次缓存的配置，等待下次文件变化');
    // 保持原有配置不变，不重置为空对象
  }
}

// 监听设备配置文件变化
fs.watch(path.join(__dirname, 'devices.json'), (eventType) => {
  if (eventType === 'change') {
    console.log('检测到设备配置变化，重新加载...');
    loadDeviceConfigs();
  }
});

// 初始化加载设备配置
loadDeviceConfigs();

// 设备最后活跃时间记录 { unitId: timestamp }
let deviceLastActive = {};

 // 新增：初始化设备活跃时间
 function initDeviceActiveTime() {
   for (const [groupName, groupConfig] of Object.entries(deviceConfigs)) {
     if (groupName === 'lastUpdated') continue;
     
     if (groupConfig && groupConfig.units) {
       for (const unit of groupConfig.units) {
         if (!deviceLastActive[unit.id]) {
           deviceLastActive[unit.id] = Date.now();
           console.log(`[离线检测] 初始化设备活跃时间: ${unit.id}`);
         }
       }
     }
   }
 }
 
 initDeviceActiveTime();


// MQTT连接选项（外网WebSocket）
const mqttOptions = {
  username: process.env.MQTT_USERNAME || 'username',
  password: process.env.MQTT_PASSWORD || 'your-mqtt-password',
  clientId: `iot-ws-${Math.random().toString(16).substr(2, 8)}`,
  clean: true,
  connectTimeout: 4000,
  reconnectPeriod: 1000,
  protocolId: 'MQTT',
  protocolVersion: 4
};

// MQTT主题配置
const MQTT_TOPIC_PREFIX = process.env.MQTT_TOPIC_PREFIX || 'iotxxx/devicename';
const STATE_TOPIC_SUFFIX = 'state'; // 状态主题
const CTRL_TOPIC_SUFFIX = 'control';   // 控制主题
const TEXTSETTING_TOPIC_SUFFIX = 'textsetting';  // 文本设置主题
const DATASETTING_TOPIC_SUFFIX = 'datasetting';  // 数据设置主题

// WebSocket客户端集合
let wsClients = new Set();

// 从环境变量读取离线检测配置
const OFFLINE_TIMEOUT = parseInt(process.env.OFFLINE_TIMEOUT) || 5 * 60 * 1000; // 默认5分钟
const CHECK_INTERVAL = parseInt(process.env.CHECK_INTERVAL) || 30 * 1000; // 默认30秒

// 更新设备活跃时间
function updateDeviceActive(unitId) {
  deviceLastActive[unitId] = Date.now();
}

// 检查设备是否离线
function checkOfflineDevices() {
  const now = Date.now();
  
  for (const [unitId, lastActive] of Object.entries(deviceLastActive)) {
    if (now - lastActive > OFFLINE_TIMEOUT) {
      // 设备离线
      console.log(`设备离线: ${unitId}`);
      broadcastOfflineStatus(unitId);
    }
  }
}

// 广播离线状态
function broadcastOfflineStatus(unitId) {
  // 从设备配置中查找单元信息
  let deviceType = 'unknown';
  let deviceId = 'unknown';
  let category = 'relay';
  let unitType = 'state';
  
  for (const [groupName, groupConfig] of Object.entries(deviceConfigs)) {
    if (groupConfig && groupConfig.units) {
      const unit = groupConfig.units.find(u => u.id === unitId);
      if (unit) {
        deviceType = groupName;
        deviceId = groupConfig.id || groupName;
        unitType = unit.type || 'state';
        break;
      }
    }
  }
  
  const offlineUpdate = {
    type: 'state-update',
    device: {
      type: deviceType,
      id: deviceId,
      category: category,
      unit: unitId,
      unitType: unitType,
      online: false  // 新增：标识设备离线
    },
    state: 'OFFLINE',  // 状态设为OFFLINE
    topic: `${MQTT_TOPIC_PREFIX}/${unitId}/state`,
    timestamp: new Date().toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' })
  };
  
  broadcastToWebSockets(offlineUpdate);
}

// 启动定时检查
setInterval(checkOfflineDevices, CHECK_INTERVAL);
console.log(`设备离线检测已启动 - 超时时间: ${OFFLINE_TIMEOUT / 1000}秒, 检查间隔: ${CHECK_INTERVAL / 1000}秒`);

// 创建MQTT WebSocket客户端（外网）
const mqttClient = mqtt.connect(MQTT_EXTERNAL_WS_SERVER, mqttOptions);

// 创建WebSocket服务器（外网）
const wss = new WebSocket.Server({ port: WS_PORT, host: '0.0.0.0' });

wss.on('connection', (ws, req) => {
  console.log('新的WebSocket状态连接（外网）:', req.socket.remoteAddress);
  wsClients.add(ws);
  
  // 发送连接确认
  ws.send(JSON.stringify({
    type: 'connected',
    message: 'WebSocket状态服务（外网）连接成功',
    timestamp: new Date().toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' })
  }));
  
  // 发送初始设备状态（包括text和data类型）
  sendInitialDeviceStates(ws);
  
  ws.on('close', () => {
    console.log('WebSocket状态连接（外网）断开');
    wsClients.delete(ws);
  });
  
  ws.on('error', (error) => {
    console.error('WebSocket状态错误（外网）:', error);
    wsClients.delete(ws);
  });
});

// 发送初始设备状态
function sendInitialDeviceStates(ws) {
  for (const [groupName, groupConfig] of Object.entries(deviceConfigs)) {
    if (groupName === 'lastUpdated') continue;
    
    if (groupConfig && groupConfig.units) {
      const deviceId = groupConfig.id || groupName;
      
      for (const unit of groupConfig.units) {
        const stateUpdate = {
          type: 'state-update',
          device: {
            type: groupName,
            id: deviceId,
            category: 'relay',
            unit: unit.id,
            unitType: unit.type || 'control'
          },
          state: unit.status || 'OFF',
          topic: `${MQTT_TOPIC_PREFIX}/${groupName}/${deviceId}/relay/${unit.id}/state`,
          timestamp: new Date().toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' })
        };
        
        ws.send(JSON.stringify(stateUpdate));
      }
    }
  }
}

// MQTT外网连接处理
mqttClient.on('connect', () => {
  console.log('MQTT WebSocket状态客户端（外网）连接成功');
  
  // 订阅状态主题：iotxxx/devicename/设备单元ID/state
  const stateTopicPattern = `${MQTT_TOPIC_PREFIX}/+/${STATE_TOPIC_SUFFIX}`;
  mqttClient.subscribe(stateTopicPattern, { qos: 1 }, (err) => {
    if (err) {
      console.error('订阅状态主题失败:', err);
    } else {
      console.log(`已订阅状态主题（外网）: ${stateTopicPattern}`);
    }
  });
  
  // 订阅文本设置主题：iotxxx/devicename/设备单元ID/textsetting
  const textsettingTopicPattern = `${MQTT_TOPIC_PREFIX}/+/${TEXTSETTING_TOPIC_SUFFIX}`;
  mqttClient.subscribe(textsettingTopicPattern, { qos: 1 }, (err) => {
    if (err) {
      console.error('订阅文本设置主题失败:', err);
    } else {
      console.log(`已订阅文本设置主题（外网）: ${textsettingTopicPattern}`);
    }
  });
  
  // 订阅数据设置主题：iotxxx/devicename/设备单元ID/datasetting
  const datasettingTopicPattern = `${MQTT_TOPIC_PREFIX}/+/${DATASETTING_TOPIC_SUFFIX}`;
  mqttClient.subscribe(datasettingTopicPattern, { qos: 1 }, (err) => {
    if (err) {
      console.error('订阅数据设置主题失败:', err);
    } else {
      console.log(`已订阅数据设置主题（外网）: ${datasettingTopicPattern}`);
    }
  });
  
});

mqttClient.on('message', (topic, message) => {
  console.log(`收到MQTT状态消息（外网）- 主题: ${topic}, 内容: ${message.toString()}`);
  
  // 解析主题，提取设备信息
  const topicParts = topic.split('/');
  
  // 新格式：iotxxx/devicename/设备单元ID/主题类型(state/textsetting/datasetting)
  if (topicParts.length === 4) {
    const unitId = topicParts[2];
    const topicType = topicParts[3];
    
    // 更新设备活跃时间
    updateDeviceActive(unitId);
    
    // 验证是否是支持的主题类型
    if (![STATE_TOPIC_SUFFIX, TEXTSETTING_TOPIC_SUFFIX, DATASETTING_TOPIC_SUFFIX].includes(topicType)) {
      return; // 忽略不支持的主题类型
    }
    
    // 从设备配置中查找单元信息
    let deviceType = 'unknown';
    let deviceId = 'unknown';
    let category = 'relay';
    let unitType = 'state';
    
    for (const [groupName, groupConfig] of Object.entries(deviceConfigs)) {
      if (groupConfig && groupConfig.units) {
        const unit = groupConfig.units.find(u => u.id === unitId);
        if (unit) {
          deviceType = groupName;
          deviceId = groupConfig.id || groupName;
          unitType = unit.type || 'state';
          break;
        }
      }
    }
    
    // 构造状态更新消息
    const stateUpdate = {
      type: 'state-update',
      device: {
        type: deviceType,
        id: deviceId,
        category: category,
        unit: unitId,
        unitType: unitType,
        topicType: topicType  // 新增：标识状态来源主题类型
      },
      state: message.toString(),
      topic: topic,
      timestamp: new Date().toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' })
    };
    
    // 广播给所有WebSocket客户端
    broadcastToWebSockets(stateUpdate);
  }
});

mqttClient.on('error', (error) => {
  console.error('MQTT WebSocket状态客户端（外网）错误:', error);
});

mqttClient.on('reconnect', () => {
  console.log('MQTT WebSocket状态客户端（外网）正在重连...');
});

mqttClient.on('close', () => {
  console.log('MQTT WebSocket状态客户端（外网）连接已关闭');
});

// 广播消息到所有WebSocket客户端
function broadcastToWebSockets(data) {
  const message = JSON.stringify(data);
  wsClients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  });
}

const os = require('os');
console.log(`WebSocket状态服务（外网）启动: ws://${SERVER_IP}:${WS_PORT}`);
console.log(`外网MQTT WebSocket服务器: ${MQTT_EXTERNAL_WS_SERVER}`);
console.log(`状态主题模式: ${MQTT_TOPIC_PREFIX}/+/${STATE_TOPIC_SUFFIX}, ${MQTT_TOPIC_PREFIX}/+/${TEXTSETTING_TOPIC_SUFFIX}, ${MQTT_TOPIC_PREFIX}/+/${DATASETTING_TOPIC_SUFFIX}`);

// 优雅关闭
process.on('SIGTERM', () => {
  console.log('收到关闭信号，正在关闭WebSocket状态服务（外网）...');
  wss.close(() => {
    console.log('WebSocket状态服务（外网）已关闭');
    mqttClient.end(true, () => {
      console.log('MQTT WebSocket状态客户端（外网）已关闭');
    });
  });
});