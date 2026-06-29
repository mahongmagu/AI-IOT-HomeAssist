// 定时任务列表组件
import hilog from '@ohos.hilog';
import promptAction from '@ohos.promptAction';
import { Schedule, ScheduleUtil } from '../model/ScheduleModel';
import { ScheduleService } from '../services/ScheduleService';
import { ApiCompatibilityUtil } from '../utils/ApiCompatibilityUtil';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'ScheduleList';

@ComponentV2
export struct ScheduleListComponent {
  @Local schedules: Schedule[] = [];
  @Local isLoading: boolean = false;
  @Local selectedUnitId: string = '';
  @Param groupName: string = '';
  @Param unitId: string = '';
  @Param onEditSchedule: (scheduleId: string) => void = () => {};
  @Param onAddSchedule: () => void = () => {};
  
  private scheduleService: ScheduleService = ScheduleService.getInstance();
  
  aboutToAppear() {
    this.loadSchedules();
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
  
  async loadSchedules() {
    this.isLoading = true;
    
    try {
      const response = await this.scheduleService.getAllSchedules();
      
      if (response.code === 200) {
        // 过滤出当前设备单元的定时任务
        const allSchedules = Object.values(response.schedules);
        
        if (this.unitId) {
          this.schedules = allSchedules.filter(s => s.unitId === this.unitId);
        } else if (this.groupName) {
          // 如果只提供了groupName，显示该组所有任务
          this.schedules = allSchedules;
        } else {
          this.schedules = allSchedules;
        }
        
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Loaded %{public}d schedules', [this.schedules.length]);
      } else {
        this.showToastMessage(response.msg || '加载定时任务失败');
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Load schedules error: %{public}s', [(error as Error).message]);
      this.showToastMessage('加载定时任务失败');
    } finally {
      this.isLoading = false;
    }
  }
  
  async deleteSchedule(scheduleId: string) {
    try {
      const response = await this.scheduleService.deleteSchedule(scheduleId);
      
      if (response.code === 200) {
        this.showToastMessage('删除成功');
        await this.loadSchedules();
      } else {
        this.showToastMessage(response.msg || '删除失败');
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Delete schedule error: %{public}s', [(error as Error).message]);
      this.showToastMessage('删除失败');
    }
  }
  
  async toggleScheduleEnable(scheduleId: string, currentEnable: boolean) {
    try {
      const response = await this.scheduleService.toggleScheduleEnable(scheduleId, !currentEnable);
      
      if (response.code === 200) {
        this.showToastMessage(currentEnable ? '已禁用' : '已启用');
        await this.loadSchedules();
      } else {
        this.showToastMessage(response.msg || '操作失败');
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Toggle schedule error: %{public}s', [(error as Error).message]);
      this.showToastMessage('操作失败');
    }
  }
  
  build() {
    Column() {
      // 标题栏
      Row() {
        Text('定时任务')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1a1a1a')
          .layoutWeight(1)
        
        Button() {
          Text('+')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffffff')
        }
        .width(36)
        .height(36)
        .backgroundColor('#0066cc')
        .borderRadius(18)
        .onClick(() => {
          this.onAddSchedule();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      
      Divider().color('#e0e0e0')
      
      // 任务列表
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color('#0066cc')
          Text('加载中...')
            .fontSize(14)
            .fontColor('#666')
            .margin({ top: 12 })
        }
        .width('100%')
        .height(200)
        .justifyContent(FlexAlign.Center)
      } else if (this.schedules.length === 0) {
        Column() {
          Text('📭')
            .fontSize(48)
            .margin({ bottom: 12 })
          Text('暂无定时任务')
            .fontSize(16)
            .fontColor('#666')
          Text('点击右上角 + 添加定时任务')
            .fontSize(14)
            .fontColor('#999')
            .margin({ top: 8 })
        }
        .width('100%')
        .height(200)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.schedules, (schedule: Schedule) => {
            ListItem() {
              this.ScheduleItem(schedule)
            }
          }, (schedule: Schedule) => schedule.id)
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: '#f0f0f0' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#ffffff')
  }
  
  @Builder ScheduleItem(schedule: Schedule) {
    Column() {
      Row() {
        // 左侧：任务信息
        Column({ space: 6 }) {
          // 任务名称
          Text(schedule.name || schedule.id)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1a1a1a')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          
          // 任务类型和时间
          Row({ space: 8 }) {
            Text(ScheduleUtil.getTypeLabel(schedule))
              .fontSize(13)
              .fontColor('#0066cc')
              .backgroundColor('#e6f2ff')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
            
            Text(ScheduleUtil.getTimeDisplay(schedule))
              .fontSize(13)
              .fontColor('#666')
          }
          
          // 执行命令
          Row({ space: 4 }) {
            Text('命令:')
              .fontSize(13)
              .fontColor('#999')
            Text(schedule.cmd)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(schedule.cmd === 'ON' ? '#28a745' : '#dc3545')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        
        // 右侧：操作按钮
        Column({ space: 8 }) {
          Row({ space: 6 }) {
            // 编辑按钮
            Button() {
              Text('编辑')
                .fontSize(12)
                .fontColor('#ffffff')
            }
            .width(50)
            .height(28)
            .backgroundColor('#0066cc')
            .borderRadius(14)
            .onClick(() => {
              this.onEditSchedule(schedule.id);
            })
            
            // 删除按钮
            Button() {
              Text('删除')
                .fontSize(12)
                .fontColor('#ffffff')
            }
            .width(50)
            .height(28)
            .backgroundColor('#dc3545')
            .borderRadius(14)
            .onClick(() => {
              promptAction.showDialog({
                title: '确认删除',
                message: `确定要删除定时任务 "${schedule.name || schedule.id}" 吗？`,
                buttons: [
                  { text: '取消', color: '#666666' },
                  { text: '删除', color: '#dc3545' }
                ]
              }).then((result) => {
                if (result.index === 1) {
                  this.deleteSchedule(schedule.id);
                }
              });
            })
          }
          
          // 启用/禁用按钮
          Button() {
            Text(schedule.enabled === false ? '启用' : '禁用')
              .fontSize(12)
              .fontColor('#ffffff')
          }
          .width(106)
          .height(28)
          .backgroundColor(schedule.enabled === false ? '#28a745' : '#dc3545')
          .borderRadius(14)
          .onClick(() => {
            this.toggleScheduleEnable(schedule.id, schedule.enabled !== false);
          })
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    }
    .width('100%')
  }
}
