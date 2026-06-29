
# IoT设备控制前端认证功能变更文档

## 1. 功能概述

为 IoT 设备控制前端页面（v9版本）增加用户认证功能，通过连接后端MQTT服务器验证用户凭据，实现安全的访问控制。

## 2. 认证流程

### 2.1 .env 文件中凭据为空（MQTT_USERNAME="" 或 MQTT_PASSWORD=""）

```
用户访问页面
    ↓
显示登录窗口，要求输入用户名和密码
    ↓
用户点击登录
    ↓
后端使用用户输入的凭据连接MQTT服务器验证
    ↓
┌─────────────┬─────────────┐
│ 认证成功    │ 认证失败    │
├─────────────┼─────────────┤
│ 进入系统    │ 提示错误    │
│            │ 重新输入    │
└─────────────┴─────────────┘
```

### 2.2 .env 文件中凭据不为空

```
用户访问页面
    ↓
后端自动使用环境变量凭据连接MQTT服务器验证
    ↓
┌─────────────┬─────────────┐
│ 认证成功    │ 认证失败    │
├─────────────┼─────────────┤
│ 直接进入    │ 显示登录    │
│ 系统        │ 窗口        │
└─────────────┴─────────────┘
```

## 3. 修改的文件

### 3.1 后端文件

**文件路径**: `d:\.openclaw\workspace\iot-web-ai\server-control-tcp.js`

| 修改内容                     | 说明                               |
| ---------------------------- | ---------------------------------- |
| 添加 `/api/auth/config` 接口 | 获取认证配置，自动进行MQTT认证     |
| 添加 `/api/auth` 接口        | 验证用户凭据（通过连接MQTT服务器） |

### 3.2 前端文件

**文件路径**: `d:\.openclaw\workspace\iot-web-ai\index.html`

| 修改内容                      | 说明                                   |
| ----------------------------- | -------------------------------------- |
| 添加登录页面                  | 包含用户名输入框、密码输入框、登录按钮 |
| 添加 `checkAuthConfig()` 函数 | 页面加载时自动检查认证配置             |
| 添加 `login()` 函数           | 用户手动登录认证                       |
| 修复变量名拼写错误            | `found上Group` → `foundGroup`          |

## 4. 技术实现细节

### 4.1 后端认证机制

```javascript
// 创建临时MQTT客户端进行认证测试
const authClient = mqtt.connect(MQTT_INTERNAL_SERVER, {
  username: username,
  password: password,
  clientId: `auth-test-${Math.random().toString(16).substr(2, 8)}`,
  clean: true,
  connectTimeout: 3000
});

// 设置超时机制（5秒）
const timeout = setTimeout(() => {
  authClient.end();
  res.status(408).json({ code: 408, msg: '认证超时' });
}, 5000);

authClient.on('connect', () => {
  clearTimeout(timeout);
  authClient.end();
  res.json({ code: 200, msg: '认证成功' });
});

authClient.on('error', (error) => {
  clearTimeout(timeout);
  authClient.end();
  res.status(401).json({ code: 401, msg: '认证失败：用户名或密码错误' });
});
```

### 4.2 前端认证流程

```javascript
// 页面加载时检查认证配置
async function checkAuthConfig() {
  const response = await fetch('/api/auth/config');
  const result = await response.json();
  
  if (result.autoAuthSuccess) {
    // 环境变量凭据自动认证成功，直接进入系统
    isAuthenticated = true;
    document.getElementById('login-page').style.display = 'none';
    document.getElementById('overview-page').style.display = 'block';
    initConfig();
  }
  // 否则显示登录窗口
}
```

## 5. 使用说明

### 5.1 无需认证模式

将 `.env` 文件中的凭据设置为空：

```env
MQTT_USERNAME=
MQTT_PASSWORD=
```

用户访问页面时需要手动输入用户名和密码登录。

### 5.2 自动认证模式

配置 `.env` 文件中的凭据：

```env
MQTT_USERNAME=username
MQTT_PASSWORD=your-mqtt-password
```

用户访问页面时自动使用配置的凭据进行认证，成功则直接进入系统。

### 5.3 认证失败处理

- **环境变量凭据认证失败**：自动显示登录窗口，用户名自动填入，提示"环境变量配置的凭据认证失败，请手动输入正确凭据"
- **用户输入凭据认证失败**：提示"认证失败：用户名或密码错误"

## 6. 错误处理

| 错误类型   | 提示信息                     | 处理方式     |
| ---------- | ---------------------------- | ------------ |
| 凭据错误   | "认证失败：用户名或密码错误" | 重新输入     |
| 连接超时   | "认证超时"                   | 检查网络连接 |
| 服务器错误 | "服务器内部错误"             | 联系管理员   |

## 7. 安全考虑

- 使用 HTTPS/WSS 加密传输凭据
- 临时MQTT客户端使用随机clientId
- 认证成功后立即关闭临时连接
- 错误信息不泄露敏感信息

---

**版本**: v1.0  
**日期**: 2026-05-14  
**适用版本**: IoT Web AI

        

