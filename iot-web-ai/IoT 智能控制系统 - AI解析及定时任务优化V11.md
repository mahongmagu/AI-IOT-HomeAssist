
# V11版本变更与问题修复总结

## 一、问题修复概览

### 1. AI定时指令解析错误修复

| 问题描述                               | 原因分析                                    | 修复方案                                   |
| -------------------------------------- | ------------------------------------------- | ------------------------------------------ |
| "每隔20分钟"触发RangeError             | `convertTimeToDateTime`无法解析相对时间格式 | 添加相对时间解析逻辑，支持"X分钟/小时"格式 |
| "每隔10分钟"被解析为"每天10:00"        | AI提示词未包含周期性间隔任务说明            | 更新AI提示词，添加interval类型支持         |
| "每天早上10点"解析为08:00              | AI理解时段错误                              | 增强提示词中的时段转换规则说明             |
| AI返回JSON包含注释导致解析失败         | AI响应中包含`// 注释`格式                   | 添加移除单行注释的清理逻辑                 |
| AI返回的interval值错误（10分钟→1分钟） | AI计算错误                                  | 添加从用户输入重新解析验证的逻辑           |

### 2. 时区显示问题修复

**问题**：定时任务时间在前端显示不正确（服务器存储10:00，前端显示18:00）

**原因**：前端使用`new Date()`解析UTC时间时自动转换为本地时区（UTC+8）

**修复**：直接从ISO时间字符串中提取时间部分，避免时区转换

### 3. 设备状态显示修复

**问题**：state和num类型设备控制单元显示OFFLINE状态

**原因**：前端渲染时未区分设备类型，统一使用`alldevicenames[key]?.state`

**修复**：修改`renderdevicenameDetail`函数，对control类型保留OFFLINE状态，对其他类型显示实际值

### 4. ESP8266舵机控制优化

**功能需求**：
- 参数dt从设备单元`keting-lyws-57134878_feedspeed-6847`读取并动态更新
- 执行完成后自动复位状态为OFF

**实现方案**：
- 订阅速度参数主题，动态更新舵机转动速度
- 添加`isExecuting`标志防止重复执行
- 执行完成后自动发布OFF状态

---

## 二、核心代码变更

### 1. server-control-tcp.js

#### 1.1 AI提示词增强（第2652行附近）

```javascript
// 新增时段转换规则说明
const prompt = `
时间格式说明:
- 时段说明：早上/早晨/上午指6:00-12:00，下午指12:00-18:00，晚上指18:00-24:00
- 时间转换规则：早上9点=09:00，上午10点=10:00，下午3点=15:00，晚上8点=20:00
...
`;
```

#### 1.2 JSON解析清理逻辑（第2696-2701行）

```javascript
const cleanResponse = response
  .replace(/^```\s*json\s*/i, '')  // 移除开头的 ```json
  .replace(/\s*```\s*$/, '')        // 移除结尾的 ```
  .replace(/\/\/.*$/gm, '')         // 移除单行注释 //...
  .replace(/\s+/g, ' ')              // 将多个空白字符替换为单个空格
  .trim();
```

#### 1.3 interval值验证与修正（第3232行附近）

```javascript
// 从用户原始输入中提取正确的时间间隔
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
  
  // 如果AI返回的值与用户预期不符，使用用户输入的值
  if (expectedInterval > 0 && (!intervalMs || Math.abs(intervalMs - expectedInterval) > 60000)) {
    intervalMs = expectedInterval;
  }
}
```

### 2. index.html

#### 2.1 定时任务时间显示修复（第1419-1428行）

```javascript
if (task.time) {
  // 直接从UTC字符串中提取时间，避免时区转换
  const timeMatch = task.time.match(/T(\d{2}:\d{2})/);
  if (timeMatch) {
    document.getElementById('schedule-time').value = timeMatch[1];
  } else {
    const date = new Date(task.time);
    document.getElementById('schedule-time').value = date.toTimeString().slice(0, 5);
  }
}
```

#### 2.2 设备状态显示修复（设备详情渲染部分）

```javascript
// 修复后的状态显示逻辑
let status;
if (unit.type === 'control') {
  status = devicenameState || unit.status || 'OFF';
} else {
  // 非控制类型忽略OFFLINE，显示实际值
  status = (devicenameState && devicenameState !== 'OFFLINE') ? devicenameState : (unit.status || '');
}
```

### 3. ESP8266_iotxxx_duoji.ino

```cpp
// 速度参数更新回调
if (String(topic) == topicFeedspeed) {
  int newSpeed = message.toInt();
  if (newSpeed > 0 && newSpeed <= 100) {
    dt = newSpeed;
    Serial.print("速度参数更新为: ");
    Serial.println(dt);
  }
}

// 舵机执行函数
void executeServoMovement() {
  if (isExecuting) return;
  isExecuting = true;
  devicenameState = "ON";
  publishState();
  // 舵机正转180°再反转回0°
  for (pos = 0; pos <= 180; pos += 2) { myservo.write(pos); delay(dt); }
  for (pos = 180; pos >= 0; pos -= 2) { myservo.write(pos); delay(dt); }
  devicenameState = "OFF";
  publishState();
  isExecuting = false;
}
```

---

## 三、MQTT主题结构说明

| 设备单元类型 | MQTT主题格式                      | 示例                                                         |
| ------------ | --------------------------------- | ------------------------------------------------------------ |
| control类型  | `iotxxx/devicename/{unitId}/control`     | `iotxxx/devicename/keting-lyws-57134878_liyuweishiqi-2169/control`  |
| data类型     | `iotxxx/devicename/{unitId}/datasetting` | `iotxxx/devicename/keting-lyws-57134878_feedspeed-6847/datasetting` |
| state类型    | `iotxxx/devicename/{unitId}/state`       | `iotxxx/devicename/{unitId}/state`                                  |

---

## 四、定时任务类型支持

| 类型       | recurring值 | 说明               |
| ---------- | ----------- | ------------------ |
| 一次性任务 | `once`      | 执行一次后自动删除 |
| 每日任务   | `daily`     | 每天指定时间执行   |
| 每周任务   | `weekly`    | 每周指定日期执行   |
| 周期性任务 | `interval`  | 每隔X分钟/小时执行 |

---

## 五、验证结果

| 测试场景   | 输入指令                | 预期结果                     | 实际结果 |
| ---------- | ----------------------- | ---------------------------- | -------- |
| 相对时间   | 每隔20分钟鲤鱼喂食      | 创建interval任务，间隔20分钟 | ✅ 通过   |
| 周期性间隔 | 每隔10分钟开鲤鱼喂食    | 创建interval任务，间隔10分钟 | ✅ 通过   |
| 每日定时   | 每天上午10:00开鲤鱼喂食 | 创建daily任务，10:00执行     | ✅ 通过   |
| 时段解析   | 每天晚上8点开灯         | 创建daily任务，20:00执行     | ✅ 通过   |
| 时区显示   | 服务器存储10:00         | 前端显示10:00                | ✅ 通过   |
| 设备状态   | state类型设备离线       | 显示实际值，不显示OFFLINE    | ✅ 通过   |

---

## 六、注意事项

1. **interval类型任务最小间隔为1分钟**，小于1分钟的间隔会被拒绝
2. **AI提示词中的时段规则**需要保持与代码逻辑一致
3. **时区处理**：服务器存储UTC时间，前端显示时直接提取时间部分避免转换
4. **设备状态显示**：仅control类型显示OFFLINE状态，其他类型显示实际值
        