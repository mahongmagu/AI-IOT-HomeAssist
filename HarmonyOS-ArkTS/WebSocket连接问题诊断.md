# WebSocket连接问题诊断

## 问题描述
登录成功后显示"服务器未连接"和"控制连接：未连接"，但HTTP API登录成功。

## 日志分析
从日志可以看到：

### 成功部分：
1. ✅ HTTP API登录成功：`http://192.168.6.40:3002/api/auth` 返回200 OK
2. ✅ 设备数据加载成功：成功获取设备列表
3. ✅ 服务器配置正确：`ServerConfig.isConfigured() = true`

### 失败部分：
1. ❌ WebSocket连接失败：`ws://192.168.6.40:8084/` 连接失败
2. ❌ 错误信息：`Lws client connection error read failed`，错误码200
3. ❌ UI显示"未连接"：因为`isConnected`跟踪WebSocket连接状态

## 根本原因
WebSocket服务器在端口8084上不可用或无法连接。

## 诊断步骤

### 步骤1：检查服务器WebSocket服务
1. 确认服务器是否运行WebSocket服务
2. 确认WebSocket服务监听的端口（可能是8084或其他端口）
3. 确认防火墙是否允许8084端口连接

### 步骤2：测试WebSocket连接
使用以下方法测试WebSocket连接：

#### 方法A：使用浏览器开发者工具
```javascript
// 在浏览器控制台中测试
const ws = new WebSocket('ws://192.168.6.40:8084/');
ws.onopen = () => console.log('WebSocket连接成功');
ws.onerror = (e) => console.error('WebSocket连接失败:', e);
ws.onclose = (e) => console.log('WebSocket连接关闭:', e);
```

#### 方法B：使用curl（如果支持）
```bash
# 测试WebSocket连接
curl --include \
     --no-buffer \
     --header "Connection: Upgrade" \
     --header "Upgrade: websocket" \
     --header "Host: 192.168.6.40:8084" \
     --header "Origin: http://192.168.6.40:3002" \
     --header "Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==" \
     --header "Sec-WebSocket-Version: 13" \
     http://192.168.6.40:8084/
```

#### 方法C：使用telnet/netcat
```bash
# 测试端口是否开放
telnet 192.168.6.40 8084
# 或
nc -zv 192.168.6.40 8084
```

### 步骤3：检查服务器配置
1. 检查服务器是否支持WebSocket协议
2. 检查WebSocket端点路径（当前为`/`）
3. 检查是否需要认证头信息

## 解决方案

### 方案A：修复服务器WebSocket服务
如果服务器没有运行WebSocket服务：
1. 启动WebSocket服务器在8084端口
2. 或者配置现有服务器支持WebSocket

### 方案B：修改客户端WebSocket端口
如果服务器使用不同的WebSocket端口：

#### 修改ServerConfig.ets中的默认端口：
```arkts
// 在entry/src/main/ets/model/ServerConfig.ets中
private static wsPort: number = 8084; // 改为实际端口，如3003
```

#### 或者在saveServerConfig中修改：
```arkts
// 在entry/src/main/ets/pages/Index.ets中
ServerConfig.setWebSocketConfig(3003, '/'); // 改为实际端口
```

### 方案C：添加WebSocket端口配置
在配置页面添加WebSocket端口输入框：

1. 在IndexData模型中添加`wsPort`字段
2. 在配置页面添加WebSocket端口输入
3. 在保存配置时设置WebSocket端口

### 方案D：处理WebSocket连接失败
即使WebSocket失败，仍然显示HTTP连接状态：

1. 修改连接状态逻辑，区分HTTP连接和WebSocket连接
2. 添加重试机制
3. 提供更明确的错误信息

## 临时解决方案

### 1. 禁用WebSocket连接
如果不需要实时状态更新，可以暂时禁用WebSocket连接：

在`initWebSocket`方法中添加条件检查：
```arkts
private initWebSocket(): void {
  // 如果不需要WebSocket，直接返回
  if (!this.enableWebSocket) {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'WebSocket disabled, skipping connection');
    return;
  }
  
  // 原有代码...
}
```

### 2. 修改连接状态显示
修改UI，区分HTTP连接和WebSocket连接状态：
```arkts
// 在MainPage中
if (this.isServerConfigured) {
  Text('● HTTP已连接')
    .fontSize(12)
    .fontColor('#28a745')
    .margin({ left: 10 })
  
  if (this.indexData.isConnected) {
    Text('● WebSocket已连接')
      .fontSize(12)
      .fontColor('#28a745')
      .margin({ left: 10 })
  } else {
    Text('○ WebSocket未连接')
      .fontSize(12)
      .fontColor('#dc3545')
      .margin({ left: 10 })
  }
}
```

## 验证步骤

### 验证HTTP连接：
1. 访问 `http://192.168.6.40:3002/api/auth` (POST请求)
2. 访问 `http://192.168.6.40:3002/api/devices` (GET请求)

### 验证WebSocket连接：
1. 使用WebSocket测试工具连接 `ws://192.168.6.40:8084/`
2. 检查服务器日志是否有WebSocket连接尝试

## 常见问题

### Q1: WebSocket端口被防火墙阻止
**解决**：在服务器防火墙中开放8084端口

### Q2: WebSocket服务器未启动
**解决**：启动WebSocket服务器服务

### Q3: WebSocket路径不正确
**解决**：检查服务器WebSocket端点路径，可能需要如 `/ws`、`/websocket` 等

### Q4: WebSocket需要认证
**解决**：检查是否需要添加认证头或token

## 推荐方案
基于当前情况，推荐：

1. **首先确认服务器WebSocket端口**：联系服务器管理员确认WebSocket服务端口
2. **修改客户端端口配置**：如果端口不同，修改`ServerConfig.setWebSocketConfig()`调用
3. **添加配置选项**：长期解决方案是添加WebSocket端口配置到UI

如果服务器确实没有WebSocket服务，可以考虑：
1. 实现WebSocket服务
2. 或者修改应用使用HTTP轮询代替WebSocket实时更新