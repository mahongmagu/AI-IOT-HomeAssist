// server-control-tcp.js - V11 TCP控制指令服务（内网）
require('dotenv').config();
const express = require('express');
const mqtt = require('mqtt');
const cors = require('cors');
const path = require('path');
const rateLimit = require('express-rate-limit');
const { ChatOllama } = require('@langchain/ollama');
const DataManager = require('./data-manager');
const fs = require('fs');
const http = require('http');

const app = express();
const dataManager = new DataManager('./devices.json');

const CONFIG_SERVICE_PORT = parseInt(process.env.CONFIG_SERVICE_PORT) || 3001;

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

// 定时任务持久化配置
const SCHEDULES_FILE = './data/schedules.json';

// 确保数据目录存在
function ensureDataDir() {
  const dir = path.dirname(SCHEDULES_FILE);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
    console.log(`[定时任务] 创建数据目录: ${dir}`);
  }
}

// 读取定时任务文件
function loadSchedules() {
  ensureDataDir();
  if (!fs.existsSync(SCHEDULES_FILE)) {
    return {};
  }
  try {
    const data = fs.readFileSync(SCHEDULES_FILE, 'utf8');
    return JSON.parse(data);
  } catch (error) {
    console.error('[定时任务] 读取任务文件失败:', error.message);
    return {};
  }
}

// 保存定时任务文件
function saveSchedules(schedules) {
  ensureDataDir();
  try {
    fs.writeFileSync(SCHEDULES_FILE, JSON.stringify(schedules, null, 2));
    console.log('[定时任务] 任务已保存到文件');
  } catch (error) {
    console.error('[定时任务] 保存任务文件失败:', error.message);
  }
}

// ===== 中文时间解析支持 =====
function chineseToNumber(ch) {
  const map = { '零':0,'一':1,'二':2,'两':2,'三':3,'四':4,'五':5,'六':6,'七':7,'八':8,'九':9,'十':10,'十一':11,'十二':12 };
  if (!ch) return null;
  if (/^\d+$/.test(ch)) return parseInt(ch, 10);
  if (map[ch] !== undefined) return map[ch];
  // handle compound like 十三
  if (ch.length === 2 && ch[0] === '十') return 10 + (map[ch[1]] || 0);
  return null;
}

function parseTimeOfDay(text) {
  // 查找诸如“下午两点半”、“晚上6点10分”、“6:10”等形式
  const meridiemMatch = text.match(/(凌晨|早上|上午|中午|下午|晚上)/);
  const meridiem = meridiemMatch ? meridiemMatch[1] : null;

  // 数字或中文数字小时
  const hourMatch = text.match(/([0-9]{1,2}|[零一二三四五六七八九十两]{1,3})\s*(点|时|:)/);
  let hour = null;
  if (hourMatch) hour = chineseToNumber(hourMatch[1]);

  // 分钟
  let minute = 0;
  const minuteMatch = text.match(/点(?:钟)?\s*(半|([0-9]{1,2})分?)/);
  if (minuteMatch) {
    if (minuteMatch[1] === '半') minute = 30;
    else if (minuteMatch[2]) minute = parseInt(minuteMatch[2], 10);
  } else {
    const colonMatch = text.match(/:(\d{1,2})/);
    if (colonMatch) minute = parseInt(colonMatch[1], 10);
  }

  if (hour === null) return null;

  // 根据 meridiem 调整小时（简单规则）
  if (meridiem === '下午' || meridiem === '晚上') {
    if (hour < 12) hour += 12;
  } else if (meridiem === '凌晨') {
    if (hour === 12) hour = 0;
  } else if (meridiem === '中午') {
    if (hour < 11) hour += 12;
  }

  return { hour, minute };
}

function getNextOccurrenceForTime(hour, minute, startDate = new Date()) {
  const now = new Date(startDate);
  const target = new Date(now);
  target.setHours(hour, minute, 0, 0);
  if (target.getTime() <= now.getTime()) {
    // 明天
    target.setDate(target.getDate() + 1);
  }
  return target;
}

function parseChineseTimeExpression(text) {
  if (!text || typeof text !== 'string') return null;
  text = text.trim();

  // 每天 ...
  if (/^每天/.test(text)) {
    const tod = parseTimeOfDay(text);
    if (!tod) return null;
    const next = getNextOccurrenceForTime(tod.hour, tod.minute);
    return { type: 'daily', interval: 86400000, time: next.toISOString(), hour: tod.hour, minute: tod.minute };
  }

  // 每周一三五 或 每周一、三、五
  const weekMatch = text.match(/^每周\s*([一二三四五六日天0-9,、\s]+)/);
  if (weekMatch) {
    const daysPart = weekMatch[1];
    const chars = daysPart.replace(/[、,\s]/g, '').split('');
    const map = { '一':1,'二':2,'三':3,'四':4,'五':5,'六':6,'日':0,'天':0,'0':0,'1':1,'2':2,'3':3,'4':4,'5':5,'6':6,'7':0 };
    const weekdays = [];
    for (const ch of chars) {
      if (map[ch] !== undefined && !weekdays.includes(map[ch])) weekdays.push(map[ch]);
    }
    const tod = parseTimeOfDay(text);
    if (!tod) return null;
    // 计算最近一次匹配的日期
    const now = new Date();
    let found = null;
    for (let i = 0; i < 7; i++) {
      const d = new Date(now);
      d.setDate(d.getDate() + i);
      if (weekdays.includes(d.getDay())) {
        const candidate = new Date(d);
        candidate.setHours(tod.hour, tod.minute, 0, 0);
        if (candidate.getTime() > now.getTime()) { found = candidate; break; }
      }
    }
    if (!found) {
      // 如果本周都过了，就找下周第一个
      for (let i = 1; i <= 7; i++) {
        const d = new Date(now);
        d.setDate(d.getDate() + i);
        if (weekdays.includes(d.getDay())) { found = new Date(d); found.setHours(tod.hour, tod.minute,0,0); break; }
      }
    }
    if (!found) return null;
    return { type: 'weekly', interval: 604800000, time: found.toISOString(), weekdays, hour: tod.hour, minute: tod.minute };
  }

  // 灵活短语：晚上六点十分、下午两点半、6:10、18:10
  const tod = parseTimeOfDay(text);
  if (tod) {
    const next = getNextOccurrenceForTime(tod.hour, tod.minute);
    return { type: 'once', time: next.toISOString() };
  }

  return null;
}

function clearTaskTimersEntry(task) {
  if (!task || !task.timer) return;
  const t = task.timer;
  if (Array.isArray(t)) {
    for (const item of t) {
      if (!item) continue;
      if (item.type === 'timeout') clearTimeout(item.id);
      else if (item.type === 'interval') clearInterval(item.id);
      else {
        try { clearTimeout(item.id || item); } catch (e) {}
        try { clearInterval(item.id || item); } catch (e) {}
      }
    }
  } else if (typeof t === 'object' && t.type) {
    if (t.type === 'timeout') clearTimeout(t.id);
    else if (t.type === 'interval') clearInterval(t.id);
  } else {
    try { clearTimeout(t); } catch (e) {}
    try { clearInterval(t); } catch (e) {}
  }
  delete task.timer;
}


// 自动获取服务器IP
function getServerIP() {
  try {
    const os = require('os');
    const interfaces = os.networkInterfaces();
    for (const name of Object.keys(interfaces)) {
      for (const iface of interfaces[name]) {
        if (iface.family === 'IPv4' && !iface.internal) {
          return iface.address;
        }
      }
    }
  } catch (error) {
    console.warn('无法自动获取服务器IP:', error.message);
  }
  return '127.0.0.1';
}

// 服务器IP配置（优先使用环境变量）
const SERVER_IP = process.env.SERVER_IP || getServerIP();

// 内网MQTT服务器配置
const MQTT_INTERNAL_SERVER = process.env.MQTT_INTERNAL_SERVER || 'mqtt://192.168.6.40:1883';
const MQTT_EXTERNAL_WS_SERVER = process.env.MQTT_EXTERNAL_WS_SERVER || `ws://${SERVER_IP}:8083/mqtt`; // EMQX WebSocket端口
const OLLAMA_HOST = process.env.OLLAMA_HOST || 'http://192.168.6.51:11434';
const WEB_PORT = parseInt(process.env.CONTROL_SERVICE_PORT) || 3002;
const AI_MODEL = process.env.AI_MODEL || 'qwen2.5:1.5b';

// 请求限制配置
const MAX_REQUEST_BODY_SIZE = process.env.MAX_REQUEST_BODY_SIZE || '10mb';
const CORS_ORIGINS = process.env.CORS_ORIGINS ? process.env.CORS_ORIGNS.split(',') : undefined;

// MQTT主题配置
const MQTT_TOPIC_PREFIX = process.env.MQTT_TOPIC_PREFIX || 'iot/device';
const CTRL_TOPIC_SUFFIX = 'control';  // 控制主题
const STATE_TOPIC_SUFFIX = 'state';   // 状态主题
const TEXTSETTING_TOPIC_SUFFIX = 'textsetting';  // 文本设置主题
const DATASETTING_TOPIC_SUFFIX = 'datasetting';  // 数据设置主题

// MQTT连接选项
const mqttOptions = {
  username: process.env.MQTT_USERNAME || 'mh',
  password: process.env.MQTT_PASSWORD || 'MaGu971204',
  clientId: `iot-control-${Math.random().toString(16).substr(2, 8)}`,
  clean: true,
  connectTimeout: 4000,
  reconnectPeriod: 1000
};

// 验证配置
if (!MQTT_INTERNAL_SERVER.startsWith('mqtt://') && !MQTT_INTERNAL_SERVER.startsWith('mqtts://')) {
  console.warn('内网MQTT服务器地址可能格式不正确，应以mqtt://或mqtts://开头');
}

// 初始化 LangChain Ollama 客户端
const llm = new ChatOllama({
  baseUrl: OLLAMA_HOST,
  model: AI_MODEL,
  temperature: 0.01,
  numPredict: 128
});

// 缓存设备配置和状态
let cachedDevices = {};
let cachedStates = {};

// 设备最后活跃时间记录
let deviceLastActive = {};

// 从环境变量读取离线检测配置
const OFFLINE_TIMEOUT = parseInt(process.env.OFFLINE_TIMEOUT) || 5 * 60 * 1000; // 默认5分钟
const CHECK_INTERVAL = parseInt(process.env.CHECK_INTERVAL) || 30 * 1000; // 默认30秒

// 更新设备活跃时间
function updateDeviceActive(unitId) {
  deviceLastActive[unitId] = Date.now();
}

// 检查并更新离线状态
async function checkOfflineDevices() {
  const now = Date.now();
  
  for (const [unitId, lastActive] of Object.entries(deviceLastActive)) {
    if (now - lastActive > OFFLINE_TIMEOUT) {
      // 更新缓存状态为OFFLINE
      if (cachedStates[unitId] !== 'OFFLINE') {
        cachedStates[unitId] = 'OFFLINE';
        console.log(`设备离线: ${unitId}`);
      }
    }
  }
}

// 启动定时检查
setInterval(checkOfflineDevices, CHECK_INTERVAL);
console.log(`设备离线检测已启动 - 超时时间: ${OFFLINE_TIMEOUT / 1000}秒, 检查间隔: ${CHECK_INTERVAL / 1000}秒`);

// 新增：初始化设备活跃时间（只监控control类型）
async function initDeviceActiveTime() {
  const devices = await dataManager.getDevices();
  for (const [groupName, groupConfig] of Object.entries(devices)) {
    if (groupName === 'lastUpdated') continue;
    
    if (groupConfig && groupConfig.units) {
      for (const unit of groupConfig.units) {
        // 只监控 control 类型的设备
        if (unit.type === 'control' && !deviceLastActive[unit.id]) {
          deviceLastActive[unit.id] = Date.now();
        }
      }
    }
  }
  console.log('[离线检测] control类型设备活跃时间初始化完成');
}

 initDeviceActiveTime();

// MQTT TCP客户端（内网）
let mqttConnected = false;
const client = mqtt.connect(MQTT_INTERNAL_SERVER, mqttOptions);



client.on('connect', () => {
  console.log('MQTT TCP控制客户端（内网）连接成功');
  mqttConnected = true;
});

client.on('error', (error) => {
  console.error('MQTT TCP控制客户端（内网）错误:', error);
  mqttConnected = false;
});

client.on('reconnect', () => {
  console.log('MQTT TCP控制客户端（内网）正在重连...');
});

client.on('close', () => {
  console.log('MQTT TCP控制客户端（内网）连接已关闭');
  mqttConnected = false;
});

// 验证设备命令
function validateDeviceCommand(cmd) {
  if (!cmd) return false;
  const upperCmd = cmd.toString().toUpperCase();
  return ['ON', 'OFF'].includes(upperCmd);
}

// 通过内网TCP/MQTT发送控制指令
function sendMqttControl(cmd, unitId) {
  if (!mqttConnected) {
    console.error('MQTT TCP控制客户端（内网）未连接，无法发送指令');
    return false;
  }

  // 构造控制主题：iot/device/设备单元ID/control
  const topic = `${MQTT_TOPIC_PREFIX}/${unitId}/${CTRL_TOPIC_SUFFIX}`;
  const message = cmd.toUpperCase();

  console.log(`发送MQTT TCP控制指令（内网）到 ${topic}: ${message}`);
  
  client.publish(topic, message, { 
    qos: 1,      // 至少一次传递
    retain: false // 不保留消息
  }, (err) => {
    if (err) {
      console.error('MQTT TCP控制指令发送失败:', err);
    } else {
      console.log('MQTT TCP控制指令发送成功');
    }
  });
  return true;
}

// 通过内网TCP/MQTT发送文本设置指令
function sendMqttTextSetting(value, unitId) {
  if (!mqttConnected) {
    console.error('MQTT TCP控制客户端（内网）未连接，无法发送指令');
    return false;
  }

  // 构造文本设置主题：iot/device/设备单元ID/textsetting
  const topic = `${MQTT_TOPIC_PREFIX}/${unitId}/${TEXTSETTING_TOPIC_SUFFIX}`;
  const message = value.toString();

  console.log(`发送MQTT TCP文本设置指令（内网）到 ${topic}: ${message}`);
  
  client.publish(topic, message, { 
    qos: 1,
    retain: false
  }, (err) => {
    if (err) {
      console.error('MQTT TCP文本设置指令发送失败:', err);
    } else {
      console.log('MQTT TCP文本设置指令发送成功');
    }
  });
  return true;
}

// 通过内网TCP/MQTT发送数据设置指令
function sendMqttDataSetting(value, unitId) {
  if (!mqttConnected) {
    console.error('MQTT TCP控制客户端（内网）未连接，无法发送指令');
    return false;
  }

  // 构造数据设置主题：iot/device/设备单元ID/datasetting
  const topic = `${MQTT_TOPIC_PREFIX}/${unitId}/${DATASETTING_TOPIC_SUFFIX}`;
  const message = value.toString();

  console.log(`发送MQTT TCP数据设置指令（内网）到 ${topic}: ${message}`);
  
  client.publish(topic, message, { 
    qos: 1,
    retain: false
  }, (err) => {
    if (err) {
      console.error('MQTT TCP数据设置指令发送失败:', err);
    } else {
      console.log('MQTT TCP数据设置指令发送成功');
    }
  });
  return true;
}

// 加载初始设备配置
async function loadInitialDevices() {
  try {
    console.log('正在加载初始设备配置...');
    cachedDevices = await dataManager.getDevices();
    
    // 构建状态映射
    cachedStates = {};
    for (const [groupName, config] of Object.entries(cachedDevices)) {
      for (const unit of config.units) {
        cachedStates[unit.id] = unit.status;
      }
    }
    
    console.log('设备配置已加载完成');
  } catch (error) {
    console.error('加载初始设备配置失败:', error);
    cachedDevices = {};
    cachedStates = {};
  }
}

// 监听 devices.json 文件变化
function watchDevicesFile() {
  try {
    fs.watch('./devices.json', async (eventType, filename) => {
      if (eventType === 'change') {
        console.log('检测到 devices.json 文件变化，正在更新缓存...');
        try {
          cachedDevices = await dataManager.getDevices();
          
          // 重建状态缓存
          cachedStates = {};
          for (const [groupName, config] of Object.entries(cachedDevices)) {
            for (const unit of config.units) {
              cachedStates[unit.id] = unit.status;
            }
          }
        } catch (error) {
          console.error('更新设备配置缓存失败:', error);
        }
      }
    });
  } catch (error) {
    console.error('无法监听 devices.json 文件:', error);
  }
}

// 速率限制中间件
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 800,
  message: '请求过于频繁，请稍后再试',
  standardHeaders: true,
  legacyHeaders: false,
});
app.use(limiter);

// 配置CORS
const corsOptions = CORS_ORIGINS ? { origin: CORS_ORIGINS } : {};
app.use(cors(corsOptions));

// 配置请求体大小限制
app.use(express.json({ limit: MAX_REQUEST_BODY_SIZE }));
app.use(express.urlencoded({ limit: MAX_REQUEST_BODY_SIZE, extended: true }));

// 提供静态文件
app.use(express.static(path.join(__dirname, './')));

// 代理设备管理API到配置服务
function proxyToConfigService(req, res) {
  const contentType = req.headers['content-type'] || 'application/json';
  let bodyData = '';

  if (req.body && typeof req.body === 'string') {
    bodyData = req.body;
  } else if (req.body && typeof req.body === 'object') {
    if (contentType.includes('application/x-www-form-urlencoded')) {
      const querystring = require('querystring');
      bodyData = querystring.stringify(req.body);
    } else {
      bodyData = JSON.stringify(req.body);
    }
  }

  const headers = {
    'Content-Type': contentType,
    'Content-Length': Buffer.byteLength(bodyData)
  };

  const options = {
    hostname: 'localhost',
    port: CONFIG_SERVICE_PORT,
    path: req.url,
    method: req.method,
    headers
  };

  console.log(`[代理] 转发设备管理请求: ${req.method} ${req.path} -> localhost:${CONFIG_SERVICE_PORT}${req.path}`);

  const proxyReq = http.request(options, (proxyRes) => {
    let body = '';
    proxyRes.on('data', (chunk) => {
      body += chunk;
    });
    proxyRes.on('end', () => {
      res.statusCode = proxyRes.statusCode || 200;
      for (const [key, value] of Object.entries(proxyRes.headers)) {
        if (key !== 'transfer-encoding') {
          res.setHeader(key, value);
        }
      }
      res.send(body);
    });
  });

  proxyReq.on('error', (err) => {
    console.error(`[代理] 设备管理请求转发失败: ${err.message}`);
    res.status(503).json({
      code: 503,
      data: null,
      msg: '配置服务暂不可用，请稍后重试'
    });
  });

  if (bodyData) {
    proxyReq.write(bodyData);
  }
  proxyReq.end();
}

app.all('/api/devices', proxyToConfigService);
app.all('/api/devices/:groupName', proxyToConfigService);
app.all('/api/devices/:groupName/units', proxyToConfigService);
app.all('/api/devices/:groupName/units/:unitId', proxyToConfigService);

// 根路径直接返回 index.html
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

// 接口：手动控制 - 通过TCP/MQTT下发
app.post('/api/control', (req, res) => {
  try {
    const { cmd, deviceType, deviceId, category, unitId, unitType } = req.body;

    // 输入验证
    if (!validateDeviceCommand(cmd)) {
      return res.status(400).json({ 
        code: 400, 
        msg: '无效的命令，只接受 ON 或 OFF' 
      });
    }

    if (!deviceType || !deviceId || !category || !unitId || !unitType) {
      return res.status(400).json({ 
        code: 400, 
        msg: '缺少必要的设备参数：deviceType, deviceId, category, unitId, unitType' 
      });
    }

    // 根据unitType决定通信方式
    if (unitType === 'control') {
      // 控制类型：通过TCP/MQTT下发
      const success = sendMqttControl(cmd, unitId);
      if (success) {
        res.json({ code: 200, msg: `指令 ${cmd.toUpperCase()} 已通过内网TCP下发到 ${unitId} (type: ${unitType})` });
      } else {
        res.status(500).json({ 
          code: 500, 
          msg: 'MQTT TCP连接失败，指令未发送' 
        });
      }
    } else if (unitType === 'state') {
      // 状态类型：通过WebSocket获取，这里只是模拟返回状态查询
      res.json({ code: 200, msg: `状态查询：${deviceType}/${deviceId}/${category}/${unitId} (type: ${unitType})` });
    } else if (unitType === 'text') {
      // 文本类型：直接返回文本值
      res.json({ code: 200, msg: `文本值查询：${deviceType}/${deviceId}/${category}/${unitId} (type: ${unitType})` });
    } else if (unitType === 'data') {
      // 数据类型：直接返回数值
      res.json({ code: 200, msg: `数值查询：${deviceType}/${deviceId}/${category}/${unitId} (type: ${unitType})` });
    } else {
      res.status(400).json({ 
        code: 400, 
        msg: '无效的单元类型，只接受 control、state、text 或 data' 
      });
    }
  } catch (error) {
    console.error('控制接口错误:', error);
    res.status(500).json({ 
      code: 500, 
      msg: '服务器内部错误' 
    });
  }
});

// 接口：控制单个插槽
app.post('/api/control-slot', async (req, res) => {
  try {
    const { slot, cmd } = req.body;

    // 输入验证
    if (!validateDeviceCommand(cmd)) {
      return res.status(400).json({ 
        code: 400, 
        msg: '无效的命令，只接受 ON 或 OFF' 
      });
    }

    if (!slot) {
      return res.status(400).json({ 
        code: 400, 
        msg: '请指定插槽名称' 
      });
    }

    // 验证插槽是否存在于设备配置中
    const devices = await dataManager.getDevices();
    let slotExists = false;
    let deviceInfo = null;
    
    for (const [groupName, config] of Object.entries(devices)) {
      for (const unit of config.units) {
        if (unit.id === slot) {
          slotExists = true;
          // 提取设备信息
          deviceInfo = {
            deviceType: groupName,
            deviceId: config.id || groupName,
            category: 'relay', // 假设继电器类别
            unitId: unit.id,
            unitType: unit.type || 'control' // 默认为control类型
          };
          break;
        }
      }
      if (slotExists) break;
    }
    
    if (!slotExists) {
      return res.status(400).json({ 
        code: 400, 
        msg: `插槽 ${slot} 不存在于设备配置中` 
      });
    }

    // 根据单元类型决定通信方式
    if (deviceInfo.unitType === 'control') {
      const success = sendMqttControl(cmd, deviceInfo.unitId);
      if (success) {
        // 更新数据库中的状态
        await dataManager.updateDeviceStatus(slot, cmd);
        res.json({ code: 200, msg: `指令 ${cmd.toUpperCase()} 已通过内网TCP下发到插槽 ${slot} (type: ${deviceInfo.unitType})` });
      } else {
        res.status(500).json({ 
          code: 500, 
          msg: 'MQTT TCP连接失败，指令未发送' 
        });
      }
    } else if (deviceInfo.unitType === 'state') {
      // 状态类型：通过WebSocket获取，这里只是模拟返回状态查询
      res.json({ code: 200, msg: `状态查询：插槽 ${slot} (type: ${deviceInfo.unitType})` });
    } else if (deviceInfo.unitType === 'text') {
      // 文本类型：直接返回文本值
      res.json({ code: 200, msg: `文本值查询：插槽 ${slot} (type: ${deviceInfo.unitType})` });
    } else if (deviceInfo.unitType === 'data') {
      // 数据类型：直接返回数值
      res.json({ code: 200, msg: `数值查询：插槽 ${slot} (type: ${deviceInfo.unitType})` });
    } else {
      res.status(400).json({ 
        code: 400, 
        msg: `无效的单元类型: ${deviceInfo.unitType}` 
      });
    }
  } catch (error) {
    console.error('插槽控制接口错误:', error);
    res.status(500).json({ 
      code: 500, 
      msg: '服务器内部错误' 
    });
  }
});

// 接口：设置文本值
app.post('/api/set-text', async (req, res) => {
  try {
    const { slot, value } = req.body;

    if (!slot || value === undefined || value === null) {
      return res.status(400).json({ 
        code: 400, 
        msg: '缺少必要参数：slot 和 value' 
      });
    }

    // 验证插槽是否存在
    const devices = await dataManager.getDevices();
    let slotExists = false;
    let unitType = 'text';
    
    for (const [groupName, config] of Object.entries(devices)) {
      for (const unit of config.units) {
        if (unit.id === slot) {
          slotExists = true;
          unitType = unit.type || 'text';
          break;
        }
      }
      if (slotExists) break;
    }
    
    if (!slotExists) {
      return res.status(400).json({ 
        code: 400, 
        msg: `插槽 ${slot} 不存在` 
      });
    }

    // 发送MQTT文本设置指令
    const success = sendMqttTextSetting(value, slot);
    if (success) {
      // 更新数据库中的值
      await dataManager.updateDeviceStatus(slot, value);
      res.json({ code: 200, msg: `文本设置成功，目标：插槽 ${slot}，值：${value}` });
    } else {
      res.status(500).json({ 
        code: 500, 
        msg: 'MQTT TCP连接失败，指令未发送' 
      });
    }
  } catch (error) {
    console.error('文本设置接口错误:', error);
    res.status(500).json({ 
      code: 500, 
      msg: '服务器内部错误' 
    });
  }
});

// 接口：设置数值
app.post('/api/set-data', async (req, res) => {
  try {
    const { slot, value } = req.body;

    if (!slot || value === undefined || value === null) {
      return res.status(400).json({ 
        code: 400, 
        msg: '缺少必要参数：slot 和 value' 
      });
    }

    // 验证数值
    const numValue = parseFloat(value);
    if (isNaN(numValue)) {
      return res.status(400).json({ 
        code: 400, 
        msg: 'value必须是数字' 
      });
    }

    // 验证插槽是否存在
    const devices = await dataManager.getDevices();
    let slotExists = false;
    let unitType = 'data';
    
    for (const [groupName, config] of Object.entries(devices)) {
      for (const unit of config.units) {
        if (unit.id === slot) {
          slotExists = true;
          unitType = unit.type || 'data';
          break;
        }
      }
      if (slotExists) break;
    }
    
    if (!slotExists) {
      return res.status(400).json({ 
        code: 400, 
        msg: `插槽 ${slot} 不存在` 
      });
    }

    // 发送MQTT数据设置指令
    const success = sendMqttDataSetting(numValue, slot);
    if (success) {
      // 更新数据库中的值
      await dataManager.updateDeviceStatus(slot, numValue.toString());
      res.json({ code: 200, msg: `数据设置成功，目标：插槽 ${slot}，值：${numValue}` });
    } else {
      res.status(500).json({ 
        code: 500, 
        msg: 'MQTT TCP连接失败，指令未发送' 
      });
    }
  } catch (error) {
    console.error('数据设置接口错误:', error);
    res.status(500).json({ 
      code: 500, 
      msg: '服务器内部错误' 
    });
  }
});

// 接口：获取设备状态（用于前端初始化）
app.get('/api/status', async (req, res) => {
  try {
    const devices = await dataManager.getDevices();
    const now = Date.now();
    
    // 构建在线状态信息
    const onlineStatus = {};
    for (const [unitId, lastActive] of Object.entries(deviceLastActive)) {
      onlineStatus[unitId] = now - lastActive <= OFFLINE_TIMEOUT;
    }
    
    res.json({
      code: 200,
      mqttConnected: mqttConnected,
      states: cachedStates,
      online: onlineStatus,  // 新增：设备在线状态
      configs: devices
    });
  } catch (error) {
    console.error('获取设备状态失败:', error);
    res.status(500).json({
      code: 500,
      msg: '获取设备状态失败',
      mqttConnected: false,
      states: {},
      online: {},
      configs: {}
    });
  }
});

// 接口：获取设备配置
app.get('/api/config', async (req, res) => {
  try {
    const devices = await dataManager.getDevices();
    res.json({
      code: 200,
      configs: devices,
      wsPort: process.env.WS_PORT || 8084,
      apiBase: '/api'
    });
  } catch (error) {
    console.error('获取设备配置失败:', error);
    res.status(500).json({
      code: 500,
      msg: '获取设备配置失败',
      configs: {},
      wsPort: process.env.WS_PORT || 8084,
      apiBase: '/api'
    });
  }
});

// 获取认证配置接口 - 判断是否需要用户输入凭据，有凭据时自动认证
app.get('/api/auth/config', (req, res) => {
  const mqttUsername = process.env.MQTT_USERNAME;
  const mqttPassword = process.env.MQTT_PASSWORD;
  
  // 判断是否配置了凭据（非空且非空白）
  const hasCredentials = !!(mqttUsername && mqttPassword && mqttUsername.trim() && mqttPassword.trim());
  
  if (!hasCredentials) {
    // 未配置凭据，需要用户输入
    res.json({
      code: 200,
      hasCredentials: false,
      requireAuth: true,
      autoAuthSuccess: false,
      username: null
    });
    return;
  }
  
  // 配置了凭据，自动进行认证
  console.log(`[认证] 使用环境变量凭据自动进行认证...`);
  
  const authClient = mqtt.connect(MQTT_INTERNAL_SERVER, {
    username: mqttUsername,
    password: mqttPassword,
    clientId: `auto-auth-${Math.random().toString(16).substr(2, 8)}`,
    clean: true,
    connectTimeout: 3000
  });
  
  const timeout = setTimeout(() => {
    authClient.end();
    console.log(`[认证] 环境变量凭据认证超时`);
    res.json({
      code: 200,
      hasCredentials: true,
      requireAuth: true,
      autoAuthSuccess: false,
      username: mqttUsername
    });
  }, 5000);
  
  authClient.on('connect', () => {
    clearTimeout(timeout);
    authClient.end();
    console.log(`[认证] 环境变量凭据认证成功`);
    res.json({
      code: 200,
      hasCredentials: true,
      requireAuth: false,
      autoAuthSuccess: true,
      username: mqttUsername
    });
  });
  
  authClient.on('error', (error) => {
    clearTimeout(timeout);
    authClient.end();
    console.log(`[认证] 环境变量凭据认证失败: ${error.message}`);
    res.json({
      code: 200,
      hasCredentials: true,
      requireAuth: true,
      autoAuthSuccess: false,
      username: mqttUsername
    });
  });
});

// 认证接口 - 通过MQTT服务器验证用户名和密码
app.post('/api/auth', (req, res) => {
  try {
    const { username, password } = req.body;
    
    if (!username || !password) {
      res.status(400).json({ code: 400, msg: '请输入用户名和密码' });
      return;
    }
    
    console.log(`[认证] 用户 ${username} 尝试通过服务器认证...`);
    
    // 创建临时MQTT客户端进行认证测试
    const authClient = mqtt.connect(MQTT_INTERNAL_SERVER, {
      username: username,
      password: password,
      clientId: `auth-test-${Math.random().toString(16).substr(2, 8)}`,
      clean: true,
      connectTimeout: 3000
    });
    
    // 设置超时
    const timeout = setTimeout(() => {
    authClient.end();
    console.log(`[认证] 用户 ${username} 认证超时`);
    res.status(408).json({ code: 408, msg: '认证超时' });
  }, 5000);
  
  authClient.on('connect', () => {
    clearTimeout(timeout);
    authClient.end();
    console.log(`[认证] 用户 ${username} 认证成功`);
    res.json({ code: 200, msg: '认证成功' });
  });
  
  authClient.on('error', (error) => {
    clearTimeout(timeout);
    authClient.end();
    console.log(`[认证] 用户 ${username} 认证失败: ${error.message}`);
    res.status(401).json({ code: 401, msg: '认证失败：用户名或密码错误' });
  });
    
  } catch (error) {
    console.error('[认证] 认证接口错误:', error);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

// ========== 定时开关功能 ==========

// 存储定时任务 { taskId: { timer, unitId, cmd, time, interval, name, enabled, createdAt } }
let scheduledTasks = {};

// 从文件加载定时任务
function initSchedules() {
  const savedSchedules = loadSchedules();
  // 先将所有任务加载到内存
  for (const [taskId, task] of Object.entries(savedSchedules)) {
    scheduledTasks[taskId] = { ...task };
  }
  // 然后恢复启用任务的定时器
  for (const [taskId, task] of Object.entries(scheduledTasks)) {
    if (task.enabled !== false && (task.time || task.interval)) {
      restoreTask(taskId, task);
    }
  }
  console.log(`[定时任务] 已从文件恢复 ${Object.keys(savedSchedules).length} 个任务`);
}

// 恢复任务定时器
function restoreTask(taskId, task) {
  if (task.interval) {
    // 周期性任务
    const now = Date.now();
    let delay = task.interval; // 默认立即开始
    
    // 如果是日任务或周任务且有指定时间，计算到下次执行的延迟
    if ((task.interval === 86400000 || task.interval === 604800000) && task.time) {
      const point = parseRecurringTimePoint(task.time);
      const targetTime = point ? point.getTime() : new Date(task.time).getTime();
      delay = targetTime - now;
      
      // 如果目标时间已经过去，加上间隔时间
      if (delay < 0) {
        const intervalsToAdd = Math.ceil(-delay / task.interval);
        delay += intervalsToAdd * task.interval;
      }
    }
    
    // 如果是周任务并且指定了 weekdays，分别为每个星期几创建独立的定时器（先 timeout 到首次执行，再每周循环）
    if (task.interval === 604800000 && Array.isArray(task.weekdays) && task.weekdays.length > 0 && task.time) {
      const timers = [];
      const nowDate = new Date();
      const todPoint = parseRecurringTimePoint(task.time) || new Date(task.time);
      const hour = todPoint.getHours();
      const minute = todPoint.getMinutes();

      for (const wd of task.weekdays) {
        // 计算下一个该星期几的时间
        let found = null;
        for (let i = 0; i < 7; i++) {
          const d = new Date(nowDate);
          d.setDate(d.getDate() + i);
          if (d.getDay() === wd) {
            const candidate = new Date(d);
            candidate.setHours(hour, minute, 0, 0);
            if (candidate.getTime() > nowDate.getTime()) { found = candidate; break; }
          }
        }
        if (!found) {
          for (let i = 1; i <= 7; i++) {
            const d = new Date(nowDate);
            d.setDate(d.getDate() + i);
            if (d.getDay() === wd) { found = new Date(d); found.setHours(hour, minute, 0, 0); break; }
          }
        }

        if (!found) continue;

        // 首次 timeout
        const startDelay = found.getTime() - Date.now();
        const startTimer = setTimeout(() => {
          console.log(`[周任务] 执行 ${taskId}(${wd}): ${task.unitId} -> ${task.cmd}`);
          sendMqttControl(task.cmd, task.unitId);

          // 每周循环
          const intervalId = setInterval(() => {
            console.log(`[周任务] 执行 ${taskId}(${wd}): ${task.unitId} -> ${task.cmd}`);
            sendMqttControl(task.cmd, task.unitId);
          }, 604800000);

          timers.push({ type: 'interval', id: intervalId });
        }, startDelay);

        timers.push({ type: 'timeout', id: startTimer });
      }

      scheduledTasks[taskId] = { ...task, timer: timers, recurring: true };
    } else {
      // 先等待到指定时间，然后开始循环执行
      const startTimer = setTimeout(() => {
        // 第一次执行
        const taskType = task.interval === 86400000 ? '日任务' : task.interval === 604800000 ? '周任务' : '周期任务';
        console.log(`[${taskType}] 执行 ${taskId}: ${task.unitId} -> ${task.cmd}`);
        sendMqttControl(task.cmd, task.unitId);
        
        // 创建循环定时器
        const timer = setInterval(() => {
          console.log(`[${taskType}] 执行 ${taskId}: ${task.unitId} -> ${task.cmd}`);
          sendMqttControl(task.cmd, task.unitId);
        }, task.interval);
        
        scheduledTasks[taskId] = { ...task, timer, recurring: true };
      }, delay);
      
      scheduledTasks[taskId] = { ...task, timer: startTimer, recurring: true };
    }
  } else if (task.time) {
    // 一次性任务
    const targetTime = new Date(task.time).getTime();
    const now = Date.now();
    if (targetTime > now) {
      const delay = targetTime - now;
      const timer = setTimeout(() => {
        console.log(`[定时任务] 执行 ${taskId}: ${task.unitId} -> ${task.cmd}`);
        sendMqttControl(task.cmd, task.unitId);
        delete scheduledTasks[taskId];
        saveSchedules(getSchedulesForSave());
      }, delay);
      scheduledTasks[taskId] = { ...task, timer };
    }
  }
}

// 获取待保存的任务数据（移除timer对象）
function getSchedulesForSave() {
  const schedules = {};
  for (const [taskId, task] of Object.entries(scheduledTasks)) {
    const { timer, ...taskData } = task;
    schedules[taskId] = taskData;
  }
  return schedules;
}

// 设置定时任务
app.post('/api/schedule', async (req, res) => {
  try {
    console.log('[定时任务] 收到创建请求:', JSON.stringify(req.body));
    const { id, name, unitId, cmd, time, recurring, weekdays, interval } = req.body;
    
    // 时区转换：如果是每日/每周任务，将本地时间转换为UTC时间存储
    let processedTime = time;
    if (typeof time === 'string' && time.includes(':') && (recurring === 'daily' || recurring === 'weekly' || interval === 86400000 || interval === 604800000)) {
      const [hours, minutes] = time.split(':').map(Number);
      const now = new Date();
      const localTime = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hours, minutes, 0, 0);
      if (!isNaN(localTime.getTime())) {
        // ✅ 正确：直接 toISOString()
        processedTime = new Date(localTime.getTime() + localTime.getTimezoneOffset() * 60000).toISOString();
    } else {
        processedTime = time;
      }
    }

    // 验证参数
    if (!unitId || !cmd || !processedTime) {
      return res.status(400).json({ code: 400, msg: '缺少必要参数: unitId, cmd, time' });
    }
    
    // 验证命令
    if (!['ON', 'OFF'].includes(cmd.toUpperCase())) {
      return res.status(400).json({ code: 400, msg: '无效的命令，只能是 ON 或 OFF' });
    }

    
    // 解析时间（支持数字、ISO、以及中文自然语言表达）
    let delay;
    const timeType = typeof time;

    if (timeType === 'number') {
      // 毫秒数
      delay = time;
    } else if (timeType === 'string') {
      // 先尝试解析中文时间表达式
      const parsed = parseChineseTimeExpression(time);
      if (parsed) {
        if (parsed.type === 'once') {
          const target = new Date(parsed.time).getTime();
          const now = Date.now();
          delay = target - now;
          if (delay < 0) return res.status(400).json({ code: 400, msg: '定时时间必须在未来' });
        } else if (parsed.type === 'daily' || parsed.type === 'weekly') {
          // 创建周期性任务（交给 restoreTask 恢复定时器）
          const taskId = id || `schedule-${Date.now()}`;
          if (scheduledTasks[taskId]) {
            return res.status(400).json({ code: 400, msg: '任务ID已存在' });
          }
          scheduledTasks[taskId] = {
            id: taskId,
            name: name || `定时任务-${taskId}`,
            unitId,
            cmd: cmd.toUpperCase(),
            interval: parsed.interval,
            time: parsed.time,
            weekdays: parsed.weekdays || undefined,
            enabled: true,
            createdAt: new Date().toISOString(),
            recurring: true
          };
          // 持久化并恢复
          saveSchedules(getSchedulesForSave());
          restoreTask(taskId, scheduledTasks[taskId]);
          return res.json({ code: 200, msg: '周期性定时任务已设置', taskId, scheduledAt: parsed.time });
        }
      }

      // 否则尝试解析为标准日期/时间或秒数
      const parsedTime = new Date(time);
      if (isNaN(parsedTime.getTime())) {
        // 尝试解析为秒数
        const seconds = parseFloat(time);
        if (!isNaN(seconds)) {
          delay = seconds * 1000;
        } else {
          return res.status(400).json({ code: 400, msg: '无效的时间格式' });
        }
      } else {
        // 计算距离目标时间的毫秒数
        const now = Date.now();
        delay = parsedTime.getTime() - now;
        if (delay < 0) {
          return res.status(400).json({ code: 400, msg: '定时时间必须在未来' });
        }
      }
    } else {
      return res.status(400).json({ code: 400, msg: '无效的时间格式' });
    }
    
    // 使用用户指定的ID或生成新ID
    const taskId = id || `schedule-${Date.now()}`;
    
    // 检查ID是否已存在
    if (scheduledTasks[taskId]) {
      return res.status(400).json({ code: 400, msg: '任务ID已存在' });
    }
    
    // 创建定时任务
    const timer = setTimeout(() => {
      // 执行定时任务
      console.log(`[定时任务] 执行 ${taskId}: ${unitId} -> ${cmd}`);
      sendMqttControl(cmd.toUpperCase(), unitId);
      
      // 从任务列表中移除已执行的任务
      delete scheduledTasks[taskId];
      saveSchedules(getSchedulesForSave());
    }, delay);
    
    // 保存任务信息
    scheduledTasks[taskId] = {
      timer,
      id: taskId,
      name: name || `定时任务-${taskId}`,
      unitId,
      cmd: cmd.toUpperCase(),
      time: new Date(Date.now() + delay).toISOString(),
      enabled: true,
      createdAt: new Date().toISOString()
    };
    
    // 保存到文件
    saveSchedules(getSchedulesForSave());
    
    console.log(`[定时任务] 已创建 ${taskId}: unitId=${unitId}, cmd=${cmd}, time=${scheduledTasks[taskId].time}`);
    console.log(`[定时任务] 当前任务列表:`, JSON.stringify(Object.keys(scheduledTasks)));
    
    res.json({
      code: 200,
      msg: '定时任务已设置',
      taskId,
      scheduledAt: scheduledTasks[taskId].time
    });
  } catch (error) {
    console.error('设置定时任务失败:', error);
    res.status(500).json({ code: 500, msg: '设置定时任务失败' });
  }
});

// 获取所有定时任务
app.get('/api/schedule', (req, res) => {
  // 转换任务信息（移除timer对象）
  const tasks = {};
  for (const [taskId, task] of Object.entries(scheduledTasks)) {
    const { timer, ...taskData } = task;
    tasks[taskId] = taskData;
  }
  
  res.json({
    code: 200,
    schedules: tasks
  });
});

// 获取所有定时任务（列表格式）
app.get('/api/schedule/list', (req, res) => {
  const schedules = [];
  for (const [taskId, task] of Object.entries(scheduledTasks)) {
    const { timer, ...taskData } = task;
    schedules.push({ id: taskId, ...taskData });
  }
  
  res.json({
    code: 200,
    schedules
  });
});

// 更新定时任务
app.put('/api/schedule/:taskId', async (req, res) => {
  try {
    const { taskId } = req.params;
    const { unitId, cmd, time, recurring, weekdays, interval } = req.body;
    
    if (!scheduledTasks[taskId]) {
      return res.status(404).json({ code: 404, msg: '定时任务不存在' });
    }
    
    // 时区转换：如果是每日/每周任务，将本地时间转换为UTC时间存储
    let processedTime = time;
    if (typeof time === 'string' && time.includes(':') && (recurring === 'daily' || recurring === 'weekly' || interval === 86400000 || interval === 604800000)) {
      const [hours, minutes] = time.split(':').map(Number);
      const now = new Date();
      const localTime = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hours, minutes, 0, 0);
      if (!isNaN(localTime.getTime())) {
        processedTime = new Date(localTime.getTime() + localTime.getTimezoneOffset() * 60000).toISOString();
      } else {
        processedTime = time;
      }
    } else {
      processedTime = time; // 其他任务直接使用原时间
    }

    
    // 验证命令
    if (cmd && !['ON', 'OFF'].includes(cmd.toUpperCase())) {
      return res.status(400).json({ code: 400, msg: '无效的命令，只能是 ON 或 OFF' });
    }
    
    // 取消原有的定时器
    clearTaskTimersEntry(scheduledTasks[taskId]);
    
    const task = scheduledTasks[taskId];
    
    
    // 更新命令
    if (cmd) {
      task.cmd = cmd.toUpperCase();
    }

        // 更新星期信息（新增）
    if (weekdays !== undefined) {
      task.weekdays = weekdays;
    }
    
    // 更新 unitId
    if (unitId) {
      task.unitId = unitId;
    }
    
    // 更新时间或间隔
    if (interval) {
      // 周期性任务
      const now = Date.now();
      let initialDelay = 0;
      
      // 如果是日任务或周任务且有指定时间，计算到下次执行的延迟
      if ((interval === 86400000 || interval === 604800000) && processedTime) {
        const targetTime = new Date(processedTime).getTime();
        initialDelay = targetTime - now;
        if (initialDelay < 0) {
          const intervalsToAdd = Math.ceil(-initialDelay / interval);
          initialDelay += intervalsToAdd * interval;
        }
      }
      
      // 先等待到指定时间，然后开始循环执行
      const startTimer = setTimeout(() => {
        const taskType = interval === 86400000 ? '日任务' : interval === 604800000 ? '周任务' : '周期任务';
        console.log(`[${taskType}] 执行 ${taskId}: ${task.unitId} -> ${task.cmd}`);
        sendMqttControl(task.cmd, task.unitId);
        
        const timer = setInterval(() => {
          console.log(`[${taskType}] 执行 ${taskId}: ${task.unitId} -> ${task.cmd}`);
          sendMqttControl(task.cmd, task.unitId);
        }, interval);
        
        task.timer = timer;
      }, initialDelay);
      
      task.timer = startTimer;
      task.interval = interval;
      task.time = processedTime || task.time;  // 更新 time 字段
      task.recurring = true;
    } else if (time) {
      // 支持中文表达的时间（一次性或转换为周期性）
      const parsed = typeof time === 'string' ? parseChineseTimeExpression(time) : null;
      if (parsed) {
        if (parsed.type === 'once') {
          const targetTime = new Date(parsed.time);
          const now = Date.now();
          const delay = targetTime.getTime() - now;
          if (delay < 0) {
            return res.status(400).json({ code: 400, msg: '定时时间必须在未来' });
          }
          const timer = setTimeout(() => {
            console.log(`[定时任务] 执行 ${taskId}: ${task.unitId} -> ${task.cmd}`);
            sendMqttControl(task.cmd, task.unitId);
            delete scheduledTasks[taskId];
            saveSchedules(getSchedulesForSave());
          }, delay);
          task.timer = timer;
          task.time = targetTime.toISOString();
          task.interval = null;
          task.recurring = false;
        } else if (parsed.type === 'daily' || parsed.type === 'weekly') {
          // 转换为周期性任务
          task.interval = parsed.interval;
          task.time = parsed.time;
          if (parsed.weekdays) task.weekdays = parsed.weekdays;
          task.recurring = true;
          // 取消老的计时器（已在上方处理）
          restoreTask(taskId, task);
        }
      } else {
        // 一次性任务（传统 ISO / 时间字符串）
        const targetTime = new Date(processedTime);
        const now = Date.now();
        const delay = targetTime.getTime() - now;
        if (delay < 0) {
          return res.status(400).json({ code: 400, msg: '定时时间必须在未来' });
        }
        const timer = setTimeout(() => {
          console.log(`[定时任务] 执行 ${taskId}: ${task.unitId} -> ${task.cmd}`);
          sendMqttControl(task.cmd, task.unitId);
          delete scheduledTasks[taskId];
          saveSchedules(getSchedulesForSave());
        }, delay);
        task.timer = timer;
        task.time = targetTime.toISOString();
        task.interval = null;
        task.recurring = false;
      }
    }
    
    // 保存到文件
    saveSchedules(getSchedulesForSave());
    
    console.log(`[定时任务] 已更新 ${taskId}: ${task.unitId} -> ${task.cmd}`);
    
    res.json({
      code: 200,
      msg: '定时任务已更新'
    });
  } catch (error) {
    console.error('更新定时任务失败:', error);
    res.status(500).json({ code: 500, msg: '更新定时任务失败' });
  }
});

// 删除定时任务
app.delete('/api/schedule/:taskId', (req, res) => {
  const { taskId } = req.params;
  
  if (!scheduledTasks[taskId]) {
    return res.status(404).json({ code: 404, msg: '定时任务不存在' });
  }
  
  // 取消定时器
  clearTaskTimersEntry(scheduledTasks[taskId]);
  
  // 删除任务
  const task = scheduledTasks[taskId];
  delete scheduledTasks[taskId];
  
  // 保存到文件
  saveSchedules(getSchedulesForSave());
  
  console.log(`[定时任务] 已取消 ${taskId}: ${task.unitId} -> ${task.cmd}`);
  
  res.json({
    code: 200,
    msg: '定时任务已取消'
  });
});

// 启用/禁用定时任务
app.put('/api/schedule/:taskId/enable', (req, res) => {
  const { taskId } = req.params;
  const { enabled } = req.body;
  
  if (!scheduledTasks[taskId]) {
    return res.status(404).json({ code: 404, msg: '定时任务不存在' });
  }
  
  const task = scheduledTasks[taskId];
  
  // 确保 enabled 有默认值
  if (task.enabled === undefined) {
    task.enabled = true;
  }
  
  if (enabled) {
    // 启用任务
    if (task.enabled) {
      return res.status(400).json({ code: 400, msg: '任务已经是启用状态' });
    }
    
    task.enabled = true;
    
    // 重新创建定时器
    if (task.recurring && task.interval) {
      // 周期性任务
      const timer = setInterval(() => {
        console.log(`[周期性任务] 执行 ${taskId}: ${task.unitId} -> ${task.cmd}`);
        sendMqttControl(task.cmd, task.unitId);
      }, task.interval);
      task.timer = timer;
    } else if (task.time) {
      // 一次性任务
      const targetTime = new Date(task.time).getTime();
      const now = Date.now();
      if (targetTime > now) {
        const delay = targetTime - now;
        const timer = setTimeout(() => {
          console.log(`[定时任务] 执行 ${taskId}: ${task.unitId} -> ${task.cmd}`);
          sendMqttControl(task.cmd, task.unitId);
          delete scheduledTasks[taskId];
          saveSchedules(getSchedulesForSave());
        }, delay);
        task.timer = timer;
      }
    }
    
    console.log(`[定时任务] 已启用 ${taskId}`);
  } else {
    // 禁用任务
    if (!task.enabled) {
      return res.status(400).json({ code: 400, msg: '任务已经是禁用状态' });
    }
    
    task.enabled = false;
    
    // 取消定时器
    clearTaskTimersEntry(task);
    
    console.log(`[定时任务] 已禁用 ${taskId}`);
  }
  
  // 保存到文件
  saveSchedules(getSchedulesForSave());
  
  res.json({
    code: 200,
    msg: enabled ? '定时任务已启用' : '定时任务已禁用',
    enabled: task.enabled
  });
});

// 设置周期性定时任务（循环执行）
app.post('/api/schedule/recurring', async (req, res) => {
  try {
    const { id, name, unitId, cmd, interval, time, weekdays } = req.body;
    
    // 验证参数
    if (!unitId || !cmd || !interval) {
      return res.status(400).json({ code: 400, msg: '缺少必要参数: unitId, cmd, interval' });
    }
    
    // 验证命令
    if (!['ON', 'OFF'].includes(cmd.toUpperCase())) {
      return res.status(400).json({ code: 400, msg: '无效的命令，只能是 ON 或 OFF' });
    }
    
    // 验证间隔时间（至少10秒）
    if (interval < 10000) {
      return res.status(400).json({ code: 400, msg: '间隔时间不能小于10秒' });
    }
    
    // 使用用户指定的ID或生成新ID
    const taskId = id || `schedule-${Date.now()}`;
    
    // 检查ID是否已存在
    if (scheduledTasks[taskId]) {
      return res.status(400).json({ code: 400, msg: '任务ID已存在' });
    }
    
    const now = Date.now();
    let initialDelay = 0;
    let firstRunTime = null;
    
    // 如果是日任务或周任务且有指定时间，计算到下次执行的延迟
    if ((interval === 86400000 || interval === 604800000) && time) {
      const targetTime = new Date(time).getTime();
      firstRunTime = new Date(time);
      initialDelay = targetTime - now;
      
      // 如果目标时间已经过去，加上间隔时间
      if (initialDelay < 0) {
        const intervalsToAdd = Math.ceil(-initialDelay / interval);
        initialDelay += intervalsToAdd * interval;
        firstRunTime = new Date(now + initialDelay);
      }
    }
    
    // 统一将本地时间转换为UTC时间保存，避免前端/后端格式不一致
    let storedTime = null;
    if (typeof time === 'string' && time.trim().length > 0) {
      const parsedTime = new Date(time);
      if (!isNaN(parsedTime.getTime())) {
        storedTime = parsedTime.toISOString();
      } else {
        storedTime = time;
      }
    }

    // 创建周期性任务
    scheduledTasks[taskId] = {
      timer: null,
      id: taskId,
      name: name || `周期性任务-${taskId}`,
      unitId,
      cmd: cmd.toUpperCase(),
      interval,
      time: storedTime,
      weekdays: Array.isArray(weekdays) && weekdays.length > 0 ? weekdays : undefined,
      enabled: true,
      createdAt: new Date().toISOString(),
      recurring: true
    };

    // 如果是每周任务并且带有 weekdays，则让 restoreTask 处理多个星期几的定时器
    if (interval === 604800000 && Array.isArray(scheduledTasks[taskId].weekdays) && scheduledTasks[taskId].weekdays.length > 0 && scheduledTasks[taskId].time) {
      saveSchedules(getSchedulesForSave());
      restoreTask(taskId, scheduledTasks[taskId]);
    } else {
      // 先等待到指定时间，然后开始循环执行
      const startTimer = setTimeout(() => {
        const taskType = interval === 86400000 ? '日任务' : interval === 604800000 ? '周任务' : '周期任务';
        // 第一次执行
        console.log(`[${taskType}] 执行 ${taskId}: ${unitId} -> ${cmd}`);
        sendMqttControl(cmd.toUpperCase(), unitId);
        
        // 创建循环定时器
        const timer = setInterval(() => {
          console.log(`[${taskType}] 执行 ${taskId}: ${unitId} -> ${cmd}`);
          sendMqttControl(cmd.toUpperCase(), unitId);
        }, interval);
        
        scheduledTasks[taskId].timer = timer;
      }, initialDelay);
      scheduledTasks[taskId].timer = startTimer;
      saveSchedules(getSchedulesForSave());
    }
    console.log(`[周期性任务] 已创建 ${taskId}: ${unitId} 每${interval / 1000}秒执行 ${cmd}`);
    
    res.json({
      code: 200,
      msg: '周期性定时任务已设置',
      taskId,
      interval
    });
  } catch (error) {
    console.error('设置周期性定时任务失败:', error);
    res.status(500).json({ code: 500, msg: '设置周期性定时任务失败' });
  }
});

// 基础AI指令解析（使用LangChain Ollama）
async function parseCommand(text) {
  // 输入验证
  if (!text || typeof text !== 'string' || text.trim().length === 0) {
    console.log('AI指令解析失败：输入为空');
    return { cmd: 'NULL', slot: null, unitType: null };
  }

  // 限制输入长度
  if (text.length > 200) {
    console.log('AI指令解析失败：输入过长');
    return { cmd: 'NULL', slot: null, unitType: null };
  }

  try {
    const prompt = `
你是智能家居指令解析器，识别命令和设备插槽：
- 命令: 打开/关闭 -> ON/OFF
- 当前可用设备: ${getDeviceListForAI().join(', ')}
- 其他 -> NULL

用户指令：${text.trim()}

输出格式（JSON）：
{"cmd": "ON|OFF|NULL", "slot": "具体设备ID|null", "unitType": "control|state|null"}
    `.trim();

    const result = await llm.invoke(prompt);
    const response = result.content.trim();
    
    console.log(`AI解析结果: ${response}`);
    
    try {
      // 尝试解析JSON响应
      const parsed = JSON.parse(response);
      return {
        cmd: parsed.cmd || 'NULL',
        slot: parsed.slot || null,
        unitType: parsed.unitType || 'control' // 默认为control类型
      };
    } catch (e) {
      // 如果不是JSON格式，尝试提取信息
      if (response.includes('ON') || response.includes('offen')) {
        // 简单提取命令
        const cmd = response.includes('ON') ? 'ON' : 'OFF';
        // 简单提取插槽（使用缓存的设备配置）
        for (const [groupName, config] of Object.entries(cachedDevices)) {
          for (let i = 0; i < config.units.length; i++) {
            const unitIndex = i + 1;
            if (response.includes(unitIndex.toString()) || 
                response.toLowerCase().includes(['first', 'second', 'third', 'fourth', 'fifth'][i])) {
              return { cmd, slot: config.units[i].id, unitType: config.units[i].type || 'control' };
            }
          }
        }
        return { cmd, slot: null, unitType: 'control' };
      } else {
        return { cmd: 'NULL', slot: null, unitType: null };
      }
    }
  } catch (e) {
    console.error('AI调用失败:', e.message);
    return { cmd: 'NULL', slot: null, unitType: null };
  }
}

/**
 * AI高级指令解析函数
 */
async function parseAdvancedCommand(text) {
  // 输入验证
  if (!text || typeof text !== 'string' || text.trim().length === 0) {
    console.log('AI指令解析失败：输入为空');
    const suggestions = await generateSuggestions();
    return [{ 
      action: 'NULL', 
      device: '', 
      slot: null, 
      unitType: null,
      error: '没有这个设备或指令不明确，请重新输入指令',
      suggestions: suggestions
    }];
  }

  try {
    // 创建详细的设备信息，用于AI理解
    const deviceInfo = [];
    
    for (const [groupName, config] of Object.entries(cachedDevices)) {
      const unitsInfo = config.units.map(unit => 
        `"${unit.name || unit.id}": "${unit.id}" (type: ${unit.type || 'control'}, location: ${config.location || 'unknown'})`
      ).join(', ');
      
      deviceInfo.push(
        `设备组名: "${groupName}", ` +
        `设备显示名: "${config.displayName || config.name}", ` +
        `位置: "${config.location || ''}", ` +
        `控制单元: {${unitsInfo}}`
      );
    }
    
    const deviceDetails = deviceInfo.join('; ');
    
    // 检查是否包含"只"字
    const isOnlyCommand = text.includes('只');
    
    let baseInstruction = '\n可执行动作: ["打开", "关闭"]\n';
    
    if (isOnlyCommand) {
      baseInstruction += `\n特别说明：用户指令包含"只"字，表示只控制特定设备单元。请优先匹配设备单元名称，如果匹配到多个，则结合设备组名称和位置信息进行精确匹配，确保只返回一个目标单元。\n`;
    } else {
      baseInstruction += '\n注意：如果用户指令涉及多个设备，返回多个对象组成的数组。如果用户指令不明确，返回一个对象，action为NULL。\n';
    }
    
    const prompt = `
你是智能家居控制助手，支持多控制开关设备：

当前系统设备配置:
${deviceDetails}

${baseInstruction}
用户输入：${text.trim()}

输出格式（JSON数组）：
[
  {
    "action": "打开|关闭|NULL",
    "device": "设备显示名或设备组名",
    "slot": "具体设备ID|设备名称|null",
    "unitType": "control|state|null",
    "location": "设备位置（如客厅、卧室等）|null"
  }
]

重要说明：
- 严格按照JSON格式输出，不要包含任何解释文字
- 如果用户指令包含"只"字（如"只关电视"），请只返回一个精确匹配的设备单元
- 如果用户指令涉及多个设备且不含"只"字，返回多个对象组成的数组
- 如果用户指令不明确，返回一个对象，action为NULL
- 对于每个设备，需要指定其单元类型（control或state）
- 如果已知设备位置，请在location字段中注明
    `.trim();

    const result = await llm.invoke(prompt);
    const response = result.content.trim();
    
    console.log(`AI高级解析原始响应: ${response}`);
    
    // 尝试解析JSON响应
    try {
      let parsed = JSON.parse(response);
      
      // 确保返回的是数组
      if (!Array.isArray(parsed)) {
        parsed = [parsed];
      }
      
      // 验证和标准化结果
      const validatedResults = parsed.map(item => ({
        action: item.action || 'NULL',
        device: item.device || '',
        slot: item.slot || null,
        unitType: item.unitType || 'control',
        location: item.location || null
      }));
      
      console.log(`AI高级解析结果:`, validatedResults);
      
      // 根据是否包含"只"字进行不同处理
      if (isOnlyCommand) {
        return await processOnlyCommand(text, validatedResults);
      } else {
        return await processNormalCommand(text, validatedResults);
      }
    } catch (e) {
      console.error('无法从AI响应中提取有效的JSON，尝试解析普通文本...');
      // 如果不是JSON格式，使用备用解析逻辑
      return await fallbackParse(text, isOnlyCommand);
    }
  } catch (error) {
    console.error('AI高级指令解析错误:', error);
    const suggestions = await generateSuggestions();
    return [{
      action: 'NULL',
      device: '',
      slot: null,
      unitType: null,
      error: '没有这个设备或指令不明确，请重新输入指令',
      suggestions: suggestions
    }];
  }
}


/**
 * 处理"只"命令的精确匹配逻辑
 */
async function processOnlyCommand(originalText, aiResults) {
  console.log(`处理"只"命令：${originalText}`);
  
  // 步骤1：提取目标单元名称（移除动作词）
  let targetName = '';
  const unitMatch = originalText.match(/只\s*(.*)/);
  if (unitMatch && unitMatch[1]) {
    let content = unitMatch[1].trim();
    // 移除动作词
    content = content.replace(/^(开|关|打开|关闭)\s*/, '').trim();
    targetName = content;
  }
  
  console.log(`提取到的目标名称: ${targetName}`);
  
  // 如果没有提取到目标名称，返回错误
  if (!targetName) {
    const suggestions = await generateSuggestions();
    return [{ 
      action: 'NULL', 
      device: '', 
      slot: null, 
      unitType: null, 
      error: '没有这个设备或指令不明确，请重新输入指令',
      suggestions: suggestions
    }];
  }
  
  // 步骤2：收集所有可能的设备单元
  let candidates = [];
  
  for (const [groupName, config] of Object.entries(cachedDevices)) {
    for (const unit of config.units) {
      candidates.push({
        unitId: unit.id,
        unitName: unit.name || '',
        groupName: groupName,
        groupDisplayName: config.displayName || groupName,
        location: config.location || '',
        unitType: unit.type || 'control'
      });
    }
  }
  
  // 步骤3：逐步进行匹配
  let matches = [];
  const action = extractAction(originalText);
  
  // 阶段1：优先匹配设备单元名称
  matches = candidates.filter(c => 
    c.unitName && (c.unitName.includes(targetName) || targetName.includes(c.unitName))
  );
  
  console.log(`阶段1 - 单元名称匹配结果: ${matches.length} 个`);
  
  if (matches.length === 1) {
    // 唯一匹配，直接返回
    const matchResult = matches[0];
    return [{
      action: action,
      device: matchResult.groupDisplayName,
      slot: matchResult.unitId,
      unitType: matchResult.unitType
    }];
  }
  
  // 阶段2：如果匹配多个单元，结合设备组名称匹配
  if (matches.length > 1 || matches.length === 0) {
    const searchPool = matches.length > 0 ? matches : candidates;
    
    const groupMatches = searchPool.filter(c => 
      (c.groupName && (c.groupName.includes(targetName) || targetName.includes(c.groupName))) ||
      (c.groupDisplayName && (c.groupDisplayName.includes(targetName) || targetName.includes(c.groupDisplayName)))
    );
    
    console.log(`阶段2 - 结合设备组匹配结果: ${groupMatches.length} 个`);
    
    if (groupMatches.length === 1) {
      const matchResult = groupMatches[0];
      return [{
        action: action,
        device: matchResult.groupDisplayName,
        slot: matchResult.unitId,
        unitType: matchResult.unitType
      }];
    }
    
    // 更新matches为更精确的结果
    if (groupMatches.length > 0) {
      matches = groupMatches;
    }
  }
  
  // 阶段3：结合位置信息匹配
  // 提取位置信息
  const locationMatch = originalText.match(/(客厅|卧室|厨房|书房|阳台|主卧|次卧|卫生间|浴室|走廊|餐厅)/);
  const location = locationMatch ? locationMatch[1] : '';
  
  if (location && (matches.length > 1 || matches.length === 0)) {
    const searchPool = matches.length > 0 ? matches : candidates;
    
    const locationMatches = searchPool.filter(c => 
      c.location && (c.location.includes(location) || location.includes(c.location))
    );
    
    console.log(`阶段3 - 结合位置匹配结果: ${locationMatches.length} 个`);
    
    if (locationMatches.length === 1) {
      const matchResult = locationMatches[0];
      return [{
        action: action,
        device: matchResult.groupDisplayName,
        slot: matchResult.unitId,
        unitType: matchResult.unitType
      }];
    }
    
    // 更新matches为更精确的结果
    if (locationMatches.length > 0) {
      matches = locationMatches;
    }
  }
  
  // 阶段4：位置+设备单元或位置+设备组+设备单元的组合匹配
  if (location && matches.length > 1) {
    const combinedMatches = matches.filter(c => 
      (c.location && c.location.includes(location) && c.unitName && c.unitName.includes(targetName)) ||
      (c.location && c.location.includes(location) && c.groupName && c.groupName.includes(targetName))
    );
    
    console.log(`阶段4 - 位置+设备组合匹配结果: ${combinedMatches.length} 个`);
    
    if (combinedMatches.length === 1) {
      const matchResult = combinedMatches[0];
      return [{
        action: action,
        device: matchResult.groupDisplayName,
        slot: matchResult.unitId,
        unitType: matchResult.unitType
      }];
    }
  }
  
  // 如果经过所有阶段仍有多个匹配或没有匹配
  if (matches.length === 0) {
    const suggestions = await generateSuggestions();
    return [{ 
      action: 'NULL', 
      device: '', 
      slot: null, 
      unitType: null, 
      error: '没有这个设备或指令不明确，请重新输入指令',
      suggestions: suggestions
    }];
  } else if (matches.length > 1) {
    const suggestions = await generateSuggestions();
    return [{ 
      action: 'NULL', 
      device: '', 
      slot: null, 
      unitType: null, 
      error: '找到多个匹配的设备，请更明确地指定设备名称或位置',
      suggestions: suggestions
    }];
  }
  
  // 默认返回第一个匹配
  const matchResult = matches[0];
  return [{
    action: action,
    device: matchResult.groupDisplayName,
    slot: matchResult.unitId,
    unitType: matchResult.unitType
  }];
}

/**
 * 处理普通命令（不含"只"字）
 */
async function processNormalCommand(originalText, aiResults) {
  console.log(`处理普通命令：${originalText}`);
  
  // 提取动作
  const action = extractAction(originalText);
  
  if (action === 'NULL') {
    const suggestions = await generateSuggestions();
    return [{ 
      action: 'NULL', 
      device: '', 
      slot: null, 
      unitType: null, 
      error: '没有这个设备或指令不明确，请重新输入指令',
      suggestions: suggestions
    }];
  }
  
  // 检查是否涉及多个设备（通过"和"、"与"、"、"、"，"等分隔符判断）
  const multiDevicePatterns = ['和', '与', '、', '，', '以及', '还有'];
  const hasMultipleDevices = multiDevicePatterns.some(pattern => originalText.includes(pattern));
  
  console.log(`检测到多设备指令: ${hasMultipleDevices}`);
  
  // 如果是多设备指令，分割指令并分别处理
  if (hasMultipleDevices) {
    return await processMultiDeviceCommand(originalText, action);
  }
  
  // 单设备处理逻辑（原有逻辑）
  
  // 阶段1：先匹配设备组
  const matchedGroups = [];
  
  for (const [groupName, config] of Object.entries(cachedDevices)) {
    const displayName = config.displayName || groupName;
    
    // 检查指令是否包含设备组名称
    if (originalText.includes(displayName) || originalText.includes(groupName)) {
      matchedGroups.push({
        groupName: groupName,
        displayName: displayName,
        config: config
      });
    }
  }
  
  console.log(`阶段1 - 设备组匹配结果: ${matchedGroups.length} 个`);
  
  if (matchedGroups.length === 1) {
    // 匹配到一个设备组，返回该组下的所有单元
    const group = matchedGroups[0];
    const results = [];
    
    for (const unit of group.config.units) {
      results.push({
        action: action,
        device: group.displayName,
        slot: unit.id,
        unitType: unit.type || 'control'
      });
    }
    
    console.log(`普通命令匹配到设备组，返回所有单元:`, results);
    return results;
  } else if (matchedGroups.length > 1) {
    // 匹配到多个设备组，继续匹配位置
    const locationMatch = originalText.match(/(客厅|卧室|厨房|书房|阳台|主卧|次卧|卫生间|浴室|走廊|餐厅)/);
    const location = locationMatch ? locationMatch[1] : '';
    
    console.log(`阶段1.1 - 多个设备组，提取位置: ${location}`);
    
    if (location) {
      // 根据位置筛选设备组
      const filteredGroups = matchedGroups.filter(group => 
        group.config.location && (group.config.location.includes(location) || location.includes(group.config.location))
      );
      
      console.log(`阶段1.2 - 位置筛选后设备组: ${filteredGroups.length} 个`);
      
      if (filteredGroups.length > 0) {
        const results = [];
        
        for (const group of filteredGroups) {
          for (const unit of group.config.units) {
            results.push({
              action: action,
              device: group.displayName,
              slot: unit.id,
              unitType: unit.type || 'control'
            });
          }
        }
        
        console.log(`普通命令匹配到多个设备组，位置筛选后返回:`, results);
        return results;
      }
    }
    
    // 没有位置信息或位置筛选后没有结果，返回所有匹配的设备组
    const results = [];
    
    for (const group of matchedGroups) {
      for (const unit of group.config.units) {
        results.push({
          action: action,
          device: group.displayName,
          slot: unit.id,
          unitType: unit.type || 'control'
        });
      }
    }
    
    console.log(`普通命令匹配到多个设备组，返回所有单元:`, results);
    return results;
  }
  
  // 阶段2：设备组匹配不上，尝试匹配控制单元
  const matchedUnits = [];
  
  for (const [groupName, config] of Object.entries(cachedDevices)) {
    for (const unit of config.units) {
      if (unit.name && originalText.includes(unit.name)) {
        matchedUnits.push({
          unitId: unit.id,
          unitName: unit.name,
          groupName: groupName,
          displayName: config.displayName || groupName,
          location: config.location || '',
          unitType: unit.type || 'control'
        });
      }
    }
  }
  
  console.log(`阶段2 - 控制单元匹配结果: ${matchedUnits.length} 个`);
  
  if (matchedUnits.length === 1) {
    // 只匹配到一个控制单元，直接返回
    const unit = matchedUnits[0];
    
    return [{
      action: action,
      device: unit.displayName,
      slot: unit.unitId,
      unitType: unit.unitType
    }];
  } else if (matchedUnits.length > 1) {
    // 匹配到多个控制单元，继续匹配位置
    const locationMatch = originalText.match(/(客厅|卧室|厨房|书房|阳台|主卧|次卧|卫生间|浴室|走廊|餐厅)/);
    const location = locationMatch ? locationMatch[1] : '';
    
    console.log(`阶段2.1 - 多个控制单元，提取位置: ${location}`);
    
    if (location) {
      // 根据位置筛选控制单元
      const filteredUnits = matchedUnits.filter(unit => 
        unit.location && (unit.location.includes(location) || location.includes(unit.location))
      );
      
      console.log(`阶段2.2 - 位置筛选后控制单元: ${filteredUnits.length} 个`);
      
      if (filteredUnits.length > 0) {
        const results = [];
        
        for (const unit of filteredUnits) {
          results.push({
            action: action,
            device: unit.displayName,
            slot: unit.unitId,
            unitType: unit.unitType
          });
        }
        
        console.log(`普通命令匹配到多个控制单元，位置筛选后返回:`, results);
        return results;
      }
    }
    
    // 没有位置信息或位置筛选后没有结果，返回所有匹配的控制单元
    const results = [];
    
    for (const unit of matchedUnits) {
      results.push({
        action: action,
        device: unit.displayName,
        slot: unit.unitId,
        unitType: unit.unitType
      });
    }
    
    console.log(`普通命令匹配到多个控制单元，返回所有单元:`, results);
    return results;
  }
  
  // 阶段3：设备组和控制单元都匹配不上
  const suggestions = await generateSuggestions();
  return [{ 
    action: 'NULL', 
    device: '', 
    slot: null, 
    unitType: null, 
    error: '没有这个设备或指令不明确，请重新输入指令',
    suggestions: suggestions
  }];
}

/**
 * 处理多设备指令
 */
async function processMultiDeviceCommand(originalText, action) {
  console.log(`处理多设备指令：${originalText}`);
  
  // 使用分隔符分割指令
  const separators = ['和', '与', '、', '，', '以及', '还有'];
  let parts = [originalText];
  
  for (const separator of separators) {
    const newParts = [];
    for (const part of parts) {
      newParts.push(...part.split(separator));
    }
    parts = newParts;
  }
  
  // 移除空字符串和动作词，提取设备名称
  const deviceNames = parts.map(part => {
    let cleaned = part.trim();
    // 移除动作词
    cleaned = cleaned.replace(/^(打开|关闭|开|关)/, '').trim();
    return cleaned;
  }).filter(name => name.length > 0);
  
  console.log(`提取到的设备名称:`, deviceNames);
  
  // 收集所有匹配的设备单元
  const results = [];
  const processedUnits = new Set(); // 避免重复处理
  
  for (const deviceName of deviceNames) {
    // 对于每个设备名称，执行单设备匹配逻辑
    const deviceResults = await matchSingleDevice(deviceName, action);
    
    for (const result of deviceResults) {
      // 避免重复
      const key = result.device + result.slot;
      if (!processedUnits.has(key)) {
        processedUnits.add(key);
        results.push(result);
      }
    }
  }
  
  // 如果没有找到任何设备
  if (results.length === 0) {
    const suggestions = await generateSuggestions();
    return [{ 
      action: 'NULL', 
      device: '', 
      slot: null, 
      unitType: null, 
      error: '没有这个设备或指令不明确，请重新输入指令',
      suggestions: suggestions
    }];
  }
  
  console.log(`多设备指令处理结果:`, results);
  return results;
}

/**
 * 匹配单个设备（辅助函数）
 */
async function matchSingleDevice(deviceName, action) {
  const results = [];
  
  // 先匹配设备组
  let matchedGroups = [];
  
  for (const [groupName, config] of Object.entries(cachedDevices)) {
    const displayName = config.displayName || groupName;
    
    if (deviceName.includes(displayName) || displayName.includes(deviceName)) {
      matchedGroups.push({
        groupName: groupName,
        displayName: displayName,
        config: config
      });
    }
  }
  
  if (matchedGroups.length > 0) {
    // 返回所有匹配设备组的单元
    for (const group of matchedGroups) {
      for (const unit of group.config.units) {
        results.push({
          action: action,
          device: group.displayName,
          slot: unit.id,
          unitType: unit.type || 'control'
        });
      }
    }
    return results;
  }
  
  // 设备组匹配不上，尝试匹配控制单元
  for (const [groupName, config] of Object.entries(cachedDevices)) {
    for (const unit of config.units) {
      if (unit.name && (deviceName.includes(unit.name) || unit.name.includes(deviceName))) {
        results.push({
          action: action,
          device: config.displayName || groupName,
          slot: unit.id,
          unitType: unit.type || 'control'
        });
      }
    }
  }
  
  return results;
}




/**
 * 从文本中提取动作（打开/关闭）
 */
function extractAction(text) {
  if (text.includes('打开') || text.includes('开')) {
    return 'ON';
  } else if (text.includes('关闭') || text.includes('关')) {
    return 'OFF';
  }
  return 'NULL';
}


/**
 * 备用解析逻辑（当JSON解析失败时使用）
 */
async function fallbackParse(text, isOnlyCommand) {
  console.log(`备用解析，是否"只"命令: ${isOnlyCommand}`);
  
  // 如果是"只"命令，使用专门的处理逻辑
  if (isOnlyCommand) {
    return await processOnlyCommand(text, []);
  }
  
  // 非"只"命令的备用解析
  // 阶段1：先匹配设备组
  const results = [];
  const actionMatch = extractActionFromText(text);
  
  if (actionMatch) {
    const normalizedAction = actionMatch === '打开' ? 'ON' : 'OFF';
    
    // 阶段1：先匹配设备组名称
    let matchedGroups = [];
    
    for (const [groupName, config] of Object.entries(cachedDevices)) {
      if (text.includes(config.displayName) || text.includes(groupName)) {
        matchedGroups.push(config);
      }
    }
    
    // 阶段2：如果匹配到多个设备组或没有匹配，尝试匹配单元名称
    if (matchedGroups.length === 0) {
      // 没有匹配到设备组，尝试匹配单元名称
      for (const [groupName, config] of Object.entries(cachedDevices)) {
        for (const unit of config.units) {
          if (unit.name && text.includes(unit.name)) {
            results.push({
              action: normalizedAction,
              device: config.displayName || groupName,
              slot: unit.id,
              unitType: unit.type || 'control'
            });
          }
        }
      }
    } else if (matchedGroups.length === 1) {
      // 匹配到一个设备组，返回该组的所有单元
      const config = matchedGroups[0];
      for (const unit of config.units) {
        results.push({
          action: normalizedAction,
          device: config.displayName || config.name,
          slot: unit.id,
          unitType: unit.type || 'control'
        });
      }
    } else {
      // 匹配到多个设备组，尝试结合位置信息
      const locationMatch = text.match(/(客厅|卧室|厨房|书房|阳台|主卧|次卧|卫生间|浴室|走廊|餐厅)/);
      const location = locationMatch ? locationMatch[1] : '';
      
      if (location) {
        // 根据位置筛选设备组
        const filteredGroups = matchedGroups.filter(config => 
          config.location && (config.location.includes(location) || location.includes(config.location))
        );
        
        if (filteredGroups.length > 0) {
          for (const config of filteredGroups) {
            for (const unit of config.units) {
              results.push({
                action: normalizedAction,
                device: config.displayName || config.name,
                slot: unit.id,
                unitType: unit.type || 'control'
              });
            }
          }
        } else {
          // 位置筛选后没有结果，返回所有匹配的设备组
          for (const config of matchedGroups) {
            for (const unit of config.units) {
              results.push({
                action: normalizedAction,
                device: config.displayName || config.name,
                slot: unit.id,
                unitType: unit.type || 'control'
              });
            }
          }
        }
      } else {
        // 没有位置信息，返回所有匹配的设备组
        for (const config of matchedGroups) {
          for (const unit of config.units) {
            results.push({
              action: normalizedAction,
              device: config.displayName || config.name,
              slot: unit.id,
              unitType: unit.type || 'control'
            });
          }
        }
      }
    }
  }
  
  // 如果没有找到匹配结果
  if (results.length === 0) {
    const suggestions = await generateSuggestions();
    return [{
      action: 'NULL',
      device: '',
      slot: null,
      unitType: 'control',
      error: '没有这个设备或指令不明确，请重新输入指令',
      suggestions: suggestions
    }];
  }
  
  console.log(`备用解析结果:`, results);
  return results;
}

/**
 * 从文本中提取动作（打开/关闭）- 备用函数
 */
function extractActionFromText(text) {
  if (text.includes('打开')) {
    return '打开';
  } else if (text.includes('关闭')) {
    return '关闭';
  } else if (text.includes('开')) {
    return '打开';
  } else if (text.includes('关')) {
    return '关闭';
  }
  return null;
}


/**
 * 生成可能的指令建议
 */
async function generateSuggestions() {
  const suggestions = [];
  
  // 收集所有可用的设备单元和设备组
  const unitNames = new Set();
  const groupNames = new Set();
  const locations = new Set();
  
  for (const [groupName, config] of Object.entries(cachedDevices)) {
    groupNames.add(config.displayName || groupName);
    if (config.location) {
      locations.add(config.location);
    }
    
    for (const unit of config.units) {
      if (unit.name) {
        unitNames.add(unit.name);
      }
    }
  }
  
  // 生成建议指令
  const actions = ['打开', '关闭'];
  
  // 生成不含"只"的建议（先设备组，再单元）
  for (const action of actions) {
    for (const groupName of groupNames) {
      suggestions.push(`${action}${groupName}`);
    }
  }
  
  // 生成含"只"的建议
  for (const action of actions) {
    for (const unitName of unitNames) {
      suggestions.push(`只${action}${unitName}`);
    }
  }
  
  // 生成带位置的建议
  for (const action of actions) {
    for (const location of locations) {
      for (const groupName of groupNames) {
        suggestions.push(`${action}${location}${groupName}`);
      }
      for (const unitName of unitNames) {
        suggestions.push(`只${action}${location}${unitName}`);
      }
    }
  }
  
  // 随机选择一些建议返回
  const shuffled = suggestions.sort(() => 0.5 - Math.random());
  return shuffled.slice(0, 5); // 返回最多5个建议
}




// 处理单个AI解析结果，查找实际的单元ID
function processSingleAiResult(aiResult) {
  console.log(`处理AI解析结果:`, aiResult);
  
  // 优先使用AI返回的slot字段，如果无法找到对应的单元ID，则通过其他方式查找
  if (aiResult.slot) {
    // 如果AI返回的slot是有效的单元ID，直接使用
    for (const [groupName, config] of Object.entries(cachedDevices)) {
      const foundUnit = config.units.find(unit => unit.id === aiResult.slot);
      if (foundUnit) {
        console.log(`AI返回的slot ${aiResult.slot} 是有效的单元ID，直接使用`);
        return {
          ...aiResult,
          slot: aiResult.slot,
          actualSlotId: aiResult.slot,
          deviceGroup: groupName,
          unitType: foundUnit.type || 'control'
        };
      }
    }
    
    // 如果AI返回的slot不是有效的单元ID，尝试通过设备名和单元名查找
    for (const [groupName, config] of Object.entries(cachedDevices)) {
      if (aiResult.device && (config.displayName === aiResult.device || groupName === aiResult.device)) {
        // 在该设备组中查找匹配的单元
        const matchingUnit = config.units.find(unit => 
          unit.name === aiResult.slot || unit.id === aiResult.slot
        );
        if (matchingUnit) {
          console.log(`在设备组 ${groupName} 中找到匹配的单元 ${matchingUnit.id}`);
          return {
            ...aiResult,
            actualSlotId: matchingUnit.id,
            deviceGroup: groupName,
            unitType: matchingUnit.type || 'control'
          };
        }
      }
    }
  }
  
  // 如果仍然找不到，尝试在所有设备中查找
  for (const [groupName, config] of Object.entries(cachedDevices)) {
    for (const unit of config.units) {
      if (unit.name === aiResult.device || unit.id === aiResult.device) {
        console.log(`在所有设备中找到匹配的单元 ${unit.id}`);
        return {
          ...aiResult,
          actualSlotId: unit.id,
          deviceGroup: groupName,
          unitType: unit.type || 'control'
        };
      }
    }
  }
  
  // 如果都找不到，返回原结果
  return {
    ...aiResult,
    actualSlotId: aiResult.slot,
    deviceGroup: null,
    unitType: aiResult.unitType || 'control'
  };
}

// 处理单个AI解析结果，执行实际操作
async function processAiResult(parsed, originalText = '') {
  const processed = processSingleAiResult(parsed);
  
  // 检查原始文本是否包含"只"字
  const containsOnly = originalText && originalText.includes('只');
  
  // 根据动作和设备类型执行相应的操作
  if (processed.action === 'ON' || processed.action === 'OFF') {
    if (processed.actualSlotId) {
      // 查找设备信息
      const devices = await dataManager.getDevices();
      let deviceInfo = null;
      
      for (const [groupName, config] of Object.entries(devices)) {
        for (const unit of config.units) {
          if (unit.id === processed.actualSlotId) {
            deviceInfo = {
              deviceType: groupName,
              deviceId: config.id || groupName,
              category: 'relay',
              unitId: unit.id,
              unitType: unit.type || 'control'
            };
            break;
          }
        }
        if (deviceInfo) break;
      }
      
      if (deviceInfo) {
        if (deviceInfo.unitType === 'control') {
            const success = sendMqttControl(processed.action, deviceInfo.unitId);
            if (success) {
              // 更新数据库中的状态
              await dataManager.updateDeviceStatus(processed.actualSlotId, processed.action);
              return {
                code: 200,
                msg: `AI解析：通过内网TCP执行${processed.action}成功，目标：插槽 ${processed.actualSlotId} (type: ${deviceInfo.unitType})`,
                success: true,
                slot: processed.actualSlotId,
                unitType: deviceInfo.unitType
              };
            } else {
              return {
                code: 500,
                msg: 'MQTT TCP连接失败，指令未发送',
                success: false,
                slot: processed.actualSlotId,
                unitType: deviceInfo.unitType
              };
            }
          } else if (deviceInfo.unitType === 'state') {
            // 状态类型：通过WebSocket获取，这里只是模拟返回状态查询
            return {
              code: 200,
              msg: `AI解析：状态查询${processed.action}成功，目标：插槽 ${processed.actualSlotId} (type: ${deviceInfo.unitType})`,
              success: true,
              slot: processed.actualSlotId,
              unitType: deviceInfo.unitType
            };
          } else if (deviceInfo.unitType === 'text') {
            // 文本类型：返回文本值
            return {
              code: 200,
              msg: `AI解析：文本值查询${processed.action}成功，目标：插槽 ${processed.actualSlotId} (type: ${deviceInfo.unitType})`,
              success: true,
              slot: processed.actualSlotId,
              unitType: deviceInfo.unitType
            };
          } else if (deviceInfo.unitType === 'data') {
            // 数据类型：返回数值
            return {
              code: 200,
              msg: `AI解析：数值查询${processed.action}成功，目标：插槽 ${processed.actualSlotId} (type: ${deviceInfo.unitType})`,
              success: true,
              slot: processed.actualSlotId,
              unitType: deviceInfo.unitType
            };
          } else {
            return {
              code: 400,
              msg: `无效的单元类型: ${deviceInfo.unitType}`,
              success: false,
              slot: processed.actualSlotId,
              unitType: deviceInfo.unitType
            };
          }
      } else {
        return {
          code: 400,
          msg: '无法找到对应设备',
          success: false,
          slot: processed.actualSlotId,
          unitType: processed.unitType
        };
      }
    } else {
      // 如果没有指定具体插槽但指定了设备组，检查是否需要特殊处理
      if (processed.device) {
        const devices = await dataManager.getDevices();
        let matchedUnits = [];
        
        // 遍历设备组寻找匹配的单元
        for (const [groupName, config] of Object.entries(devices)) {
          // 检查设备组名或显示名是否匹配
          if (groupName === processed.device || config.displayName === processed.device) {
            // 检查设备组名称和单元名称是否相同或相近
            let hasSimilarNames = false;
            for (const unit of config.units) {
              if (unit.name && (unit.name.includes(config.displayName || groupName) || 
                  (config.displayName || groupName).includes(unit.name))) {
                hasSimilarNames = true;
                break;
              }
            }
            
            // 如果设备组名称和单元名称相同或相近，且指令包含"只"字
            if (hasSimilarNames && containsOnly) {
              // 提取"只"字后面的关键词
              const match = originalText.match(/只[\s\u4e00-\u9fa5]*([\u4e00-\u9fa5]+)/);
              if (match && match[1]) {
                const keyword = match[1];
                // 只匹配名称中包含关键词的单元
                for (const unit of config.units) {
                  if (unit.name && unit.name.includes(keyword)) {
                    matchedUnits.push({
                      deviceType: groupName,
                      deviceId: config.id || groupName,
                      category: 'relay',
                      unitId: unit.id,
                      unitType: unit.type || 'control',
                      unitName: unit.name
                    });
                  }
                }
              }
            } else {
              // 否则控制整个设备组的所有单元
              for (const unit of config.units) {
                matchedUnits.push({
                  deviceType: groupName,
                  deviceId: config.id || groupName,
                  category: 'relay',
                  unitId: unit.id,
                  unitType: unit.type || 'control',
                  unitName: unit.name
                });
              }
            }
            
            break; // 找到设备组后退出外层循环
          }
        }
        
        // 如果找到了匹配的单元，执行批量操作
        if (matchedUnits.length > 0) {
          const results = [];
          
          for (const unit of matchedUnits) {
            const success = sendMqttControl(processed.action, unit.unitId);
            if (success) {
              // 更新数据库中的状态
              await dataManager.updateDeviceStatus(unit.unitId, processed.action);
              results.push({
                code: 200,
                msg: `AI解析：通过内网TCP执行${processed.action}成功，目标：插槽 ${unit.unitId} (type: ${unit.unitType})`,
                success: true,
                slot: unit.unitId,
                unitType: unit.unitType
              });
            } else {
              results.push({
                code: 500,
                msg: 'MQTT TCP连接失败，指令未发送',
                success: false,
                slot: unit.unitId,
                unitType: unit.unitType
              });
            }
          }
          
          return {
            code: 200,
            msg: `AI批量操作完成，共处理 ${matchedUnits.length} 个设备单元`,
            success: true,
            details: results
          };
        }
      }
      
      return {
        code: 400,
        msg: '未指定插槽',
        success: false,
        slot: null,
        unitType: processed.unitType
      };
    }
  } else {
    return {
      code: 400,
      msg: '无法解析指令',
      success: false,
      slot: processed.actualSlotId,
      unitType: processed.unitType
    };
  }
}


// 获取设备列表用于AI解析
function getDeviceListForAI() {
  const deviceList = [];
  for (const [groupName, config] of Object.entries(cachedDevices)) {
    deviceList.push(config.displayName || config.name);
    for (const unit of config.units) {
      deviceList.push(unit.name || unit.id);
    }
  }
  return [...new Set(deviceList)]; // 去重
}

// 接口：AI自然语言控制（基础版）
app.post('/api/ai', async (req, res) => {
  try {
    const { text } = req.body;

    // 输入验证
    if (!text || typeof text !== 'string') {
      return res.status(400).json({ 
        code: 400, 
        cmd: 'NULL', 
        slot: null,
        unitType: null,
        msg: '无效的输入，需要文本内容' 
      });
    }

    console.log(`==================== AI指令请求 ====================`);
    console.log(`用户输入（原始指令）: ${text}`);
    console.log(`-----------------------------------------------------`);

    const { cmd, slot, unitType } = await parseCommand(text);
    if (cmd === 'ON' || cmd === 'OFF') {
      // 通过TCP/MQTT发送控制指令
      if (slot) {
        // 查找设备信息
        const devices = await dataManager.getDevices();
        let deviceInfo = null;
        
        for (const [groupName, config] of Object.entries(devices)) {
          for (const unit of config.units) {
            if (unit.id === slot) {
              deviceInfo = {
                deviceType: groupName,
                deviceId: config.id || groupName,
                category: 'relay',
                unitId: unit.id,
                unitType: unit.type || 'control' // 默认为control类型
              };
              break;
            }
          }
          if (deviceInfo) break;
        }
        
        if (deviceInfo) {
          if (deviceInfo.unitType === 'control') {
            const success = sendMqttControl(cmd, deviceInfo.unitId);
            if (success) {
              res.json({ code: 200, cmd, slot, unitType: deviceInfo.unitType, msg: `AI解析：通过内网TCP执行${cmd}成功，目标：插槽 ${slot} (type: ${deviceInfo.unitType})` });
            } else {
              res.status(500).json({ 
                code: 500, 
                cmd: 'NULL', 
                slot: null,
                unitType: deviceInfo.unitType,
                msg: 'MQTT TCP连接失败，指令未发送' 
              });
            }
          } else if (deviceInfo.unitType === 'state') {
            // 状态类型：通过WebSocket获取，这里只是模拟返回状态查询
            res.json({ code: 200, cmd, slot, unitType: deviceInfo.unitType, msg: `AI解析：状态查询${cmd}成功，目标：插槽 ${slot} (type: ${deviceInfo.unitType})` });
          } else if (deviceInfo.unitType === 'text') {
            // 文本类型：返回文本值
            res.json({ code: 200, cmd, slot, unitType: deviceInfo.unitType, msg: `AI解析：文本值查询${cmd}成功，目标：插槽 ${slot} (type: ${deviceInfo.unitType})` });
          } else if (deviceInfo.unitType === 'data') {
            // 数据类型：返回数值
            res.json({ code: 200, cmd, slot, unitType: deviceInfo.unitType, msg: `AI解析：数值查询${cmd}成功，目标：插槽 ${slot} (type: ${deviceInfo.unitType})` });
          } else {
            res.status(400).json({ code: 400, cmd: 'NULL', slot: null, unitType: deviceInfo.unitType, msg: '无效的单元类型' });
          }
        } else {
          res.status(400).json({ code: 400, cmd: 'NULL', slot: null, unitType: null, msg: '无法找到对应设备' });
        }
      } else {
        res.status(400).json({ code: 400, cmd: 'NULL', slot: null, unitType: null, msg: '未指定插槽' });
      }
    } else {
      res.status(400).json({ code: 400, cmd: 'NULL', slot: null, unitType: null, msg: '无法解析指令' });
    }
  } catch (error) {
    console.error('AI接口错误:', error);
    res.status(500).json({ 
      code: 500, 
      cmd: 'NULL', 
      slot: null,
      unitType: null,
      msg: '服务器内部错误' 
    });
  }
});

/**
 * AI定时指令解析函数
 * 支持的指令格式：
 * - "晚上九点打开扫地机" - 一次性定时任务
 * - "每天早上8:00打开电视" - 每日定时任务
 * - "每周二早上8:00打开电视" - 每周定时任务
 */
async function parseScheduleCommand(text) {
  // 输入验证
  if (!text || typeof text !== 'string' || text.trim().length === 0) {
    console.log('AI定时指令解析失败：输入为空');
    return null;
  }

  try {
    // 创建详细的设备信息，用于AI理解
    const deviceInfo = [];
    
    for (const [groupName, config] of Object.entries(cachedDevices)) {
      const unitsInfo = config.units.map(unit => 
        `"${unit.name || unit.id}": "${unit.id}" (type: ${unit.type || 'control'}, location: ${config.location || 'unknown'})`
      ).join(', ');
      
      deviceInfo.push(
        `设备组名: "${groupName}", ` +
        `设备显示名: "${config.displayName || config.name}", ` +
        `位置: "${config.location || ''}", ` +
        `控制单元: {${unitsInfo}}`
      );
    }
    
    const deviceDetails = deviceInfo.join('; ');

    const prompt = `
你是智能家居定时任务指令解析器，需要从用户输入中提取定时任务信息。

当前系统设备配置:
${deviceDetails}

时间格式说明:
- 时间可以是具体时刻如"晚上九点"、"早上8:00"、"10点"、"21:00"
- 日期可以是"明天"、"周一"到"周日"、"每周一"到"每周日"
- 周期性间隔可以是"每隔X分钟"、"每X小时"、"每隔X小时"等格式
- 时段说明：早上/早晨/上午指6:00-12:00，下午指12:00-18:00，晚上指18:00-24:00
- 时间转换规则：早上9点=09:00，上午10点=10:00，下午3点=15:00，晚上8点=20:00
- 严格按照中文时间习惯转换：
  - 上午/早上/早晨 时间保持不变（如"上午九点" → "09:00"）
  - 下午时间需要加12（如"下午三点" → "15:00"，"下午四点" → "16:00"）
      ✅ 正确示例：
        下午一点 → 13:00 | 下午两点 → 14:00 | 下午三点 → 15:00 | 下午四点 → 16:00 | 下午五点 → 17:00
        晚上六点 → 18:00 | 晚上七点 → 19:00 | 晚上十二点 → 24:00（或00:00）
     ❌ 错误示例（禁止返回）：
        下午四点 → 14:00（错误！）| 下午五点 → 15:00（错误！）
  - 晚上/晚间 时间需要加12（如"晚上七点" → "19:00"）
- 时间格式统一使用24小时制：HH:MM格式（如"08:00", "15:30", "20:45"）
- 校验要求：
   - 生成time字段前，先核对：下午X点 = X+12，确认无误后再输出

输出格式（JSON）:
{
  "action": "打开|关闭",
  "device": "设备显示名",
  "slot": "设备单元ID",
  "unitType": "control|state|null",
  "time": "具体时间字符串（HH:MM格式，如09:00、14:30）",
  "recurring": "daily|weekly|once|interval",
  "weekday": "周一|周二|周三|周四|周五|周六|周日|null",
  "location": "设备位置|null",
  "interval": 周期间隔毫秒数（仅当recurring为interval时需要）
}

重要说明:
- 如果指令是"每天"或"每天早上/晚上"，recurring设为"daily"
- 如果指令是"每周X"，recurring设为"weekly"，并设置weekday为单个值（如"周一"）
- 如果指令是"每隔X分钟"或"每X小时"，recurring设为"interval"，time设为间隔描述（如"10分钟"），interval设为毫秒数
- 如果没有重复指示，recurring设为"once"
- daily任务的weekday字段必须设为null
- 严格按照JSON格式输出，不要包含任何解释文字

用户输入：${text.trim()}
    `.trim();

    const result = await llm.invoke(prompt);
    const response = result.content.trim();
    
    console.log(`AI定时解析原始响应: ${response}`);
    
    try {

      // 在 JSON.parse(response) 之前添加清理逻辑
      const cleanResponse = response
        .replace(/^```\s*json\s*/i, '')  // 移除开头的 ```json
        .replace(/\s*```\s*$/, '')        // 移除结尾的 ```
        .replace(/\/\/.*$/gm, '')         // 移除单行注释 //...
        .replace(/\s+/g, ' ')              // 将多个空白字符替换为单个空格
        .trim();


        const parsed = JSON.parse(cleanResponse);

      
      // 验证和标准化结果
      const validated = {
        action: parsed.action || '',
        device: parsed.device || '',
        slot: parsed.slot || null,
        unitType: parsed.unitType || 'control',
        time: parsed.time || '',
        recurring: parsed.recurring || 'once',
  weekday: parsed.weekday || null,
  location: parsed.location || null,
  interval: parsed.interval || null
};

      
      // 如果slot不是有效的单元ID，尝试通过设备名查找
      if (validated.slot && !isValidSlotId(validated.slot)) {
        const foundSlot = findSlotByName(validated.slot, validated.device);
        if (foundSlot) {
          validated.slot = foundSlot;
        } else {
          validated.slot = null;
        }
      }
      
      return validated;
    } catch (e) {
      console.error('无法从AI响应中提取有效的JSON，使用备用解析...');
      return fallbackParseSchedule(text);
    }
  } catch (error) {
    console.error('AI定时指令解析错误:', error);
    return null;
  }
}

/**
 * 验证slot是否是有效的单元ID
 */
function isValidSlotId(slot) {
  for (const [groupName, config] of Object.entries(cachedDevices)) {
    if (config.units && config.units.some(unit => unit.id === slot)) {
      return true;
    }
  }
  return false;
}

/**
 * 通过设备名和单元名查找单元ID
 */
function findSlotByName(unitName, deviceName) {
  for (const [groupName, config] of Object.entries(cachedDevices)) {
    const displayName = config.displayName || groupName;
    
    // 检查设备名是否匹配
    if (!deviceName || displayName === deviceName || groupName === deviceName) {
      for (const unit of config.units) {
        if (unit.name === unitName || unit.id.includes(unitName)) {
          return unit.id;
        }
      }
    }
  }
  return null;
}

/**
 * 备用定时指令解析逻辑
 */
function fallbackParseSchedule(text) {
  console.log(`备用定时解析: ${text}`);
  
  // 提取动作
  const action = text.includes('打开') || text.includes('开') ? '打开' : 
                 (text.includes('关闭') || text.includes('关') ? '关闭' : '');
  
  if (!action) {
    return null;
  }
  
  // 提取重复周期
  let recurring = 'once';
  let weekday = null;
  let interval = null;
  
  // 优先检查周期性间隔（每隔X分钟/小时）
  const intervalMatch = text.match(/(每(隔)?\s*)(\d+)\s*(分钟|分|小时|时)/);
  if (intervalMatch) {
    recurring = 'interval';
    const value = parseInt(intervalMatch[3]);
    const unit = intervalMatch[4];
    if (unit === '分钟' || unit === '分') {
      interval = value * 60 * 1000;  // 转换为毫秒
    } else if (unit === '小时' || unit === '时') {
      interval = value * 60 * 60 * 1000;  // 转换为毫秒
    }
  } else if (text.includes('每周')) {
    recurring = 'weekly';
    // 提取周几
    const weekdayMatch = text.match(/每周(一|二|三|四|五|六|日)/);
    if (weekdayMatch) {
      weekday = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][
        ['一', '二', '三', '四', '五', '六', '日'].indexOf(weekdayMatch[1])
      ];
    }
  } else if (text.includes('每天') || text.includes('天天')) {
    recurring = 'daily';
  }
  
  // 提取时间
  let timeStr = '';
  
  // 匹配时间格式：
  // 1. 晚上九点、早上8点、下午3点
  // 2. 9点、8:00、21:00
  // 3. 九点、八点半
  // 4. 上午10点、早晨8点
  
  const timePatterns = [
    /(早上|早晨|上午|下午|晚上)?\s*(\d{1,2})(?::(\d{2}))?\s*点(半)?/,
    /(早上|早晨|上午|下午|晚上)?\s*(\d{1,2}):(\d{2})/,
    /([零一二三四五六七八九十]+)点(半)?/
  ];
  
  for (const pattern of timePatterns) {
    const match = text.match(pattern);
    if (match) {
      // 确定匹配的是哪个模式
      let period, hourStr, minuteStr, isHalf;
      
      if (pattern === timePatterns[2]) {
        // 中文数字模式
        hourStr = match[1];
        isHalf = match[2] === '半';
        period = null;
      } else {
        period = match[1];
        hourStr = match[2];
        minuteStr = match[3];
        isHalf = match[4] === '半';
      }
      
      // 解析小时
      let hour = parseInt(hourStr);
      if (isNaN(hour)) {
        // 尝试中文数字转换
        hour = chineseToNumber(hourStr);
      }
      
      // 解析分钟
      let minute = parseInt(minuteStr) || (isHalf ? 30 : 0);
      
      // 根据时段调整小时
      if (period === '晚上' && hour < 12) hour += 12;
      if (period === '下午' && hour < 12) hour += 12;
      // 早上、早晨、上午保持原样（上午10点就是10:00）
      
      // 验证时间有效性
      if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
        timeStr = `${hour.toString().padStart(2, '0')}:${minute.toString().padStart(2, '0')}`;
      }
      break;
    }
  }
  
  if (!timeStr) {
    console.log('无法解析时间');
    return null;
  }
  
  // 提取设备名
  let deviceName = '';
  let unitName = '';
  
  // 移除时间和动作词，提取设备名
  let remaining = text;
  remaining = remaining.replace(/(打开|关闭|开|关)/g, '');
  remaining = remaining.replace(/(每天|天天|每周[一二三四五六日])/g, '');
  remaining = remaining.replace(/(早上|上午|下午|晚上)/g, '');
  remaining = remaining.replace(/\d{1,2}:\d{2}/g, '');
  remaining = remaining.replace(/\d{1,2}\s*点(半)?/g, '');
  remaining = remaining.replace(/[零一二三四五六七八九十]+点(半)?/g, '');
  remaining = remaining.trim();
  
  // 在设备列表中查找匹配
  for (const [groupName, config] of Object.entries(cachedDevices)) {
    const displayName = config.displayName || groupName;
    
    if (remaining.includes(displayName) || displayName.includes(remaining)) {
      deviceName = displayName;
      // 如果设备组只有一个控制单元，直接使用
      const controlUnits = config.units.filter(u => u.type === 'control' || u.type === undefined);
      if (controlUnits.length === 1) {
        unitName = controlUnits[0].id;
      } else {
        // 尝试匹配单元名
        for (const unit of controlUnits) {
          if (remaining.includes(unit.name)) {
            unitName = unit.id;
            break;
          }
        }
      }
      break;
    }
  }
  
  if (!deviceName) {
    console.log('无法解析设备名');
    return null;
  }
  
  // 对于interval类型，设置time为间隔描述
  const finalTimeStr = recurring === 'interval' && interval ? 
    `${Math.round(interval / 60000)}分钟` : timeStr;
  
  return {
    action,
    device: deviceName,
    slot: unitName || null,
    unitType: 'control',
    time: finalTimeStr,
    recurring,
    weekday,
    location: null,
    interval
  };
}

/**
 * 将中文数字转换为阿拉伯数字
 */
function chineseToNumber(chineseNum) {
  const chineseDigits = {'零':0, '一':1, '二':2, '三':3, '四':4, '五':5, '六':6, '七':7, '八':8, '九':9, '十':10};
  let result = 0;
  let temp = 0;
  
  for (const char of chineseNum) {
    if (char === '十') {
      result += temp * 10 || 10;
      temp = 0;
    } else {
      temp = chineseDigits[char] || 0;
    }
  }
  result += temp;
  return result;
}

/**
 * 将时间字符串转换为完整的日期时间
 * 支持格式：
 * 1. 绝对时间格式："14:30", "9:00"
 * 2. 相对时间格式："20分钟", "1小时", "30秒"
 */
function convertTimeToDateTime(timeStr, recurring, weekday) {
  const now = new Date();
  let targetDate = new Date(now);
  
  // 首先尝试解析相对时间格式（如 "20分钟", "1小时"）
  const relativeMatch = timeStr.match(/(\d+)\s*(分钟|分|小时|时|秒)/);
  if (relativeMatch && recurring === 'once') {
    // 相对时间格式：从现在开始计算
    const value = parseInt(relativeMatch[1]);
    const unit = relativeMatch[2];
    
    let milliseconds = 0;
    if (unit === '分钟' || unit === '分') {
      milliseconds = value * 60 * 1000;
    } else if (unit === '小时' || unit === '时') {
      milliseconds = value * 60 * 60 * 1000;
    } else if (unit === '秒') {
      milliseconds = value * 1000;
    }
    
    targetDate.setTime(now.getTime() + milliseconds);
    return targetDate;
  }
  
  // 解析绝对时间格式（如 "14:30"）
  const [hour, minute] = timeStr.split(':').map(Number);
  
  // 验证时间是否有效
  if (isNaN(hour) || (minute !== undefined && isNaN(minute))) {
    console.error(`[时间解析] 无效的时间格式: ${timeStr}`);
    return null;  // 返回null表示解析失败
  }
  
  const finalMinute = minute !== undefined ? minute : 0;
  
  if (recurring === 'once') {
    // 一次性任务：今天或明天
    targetDate.setHours(hour, finalMinute, 0, 0);
    
    // 如果时间已过，设置为明天
    if (targetDate.getTime() < now.getTime()) {
      targetDate.setDate(targetDate.getDate() + 1);
    }
  } else if (recurring === 'daily') {
    // 每日任务
    targetDate.setHours(hour, finalMinute, 0, 0);
    
    // 如果今天的时间已过，设置为明天
    if (targetDate.getTime() < now.getTime()) {
      targetDate.setDate(targetDate.getDate() + 1);
    }
  } else if (recurring === 'weekly') {
    // 每周任务
    const weekdayOrder = {'周一':1, '周二':2, '周三':3, '周四':4, '周五':5, '周六':6, '周日':0};
    const targetDay = weekdayOrder[weekday];
    const currentDay = now.getDay();
    
    // 计算到目标日期的天数
    let daysToAdd = targetDay - currentDay;
    if (daysToAdd <= 0) daysToAdd += 7;
    
    targetDate.setDate(now.getDate() + daysToAdd);
    targetDate.setHours(hour, finalMinute, 0, 0);
  }
  
  return targetDate;
}

function formatLocalDateTime(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  const hour = String(date.getHours()).padStart(2, '0');
  const minute = String(date.getMinutes()).padStart(2, '0');
  const second = String(date.getSeconds()).padStart(2, '0');
  return `${year}-${month}-${day}T${hour}:${minute}:${second}`;
}

function parseRecurringTimePoint(timeValue) {
  if (!timeValue) return null;
  // 首先尝试按 Date 解析（处理 ISO Z 或带偏移的字符串，得到本地时刻）
  const parsed = new Date(timeValue);
  if (!isNaN(parsed.getTime())) return parsed;

  // 回退：从简单的 T/H:M 模式提取小时分钟，构造本地时间点
  const str = String(timeValue);
  const match = str.match(/T(\d{2}):(\d{2})/);
  if (match) {
    const now = new Date();
    const point = new Date(now);
    point.setHours(Number(match[1]), Number(match[2]), 0, 0);
    return point;
  }
  return null;
}

// 接口：AI定时指令（自然语言创建定时任务）
app.post('/api/ai-schedule', async (req, res) => {
  try {
    const { text } = req.body;

    // 输入验证
    if (!text || typeof text !== 'string') {
      return res.status(400).json({ 
        code: 400, 
        msg: '无效的输入，需要文本内容' 
      });
    }

    console.log(`==================== AI定时指令请求 ====================`);
    console.log(`用户输入（原始指令）: ${text}`);
    console.log(`-----------------------------------------------------`);

    // 解析定时指令
    const parsed = await parseScheduleCommand(text);
    
    if (!parsed) {
      return res.status(400).json({ 
        code: 400, 
        msg: '无法解析定时指令' 
      });
    }

    console.log(`AI定时解析结果:`, parsed);

    // 验证解析结果
    if (!parsed.action || !parsed.device || !parsed.time) {
      return res.status(400).json({ 
        code: 400, 
        msg: '解析结果不完整，请检查指令格式' 
      });
    }

    // 如果没有slot，尝试查找设备的第一个控制单元
    let slot = parsed.slot;
    if (!slot) {
      for (const [groupName, config] of Object.entries(cachedDevices)) {
        const displayName = config.displayName || groupName;
        if (displayName === parsed.device || groupName === parsed.device) {
          const controlUnits = config.units.filter(u => u.type === 'control' || u.type === undefined);
          if (controlUnits.length > 0) {
            slot = controlUnits[0].id;
            parsed.slot = slot;
            break;
          }
        }
      }
    }

    if (!slot) {
      return res.status(400).json({ 
        code: 400, 
        msg: '无法找到对应的设备控制单元' 
      });
    }

    // 获取设备显示名用于任务名称
    let deviceDisplayName = parsed.device;
    for (const [groupName, config] of Object.entries(cachedDevices)) {
      const displayName = config.displayName || groupName;
      if (displayName === parsed.device || groupName === parsed.device) {
        deviceDisplayName = displayName;
        break;
      }
    }

    // 转换动作
    const cmd = parsed.action === '打开' ? 'ON' : 'OFF';

    // 根据重复类型创建定时任务
    const taskId = `${slot}-${Date.now()}`;
    let responseMsg = '';

    if (parsed.recurring === 'once') {
      // 一次性任务
      const targetDate = convertTimeToDateTime(parsed.time, 'once', null);
      
      // 检查时间解析是否成功
      if (!targetDate || isNaN(targetDate.getTime())) {
        return res.status(400).json({ 
          code: 400, 
          msg: `无法解析时间格式: ${parsed.time}` 
        });
      }
      
      const delay = targetDate.getTime() - Date.now();

      if (delay <= 0) {
        return res.status(400).json({ 
          code: 400, 
          msg: '定时时间必须在未来' 
        });
      }

      const timer = setTimeout(() => {
        console.log(`[定时任务] 执行 ${taskId}: ${slot} -> ${cmd}`);
        sendMqttControl(cmd, slot);
        delete scheduledTasks[taskId];
        saveSchedules(getSchedulesForSave());
        console.log(`[定时任务] 已从列表中移除已执行的一次性任务: ${taskId}`);
      }, delay);

      // 保存任务信息（与原有定时任务格式保持一致）
      scheduledTasks[taskId] = {
        timer,
        id: taskId,
        name: `${parsed.time} ${parsed.action}${deviceDisplayName}`,
        unitId: slot,
        cmd,
        time: targetDate.toISOString(),
        enabled: true,
        createdAt: new Date().toISOString()
      };

      // 保存到文件
      saveSchedules(getSchedulesForSave());
      console.log(`[AI定时任务] 一次性任务已保存到文件: ${taskId}`);
      responseMsg = `一次性定时任务已设置：${targetDate.toLocaleString('zh-CN')} ${parsed.action}${deviceDisplayName}`;

    } else if (parsed.recurring === 'daily') {
      // 每日任务
      const targetDate = convertTimeToDateTime(parsed.time, 'daily', null);
      const initialDelay = targetDate.getTime() - Date.now();

      const startTimer = setTimeout(() => {
        console.log(`[日任务] 执行 ${taskId}: ${slot} -> ${cmd}`);
        sendMqttControl(cmd, slot);

        const timer = setInterval(() => {
          console.log(`[日任务] 执行 ${taskId}: ${slot} -> ${cmd}`);
          sendMqttControl(cmd, slot);
        }, 86400000); // 24小时

        scheduledTasks[taskId].timer = timer;
        console.log(`[日任务] 已启动循环定时器: ${taskId}`);
      }, initialDelay);

      // 保存任务信息（与原有定时任务格式保持一致）
      scheduledTasks[taskId] = {
        timer: startTimer,
        id: taskId,
        name: `每天${parsed.time} ${parsed.action}${deviceDisplayName}`,
        unitId: slot,
        cmd,
        interval: 86400000,
        time: targetDate.toISOString(),
        enabled: true,
        createdAt: new Date().toISOString(),
        recurring: true
      };

      // 保存到文件
      saveSchedules(getSchedulesForSave());
      console.log(`[AI定时任务] 每日任务已保存到文件: ${taskId}`);
      responseMsg = `每日定时任务已设置：每天${parsed.time} ${parsed.action}${deviceDisplayName}`;

    } else if (parsed.recurring === 'weekly') {
      // 每周任务
      const targetDate = convertTimeToDateTime(parsed.time, 'weekly', parsed.weekday);
      const initialDelay = targetDate.getTime() - Date.now();

      const startTimer = setTimeout(() => {
        console.log(`[周任务] 执行 ${taskId}: ${slot} -> ${cmd}`);
        sendMqttControl(cmd, slot);

        const timer = setInterval(() => {
          console.log(`[周任务] 执行 ${taskId}: ${slot} -> ${cmd}`);
          sendMqttControl(cmd, slot);
        }, 604800000); // 7天

        scheduledTasks[taskId].timer = timer;
        console.log(`[周任务] 已启动循环定时器: ${taskId}`);
      }, initialDelay);

      // 计算周几对应的日期
      const weekdayIndex = ['日', '一', '二', '三', '四', '五', '六'].indexOf(parsed.weekday.slice(-1));
      const dateDay = weekdayIndex === 0 ? 7 : weekdayIndex;

      // 保存任务信息（与原有定时任务格式保持一致）
      scheduledTasks[taskId] = {
        timer: startTimer,
        id: taskId,
        name: `每周${parsed.weekday}${parsed.time} ${parsed.action}${deviceDisplayName}`,
        unitId: slot,
        cmd,
        interval: 604800000,
        time: targetDate.toISOString(),
        enabled: true,
        createdAt: new Date().toISOString(),
        recurring: true
      };

      // 保存到文件
      saveSchedules(getSchedulesForSave());
      console.log(`[AI定时任务] 每周任务已保存到文件: ${taskId}`);
      responseMsg = `每周定时任务已设置：每周${parsed.weekday}${parsed.time} ${parsed.action}${deviceDisplayName}`;

    } else if (parsed.recurring === 'interval') {
      // 周期性间隔任务（每隔X分钟/小时）
      let intervalMs = parsed.interval;
      
      // 如果AI返回的interval为空，尝试从time字段解析
      if (!intervalMs && parsed.time) {
        const timeMatch = parsed.time.match(/(\d+)\s*(分钟|分|小时|时)/);
        if (timeMatch) {
          const value = parseInt(timeMatch[1]);
          const unit = timeMatch[2];
          if (unit === '分钟' || unit === '分') {
            intervalMs = value * 60 * 1000;
          } else if (unit === '小时' || unit === '时') {
            intervalMs = value * 60 * 60 * 1000;
          }
        }
      }
      
        // 从用户原始输入中提取正确的时间间隔（用于验证AI返回值）
        const text = req.body.text;
        const userIntervalMatch = text.match(/(每(隔)?\s*)(\d+)\s*(分钟|分|小时|时)/);
  
        // 验证并修正AI返回的interval值
        if (userIntervalMatch) {
          const userValue = parseInt(userIntervalMatch[3]);
          const userUnit = userIntervalMatch[4];
          let expectedInterval = 0; 
    
        if (userUnit === '分钟' || userUnit === '分') {
          expectedInterval = userValue * 60 * 1000;
        } else if (userUnit === '小时' || userUnit === '时') {
          expectedInterval = userValue * 60 * 60 * 1000;
        } 
    
        // 如果AI返回的值与用户预期不符（差异超过1分钟），使用用户输入的值
          if (expectedInterval > 0 && (!intervalMs || Math.abs(intervalMs - expectedInterval) > 60000)) {
            console.log(`[AI定时任务] 修正interval值: AI返回${intervalMs || 'null'} -> 用户输入${expectedInterval} (${userValue}${userUnit})`); 
      intervalMs = expectedInterval;
    }
  }


      // 验证间隔时间
      if (!intervalMs || intervalMs < 60000) { // 最小1分钟
        return res.status(400).json({ 
          code: 400, 
          msg: '无效的间隔时间，最小为1分钟' 
        });
      }

      // 创建周期性任务，立即开始执行
      const timer = setInterval(() => {
        console.log(`[周期任务] 执行 ${taskId}: ${slot} -> ${cmd}`);
        sendMqttControl(cmd, slot);
      }, intervalMs);

      // 立即执行一次
      console.log(`[周期任务] 首次执行 ${taskId}: ${slot} -> ${cmd}`);
      sendMqttControl(cmd, slot);

      // 保存任务信息
      const minutes = Math.round(intervalMs / 60000);
      scheduledTasks[taskId] = {
        timer,
        id: taskId,
        name: `每${minutes}分钟 ${parsed.action}${deviceDisplayName}`,
        unitId: slot,
        cmd,
        interval: intervalMs,
        time: new Date().toISOString(),
        enabled: true,
        createdAt: new Date().toISOString(),
        recurring: true
      };

      // 保存到文件
      saveSchedules(getSchedulesForSave());
      console.log(`[AI定时任务] 周期任务已保存到文件: ${taskId}`);
      responseMsg = `周期定时任务已设置：每${minutes}分钟 ${parsed.action}${deviceDisplayName}`;
    }

    console.log(`[AI定时任务] ${responseMsg}`);

    // 获取当前任务列表用于确认
    const currentTasks = {};
    for (const [tid, task] of Object.entries(scheduledTasks)) {
      const { timer, ...taskData } = task;
      currentTasks[tid] = taskData;
    }
    console.log(`[AI定时任务] 当前任务列表:`, Object.keys(currentTasks));

    res.json({
      code: 200,
      msg: responseMsg,
      taskId,
      schedule: {
        action: parsed.action,
        device: deviceDisplayName,
        slot,
        time: parsed.time,
        recurring: parsed.recurring,
        weekday: parsed.weekday
      },
      taskList: currentTasks
    });

  } catch (error) {
    console.error('AI定时接口错误:', error);
    res.status(500).json({ 
      code: 500, 
      msg: '服务器内部错误' 
    });
  }
});

// 接口：AI自然语言控制（高级版）
app.post('/api/ai-advanced', async (req, res) => {
  try {
    const { text } = req.body;

    // 输入验证
    if (!text || typeof text !== 'string') {
      return res.status(400).json({ 
        code: 400, 
        msg: '无效的输入，需要文本内容' 
      });
    }

    console.log(`==================== AI高级指令请求 ====================`);
    console.log(`用户输入（原始指令）: ${text}`);
    console.log(`-----------------------------------------------------`);

    // 调用AI解析，返回多个结果
    const parsedResults = await parseAdvancedCommand(text);
    console.log(`AI解析完成，找到 ${parsedResults.length} 个目标`);

    const results = [];

    for (const parsed of parsedResults) {
      const result = await processAiResult(parsed, text);  // 传递原始文本
      // 如果是批量操作（slot为null时会返回details），展开details
      if (result.details && Array.isArray(result.details)) {
        results.push(...result.details);
        delete result.details;
      } else {
        results.push(result);
      }
    }

    res.json({ 
      code: 200, 
      msg: `AI高级解析完成，处理了 ${results.length} 个设备`,
      details: results
    });
  } catch (error) {
    console.error('AI高级接口错误:', error);
    res.status(500).json({ 
      code: 500, 
      msg: '服务器内部错误' 
    });
  }
});

// 启动服务
const server = app.listen(WEB_PORT, '0.0.0.0', async () => {
  console.log(`控制服务启动：http://${SERVER_IP}:${WEB_PORT}`);
  console.log(`内网MQTT TCP服务器: ${MQTT_INTERNAL_SERVER}`);
  console.log(`控制主题: ${MQTT_TOPIC_PREFIX}/设备单元ID/${CTRL_TOPIC_SUFFIX} (内网TCP下发)`);
  console.log(`状态主题: ${MQTT_TOPIC_PREFIX}/设备单元ID/${STATE_TOPIC_SUFFIX} (外网WebSocket获取)`);
  console.log(`基础AI接口：POST /api/ai`);
  
  // 初始化定时任务（从文件加载）
  initSchedules();
  console.log(`高级AI接口：POST /api/ai-advanced`);
  
  // 在服务器启动时加载初始设备配置
  await loadInitialDevices();
  
  // 开始监听文件变化
  watchDevicesFile();
});

// 优雅关闭
process.on('SIGTERM', () => {
  console.log('收到关闭信号，正在关闭控制服务...');
  server.close(() => {
    console.log('控制服务已关闭');
    if (client.connected) {
      client.end(true, () => {
        console.log('MQTT TCP控制客户端已关闭');
      });
    } else {
      console.log('MQTT TCP控制客户端未建立或已关闭');
    }
  });
});