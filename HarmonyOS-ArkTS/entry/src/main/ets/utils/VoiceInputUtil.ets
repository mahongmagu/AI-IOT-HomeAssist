import hilog from '@ohos.hilog';
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';

// 常量定义
const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'VoiceInputUtil';

/**
 * 语音识别结果回调接口
 */
export interface VoiceRecognitionCallback {
  onStart: () => void;
  onResult: (result: string, isFinal: boolean) => void;
  onComplete: () => void;
  onError: (errorCode: number, errorMessage: string) => void;
}

/**
 * 语音输入工具类
 * 使用 HarmonyOS Core Speech Kit 实现语音识别
 */
export class VoiceInputUtil {
  private static instance: VoiceInputUtil;
  private asrEngine: speechRecognizer.SpeechRecognitionEngine | null = null;
  private sessionId: string = 'voice_input_' + Date.now();
  private isRecognizing: boolean = false;

  static getInstance(): VoiceInputUtil {
    if (!VoiceInputUtil.instance) {
      VoiceInputUtil.instance = new VoiceInputUtil();
    }
    return VoiceInputUtil.instance;
  }

  /**
   * 初始化语音识别引擎
   */
  private async createEngine(): Promise<void> {
    if (this.asrEngine) {
      return;
    }

    try {
      // 设置创建引擎参数
      const extraParam: Record<string, Object> = {
        'locate': 'CN',
        'recognizerMode': 'short' // 短语音模式，适合指令输入
      };

      const initParamsInfo: speechRecognizer.CreateEngineParams = {
        language: 'zh-CN',
        online: 1, // 离线模式
        extraParams: extraParam
      };

      // 创建引擎
      this.asrEngine = await speechRecognizer.createEngine(initParamsInfo);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Speech recognition engine created successfully');
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, 
        `Failed to create speech recognition engine. Code: ${err.code}, message: ${err.message}`);
      throw new Error(`Failed to create speech recognition engine: ${err.message}`);
    }
  }

  /**
   * 开始语音识别
   * @param callback 识别结果回调
   */
  async startVoiceRecognition(callback: VoiceRecognitionCallback): Promise<void> {
    try {
      // 检查设备是否支持语音识别
      if (!this.isVoiceInputSupported()) {
        callback.onError(-1, '当前设备不支持语音识别');
        return;
      }

      // 如果正在识别，先停止
      if (this.isRecognizing) {
        this.stopRecognition();
        await this.sleep(200); // 等待停止完成
      }

      // 创建引擎
      await this.createEngine();

      // 设置监听回调
      this.setListener(callback);

      // 开始识别
      this.startListening();

      this.isRecognizing = true;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Voice recognition started');
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, 
        `Failed to start voice recognition. Code: ${err.code}, message: ${err.message}`);
      callback.onError(err.code, err.message);
    }
  }

  /**
   * 设置语音识别监听回调
   */
  private setListener(callback: VoiceRecognitionCallback): void {
    if (!this.asrEngine) {
      return;
    }

    const listener: speechRecognizer.RecognitionListener = {
      // 开始识别成功回调
      onStart: (sessionId: string, eventMessage: string) => {
        hilog.info(LOG_DOMAIN, LOG_TAG, `Recognition started: ${eventMessage}`);
        callback.onStart();
      },

      // 事件回调
      onEvent: (sessionId: string, eventCode: number, eventMessage: string) => {
        hilog.info(LOG_DOMAIN, LOG_TAG, 
          `Recognition event: code=${eventCode}, message=${eventMessage}`);
      },

      // 识别结果回调
      onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult) => {
        hilog.info(LOG_DOMAIN, LOG_TAG, 
          `Recognition result: ${result.result}, isFinal=${result.isFinal}`);
        callback.onResult(result.result, result.isFinal);
      },

      // 识别完成回调
      onComplete: (sessionId: string, eventMessage: string) => {
        hilog.info(LOG_DOMAIN, LOG_TAG, `Recognition completed: ${eventMessage}`);
        this.isRecognizing = false;
        callback.onComplete();
      },

      // 错误回调
      onError: (sessionId: string, errorCode: number, errorMessage: string) => {
        hilog.error(LOG_DOMAIN, LOG_TAG, 
          `Recognition error: code=${errorCode}, message=${errorMessage}`);
        this.isRecognizing = false;
        callback.onError(errorCode, errorMessage);
      }
    };

    this.asrEngine.setListener(listener);
  }

  /**
   * 开始监听语音
   */
  private startListening(): void {
    if (!this.asrEngine) {
      return;
    }

    // 生成新的会话ID
    this.sessionId = 'voice_input_' + Date.now();

    // 设置识别参数
    const recognizerParams: speechRecognizer.StartParams = {
      sessionId: this.sessionId,
      audioInfo: {
        audioType: 'pcm',
        sampleRate: 16000,
        soundChannel: 1,
        sampleBit: 16
      },
      extraParams: {
        'recognitionMode': 0, // 实时录音识别
        'vadBegin': 2000, // 前端点检测时间
        'vadEnd': 3000, // 后端点检测时间
        'maxAudioDuration': 60000 // 最大音频时长
      }
    };

    // 开始识别
    this.asrEngine.startListening(recognizerParams);
  }

  /**
   * 停止语音识别
   */
  stopRecognition(): void {
    if (!this.asrEngine || !this.isRecognizing) {
      return;
    }

    try {
      this.asrEngine.finish(this.sessionId);
      this.isRecognizing = false;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Voice recognition stopped');
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to stop recognition:', error);
    }
  }

  /**
   * 取消语音识别
   */
  cancelRecognition(): void {
    if (!this.asrEngine || !this.isRecognizing) {
      return;
    }

    try {
      this.asrEngine.cancel(this.sessionId);
      this.isRecognizing = false;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Voice recognition canceled');
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to cancel recognition:', error);
    }
  }

  /**
   * 释放语音识别引擎资源
   */
  release(): void {
    if (!this.asrEngine) {
      return;
    }

    try {
      // 先停止识别
      if (this.isRecognizing) {
        this.asrEngine.cancel(this.sessionId);
        this.isRecognizing = false;
      }

      // 关闭引擎
      this.asrEngine.shutdown();
      this.asrEngine = null;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Speech recognition engine released');
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to release engine:', error);
    }
  }

  /**
   * 检查是否支持语音输入
   */
  isVoiceInputSupported(): boolean {
    try {
      const isSupported = canIUse('SystemCapability.AI.SpeechRecognizer');
      hilog.info(LOG_DOMAIN, LOG_TAG, `Voice input supported: ${isSupported}`);
      return isSupported;
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to check voice input support:', error);
      return false;
    }
  }

  /**
   * 检查是否正在识别
   */
  isRecognizingNow(): boolean {
    return this.isRecognizing;
  }

  /**
   * 延时函数
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
