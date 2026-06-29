import hilog from '@ohos.hilog';
import promptAction from '@ohos.promptAction';
import router from '@ohos.router';
import { DeviceUnit, DeviceGroup } from '../model/DeviceModel';
import { DeviceUnitDataSource } from '../utils/DataSource';
import { ApiService, DeviceApiResponse, ApiResponse } from '../services/ApiService';
import { ApiCompatibilityUtil } from '../utils/ApiCompatibilityUtil';
import { WebSocketService, StateUpdateMessage } from '../services/WebSocketService';
import { ScreenAdaptUtil } from '../utils/ScreenAdaptUtil';
import { Schedule, ScheduleUtil, ScheduleRequest } from '../model/ScheduleModel';
import { ScheduleService } from '../services/ScheduleService';
import { DeviceIcons, IconItem } from '../config/DeviceIcons';
import { IconStorage } from '../utils/IconStorage';
import common from '@ohos.app.ability.common';

// Select选项接口
interface SelectOption {
  value: string;
  icon?: ResourceStr;
}




// 常量定义
const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'DeviceDetail';

@Entry
@ComponentV2
struct DeviceDetail {
  @Local groupName: string = '';
  @Local deviceGroup: DeviceGroup = new DeviceGroup();
  @Local deviceUnits: DeviceUnit[] = [];
  @Local isLoading: boolean = false;
  @Local loadError: string = '';
  @Local showMenu: boolean = false;
  @Local menuX: number = 0;
  @Local menuY: number = 0;
  @Local gridColumns: number = 1; // 响应式列数
  // 定时任务相关
  @Local showScheduleList: boolean = false;
  @Local showScheduleEdit: boolean = false;
  @Local editingSchedule: Schedule | null = null;
  @Local selectedUnitForSchedule: DeviceUnit | null = null;
  @Local allSchedules: Schedule[] = [];
  // 缓存所有定时任务，用于在设备单元卡片中显示
  @Local allSchedulesCache: Schedule[] = [];
  @Local showPageConfig: boolean = false;
  @Local selectedUnitForIconChange: DeviceUnit | null = null;
  @Local iconUpdateTrigger: number = 0;
  // 时间选择器相关
  @Local selectedHour: number = 0;
  @Local selectedMinute: number = 0;
  // 定时类型相关
  @Local selectedScheduleType: number = 0; // 0: 每天, 1: 每周, 2: 一次性
  @Local selectedWeekdays: boolean[] = [false, false, false, false, false, false, false]; // 周日到周六
  private deviceUnitsDataSource: DeviceUnitDataSource = new DeviceUnitDataSource([]);
  // WebSocket 相关
  private originalCallback: ((message: StateUpdateMessage) => void) | null = null;
  private scheduleService: ScheduleService = ScheduleService.getInstance();
  private iconStorage: IconStorage = IconStorage.getInstance();
  private context: common.Context | undefined = undefined;
  
  // Method to show toast using component context to avoid deprecation warning
  private showToastMessage(message: string): void {
    // 检查设备是否支持promptAction
    if (!ApiCompatibilityUtil.isPromptActionSupported()) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'PromptAction not supported on this device');
      return;
    }
    
    try {
      promptAction.showToast({
        message: message,
        duration: 2000
      });
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to show toast: %{public}s', [error instanceof Error ? error.message : String(error)]);
    }
  }

  aboutToAppear() {
    // 获取上下文并初始化图标存储
    this.context = this.getUIContext().getHostContext();
    if (this.context) {
      this.iconStorage.init(this.context);
    }
    
    // 初始化屏幕适配列数
    this.gridColumns = ScreenAdaptUtil.getDeviceUnitColumns();
    hilog.info(LOG_DOMAIN, LOG_TAG, `Screen adapted: device type=${ScreenAdaptUtil.getDeviceType()}, columns=${this.gridColumns}`);
    
    // 从路由参数中获取设备组名称
    const params = router.getParams() as Record<string, string>;
    if (params && params.groupName) {
      this.groupName = params.groupName;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Received groupName from params: %{public}s', [this.groupName]);
      this.loadDeviceGroupDetails();
    } else {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'No groupName parameter received from router');
      this.loadError = '未收到设备组参数';
      this.showToastMessage('未收到设备组参数');
    }
    
    // 注册 WebSocket 回调，监听当前设备组的状态变化
    this.registerWebSocketCallback();
  }

  aboutToDisappear() {
    // 恢复原有的 WebSocket 回调
    this.restoreWebSocketCallback();
  }

  private registerWebSocketCallback(): void {
    const wsService = WebSocketService.getInstance();
    
    // 保存原有的回调
    this.originalCallback = wsService.getCallback();
    
    // 设置新的回调，只处理当前设备组的状态更新
    wsService.setCallback((message: StateUpdateMessage) => {
      this.handleWebSocketMessage(message);
      
      // 如果原回调存在，也调用原回调（保证 Index 页面也能收到更新）
      if (this.originalCallback) {
        this.originalCallback(message);
      }
    });
    
    hilog.info(LOG_DOMAIN, LOG_TAG, 'WebSocket callback registered for device detail page');
  }

  private restoreWebSocketCallback(): void {
    const wsService = WebSocketService.getInstance();
    
    // 恢复原有的回调
    if (this.originalCallback) {
      wsService.setCallback(this.originalCallback);
      this.originalCallback = null;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'WebSocket callback restored');
    }
  }

  private handleWebSocketMessage(message: StateUpdateMessage): void {
    // 检查消息是否属于当前设备组
    const unitId = message.device.unit;
    
    // 使用双重匹配策略检查是否属于当前设备组
    const isCurrentGroup = this.deviceUnits.some(unit => unit.id === unitId);
    
    if (isCurrentGroup) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 
        `Updating device unit status: ${unitId} -> ${message.state}`);
      
      // 更新对应的设备单元状态
      const targetUnit = this.deviceUnits.find(unit => unit.id === unitId);
      if (targetUnit) {
        targetUnit.status = message.state;
        this.deviceUnitsDataSource.updateData(this.deviceUnits);
      }
      
      // 更新设备组的离线状态
      const isOffline = message.device.online === false || message.state === 'OFFLINE';
      this.deviceGroup.isOffline = isOffline;
      
      this.showToastMessage(`设备 ${message.device.unit} 状态已更新`);
    }
  }

  // 生成定时任务名称
  private getGeneratedScheduleName(): string {
    // 如果是编辑现有任务，返回现有名称
    if (this.editingSchedule && this.editingSchedule.name) {
      return this.editingSchedule.name;
    }
    
    // 计算序号：获取该设备单元已有的定时任务数量
    let scheduleCount = 0;
    if (this.selectedUnitForSchedule) {
      scheduleCount = this.allSchedules.filter((s: Schedule) => s.unitId === this.selectedUnitForSchedule!.id).length;
    }
    
    const sequence = scheduleCount + 1; // 序号 = 已有数量 + 1
    const parts: string[] = [];
    
    // 确保即使某些部分为空，也能生成合理的名称
    const locationPart = this.deviceGroup.location || '未知位置';
    const groupPart = this.deviceGroup.displayName || this.groupName || '未知设备组';
    const unitPart = this.selectedUnitForSchedule?.name || '未知设备单元';
    
    parts.push(locationPart);
    parts.push(groupPart);
    parts.push(unitPart);
    parts.push(`任务${sequence}`);
    
    return parts.join('-');
  }

  build() {
    Stack() {
      // 渐变背景层
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor('#1e3a5f')

      // 主内容
      Column() {
        // 顶部状态栏
        this.TopStatusBar()

        // 详情头部
        this.DetailHeader()

        // 根据状态显示不同内容
        if (this.isLoading) {
          // 加载中状态
          Column() {
            LoadingProgress()
              .width(50)
              .height(50)
              .color($r('app.color.primary_color'))
            Text('加载设备信息中...')
              .fontSize(14)
              .fontColor('#666')
              .margin({ top: 15 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .layoutWeight(1)
        } else if (this.loadError) {
          // 错误状态
          Column() {
            Text('❌')
              .fontSize(60)
              .margin({ bottom: 20 })
            Text('加载失败')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#dc3545')
              .margin({ bottom: 10 })
            Text(this.loadError)
              .fontSize(14)
              .fontColor('#666')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 20 })
              .padding({ left: 20, right: 20 })
            Button() {
              Text('重试')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
            }
            .width(120)
            .height(40)
            .backgroundColor($r('app.color.primary_button_background'))
            .fontColor('#ffffff')
            .borderRadius(8)
            .onClick(() => {
              this.loadDeviceGroupDetails();
            })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .layoutWeight(1)
        } else if (this.deviceUnits.length === 0) {
          // 空状态
          Column() {
            Text('📭')
              .fontSize(60)
              .margin({ bottom: 20 })
            Text('暂无设备单元')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#666')
              .margin({ bottom: 10 })
            Text('该设备组暂无可用设备单元')
              .fontSize(14)
              .fontColor('#999')
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .layoutWeight(1)
        } else {
          // 正常状态 - 显示设备单元网格（支持折叠屏）
          Scroll() {
            Grid() {
              LazyForEach(this.deviceUnitsDataSource, (unit: DeviceUnit) => {
                GridItem() {
                  this.UnitCard(unit);
                }
              }, (unit: DeviceUnit) => `${unit.id}_${this.iconUpdateTrigger}`)
            }
            .columnsTemplate(ScreenAdaptUtil.generateColumnsTemplate(this.gridColumns))
            .width('100%')
            .rowsGap(16)
            .columnsGap(16)
            .padding({ bottom: 80 }) // 为底部状态栏留出空间
          }
          .width('100%')
          .height(0)
          .scrollBar(BarState.Off)
          .layoutWeight(1)
        }

        // 底部状态栏
        this.StatusBar()
        
        // 编辑弹窗
        this.EditDialog()
      }
      
      // 定时任务列表弹窗
      if (this.showScheduleList) {
        this.ScheduleListDialog()
      }
      
      // 定时任务编辑弹窗
      if (this.showScheduleEdit) {
        this.ScheduleEditDialog()
      }

      // 页面配置弹窗
      if (this.showPageConfig) {
        this.PageConfigDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder TopStatusBar() {
    Row() {
      Column({ space: 4 }) {
        Text(`设备组数: ${this.deviceGroup.units?.length || 0}`)
          .fontSize(11)
          .fontColor('#ffffff')
          .fontWeight(FontWeight.Medium)
        Text(`在线设备: ${this.getOnlineCount()}`)
          .fontSize(11)
          .fontColor('#ffffff')
          .fontWeight(FontWeight.Medium)
      }
      .layoutWeight(1)

      Column({ space: 4 }) {
        Text(`控制连接: ${this.deviceGroup.isOffline ? '未知' : '在线'}`)
          .fontSize(11)
          .fontColor('#ffffff')
          .fontWeight(FontWeight.Medium)
        Row() {
          Text('状态连接: ')
            .fontSize(11)
            .fontColor('#ffffff')
            .fontWeight(FontWeight.Medium)
          Circle()
            .width(8)
            .height(8)
            .backgroundColor(this.deviceGroup.isOffline ? '#dc3545' : '#28a745')
            .margin({ left: 4 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding({ top: 15, bottom: 10, left: 20, right: 20 })
  }

  @Builder DetailHeader() {
    Row() {
      // 返回按钮
      Button() {
        Text('←')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1a1a1a')
          .width('100%')
          .height('100%')
          .textAlign(TextAlign.Center)
          .alignSelf(ItemAlign.Center)
      }
      .width(44)
      .height(44)
      .backgroundColor('#ffffff')
      .borderRadius(12)
      .shadow({
        radius: 4,
        color: '#00000015',
        offsetX: 0,
        offsetY: 2
      })
      .margin({ right: 12 })
      .onClick(() => {
        // 检查设备是否支持路由功能
        if (!ApiCompatibilityUtil.isRouterSupported()) {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'Router not supported on this device');
          return;
        }
        
        // 使用最新的路由API替代已弃用的router.back()
        try {
          router.back();
        } catch (error) {
          hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to navigate back: %{public}s', [(error as Error).message]);
        }
      })

      // 设备信息
      Column({ space: 4 }) {
        Text(this.deviceGroup.displayName || this.groupName)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#ffffff')
          .alignSelf(ItemAlign.Start)
        
        Text(`设备ID: ${this.deviceGroup.id || this.groupName}`)
          .fontSize(12)
          .fontColor('#ffffffcc')
          .alignSelf(ItemAlign.Start)
      }
      .layoutWeight(1)

      // 下拉箭头按钮和菜单
      Column() {
        Button() {
          Text('▼')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1a1a1a')
            .width('100%')
            .height('100%')
            .textAlign(TextAlign.Center)
            .alignSelf(ItemAlign.Center)
        }
        .width(44)
        .height(44)
        .backgroundColor('#ffffff')
        .borderRadius(12)
        .shadow({
          radius: 4,
          color: '#00000015',
          offsetX: 0,
          offsetY: 2
        })
        .onClick(() => {
          this.showMenu = !this.showMenu;
        })

        // 下拉菜单（显示在按钮下方）
        if (this.showMenu) {
          Column() {
            Row() {
              Text('⏰')
                .fontSize(16)
                .margin({ right: 8 })
              Text('定时任务')
                .fontSize(16)
                .fontColor('#333')
            }
            .width('100%')
            .padding({ top: 12, bottom: 12, left: 20, right: 20 })
            .backgroundColor('#ffffff')
            .onClick(() => {
              this.showMenu = false;
              this.openScheduleList();
            })

            // 分割线
            Divider()
              .width('100%')
              .height(1)
              .color('#f0f0f0')

            // 页面配置
            Row() {
              Text('⚙️')
                .fontSize(16)
                .margin({ right: 8 })
              Text('页面配置')
                .fontSize(16)
                .fontColor('#333')
            }
            .width('100%')
            .padding({ top: 12, bottom: 12, left: 20, right: 20 })
            .backgroundColor('#ffffff')
            .onClick(() => {
              this.showMenu = false;
              this.showPageConfig = true;
            })
          }
          .width(160)
          .backgroundColor('#ffffff')
          .borderRadius(12)
          .shadow({
            radius: 8,
            color: '#00000025',
            offsetX: 0,
            offsetY: 4
          })
          .margin({ top: 8 })
          .zIndex(100)
        }
      }
      .alignItems(HorizontalAlign.End)
    }
  }

  @Builder UnitCard(unit: DeviceUnit) {
    Column() {
      Column({ space: 12 }) {
        this.UnitHeader(unit)
        // 将状态和按钮放在同一行
        this.UnitContentWithButtons(unit)
        // 定时任务显示区域（仅对control类型单元显示）
        if (unit.type === 'control') {
          this.UnitScheduleSection(unit)
        }
      }
      .padding({ top: 16, bottom: 16, left: 16, right: 16 })
      .width('100%')
      .backgroundColor('#ffffff')
      .borderRadius(20)
      .shadow({
        radius: 8,
        color: '#00000015',
        offsetX: 0,
        offsetY: 4
      })
    }
    .width('100%')
    .margin({ bottom: 16 })
  }

  @Builder UnitHeader(unit: DeviceUnit) {
    // 单元头：左侧图标+名称，右侧类型标签
    Row() {
      // 左侧：图标 + 名称
      Row({ space: 12 }) {
        // 设备图标
        this.DeviceIcon(unit.name, unit.customIcon)
        // 设备名称
        Text(unit.name)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1a1a1a')
      }
      .layoutWeight(1)

      // 右侧：类型标签
      this.UnitTypeBadge(unit.type)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }


  // 获取类型标签的颜色
  getTypeBadgeColor(type: string): string {
    if (type === 'control') {
      return '#1e3a8a'; // 深蓝色
    } else if (type === 'data') {
      return '#6b7280'; // 灰色
    } else if (type === 'state') {
      return '#0891b2'; // 青色
    } else if (type === 'text') {
      return '#7c3aed'; // 紫色
    }
    return '#333333'; // 默认深灰色
  }

  @Builder UnitTypeBadge(type: string) {
    // 根据单元类型显示不同的标签样式（不同类型不同颜色）
    if (this.getTypeText(type)) {
      Row() {
        Text('【')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getTypeBadgeColor(type)) // 方括号颜色与文字一致
        Text(this.getTypeText(type))
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getTypeBadgeColor(type)) // 类型文字颜色
        Text('】')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getTypeBadgeColor(type)) // 方括号颜色与文字一致
      }
      .padding({ left: 4, right: 4, top: 2, bottom: 2 })
    }
  }

  @Builder UnitContentWithButtons(unit: DeviceUnit) {
    // 将状态显示和控制按钮放在同一行
    Row() {
      // 左侧：状态显示（占1/2）
      Row({ space: 8 }) {
        Text('状态:')
          .fontSize(16)
          .fontColor('#666666')
        Text(this.getStatusDisplayText(unit))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getStatusColor(unit))
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      
      // 右侧：控制按钮（占1/2）
      Row() {
        this.UnitActionButtons(unit)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // 设备单元定时任务显示区域
  @Builder UnitScheduleSection(unit: DeviceUnit) {
    Column() {
      // 获取该单元的定时任务
      if (this.getSchedulesForUnit(unit.id).length > 0) {
        Divider().margin({ top: 8, bottom: 12 })
        
        Row() {
          Text('定时任务')
            .fontSize(14)
            .fontColor('#666')
            .fontWeight(FontWeight.Medium)
        }
        .width('100%')
        .margin({ bottom: 8 })

        Column({ space: 6 }) {
          ForEach(this.getSchedulesForUnit(unit.id), (schedule: Schedule) => {
            Row() {
              // 任务类型图标
              Text(this.getScheduleTypeIcon(schedule))
                .fontSize(16)
                .margin({ right: 8 })

              // 任务信息（左侧区域）
              Column() {
                // 任务时间（可多行）
                Text(ScheduleUtil.getTimeDisplay(schedule))
                  .fontSize(13)
                  .fontColor('#333')
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                // 任务命令（单独一行）
                Text(schedule.cmd === 'ON' ? '开启' : '关闭')
                  .fontSize(12)
                  .fontColor('#1890ff')
                  .margin({ top: 2 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              // 操作按钮组（右侧固定区域）
              Row({ space: 4 }) {
                // 启用状态开关
                Toggle({ type: ToggleType.Switch, isOn: schedule.enabled !== false })
                  .onChange((isOn: boolean) => {
                    this.toggleScheduleEnabled(schedule, isOn);
                  })
                  .margin({ right: 10 })

                // 编辑按钮
                Button() {
                  Text('✏️')
                    .fontSize(12)
                }
                .width(26)
                .height(22)
                .backgroundColor('#0066cc')
                .borderRadius(11)
                .onClick(() => {
                  this.openScheduleEdit(schedule);
                })

                // 删除按钮
                Button() {
                  Text('🗑️')
                    .fontSize(12)
                }
                .width(26)
                .height(22)
                .backgroundColor('#dc3545')
                .borderRadius(11)
                .onClick(() => {
                  this.deleteSchedule(schedule);
                })
              }
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .backgroundColor('#f8f9fa')
            .borderRadius(6)
          }, (schedule: Schedule) => schedule.id)
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  // 获取定时任务类型图标
  private getScheduleTypeIcon(schedule: Schedule): string {
    // 根据interval值判断任务类型
    if (schedule.interval === 86400000) {
      return '📅'; // 日任务（每天）
    } else if (schedule.interval === 604800000) {
      return '📆'; // 周任务（每周）
    } else if (schedule.interval !== undefined && schedule.interval > 0) {
      return '🔄'; // 周期任务（自定义间隔）
    } else {
      return '⏰'; // 一次性任务（interval为0或undefined）
    }
  }

  @Builder UnitContent(unit: DeviceUnit) {
    // 单元内容：左侧状态文字，右侧预留空间
    Row() {
      // 左侧：状态显示
      Row({ space: 8 }) {
        Text('状态:')
          .fontSize(18)
          .fontColor('#666666')
        Text(this.getStatusDisplayText(unit))
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getStatusColor(unit))
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  private getStatusDisplayText(unit: DeviceUnit): string {
    if (unit.status === 'OFFLINE') {
      return '离线';
    } else if (unit.status === 'ON') {
      return '开启';
    } else if (unit.status === 'OFF') {
      return '关闭';
    }
    return unit.status || '未知';
  }

  private getStatusColor(unit: DeviceUnit): ResourceColor {
    if (unit.status === 'ON') {
      return '#28a745'; // 绿色 - 开启
    } else if (unit.status === 'OFF') {
      return '#dc3545'; // 红色 - 关闭
    } else if (unit.status === 'OFFLINE') {
      return '#6c757d'; // 灰色 - 离线
    }
    return '#fd7e14'; // 橘色 - 数据值
  }

  @Builder DeviceIcon(deviceName: string, customIcon?: string) {
    Column() {
      Text(customIcon || this.getIconText(deviceName))
        .fontSize(32)
    }
    .width(56)
    .height(56)
    .borderRadius(12)
    .backgroundColor('#f0f8ff')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  private getIconText(deviceName: string): string {
    switch (deviceName) {
      case '风扇':
      case '风扇_right':
        return '🌀';
      case '氧气':
        return '💨';
      case '氧气_right':
        return '🫙';
      case '喂食':
        return '🫙';
      case '喂食_right':
        return '🥣';
      case '供水':
      case '供水_right':
        return '🚰';
      case '主灯':
        return '💡';
      case '传感器':
        return '📡';
      default:
        return '⚙';
    }
  }
  
  @Builder UnitActionButtons(unit: DeviceUnit) {
    // 操作按钮
    if (unit.type === 'control') {
      this.ControlButtons(unit);
    } else {
      Row() {
        Button() {
          Text('查询')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
        }
        .width(60)
        .height(32)
        .backgroundColor($r('app.color.primary_button_background'))
        .fontColor('#ffffff')
        .borderRadius(16)
        .shadow({
          radius: 4,
          color: '#0099ff40',
          offsetX: 0,
          offsetY: 2
        })
        .onClick(() => {
          this.queryUnitStatus(unit);
        })

        Button() {
          Text('编辑')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
        }
        .width(60)
        .height(32)
        .backgroundColor($r('app.color.secondary_button_background'))
        .fontColor('#ffffff')
        .borderRadius(16)
        .shadow({
          radius: 4,
          color: '#6c757d40',
          offsetX: 0,
          offsetY: 2
        })
        .margin({ left: 6 })
        .onClick(() => {
          this.editUnit(unit);
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
  }

  @Builder ControlButtons(unit: DeviceUnit) {
    Row() {
      Button() {
        Text('开启')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
      }
      .width(60)
      .height(32)
      .backgroundColor('#0099ff')
      .fontColor('#ffffff')
      .borderRadius(16)
      .linearGradient({
        angle: 90,
        colors: [['#0099ff', 0.0], ['#00d4aa', 1.0]]
      })
      .shadow({
        radius: 4,
        color: '#0099ff40',
        offsetX: 0,
        offsetY: 2
      })
      .onClick(() => {
        this.controlUnit(unit, 'ON');
      })

      Button() {
        Text('关闭')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
      }
      .width(60)
      .height(32)
      .backgroundColor('#ffffff')
      .fontColor('#ffffff')
      .borderRadius(16)
      .linearGradient({
        angle: 90,
        colors: [['#ffffff', 0.0], ['#dc3545', 1.0]]
      })
      .shadow({
        radius: 4,
        color: '#dc354540',
        offsetX: 0,
        offsetY: 2
      })
      .margin({ left: 6 })
      .onClick(() => {
        this.controlUnit(unit, 'OFF');
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
  }

  @Builder StatusBar() {
    Row() {
      Text(`设备组数: ${this.deviceGroup.units?.length || 0}`)
        .fontSize(12)
        .fontColor('#888')
      
      Text(`在线设备: ${this.getOnlineCount()}`)
        .fontSize(12)
        .fontColor('#888')
      
      Text(`控制连接: ${this.deviceGroup.isOffline ? '未知' : '在线'}`)
        .fontSize(12)
        .fontColor('#888')
      
      Row() {
        Text('状态连接: ')
          .fontSize(12)
          .fontColor('#888')
        
        Circle()
          .width(8)
          .height(8)
          .backgroundColor(this.deviceGroup.isOffline ? '#dc3545' : '#28a745')
          .margin({ left: 4 })
      }
    }
    .width('100%')
    .height(45)
    .padding({ left: 20, right: 20 })
    .backgroundColor('#ffffff')
    .borderRadius({ topLeft: 16, topRight: 16 })
    .shadow({
      radius: 8,
      color: '#00000015',
      offsetX: 0,
      offsetY: -4
    })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .position({ x: 0, y: 'calc(100% - 45px)' })
  }

  private getOnlineCount(): number {
    return this.deviceUnits.filter(u => u.status === 'ON').length;
  }

  /**
   * 保存当前设备组的自定义图标映射到持久化存储
   */
  private async saveCurrentIcons(): Promise<void> {
    try {
      const iconMap: Record<string, string> = {};
      this.deviceUnits.forEach(unit => {
        if (unit.customIcon) {
          iconMap[unit.id] = unit.customIcon;
        }
      });
      
      if (Object.keys(iconMap).length > 0) {
        await this.iconStorage.saveIconMap(this.groupName, iconMap);
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Icons saved for group: %{public}s', [this.groupName]);
      } else {
        // 如果没有自定义图标，清除存储
        await this.iconStorage.clearIconMap(this.groupName);
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Icon map cleared for group: %{public}s', [this.groupName]);
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to save icons: %{public}s',
        [error instanceof Error ? error.message : String(error)]);
    }
  }

  private async loadDeviceGroupDetails() {
    if (!this.groupName) {
      this.loadError = '设备组名称不能为空';
      this.showToastMessage('设备组名称不能为空');
      return;
    }
    
    this.isLoading = true;
    this.loadError = '';
    
    try {
      const response = await ApiService.getInstance().getDevices();
      
      // 从响应中查找匹配的设备组
      const data = response.data;
      if (data && Array.isArray(data)) {
        const foundGroup = data.find((group: DeviceGroup) => {
          return group.groupName === this.groupName || group.name === this.groupName;
        });
        
        if (foundGroup) {
          const fg = foundGroup;
          // 从持久化存储加载自定义图标映射
          const savedIconMap = await this.iconStorage.loadIconMap(this.groupName);
          
          this.deviceUnits = (fg.units || []).map(unit => {
            const newUnit = new DeviceUnit();
            newUnit.id = unit.id;
            newUnit.name = unit.name;
            newUnit.type = unit.type;
            newUnit.status = unit.status;
            // 优先使用持久化存储中的图标，其次使用内存中的图标
            newUnit.customIcon = savedIconMap[unit.id] || '';
            return newUnit;
          });
          
          this.deviceGroup.id = fg.id;
          this.deviceGroup.name = fg.name;
          this.deviceGroup.displayName = fg.displayName || fg.name;
          this.deviceGroup.location = fg.location || '';
          this.deviceGroup.units = this.deviceUnits;
          this.deviceGroup.groupName = fg.groupName || fg.name;
          this.deviceGroup.icon = fg.icon || '';
          this.deviceGroup.hasControlUnit = (fg.units || []).some(unit => unit.type === 'control');
          this.deviceGroup.isOffline = fg.isOffline || false;
          // 添加日志确认每个单元的类型
          this.deviceUnits.forEach(unit => {
            hilog.info(LOG_DOMAIN, LOG_TAG, `Loaded unit: id=${unit.id}, name=${unit.name}, type=${unit.type}`);
          });
          this.deviceUnitsDataSource.updateData(this.deviceUnits);
          hilog.info(LOG_DOMAIN, LOG_TAG, 'Successfully loaded device group details: %{public}s', [String(this.groupName)]);
        } else {
          // 如果在API响应中找不到匹配的组，则使用默认值
          const savedIconMap = await this.iconStorage.loadIconMap(this.groupName);
          this.deviceUnits = [
            (() => { const u = new DeviceUnit(); u.id = 'fan'; u.name = '风扇'; u.type = 'control'; u.status = 'ON'; u.customIcon = savedIconMap['fan'] || ''; return u; })(),
            (() => { const u = new DeviceUnit(); u.id = 'oxygen'; u.name = '氧气'; u.type = 'control'; u.status = 'ON'; u.customIcon = savedIconMap['oxygen'] || ''; return u; })(),
            (() => { const u = new DeviceUnit(); u.id = 'feeding'; u.name = '喂食'; u.type = 'control'; u.status = 'ON'; u.customIcon = savedIconMap['feeding'] || ''; return u; })(),
            (() => { const u = new DeviceUnit(); u.id = 'water'; u.name = '供水'; u.type = 'control'; u.status = 'ON'; u.customIcon = savedIconMap['water'] || ''; return u; })()
          ];
          
          this.deviceGroup.id = this.groupName;
          this.deviceGroup.name = this.groupName;
          this.deviceGroup.displayName = this.groupName;
          this.deviceGroup.location = '';
          this.deviceGroup.units = this.deviceUnits;
          this.deviceGroup.groupName = this.groupName;
          this.deviceGroup.icon = '';
          this.deviceGroup.hasControlUnit = false;
          this.deviceGroup.isOffline = false;
          this.deviceUnitsDataSource.updateData(this.deviceUnits);
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'Device group not found in API response: %{public}s, using default data', [this.groupName]);
        }
      } else {
        this.loadError = 'API返回数据格式不正确';
        this.showToastMessage('服务器返回数据格式错误');
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Invalid API response format');
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to load device group details: %{public}s', [errorMessage]);
      this.loadError = `加载失败: ${errorMessage}`;
      this.showToastMessage(`加载设备详情失败: ${errorMessage}`);
      
      // 出错时使用默认值
      const savedIconMap = await this.iconStorage.loadIconMap(this.groupName);
      this.deviceUnits = [
        (() => { const u = new DeviceUnit(); u.id = 'fan'; u.name = '风扇'; u.type = 'control'; u.status = 'ON'; u.customIcon = savedIconMap['fan'] || ''; return u; })(),
        (() => { const u = new DeviceUnit(); u.id = 'oxygen'; u.name = '氧气'; u.type = 'control'; u.status = 'ON'; u.customIcon = savedIconMap['oxygen'] || ''; return u; })(),
        (() => { const u = new DeviceUnit(); u.id = 'feeding'; u.name = '喂食'; u.type = 'control'; u.status = 'ON'; u.customIcon = savedIconMap['feeding'] || ''; return u; })(),
        (() => { const u = new DeviceUnit(); u.id = 'water'; u.name = '供水'; u.type = 'control'; u.status = 'ON'; u.customIcon = savedIconMap['water'] || ''; return u; })()
      ];
      
      this.deviceGroup.id = this.groupName;
      this.deviceGroup.name = this.groupName;
      this.deviceGroup.displayName = this.groupName;
      this.deviceGroup.location = '';
      this.deviceGroup.units = this.deviceUnits;
      this.deviceGroup.groupName = this.groupName;
      this.deviceGroup.icon = '';
      this.deviceGroup.hasControlUnit = false;
      this.deviceGroup.isOffline = false;
      this.deviceUnitsDataSource.updateData(this.deviceUnits);
    } finally {
      // 加载所有定时任务，用于在设备单元卡片中显示
      await this.loadAllSchedules();
      
      this.isLoading = false;
    }
  }

  private getTypeText(type: string): string {
    switch (type) {
      case 'control': return '控制';
      case 'state': return '状态';
      case 'text': return '文本';
      case 'data': return '数据';
      default: return '未知';
    }
  }

  private getTypeColor(type: string): ResourceColor {
    switch (type) {
      case 'control': return '#007bff';
      case 'state': return '#28a745';
      case 'text': return '#6c757d';
      case 'data': return '#fd7e14';
      default: return '#6c757d';
    }
  }

  private isUnitOn(unit: DeviceUnit): boolean {
    return unit.status === 'ON';
  }

  private controlUnit(unit: DeviceUnit, command: string) {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Control unit %{public}s with command %{public}s', [unit.id, command]);
    
    // 直接修改目标单元的状态，V2装饰器会自动检测变化
    const targetUnit = this.deviceUnits.find(u => u.id === unit.id);
    if (targetUnit) {
      targetUnit.status = command;
      this.deviceUnitsDataSource.updateData(this.deviceUnits);
    }
    
    // 在实际应用中，这里应该调用API
    ApiService.getInstance().controlUnit(this.groupName, unit.id, command)
      .then((response: ApiResponse) => {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Successfully controlled unit: %{public}s, command: %{public}s', [unit.id, command]);
        this.showToastMessage(`设备 ${unit.name} 控制成功`);
        
        // API调用成功后，可以重新加载数据以确保状态同步
        // this.loadDeviceGroupDetails();
      })
      .catch((error: Error) => {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to control unit %{public}s: %{public}s', [unit.id, error.message]);
        this.showToastMessage(`设备 ${unit.name} 控制失败: ${error.message}`);
        
        // 如果API调用失败，回滚到之前的状态
        if (targetUnit) {
          targetUnit.status = unit.status; // 恢复原始状态
          this.deviceUnitsDataSource.updateData(this.deviceUnits);
        }
      });
  }

  private async queryUnitStatus(unit: DeviceUnit) {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Query unit %{public}s status', [unit.id]);
    
    try {
      // 在实际应用中，这里应该调用API查询状态
      const response = await ApiService.getInstance().getDevices();
      
      const data = response.data;
      if (data && Array.isArray(data)) {
        // 查找当前设备组
        const foundGroup = data.find((group: DeviceGroup) => {
          return group.groupName === this.groupName || group.name === this.groupName;
        });
        
        if (foundGroup && foundGroup.units) {
          // 查找特定单元的最新状态
          const updatedUnit = foundGroup.units.find((u: DeviceUnit) => u.id === unit.id);
          if (updatedUnit) {
            // 直接更新目标单元的状态，V2装饰器会自动检测变化
            const targetUnit = this.deviceUnits.find(u => u.id === unit.id);
            if (targetUnit) {
              targetUnit.status = updatedUnit.status;
              this.deviceUnitsDataSource.updateData(this.deviceUnits);
            }
            hilog.info(LOG_DOMAIN, LOG_TAG, 'Successfully updated unit status: %{public}s -> %{public}s', [unit.id, updatedUnit.status]);
            this.showToastMessage(`设备 ${unit.name} 状态已更新`);
          } else {
            hilog.warn(LOG_DOMAIN, LOG_TAG, 'Unit not found in API response: %{public}s', [unit.id]);
            this.showToastMessage(`设备 ${unit.name} 状态未找到`);
          }
        } else {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'Group not found or has no units: %{public}s', [this.groupName]);
          this.showToastMessage(`设备组 ${this.groupName} 未找到`);
        }
      } else {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Invalid API response format when querying unit status');
        this.showToastMessage('服务器返回数据格式错误');
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to query unit status: %{public}s', [errorMessage]);
      this.showToastMessage(`设备 ${unit.name} 状态查询失败: ${errorMessage}`);
    }
  }

  @Local showEditDialog: boolean = false;
  @Local editingUnit: DeviceUnit | null = null;
  @Local newUnitValue: string = '';

  @Builder EditDialog() {
    if (this.showEditDialog && this.editingUnit) {
      Column() {
        // 遮罩层
        Column() {
          Column() {
            // 标题
            Text(`编辑 ${this.editingUnit.name}`)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .margin({ bottom: 20 })

            // 当前值提示
            Text(`当前值: ${this.editingUnit.status}`)
              .fontSize(14)
              .fontColor('#666')
              .margin({ bottom: 15 })

            // 输入框
            TextInput({
              placeholder: '请输入新的数值'
            })
            .placeholderColor('#999')
            .padding({ left: 15, right: 15 })
            .height(45)
            .width('100%')
            .backgroundColor('#f5f5f5')
            .borderRadius(8)
            .onChange((value: string) => {
              this.newUnitValue = value;
            })
            .margin({ bottom: 20 })

            // 按钮
            Row() {
              Button() {
                Text('取消')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
              }
              .width('45%')
              .height(40)
              .backgroundColor('#e9ecef')
              .fontColor('#666')
              .borderRadius(8)
              .onClick(() => {
                this.showEditDialog = false;
                this.newUnitValue = '';
              })

              Button() {
                Text('确定')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
              }
              .width('45%')
              .height(40)
              .backgroundColor('#0066cc')
              .fontColor('#ffffff')
              .borderRadius(8)
              .margin({ left: '10%' })
              .onClick(() => {
                this.handleEditConfirm();
              })
            }
            .width('100%')
          }
          .width('80%')
          .padding(20)
          .backgroundColor(Color.White)
          .borderRadius(12)
          .shadow({
            radius: 10,
            color: '#00000030',
            offsetX: 0,
            offsetY: 4
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#00000040')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
      .zIndex(100)
    }
  }
  
  // 定时任务列表弹窗
  @Builder
  ScheduleListDialog() {
    if (this.showScheduleList) {
      Column() {
        // 遮罩层
        Column() {
          Column() {
            // 标题栏
            Row() {
              Text('定时任务管理')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor('#ffffff')
              
              Blank()
              
              Button() {
                Text('✕')
                  .fontSize(20)
                  .fontColor('#ffffff')
              }
              .width(40)
              .height(40)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.showScheduleList = false;
              })
            }
            .width('100%')
            .padding({ left: 20, right: 10, top: 15, bottom: 15 })
            
            // 设备单元选择
            Row() {
              Text('选择设备单元：')
                .fontSize(14)
                .fontColor('#ffffff')
              
              Select(this.deviceUnits.filter((unit: DeviceUnit): boolean => unit.type === 'control').map((unit: DeviceUnit): SelectOption => ({ value: unit.name })))
                .selected(this.selectedUnitForSchedule ? 
                  this.deviceUnits.filter((u: DeviceUnit): boolean => u.type === 'control').findIndex((u: DeviceUnit): boolean => u.id === this.selectedUnitForSchedule!.id) : -1)
                .value(this.selectedUnitForSchedule ? this.selectedUnitForSchedule.name : '请选择')
                .font({ size: 14 })
                .fontColor('#ffffff')
                .selectedOptionFont({ size: 14 })
                .optionFont({ size: 14 })
                .onSelect((index: number) => {
                  const controlUnits = this.deviceUnits.filter((u: DeviceUnit): boolean => u.type === 'control');
                  this.selectedUnitForSchedule = controlUnits[index];
                  this.loadSchedulesForUnit();
                })
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 10, bottom: 10 })
            
            Divider().color('#3d3d5c').margin({ left: 20, right: 20 })
            
            // 定时任务列表
            if (this.selectedUnitForSchedule) {
              Column() {
                if (this.allSchedules.length === 0) {
                  Column() {
                    Text('暂无定时任务')
                      .fontSize(16)
                      .fontColor('#999')
                      .margin({ top: 40, bottom: 20 })
                    
                    Button('创建定时任务')
                      .fontSize(16)
                      .fontColor('#fff')
                      .backgroundColor('#4CAF50')
                      .borderRadius(8)
                      .onClick(() => {
                        this.openScheduleEdit(null);
                      })
                  }
                  .width('100%')
                  .height(200)
                  .justifyContent(FlexAlign.Center)
                } else {
                  List() {
                    ForEach(this.allSchedules, (schedule: Schedule) => {
                      ListItem() {
                        Row() {
                          Column() {
                            Text(schedule.name)
                              .fontSize(16)
                              .fontWeight(FontWeight.Medium)
                              .fontColor('#ffffff')
                            
                            Text(ScheduleUtil.getDisplayTime(schedule))
                              .fontSize(12)
                              .fontColor('#e0e0e0')
                              .margin({ top: 4 })
                            
                            Text(`命令: ${schedule.cmd}`)
                              .fontSize(12)
                              .fontColor('#999')
                              .margin({ top: 2 })
                          }
                          .alignItems(HorizontalAlign.Start)
                          .layoutWeight(1)
                          
                          // 启用/禁用按钮
                          Button() {
                            Text(schedule.enabled === false ? '启用' : '禁用')
                              .fontSize(12)
                              .fontColor('#ffffff')
                          }
                          .width(60)
                          .height(28)
                          .backgroundColor(schedule.enabled === false ? '#28a745' : '#dc3545')
                          .borderRadius(14)
                          .margin({ right: 8 })
                          .onClick(() => {
                            this.toggleScheduleEnable(schedule.id, schedule.enabled !== false);
                          })
                          
                          // 编辑按钮
                          Button() {
                            Text('✎')
                              .fontSize(18)
                              .fontColor('#cccccc')
                          }
                          .width(36)
                          .height(36)
                          .backgroundColor('#3d3d5c')
                          .borderRadius(8)
                          .margin({ right: 8 })
                          .onClick(() => {
                            this.openScheduleEdit(schedule);
                          })
                          
                          // 删除按钮
                          Button() {
                            Text('🗑')
                              .fontSize(16)
                          }
                          .width(36)
                          .height(36)
                          .backgroundColor('#4a2030')
                          .borderRadius(8)
                          .onClick(() => {
                            this.deleteSchedule(schedule);
                          })
                        }
                        .width('100%')
                        .padding(15)
                        .backgroundColor('#2d2d44')
                        .borderRadius(8)
                        .margin({ bottom: 10 })
                      }
                    }, (schedule: Schedule) => schedule.id)
                  }
                  .width('100%')
                  .layoutWeight(1)
                  .padding({ left: 20, right: 20, top: 10, bottom: 10 })
                  
                  // 底部添加按钮
                  Row() {
                    Button('新建定时任务')
                      .fontSize(16)
                      .fontColor('#fff')
                      .backgroundColor('#4CAF50')
                      .borderRadius(8)
                      .width('100%')
                      .onClick(() => {
                        this.openScheduleEdit(null);
                      })
                  }
                  .width('100%')
                  .padding({ left: 20, right: 20, top: 10, bottom: 15 })
                }
              }
              .width('100%')
              .layoutWeight(1)
            } else {
              Column() {
                Text('请先选择设备单元')
                  .fontSize(16)
                  .fontColor('#999')
              }
              .width('100%')
              .height(200)
              .justifyContent(FlexAlign.Center)
            }
          }
          .width('90%')
          .height('80%')
          .backgroundColor('#1a1a2e')
          .borderRadius(16)
          .shadow({ radius: 20, color: '#00000080', offsetX: 0, offsetY: 10 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#00000080')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
      .zIndex(200)
    }
  }
  
  // 定时任务编辑弹窗
  @Builder
  ScheduleEditDialog() {
    if (this.showScheduleEdit) {
      Column() {
        // 遮罩层
        Column() {
          Column() {
            // 标题栏
            Row() {
              Text(this.editingSchedule ? '编辑定时任务' : '新建定时任务')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor('#333')
              
              Blank()
              
              Button() {
                Text('✕')
                  .fontSize(20)
                  .fontColor('#666')
              }
              .width(40)
              .height(40)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.showScheduleEdit = false;
              })
            }
            .width('100%')
            .padding({ left: 20, right: 10, top: 15, bottom: 15 })
            
            Divider()
            
            // 编辑表单
            Column() {

              // 任务名称（自动生成）
              Column({ space: 8 }) {
                Text('任务名称')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#333')
                  .alignSelf(ItemAlign.Start)
                
                Text(this.getGeneratedScheduleName())
                  .fontSize(16)
                  .fontColor('#666')
                  .width('100%')
                  .padding({ top: 8, bottom: 8, left: 12, right: 12 })
                  .backgroundColor('#f8f9fa')
                  .borderRadius(8)
              }
              .width('100%')
              .padding({ top: 15, bottom: 15, left: 20, right: 20 })
              
              // 定时类型
              Column() {
                Row() {
                  Text('定时类型：')
                    .fontSize(14)
                    .fontColor('#666')
                    .width(80)

                  Select([
                    { value: '每天' },
                    { value: '每周' },
                    { value: '一次性' }
                  ])
                    .selected(this.selectedScheduleType)
                    .value(['每天', '每周', '一次性'][this.selectedScheduleType])
                    .font({ size: 14 })
                    .fontColor('#333')
                    .onSelect((index: number) => {
                      this.selectedScheduleType = index;
                      if (!this.editingSchedule) {
                        const generatedName = this.getGeneratedScheduleName();
                        this.editingSchedule = ScheduleUtil.createDefault(this.selectedUnitForSchedule!.id);
                        this.editingSchedule.name = generatedName;
                      }
                      if (index === 0) {
                        // 每天
                        this.editingSchedule.recurring = true;
                        this.editingSchedule.interval = 86400000;
                        this.editingSchedule.weekdays = undefined;
                      } else if (index === 1) {
                        // 每周
                        this.editingSchedule.recurring = true;
                        this.editingSchedule.interval = 604800000;
                        // 更新weekdays
                        this.updateWeekdaysFromSelection();
                      } else {
                        // 一次性
                        this.editingSchedule.recurring = false;
                        this.editingSchedule.interval = 0; // 一次性任务interval设为0，而不是undefined
                        this.editingSchedule.weekdays = undefined;
                      }
                    })
                }
                .width('100%')
                .padding({ top: 10, bottom: 10, left: 20, right: 20 })

                // 星期选择（仅当选择"每周"时显示）
                if (this.selectedScheduleType === 1) {
                  Column() {
                    Text('执行日期：')
                      .fontSize(14)
                      .fontColor('#666')
                      .alignSelf(ItemAlign.Start)
                      .padding({ left: 20, bottom: 8 })

                    Row({ space: 4 }) {
                      ForEach(['一', '二', '三', '四', '五', '六', '日'], (day: string, index: number) => {

                        Button() {
                          Text(`周${day}`)
                            .fontSize(12)
                            .fontColor(this.selectedWeekdays[day === '日' ? 0 : index + 1] ? '#fff' : '#333')
                        }
                        .layoutWeight(1)
                        .height(36)
                        .backgroundColor(this.selectedWeekdays[day === '日' ? 0 : index + 1] ? '#4CAF50' : '#f0f0f0')
                        .borderRadius(18)
                        .onClick(() => {
                          this.selectedWeekdays[day === '日' ? 0 : index + 1] = !this.selectedWeekdays[day === '日' ? 0 : index + 1];
                          this.updateWeekdaysFromSelection();
                        })
                      })
                    }
                    .width('100%')
                    .padding({ left: 20, right: 20, bottom: 10 })
                  }
                  .width('100%')
                }
              }
              .width('100%')

              // 执行时间
              Column() {
                // 时间输入行
                Row() {
                  Text('执行时间：')
                    .fontSize(14)
                    .fontColor('#666')
                    .width(80)

                  TextInput({
                    placeholder: 'HH:mm',
                    text: this.formatTimeToHHMM(this.editingSchedule?.time)
                  })
                    .fontSize(14)
                    .layoutWeight(1)
                    .onChange((value: string) => {
                      if (!this.editingSchedule) {
                        const generatedName = this.getGeneratedScheduleName();
                        this.editingSchedule = ScheduleUtil.createDefault(this.selectedUnitForSchedule!.id);
                        this.editingSchedule.name = generatedName;
                      }
                      // 将HH:mm格式转换为ISO时间
                      this.editingSchedule.time = this.convertHHMMToISO(value);
                      // 解析时间并更新选择器
                      this.parseTimeAndUpdatePicker(value);
                    })
                }
                .width('100%')
                .padding({ top: 10, bottom: 5, left: 20, right: 20 })

                // 时间选择器行
                Row() {
                  Text('快速选择：')
                    .fontSize(14)
                    .fontColor('#666')
                    .width(80)

                  // 小时选择
                  Select(this.getHourOptions())
                    .value(this.selectedHour.toString().padStart(2, '0') + '时')
                    .font({ size: 14 })
                    .selectedOptionFont({ size: 14 })
                    .optionFont({ size: 14 })
                    .onSelect((index: number) => {
                      this.selectedHour = index;
                      this.updateTimeFromPicker();
                    })
                    .width(80)

                  Text(':')
                    .fontSize(14)
                    .fontColor('#666')
                    .margin({ left: 5, right: 5 })

                  // 分钟选择
                  Select(this.getMinuteOptions())
                    .value(this.selectedMinute.toString().padStart(2, '0') + '分')
                    .font({ size: 14 })
                    .selectedOptionFont({ size: 14 })
                    .optionFont({ size: 14 })
                    .onSelect((index: number) => {
                      this.selectedMinute = index;
                      this.updateTimeFromPicker();
                    })
                    .width(80)
                }
                .width('100%')
                .padding({ top: 5, bottom: 10, left: 20, right: 20 })
              }
              .width('100%')
              // 命令选择
              Row() {
                Text('执行命令：')
                  .fontSize(14)
                  .fontColor('#666')
                  .width(80)
                
                Select([
                  { value: 'ON' },
                  { value: 'OFF' },
                  { value: 'TOGGLE' }
                ])
                  .selected(this.editingSchedule ? 
                    ['ON', 'OFF', 'TOGGLE'].indexOf(this.editingSchedule.cmd) : 0)
                  .value(this.editingSchedule?.cmd || 'ON')
                  .font({ size: 14 })
                  .fontColor('#333')
                  .onSelect((index: number) => {
                    const cmds = ['ON', 'OFF', 'TOGGLE'];
                    if (!this.editingSchedule) {
                      this.editingSchedule = ScheduleUtil.createDefault(this.selectedUnitForSchedule!.id);
                    }
                    this.editingSchedule.cmd = cmds[index];
                  })
              }
              .width('100%')
              .padding({ top: 10, bottom: 10, left: 20, right: 20 })
              
              // 启用状态
              Row() {
                Text('启用状态：')
                  .fontSize(14)
                  .fontColor('#666')
                  .width(80)
                
                Toggle({ type: ToggleType.Switch, isOn: this.editingSchedule?.enabled ?? true })
                  .onChange((isOn: boolean) => {
                    if (!this.editingSchedule) {
                      this.editingSchedule = ScheduleUtil.createDefault(this.selectedUnitForSchedule!.id);
                    }
                    this.editingSchedule.enabled = isOn;
                  })
              }
              .width('100%')
              .padding({ top: 10, bottom: 15, left: 20, right: 20 })
            }
            .width('100%')
            
            Divider()
            
            // 底部按钮
            Row() {
              Button('取消')
                .fontSize(16)
                .fontColor('#666')
                .backgroundColor('#f0f0f0')
                .borderRadius(8)
                .layoutWeight(1)
                .onClick(() => {
                  this.showScheduleEdit = false;
                })
              
              Blank().width(20)
              
              Button('保存')
                .fontSize(16)
                .fontColor('#fff')
                .backgroundColor('#4CAF50')
                .borderRadius(8)
                .layoutWeight(1)
                .onClick(() => {
                  this.saveSchedule();
                })
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 15, bottom: 20 })
          }
          .width('85%')
          .backgroundColor('#ffffff')
          .borderRadius(16)
          .shadow({ radius: 20, color: '#00000040', offsetX: 0, offsetY: 10 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#00000080')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
      .zIndex(300)
    }
  }

  private editUnit(unit: DeviceUnit) {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Edit unit %{public}s', [unit.id]);
    this.editingUnit = unit;
    this.newUnitValue = unit.status;
    this.showEditDialog = true;
  }

  private handleEditConfirm() {
    if (!this.editingUnit) return;
    
    const newValue = this.newUnitValue.trim();
    if (newValue === '') {
      this.showToastMessage('请输入值');
      return;
    }
    
    // 根据设备单元类型进行不同的验证
    if (this.editingUnit.type === 'data') {
      // 数字类型需要验证是否为有效数字
      if (isNaN(parseFloat(newValue))) {
        this.showToastMessage('请输入有效的数字');
        return;
      }
    }
    // text类型不需要数字验证，允许任何文本输入
    
    // 更新本地状态
    const targetUnit = this.deviceUnits.find(u => u.id === this.editingUnit!.id);
    if (targetUnit) {
      targetUnit.status = newValue;
      this.deviceUnitsDataSource.updateData(this.deviceUnits);
      
      // 根据单元类型调用对应的API接口
      const apiService = ApiService.getInstance();
      let updatePromise: Promise<ApiResponse>;
      
      if (this.editingUnit!.type === 'text') {
        updatePromise = apiService.setTextValue(this.editingUnit!.id, newValue);
      } else if (this.editingUnit!.type === 'data') {
        updatePromise = apiService.setDataValue(this.editingUnit!.id, newValue);
      } else {
        updatePromise = apiService.updateUnit(this.groupName, this.editingUnit!.id, newValue, this.editingUnit!.type);
      }
      
      updatePromise
        .then((response: ApiResponse) => {
          hilog.info(LOG_DOMAIN, LOG_TAG, 'Successfully updated unit %{public}s with value %{public}s', [this.editingUnit!.id, newValue]);
          this.showToastMessage(`${this.editingUnit!.name} 值已更新为 ${newValue}`);
        })
        .catch((error: Error) => {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'API update unit failed: %{public}s', [error.message]);
          // 后端API可能未实现或连接失败，但本地更新已成功
          this.showToastMessage(`${this.editingUnit!.name} 值已更新为 ${newValue}（本地）`);
        })
        .finally(() => {
          this.showEditDialog = false;
          this.newUnitValue = '';
        });
    }
  }
  
  // 定时任务相关方法
  private openScheduleList(): void {
    this.showScheduleList = true;
    // 默认选择第一个设备单元
    if (this.deviceUnits.length > 0 && !this.selectedUnitForSchedule) {
      this.selectedUnitForSchedule = this.deviceUnits[0];
      this.loadSchedulesForUnit();
    }
  }
  
  private async loadSchedulesForUnit(): Promise<void> {
    if (!this.selectedUnitForSchedule) {
      return;
    }
    
    try {
      const response = await this.scheduleService.getAllSchedules();
      if (response.code === 200 && response.schedules) {
        // 将对象转换为数组
        const allSchedulesArray: Schedule[] = [];
        const scheduleKeys = Object.keys(response.schedules);
        for (let i = 0; i < scheduleKeys.length; i++) {
          const key = scheduleKeys[i];
          allSchedulesArray.push(response.schedules[key]);
        }
        // 缓存所有定时任务（用于设备单元卡片显示）
        this.allSchedulesCache = allSchedulesArray;
        // 过滤出当前设备单元的定时任务
        this.allSchedules = allSchedulesArray.filter((s: Schedule) => s.unitId === this.selectedUnitForSchedule!.id);
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Loaded %{public}d schedules for unit %{public}s', 
          [this.allSchedules.length, this.selectedUnitForSchedule.id]);
      } else {
        this.allSchedules = [];
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to load schedules: %{public}s', [String(error)]);
      this.allSchedules = [];
    }
  }

  // 获取某个设备单元的定时任务
  // 加载所有定时任务（用于在设备单元卡片中显示）
  private async loadAllSchedules(): Promise<void> {
    try {
      const response = await this.scheduleService.getAllSchedules();
      const allSchedulesArray: Schedule[] = [];
      const scheduleKeys = Object.keys(response.schedules);
      for (let i = 0; i < scheduleKeys.length; i++) {
        const key = scheduleKeys[i];
        allSchedulesArray.push(response.schedules[key]);
      }
      
      this.allSchedulesCache = allSchedulesArray; // 缓存所有定时任务
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Loaded all schedules for unit cards: %{public}d', [this.allSchedulesCache.length]);
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to load all schedules: %{public}s', [(error as Error).message]);
    }
  }

  private getSchedulesForUnit(unitId: string): Schedule[] {
    return this.allSchedulesCache.filter((s: Schedule) => s.unitId === unitId);
  }

  // 从时间选择器更新时间
  private updateTimeFromPicker(): void {
    if (!this.editingSchedule) {
      const generatedName = this.getGeneratedScheduleName();
      this.editingSchedule = ScheduleUtil.createDefault(this.selectedUnitForSchedule!.id);
      this.editingSchedule.name = generatedName;
    }
    const hourStr = this.selectedHour.toString().padStart(2, '0');
    const minuteStr = this.selectedMinute.toString().padStart(2, '0');
    this.editingSchedule.time = `${hourStr}:${minuteStr}`;
  }

  // 解析时间文本并更新选择器
  private parseTimeAndUpdatePicker(time: string): void {
    if (!time) {
      return;
    }
    const parts = time.split(':');
    if (parts.length === 2) {
      const hour = parseInt(parts[0], 10);
      const minute = parseInt(parts[1], 10);
      if (!isNaN(hour) && hour >= 0 && hour < 24) {
        this.selectedHour = hour;
      }
      if (!isNaN(minute) && minute >= 0 && minute < 60) {
        this.selectedMinute = minute;
      }
    }
  }

  // 格式化ISO时间为HH:mm格式
  private formatTimeToHHMM(isoTime: string | undefined): string {
    if (!isoTime) {
      // 如果没有时间，返回当前时间
      const now = new Date();
      return `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
    }
    
    try {
      const date = new Date(isoTime);
      if (isNaN(date.getTime())) {
        // 如果不是有效的ISO时间，尝试直接解析HH:mm格式
        const parts = isoTime.split(':');
        if (parts.length === 2) {
          return isoTime;
        }
        // 返回当前时间
        const now = new Date();
        return `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
      }
      const hours = String(date.getHours()).padStart(2, '0');
      const minutes = String(date.getMinutes()).padStart(2, '0');
      return `${hours}:${minutes}`;
    } catch (error) {
      // 出错时返回当前时间
      const now = new Date();
      return `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
    }
  }

  // 将HH:mm格式转换为ISO时间
  private convertHHMMToISO(hhmm: string): string {
    const parts = hhmm.split(':');
    if (parts.length !== 2) {
      return new Date().toISOString();
    }
    
    const hour = parseInt(parts[0], 10);
    const minute = parseInt(parts[1], 10);
    
    if (isNaN(hour) || isNaN(minute) || hour < 0 || hour >= 24 || minute < 0 || minute >= 60) {
      return new Date().toISOString();
    }
    
    const now = new Date();
    now.setHours(hour, minute, 0, 0);
    
    // 如果时间已过，设置为明天
    if (now.getTime() <= Date.now()) {
      now.setDate(now.getDate() + 1);
    }
    
    return now.toISOString();
  }

  // 生成小时选项
  private getHourOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (let i = 0; i < 24; i++) {
      options.push({ value: i.toString().padStart(2, '0') + '时' });
    }
    return options;
  }

  // 生成分钟选项
  private getMinuteOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (let i = 0; i < 60; i++) {
      options.push({ value: i.toString().padStart(2, '0') + '分' });
    }
    return options;
  }

  // 从选择更新weekdays
  private updateWeekdaysFromSelection(): void {
    if (!this.editingSchedule) {
      const generatedName = this.getGeneratedScheduleName();
      this.editingSchedule = ScheduleUtil.createDefault(this.selectedUnitForSchedule!.id);
      this.editingSchedule.name = generatedName;
    }
    const weekdays: number[] = [];
    for (let i = 0; i < 7; i++) {
      if (this.selectedWeekdays[i]) {
        weekdays.push(i);
      }
    }
    this.editingSchedule.weekdays = weekdays.length > 0 ? weekdays : undefined;
  }

  // 从weekdays初始化选择
  private initWeekdaysSelection(weekdays: number[] | undefined): void {
    // 重置所有选择
    for (let i = 0; i < 7; i++) {
      this.selectedWeekdays[i] = false;
    }
    // 设置选中的星期
    if (weekdays && weekdays.length > 0) {
      for (const day of weekdays) {
        if (day >= 0 && day < 7) {
          this.selectedWeekdays[day] = true;
        }
      }
    }
  }
  
  private openScheduleEdit(schedule: Schedule | null): void {
    if (schedule) {
      // 复制schedule对象
      this.editingSchedule = {
        id: schedule.id,
        name: schedule.name,
        unitId: schedule.unitId,
        cmd: schedule.cmd,
        time: schedule.time,
        recurring: schedule.recurring,
        interval: schedule.interval,
        weekdays: schedule.weekdays,
        enabled: schedule.enabled
      };
      // 初始化定时类型选择
      if (schedule.recurring === false) {
        this.selectedScheduleType = 2; // 一次性
      } else if (schedule.interval === 604800000) {
        this.selectedScheduleType = 1; // 每周
      } else {
        this.selectedScheduleType = 0; // 每天
      }
      // 初始化星期选择
      this.initWeekdaysSelection(schedule.weekdays);
      // 初始化时间选择器
      if (schedule.time) {
        this.parseTimeAndUpdatePicker(schedule.time);
      }
    } else {
      // 创建新任务，先生成名称，再创建对象
      const generatedName = this.getGeneratedScheduleName();
      this.editingSchedule = ScheduleUtil.createDefault(this.selectedUnitForSchedule!.id);
      this.editingSchedule.name = generatedName;
      // 重置选择状态
      this.selectedScheduleType = 0; // 默认每天
      this.initWeekdaysSelection(undefined);
      // 设置当前时间
      const now = new Date();
      this.selectedHour = now.getHours();
      this.selectedMinute = now.getMinutes();
      // 更新时间字段为当前时间
      this.editingSchedule.time = this.convertHHMMToISO(
        `${String(this.selectedHour).padStart(2, '0')}:${String(this.selectedMinute).padStart(2, '0')}`
      );
    }
    this.showScheduleEdit = true;
  }
  
  private async saveSchedule(): Promise<void> {
    if (!this.editingSchedule) {
      return;
    }
    
    // 如果是新建任务，自动生成名称
    if (!this.editingSchedule.id && !this.editingSchedule.name) {
      this.editingSchedule.name = this.getGeneratedScheduleName();
    }

    // 验证必填字段
    if (!this.editingSchedule.time) {
      this.showToastMessage('请填写执行时间');
      return;
    }
    
    try {
      // 如果是新建任务，生成ID
      let scheduleId = this.editingSchedule.id;
      if (!scheduleId) {
        // 生成ID格式：设备组ID_设备单元ID-唯一顺序号
        const groupId = this.deviceGroup.id || this.groupName;
        const unitId = this.editingSchedule.unitId;
        const timestamp = Date.now();
        scheduleId = `${groupId}_${unitId}-${timestamp}`;
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Generated schedule ID: %{public}s', [scheduleId]);
      }

      // 构建ScheduleRequest对象
      const scheduleRequest: ScheduleRequest = {
        id: scheduleId,
        name: this.editingSchedule.name,
        unitId: this.editingSchedule.unitId,
        cmd: this.editingSchedule.cmd,
        time: this.editingSchedule.time,
        recurring: this.editingSchedule.recurring,
        interval: this.editingSchedule.interval,
        weekdays: this.editingSchedule.weekdays
      };
      
      if (this.editingSchedule.id) {
        // 更新现有任务
        await this.scheduleService.updateSchedule(this.editingSchedule.id, scheduleRequest);
        this.showToastMessage('定时任务已更新');
      } else {
        // 创建新任务：根据任务类型选择不同的API
        if (scheduleRequest.recurring && scheduleRequest.interval && scheduleRequest.interval > 0) {
          // 重复任务使用专门的API
          await this.scheduleService.createRecurringSchedule(scheduleRequest);
          hilog.info(LOG_DOMAIN, LOG_TAG, 'Created recurring schedule with interval: %{public}d', [scheduleRequest.interval || 0]);
        } else {
          // 一次性任务使用普通API
          await this.scheduleService.createSchedule(scheduleRequest);
          hilog.info(LOG_DOMAIN, LOG_TAG, 'Created one-time schedule');
        }
        this.showToastMessage('定时任务已创建');
      }
      
      this.showScheduleEdit = false;
      this.editingSchedule = null;
      await this.loadSchedulesForUnit();
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to save schedule: %{public}s', [String(error)]);
      this.showToastMessage('保存失败，请重试');
    }
  }
  
  private async deleteSchedule(schedule: Schedule): Promise<void> {
    try {
      await this.scheduleService.deleteSchedule(schedule.id);
      this.showToastMessage('定时任务已删除');
      await this.loadSchedulesForUnit();
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to delete schedule: %{public}s', [String(error)]);
      this.showToastMessage('删除失败，请重试');
    }
  }
  
  private async toggleScheduleEnable(scheduleId: string, currentEnable: boolean): Promise<void> {
    try {
      const response = await this.scheduleService.toggleScheduleEnable(scheduleId, !currentEnable);
      
      if (response.code === 200) {
        this.showToastMessage(currentEnable ? '已禁用' : '已启用');
        await this.loadSchedulesForUnit();
      } else {
        this.showToastMessage(response.msg || '操作失败');
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Toggle schedule error: %{public}s', [(error as Error).message]);
      this.showToastMessage('操作失败');
    }
  }

  private async toggleScheduleEnabled(schedule: Schedule, enabled: boolean): Promise<void> {
    try {
      // 使用专门的toggleScheduleEnable方法
      const response = await this.scheduleService.toggleScheduleEnable(schedule.id, enabled);
      
      if (response.code === 200) {
        this.showToastMessage(enabled ? '已启用' : '已禁用');
        await this.loadSchedulesForUnit();
      } else {
        this.showToastMessage(response.msg || '状态切换失败');
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to toggle schedule: %{public}s', [String(error)]);
      this.showToastMessage('状态切换失败');
    }
  }

  @Builder PageConfigDialog() {
    Column() {
      Column() {
        Row() {
          Text('页面配置')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333')
          Blank()
          Button() {
            Text('✕')
              .fontSize(16)
              .fontColor('#666')
          }
          .width(32)
          .height(32)
          .backgroundColor('#f5f5f5')
          .borderRadius(16)
          .onClick(() => {
            this.showPageConfig = false;
            this.selectedUnitForIconChange = null;
          })
        }
        .width('100%')
        .padding({ top: 20, bottom: 15, left: 20, right: 20 })
        .border({
          width: { bottom: 1 },
          color: '#f0f0f0'
        })

        Scroll() {
          Column({ space: 12 }) {
            Text('设备单元图标')
              .fontSize(14)
              .fontColor('#666')
              .margin({ top: 10 })

            ForEach(this.deviceUnits, (unit: DeviceUnit) => {
              Row() {
                this.DeviceIcon(unit.name, unit.customIcon)

                Column() {
                  Text(unit.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#333')
                  Text(unit.customIcon ? '已自定义' : '默认图标')
                    .fontSize(12)
                    .fontColor('#999')
                }
                .layoutWeight(1)

                Button() {
                  Text('更换')
                    .fontSize(14)
                    .fontColor('#4CAF50')
                }
                .width(60)
                .height(32)
                .backgroundColor('#e8f5e9')
                .borderRadius(16)
                .onClick(() => {
                  this.selectedUnitForIconChange = unit;
                })
              }
              .width('100%')
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .backgroundColor('#fafafa')
              .borderRadius(12)
            }, (unit: DeviceUnit) => `${unit.id}_${this.iconUpdateTrigger}`)
          }
          .padding({ left: 20, right: 20, bottom: 20 })
        }
        .layoutWeight(1)
        .width('100%')

        Button() {
          Text('关闭')
            .fontSize(16)
            .fontColor('#fff')
        }
        .width('100%')
        .height(48)
        .backgroundColor('#4CAF50')
        .borderRadius(24)
        .margin({ bottom: 20, left: 20, right: 20 })
        .onClick(() => {
          this.showPageConfig = false;
          this.selectedUnitForIconChange = null;
        })
      }
      .width('90%')
      .height('80%')
      .backgroundColor('#ffffff')
      .borderRadius(20)
      .shadow({
        radius: 16,
        color: '#00000030',
        offsetX: 0,
        offsetY: 8
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#00000050')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (this.selectedUnitForIconChange) {
        this.selectedUnitForIconChange = null;
      }
    })

    if (this.selectedUnitForIconChange) {
      Column() {
        Column() {
          Row() {
            Text('选择图标')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333')
            Blank()
            Button() {
              Text('✕')
                .fontSize(16)
                .fontColor('#666')
            }
            .width(32)
            .height(32)
            .backgroundColor('#f5f5f5')
            .borderRadius(16)
            .onClick(() => {
              this.selectedUnitForIconChange = null;
            })
          }
          .width('100%')
          .padding({ top: 20, bottom: 15, left: 20, right: 20 })
          .border({
          width: { bottom: 1 },
          color: '#f0f0f0'
        })

          Scroll() {
            Grid() {
              ForEach(DeviceIcons, (item: IconItem) => {
                GridItem() {
                  Column({ space: 4 }) {
                    Text(item.icon)
                      .fontSize(28)
                    Text(item.label)
                      .fontSize(10)
                      .fontColor('#999')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .width('100%')
                  .height(60)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .backgroundColor(this.selectedUnitForIconChange?.customIcon === item.icon ? '#e8f5e9' : '#fafafa')
                  .borderRadius(12)
                  .border({ width: 2, color: this.selectedUnitForIconChange?.customIcon === item.icon ? '#4CAF50' : 'transparent' })
                  .onClick(() => {
                    const selectedUnit = this.selectedUnitForIconChange;
                    if (selectedUnit) {
                      const unitIndex = this.deviceUnits.findIndex(u => u.id === selectedUnit.id);
                      if (unitIndex >= 0) {
                        this.deviceUnits[unitIndex].customIcon = item.icon;
                        if (this.deviceGroup.units) {
                          const groupUnitIndex = this.deviceGroup.units.findIndex(u => u.id === selectedUnit.id);
                          if (groupUnitIndex >= 0) {
                            this.deviceGroup.units[groupUnitIndex].customIcon = item.icon;
                          }
                        }
                        // 持久化保存图标
                        this.saveCurrentIcons();
                      }
                    }
                    this.selectedUnitForIconChange = null;
                    this.showToastMessage('图标已更换');
                    this.iconUpdateTrigger++;
                    this.deviceUnitsDataSource.updateData([...this.deviceUnits]);
                  })
                }
              }, (item: IconItem) => item.key)
            }
            .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
            .columnsGap(8)
            .rowsGap(8)
            .padding({ left: 16, right: 16, bottom: 16 })
          }
          .layoutWeight(1)
          .width('100%')

          Button() {
            Text('恢复默认')
              .fontSize(14)
              .fontColor('#666')
          }
          .width('100%')
          .height(40)
          .backgroundColor('#f5f5f5')
          .borderRadius(20)
          .margin({ bottom: 10, left: 20, right: 20 })
          .onClick(() => {
            const selectedUnit = this.selectedUnitForIconChange;
            if (selectedUnit) {
              const unitIndex = this.deviceUnits.findIndex(u => u.id === selectedUnit.id);
              if (unitIndex >= 0) {
                this.deviceUnits[unitIndex].customIcon = '';
                if (this.deviceGroup.units) {
                  const groupUnitIndex = this.deviceGroup.units.findIndex(u => u.id === selectedUnit.id);
                  if (groupUnitIndex >= 0) {
                    this.deviceGroup.units[groupUnitIndex].customIcon = '';
                  }
                }
                // 持久化保存图标
                this.saveCurrentIcons();
              }
            }
            this.selectedUnitForIconChange = null;
            this.showToastMessage('已恢复默认图标');
            this.iconUpdateTrigger++;
            this.deviceUnitsDataSource.updateData([...this.deviceUnits]);
          })
        }
        .width('90%')
        .height('70%')
        .backgroundColor('#ffffff')
        .borderRadius(20)
        .shadow({
          radius: 16,
          color: '#00000030',
          offsetX: 0,
          offsetY: 8
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#00000050')
      .justifyContent(FlexAlign.Center)
    }
  }
}