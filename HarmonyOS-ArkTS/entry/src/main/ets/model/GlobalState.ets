// 全局状态管理 - 单例模式
import { IndexData } from './IndexData';
import { DeviceGroup, DeviceUnit } from './DeviceModel';

/**
 * 全局状态管理类
 * 使用单例模式确保整个应用共享同一个数据源
 */
export class GlobalState {
  private static instance: GlobalState | null = null;
  private _indexData: IndexData = new IndexData();

  private constructor() {
    // 私有构造函数，防止外部实例化
  }

  /**
   * 获取全局状态单例
   */
  public static getInstance(): GlobalState {
    if (!GlobalState.instance) {
      GlobalState.instance = new GlobalState();
    }
    return GlobalState.instance;
  }

  /**
   * 获取全局数据
   */
  public get indexData(): IndexData {
    return this._indexData;
  }

  /**
   * 更新设备单元状态（同步更新设备组数据）
   * @param groupName 设备组名称
   * @param unitId 设备单元ID
   * @param status 新状态
   * @returns 是否更新成功
   */
  public updateUnitStatus(groupName: string, unitId: string, status: string): boolean {
    const group = this._indexData.deviceGroups.find(g => g.groupName === groupName || g.name === groupName);
    if (!group) {
      return false;
    }

    const unit = group.units?.find(u => u.id === unitId);
    if (!unit) {
      return false;
    }

    // 更新单元状态
    unit.status = status;
    
    return true;
  }

  /**
   * 根据设备组名称获取设备组
   */
  public getDeviceGroup(groupName: string): DeviceGroup | undefined {
    return this._indexData.deviceGroups.find(g => g.groupName === groupName || g.name === groupName);
  }

  /**
   * 重置全局状态（用于测试或重新初始化）
   */
  public static reset(): void {
    GlobalState.instance = null;
  }
}
