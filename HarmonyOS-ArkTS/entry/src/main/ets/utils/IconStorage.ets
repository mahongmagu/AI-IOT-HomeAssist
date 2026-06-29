import hilog from '@ohos.hilog';
import common from '@ohos.app.ability.common';
import dataPreferences from '@ohos.data.preferences';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'IconStorage';

/**
 * 自定义图标持久化存储工具类
 * 使用 Preferences 存储设备单元的自定义图标映射
 */
export class IconStorage {
  private static instance: IconStorage | null = null;
  private preferences: dataPreferences.Preferences | null = null;

  private static readonly PREF_NAME = 'custom_icons_data';

  private constructor() {}

  static getInstance(): IconStorage {
    if (!IconStorage.instance) {
      IconStorage.instance = new IconStorage();
    }
    return IconStorage.instance;
  }

  async init(context: common.Context): Promise<void> {
    try {
      this.preferences = await dataPreferences.getPreferences(context, IconStorage.PREF_NAME);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'IconStorage initialized');
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to initialize IconStorage: %{public}s',
        [error instanceof Error ? error.message : String(error)]);
    }
  }

  /**
   * 保存设备组的自定义图标映射
   * @param groupName 设备组名称
   * @param iconMap 设备单元ID到自定义图标的映射
   */
  async saveIconMap(groupName: string, iconMap: Record<string, string>): Promise<boolean> {
    if (!this.preferences) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Preferences not initialized');
      return false;
    }

    try {
      const key = `icons_${groupName}`;
      const jsonStr = JSON.stringify(iconMap);
      await this.preferences.put(key, jsonStr);
      await this.preferences.flush();
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Icon map saved for group: %{public}s', [groupName]);
      return true;
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to save icon map: %{public}s',
        [error instanceof Error ? error.message : String(error)]);
      return false;
    }
  }

  /**
   * 加载设备组的自定义图标映射
   * @param groupName 设备组名称
   * @returns 设备单元ID到自定义图标的映射，无数据时返回空对象
   */
  async loadIconMap(groupName: string): Promise<Record<string, string>> {
    if (!this.preferences) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Preferences not initialized');
      return {};
    }

    try {
      const key = `icons_${groupName}`;
      const jsonStr = await this.preferences.get(key, '') as string;
      if (jsonStr) {
        const iconMap: Record<string, string> = JSON.parse(jsonStr);
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Icon map loaded for group: %{public}s, entries: %{public}d',
          [groupName, Object.keys(iconMap).length]);
        return iconMap;
      }
      return {};
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to load icon map: %{public}s',
        [error instanceof Error ? error.message : String(error)]);
      return {};
    }
  }

  /**
   * 删除设备组的自定义图标映射
   */
  async clearIconMap(groupName: string): Promise<boolean> {
    if (!this.preferences) {
      return false;
    }

    try {
      const key = `icons_${groupName}`;
      await this.preferences.delete(key);
      await this.preferences.flush();
      return true;
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to clear icon map: %{public}s',
        [error instanceof Error ? error.message : String(error)]);
      return false;
    }
  }
}
