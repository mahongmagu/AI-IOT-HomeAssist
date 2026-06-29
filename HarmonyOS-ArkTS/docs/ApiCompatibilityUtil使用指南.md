# ApiCompatibilityUtil 快速参考

## 📌 常用方法速查表

### UI组件
| 方法 | SysCap | 说明 |
|------|--------|------|
| `isRouterSupported()` | ArkUI.Full | 路由跳转 |
| `isPromptActionSupported()` | ArkUI.Full | Toast提示 |
| `isListSupported()` | ArkUI.Full | List组件 |
| `isGridSupported()` | ArkUI.Full | Grid组件 |
| `isAnimationSupported()` | ArkUI.Full | 动画效果 |

### 网络
| 方法 | SysCap | 说明 |
|------|--------|------|
| `isHttpSupported()` | NetStack | HTTP请求 |
| `isWebSocketSupported()` | NetStack | WebSocket |

### 媒体
| 方法 | SysCap | 说明 |
|------|--------|------|
| `isCameraSupported()` | Camera.Core | 相机 |
| `isMicrophoneSupported()` | Audio.Core | 麦克风 |
| `isAudioPlaybackSupported()` | Audio.Core | 音频播放 |
| `isVideoPlaybackSupported()` | Media.Core | 视频播放 |
| `isMediaLibrarySupported()` | FileManager | 媒体库 |

### 传感器
| 方法 | SysCap | 说明 |
|------|--------|------|
| `isAccelerometerSupported()` | Sensor | 加速度传感器 |
| `isGyroscopeSupported()` | Sensor | 陀螺仪 |
| `isLightSensorSupported()` | Sensor | 光线传感器 |

### 位置服务
| 方法 | SysCap | 说明 |
|------|--------|------|
| `isLocationSupported()` | Location.Core | 地理位置 |
| `isGeocodingSupported()` | Location.Geocoder | 地理编码 |

### 通信
| 方法 | SysCap | 说明 |
|------|--------|------|
| `isBluetoothSupported()` | Bluetooth.Core | 蓝牙 |
| `isNFCSupported()` | NFC.Core | NFC |
| `isWiFiSupported()` | WiFi.Core | WiFi |

### 电话
| 方法 | SysCap | 说明 |
|------|--------|------|
| `isCallSupported()` | CallManager | 拨打电话 |
| `isSmsSupported()` | SmsMms | 发送短信 |

### AI
| 方法 | SysCap | 说明 |
|------|--------|------|
| `isSpeechRecognitionSupported()` | SpeechRecognizer | 语音识别 |
| `isTextToSpeechSupported()` | TextToSpeech | 语音合成 |
| `isFaceRecognitionSupported()` | FaceRecognizer | 人脸识别 |
| `isOCRSupported()` | GeneralRecognizer | 文字识别 |

---

## 🚀 快速使用

### 1. 单个检查
```typescript
if (ApiCompatibilityUtil.isCameraSupported()) {
  // 调用相机API
}
```

### 2. 批量检查
```typescript
const results = ApiCompatibilityUtil.batchCheck([
  'SystemCapability.ArkUI.ArkUI.Full',
  'SystemCapability.Communication.NetStack'
]);
```

### 3. 全部支持检查
```typescript
if (ApiCompatibilityUtil.checkAllSupported([
  'SystemCapability.ArkUI.ArkUI.Full',
  'SystemCapability.Communication.NetStack'
])) {
  // 所有能力都支持
}
```

### 4. 至少一个支持检查
```typescript
if (ApiCompatibilityUtil.checkAnySupported([
  'SystemCapability.AI.SpeechRecognizer',
  'SystemCapability.AI.TextToSpeech'
])) {
  // 至少支持一个AI能力
}
```

---

## 📝 扩展新方法模板

```typescript
/**
 * 检查是否支持[功能名称]
 */
static is[功能名称]Supported(): boolean {
  try {
    return canIUse('SystemCapability.[模块].[子模块]');
  } catch (error) {
    console.error('Failed to check [功能名称] support:', error);
    return false;
  }
}
```

---

## ⚠️ 注意事项

1. **始终使用 try-catch**: 防止检查失败导致应用崩溃
2. **返回 false 作为默认值**: 不支持时安全降级
3. **记录错误日志**: 便于问题排查
4. **提供替代方案**: 不支持时给用户其他选择

---

## 🔍 如何查找SysCap

### 方法1: 查看API文档
在DevEco Studio中，点击API方法，查看`@syscap`注解

### 方法2: 查看SDK目录
```
SDK路径/sdk/default/openharmony/api/device-define/
├── phone.json      # 手机支持的能力
├── tablet.json     # 平板支持的能力
├── wearable.json   # 手表支持的能力
└── ...
```

### 方法3: 使用DevEco Studio
在代码编辑器中输入`canIUse`，IDE会自动提示可用的SysCap

---

## 💡 最佳实践

### ✅ 推荐写法
```typescript
// 1. 检查能力
if (ApiCompatibilityUtil.isCameraSupported()) {
  // 2. Try-catch保护
  try {
    // 3. 调用API
    camera.takePhoto();
  } catch (error) {
    // 4. 错误处理
    hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to take photo: %{public}s', [error.message]);
  }
} else {
  // 5. 提供替代方案
  promptAction.showToast({ message: '设备不支持相机功能' });
}
```

### ❌ 不推荐写法
```typescript
// 缺少兼容性检查
camera.takePhoto(); // 可能崩溃
```
