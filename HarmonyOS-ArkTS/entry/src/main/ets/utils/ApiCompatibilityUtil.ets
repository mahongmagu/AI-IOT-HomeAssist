/**
 * API兼容性检查工具类
 * 用于检查设备是否支持特定的系统能力
 * 
 * 使用示例：
 * // 1. 简单检查
 * if (ApiCompatibilityUtil.isCameraSupported()) {
 *   // 调用相机API
 * }
 * 
 * // 2. 通用检查
 * if (ApiCompatibilityUtil.checkCapability('SystemCapability.XXX')) {
 *   // 调用API
 * }
 * 
 * // 3. 批量检查
 * const results = ApiCompatibilityUtil.batchCheck([
 *   'SystemCapability.ArkUI.ArkUI.Full',
 *   'SystemCapability.Communication.NetStack'
 * ]);
 */
export class ApiCompatibilityUtil {
  // ==================== UI相关 ====================
  
  /**
   * 检查是否支持路由功能
   */
  static isRouterSupported(): boolean {
    try {
      return canIUse('SystemCapability.ArkUI.ArkUI.Full');
    } catch (error) {
      console.error('Failed to check router support:', error);
      return false;
    }
  }

  /**
   * 检查是否支持Toast提示
   */
  static isPromptActionSupported(): boolean {
    try {
      return canIUse('SystemCapability.ArkUI.ArkUI.Full');
    } catch (error) {
      console.error('Failed to check promptAction support:', error);
      return false;
    }
  }

  /**
   * 检查是否支持List组件
   */
  static isListSupported(): boolean {
    try {
      return canIUse('SystemCapability.ArkUI.ArkUI.Full');
    } catch (error) {
      console.error('Failed to check List support:', error);
      return false;
    }
  }

  /**
   * 检查是否支持Grid组件
   */
  static isGridSupported(): boolean {
    try {
      return canIUse('SystemCapability.ArkUI.ArkUI.Full');
    } catch (error) {
      console.error('Failed to check Grid support:', error);
      return false;
    }
  }

  /**
   * 检查是否支持动画
   */
  static isAnimationSupported(): boolean {
    try {
      return canIUse('SystemCapability.ArkUI.ArkUI.Full');
    } catch (error) {
      console.error('Failed to check animation support:', error);
      return false;
    }
  }

  // ==================== 网络相关 ====================

  /**
   * 检查是否支持HTTP网络请求
   */
  static isHttpSupported(): boolean {
    try {
      return canIUse('SystemCapability.Communication.NetStack');
    } catch (error) {
      console.error('Failed to check HTTP support:', error);
      return false;
    }
  }

  /**
   * 检查是否支持WebSocket
   */
  static isWebSocketSupported(): boolean {
    try {
      return canIUse('SystemCapability.Communication.NetStack');
    } catch (error) {
      console.error('Failed to check WebSocket support:', error);
      return false;
    }
  }

  // ==================== 媒体相关 ====================

  /**
   * 检查是否支持相机
   */
  static isCameraSupported(): boolean {
    try {
      return canIUse('SystemCapability.Multimedia.Camera.Core');
    } catch (error) {
      console.error('Failed to check camera support:', error);
      return false;
    }
  }

  /**
   * 检查是否支持麦克风录音
   */
  static isMicrophoneSupported(): boolean {
    try {
      return canIUse('SystemCapability.Multimedia.Audio.Core');
    } catch (error) {
      console.error('Failed to check microphone support:', error);
      return false;
    }
  }

  /**
   * 患查是否支持音频播放
   */
  static isAudioPlaybackSupported(): boolean {
    try {
      return canIUse('SystemCapability.Multimedia.Audio.Core');
    } catch (error) {
      console.error('Failed to check audio playback support:', error);
      return false;
    }
  }

  /**
   * 检查是否支持视频播放
   */
  static isVideoPlaybackSupported(): boolean {
    try {
      return canIUse('SystemCapability.Multimedia.Media.Core');
    } catch (error) {
      console.error('Failed to check video playback support:', error);
      return false;
    }
  }

  /**
   * 检查是否支持媒体库（相册、视频库）
   */
  static isMediaLibrarySupported(): boolean {
    try {
      return canIUse('SystemCapability.FileManagement.FileManager.FwkUtils');
    } catch (error) {
      console.error('Failed to check media library support:', error);
      return false;
    }
  }

  // ==================== 传感器相关 ====================

  /**
   * 检查是否支持加速度传感器
   */
  static isAccelerometerSupported(): boolean {
    try {
      return canIUse('SystemCapability.Sensors.Sensor');
    } catch (error) {
      console.error('Failed to check accelerometer support:', error);
      return false;
    }
  }

  /**
   * 检查是否支持陀螺仪
   */
  static isGyroscopeSupported(): boolean {
    try {
      return canIUse('SystemCapability.Sensors.Sensor');
    } catch (error) {
      console.error('Failed to check gyroscope support:', error);
      return false;
    }
  }

  /**
   * 检查是否支持光线传感器
   */
  static isLightSensorSupported(): boolean {
    try {
      return canIUse('SystemCapability.Sensors.Sensor');
    } catch (error) {
      console.error('Failed to check light sensor support:', error);
      return false;
    }
  }

  // ==================== 位置服务 ====================

  /**
   * 检查是否支持地理位置服务
   */
  static isLocationSupported(): boolean {
    try {
      return canIUse('SystemCapability.Location.Location.Core');
    } catch (error) {
      console.error('Failed to check location support:', error);
      return false;
    }
  }

  /**
   * 检查是否支持地理编码（地址解析）
   */
  static isGeocodingSupported(): boolean {
    try {
      return canIUse('SystemCapability.Location.Location.Geocoder');
    } catch (error) {
      console.error('Failed to check geocoding support:', error);
      return false;
    }
  }

  // ==================== 通信相关 ====================

  /**
   * 检查是否支持蓝牙
   */
  static isBluetoothSupported(): boolean {
    try {
      return canIUse('SystemCapability.Communication.Bluetooth.Core');
    } catch (error) {
      console.error('Failed to check bluetooth support:', error);
      return false;
    }
  }

  /**
   * 检查是否支持NFC
   */
  static isNFCSupported(): boolean {
    try {
      return canIUse('SystemCapability.Communication.NFC.Core');
    } catch (error) {
      console.error('Failed to check NFC support:', error);
      return false;
    }
  }

  /**
   * 检查是否支持WiFi
   */
  static isWiFiSupported(): boolean {
    try {
      return canIUse('SystemCapability.Communication.WiFi.Core');
    } catch (error) {
      console.error('Failed to check WiFi support:', error);
      return false;
    }
  }

  // ==================== 电话相关 ====================

  /**
   * 检查是否支持拨打电话
   */
  static isCallSupported(): boolean {
    try {
      return canIUse('SystemCapability.Telephony.CallManager');
    } catch (error) {
      console.error('Failed to check call support:', error);
      return false;
    }
  }

  /**
   * 检查是否支持发送短信
   */
  static isSmsSupported(): boolean {
    try {
      return canIUse('SystemCapability.Telephony.SmsMms');
    } catch (error) {
      console.error('Failed to check SMS support:', error);
      return false;
    }
  }

  // ==================== 存储相关 ====================

  /**
   * 检查是否支持文件存储
   */
  static isFileStorageSupported(): boolean {
    try {
      return canIUse('SystemCapability.FileManagement.FileManager.FwkUtils');
    } catch (error) {
      console.error('Failed to check file storage support:', error);
      return false;
    }
  }

  /**
   * 检查是否支持关系型数据库
   */
  static isDatabaseSupported(): boolean {
    try {
      return canIUse('SystemCapability.DistributedDataManager.RelationalStore.Core');
    } catch (error) {
      console.error('Failed to check database support:', error);
      return false;
    }
  }

  // ==================== AI相关 ====================

  /**
   * 检查是否支持语音识别
   */
  static isSpeechRecognitionSupported(): boolean {
    try {
      return canIUse('SystemCapability.AI.SpeechRecognizer');
    } catch (error) {
      console.error('Failed to check speech recognition support:', error);
      return false;
    }
  }

  /**
   * 检查是否支持语音合成（TTS）
   */
  static isTextToSpeechSupported(): boolean {
    try {
      return canIUse('SystemCapability.AI.TextToSpeech');
    } catch (error) {
      console.error('Failed to check TTS support:', error);
      return false;
    }
  }

  /**
   * 检查是否支持人脸识别
   */
  static isFaceRecognitionSupported(): boolean {
    try {
      return canIUse('SystemCapability.AI.FaceRecognizer');
    } catch (error) {
      console.error('Failed to check face recognition support:', error);
      return false;
    }
  }

  /**
   * 检查是否支持文字识别（OCR）
   */
  static isOCRSupported(): boolean {
    try {
      return canIUse('SystemCapability.AI.GeneralRecognizer');
    } catch (error) {
      console.error('Failed to check OCR support:', error);
      return false;
    }
  }

  // ==================== 日志相关 ====================

  /**
   * 检查是否支持日志输出
   */
  static isHilogSupported(): boolean {
    try {
      return canIUse('SystemCapability.HiviewDFX.HiLog');
    } catch (error) {
      console.error('Failed to check hilog support:', error);
      return false;
    }
  }

  // ==================== 通用方法 ====================

  /**
   * 通用兼容性检查方法
   * @param sysCap 系统能力名称
   * @returns 是否支持
   */
  static checkCapability(sysCap: string): boolean {
    try {
      return canIUse(sysCap);
    } catch (error) {
      console.error(`Failed to check capability ${sysCap}:`, error);
      return false;
    }
  }

  /**
   * 批量检查多个系统能力
   * @param sysCaps 系统能力名称数组
   * @returns 检查结果映射表
   */
  static batchCheck(sysCaps: string[]): Map<string, boolean> {
    const results = new Map<string, boolean>();
    sysCaps.forEach(sysCap => {
      results.set(sysCap, ApiCompatibilityUtil.checkCapability(sysCap));
    });
    return results;
  }

  /**
   * 检查是否所有能力都支持
   * @param sysCaps 系统能力名称数组
   * @returns 是否全部支持
   */
  static checkAllSupported(sysCaps: string[]): boolean {
    return sysCaps.every(sysCap => ApiCompatibilityUtil.checkCapability(sysCap));
  }

  /**
   * 检查是否至少支持一个能力
   * @param sysCaps 系统能力名称数组
   * @returns 是否至少支持一个
   */
  static checkAnySupported(sysCaps: string[]): boolean {
    return sysCaps.some(sysCap => ApiCompatibilityUtil.checkCapability(sysCap));
  }

  /**
   * 获取不支持的能力列表
   * @param sysCaps 系统能力名称数组
   * @returns 不支持的能力列表
   */
  static getUnsupportedCapabilities(sysCaps: string[]): string[] {
    return sysCaps.filter(sysCap => !ApiCompatibilityUtil.checkCapability(sysCap));
  }

  /**
   * 打印能力支持情况（用于调试）
   * @param sysCaps 系统能力名称数组
   */
  static printSupportStatus(sysCaps: string[]): void {
    console.info('=== API Compatibility Check Results ===');
    sysCaps.forEach(sysCap => {
      const isSupported = ApiCompatibilityUtil.checkCapability(sysCap);
      const status = isSupported ? '✅ Supported' : '❌ Not Supported';
      console.info(`${sysCap}: ${status}`);
    });
    console.info('========================================');
  }
}
