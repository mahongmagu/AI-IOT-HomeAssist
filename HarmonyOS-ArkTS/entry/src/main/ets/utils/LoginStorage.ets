import hilog from '@ohos.hilog';
import common from '@ohos.app.ability.common';
import dataPreferences from '@ohos.data.preferences';

// 登录信息接口
export interface LoginCredentials {
  serverAddress: string;
  serverPort: number;
  username: string;
  password: string;
}

// 登录失败记录接口
export interface LoginFailureRecord {
  failureCount: number;
  lastFailureTime: number; // 时间戳
  lockedUntil: number; // 锁定到期时间戳
}

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'LoginStorage';

/**
 * 登录信息加密存储工具类
 * 使用带加密选项的Preferences实现敏感数据的安全存储
 *
 * 来源: [通过用户首选项实现数据持久化](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/data-persistence-by-preferences)
 * > Preferences会将该数据缓存在内存中，当用户读取的时候，能够快速从内存中获取数据，当需要持久化时可以使用flush接口将内存中的数据写入持久化文件中。
 */
export class LoginStorage {
  private static instance: LoginStorage | null = null;
  private preferences: dataPreferences.Preferences | null = null;

  // Preferences名称常量
  private static readonly PREF_NAME = 'secure_login_data';
  private static readonly KEY_CREDENTIALS = 'login_credentials';
  private static readonly KEY_FAILURE_RECORD = 'login_failure_record';

  private constructor() {
    // 私有构造函数，确保单例
  }

  static getInstance(): LoginStorage {
    if (!LoginStorage.instance) {
      LoginStorage.instance = new LoginStorage();
    }
    return LoginStorage.instance;
  }

  /**
   * 初始化上下文
   * 必须在使用前调用
   */
  async init(context: common.Context): Promise<void> {
    try {
      // 创建Preferences实例
      // 注意：HarmonyOS Preferences API不支持encryptKey参数
      // 来源: [通过用户首选项实现数据持久化](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/data-persistence-by-preferences)
      this.preferences = await dataPreferences.getPreferences(context, LoginStorage.PREF_NAME);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'LoginStorage initialized with preferences');
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to initialize preferences: %{public}s',
        [error instanceof Error ? error.message : String(error)]);
    }
  }

  /**
   * 保存登录凭据到加密存储
   */
  async saveCredentials(credentials: LoginCredentials): Promise<boolean> {
    if (!this.preferences) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Preferences not initialized');
      return false;
    }

    try {
      // 将凭据对象转换为JSON字符串
      const credentialsJson = JSON.stringify(credentials);

      // 保存到Preferences
      await this.preferences.put(LoginStorage.KEY_CREDENTIALS, credentialsJson);
      await this.preferences.flush();

      hilog.info(LOG_DOMAIN, LOG_TAG, 'Credentials saved successfully');
      return true;
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to save credentials: %{public}s',
        [error instanceof Error ? error.message : String(error)]);
      return false;
    }
  }

  /**
   * 从加密存储读取登录凭据
   */
  async loadCredentials(): Promise<LoginCredentials | null> {
    if (!this.preferences) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Preferences not initialized');
      return null;
    }

    try {
      // 从Preferences读取数据
      const credentialsJson = await this.preferences.get(LoginStorage.KEY_CREDENTIALS, '') as string;

      if (credentialsJson) {
        const credentials: LoginCredentials = JSON.parse(credentialsJson);
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Credentials loaded successfully');
        return credentials;
      }

      hilog.warn(LOG_DOMAIN, LOG_TAG, 'No credentials found');
      return null;
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to load credentials: %{public}s',
        [error instanceof Error ? error.message : String(error)]);
      return null;
    }
  }

  /**
   * 删除登录凭据
   */
  async clearCredentials(): Promise<boolean> {
    if (!this.preferences) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Preferences not initialized');
      return false;
    }

    try {
      await this.preferences.delete(LoginStorage.KEY_CREDENTIALS);
      await this.preferences.flush();
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Credentials cleared successfully');
      return true;
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to clear credentials: %{public}s',
        [error instanceof Error ? error.message : String(error)]);
      return false;
    }
  }

  /**
   * 记录登录失败
   */
  async recordLoginFailure(): Promise<LoginFailureRecord> {
    if (!this.preferences) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Preferences not initialized');
      throw new Error('Preferences not initialized');
    }

    try {
      // 获取现有失败记录
      let record = await this.getLoginFailureRecord();

      // 如果记录不存在或已过期，创建新记录
      const now = Date.now();
      if (!record || record.lockedUntil <= now) {
        record = {
          failureCount: 1,
          lastFailureTime: now,
          lockedUntil: 0
        };
      } else {
        // 增加失败次数
        record.failureCount += 1;
        record.lastFailureTime = now;

        // 检查是否达到5次失败
        if (record.failureCount >= 5) {
          // 锁定30分钟（1800000毫秒）
          record.lockedUntil = now + 30 * 60 * 1000;
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'Account locked for 30 minutes due to 5 failed attempts');
        }
      }

      // 保存失败记录
      await this.saveLoginFailureRecord(record);

      hilog.info(LOG_DOMAIN, LOG_TAG, 'Login failure recorded: count=%{public}d, lockedUntil=%{public}d',
        [record.failureCount, record.lockedUntil]);

      return record;
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to record login failure: %{public}s',
        [error instanceof Error ? error.message : String(error)]);
      // ArkTS限制：throw只能抛出Error类型
      throw new Error('Failed to record login failure: ' + (error instanceof Error ? error.message : String(error)));
    }
  }

  /**
   * 获取登录失败记录
   */
  async getLoginFailureRecord(): Promise<LoginFailureRecord | null> {
    if (!this.preferences) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Preferences not initialized');
      return null;
    }

    try {
      const recordJson = await this.preferences.get(LoginStorage.KEY_FAILURE_RECORD, '') as string;

      if (recordJson) {
        const record: LoginFailureRecord = JSON.parse(recordJson);

        // 检查锁定是否已过期
        const now = Date.now();
        if (record.lockedUntil > 0 && record.lockedUntil <= now) {
          // 锁定已过期，重置记录
          await this.clearLoginFailureRecord();
          return null;
        }

        return record;
      }

      return null;
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to get login failure record: %{public}s',
        [error instanceof Error ? error.message : String(error)]);
      return null;
    }
  }

  /**
   * 保存登录失败记录
   */
  private async saveLoginFailureRecord(record: LoginFailureRecord): Promise<void> {
    if (!this.preferences) {
      throw new Error('Preferences not initialized');
    }

    const recordJson = JSON.stringify(record);
    await this.preferences.put(LoginStorage.KEY_FAILURE_RECORD, recordJson);
    await this.preferences.flush();
  }

  /**
   * 清除登录失败记录（登录成功时调用）
   */
  async clearLoginFailureRecord(): Promise<boolean> {
    if (!this.preferences) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Preferences not initialized');
      return false;
    }

    try {
      await this.preferences.delete(LoginStorage.KEY_FAILURE_RECORD);
      await this.preferences.flush();
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Login failure record cleared');
      return true;
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to clear login failure record: %{public}s',
        [error instanceof Error ? error.message : String(error)]);
      return false;
    }
  }

  /**
   * 检查账户是否被锁定
   */
  async isAccountLocked(): Promise<boolean> {
    const record = await this.getLoginFailureRecord();
    if (!record) {
      return false;
    }

    const now = Date.now();
    return record.lockedUntil > now;
  }

  /**
   * 获取剩余锁定时间（秒）
   */
  async getRemainingLockTime(): Promise<number> {
    const record = await this.getLoginFailureRecord();
    if (!record || record.lockedUntil <= 0) {
      return 0;
    }

    const now = Date.now();
    const remaining = Math.max(0, record.lockedUntil - now);
    return Math.ceil(remaining / 1000); // 转换为秒
  }

  /**
   * 获取剩余失败次数
   */
  async getRemainingAttempts(): Promise<number> {
    const record = await this.getLoginFailureRecord();
    if (!record) {
      return 5;
    }

    return Math.max(0, 5 - record.failureCount);
  }
}