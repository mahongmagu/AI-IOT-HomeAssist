# 安装

## 一、服务器环境安装

bash

```
# 1. 安装Node.js
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash
sudo apt install -y nodejs

# 2. 安装Ollama
curl -fsSL https://ollama.com/install.sh | sh

# 3. 下载Qwen2.5-1.5b模型
ollama pull qwen2.5:1.5b
```

## 二、部署项目

bash



```
# 创建文件夹
mkdir iot-web-ai && cd iot-web-ai

# 将所有文件放入iot-web-ai目录下

# 安装依赖
npm install

# 启动服务
npm start
```

## 三、访问使用

- 手机浏览器打开：`http://你的服务器公网IP:3002`
- 功能：
  - 手动开关设备
  - 输入文字 AI 自动控制（打开、关闭、开灯、关灯等）
  - 实时显示设备状态



# 系统服务配置

这是 `package.json` 中的 **npm 脚本配置**，用于管理 IoT 智能控制系统的三个核心服务。以下是详细解释：

---

# 📋 脚本功能分类说明

### 1. 开发模式脚本（直接启动）

| 脚本                        | 命令                                                 | 功能说明                                                     |
| --------------------------- | ---------------------------------------------------- | ------------------------------------------------------------ |
| `npm run start`             | `node server-control-tcp.js`                         | 启动**控制服务**（端口3002）<br>→ 负责定时任务管理、设备控制API |
| `npm run status`            | `node server-status-ws.js`                           | 启动**状态服务**（端口8090）<br>→ 负责WebSocket实时状态推送  |
| `npm run config`            | `node server-config.js`                              | 启动**配置服务**（端口3001）<br>→ 负责设备配置管理           |
| `npm run home-assistant-AI` | `concurrently "npm:start" "npm:status" "npm:config"` | **同时启动三个服务**（需先安装 `concurrently`）              |

### 2. PM2 生产模式脚本（后台运行）

| 脚本               | 命令                                                         | 功能说明                                 |
| ------------------ | ------------------------------------------------------------ | ---------------------------------------- |
| `npm run pm2-ctl`  | `pm2 start npm --name AI-CTL-server -- run start`            | PM2启动控制服务                          |
| `npm run pm2-sta`  | `pm2 start npm --name AI-STA-server -- run status`           | PM2启动状态服务                          |
| `npm run pm2-cfg`  | `pm2 start npm --name AI-CFG-server -- run config`           | PM2启动配置服务                          |
| `npm run pm2-iot`  | `pm2 start npm --name AI-iot-Server -- run home-assistant-AI` | **一键启动全部三个服务**（推荐生产环境） |
| `npm run pm2-list` | `pm2 list`                                                   | 查看PM2管理的所有进程状态                |
| `npm run pm2-logs` | `pm2 logs`                                                   | 查看PM2进程实时日志                      |
| `pm2-stop`         | `pm2 delete all`                                             | 停止并删除所有PM2进程                    |

### 3. 服务停止命令

| 脚本               | 命令                       | 功能说明                 |
| ------------------ | -------------------------- | ------------------------ |
| `npm run stop-ctl` | `pm2 delete AI-CTL-server` | 停止控制服务（单个）     |
| `npm run stop-sta` | `pm2 delete AI-STA-server` | 停止状态服务（单个）     |
| `npm run stop-cfg` | `pm2 delete AI-CFG-server` | 停止配置服务（单个）     |
| `npm run stop-all` | `npm run pm2-stop`         | 停止所有服务（快捷命令） |

---

## 🚀 使用场景

### 开发调试（需要多个终端）
```bash
# 终端1：启动配置服务
npm run config

# 终端2：启动控制服务
npm run start

# 终端3：启动状态服务  
npm run status

# 或者使用 concurrently 一键启动（推荐）
npm run home-assistant-AI
```

### 生产环境（PM2后台运行）
```bash
# 一键启动全部服务
npm run pm2-iot

# 查看进程状态
npm run pm2-list

# 查看实时日志
npm run pm2-logs

# 停止所有服务
npm run stop-all
```

---

## 🔗 服务架构图

```
┌─────────────────────────────────────────────────────────────┐
│                    IoT 智能控制系统                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐   │
│  │ 配置服务     │    │ 控制服务     │    │ 状态服务     │   │
│  │ (端口6001)   │    │ (端口6002)   │    │ (端口8090)   │   │
│  │ server-config│    │ server-control│   │ server-status│   │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘   │
│         │                   │                   │            │
│         └───────────────────┼───────────────────┘            │
│                             ▼                                │
│                      ┌──────────────┐                        │
│                      │   MQTT服务器  │                        │
│                      │  (端口1883/8083)│                     │
│                      └───────┬───────┘                        │
│                             ▼                                │
│                      ┌──────────────┐                        │
│                      │   设备端      │                        │
│                      └──────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

> **提示**：使用 `home-assistant-AI` 或 `pm2-iot` 需要先安装 `concurrently`：
> ```bash
> npm install concurrently --save-dev
> ```



# IoT 服务作为 **daemon（守护进程）**

将 IoT 服务作为 **daemon（守护进程）** 运行有多种方式，以下是推荐的三种方法：

---

## 🚀 方法一：使用 PM2（推荐）

PM2 是 Node.js 专用的进程管理器，支持自动重启、日志管理、负载均衡等功能。

### 1. 安装 PM2
```bash
npm install pm2 -g
```

### 2. 启动服务（一键启动全部）
```bash
# 启动全部三个服务（推荐生产环境）
npm run pm2-iot

# 或者分别启动单个服务
npm run pm2-ctl   # 控制服务
npm run pm2-sta   # 状态服务
npm run pm2-cfg   # 配置服务
```

### 3. 常用命令
```bash
# 查看进程状态
npm run pm2-list

# 查看实时日志
npm run pm2-logs

# 停止服务
npm run stop-all

# 重启服务
pm2 restart AI-iot-Server  # 重启全部服务
pm2 restart AI-CTL-server  # 重启单个服务

# 设置开机自启
pm2 startup   # 生成开机自启脚本
pm2 save      # 保存当前进程配置
```

### 4. PM2 配置文件（可选）

创建 `ecosystem.config.js` 文件，更灵活地管理服务：

```javascript
module.exports = {
  apps: [
    {
      name: 'AI-CTL-server',
      script: 'server-control-tcp.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      env: {
        NODE_ENV: 'production'
      }
    },
    {
      name: 'AI-STA-server',
      script: 'server-status-ws.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      env: {
        NODE_ENV: 'production'
      }
    },
    {
      name: 'AI-CFG-server',
      script: 'server-config.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      env: {
        NODE_ENV: 'production'
      }
    }
  ]
};
```

启动方式：
```bash
pm2 start ecosystem.config.js
```

---

## 🖥️ 方法二：使用 systemd（Linux 系统服务）

适合需要深度集成到 Linux 系统的场景。

### 1. 创建 systemd 服务文件

创建 `/etc/systemd/system/iot-web-ai.service`：

```ini
[Unit]
Description=IoT Web AI Service
After=network.target

[Service]
Type=simple
User=your_username
WorkingDirectory=/path/to/your/project/v8
ExecStart=/usr/bin/node server-control-tcp.js
Restart=always
RestartSec=3
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
```

### 2. 启动服务
```bash
# 重新加载 systemd 配置
sudo systemctl daemon-reload

# 启动服务
sudo systemctl start iot-web-ai

# 设置开机自启
sudo systemctl enable iot-web-ai

# 查看状态
sudo systemctl status iot-web-ai

# 查看日志
journalctl -u iot-web-ai -f
```

> **注意**：需要为三个服务分别创建 systemd 配置文件，或者使用 `Type=oneshot` 配合脚本启动。

---

## 📝 方法三：使用 nohup（简单但功能有限）

适合临时测试或简单场景。

```bash
# 启动服务并后台运行
nohup npm run home-assistant-AI > /var/log/iot-web-ai.log 2>&1 &

# 查看进程
ps aux | grep node

# 停止服务
pkill -f "node server-control-tcp.js"
pkill -f "node server-status-ws.js"
pkill -f "node server-config.js"
```

---

## ✅ 推荐方案对比

| 特性     | PM2  | systemd | nohup        |
| -------- | ---- | ------- | ------------ |
| 自动重启 | ✅    | ✅       | ❌            |
| 日志管理 | ✅    | ✅       | ⚠️ 需手动配置 |
| 开机自启 | ✅    | ✅       | ❌            |
| 进程监控 | ✅    | ✅       | ❌            |
| 资源限制 | ✅    | ✅       | ❌            |
| 使用难度 | 低   | 中      | 低           |

**推荐选择：**
- **开发/测试环境**：使用 `npm run home-assistant-AI` 或 `npm run pm2-iot`
- **生产环境**：使用 **PM2**（简单易用）或 **systemd**（系统级集成）

---

## 📌 生产环境最佳实践

1. **使用 PM2** 管理进程，配合 `pm2 startup` 和 `pm2 save` 实现开机自启
2. **配置日志轮转**：PM2 默认日志会不断增长，建议配置日志轮转
3. **设置资源限制**：使用 `max_memory_restart` 防止内存泄漏
4. **监控告警**：配合 PM2 Plus 或其他监控工具实现告警
5. **使用 .env 文件**：管理敏感配置，不要硬编码

```bash
# 日志轮转配置示例
pm2 install pm2-logrotate
pm2 set pm2-logrotate:max_size 10M
pm2 set pm2-logrotate:retain 7
```





{
  "scripts": {
    // ============ 开发模式：直接启动（需要多个终端） ============
    "start": "node server-control-tcp.js",        // 启动控制服务（端口3002）：定时任务管理、设备控制API
    "status": "node server-status-ws.js",        // 启动状态服务（端口8090）：WebSocket实时状态推送
    "config": "node server-config.js",           // 启动配置服务（端口3001）：设备配置管理
    "home-assistant-AI": "concurrently \"npm:start\" \"npm:status\" \"npm:config\"",  // 同时启动三个服务（需安装concurrently）

    // ============ PM2生产模式：后台启动（推荐） ============
    "pm2-ctl": "pm2 start npm --name AI-CTL-server -- run start",  // PM2启动控制服务
    "pm2-sta": "pm2 start npm --name AI-STA-server -- run status",  // PM2启动状态服务
    "pm2-cfg": "pm2 start npm --name AI-CFG-server -- run config",  // PM2启动配置服务
    "pm2-iot": "pm2 start npm --name AI-iot-Server -- run home-assistant-AI",  // PM2启动全部服务（一键启动）
    "pm2-list": "pm2 list",                     // 查看PM2管理的所有进程状态
    "pm2-logs": "pm2 logs",                     // 查看PM2进程实时日志
    "pm2-stop": "pm2 delete all",               // 停止并删除所有PM2进程
    
    // ============ 服务停止命令 ============
    "stop-ctl": "pm2 delete AI-CTL-server",     // 停止控制服务（单个）
    "stop-sta": "pm2 delete AI-STA-server",     // 停止状态服务（单个）
    "stop-cfg": "pm2 delete AI-CFG-server",     // 停止配置服务（单个）
    "stop-all": "npm run pm2-stop"              // 停止所有服务（快捷命令）
  }
}



# 日志轮转

**配置 PM2 日志轮转**可以有效防止日志文件无限增长，以下是完整的配置步骤：

---

## 🚀 方法一：使用 PM2 官方日志轮转插件（推荐）

### 1. 安装日志轮转插件
```bash
# 安装 pm2-logrotate 插件
pm2 install pm2-logrotate
```

### 2. 配置轮转参数

```bash
# 设置日志文件最大大小（如 10MB）
pm2 set pm2-logrotate:max_size 10M

# 设置保留的日志文件数量（如保留最近7个）
pm2 set pm2-logrotate:retain 7

# 设置轮转间隔时间（如每天凌晨3点轮转）
pm2 set pm2-logrotate:rotateInterval '0 3 * * *'

# 设置是否压缩归档日志（推荐开启）
pm2 set pm2-logrotate:compress true

# 设置是否在文件达到最大大小时强制轮转
pm2 set pm2-logrotate:rotateModule true

# 设置日志文件名格式
pm2 set pm2-logrotate:dateFormat YYYY-MM-DD_HH-mm-ss
```

### 3. 常用配置项说明

| 配置项           | 说明                     | 默认值              |
| ---------------- | ------------------------ | ------------------- |
| `max_size`       | 单个日志文件最大大小     | 10M                 |
| `retain`         | 保留的日志文件数量       | 30                  |
| `rotateInterval` | 定时轮转时间（cron格式） | 每天凌晨0点         |
| `compress`       | 是否压缩归档日志         | false               |
| `rotateModule`   | 是否轮转 pm2 模块日志    | true                |
| `dateFormat`     | 归档日志日期格式         | YYYY-MM-DD_HH-mm-ss |

### 4. 查看当前配置
```bash
pm2 conf
```

---

## 📝 方法二：使用 Linux 系统的 logrotate（更灵活）

### 1. 创建 logrotate 配置文件

创建 `/etc/logrotate.d/pm2-iot`：

```bash
/path/to/your/project/v8/.pm2/logs/*.log {
    daily                    # 每天轮转
    missingok                # 如果日志文件不存在，不报错
    rotate 7                 # 保留7天日志
    compress                 # 压缩归档日志
    delaycompress            # 延迟压缩（保留最新归档不压缩）
    dateext                  # 使用日期作为扩展名
    dateformat -%Y%m%d       # 日期格式
    size 10M                 # 文件达到10MB时强制轮转
    sharedscripts            # 轮转前后只执行一次脚本
    postrotate
        pm2 reloadLogs       # 重新加载日志文件
    endscript
}
```

### 2. 测试配置
```bash
# 手动执行一次轮转测试
logrotate -f /etc/logrotate.d/pm2-iot

# 验证轮转结果
ls -la /path/to/your/project/v8/.pm2/logs/
```

---

## 🔧 方法三：在 PM2 配置文件中设置

创建或修改 `ecosystem.config.js`：

```javascript
module.exports = {
  apps: [
    {
      name: 'AI-CTL-server',
      script: 'server-control-tcp.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      // 日志配置
      error_file: './logs/ctl-error.log',
      out_file: './logs/ctl-out.log',
      merge_logs: true,
      log_date_format: 'YYYY-MM-DD HH:mm:ss',
      env: {
        NODE_ENV: 'production'
      }
    },
    // ... 其他服务配置
  ],
  // 日志轮转配置
  deploy: {
    production: {
      user: 'your_user',
      host: 'your_server',
      ref: 'origin/master',
      repo: 'your_repo',
      path: '/path/to/production',
      'post-deploy': 'npm install && pm2 reload ecosystem.config.js --env production'
    }
  }
};
```

---

## 📊 日志文件位置

PM2 默认日志路径：
```
~/.pm2/logs/
├── AI-CTL-server-out.log    # 控制服务标准输出
├── AI-CTL-server-error.log  # 控制服务错误日志
├── AI-STA-server-out.log    # 状态服务标准输出
├── AI-STA-server-error.log  # 状态服务错误日志
├── AI-CFG-server-out.log    # 配置服务标准输出
└── AI-CFG-server-error.log  # 配置服务错误日志
```

---

## 🧹 日志清理维护

```bash
# 手动清理超过30天的日志
find /path/to/logs -name "*.log" -type f -mtime +30 -delete

# 查看日志大小
du -sh /path/to/logs

# 查看日志内容
pm2 logs AI-CTL-server       # 查看单个服务日志
pm2 logs --lines 100        # 查看最近100行日志
pm2 flush                   # 清空所有日志
```

---

## ✅ 推荐配置总结

```bash
# 1. 安装日志轮转插件
pm2 install pm2-logrotate

# 2. 配置轮转参数
pm2 set pm2-logrotate:max_size 10M
pm2 set pm2-logrotate:retain 7
pm2 set pm2-logrotate:compress true
pm2 set pm2-logrotate:rotateInterval '0 3 * * *'

# 3. 验证配置
pm2 conf | grep logrotate
```

> **提示**：建议同时使用 `pm2-logrotate` 和系统 `logrotate`，形成双层防护，确保日志不会无限增长。



# 内存管理


**`max_memory_restart`** 是 PM2 提供的一个重要参数，用于**在进程内存占用达到阈值时自动重启**，从而有效防止内存泄漏导致的服务崩溃。

---

## 🚀 基本概念

### 什么是内存泄漏？
内存泄漏是指程序在运行过程中，分配的内存没有被正确释放，导致内存占用持续增长，最终耗尽系统资源。

### `max_memory_restart` 的作用
当进程的内存占用超过设定的阈值时，PM2 会**自动重启该进程**，释放占用的内存，恢复服务正常运行。

---

## 🔧 配置方法

### 方法一：在 PM2 命令中设置

```bash
# 启动服务时设置内存限制（例如 500MB）
pm2 start npm --name AI-CTL-server --run start -- --max_memory_restart 500M

# 或者使用环境变量
pm2 start npm --name AI-CTL-server --run start -- -e MAX_MEMORY=500M
```

### 方法二：在 `ecosystem.config.js` 中配置（推荐）

创建或修改项目根目录下的 `ecosystem.config.js` 文件：

```javascript
module.exports = {
  apps: [
    {
      name: 'AI-CTL-server',
      script: 'server-control-tcp.js',
      instances: 1,
      autorestart: true,
      watch: false,
      // 设置内存限制（支持 K, M, G 单位）
      max_memory_restart: '500M',  // 内存超过 500MB 时自动重启
      env: {
        NODE_ENV: 'production'
      }
    },
    {
      name: 'AI-STA-server',
      script: 'server-status-ws.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '300M',  // 状态服务内存需求较低
      env: {
        NODE_ENV: 'production'
      }
    },
    {
      name: 'AI-CFG-server',
      script: 'server-config.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '200M',  // 配置服务内存需求最低
      env: {
        NODE_ENV: 'production'
      }
    }
  ]
};
```

### 方法三：使用 PM2 配置命令

```bash
# 设置全局内存限制
pm2 set pm2:max_memory_restart 500M

# 为特定进程设置内存限制
pm2 restart AI-CTL-server --max-memory-restart 500M
```

---

## 📊 内存单位说明

| 单位 | 说明 | 示例            |
| ---- | ---- | --------------- |
| `K`  | KB   | `512K` = 512 KB |
| `M`  | MB   | `500M` = 500 MB |
| `G`  | GB   | `2G` = 2 GB     |

---

## ✅ 最佳实践

### 1. 合理设置阈值

根据服务类型和资源需求设置不同的阈值：

| 服务类型 | 推荐阈值    | 说明                             |
| -------- | ----------- | -------------------------------- |
| 控制服务 | 500M - 1G   | 处理定时任务，内存需求中等       |
| 状态服务 | 300M - 500M | WebSocket 连接，内存随连接数增长 |
| 配置服务 | 200M - 300M | 配置管理，内存需求较低           |

### 2. 监控内存使用

```bash
# 查看进程内存使用情况
pm2 monit

# 查看详细内存统计
pm2 show AI-CTL-server

# 查看所有进程状态（包含内存信息）
pm2 list
```

### 3. 结合日志分析

```bash
# 查看重启日志
pm2 logs AI-CTL-server --lines 100

# 搜索内存相关日志
pm2 logs AI-CTL-server | grep -i memory
```

### 4. 设置重启延迟

```javascript
module.exports = {
  apps: [
    {
      name: 'AI-CTL-server',
      script: 'server-control-tcp.js',
      max_memory_restart: '500M',
      restart_delay: 1000,  // 重启前延迟 1 秒
      kill_timeout: 5000,   // 强制杀死进程前等待 5 秒
      wait_ready: true,     // 等待应用就绪
      listen_timeout: 30000 // 就绪超时时间
    }
  ]
};
```

---

## 🚨 注意事项

### 1. 不是解决方案
`max_memory_restart` 只是**临时缓解**内存泄漏的手段，不能替代根本修复。需要：
- 使用内存分析工具（如 `heapdump`, `clinic.js`）定位泄漏点
- 优化代码，正确释放资源

### 2. 避免误触发
设置阈值时要考虑：
- 服务正常运行时的内存峰值
- GC（垃圾回收）导致的内存波动
- 建议设置为正常内存使用的 2-3 倍

### 3. 配合其他策略

```javascript
module.exports = {
  apps: [
    {
      name: 'AI-CTL-server',
      script: 'server-control-tcp.js',
      max_memory_restart: '500M',
      autorestart: true,        // 自动重启
      watch: false,            // 关闭文件监听
      ignore_watch: ['node_modules', '.git'],
      instances: 1,            // 单实例
      exec_mode: 'fork'        // fork 模式
    }
  ]
};
```

---

## 📈 内存泄漏排查工具

### 1. Node.js 内置工具

```bash
# 启用堆快照
node --inspect server-control-tcp.js

# 使用 Chrome DevTools 分析
# 打开 chrome://inspect
```

### 2. clinic.js（推荐）

```bash
# 安装 clinic.js
npm install -g clinic

# 运行服务并分析
clinic doctor -- node server-control-tcp.js

# 生成火焰图
clinic flame -- node server-control-tcp.js
```

### 3. heapdump

```javascript
// 在代码中添加堆快照
const heapdump = require('heapdump');

// 定时生成快照
setInterval(() => {
  heapdump.writeSnapshot(`./heap-${Date.now()}.heapsnapshot`);
}, 300000); // 每5分钟生成一次
```

---

## 🎯 配置示例总结

```javascript
// ecosystem.config.js
module.exports = {
  apps: [
    {
      name: 'AI-CTL-server',
      script: 'server-control-tcp.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '500M',
      restart_delay: 1000,
      kill_timeout: 5000,
      env: {
        NODE_ENV: 'production'
      }
    },
    {
      name: 'AI-STA-server',
      script: 'server-status-ws.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '300M',
      env: {
        NODE_ENV: 'production'
      }
    },
    {
      name: 'AI-CFG-server',
      script: 'server-config.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '200M',
      env: {
        NODE_ENV: 'production'
      }
    }
  ]
};
```

启动命令：
```bash
pm2 start ecosystem.config.js
```

> **提示**：建议定期监控内存使用趋势，根据实际情况调整 `max_memory_restart` 的阈值，平衡稳定性和性能。



# 监控和报警


实现 IoT 服务的监控告警可以帮助及时发现问题并采取行动。以下是使用 **PM2 Plus** 和其他主流监控工具的配置方法：

---

## 🚀 方法一：使用 PM2 Plus（官方云监控）

PM2 Plus 是 PM2 官方提供的云端监控平台，支持实时监控、告警通知、性能分析等功能。

### 1. 注册 PM2 Plus

```bash
# 安装 PM2 Plus 客户端
pm2 install pm2-plus

# 登录并连接到云端
pm2 link <your-secret-key> <your-public-key>
```

### 2. 配置告警规则

登录 [PM2 Plus 控制台](https://pm2.io/)，在 **Alerting** 页面配置告警规则：

#### 告警规则配置示例

| 监控指标       | 阈值设置   | 告警条件             |
| -------------- | ---------- | -------------------- |
| **内存使用率** | > 80%      | 进程内存占用超过阈值 |
| **CPU 使用率** | > 90%      | CPU 占用过高         |
| **重启次数**   | > 5次/小时 | 服务频繁重启         |
| **响应时间**   | > 500ms    | API 响应超时         |
| **进程异常**   | 任意       | 进程崩溃或无响应     |

### 3. 告警通知方式

PM2 Plus 支持多种通知渠道：

```bash
# 配置邮件通知
pm2 conf set pm2-plus:email_notification true

# 配置 Slack 通知
pm2 conf set pm2-plus:slack_webhook https://hooks.slack.com/services/xxx

# 配置 Telegram 通知
pm2 conf set pm2-plus:telegram_bot_token xxx
pm2 conf set pm2-plus:telegram_chat_id xxx

# 配置 Webhook 通知
pm2 conf set pm2-plus:webhook_url https://your-server.com/webhook
```

---

## 📊 方法二：使用 Prometheus + Grafana（自建监控）

### 1. 安装依赖

```bash
# 安装 Prometheus 客户端
npm install prom-client

# 安装 PM2 Exporter
pm2 install pm2-exporter
```

### 2. 配置 Prometheus

创建 `prometheus.yml`：

```yaml
scrape_configs:
  - job_name: 'pm2'
    static_configs:
      - targets: ['localhost:9209']  # PM2 Exporter 默认端口
    scrape_interval: 15s
```

### 3. 配置 Grafana 告警规则

在 Grafana 中创建告警规则：

```json
{
  "alert": {
    "name": "PM2 Memory Alert",
    "conditions": [
      {
        "evaluator": {
          "type": "gt",
          "params": ["80"]
        },
        "query": {
          "params": ["A", "5m", "now"]
        },
        "reducer": {
          "type": "avg",
          "params": []
        },
        "type": "query"
      }
    ],
    "frequency": "60s",
    "handler": 1,
    "message": "PM2 内存使用率超过 80%",
    "name": "PM2 Memory Alert",
    "noDataState": "no_data",
    "notifications": [
      {
        "id": 1
      }
    ]
  }
}
```

### 4. 设置告警通知

在 Grafana 中配置通知渠道：
- **邮件通知**：配置 SMTP 服务器
- **Slack**：添加 Slack webhook
- **钉钉**：添加钉钉机器人
- **企业微信**：添加企业微信机器人

---

## 📱 方法三：使用 Datadog（云端监控）

### 1. 安装 Datadog Agent

```bash
# 安装 Datadog Agent
DD_API_KEY=your-api-key bash -c "$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)"

# 安装 Node.js 集成
npm install dd-trace --save
```

### 2. 配置 Datadog 告警

在 Datadog 控制台创建监控告警：

```python
# datadog_metrics.py
from datadog import initialize, api

options = {
    'api_key': 'your-api-key',
    'app_key': 'your-app-key'
}

initialize(**options)

# 创建监控
api.Monitor.create(
    type='metric alert',
    query='avg(last_5m):avg:pm2.process.memory{*} by {process} > 80',
    name='PM2 Memory Alert',
    message='PM2 内存使用率超过 80%\n\n{{#is_alert}}@slack-channel{{/is_alert}}',
    tags=['pm2', 'memory'],
    options={
        'notify_no_data': False,
        'no_data_timeframe': 10,
        'notify_audit': True
    }
)
```

---

## 🔔 方法四：自建简易告警系统

### 1. 使用 Node.js 编写告警脚本

```javascript
// alert.js
const os = require('os');
const nodemailer = require('nodemailer');

// 配置邮件发送
const transporter = nodemailer.createTransport({
  service: 'Gmail',
  auth: {
    user: 'your-email@gmail.com',
    pass: 'your-password'
  }
});

// 监控函数
function checkMemory() {
  const totalMemory = os.totalmem();
  const freeMemory = os.freemem();
  const usedPercent = ((totalMemory - freeMemory) / totalMemory) * 100;
  
  if (usedPercent > 80) {
    sendAlert('内存告警', `内存使用率: ${usedPercent.toFixed(2)}%`);
  }
}

// 发送告警邮件
function sendAlert(subject, message) {
  transporter.sendMail({
    from: 'Monitor <your-email@gmail.com>',
    to: 'admin@example.com',
    subject: subject,
    text: message
  });
}

// 定时检查（每5分钟）
setInterval(checkMemory, 5 * 60 * 1000);
```

### 2. 使用 PM2 启动告警服务

```bash
pm2 start alert.js --name alert-monitor
```

---

## ✅ 告警配置最佳实践

### 1. 设置合理的告警阈值

| 指标       | 建议阈值   | 说明                |
| ---------- | ---------- | ------------------- |
| 内存使用率 | > 80%      | 预留 20% 缓冲空间   |
| CPU 使用率 | > 90%      | 持续超过 5 分钟触发 |
| 进程重启   | > 5次/小时 | 频繁重启可能有问题  |
| 响应时间   | > 1000ms   | API 响应超时        |
| 磁盘空间   | > 90%      | 磁盘即将满          |

### 2. 设置告警级别

```json
{
  "critical": {
    "memory": "> 90%",
    "cpu": "> 95%",
    "action": "立即通知 + 自动重启"
  },
  "warning": {
    "memory": "> 80%",
    "cpu": "> 85%",
    "action": "通知管理员"
  },
  "info": {
    "memory": "> 70%",
    "cpu": "> 75%",
    "action": "记录日志"
  }
}
```

### 3. 配置告警升级策略

```
Level 1: 首次告警 → 发送邮件通知
Level 2: 5分钟未恢复 → 发送 Slack 通知
Level 3: 15分钟未恢复 → 发送短信通知
Level 4: 30分钟未恢复 → 自动重启服务
Level 5: 1小时未恢复 → 电话通知管理员
```

### 4. 设置告警静默期

```javascript
// 避免告警风暴
const alertHistory = {};

function shouldAlert(alertType) {
  const now = Date.now();
  const lastAlert = alertHistory[alertType];
  
  if (!lastAlert || now - lastAlert > 300000) { // 5分钟静默期
    alertHistory[alertType] = now;
    return true;
  }
  return false;
}
```

---

## 📋 告警通知模板示例

### 邮件通知
```
【IoT服务告警】

告警级别: 严重
告警类型: 内存使用率过高
告警时间: 2024-01-15 10:30:00
服务名称: AI-CTL-server
当前值: 92%
阈值: 80%

建议操作:
1. 检查服务日志
2. 考虑重启服务
3. 分析内存泄漏原因

服务地址: http://192.168.6.40:3002
```

### Slack 通知
```
🚨 *IoT服务告警* 🚨

• 级别: 严重
• 类型: 内存使用率过高
• 服务: AI-CTL-server
• 当前: 92% (阈值: 80%)
• 时间: 2024-01-15 10:30:00

🔗 [查看详情](http://monitor.example.com)
```

---

## 🎯 推荐监控工具对比

| 工具                     | 类型 | 优点               | 缺点     |
| ------------------------ | ---- | ------------------ | -------- |
| **PM2 Plus**             | 云端 | 集成度高，配置简单 | 需要付费 |
| **Prometheus + Grafana** | 自建 | 高度定制，免费     | 部署复杂 |
| **Datadog**              | 云端 | 功能强大，生态完善 | 费用较高 |
| **自建脚本**             | 自建 | 灵活定制，完全免费 | 功能有限 |

**推荐选择：**
- **开发/测试环境**：使用 PM2 Plus 免费版或自建脚本
- **生产环境**：使用 Prometheus + Grafana（自建）或 Datadog（云端）

---

## 📝 配置检查清单

```bash
# 1. 确认监控服务正常运行
pm2 list

# 2. 检查告警配置
pm2 conf

# 3. 测试告警功能
pm2 trigger AI-CTL-server --alert memory

# 4. 验证通知渠道
echo "Test Alert" | mail -s "Test" admin@example.com

# 5. 查看告警历史
pm2 logs AI-CTL-server | grep -i alert
```

> **提示**：建议定期演练告警流程，确保在真正出现问题时能够及时收到通知并采取正确的应对措施。

