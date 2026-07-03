4. # IoT Web AI 项目文档
   
   ---
   
   ## 一、架构和功能说明
   
   ### 1.1 系统架构
   
   #### 1.1.1 整体架构图
   
   ```
   ┌─────────────────────────────────────────────────────────────────────────┐
   │                        系统架构                                        │
   ├─────────────────────────────────────────────────────────────────────────┤
   │                                                                         │
   │   ┌─────────────────┐      ┌─────────────────┐      ┌───────────────┐   │
   │   │   前端页面      │──────│   控制服务       │──────│   MQTT服务器  │   │
   │   │   index.html    │      │ server-control- │      │    EMQX       │   │
   │   │   config.html   │      │   tcp.js        │      │ 192.168.1.40 │   │
   │   └────────┬────────┘      └────────┬────────┘      └───────┬───────┘   │
   │            │                        │                        │          │
   │            │ WebSocket              │ MQTT TCP               │ MQTT     │
   │            ↓                        ↓                        ↓          │
   │   ┌───────────────────────────────────────────────────────────────────┐ │
   │   │                    状态服务 (server-status-ws.js)                 │ │
   │   │                  监听端口: 8084                                   │ │
   │   │                  IP: 192.168.1.40                               │ │
   │   └───────────────────────────────────────────────────────────────────┘ │
   │                                                                         │
   └─────────────────────────────────────────────────────────────────────────┘
   ```
   
   #### 1.1.2 服务组件
   
   | 服务     | 文件                    | 端口 | 功能                 |
   | -------- | ----------------------- | ---- | -------------------- |
   | 配置服务 | `server-config.js`      | 6001 | 设备配置管理（CRUD） |
   | 控制服务 | `server-control-tcp.js` | 6002 | MQTT控制指令下发     |
   | 状态服务 | `server-status-ws.js`   | 8084 | WebSocket状态推送    |
   
   #### 1.1.3 数据流
   
   ```
   用户操作 → 前端页面 → 控制服务 → MQTT服务器 → 设备端
                                             ↓
                                       状态上报 → MQTT服务器 → 状态服务 → 前端页面
   ```
   
   ### 1.2 核心功能
   
   #### 1.2.1 设备管理
   
   | 功能         | 说明                                     |
   | ------------ | ---------------------------------------- |
   | 设备组管理   | 创建、编辑、删除设备组                   |
   | 设备单元管理 | 添加、编辑、删除设备单元                 |
   | 自动ID生成   | 设备组和单元ID自动生成（支持中文转拼音） |
   | 位置字段     | 设备组支持可选位置字段                   |
   
   #### 1.2.2 设备控制
   
   | 设备类型 | 控制方式       | 说明       |
   | -------- | -------------- | ---------- |
   | control  | ON/OFF下拉选择 | 控制型设备 |
   | state    | 文本输入       | 状态型设备 |
   | text     | 文本编辑       | 文本型设备 |
   | data     | 数值编辑       | 数据型设备 |
   
   #### 1.2.3 实时状态同步
   
   - **WebSocket实时推送**：状态变化即时更新
   - **MQTT主题订阅**：支持 state/textsetting/datasetting 主题
   - **初始状态加载**：连接建立时同步所有设备状态
   
   #### 1.2.4 AI指令解析
   
   - **基础AI接口**：`POST /api/ai`
   - **高级AI接口**：`POST /api/ai-advanced`
   - **指令格式**：自然语言指令（如"打开插座1"）
   
   ### 1.3 MQTT主题设计
   
   | 主题格式                          | 用途     | 说明          |
   | --------------------------------- | -------- | ------------- |
   | `iot/device/{unitId}/control`     | 控制指令 | 服务端→设备端 |
   | `iot/device/{unitId}/state`       | 状态上报 | 设备端→服务端 |
   | `iot/device/{unitId}/textsetting` | 文本设置 | 双向          |
   | `iot/device/{unitId}/datasetting` | 数据设置 | 双向          |
   
   ---
   
   ## 二、安装部署和操作
   
   ### 2.1 环境要求
   
   | 项目        | 要求                |
   | ----------- | ------------------- |
   | Node.js     | >= 14.0.0           |
   | npm         | >= 6.0.0            |
   | MQTT Broker | EMQX 4.x 或兼容服务 |
   
   ### 2.2 安装步骤
   
   #### 2.2.1 克隆项目
   
   ```bash
   git clone <repository-url>
   cd iot-web-ai
   ```
   
   #### 2.2.2 安装依赖
   
   ```bash
   npm install
   npm install pinyin  # 拼音转换库
   ```
   
   #### 2.2.3 配置环境变量
   
   根据实际网络和主机配置修改 `.env` 文件：
   
   ```env
   # 服务器配置
   SERVER_IP=192.168.1.149
   WS_PORT=8084
   
   # MQTT服务器配置
   MQTT_EXTERNAL_WS_SERVER=ws://192.168.1.40:8083/mqtt
   MQTT_INTERNAL_SERVER=mqtt://192.168.1.40:1883
   MQTT_TOPIC_PREFIX=iot/device
   MQTT_USERNAME=xx
   MQTT_PASSWORD=XXXXXX
   
   # 服务端口配置
   CONFIG_SERVICE_PORT=6001
   CONTROL_SERVICE_PORT=6002
   ```
   
   ### 2.3 启动服务
   
   #### 2.3.1 启动配置服务
   
   ```bash
   npm run config
   # 输出示例：
   # 配置服务启动：http://192.168.1.149:6001
   ```
   
   #### 2.3.2 启动控制服务
   
   ```bash
   npm run start
   # 输出示例：
   # 控制服务启动：http://192.168.1.40:6002
   # MQTT TCP控制客户端（内网）连接成功
   ```
   
   #### 2.3.3 启动状态服务
   
   ```bash
   npm run status
   # 输出示例：
   # WebSocket状态服务（外网）启动: ws://192.168.1.40:8084
   # MQTT WebSocket状态客户端（外网）连接成功
   ```
   
   ### 2.4 访问方式
   
   | 服务         | URL                                   |
   | ------------ | ------------------------------------- |
   | 设备控制页面 | `http://<server-ip>:6002/index.html`  |
   | 配置管理页面 | `http://<server-ip>:6001/config.html` |
   
   ### 2.5 设备端配置
   
   #### 2.5.1 订阅主题
   
   设备端需要订阅以下主题：
   
   ```bash
   # 控制指令
   iot/device/+/control
   
   # 文本设置
   iot/device/+/textsetting
   
   # 数据设置
   iot/device/+/datasetting
   ```
   
   #### 2.5.2 状态上报
   
   设备执行操作后，需要上报状态到：
   
   ```bash
   iot/device/{unitId}/state
   ```
   
   ---
   
   ## 三、测试步骤和内容
   
   ### 3.1 功能测试
   
   #### 3.1.1 设备组管理测试
   
   | 测试项         | 步骤                               | 预期结果                   |
   | -------------- | ---------------------------------- | -------------------------- |
   | 创建设备组     | 填写名称、显示名称、位置、设备单元 | 设备组创建成功，ID自动生成 |
   | 编辑设备组     | 修改名称、显示名称、位置           | 修改成功，设备组信息更新   |
   | 删除设备组     | 点击删除按钮                       | 设备组删除成功             |
   | 查看设备组列表 | 访问配置页面                       | 显示所有设备组             |
   
   #### 3.1.2 设备单元管理测试
   
   | 测试项       | 步骤                     | 预期结果                 |
   | ------------ | ------------------------ | ------------------------ |
   | 添加设备单元 | 选择类型、填写名称、状态 | 单元添加成功，ID自动生成 |
   | 编辑设备单元 | 修改类型、名称、状态     | 修改成功                 |
   | 删除设备单元 | 点击删除按钮             | 单元删除成功             |
   
   #### 3.1.3 设备控制测试
   
   | 测试项     | 步骤                       | 预期结果                       |
   | ---------- | -------------------------- | ------------------------------ |
   | 控制型设备 | 点击打开/关闭按钮          | MQTT消息发送成功，设备状态变化 |
   | 文本型设备 | 点击编辑文本按钮，输入文本 | textsetting消息发送成功        |
   | 数据型设备 | 点击编辑数值按钮，输入数字 | datasetting消息发送成功        |
   | 状态型设备 | 点击查询状态按钮           | 状态刷新                       |
   
   #### 3.1.4 AI指令测试
   
   | 测试项     | 步骤            | 预期结果               |
   | ---------- | --------------- | ---------------------- |
   | 基础AI接口 | 发送"打开插座1" | 指令解析成功，设备打开 |
   | 高级AI接口 | 发送复杂指令    | 多个设备操作执行成功   |
   
   ### 3.2 接口测试
   
   #### 3.2.1 设备组接口
   
   | 接口                  | 方法   | 测试数据                                                     | 预期结果       |
   | --------------------- | ------ | ------------------------------------------------------------ | -------------- |
   | `/api/devices`        | GET    | -                                                            | 返回所有设备组 |
   | `/api/devices`        | POST   | `{"name":"test","displayName":"测试","location":"测试位置","units":[]}` | 创建成功       |
   | `/api/devices/{name}` | GET    | 设备组名称                                                   | 返回设备组详情 |
   | `/api/devices/{name}` | PUT    | 修改数据                                                     | 修改成功       |
   | `/api/devices/{name}` | DELETE | 设备组名称                                                   | 删除成功       |
   
   #### 3.2.2 设备单元接口
   
   | 接口                                      | 方法   | 测试数据                                              | 预期结果 |
   | ----------------------------------------- | ------ | ----------------------------------------------------- | -------- |
   | `/api/devices/{groupName}/units`          | POST   | `{"name":"测试单元","type":"control","status":"OFF"}` | 添加成功 |
   | `/api/devices/{groupName}/units/{unitId}` | PUT    | 修改数据                                              | 修改成功 |
   | `/api/devices/{groupName}/units/{unitId}` | DELETE | 单元ID                                                | 删除成功 |
   
   #### 3.2.3 控制接口
   
   | 接口                | 方法 | 测试数据                            | 预期结果         |
   | ------------------- | ---- | ----------------------------------- | ---------------- |
   | `/api/control-slot` | POST | `{"slot":"unit-id","cmd":"ON"}`     | 控制指令发送成功 |
   | `/api/set-text`     | POST | `{"slot":"unit-id","value":"test"}` | 文本设置成功     |
   | `/api/set-data`     | POST | `{"slot":"unit-id","value":100}`    | 数据设置成功     |
   
   ### 3.3 状态同步测试
   
   #### 3.3.1 WebSocket连接测试
   
   | 测试项   | 步骤             | 预期结果             |
   | -------- | ---------------- | -------------------- |
   | 连接建立 | 打开设备控制页面 | 状态连接显示"已连接" |
   | 状态推送 | 设备上报状态变化 | 页面实时更新显示     |
   | 连接断开 | 停止状态服务     | 状态连接显示"未连接" |
   
   #### 3.3.2 MQTT消息测试
   
   使用MQTT客户端测试：
   
   ```bash
   # 订阅状态主题
   mqtt sub -t "iot/device/+/state" -h 192.168.1.40 -p 1883
   
   # 发布测试消息
   mqtt pub -t "iot/device/test-unit/state" -m "ON" -h 192.168.1.40 -p 1883
   
   # 预期：前端页面显示设备状态变为ON
   ```
   
   ### 3.4 性能测试
   
   | 测试项   | 方法                  | 指标              |
   | -------- | --------------------- | ----------------- |
   | 并发连接 | 模拟多个WebSocket连接 | 支持100+并发      |
   | 消息延迟 | 发送指令到状态更新    | < 500ms           |
   | 设备数量 | 创建大量设备组和单元  | 支持1000+设备单元 |
   
   ---
   
   ## 四、优化建议
   
   ### 4.1 架构优化
   
   #### 4.1.1 服务分离
   
   **现状**：三个服务独立运行，需要手动启动
   
   **建议**：使用 Docker Compose 编排服务，一键启动
   
   ```yaml
   # docker-compose.yml
   version: '3'
   services:
     config-service:
       build: .
       command: npm run config
       ports:
         - "6001:6001"
     
     control-service:
       build: .
       command: npm run start
       ports:
         - "6002:6002"
     
     status-service:
       build: .
       command: npm run status
       ports:
         - "8084:8084"
   
     emqx:
       image: emqx/emqx:4.4
       ports:
         - "1883:1883"
         - "8083:8083"
         - "8084:8084"
   ```
   
   #### 4.1.2 数据库集成
   
   **现状**：使用 JSON 文件存储配置
   
   **建议**：集成 SQLite 或 MongoDB，支持更复杂的查询和事务
   
   ```javascript
   // 使用 SQLite 示例
   const sqlite3 = require('sqlite3').verbose();
   const db = new sqlite3.Database('devices.db');
   
   db.run(`CREATE TABLE IF NOT EXISTS device_groups (
     id TEXT PRIMARY KEY,
     name TEXT,
     displayName TEXT,
     location TEXT,
     createdAt TEXT
   )`);
   ```
   
   ### 4.2 功能优化
   
   #### 4.2.1 用户认证
   
   **现状**：无用户认证机制
   
   **建议**：添加 JWT 认证，保护 API 接口
   
   ```javascript
   // JWT 中间件
   function authenticateToken(req, res, next) {
     const authHeader = req.headers['authorization'];
     const token = authHeader && authHeader.split(' ')[1];
     
     if (!token) return res.sendStatus(401);
     
     jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
       if (err) return res.sendStatus(403);
       req.user = user;
       next();
     });
   }
   ```
   
   #### 4.2.2 操作日志
   
   **现状**：基本日志记录
   
   **建议**：完善操作日志系统，记录所有设备操作
   
   ```javascript
   // 操作日志结构
   {
     timestamp: Date,
     operator: String,
     action: String,
     target: String,
     before: Object,
     after: Object,
     result: String
   }
   ```
   
   #### 4.2.3 设备发现
   
   **现状**：手动添加设备
   
   **建议**：支持 MQTT 自动发现协议，设备自动注册
   
   ```javascript
   // 设备发现主题
   mqttClient.subscribe('iot/device/discovery', (err) => {
     // 处理设备发现消息
   });
   ```
   
   ### 4.3 性能优化
   
   #### 4.3.1 缓存优化
   
   **现状**：内存缓存，重启后失效
   
   **建议**：使用 Redis 作为分布式缓存
   
   ```javascript
   const redis = require('redis');
   const client = redis.createClient();
   
   // 缓存设备配置
   await client.set('devices', JSON.stringify(devices));
   ```
   
   #### 4.3.2 消息队列
   
   **现状**：同步处理消息
   
   **建议**：使用消息队列异步处理，提高吞吐量
   
   ```javascript
   // 使用 Bull 队列
   const Queue = require('bull');
   const controlQueue = new Queue('control');
   
   controlQueue.process(async (job) => {
     await sendMqttControl(job.data.cmd, job.data.unitId);
   });
   ```
   
   ### 4.4 安全性优化
   
   #### 4.4.1 输入验证
   
   **现状**：基本验证
   
   **建议**：使用 Joi 进行严格的输入验证
   
   ```javascript
   const Joi = require('joi');
   
   const schema = Joi.object({
     name: Joi.string().required(),
     displayName: Joi.string().required(),
     location: Joi.string(),
     units: Joi.array().items(Joi.object({
       name: Joi.string().required(),
       type: Joi.string().valid('control', 'state', 'text', 'data').required(),
       status: Joi.string().required()
     }))
   });
   ```
   
   #### 4.4.2 HTTPS支持
   
   **现状**：HTTP 协议
   
   **建议**：配置 HTTPS，使用 Let's Encrypt 证书
   
   ```javascript
   const https = require('https');
   const fs = require('fs');
   
   const options = {
     key: fs.readFileSync('server.key'),
     cert: fs.readFileSync('server.cert')
   };
   
   https.createServer(options, app).listen(443);
   ```
   
   ### 4.5 监控和告警
   
   #### 4.5.1 健康检查
   
   **建议**：添加健康检查接口
   
   ```javascript
   app.get('/health', (req, res) => {
     res.json({
       status: 'healthy',
       timestamp: new Date().toISOString(),
       mqttConnected: mqttConnected,
       wsClients: wsClients.size
     });
   });
   ```
   
   #### 4.5.2 告警机制
   
   **建议**：配置告警规则，异常情况通知
   
   ```javascript
   // 设备离线告警
   function checkDeviceOffline(deviceId, lastOnline) {
     const offlineMinutes = (Date.now() - lastOnline) / 60000;
     if (offlineMinutes > 5) {
       sendAlert(`设备 ${deviceId} 离线超过5分钟`);
     }
   }
   ```
   
   ---
   
   ## 五、附录
   
   ### 5.1 文件结构
   
   ```
   iot-web-ai/v8/
   ├── .env                    # 环境变量配置
   ├── package.json            # 项目依赖
   ├── data-manager.js         # 数据持久化管理
   ├── devices.json            # 设备配置文件
   ├── server-config.js        # 配置服务
   ├── server-control-tcp.js   # 控制服务
   ├── server-status-ws.js     # 状态服务
   ├── index.html              # 设备控制页面
   └── config.html             # 配置管理页面
   ```
   
   ### 5.2 设备数据结构
   
   ```json
   {
     "设备组名称": {
       "name": "设备组名称",
       "displayName": "显示名称",
       "id": "设备组ID",
       "location": "位置",
       "units": [
         {
           "id": "设备单元ID",
           "name": "设备单元名称",
           "type": "control|state|text|data",
           "status": "状态值"
         }
       ]
     }
   }
   ```
   
   ### 5.3 常见问题
   
   | 问题                         | 原因                | 解决方案                           |
   | ---------------------------- | ------------------- | ---------------------------------- |
   | 状态连接显示"未知"           | WebSocket连接未建立 | 检查状态服务是否启动，端口是否正确 |
   | MQTT消息发送成功但设备无响应 | 设备未订阅对应主题  | 检查设备端订阅配置                 |
   | 配置文件加载失败             | JSON语法错误        | 检查devices.json格式               |
   | 端口冲突                     | 端口被占用          | 修改.env中的端口配置               |
   
   ---
   
   **文档版本**: v1.0  
   **生成日期**: 2026-05-07  
   **项目版本**: IoT Web AI v2.2.1
           
