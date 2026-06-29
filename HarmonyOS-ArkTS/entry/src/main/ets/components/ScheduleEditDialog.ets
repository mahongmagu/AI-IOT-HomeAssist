// 定时任务编辑弹窗组件
import hilog from '@ohos.hilog';
import promptAction from '@ohos.promptAction';
import { Schedule, ScheduleType, ScheduleRequest, ScheduleUtil } from '../model/ScheduleModel';
import { ScheduleService } from '../services/ScheduleService';
import { DeviceUnit } from '../model/DeviceModel';
import { ApiCompatibilityUtil } from '../utils/ApiCompatibilityUtil';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'ScheduleEditDialog';

@ComponentV2
export struct ScheduleEditDialog {
  @Local isVisible: boolean = false;
  @Local scheduleType: string = ScheduleType.ONCE;
  @Local selectedHour: number = 8;
  @Local selectedMinute: number = 0;
  @Local selectedCmd: string = 'ON';
  @Local intervalMinutes: number = 60;
  @Local selectedWeekdays: number[] = [];
  @Local isLoading: boolean = false;
  @Local editingScheduleId: string = '';
  
  @Param schedule: Schedule | null = null;
  @Param unitId: string = '';
  @Param unitName: string = '';
  @Param groupName: string = '';
  @Param groupId: string = ''; // 设备组ID，用于生成定时任务ID
  @Param location: string = ''; // 位置信息
  @Param existingScheduleCount: number = 0; // 已有定时任务数量，用于生成序号
  @Param onSaveSuccess: () => void = () => {};
  @Param onCancel: () => void = () => {};
  
  private scheduleService: ScheduleService = ScheduleService.getInstance();
  
  aboutToAppear() {
    if (this.schedule) {
      this.loadScheduleData(this.schedule);
    }
  }
  
  private loadScheduleData(schedule: Schedule) {
    this.editingScheduleId = schedule.id;
    this.selectedCmd = schedule.cmd || 'ON';
    
    // 解析时间
    if (schedule.time) {
      const date = new Date(schedule.time);
      this.selectedHour = date.getHours();
      this.selectedMinute = date.getMinutes();
    }
    
    // 解析类型
    if (schedule.interval === 86400000) {
      this.scheduleType = ScheduleType.DAILY;
    } else if (schedule.interval === 604800000) {
      this.scheduleType = ScheduleType.WEEKLY;
      if (schedule.weekdays) {
        this.selectedWeekdays = [...schedule.weekdays];
      }
    } else if (schedule.interval !== undefined && schedule.interval > 0) {
      this.scheduleType = ScheduleType.INTERVAL;
      this.intervalMinutes = Math.floor(schedule.interval / 60000);
    } else {
      // interval为0或undefined时，都是一次性任务
      this.scheduleType = ScheduleType.ONCE;
    }
  }
  
  // 生成定时任务名称
  private getGeneratedScheduleName(): string {
    // 如果是编辑现有任务，返回现有名称
    if (this.schedule && this.schedule.name) {
      return this.schedule.name;
    }
    
    // 计算序号：获取该设备单元已有的定时任务数量
    let scheduleCount = this.existingScheduleCount;
    
    // 如果外部没有传递数量，默认从1开始
    if (scheduleCount === 0) {
      scheduleCount = 0; // 默认从0开始，+1后得到序号1
    }
    
    const sequence = scheduleCount + 1; // 序号 = 已有数量 + 1
    const parts: string[] = [];
    
    // 确保即使某些部分为空，也能生成合理的名称
    const locationPart = this.location || '未知位置';
    const groupPart = this.groupName || '未知设备组';
    const unitPart = this.unitName || '未知设备单元';
    
    parts.push(locationPart);
    parts.push(groupPart);
    parts.push(unitPart);
    parts.push(`任务${sequence}`);
    
    return parts.join('-');
  }
  
  private showToastMessage(message: string): void {
    if (!ApiCompatibilityUtil.isPromptActionSupported()) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'PromptAction not supported');
      return;
    }
    
    try {
      promptAction.showToast({
        message: message,
        duration: 2000
      });
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to show toast: %{public}s', [(error as Error).message]);
    }
  }
  
  async saveSchedule() {
    // 验证输入
    if (this.scheduleType === ScheduleType.WEEKLY && this.selectedWeekdays.length === 0) {
      this.showToastMessage('请至少选择一个星期');
      return;
    }
    
    if (this.scheduleType === ScheduleType.INTERVAL && this.intervalMinutes < 1) {
      this.showToastMessage('请输入有效的周期时间');
      return;
    }
    
    this.isLoading = true;
    
    try {
      const scheduleData: ScheduleRequest = {
        unitId: this.unitId,
        cmd: this.selectedCmd.toUpperCase() // 确保大写
      } as ScheduleRequest & { enabled?: boolean };
      
      // 添加enabled字段
      (scheduleData as any).enabled = true;
      
      // 如果是新增任务，生成ID和名称
      if (!this.editingScheduleId) {
        // 生成ID格式：设备组ID_设备单元ID-唯一顺序号
        const gId = this.groupId || this.groupName;
        const timestamp = Date.now();
        scheduleData.id = `${gId}_${this.unitId}-${timestamp}`;
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Generated schedule ID: %{public}s', [scheduleData.id]);
        
        // 计算序号：获取该设备单元已有的定时任务数量
        let scheduleCount = this.existingScheduleCount;
        if (scheduleCount === 0) {
          // 如果外部没有传递数量，尝试从服务获取
          try {
            const allSchedules = await this.scheduleService.getAllSchedules();
            const unitSchedules = Object.values(allSchedules).filter((s: Schedule) => s.unitId === this.unitId);
            scheduleCount = unitSchedules.length;
          } catch (error) {
            hilog.warn(LOG_DOMAIN, LOG_TAG, 'Failed to get existing schedule count: %{public}s', [(error as Error).message]);
          }
        }
        
        const sequence = scheduleCount + 1; // 序号 = 已有数量 + 1
        const parts: string[] = [];
        
        // 确保即使某些部分为空，也能生成合理的名称
        const locationPart = this.location || '未知位置';
        const groupPart = this.groupName || '未知设备组';
        const unitPart = this.unitName || '未知设备单元';
        
        parts.push(locationPart);
        parts.push(groupPart);
        parts.push(unitPart);
        parts.push(`任务${sequence}`);
        
        scheduleData.name = parts.join('-');
      }
      
      // 根据类型设置时间和重复规则
      if (this.scheduleType === ScheduleType.DAILY) {
        scheduleData.recurring = true; // 重复任务
        scheduleData.interval = 86400000;
        scheduleData.time = ScheduleUtil.localTimeToUTC(this.selectedHour, this.selectedMinute);
      } else if (this.scheduleType === ScheduleType.WEEKLY) {
        scheduleData.recurring = true; // 重复任务
        scheduleData.interval = 604800000;
        scheduleData.weekdays = [...this.selectedWeekdays];
        scheduleData.time = ScheduleUtil.getNextWeeklyTime(this.selectedHour, this.selectedMinute, this.selectedWeekdays);
      } else if (this.scheduleType === ScheduleType.INTERVAL) {
        scheduleData.recurring = true; // 重复任务
        scheduleData.interval = this.intervalMinutes * 60000;
      } else {
        // 一次性任务
        scheduleData.recurring = false; // 非重复任务
        scheduleData.interval = 0; // 一次性任务interval设为0，而不是undefined
        scheduleData.time = ScheduleUtil.localTimeToUTC(this.selectedHour, this.selectedMinute);
      }
      
      // 调试日志：记录要发送的数据
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Saving schedule data: %{public}s', [JSON.stringify(scheduleData)]);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Schedule type: %{public}s, editing: %{public}s', [this.scheduleType, this.editingScheduleId]);
      
      let response;
      
      if (this.editingScheduleId) {
        // 更新任务
        response = await this.scheduleService.updateSchedule(this.editingScheduleId, scheduleData);
      } else {
        // 创建任务
        if (scheduleData.interval !== undefined && scheduleData.interval > 0 && scheduleData.recurring) {
          response = await this.scheduleService.createRecurringSchedule(scheduleData);
        } else {
          response = await this.scheduleService.createSchedule(scheduleData);
        }
      }
      
      if (response.code === 200) {
        this.showToastMessage(this.editingScheduleId ? '更新成功' : '创建成功');
        this.onSaveSuccess();
        this.isVisible = false;
      } else {
        this.showToastMessage(response.msg || '保存失败');
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Save schedule error: %{public}s', [(error as Error).message]);
      this.showToastMessage('保存失败');
    } finally {
      this.isLoading = false;
    }
  }
  
  toggleWeekday(day: number) {
    const index = this.selectedWeekdays.indexOf(day);
    if (index > -1) {
      this.selectedWeekdays.splice(index, 1);
    } else {
      this.selectedWeekdays.push(day);
    }
  }
  
  build() {
    if (this.isVisible) {
      Column() {
        // 遮罩层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#00000080')
          .onClick(() => {
            this.isVisible = false;
            this.onCancel();
          })
        
        // 弹窗内容
        Column() {
          // 标题栏
          Row() {
            Text(this.editingScheduleId ? '编辑定时任务' : '新建定时任务')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#ffffff')
              .layoutWeight(1)
            
            Button() {
              Text('×')
                .fontSize(24)
                .fontColor('#ffffff')
            }
            .width(36)
            .height(36)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.isVisible = false;
              this.onCancel();
            })
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 16, bottom: 16 })
          .linearGradient({
            angle: 90,
            colors: [['#667eea', 0.0], ['#764ba2', 1.0]]
          })
          
          // 表单内容
          Scroll() {
            Column({ space: 20 }) {
              // 设备单元信息
              Column({ space: 8 }) {
                Text('目标设备单元')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#ffffff')
                  .alignSelf(ItemAlign.Start)
                
                Row() {
                  Text(`${this.groupName} - ${this.unitName}`)
                    .fontSize(16)
                    .fontColor('#e0e0e0')
                    .layoutWeight(1)
                  
                  Text(`ID: ${this.unitId}`)
                    .fontSize(12)
                    .fontColor('#999')
                }
                .width('100%')
                .padding(12)
                .backgroundColor('#2d2d44')
                .borderRadius(8)
              }
              .width('100%')
              
              // 任务名称（自动生成）
              Column({ space: 8 }) {
                Text('任务名称')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#ffffff')
                  .alignSelf(ItemAlign.Start)
                
                Text(this.getGeneratedScheduleName())
                  .fontSize(16)
                  .fontColor('#e0e0e0')
                  .width('100%')
                  .padding({ top: 8, bottom: 8, left: 12, right: 12 })
                  .backgroundColor('#2d2d44')
                  .borderRadius(8)
              }
              .width('100%')
              
              // 定时类型
              Column({ space: 8 }) {
                Text('定时类型')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#ffffff')
                  .alignSelf(ItemAlign.Start)
                
                Row({ space: 8 }) {
                  ForEach([
                    { value: ScheduleType.ONCE, label: '一次性' },
                    { value: ScheduleType.DAILY, label: '每天' },
                    { value: ScheduleType.WEEKLY, label: '每周' },
                    { value: ScheduleType.INTERVAL, label: '周期' }
                  ], (item: { value: string, label: string }) => {
                    Button() {
                      Text(item.label)
                        .fontSize(14)
                        .fontColor(this.scheduleType === item.value ? '#ffffff' : '#cccccc')
                    }
                    .width(70)
                    .height(36)
                    .backgroundColor(this.scheduleType === item.value ? '#0066cc' : '#2d2d44')
                    .borderRadius(18)
                    .onClick(() => {
                      this.scheduleType = item.value;
                    })
                  })
                }
                .width('100%')
                .justifyContent(FlexAlign.Start)
              }
              .width('100%')
              
              // 时间选择（非周期类型）
              if (this.scheduleType !== ScheduleType.INTERVAL) {
                Column({ space: 8 }) {
                  Text('执行时间')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#ffffff')
                    .alignSelf(ItemAlign.Start)
                  
                  Row({ space: 12 }) {
                    // 小时选择
                    Column() {
                      Text('时')
                        .fontSize(12)
                        .fontColor('#999')
                        .margin({ bottom: 4 })
                      
                      TextInput({ text: String(this.selectedHour) })
                        .type(InputType.Number)
                        .width(60)
                        .height(40)
                        .fontSize(16)
                        .fontColor('#ffffff')
                        .textAlign(TextAlign.Center)
                        .backgroundColor('#2d2d44')
                        .borderRadius(8)
                        .onChange((value: string) => {
                          const num = parseInt(value);
                          if (num >= 0 && num <= 23) {
                            this.selectedHour = num;
                          }
                        })
                    }
                    
                    Text(':')
                      .fontSize(24)
                      .fontColor('#ffffff')
                    
                    // 分钟选择
                    Column() {
                      Text('分')
                        .fontSize(12)
                        .fontColor('#999')
                        .margin({ bottom: 4 })
                      
                      TextInput({ text: String(this.selectedMinute) })
                        .type(InputType.Number)
                        .width(60)
                        .height(40)
                        .fontSize(16)
                        .fontColor('#ffffff')
                        .textAlign(TextAlign.Center)
                        .backgroundColor('#2d2d44')
                        .borderRadius(8)
                        .onChange((value: string) => {
                          const num = parseInt(value);
                          if (num >= 0 && num <= 59) {
                            this.selectedMinute = num;
                          }
                        })
                    }
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.Center)
                }
                .width('100%')
              }
              
              // 星期选择（每周类型）
              if (this.scheduleType === ScheduleType.WEEKLY) {
                Column({ space: 8 }) {
                  Text('执行日期')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#ffffff')
                    .alignSelf(ItemAlign.Start)
                  
                  Row({ space: 4 }) {
                    ForEach([
                      { day: 1, label: '周一' },
                      { day: 2, label: '周二' },
                      { day: 3, label: '周三' },
                      { day: 4, label: '周四' },
                      { day: 5, label: '周五' },
                      { day: 6, label: '周六' },
                      { day: 0, label: '周日' }
                    ], (item: { day: number, label: string }) => {
                      Button() {
                        Text(item.label)
                          .fontSize(12)
                          .fontColor(this.selectedWeekdays.includes(item.day) ? '#ffffff' : '#cccccc')
                      }
                      .layoutWeight(1)
                      .height(36)
                      .backgroundColor(this.selectedWeekdays.includes(item.day) ? '#0066cc' : '#2d2d44')
                      .borderRadius(18)
                      .onClick(() => {
                        this.toggleWeekday(item.day);
                      })
                    })
                  }
                  .width('100%')
                }
                .width('100%')
              }
              
              // 周期时间（周期类型）
              if (this.scheduleType === ScheduleType.INTERVAL) {
                Column({ space: 8 }) {
                  Text('重复周期（分钟）')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#ffffff')
                    .alignSelf(ItemAlign.Start)
                  
                  TextInput({ text: String(this.intervalMinutes) })
                    .type(InputType.Number)
                    .width('100%')
                    .height(40)
                    .fontSize(16)
                    .fontColor('#ffffff')
                    .backgroundColor('#2d2d44')
                    .borderRadius(8)
                    .onChange((value: string) => {
                      const num = parseInt(value);
                      if (num > 0) {
                        this.intervalMinutes = num;
                      }
                    })
                }
                .width('100%')
              }
              
              // 执行命令
              Column({ space: 8 }) {
                Text('执行命令')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#ffffff')
                  .alignSelf(ItemAlign.Start)
                
                Row({ space: 12 }) {
                  Button() {
                    Text('开启 (ON)')
                      .fontSize(14)
                      .fontColor(this.selectedCmd === 'ON' ? '#ffffff' : '#4caf50')
                  }
                  .width(120)
                  .height(40)
                  .backgroundColor(this.selectedCmd === 'ON' ? '#28a745' : '#2d2d44')
                  .borderRadius(20)
                  .onClick(() => {
                    this.selectedCmd = 'ON';
                  })
                  
                  Button() {
                    Text('关闭 (OFF)')
                      .fontSize(14)
                      .fontColor(this.selectedCmd === 'OFF' ? '#ffffff' : '#f44336')
                  }
                  .width(120)
                  .height(40)
                  .backgroundColor(this.selectedCmd === 'OFF' ? '#dc3545' : '#2d2d44')
                  .borderRadius(20)
                  .onClick(() => {
                    this.selectedCmd = 'OFF';
                  })
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
              }
              .width('100%')
            }
            .width('100%')
            .padding(20)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          
          // 底部按钮
          Row({ space: 12 }) {
            Button() {
              Text('取消')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#666')
            }
            .width(120)
            .height(44)
            .backgroundColor('#f0f0f0')
            .borderRadius(22)
            .onClick(() => {
              this.isVisible = false;
              this.onCancel();
            })
            
            Button() {
              if (this.isLoading) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color('#ffffff')
              } else {
                Text('保存')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#ffffff')
              }
            }
            .width(120)
            .height(44)
            .backgroundColor('#0066cc')
            .borderRadius(22)
            .enabled(!this.isLoading)
            .onClick(() => {
              this.saveSchedule();
            })
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 12, bottom: 12 })
          .justifyContent(FlexAlign.Center)
        }
        .width('90%')
        .maxWidth(400)
        .backgroundColor('#1a1a2e')
        .borderRadius(16)
        .shadow({
          radius: 20,
          color: '#00000080',
          offsetX: 0,
          offsetY: 10
        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }
}
