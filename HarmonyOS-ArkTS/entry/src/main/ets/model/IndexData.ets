// Index 页面数据模型
import { DeviceGroup } from './DeviceModel';

@ObservedV2
export class IndexData {
  @Trace serverIp: string = '';
  @Trace serverPort: string = '8080';
  @Trace username: string = '';
  @Trace password: string = '';
  @Trace isConnected: boolean = false;
  @Trace deviceGroups: Array<DeviceGroup> = [];
  @Trace aiInputText: string = '';
  @Trace aiResult: string = '';
  @Trace showConfigPage: boolean = false;
  @Trace isAccountLocked: boolean = false;
  @Trace remainingLockTime: number = 0;
  @Trace remainingAttempts: number = 5;
  @Trace isAutoLogin: boolean = false;
  
  // 统计信息
  @Trace totalGroups: number = 0;
  @Trace onlineDevices: number = 0;
}