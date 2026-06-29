
# 设备管理系统变更文档（补充代码版）

## 更新日期
2026年5月6日

---

## 一、依赖安装

### 1.1 pinyin包安装
```bash
npm install pinyin
```

**功能用途**：实现中文转拼音功能，用于设备组和设备单元ID的自动生成

**导入方式**：
```javascript
// server-config.js
const { pinyin } = require('pinyin');
```

---

## 二、修复类变更

### 2.1 创建设备组失败修复
- **问题描述**：创建设备组时出现 `ReferenceError: unit is not defined` 错误
- **问题原因**：循环外部存在重复的类型验证代码块
- **修复位置**：`server-config.js`
- **修复前代码**：
```javascript
// 删除前（重复代码）
}

  // 验证type字段只能是control、state或setting
  if (unit.type !== 'control' && unit.type !== 'state' && unit.type !== 'setting') {
    logOperation('UPDATE_DEVICE_UNIT', ...);
    return res.status(400).json({...});
  }

const devices = await dataManager.getDevices();
```
- **修复后代码**：
```javascript
// 删除后
}

const devices = await dataManager.getDevices();
```

### 2.2 更新设备单元类型验证修复
- **问题描述**：修改设备单元类型为 `data` 时报错 "Invalid unit type"
- **修复位置**：`server-config.js` 第527-534行
- **修复前代码**：
```javascript
// 验证type字段只能是control或state
if (type !== 'control' && type !== 'state') {
  logOperation('UPDATE_DEVICE_UNIT', ...);
  return res.status(400).json({
    code: 400,
    data: null,
    msg: '设备单元type字段只能是control或state'
  });
}
```
- **修复后代码**：
```javascript
// 验证type字段只能是control、state、text或data
if (type !== 'control' && type !== 'state' && type !== 'text' && type !== 'data') {
  logOperation('UPDATE_DEVICE_UNIT', ...);
  return res.status(400).json({
    code: 400,
    data: null,
    msg: '设备单元type字段只能是control、state、text或data'
  });
}
```

### 2.3 拼音转换功能实现
- **问题描述**：设备组ID显示中文，设备单元ID显示下划线
- **修复位置**：`server-config.js`
- **实现代码**：
```javascript
// 位置信息处理函数：将中文转换为拼音
function processLocation(location) {
  if (!location || typeof location !== 'string') {
    return '0000';
  }
  
  const hasChinese = /.*[\u4e00-\u9fa5]+.*/.test(location);
  
  if (hasChinese) {
    try {
      const pinyinResult = pinyin(location, {
        heteronym: false,
        segment: false,
        style: pinyin.STYLE_NORMAL
      });
      const processedLocation = pinyinResult.flat().join('').toLowerCase();
      return processedLocation || '0000';
    } catch (e) {
      console.warn('Pinyin conversion failed:', e);
      return location.replace(/[^a-zA-Z0-9_-]/g, '_') || '0000';
    }
  } else {
    return location.replace(/[^a-zA-Z0-9_-]/g, '_') || '0000';
  }
}
```

---

## 三、功能增强类变更

### 3.1 设备单元类型扩展

| 类型名称  | 变量类型 | 状态输入方式     | 说明                              |
| --------- | -------- | ---------------- | --------------------------------- |
| `control` | 布尔     | 下拉选择(ON/OFF) | 控制型设备                        |
| `state`   | 字符串   | 文本输入框       | 状态型设备                        |
| `text`    | 字符串   | 文本输入框       | 文本型设备（原setting类型重命名） |
| `data`    | 数字     | 数字输入框       | 新增数据型设备                    |

### 3.2 前端类型变更事件处理
**实现位置**：`config.html`
```javascript
// 设备类型变更时，调整状态输入方式
document.getElementById('unit-type').addEventListener('change', function() {
  const type = this.value;
  const statusContainer = document.getElementById('unit-status').parentNode;
  
  if (type === 'control') {
    // 控制型设备只能选择 ON 或 OFF
    statusContainer.innerHTML = `
      <label style="display:inline-block;width:100px;">状态：</label>
      <select class="input" id="unit-status" required style="width:calc(100% - 110px);display:inline-block;">
        <option value="ON">ON</option>
        <option value="OFF" selected>OFF</option>
      </select>
    `;
  } else if (type === 'data') {
    // 数据型设备只能输入数字
    statusContainer.innerHTML = `
      <label style="display:inline-block;width:100px;">状态：</label>
      <input class="input" id="unit-status" type="number" placeholder="数字值" value="0" required style="width:calc(100% - 110px);display:inline-block;">
    `;
  } else {
    // 状态型和文本型设备可以输入任意文本
    statusContainer.innerHTML = `
      <label style="display:inline-block;width:100px;">状态：</label>
      <input class="input" id="unit-status" placeholder="状态值" value="OFF" required style="width:calc(100% - 110px);display:inline-block;">
    `;
  }
});
```

### 3.3 设备组编辑模态框
**实现位置**：`config.html`
```javascript
async function editGroup(groupName, displayName, location) {
  const modal = document.createElement('div');
  modal.id = 'edit-group-modal-overlay';
  modal.style.cssText = "position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.5);display:flex;align-items:center;justify-content:center;z-index:1000;";
  modal.innerHTML = `
    <div style="background:white;padding:20px;border-radius:8px;width:90%;max-width:500px;">
      <h3>编辑设备组</h3>
      <div style="margin-bottom:10px;">
        <label style="display:inline-block;width:80px;">名称：</label>
        <input class="input" id="edit-group-name" value="${groupName}" style="width:calc(100% - 90px);display:inline-block;">
      </div>
      <div style="margin-bottom:10px;">
        <label style="display:inline-block;width:80px;">显示名称：</label>
        <input class="input" id="edit-group-display-name" value="${displayName}" style="width:calc(100% - 90px);display:inline-block;">
      </div>
      <div style="margin-bottom:10px;">
        <label style="display:inline-block;width:80px;">位置：</label>
        <input class="input" id="edit-group-location" value="${location || ''}" style="width:calc(100% - 90px);display:inline-block;">
      </div>
      <div style="display:flex;gap:10px;margin-top:15px;">
        <button class="btn update-btn" id="save-group-btn" style="flex:1;">保存</button>
        <button class="btn back-btn" id="cancel-group-btn" style="flex:1;">取消</button>
      </div>
    </div>
  `;
  document.body.appendChild(modal);
  // 事件绑定...
}
```

---

## 四、代码变更清单

### 4.1 server-config.js
| 行号范围     | 变更内容         | 代码示例                                |
| ------------ | ---------------- | --------------------------------------- |
| 头部         | 添加pinyin库导入 | `const { pinyin } = require('pinyin');` |
| 位置处理函数 | 实现中文转拼音   | `processLocation()` 函数                |
| 234-242      | 删除重复代码     | 移除循环外的类型验证                    |
| 223-230      | 类型验证升级     | 支持text、data类型                      |
| 527-534      | 类型验证升级     | 支持text、data类型                      |

### 4.2 config.html
| 行号范围 | 变更内容       | 代码示例               |
| -------- | -------------- | ---------------------- |
| 79-103   | 表单重构       | 添加标签、调整布局     |
| 655-677  | 类型变更事件   | 动态调整状态输入方式   |
| 461-555  | 编辑模态框重构 | 动态状态输入、类型切换 |

### 4.3 package.json
| 变更内容              |
| --------------------- |
| `"pinyin": "^2.11.0"` |

---

## 五、问题与解决方法

### 5.1 问题1：设备组ID显示中文
**现象**：设备组ID显示为"保姆间-sdj-91234409"
**原因**：拼音库未正确安装或导入错误
**解决方法**：
```bash
npm install pinyin
```

### 5.2 问题2：ReferenceError: pinyinLib is not defined
**现象**：运行时出现变量未定义错误
**原因**：使用了错误的变量名
**解决方法**：将 `pinyinLib` 替换为 `pinyin`

### 5.3 问题3：添加设备单元报400错误
**现象**：报错 "Invalid unit type"
**原因**：类型验证不支持新增类型
**解决方法**：更新类型验证逻辑

---

*文档版本：v1.2*  
*生成时间：2026-05-06*
        