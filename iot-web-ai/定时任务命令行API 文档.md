
按天和按周定时任务的完整流程：

## 一、创建任务流程

### 1. 用户操作
用户在定时设置弹窗中选择：
- 目标设备单元
- 定时类型：日任务（daily）或周任务（weekly）
- 执行时间（几点几分）
- 执行命令（ON/OFF）

### 2. 前端处理（index.html）
```javascript
// 获取表单数据
const type = document.getElementById('schedule-type').value; // 'daily' 或 'weekly'
const time = document.getElementById('schedule-time').value; // '08:00'

// 构建任务数据
if (type === 'daily') {
  data.interval = 86400000; // 24小时
  const [hours, minutes] = time.split(':');
  const target = new Date();
  target.setHours(hours, minutes, 0, 0);
  if (target < new Date()) target.setDate(target.getDate() + 1);
  data.time = target.toISOString(); // 第一次执行时间
} else if (type === 'weekly') {
  data.interval = 604800000; // 7天
  // 同样设置第一次执行时间...
}

// 发送请求
fetch(api + '/schedule/recurring', {
  method: 'POST',
  body: JSON.stringify(data)
});
```

### 3. 后端处理（server-control-tcp.js）
```javascript
app.post('/api/schedule/recurring', (req, res) => {
  const { unitId, cmd, interval, time } = req.body;
  
  // 创建任务
  const taskId = `schedule-${Date.now()}`;
  scheduledTasks[taskId] = {
    id: taskId,
    unitId,
    cmd,
    interval,
    time,
    enabled: true,
    recurring: true
  };
  
  // 设置定时器（首次执行）
  const targetTime = new Date(time).getTime();
  const delay = targetTime - Date.now();
  
  setTimeout(() => {
    // 第一次执行
    sendMqttControl(cmd, unitId);
    // 然后创建循环定时器
    const timer = setInterval(() => {
      sendMqttControl(cmd, unitId);
    }, interval);
    scheduledTasks[taskId].timer = timer;
  }, delay);
  
  // 保存到文件
  saveSchedules(getSchedulesForSave());
});
```

## 二、修改任务流程

### 1. 用户操作
点击任务的"修改"按钮，弹出定时设置弹窗，修改参数后保存。

### 2. 前端处理
```javascript
function editSchedule(scheduleId) {
  // 获取任务详情
  fetch(api + '/schedule').then(res => res.json())
  .then(result => {
    const task = result.schedules[scheduleId];
    
    // 填充表单（包括日/周任务的时间）
    document.getElementById('schedule-time').value = 
      new Date(task.time).toTimeString().slice(0, 5);
    
    // 设置编辑模式
    editingScheduleId = scheduleId;
  });
  
  // 保存时发送 PUT 请求
  fetch(api + '/schedule/' + editingScheduleId, {
    method: 'PUT',
    body: JSON.stringify(data)
  });
}
```

### 3. 后端处理
```javascript
app.put('/api/schedule/:taskId', (req, res) => {
  const task = scheduledTasks[taskId];
  
  // 更新参数
  if (interval) {
    task.interval = interval;
    // 保留 time 字段（不设置为 null）
    task.recurring = true;
  }
  if (time) {
    task.time = time;
  }
  
  // 更新定时器
  // ...
  
  saveSchedules(getSchedulesForSave());
});
```

## 三、删除任务流程

### 1. 用户操作
点击任务的"删除"按钮，确认后删除。

### 2. 前端处理
```javascript
function deleteSchedule(scheduleId) {
  fetch(api + '/schedule/' + scheduleId, {
    method: 'DELETE'
  }).then(res => {
    // 刷新任务列表
    loadDeviceDetail(currentDeviceGroup);
  });
}
```

### 3. 后端处理
```javascript
app.delete('/api/schedule/:taskId', (req, res) => {
  const task = scheduledTasks[taskId];
  
  // 取消定时器
  if (task.recurring) {
    clearInterval(task.timer);
  } else {
    clearTimeout(task.timer);
  }
  
  // 删除任务
  delete scheduledTasks[taskId];
  
  // 保存到文件
  saveSchedules(getSchedulesForSave());
});
```

## 四、数据格式

### 日任务数据格式（schedule.json）
```json
{
  "schedule-1778221625048": {
    "id": "schedule-1778221625048",
    "name": "宝木间-开关设备-开关1-1",
    "unitId": "baomujian-sdj-40858013_kaiguan-2966",
    "cmd": "ON",
    "interval": 86400000,  // 24小时
    "time": "2026-05-09T08:00:00.000Z",  // 第一次执行时间
    "enabled": true,
    "recurring": true,
    "createdAt": "2026-05-08T06:27:05.048Z"
  }
}
```

### 周任务数据格式（schedule.json）
```json
{
  "schedule-1778221751655": {
    "id": "schedule-1778221751655",
    "name": "宝木间-开关设备-开关2-1",
    "unitId": "baomujian-sdj-40858013_kaiguan-2967",
    "cmd": "OFF",
    "interval": 604800000,  // 7天
    "time": "2026-05-12T18:30:00.000Z",  // 第一次执行时间（本周六）
    "enabled": true,
    "recurring": true,
    "createdAt": "2026-05-08T06:29:11.655Z"
  }
}
```

## 五、关键要点

| 字段        | 说明                                         |
| ----------- | -------------------------------------------- |
| `interval`  | 执行间隔：日任务=86400000，周任务=604800000  |
| `time`      | **必须有！** 第一次执行的具体时间（ISO格式） |
| `recurring` | true（表示周期性任务）                       |
| `enabled`   | true/false（控制任务是否启用）               |

**日任务和周任务的执行逻辑：**
1. 根据 `time` 字段计算首次执行延迟
2. 到时间后执行第一次命令
3. 然后创建 `setInterval` 循环执行（每24小时/7天）
4. 如果 `time` 为 null，任务会立即开始执行（错误行为）
        

以下是定时任务配置的完整命令行文档：

---

## 定时任务 API 文档

### 1. 创建一次性定时任务

```bash
curl -X POST http://localhost:3000/api/schedule \
  -H "Content-Type: application/json" \
  -d '{
    "id": "kaiguan-2966-1",
    "name": "宝木间-开关设备-开关-1",
    "unitId": "kaiguan-2966",
    "cmd": "ON",
    "time": "2024-01-15T08:00:00.000Z"
  }'
```

**参数说明：**
| 参数   | 类型          | 必填 | 说明                                                 |
| ------ | ------------- | ---- | ---------------------------------------------------- |
| id     | string        | 否   | 任务ID（格式：设备单元ID+序号，如 `kaiguan-2966-1`） |
| name   | string        | 否   | 任务名称（格式：位置+设备组+设备单元+序号）          |
| unitId | string        | 是   | 设备单元ID                                           |
| cmd    | string        | 是   | 命令：`ON` 或 `OFF`                                  |
| time   | string/number | 是   | 定时时间（ISO日期格式或毫秒数）                      |

---

### 2. 创建周期性定时任务

```bash
curl -X POST http://localhost:3000/api/schedule/recurring \
  -H "Content-Type: application/json" \
  -d '{
    "id": "kaiguan-2966-2",
    "name": "宝木间-开关设备-开关-2",
    "unitId": "kaiguan-2966",
    "cmd": "OFF",
    "interval": 1800000
  }'
```

**参数说明：**
| 参数     | 类型   | 必填 | 说明                        |
| -------- | ------ | ---- | --------------------------- |
| id       | string | 否   | 任务ID                      |
| name     | string | 否   | 任务名称                    |
| unitId   | string | 是   | 设备单元ID                  |
| cmd      | string | 是   | 命令：`ON` 或 `OFF`         |
| interval | number | 是   | 执行间隔（毫秒，最小10000） |

---

### 3. 获取定时任务列表

```bash
curl -X GET http://localhost:3000/api/schedule/list
```

**响应示例：**
```json
{
  "code": 200,
  "schedules": [
    {
      "id": "kaiguan-2966-1",
      "name": "宝木间-开关设备-开关-1",
      "unitId": "kaiguan-2966",
      "cmd": "ON",
      "time": "2024-01-15T08:00:00.000Z",
      "enabled": true,
      "createdAt": "2024-01-10T10:30:00.000Z"
    }
  ]
}
```

---

### 4. 获取定时任务详情（对象格式）

```bash
curl -X GET http://localhost:3000/api/schedule
```

---

### 5. 删除定时任务

```bash
curl -X DELETE http://localhost:3000/api/schedule/{taskId}
```

**示例：**
```bash
curl -X DELETE http://localhost:3000/api/schedule/kaiguan-2966-1
```

---

### 6. 启用定时任务

```bash
curl -X PUT http://localhost:3000/api/schedule/{taskId}/enable \
  -H "Content-Type: application/json" \
  -d '{"enabled": true}'
```

---

### 7. 禁用定时任务

```bash
curl -X PUT http://localhost:3000/api/schedule/{taskId}/enable \
  -H "Content-Type: application/json" \
  -d '{"enabled": false}'
```

---

## 任务数据持久化

定时任务自动保存到 `./data/schedules.json` 文件：

```json
{
  "kaiguan-2966-1": {
    "id": "kaiguan-2966-1",
    "name": "宝木间-开关设备-开关-1",
    "unitId": "kaiguan-2966",
    "cmd": "ON",
    "time": "2024-01-15T08:00:00.000Z",
    "enabled": true,
    "createdAt": "2024-01-10T10:30:00.000Z"
  },
  "kaiguan-2967-1": {
    "id": "kaiguan-2967-1",
    "name": "宝木间-开关设备-开关2-1",
    "unitId": "kaiguan-2967",
    "cmd": "OFF",
    "interval": 1800000,
    "enabled": true,
    "createdAt": "2024-01-10T11:00:00.000Z",
    "recurring": true
  }
}
```

---

## 注意事项

1. **服务重启后恢复**：未执行的一次性任务和所有周期性任务会自动恢复
2. **时间格式**：支持 ISO 8601 格式（如 `2024-01-15T08:00:00.000Z`）或毫秒数
3. **周期性任务间隔**：最小为 10 秒（10000毫秒）
4. **任务ID格式**：建议使用 `设备单元ID-序号` 格式，如 `kaiguan-2966-1`
5. **任务名称格式**：建议使用 `位置-设备组-设备单元-序号` 格式
        