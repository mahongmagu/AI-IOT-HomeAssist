// data-manager.js
const fs = require('fs').promises;
const path = require('path');

class DataManager {
  constructor(filePath = './devices.json') {
    this.filePath = filePath;
  }

  // 读取设备数据
  async readData() {
    try {
      const data = await fs.readFile(this.filePath, 'utf8');
      return JSON.parse(data);
    } catch (error) {
      if (error.code === 'ENOENT') {
        // 文件不存在，创建默认数据
        const defaultData = {
          devices: {},
          lastUpdated: new Date().toISOString()
        };
        await this.writeData(defaultData);
        return defaultData;
      }
      throw error;
    }
  }

  // 写入设备数据
  async writeData(data) {
    data.lastUpdated = new Date().toISOString();
    await fs.writeFile(this.filePath, JSON.stringify(data, null, 2), 'utf8');
  }

  // 获取所有设备
  async getDevices() {
    const data = await this.readData();
    // 如果数据结构是直接的设备组（而不是嵌套在devices键下），直接返回整个数据
    if (data.devices) {
      return data.devices;
    }
    
    // 过滤掉元数据字段，只返回设备组
    const devices = {};
    for (const key in data) {
      if (key !== 'lastUpdated') {  // 排除元数据字段
        devices[key] = data[key];
      }
    }
    return devices;
  }

  // 获取特定设备
  async getDevice(deviceName) {
    const devices = await this.getDevices();
    return devices[deviceName];
  }

  // 添加设备
  async addDevice(device) {
    const data = await this.readData();
    data.devices[device.name] = device;
    await this.writeData(data);
  }

  // 更新设备
  async updateDevice(deviceName, updatedDevice) {
    const data = await this.readData();
    if (data.devices[deviceName]) {
      data.devices[deviceName] = updatedDevice;
      await this.writeData(data);
    }
  }

  // 删除设备
  async deleteDevice(deviceName) {
    const data = await this.readData();
    if (data.devices[deviceName]) {
      delete data.devices[deviceName];
      await this.writeData(data);
    }
  }

  // 更新设备状态
  async updateDeviceStatus(deviceId, status) {
    const data = await this.readData();
    
    // 确定要遍历的数据结构
    const devices = data.devices || data;
    
    // 遍历所有设备和其单元来查找匹配的ID
    for (const [groupName, groupConfig] of Object.entries(devices)) {
      // 跳过元数据字段
      if (groupName === 'lastUpdated') continue;
      
      if (groupConfig && groupConfig.units) {
        for (const unit of groupConfig.units) {
          if (unit.id === deviceId) {
            unit.status = status;
            await this.writeData(data);
            return true;
          }
        }
      }
    }
    
    return false; // 设备ID未找到
  }

  // 更新多个设备状态
  async updateMultipleDeviceStatus(statusUpdates) {
    const data = await this.readData();
    
    for (const [deviceId, status] of Object.entries(statusUpdates)) {
      // 遍历所有设备和其单元来查找匹配的ID
      for (const [groupName, groupConfig] of Object.entries(data.devices)) {
        for (const unit of groupConfig.units) {
          if (unit.id === deviceId) {
            unit.status = status;
            break;
          }
        }
      }
    }
    
    await this.writeData(data);
  }

  // 保存设备数据
  async saveDevices(devices) {
    // 检查现有数据结构
    let currentData;
    try {
      currentData = await this.readData();
    } catch (error) {
      // 如果文件不存在，创建新的数据结构
      currentData = {};
    }
    
    // 如果当前数据结构包含 devices 键，则使用该结构
    if (currentData.devices !== undefined) {
      currentData.devices = devices;
    } else {
      // 否则直接保存设备数据
      currentData = devices;
    }
    
    await this.writeData(currentData);
  }
}

module.exports = DataManager;