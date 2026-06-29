/**
 * ApiCompatibilityUtil 使用示例
 * 
 * 本文件展示如何在项目中使用 ApiCompatibilityUtil 工具类进行API兼容性检查
 */

import { ApiCompatibilityUtil } from './ApiCompatibilityUtil';
import hilog from '@ohos.hilog';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'ApiCompatibilityExample';

/**
 * 示例1: 基础使用 - 单个API检查
 */
export function example1_BasicUsage() {
  // 检查是否支持相机
  if (ApiCompatibilityUtil.isCameraSupported()) {
    // 设备支持相机，可以调用相机API
    console.info('设备支持相机功能');
    // 调用相机相关代码...
  } else {
    // 设备不支持相机，提供替代方案
    console.warn('设备不支持相机功能');
    // 显示提示或使用其他方式...
  }
}

/**
 * 示例2: UI组件兼容性检查
 */
export function example2_UIComponents() {
  // 检查是否支持List组件
  if (ApiCompatibilityUtil.isListSupported()) {
    // 使用List组件
    console.info('使用List组件展示数据');
  } else {
    // 使用其他方式展示数据
    console.info('使用Column + ForEach展示数据');
  }

  // 检查是否支持动画
  if (ApiCompatibilityUtil.isAnimationSupported()) {
    // 使用动画效果
    console.info('启用动画效果');
  } else {
    // 禁用动画
    console.info('禁用动画效果');
  }
}

/**
 * 示例3: 网络功能兼容性检查
 */
export function example3_NetworkFeatures() {
  // 检查HTTP支持
  if (ApiCompatibilityUtil.isHttpSupported()) {
    // 发起HTTP请求
    console.info('发起HTTP请求');
  } else {
    console.error('设备不支持HTTP请求');
  }

  // 检查WebSocket支持
  if (ApiCompatibilityUtil.isWebSocketSupported()) {
    // 建立WebSocket连接
    console.info('建立WebSocket连接');
  } else {
    // 使用轮询或其他方式
    console.info('使用HTTP轮询替代WebSocket');
  }
}

/**
 * 示例4: 媒体功能兼容性检查
 */
export function example4_MediaFeatures() {
  // 检查相机和麦克风
  const hasCamera = ApiCompatibilityUtil.isCameraSupported();
  const hasMicrophone = ApiCompatibilityUtil.isMicrophoneSupported();

  if (hasCamera && hasMicrophone) {
    // 支持录像功能
    console.info('设备支持录像功能');
  } else if (hasCamera) {
    // 仅支持拍照
    console.info('设备仅支持拍照');
  } else {
    // 不支持相机
    console.warn('设备不支持相机');
  }

  // 检查音频播放
  if (ApiCompatibilityUtil.isAudioPlaybackSupported()) {
    console.info('支持音频播放');
  }
}

/**
 * 示例5: 传感器兼容性检查
 */
export function example5_SensorFeatures() {
  // 检查加速度传感器
  if (ApiCompatibilityUtil.isAccelerometerSupported()) {
    // 使用加速度传感器实现摇一摇功能
    console.info('启用摇一摇功能');
  }

  // 检查光线传感器
  if (ApiCompatibilityUtil.isLightSensorSupported()) {
    // 根据环境光调整屏幕亮度
    console.info('启用自动亮度调节');
  }
}

/**
 * 示例6: 位置服务兼容性检查
 */
export function example6_LocationFeatures() {
  // 检查位置服务
  if (ApiCompatibilityUtil.isLocationSupported()) {
    // 获取当前位置
    console.info('获取当前位置');
    
    // 检查地理编码支持
    if (ApiCompatibilityUtil.isGeocodingSupported()) {
      // 支持地址解析
      console.info('支持地址解析');
    }
  } else {
    console.warn('设备不支持位置服务');
  }
}

/**
 * 示例7: 通信功能兼容性检查
 */
export function example7_CommunicationFeatures() {
  // 检查蓝牙
  if (ApiCompatibilityUtil.isBluetoothSupported()) {
    console.info('支持蓝牙功能');
  }

  // 检查NFC
  if (ApiCompatibilityUtil.isNFCSupported()) {
    console.info('支持NFC功能');
  }

  // 检查WiFi
  if (ApiCompatibilityUtil.isWiFiSupported()) {
    console.info('支持WiFi功能');
  }
}

/**
 * 示例8: AI功能兼容性检查
 */
export function example8_AIFeatures() {
  // 检查语音识别
  if (ApiCompatibilityUtil.isSpeechRecognitionSupported()) {
    console.info('支持语音识别');
  } else {
    console.warn('不支持语音识别，请使用文字输入');
  }

  // 检查语音合成
  if (ApiCompatibilityUtil.isTextToSpeechSupported()) {
    console.info('支持语音播报');
  }

  // 检查人脸识别
  if (ApiCompatibilityUtil.isFaceRecognitionSupported()) {
    console.info('支持人脸识别登录');
  }

  // 检查OCR
  if (ApiCompatibilityUtil.isOCRSupported()) {
    console.info('支持文字识别');
  }
}

/**
 * 示例9: 通用方法使用
 */
export function example9_GenericMethods() {
  // 使用通用检查方法
  const isSupported = ApiCompatibilityUtil.checkCapability('SystemCapability.XXX');
  console.info(`自定义能力检查结果: ${isSupported}`);
}

/**
 * 示例10: 批量检查
 */
export function example10_BatchCheck() {
  // 定义需要检查的能力列表
  const capabilities = [
    'SystemCapability.Multimedia.Camera.Core',
    'SystemCapability.Location.Location.Core',
    'SystemCapability.Communication.Bluetooth.Core',
    'SystemCapability.AI.SpeechRecognizer'
  ];

  // 批量检查
  const results = ApiCompatibilityUtil.batchCheck(capabilities);
  results.forEach((isSupported, sysCap) => {
    console.info(`${sysCap}: ${isSupported ? '支持' : '不支持'}`);
  });

  // 检查是否全部支持
  const allSupported = ApiCompatibilityUtil.checkAllSupported(capabilities);
  console.info(`是否全部支持: ${allSupported}`);

  // 检查是否至少支持一个
  const anySupported = ApiCompatibilityUtil.checkAnySupported(capabilities);
  console.info(`是否至少支持一个: ${anySupported}`);

  // 获取不支持的能力列表
  const unsupported = ApiCompatibilityUtil.getUnsupportedCapabilities(capabilities);
  console.info(`不支持的能力: ${unsupported.join(', ')}`);
}

/**
 * 示例11: 调试输出
 */
export function example11_DebugOutput() {
  // 打印能力支持情况
  ApiCompatibilityUtil.printSupportStatus([
    'SystemCapability.Multimedia.Camera.Core',
    'SystemCapability.Location.Location.Core',
    'SystemCapability.AI.SpeechRecognizer'
  ]);
}

/**
 * 示例12: 实际场景 - 智能家居设备控制
 */
export class SmartHomeController {
  // 检查并初始化设备控制能力
  initializeCapabilities(): void {
    // 检查网络能力
    if (!ApiCompatibilityUtil.isHttpSupported()) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '设备不支持网络功能，无法控制智能设备');
      return;
    }

    // 检查WebSocket（用于实时状态更新）
    const hasWebSocket = ApiCompatibilityUtil.isWebSocketSupported();
    hilog.info(LOG_DOMAIN, LOG_TAG, `WebSocket支持: ${hasWebSocket}`);

    // 检查语音控制能力
    const hasVoiceControl = ApiCompatibilityUtil.isSpeechRecognitionSupported();
    hilog.info(LOG_DOMAIN, LOG_TAG, `语音控制支持: ${hasVoiceControl}`);

    // 根据能力初始化不同功能
    this.initializeFeatures(hasWebSocket, hasVoiceControl);
  }

  private initializeFeatures(hasWebSocket: boolean, hasVoiceControl: boolean): void {
    // 实现初始化逻辑
    if (hasWebSocket) {
      // 初始化WebSocket连接
    }
    if (hasVoiceControl) {
      // 启用语音控制
    }
  }
}

/**
 * 媒体能力接口定义
 */
interface MediaCapabilities {
  canPlayAudio: boolean;
  canPlayVideo: boolean;
  canRecord: boolean;
  canTakePhoto: boolean;
}

/**
 * 示例13: 实际场景 - 媒体应用
 */
export class MediaAppController {
  // 检查媒体能力并初始化
  checkMediaCapabilities(): MediaCapabilities {
    return {
      canPlayAudio: ApiCompatibilityUtil.isAudioPlaybackSupported(),
      canPlayVideo: ApiCompatibilityUtil.isVideoPlaybackSupported(),
      canRecord: ApiCompatibilityUtil.isMicrophoneSupported(),
      canTakePhoto: ApiCompatibilityUtil.isCameraSupported()
    };
  }

  // 根据能力显示不同的UI
  buildMediaUI(): void {
    const capabilities = this.checkMediaCapabilities();

    if (capabilities.canPlayVideo) {
      console.info('显示视频播放按钮');
    }

    if (capabilities.canTakePhoto) {
      console.info('显示拍照按钮');
    }

    if (capabilities.canRecord) {
      console.info('显示录音按钮');
    }
  }
}

/**
 * 示例14: 实际场景 - 地图应用
 */
export class MapAppController {
  // 检查地图相关能力
  checkMapCapabilities(): void {
    // 检查位置服务
    if (!ApiCompatibilityUtil.isLocationSupported()) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '设备不支持位置服务，无法显示当前位置');
      // 显示提示，让用户手动输入位置
      return;
    }

    // 检查传感器（用于指南针功能）
    if (ApiCompatibilityUtil.isAccelerometerSupported()) {
      console.info('启用地图指南针功能');
    }

    // 检查网络（用于地图数据加载）
    if (!ApiCompatibilityUtil.isHttpSupported()) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '设备不支持网络，使用离线地图');
      // 加载离线地图数据
    }
  }
}
