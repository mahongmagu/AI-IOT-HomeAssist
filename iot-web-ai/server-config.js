// server-config.js - 设备配置管理服务
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const rateLimit = require('express-rate-limit');
const DataManager = require('./data-manager');
const fs = require('fs');

// 引入拼音转换库
const { pinyin } = require('pinyin');

// 日志记录函数
function logOperation(operation, details, success = true) {
  const timestamp = new Date().toISOString();
  const status = success ? 'SUCCESS' : 'FAILED';
  console.log(`[${timestamp}] ${operation} - ${status} - ${details}`);
}

// IP获取函数
function getClientIP(req) {
  return req.headers['x-forwarded-for'] ||
         req.headers['x-real-ip'] ||
         req.connection.remoteAddress ||
         req.socket.remoteAddress ||
         (req.connection.socket ? req.connection.socket.remoteAddress : null) ||
         'UNKNOWN';
}

// 位置信息处理函数：将中文转换为拼音
function processLocation(location) {
  if (!location || typeof location !== 'string') {
    return '0000';
  }
  
  // 检查是否包含中文字符
  const hasChinese = /.*[\u4e00-\u9fa5]+.*/.test(location);
  
  if (hasChinese) {
    try {
      // 转换为拼音并连接
      const pinyinResult = pinyin(location, {
        heteronym: false, // 不启用多音字
        segment: false,   // 不分词
        style: pinyin.STYLE_NORMAL // 普通风格，不带声调
      });
      
      // 展平数组并连接
      const processedLocation = pinyinResult.flat().join('').toLowerCase();
      
      // 确保不为空，如果是空则返回'0000'
      return processedLocation || '0000';
    } catch (e) {
      console.warn('Pinyin conversion failed:', e);
      // 如果转换失败，返回原始位置或'0000'
      return location.replace(/[^a-zA-Z0-9_-]/g, '_') || '0000';
    }
  } else {
    // 如果没有中文字符，只保留字母数字下划线连字符
    return location.replace(/[^a-zA-Z0-9_-]/g, '_') || '0000';
  }
}

const app = express();
const dataManager = new DataManager('./devices.json');

// 辅助函数：生成随机数字字符串
function generateRandomDigits(count) {
  let result = '';
  for (let i = 0; i < count; i++) {
    result += Math.floor(Math.random() * 10);
  }
  return result;
}

// 检查ID是否已存在
async function isGroupIdExists(groupId) {
  const devices = await dataManager.getDevices();
  return Object.keys(devices).some(key => devices[key].id === groupId);
}

async function isUnitIdExists(groupId, unitId) {
  const devices = await dataManager.getDevices();
  const group = devices[groupId];
  if (!group) return false;
  return group.units.some(unit => unit.id === unitId);
}

// 配置
const WEB_PORT = parseInt(process.env.CONFIG_SERVICE_PORT) || 3001;
const MQTT_SERVER = process.env.MQTT_SERVER || 'mqtt://192.168.6.40:1883';
const MQTT_TOPIC_PREFIX = process.env.MQTT_TOPIC_PREFIX || 'iot/device';

// 请求限制配置
const MAX_REQUEST_BODY_SIZE = process.env.MAX_REQUEST_BODY_SIZE || '10mb';
const CORS_ORIGINS = process.env.CORS_ORIGINS ? process.env.CORS_ORIGINS.split(',') : undefined;

// 速率限制中间件
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 400,
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

// 根路径直接返回 config.html
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'config.html'));
});

// 提供静态文件
app.use(express.static(path.join(__dirname, './')));

// 接口：获取所有设备配置
app.get('/api/devices', async (req, res) => {
  try {
    const clientIP = getClientIP(req);
    const devices = await dataManager.getDevices();
    const groupCount = Object.keys(devices).length;
    logOperation('GET_ALL_DEVICES', `IP: ${clientIP}, GroupsCount: ${groupCount}`);
    res.json({
      code: 200,
      data: devices,
      msg: '获取设备配置成功'
    });
  } catch (error) {
    console.error('获取设备配置失败:', error);
    res.status(500).json({
      code: 500,
      data: null,
      msg: '获取设备配置失败: ' + error.message
    });
  }
});

// 接口：获取单个设备组配置
app.get('/api/devices/:groupName', async (req, res) => {
  try {
    const { groupName } = req.params;
    const devices = await dataManager.getDevices();
    
    if (!devices[groupName]) {
      return res.status(404).json({
        code: 404,
        data: null,
        msg: `设备组 ${groupName} 不存在`
      });
    }
    
    res.json({
      code: 200,
      data: devices[groupName],
      msg: '获取设备组配置成功'
    });
  } catch (error) {
    console.error('获取设备组配置失败:', error);
    res.status(500).json({
      code: 500,
      data: null,
      msg: '获取设备组配置失败: ' + error.message
    });
  }
});

// 接口：创建设备组
app.post('/api/devices', async (req, res) => {
  try {
    const payload = req.body || {};
    let name = payload.name || payload.groupName || payload.deviceGroupName || payload.group_name;
    let displayName = payload.displayName || payload.display_name || payload.groupDisplayName || payload.deviceGroupDisplayName || name;
    let location = payload.location ?? payload.groupLocation ?? payload.group_location ?? null;
    let units = payload.units;

    if (!Array.isArray(units) && Array.isArray(payload.unitList)) {
      units = payload.unitList;
    }
    if (!Array.isArray(units) && Array.isArray(payload.items)) {
      units = payload.items;
    }

    const clientIP = getClientIP(req);
    
    // 输入验证
    if (!name || !displayName || !Array.isArray(units)) {
      logOperation('CREATE_DEVICE_GROUP', `IP: ${clientIP}, Name: ${name || 'unknown'}, Status: FAILED - Missing required parameters`);
      return res.status(400).json({
        code: 400,
        data: null,
        msg: '缺少必要参数：name, displayName, units'
      });
    }
    
    // 系统自动生成设备组ID，格式为：位置-设备组名称-8位动态唯一数字
    // 处理位置信息，如果是中文则转换为拼音
    let generatedId;
    let isUnique = false;
    const locationPrefix = processLocation(location);
    while (!isUnique) {
      generatedId = `${locationPrefix}-${name}-${generateRandomDigits(8)}`;
      isUnique = !(await isGroupIdExists(generatedId));
    }
    const id = generatedId;
    
        // 验证units数组中每个单元都有必需字段，系统自动生成单元ID
    for (const unit of units) {
      // 系统自动生成设备单元ID，格式为：设备组ID_设备单元名称拼音-4位唯一动态数字
      const unitName = unit.name || 'unit';
      let unitGeneratedId;
      let isUnitUnique = false;
      while (!isUnitUnique) {
        unitGeneratedId = `${id}_${processLocation(unitName)}-${generateRandomDigits(4)}`;
        isUnitUnique = !(await isUnitIdExists(name, unitGeneratedId));
      }
      unit.id = unitGeneratedId;
      
      if (!unit.name || !unit.status || !unit.type) {
        logOperation('CREATE_DEVICE_GROUP', `IP: ${clientIP}, Group: ${name}, Status: FAILED - Unit validation failed`);
        return res.status(400).json({
          code: 400,
          data: null,
          msg: '每个设备单元必须包含name, status, type字段（id由系统自动生成）'
        });
      }
      
      // 验证type字段只能是control、state、text或data
      if (unit.type !== 'control' && unit.type !== 'state' && unit.type !== 'text' && unit.type !== 'data') {
        logOperation('CREATE_DEVICE_GROUP', `IP: ${clientIP}, Group: ${name}, Status: FAILED - Invalid unit type`);
        return res.status(400).json({
          code: 400,
          data: null,
          msg: '设备单元type字段只能是control、state、text或data'
        });
      }
    }

    const devices = await dataManager.getDevices();
    
    // 检查设备组是否已存在
    if (devices[name]) {
      logOperation('CREATE_DEVICE_GROUP', `IP: ${clientIP}, Name: ${name}, Status: FAILED - Group already exists`);
      return res.status(400).json({
        code: 400,
        data: null,
        msg: `设备组 ${name} 已存在`
      });
    }
    
    // 创建新设备组
    const newDeviceGroup = {
      name,
      displayName,
      id,
      location,  // 添加位置字段
      units
    };
    
    // 如果没有提供位置，则设置为null
    if (location === undefined) {
      newDeviceGroup.location = null;
    }
    
    devices[name] = newDeviceGroup;
    
    await dataManager.saveDevices(devices);
    
    logOperation('CREATE_DEVICE_GROUP', `IP: ${clientIP}, Name: ${name}, DisplayName: ${displayName}, Location: ${location || 'null'}, UnitsCount: ${units.length}`);
    
    res.json({
      code: 200,
      data: newDeviceGroup,
      msg: '创建设备组成功'
    });
  } catch (error) {
    console.error('创建设备组失败:', error);
    res.status(500).json({
      code: 500,
      data: null,
      msg: '创建设备组失败: ' + error.message
    });
  }
});

// 接口：更新设备组
app.put('/api/devices/:groupName', async (req, res) => {
  try {
    const { groupName } = req.params;
    const payload = req.body || {};
    let name = payload.name || payload.groupName || payload.deviceGroupName || payload.group_name;
    let displayName = payload.displayName || payload.display_name || payload.groupDisplayName || payload.deviceGroupDisplayName || name;
    let location = payload.location ?? payload.groupLocation ?? payload.group_location ?? null;
    let units = payload.units;

    if (!Array.isArray(units) && Array.isArray(payload.unitList)) {
      units = payload.unitList;
    }
    if (!Array.isArray(units) && Array.isArray(payload.items)) {
      units = payload.items;
    }

    const clientIP = getClientIP(req);
    
    // 输入验证
    if (!name || !displayName || !Array.isArray(units)) {
      logOperation('UPDATE_DEVICE_GROUP', `IP: ${clientIP}, OriginalGroup: ${groupName}, Status: FAILED - Missing required parameters`);
      return res.status(400).json({
        code: 400,
        data: null,
        msg: '缺少必要参数：name, displayName, units'
      });
    }
    
    // 获取当前设备组以保留原始ID
    const devices = await dataManager.getDevices();
    const currentGroup = devices[groupName];
    if (!currentGroup) {
      logOperation('UPDATE_DEVICE_GROUP', `IP: ${clientIP}, Group: ${groupName}, Status: FAILED - Group not found`);
      return res.status(404).json({
        code: 404,
        data: null,
        msg: `设备组 ${groupName} 不存在`
      });
    }
    
    // 强制使用原始ID，不允许修改
    const preservedId = currentGroup.id;
    
    // 验证units数组中每个单元都有必需字段
    for (const unit of units) {
      if (!unit.id || !unit.name || !unit.status || !unit.type) {
        logOperation('UPDATE_DEVICE_GROUP', `IP: ${clientIP}, Group: ${groupName}, Status: FAILED - Unit validation failed`);
        return res.status(400).json({
          code: 400,
          data: null,
          msg: '每个设备单元必须包含id, name, status, type字段'
        });
      }
      
      // 验证type字段只能是control、state、text或data
      if (unit.type !== 'control' && unit.type !== 'state' && unit.type !== 'text' && unit.type !== 'data') {
        logOperation('UPDATE_DEVICE_UNIT', `IP: ${clientIP}, Group: ${groupName}, UnitID: ${unitId}, Status: FAILED - Invalid unit type`);
        return res.status(400).json({
          code: 400,
          data: null,
          msg: '设备单元type字段只能是control、state、text或data'
        });
      }
    }
    // 检查设备组是否存在
    if (!devices[groupName]) {
      logOperation('UPDATE_DEVICE_GROUP', `IP: ${clientIP}, Group: ${groupName}, Status: FAILED - Group not found`);
      return res.status(404).json({
        code: 404,
        data: null,
        msg: `设备组 ${groupName} 不存在`
      });
    }
    
    // 更新设备组，保留原始ID
    const updatedDeviceGroup = {
      name,
      displayName,
      id: preservedId,  // 强制保留原始ID
      location,  // 添加位置字段
      units
    };
    
    // 如果没有提供位置，则保留原有位置或设置为null
    if (location === undefined) {
      updatedDeviceGroup.location = currentGroup.location || null;
    }
    
    devices[name] = updatedDeviceGroup;
    
    // 如果组名发生变化，删除旧的组
    if (name !== groupName) {
      delete devices[groupName];
    }
    
    await dataManager.saveDevices(devices);
    
    logOperation('UPDATE_DEVICE_GROUP', `IP: ${clientIP}, OriginalGroup: ${groupName}, UpdatedGroup: ${name}, DisplayName: ${displayName}, Location: ${location || 'null'}, UnitsCount: ${units.length}`);
    
    res.json({
      code: 200,
      data: updatedDeviceGroup,
      msg: '更新设备组成功'
    });
  } catch (error) {
    console.error('更新设备组失败:', error);
    res.status(500).json({
      code: 500,
      data: null,
      msg: '更新设备组失败: ' + error.message
    });
  }
});

// 接口：删除设备组
app.delete('/api/devices/:groupName', async (req, res) => {
  try {
    const { groupName } = req.params;
    const clientIP = getClientIP(req);
    const devices = await dataManager.getDevices();
    
    // 检查设备组是否存在
    if (!devices[groupName]) {
      logOperation('DELETE_DEVICE_GROUP', `IP: ${clientIP}, Group: ${groupName}, Status: FAILED - Group not found`);
      return res.status(404).json({
        code: 404,
        data: null,
        msg: `设备组 ${groupName} 不存在`
      });
    }
    
    const deletedDeviceGroup = devices[groupName];
    delete devices[groupName];
    
    await dataManager.saveDevices(devices);
    
    logOperation('DELETE_DEVICE_GROUP', `IP: ${clientIP}, Group: ${groupName}, DisplayName: ${deletedDeviceGroup.displayName}, UnitsCount: ${deletedDeviceGroup.units.length}`);
    
    res.json({
      code: 200,
      data: deletedDeviceGroup,
      msg: '删除设备组成功'
    });
  } catch (error) {
    console.error('删除设备组失败:', error);
    res.status(500).json({
      code: 500,
      data: null,
      msg: '删除设备组失败: ' + error.message
    });
  }
});

// 接口：添加设备单元
app.post('/api/devices/:groupName/units', async (req, res) => {
  try {
    const { groupName } = req.params;
    const { name, status, type } = req.body;  // 不再需要id，由系统生成
    const clientIP = getClientIP(req);
    
    // 输入验证
    if (!name || !status || !type) {
      logOperation('ADD_DEVICE_UNIT', `IP: ${clientIP}, Group: ${groupName}, Status: FAILED - Missing required parameters`);
      return res.status(400).json({
        code: 400,
        data: null,
        msg: '缺少必要参数：name, status, type（id由系统自动生成）'
      });
    }
    
    // 验证type字段只能是control、state、text或data
    if (type !== 'control' && type !== 'state' && type !== 'text' && type !== 'data') {
      logOperation('ADD_DEVICE_UNIT', `IP: ${clientIP}, Group: ${groupName}, UnitName: ${name}, Status: FAILED - Invalid unit type`);
      return res.status(400).json({
        code: 400,
        data: null,
        msg: '设备单元type字段只能是control、state、text或data'
      });
    }
    
    const devices = await dataManager.getDevices();
    
    // 检查设备组是否存在
    if (!devices[groupName]) {
      logOperation('ADD_DEVICE_UNIT', `IP: ${clientIP}, Group: ${groupName}, UnitName: ${name}, Status: FAILED - Group not found`);
      return res.status(404).json({
        code: 404,
        data: null,
        msg: `设备组 ${groupName} 不存在`
      });
    }
    
    // 获取设备组信息以获得设备组ID
    const groupInfo = devices[groupName];
    const groupId = groupInfo.id || groupName;
    
    // 系统自动生成ID，格式为：设备组ID_设备单元名称拼音-4位唯一动态数字
    let generatedId;
    let isUnique = false;
    while (!isUnique) {
      generatedId = `${groupId}_${processLocation(name)}-${generateRandomDigits(4)}`;

      isUnique = !(await isUnitIdExists(groupName, generatedId));
    }
    const id = generatedId;
    
    // 检查单元ID是否已存在
    const existingUnit = devices[groupName].units.find(unit => unit.id === id);
    if (existingUnit) {
      logOperation('ADD_DEVICE_UNIT', `IP: ${clientIP}, Group: ${groupName}, UnitName: ${name}, UnitID: ${id}, Status: FAILED - Unit ID already exists`);
      return res.status(400).json({
        code: 400,
        data: null,
        msg: `设备单元ID ${id} 在组 ${groupName} 中已存在`
      });
    }
    
    // 添加新单元
    const newUnit = { id, name, status, type };
    devices[groupName].units.push(newUnit);
    
    await dataManager.saveDevices(devices);
    
    logOperation('ADD_DEVICE_UNIT', `IP: ${clientIP}, Group: ${groupName}, UnitName: ${name}, UnitID: ${id}, Type: ${type}, Status: ${status}`);
    
    res.json({
      code: 200,
      data: newUnit,
      msg: '添加设备单元成功'
    });
  } catch (error) {
    console.error('添加设备单元失败:', error);
    res.status(500).json({
      code: 500,
      data: null,
      msg: '添加设备单元失败: ' + error.message
    });
  }
});

// 接口：更新设备单元
app.put('/api/devices/:groupName/units/:unitId', async (req, res) => {
  try {
    const { groupName, unitId } = req.params;
    const { name, status, type } = req.body;
    const clientIP = getClientIP(req);
    
    // 输入验证
    if (name === undefined || status === undefined || type === undefined) {
      logOperation('UPDATE_DEVICE_UNIT', `IP: ${clientIP}, Group: ${groupName}, UnitID: ${unitId}, Status: FAILED - Missing required parameters`);
      return res.status(400).json({
        code: 400,
        data: null,
        msg: '缺少必要参数：name, status, type'
      });
    }
    
    // 验证type字段只能是control、state、text或data
    if (type !== 'control' && type !== 'state' && type !== 'text' && type !== 'data') {
      logOperation('UPDATE_DEVICE_UNIT', `IP: ${clientIP}, Group: ${groupName}, UnitID: ${unitId}, Status: FAILED - Invalid unit type`);
      return res.status(400).json({
        code: 400,
        data: null,
        msg: '设备单元type字段只能是control、state、text或data'
      });
    }
    
    const devices = await dataManager.getDevices();
    
    // 检查设备组是否存在
    if (!devices[groupName]) {
      logOperation('UPDATE_DEVICE_UNIT', `IP: ${clientIP}, Group: ${groupName}, UnitID: ${unitId}, Status: FAILED - Group not found`);
      return res.status(404).json({
        code: 404,
        data: null,
        msg: `设备组 ${groupName} 不存在`
      });
    }
    
    // 查找要更新的单元
    const unitIndex = devices[groupName].units.findIndex(unit => unit.id === unitId);
    if (unitIndex === -1) {
      logOperation('UPDATE_DEVICE_UNIT', `IP: ${clientIP}, Group: ${groupName}, UnitID: ${unitId}, Status: FAILED - Unit not found`);
      return res.status(404).json({
        code: 404,
        data: null,
        msg: `设备组 ${groupName} 中不存在单元ID ${unitId}`
      });
    }
    
    // 记录更新前的信息
    const originalUnit = {...devices[groupName].units[unitIndex]};
    
    // 更新单元
    devices[groupName].units[unitIndex] = {
      ...devices[groupName].units[unitIndex],
      name,
      status,
      type
    };
    
    await dataManager.saveDevices(devices);
    
    logOperation('UPDATE_DEVICE_UNIT', `IP: ${clientIP}, Group: ${groupName}, UnitID: ${unitId}, OriginalName: ${originalUnit.name}, NewName: ${name}, OriginalType: ${originalUnit.type}, NewType: ${type}, OriginalStatus: ${originalUnit.status}, NewStatus: ${status}`);
    
    res.json({
      code: 200,
      data: devices[groupName].units[unitIndex],
      msg: '更新设备单元成功'
    });
  } catch (error) {
    console.error('更新设备单元失败:', error);
    res.status(500).json({
      code: 500,
      data: null,
      msg: '更新设备单元失败: ' + error.message
    });
  }
});

// 接口：删除设备单元
app.delete('/api/devices/:groupName/units/:unitId', async (req, res) => {
  try {
    const { groupName, unitId } = req.params;
    const clientIP = getClientIP(req);
    const devices = await dataManager.getDevices();
    
    // 检查设备组是否存在
    if (!devices[groupName]) {
      logOperation('DELETE_DEVICE_UNIT', `IP: ${clientIP}, Group: ${groupName}, UnitID: ${unitId}, Status: FAILED - Group not found`);
      return res.status(404).json({
        code: 404,
        data: null,
        msg: `设备组 ${groupName} 不存在`
      });
    }
    
    // 查找要删除的单元
    const unitIndex = devices[groupName].units.findIndex(unit => unit.id === unitId);
    if (unitIndex === -1) {
      logOperation('DELETE_DEVICE_UNIT', `IP: ${clientIP}, Group: ${groupName}, UnitID: ${unitId}, Status: FAILED - Unit not found`);
      return res.status(404).json({
        code: 404,
        data: null,
        msg: `设备组 ${groupName} 中不存在单元ID ${unitId}`
      });
    }
    
    const deletedUnit = devices[groupName].units.splice(unitIndex, 1)[0];
    
    await dataManager.saveDevices(devices);
    
    logOperation('DELETE_DEVICE_UNIT', `IP: ${clientIP}, Group: ${groupName}, UnitID: ${unitId}, UnitName: ${deletedUnit.name}, Type: ${deletedUnit.type}, Status: ${deletedUnit.status}`);
    
    res.json({
      code: 200,
      data: deletedUnit,
      msg: '删除设备单元成功'
    });
  } catch (error) {
    console.error('删除设备单元失败:', error);
    res.status(500).json({
      code: 500,
      data: null,
      msg: '删除设备单元失败: ' + error.message
    });
  }
});

// 接口：获取特定设备组的所有设备单元
app.get('/api/devices/:groupName/units', async (req, res) => {
  try {
    const { groupName } = req.params;
    const devices = await dataManager.getDevices();
    
    if (!devices[groupName]) {
      return res.status(404).json({
        code: 404,
        data: null,
        msg: `设备组 ${groupName} 不存在`
      });
    }
    
    res.json({
      code: 200,
      data: devices[groupName].units,
      msg: '获取设备单元列表成功'
    });
  } catch (error) {
    console.error('获取设备单元列表失败:', error);
    res.status(500).json({
      code: 500,
      data: null,
      msg: '获取设备单元列表失败: ' + error.message
    });
  }
});

// 接口：获取特定设备单元
app.get('/api/devices/:groupName/units/:unitId', async (req, res) => {
  try {
    const { groupName, unitId } = req.params;
    const devices = await dataManager.getDevices();
    
    if (!devices[groupName]) {
      return res.status(404).json({
        code: 404,
        data: null,
        msg: `设备组 ${groupName} 不存在`
      });
    }
    
    const unit = devices[groupName].units.find(u => u.id === unitId);
    if (!unit) {
      return res.status(404).json({
        code: 404,
        data: null,
        msg: `设备组 ${groupName} 中不存在单元ID ${unitId}`
      });
    }
    
    res.json({
      code: 200,
      data: unit,
      msg: '获取设备单元成功'
    });
  } catch (error) {
    console.error('获取设备单元失败:', error);
    res.status(500).json({
      code: 500,
      data: null,
      msg: '获取设备单元失败: ' + error.message
    });
  }
});

// 接口：获取所有设备单元（跨组）
app.get('/api/all-units', async (req, res) => {
  try {
    const devices = await dataManager.getDevices();
    const allUnits = [];
    
    for (const [groupName, groupConfig] of Object.entries(devices)) {
      for (const unit of groupConfig.units) {
        allUnits.push({
          ...unit,
          groupName,
          groupDisplayName: groupConfig.displayName
        });
      }
    }
    
    res.json({
      code: 200,
      data: allUnits,
      msg: '获取所有设备单元成功'
    });
  } catch (error) {
    console.error('获取所有设备单元失败:', error);
    res.status(500).json({
      code: 500,
      data: null,
      msg: '获取所有设备单元失败: ' + error.message
    });
  }
});

// 启动服务
app.listen(WEB_PORT, '0.0.0.0', () => {
  console.log(`配置服务启动：http://10.70.33.218:${WEB_PORT}`);
  console.log(`MQTT服务器: ${MQTT_SERVER}`);
  console.log(`MQTT主题前缀: ${MQTT_TOPIC_PREFIX}`);
  console.log(`设备配置文件: ./devices.json`);
});

module.exports = app;