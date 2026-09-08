// server-auto.js - 场景自动化模块
//
// 功能：根据一个或多个设备单元的状态/值组合（条件之间 AND/OR 链式组合），
//       触发对一个或多个设备单元的动作（control ON/OFF、设置 data/text 值、执行其他场景）。
//
// 挂载方式（与 OTA/ota-routes.js 相同的双服务挂载模式）：
//   配置服务 server-config.js(6001) : app.use(require('./server-auto').router)
//   控制服务 server-control-tcp.js(6002): const auto = require('./server-auto'); app.use(auto.router); auto.startEngine();
//
// 说明：
//   - CRUD 路由在两个服务均可用，数据存储于 data/scenes.json（原子写入，两进程共享同一文件）
//   - 自动评估引擎（MQTT订阅状态 + 边沿触发 + 动作执行）仅在控制服务进程通过 startEngine() 启动，
//     避免两个进程重复触发；配置服务进程仅提供 CRUD 和手动触发（手动触发时按需懒加载MQTT连接发布指令）
//
// 数据模型（data/scenes.json）：
//   {
//     "scenes": {
//       "scene_<时间戳>_<随机>": {
//         "id": "scene_...",
//         "name": "场景名称",
//         "enabled": true,
//         "conditions": [
//           { "id":"c1", "unitId":"...", "unitName":"温度传感器", "unitType":"state",
//             "operator":">=", "value":"28", "logic":"AND" }   // logic=与上一条件的关系，首条忽略
//         ],
//         "actions": [
//           { "id":"a1", "type":"control", "unitId":"...", "unitName":"风扇", "value":"ON" }
//           // type: control(ON/OFF) | data(数值设置) | text(文本设置) | scene(执行其他场景, value=场景ID)
//         ],
//         "createdAt":"ISO时间", "updatedAt":"ISO时间", "lastTriggered":null
//       }
//     },
//     "lastUpdated": "ISO时间"
//   }

const express = require('express');
const mqtt = require('mqtt');
const fs = require('fs');
const fsp = fs.promises;
const path = require('path');

require('dotenv').config({ path: path.join(__dirname, '.env') });

// ========== 配置 ==========
const DATA_DIR = path.join(__dirname, 'data');
const SCENES_FILE = path.join(DATA_DIR, 'scenes.json');
const DEVICES_FILE = path.join(__dirname, 'devices.json');
const TRIGGER_LOG_FILE = path.join(DATA_DIR, 'scene-trigger-log.json');
const MAX_TRIGGER_LOG = 200; // 最多保留200条触发记录
const MQTT_INTERNAL_SERVER = process.env.MQTT_INTERNAL_SERVER || 'mqtt://192.168.1.40:1883';
const MQTT_TOPIC_PREFIX = process.env.MQTT_TOPIC_PREFIX || 'iot/device';
const MQTT_USERNAME = process.env.MQTT_USERNAME;
const MQTT_PASSWORD = process.env.MQTT_PASSWORD;

const NUMERIC_OPERATORS = ['>', '>=', '<', '<=', '==', '!='];
const MAX_SCENE_DEPTH = 5; // 场景嵌套执行最大深度（防止循环引用）

// ========== 触发日志存储 ==========
async function readTriggerLog() {
  try {
    const raw = await fsp.readFile(TRIGGER_LOG_FILE, 'utf8');
    const data = JSON.parse(raw);
    if (!data.logs) data.logs = [];
    return data;
  } catch (err) {
    if (err.code === 'ENOENT') {
      await fsp.mkdir(DATA_DIR, { recursive: true });
      const init = { logs: [], lastUpdated: new Date().toISOString() };
      await fsp.writeFile(TRIGGER_LOG_FILE, JSON.stringify(init, null, 2), 'utf8');
      return init;
    }
    throw err;
  }
}

async function appendTriggerLog(entry) {
  try {
    const data = await readTriggerLog();
    data.logs.unshift(entry);
    if (data.logs.length > MAX_TRIGGER_LOG) data.logs = data.logs.slice(0, MAX_TRIGGER_LOG);
    data.lastUpdated = new Date().toISOString();
    await fsp.mkdir(DATA_DIR, { recursive: true });
    const tmp = TRIGGER_LOG_FILE + '.tmp';
    await fsp.writeFile(tmp, JSON.stringify(data, null, 2), 'utf8');
    await fsp.rename(tmp, TRIGGER_LOG_FILE);
  } catch (e) {
    console.error('[场景自动化] 写入触发日志失败:', e.message);
  }
}
// ========== 场景存储 ==========
async function readScenesData() {
  try {
    const raw = await fsp.readFile(SCENES_FILE, 'utf8');
    const data = JSON.parse(raw);
    if (!data.scenes) data.scenes = {};
    return data;
  } catch (err) {
    if (err.code === 'ENOENT') {
      await fsp.mkdir(DATA_DIR, { recursive: true });
      const init = { scenes: {}, lastUpdated: new Date().toISOString() };
      await fsp.writeFile(SCENES_FILE, JSON.stringify(init, null, 2), 'utf8');
      return init;
    }
    throw err;
  }
}

async function writeScenesData(data) {
  data.lastUpdated = new Date().toISOString();
  await fsp.mkdir(DATA_DIR, { recursive: true });
  const tmp = SCENES_FILE + '.tmp';
  await fsp.writeFile(tmp, JSON.stringify(data, null, 2), 'utf8');
  await fsp.rename(tmp, SCENES_FILE);
}

async function readDevices() {
  try {
    const raw = await fsp.readFile(DEVICES_FILE, 'utf8');
    return JSON.parse(raw);
  } catch (err) {
    return {};
  }
}

// 查找设备单元及其所属设备组
function findUnit(devices, unitId) {
  for (const [groupName, group] of Object.entries(devices)) {
    if (groupName === 'lastUpdated' || !group || !Array.isArray(group.units)) continue;
    const unit = group.units.find(u => u.id === unitId);
    if (unit) return { groupName, group, unit };
  }
  return null;
}

// 从 devices.json 读取单元当前状态（引擎启动初期 stateCache 未填充时的兜底值）
function getDeviceStatus(unitId) {
  try {
    const devices = JSON.parse(fs.readFileSync(DEVICES_FILE, 'utf8'));
    const found = findUnit(devices, unitId);
    return found ? found.unit.status : undefined;
  } catch {
    return undefined;
  }
}

// ========== MQTT 客户端（懒加载，进程内单例） ==========
let mqttClient = null;
function getMqttClient() {
  if (!mqttClient) {
    mqttClient = mqtt.connect(MQTT_INTERNAL_SERVER, {
      username: MQTT_USERNAME,
      password: MQTT_PASSWORD,
      reconnectPeriod: 5000,
      clientId: 'auto_' + Math.random().toString(16).slice(2, 10)
    });
    mqttClient.on('connect', () => {
      console.log('[场景自动化] MQTT客户端连接成功');
    });
    mqttClient.on('error', (e) => {
      console.error('[场景自动化] MQTT错误:', e.message);
    });
    mqttClient.on('reconnect', () => {
      console.log('[场景自动化] MQTT正在重连...');
    });
  }
  return mqttClient;
}

// 判断单元所属设备组是否 lowPower（控制指令是否需要 retained）
async function isLowPowerUnit(unitId) {
  const devices = await readDevices();
  const found = findUnit(devices, unitId);
  return !!(found && found.group.lowPower === true);
}

// 发布控制指令 ON/OFF
async function publishControl(unitId, cmd) {
  const client = getMqttClient();
  const retain = await isLowPowerUnit(unitId);
  const topic = `${MQTT_TOPIC_PREFIX}/${unitId}/control`;
  client.publish(topic, String(cmd).toUpperCase(), { qos: 1, retain }, (err) => {
    if (err) console.error(`[场景自动化] 控制指令发布失败 ${topic}:`, err.message);
    else console.log(`[场景自动化] 控制指令 ${cmd} -> ${topic}${retain ? ' [retained]' : ''}`);
  });
}

// 发布数值参数设置（datasetting，retained）
function publishDataSetting(unitId, value) {
  const client = getMqttClient();
  const topic = `${MQTT_TOPIC_PREFIX}/${unitId}/datasetting`;
  client.publish(topic, String(value), { qos: 1, retain: true }, (err) => {
    if (err) console.error(`[场景自动化] 数值设置发布失败 ${topic}:`, err.message);
    else console.log(`[场景自动化] 数值设置 ${value} -> ${topic} [retained]`);
  });
}

// 发布文本参数设置（textsetting，retained）
function publishTextSetting(unitId, value) {
  const client = getMqttClient();
  const topic = `${MQTT_TOPIC_PREFIX}/${unitId}/textsetting`;
  client.publish(topic, String(value), { qos: 1, retain: true }, (err) => {
    if (err) console.error(`[场景自动化] 文本设置发布失败 ${topic}:`, err.message);
    else console.log(`[场景自动化] 文本设置 ${value} -> ${topic} [retained]`);
  });
}

// ========== 条件评估 ==========
function toNumber(v) {
  if (v === undefined || v === null) return null;
  const n = parseFloat(String(v).trim());
  return isNaN(n) ? null : n;
}

// 评估单个条件
function evalCondition(cond, valueProvider) {
  if (!cond || !cond.unitId) return false;
  const raw = valueProvider(cond.unitId);
  if (raw === undefined || raw === null || String(raw) === 'OFFLINE') return false;

  const op = cond.operator || '==';
  if (['>', '>=', '<', '<='].includes(op)) {
    const a = toNumber(raw);
    const b = toNumber(cond.value);
    if (a === null || b === null) return false;
    if (op === '>') return a > b;
    if (op === '>=') return a >= b;
    if (op === '<') return a < b;
    return a <= b;
  }
  // == / != 按字符串比较（ON/OFF 等大小写不敏感）
  const a = String(raw).trim().toUpperCase();
  const b = String(cond.value === undefined ? '' : cond.value).trim().toUpperCase();
  return op === '!=' ? a !== b : a === b;
}

// 评估单个条件并返回快照信息（用于触发日志）
function evalConditionWithSnapshot(cond, valueProvider) {
  if (!cond || !cond.unitId) return { satisfied: false, snapshot: null };
  const raw = valueProvider(cond.unitId);
  const currentValue = raw === undefined || raw === null ? '--' : String(raw);

  const op = cond.operator || '==';
  let satisfied = false;
  if (raw === undefined || raw === null || String(raw) === 'OFFLINE') {
    satisfied = false;
  } else if (['>', '>=', '<', '<='].includes(op)) {
    const a = toNumber(raw);
    const b = toNumber(cond.value);
    if (a === null || b === null) satisfied = false;
    else if (op === '>') satisfied = a > b;
    else if (op === '>=') satisfied = a >= b;
    else if (op === '<') satisfied = a < b;
    else satisfied = a <= b;
  } else {
    const a = String(raw).trim().toUpperCase();
    const b = String(cond.value === undefined ? '' : cond.value).trim().toUpperCase();
    satisfied = op === '!=' ? a !== b : a === b;
  }

  return {
    satisfied,
    snapshot: {
      unitId: cond.unitId,
      unitName: cond.unitName || '',
      currentValue,
      operator: op,
      conditionValue: String(cond.value === undefined || cond.value === null ? '' : cond.value),
      satisfied
    }
  };
}

// 完整评估场景并返回条件快照列表
function evalSceneConditionsWithSnapshot(scene, valueProvider) {
  const conds = Array.isArray(scene.conditions) ? scene.conditions : [];
  const snapshots = [];
  if (conds.length === 0) return { satisfied: false, snapshots };
  let result = false;
  for (let i = 0; i < conds.length; i++) {
    const { satisfied, snapshot } = evalConditionWithSnapshot(conds[i], valueProvider);
    if (snapshot) {
      snapshot.logic = i === 0 ? '--' : (String(conds[i].logic || 'AND').toUpperCase() === 'OR' ? 'OR' : 'AND');
      snapshots.push(snapshot);
    }
    if (i === 0) {
      result = satisfied;
    } else {
      const logic = String(conds[i].logic || 'AND').toUpperCase() === 'OR' ? 'OR' : 'AND';
      result = logic === 'OR' ? (result || satisfied) : (result && satisfied);
    }
  }
  return { satisfied: result, snapshots };
}

// 评估整个场景：条件按链式 logic(AND/OR) 从左到右组合
function evalSceneConditions(scene, valueProvider) {
  const conds = Array.isArray(scene.conditions) ? scene.conditions : [];
  if (conds.length === 0) return false;
  let result = evalCondition(conds[0], valueProvider);
  for (let i = 1; i < conds.length; i++) {
    const r = evalCondition(conds[i], valueProvider);
    const logic = String(conds[i].logic || 'AND').toUpperCase() === 'OR' ? 'OR' : 'AND';
    result = logic === 'OR' ? (result || r) : (result && r);
  }
  return result;
}

// ========== 动作执行 ==========
async function executeScene(sceneId, ctx) {
  const context = ctx || { depth: 0, visited: new Set(), source: 'manual' };
  if (context.visited.has(sceneId)) {
    console.warn(`[场景自动化] 场景 ${sceneId} 存在循环引用，跳过`);
    return { ok: false, msg: '场景循环引用' };
  }
  if (context.depth > MAX_SCENE_DEPTH) {
    console.warn(`[场景自动化] 场景嵌套超过 ${MAX_SCENE_DEPTH} 层，停止执行`);
    return { ok: false, msg: '场景嵌套过深' };
  }
  context.visited.add(sceneId);

  const data = await readScenesData();
  const scene = data.scenes[sceneId];
  if (!scene) return { ok: false, msg: '场景不存在' };

  console.log(`[场景自动化] 执行场景"${scene.name}"(${sceneId})，来源: ${context.source}，动作数: ${(scene.actions || []).length}`);
    // 采集条件快照（自动触发时条件已评估，此处仅采集快照用于日志；手动触发时也采集）
  const { snapshots } = evalSceneConditionsWithSnapshot(scene, valueProvider);
  const results = [];

  for (const act of (scene.actions || [])) {
    try {
      if (act.type === 'control') {
        await publishControl(act.unitId, act.value);
        results.push({ action: 'control', unitId: act.unitId, value: act.value, ok: true });
      } else if (act.type === 'data') {
        publishDataSetting(act.unitId, act.value);
        results.push({ action: 'data', unitId: act.unitId, value: act.value, ok: true });
      } else if (act.type === 'text') {
        publishTextSetting(act.unitId, act.value);
        results.push({ action: 'text', unitId: act.unitId, value: act.value, ok: true });
      } else if (act.type === 'scene') {
        console.log(`[场景自动化] 场景"${scene.name}"调用子场景 ${act.value}`);
        const sub = await executeScene(act.value, {
          depth: context.depth + 1,
          visited: context.visited,
          source: 'scene:' + sceneId
        });
        results.push({ action: 'scene', sceneId: act.value, ok: sub.ok });
      }
    } catch (e) {
      console.error(`[场景自动化] 动作执行失败:`, e.message);
      results.push({ action: act.type, unitId: act.unitId, ok: false, error: e.message });
    }
  }

  // 更新最后触发时间
  try {
    const latest = await readScenesData();
    if (latest.scenes[sceneId]) {
      latest.scenes[sceneId].lastTriggered = new Date().toISOString();
      await writeScenesData(latest);
    }
  } catch (e) {
    console.error('[场景自动化] 更新触发时间失败:', e.message);
  }

    // 写入触发日志
  const logEntry = {
    id: 'log_' + Date.now() + '_' + Math.random().toString(16).slice(2, 6),
    sceneId,
    sceneName: scene.name,
    source: context.source,
    triggeredAt: new Date().toISOString(),
    conditionSnapshot: snapshots,
    actionResults: results,
    ok: results.every(r => r.ok !== false)
  };
  appendTriggerLog(logEntry).catch(e => console.error('[场景自动化] 记录触发日志失败:', e.message));

  return { ok: true, sceneName: scene.name, results };
}

// ========== 自动化引擎（仅控制服务进程启动） ==========
const stateCache = {};      // unitId -> 最新状态值（MQTT实时）
const prevSatisfied = {};  // sceneId -> 上一轮条件是否满足（边沿触发去抖）
let engineStarted = false;

function startEngine() {
  if (engineStarted) return;
  engineStarted = true;

  const client = getMqttClient();
  const stateTopic = `${MQTT_TOPIC_PREFIX}/+/state`;

  const doSubscribe = () => {
    client.subscribe(stateTopic, { qos: 1 }, (err) => {
      if (err) console.error('[场景自动化] 订阅状态主题失败:', err.message);
      else console.log(`[场景自动化] 引擎已启动，订阅状态主题: ${stateTopic}`);
    });
  };

  if (client.connected) doSubscribe();
  client.on('connect', doSubscribe);

  client.on('message', async (topic, message) => {
    const parts = topic.split('/');
    // iot/device/{unitId}/state
    if (parts.length !== 4 || parts[0] + '/' + parts[1] !== MQTT_TOPIC_PREFIX) return;
    if (parts[3] !== 'state') return;
    const unitId = parts[2];
    let val;
    try { val = JSON.parse(message.toString()); } catch { val = message.toString(); }
    stateCache[unitId] = val;
    await evaluateAll('state:' + unitId);
  });

  // 每30秒兜底评估一次（覆盖场景刚创建/启用时条件已满足的情况）
  setInterval(() => evaluateAll('periodic').catch(() => {}), 30000);
  console.log('[场景自动化] 引擎初始化完成（边沿触发 + 30秒兜底评估）');
}

// 值来源：优先MQTT实时缓存，其次 devices.json 中的状态
function valueProvider(unitId) {
  if (stateCache[unitId] !== undefined) return stateCache[unitId];
  return getDeviceStatus(unitId);
}

async function evaluateAll(source) {
  let data;
  try {
    data = await readScenesData();
  } catch (e) {
    console.error('[场景自动化] 读取场景失败:', e.message);
    return;
  }
  for (const [sceneId, scene] of Object.entries(data.scenes || {})) {
    if (scene.enabled === false) {
      prevSatisfied[sceneId] = false;
      continue;
    }
    let satisfied = false;
    try {
      satisfied = evalSceneConditions(scene, valueProvider);
    } catch (e) {
      console.error(`[场景自动化] 场景"${scene.name}"条件评估异常:`, e.message);
      continue;
    }
    const wasSatisfied = prevSatisfied[sceneId] === true;
    if (satisfied && !wasSatisfied) {
      console.log(`[场景自动化] 场景"${scene.name}"条件满足（${source}），触发动作`);
      executeScene(sceneId, { depth: 0, visited: new Set(), source: 'auto' }).catch(e =>
        console.error('[场景自动化] 自动执行失败:', e.message));
    }
    prevSatisfied[sceneId] = satisfied;
  }
}

// ========== Express 路由 ==========
const router = express.Router();

function genSceneId() {
  return 'scene_' + Date.now() + '_' + Math.random().toString(16).slice(2, 6);
}
function genItemId(prefix) {
  return prefix + '_' + Date.now().toString(36) + Math.random().toString(16).slice(2, 5);
}

// 规范化/校验场景内容
function sanitizeScene(body, existing) {
  const errors = [];
  const name = (body.name || '').toString().trim();
  if (!name) errors.push('场景名称不能为空');

  const conditions = Array.isArray(body.conditions) ? body.conditions.map((c, i) => ({
    id: c.id || genItemId('c'),
    unitId: String(c.unitId || ''),
    unitName: String(c.unitName || ''),
    unitType: String(c.unitType || ''),
    operator: NUMERIC_OPERATORS.includes(c.operator) ? c.operator : '==',
    value: c.value === undefined || c.value === null ? '' : String(c.value),
    logic: String(c.logic || 'AND').toUpperCase() === 'OR' ? 'OR' : 'AND'
  })).filter(c => c.unitId) : [];

  const actions = Array.isArray(body.actions) ? body.actions.map(a => ({
    id: a.id || genItemId('a'),
    type: ['control', 'data', 'text', 'scene'].includes(a.type) ? a.type : 'control',
    unitId: String(a.unitId || ''),
    unitName: String(a.unitName || ''),
    value: a.value === undefined || a.value === null ? '' : String(a.value)
  })).filter(a => (a.type === 'scene' ? a.value : a.unitId)) : [];

  if (conditions.length === 0) errors.push('至少需要一个条件');
  if (actions.length === 0) errors.push('至少需要一个执行动作');

  const description = (body.description || '').toString().trim();

  return {
    name,
    description,
    enabled: body.enabled === undefined ? (existing ? existing.enabled : true) : body.enabled !== false,
    conditions,
    actions,
    errors
  };
}

// 获取所有场景
router.get('/api/scenes', async (req, res) => {
  try {
    const data = await readScenesData();
    res.json({ code: 200, data: data.scenes, msg: '获取场景列表成功' });
  } catch (e) {
    res.status(500).json({ code: 500, data: null, msg: '获取场景列表失败: ' + e.message });
  }
});

// 获取单个场景
router.get('/api/scenes/:sceneId', async (req, res) => {
  try {
    const data = await readScenesData();
    const scene = data.scenes[req.params.sceneId];
    if (!scene) return res.status(404).json({ code: 404, data: null, msg: '场景不存在' });
    res.json({ code: 200, data: scene, msg: '获取场景成功' });
  } catch (e) {
    res.status(500).json({ code: 500, data: null, msg: '获取场景失败: ' + e.message });
  }
});

// 获取触发日志
router.get('/api/scenes/trigger-log', async (req, res) => {
  try {
    const data = await readTriggerLog();
    const limit = parseInt(req.query.limit) || 50;
    const logs = data.logs.slice(0, limit);
    res.json({ code: 200, data: { logs, total: data.logs.length }, msg: '获取触发日志成功' });
  } catch (e) {
    res.status(500).json({ code: 500, data: null, msg: '获取触发日志失败: ' + e.message });
  }
});

// 清空触发日志
router.delete('/api/scenes/trigger-log', async (req, res) => {
  try {
    await fsp.mkdir(DATA_DIR, { recursive: true });
    const init = { logs: [], lastUpdated: new Date().toISOString() };
    await fsp.writeFile(TRIGGER_LOG_FILE, JSON.stringify(init, null, 2), 'utf8');
    res.json({ code: 200, msg: '触发日志已清空' });
  } catch (e) {
    res.status(500).json({ code: 500, msg: '清空触发日志失败: ' + e.message });
  }
});

// 创建场景
router.post('/api/scenes', async (req, res) => {
  try {
    const s = sanitizeScene(req.body || {});
    if (s.errors.length) return res.status(400).json({ code: 400, msg: s.errors.join('；') });
    const data = await readScenesData();
    const id = genSceneId();
    const now = new Date().toISOString();
    data.scenes[id] = {
      id,
      name: s.name,
      description: s.description,
      enabled: s.enabled,
      conditions: s.conditions,
      actions: s.actions,
      createdAt: now,
      updatedAt: now,
      lastTriggered: null
    };
    await writeScenesData(data);
    // 重置引擎边沿状态，使新场景立即参与评估
    delete prevSatisfied[id];
    res.json({ code: 200, data: data.scenes[id], msg: '场景创建成功' });
  } catch (e) {
    res.status(500).json({ code: 500, msg: '创建场景失败: ' + e.message });
  }
});

// 修改场景
router.put('/api/scenes/:sceneId', async (req, res) => {
  try {
    const data = await readScenesData();
    const existing = data.scenes[req.params.sceneId];
    if (!existing) return res.status(404).json({ code: 404, msg: '场景不存在' });
    const s = sanitizeScene(req.body || {}, existing);
    if (s.errors.length) return res.status(400).json({ code: 400, msg: s.errors.join('；') });
    data.scenes[req.params.sceneId] = {
      ...existing,
      name: s.name,
      description: s.description,
      enabled: s.enabled,
      conditions: s.conditions,
      actions: s.actions,
      updatedAt: new Date().toISOString()
    };
    await writeScenesData(data);
    delete prevSatisfied[req.params.sceneId]; // 内容变更后重新评估
    res.json({ code: 200, data: data.scenes[req.params.sceneId], msg: '场景更新成功' });
  } catch (e) {
    res.status(500).json({ code: 500, msg: '更新场景失败: ' + e.message });
  }
});

// 删除场景
router.delete('/api/scenes/:sceneId', async (req, res) => {
  try {
    const data = await readScenesData();
    if (!data.scenes[req.params.sceneId]) return res.status(404).json({ code: 404, msg: '场景不存在' });
    delete data.scenes[req.params.sceneId];
    await writeScenesData(data);
    delete prevSatisfied[req.params.sceneId];
    res.json({ code: 200, msg: '场景删除成功' });
  } catch (e) {
    res.status(500).json({ code: 500, msg: '删除场景失败: ' + e.message });
  }
});

// 手动触发场景（场景列表页"执行"按钮）
router.post('/api/scenes/:sceneId/trigger', async (req, res) => {
  try {
    const data = await readScenesData();
    if (!data.scenes[req.params.sceneId]) return res.status(404).json({ code: 404, msg: '场景不存在' });
    const result = await executeScene(req.params.sceneId, { depth: 0, visited: new Set(), source: 'manual' });
    res.json({ code: result.ok ? 200 : 500, data: result, msg: result.ok ? '场景已触发' : result.msg });
  } catch (e) {
    res.status(500).json({ code: 500, msg: '场景触发失败: ' + e.message });
  }
});

module.exports = { router, startEngine, executeScene, evalSceneConditions };