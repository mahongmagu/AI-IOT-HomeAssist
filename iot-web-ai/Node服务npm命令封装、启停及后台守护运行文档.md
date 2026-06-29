# Node服务npm命令封装、启停及后台守护运行文档

# 一、封装npm命令服务（简化服务启动操作）

## 1\.1 核心目的

将复杂的Node服务启动命令（如多进程启动、指定入口文件），封装成简单的`npm run xxx`命令，实现命令简化、团队操作统一、后续维护便捷，避免重复输入冗长命令。

## 1\.2 操作步骤（核心：修改package\.json）

打开项目根目录下的`package\.json`文件，找到`\&\#34;scripts\&\#34;`节点，按需求添加/修改脚本命令，以下是适配当前项目（iot\-web\-ai，版本2\.2\.1）的最新配置（与实际项目配置完全一致，可直接参考）：

```json
"scripts": {
  "start": "node server-control-tcp.js",          // 普通启动主服务（项目主入口文件）
  "status": "node server-status-ws.js",           // 启动状态服务（更新为ws相关状态服务）
  "config": "node server-config.js",              // 启动配置服务
  "home-assistant": "concurrently \"npm:start\" \"npm:status\" \"npm:config\"" // 一键启动多进程服务（原ha命令更新为标准命名）
}
```

补充说明：项目当前依赖已包含`concurrently@9\.2\.1`（devDependencies）、`nodemon@3\.0\.1`（devDependencies），可直接使用相关脚本，无需额外安装。

## 1\.3 封装后常用命令

- 普通启动主服务：`npm run start`

- 一键启动多进程服务（home\-assistant）：`npm run home\-assistant`（替换原ha命令，与package\.json保持一致）

- 开发环境热更新启动：需手动添加脚本`\&\#34;dev\&\#34;: \&\#34;nodemon server\-control\-tcp\.js\&\#34;`，添加后执行`npm run dev`（项目已安装nodemon，可直接使用）

- pm2后台启动多进程服务：需手动添加脚本`\&\#34;pm2\-ha\&\#34;: \&\#34;pm2 start npm \-\-name iot\-ha \-\- run home\-assistant\&\#34;`，添加后执行`npm run pm2\-ha`

- 查看pm2后台服务：需手动添加脚本`\&\#34;pm2\-list\&\#34;: \&\#34;pm2 list\&\#34;`，添加后执行`npm run pm2\-list`

备注：若需使用pm2相关便捷脚本，可将以下内容补充至package\.json的scripts节点：

```json
"pm2": "pm2 start npm --name iot-server -- run start",         // pm2后台启动主服务
"pm2-ha": "pm2 start npm --name iot-ha -- run home-assistant", // pm2后台启动多进程服务
"pm2-list": "pm2 list",                                        // 查看pm2后台所有服务
"pm2-logs": "pm2 logs",                                        // 实时查看pm2后台服务日志
"pm2-stop": "pm2 delete all"                                   // 停止并删除所有pm2后台服务"
```

# 二、Node服务启停操作（两种运行模式对应）

Node服务分为「普通运行」和「pm2后台守护运行」两种模式，启停方式不同，分别对应操作如下：

## 2\.1 普通运行模式（npm run start/home\-assistant）

适用于开发调试，关闭终端后服务会停止，启停操作简单：

- 启动：执行对应npm命令（如`npm run start`、`npm run home\-assistant`）

- 停止：在启动服务的终端中，按`Ctrl \+ C`（一次不行可按两次），即可立即停止服务

## 2\.2 pm2后台守护运行模式（需补充pm2相关脚本）

适用于生产环境，关闭终端后服务仍会后台运行，启停需通过pm2命令；若已补充上述pm2便捷脚本，可直接使用封装命令：

### 2\.2\.1 基础启停命令

- 启动：执行封装好的pm2命令（如`npm run pm2`、`npm run pm2\-ha`），未封装则执行`pm2 start npm \-\-name \&\#34;iot\-ha\&\#34; \-\- run home\-assistant`

- 临时停止（不删除服务，可重启）：`pm2 stop all`（停止所有服务）或`pm2 stop 服务名称/ID`（停止指定服务）

- 彻底停止（删除服务，需重新启动）：`pm2 delete all`（删除所有服务）或`pm2 delete 服务名称/ID`（删除指定服务）

### 2\.2\.2 便捷操作（通过封装的npm命令）

- 查看后台服务：`npm run pm2\-list`（需补充对应脚本）

- 查看服务日志：`npm run pm2\-logs`（需补充对应脚本）

- 彻底停止所有服务：`npm run pm2\-stop`（需补充对应脚本）

# 三、设置Node程序作为Daemon（后台守护进程）运行

Daemon（守护进程）即后台常驻进程，关闭终端、重启电脑后可自动恢复运行，适用于生产环境，推荐使用行业标准工具「pm2」，操作简单且功能完善。项目已安装核心依赖，可直接使用pm2。

## 3\.1 安装pm2（全局安装，一次安装终身可用）

需用**管理员身份**打开终端（Windows：右键开始菜单→Windows PowerShell\(管理员\)；Linux：sudo权限），执行以下命令：

```bash
npm install pm2 -g
```

## 3\.2 后台守护启动Node服务

进入项目根目录（如：`cd D:\\\.openclaw\\workspace\\iot\-web\-ai\\v8`），可通过两种方式启动：

### 3\.2\.1 直接使用pm2命令（不依赖npm脚本封装）

- 启动主服务：`pm2 start server\-control\-tcp\.js \-\-name \&\#34;iot\-server\&\#34;`（\-\-name指定服务名称，方便后续管理，项目主入口为server\-control\-tcp\.js）

- 启动多进程服务（home\-assistant）：`pm2 start npm \-\-name \&\#34;iot\-ha\&\#34; \-\- run home\-assistant`（通过pm2启动npm脚本，与package\.json中多进程命令一致）

### 3\.2\.2 使用封装好的npm命令（推荐，更简洁）

若已在package\.json中补充pm2相关脚本，直接执行：

- 后台启动主服务：`npm run pm2`

- 后台启动多进程服务：`npm run pm2\-ha`

## 3\.3 pm2核心常用命令（必记）

```bash
pm2 list              # 查看所有后台运行的服务（显示服务ID、名称、状态等）
pm2 logs              # 实时查看所有服务的日志（按Ctrl+C退出）
pm2 logs 服务名称/ID   # 查看指定服务的日志
pm2 restart 服务名称/ID # 重启指定服务
pm2 restart all       # 重启所有服务
pm2 stop 服务名称/ID   # 临时停止指定服务
pm2 stop all          # 临时停止所有服务
pm2 delete 服务名称/ID # 彻底删除指定服务
pm2 delete all        # 彻底删除所有服务
```

## 3\.4 设置开机自启（永久后台，关键步骤）

为确保电脑重启后，后台服务自动启动，需执行以下两步（管理员终端执行）：

```bash
pm2 startup            # 生成开机自启配置（自动适配Windows/Linux系统）
pm2 save               # 保存当前后台运行的服务列表，开机后自动恢复
```

## 3\.5 注意事项

- Windows系统必须用管理员身份安装和启动pm2，否则可能出现权限不足问题；项目依赖的concurrently、nodemon已安装，无需额外执行npm install。

- pm2日志默认存储在系统指定目录，可通过`pm2 logs`快速排查服务报错；项目核心依赖包括pinyin@4\.0\.0、ws@8\.14\.2等，确保依赖安装完整（执行npm install可安装所有依赖）。

- 若服务崩溃，pm2会自动重启服务，无需手动干预，保障服务稳定性；启动多进程服务时，确保concurrently依赖正常（项目已安装，版本9\.2\.1）。

- package\.json中status脚本已更新为`node server\-status\-ws\.js`，启动状态服务时需确保该文件存在，避免启动报错。

# 四、总结（快速查阅指南）

|操作场景|推荐命令|
|---|---|
|封装npm命令|修改package\.json的scripts节点（参考1\.2最新配置）|
|普通启动多进程服务|npm run home\-assistant（与package\.json一致）|
|普通启动停止服务|启动：npm run xxx；停止：Ctrl \+ C|
|后台启动多进程服务|pm2 start npm \-\-name \&\#34;iot\-ha\&\#34; \-\- run home\-assistant（或补充脚本后用npm run pm2\-ha）|
|后台停止所有服务|pm2 delete all（或补充脚本后用npm run pm2\-stop）|
|设置开机自启|pm2 startup → pm2 save|
|查看后台服务/日志|pm2 list / pm2 logs（或补充脚本后用npm run pm2\-list/pm2\-logs）|

> （注：文档部分内容可能由 AI 生成）
