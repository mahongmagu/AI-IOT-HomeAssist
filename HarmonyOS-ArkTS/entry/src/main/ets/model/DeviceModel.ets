// 设备组模型

@ObservedV2
export class DeviceGroup {
  @Trace id: string = '';
  @Trace name: string = '';
  @Trace displayName: string = '';
  @Trace location?: string = '';
  @Trace units: DeviceUnit[] = [];
  // 兼容Index.ets中使用的属性
  @Trace groupName: string = '';
  @Trace icon: string = '';
  @Trace hasControlUnit: boolean = false;
  @Trace isOffline: boolean = false;
}

// 设备单元模型

@ObservedV2
export class DeviceUnit {
  @Trace id: string = '';
  @Trace name: string = '';
  @Trace type: 'control' | 'state' | 'text' | 'data' = 'control';
  @Trace status: string = '';
  @Trace customIcon?: string = '';
}

// 定时任务模型
export class ScheduleTask {
  id: string = '';
  groupId: string = '';
  unitId: string = '';
  type: 'once' | 'daily' | 'weekly' | 'interval' = 'once';
  time: string = '';
  cmd: string = '';
  enabled: boolean = true;
  weekdays?: number[] = [];
  interval?: number = 0;
}