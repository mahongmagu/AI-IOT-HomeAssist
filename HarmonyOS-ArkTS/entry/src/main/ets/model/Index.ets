import router from '@ohos.router';
import hilog from '@ohos.hilog';
import promptAction from '@ohos.promptAction';
import { BusinessError } from '@kit.BasicServicesKit';


import { ServerConfig } from '../model/ServerConfig';
import { VoiceInputUtil } from '../utils/VoiceInputUtil';
import { ApiService, ApiResponse } from '../services/ApiService';
import { WebSocketService, StateUpdateMessage } from '../services/WebSocketService';
import { IndexData } from '../model/IndexData';
import { DeviceGroup, DeviceUnit } from '../model/DeviceModel';
import { DeviceGroupDataSource } from '../utils/DataSource';

// 常量定义
const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'Index';



@Entry
@ComponentV2
struct Index {
  @Local indexData: IndexData = new IndexData();
  private deviceGroupsDataSource: DeviceGroupDataSource = new DeviceGroupDataSource([]);
  
  private ipInputController: TextInputController = new TextInputController();
  private portInputController: TextInputController = new TextInputController();
  private aiTextInputController: TextInputController = new TextInputController();
  private aiInputText: string = '';
  
  // Method to show toast using promptAction
  private showToastMessage(message: string): void {
    try {
      promptAction.showToast({
        message: message,
        duration: 1500
      });
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to show toast: %{public}s', [error instanceof Error ? error.message : String(error)]);
    }
  }

  aboutToAppear() {
    if (!ServerConfig.isConfigured()) {
      this.indexData.showConfigPage = true;
    } else {
      this.connectToServer();
    }
  }

  // 当页面重新显示时（从详情页返回），刷新设备状态
  onShow() {
    if (ServerConfig.isConfigured() && !this.indexData.showConfigPage) {
      this.loadDeviceGroups();
    }
  }

  aboutToDisappear() {
    // 页面消失时关闭WebSocket连接
    WebSocketService.getInstance().disconnect();
  }

  build() {
    Column() {
      if (this.indexData.showConfigPage || !ServerConfig.isConfigured()) {
        // 配置页面 - 首次启动时需要输入服务端IP地址或域名
        this.ConfigurationPage();
      } else {
        // 主页面
        this.MainPage();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }

  @Builder ConfigurationPage() {
    Column() {
      Image($r('app.media.icon'))
        .width(80)
        .height(80)
        .margin({ top: 80, bottom: 30 })

      Text('IoT设备控制系统')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 50 })

      Column() {
        Text('服务端配置')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: 20 })

        TextInput({
          controller: this.ipInputController,
          placeholder: '请输入服务端IP地址或域名'
        })
        .placeholderColor('#999')
        .padding({ left: 15, right: 15 })
        .height(50)
        .width('90%')
        .backgroundColor('#f5f5f5')
        .borderRadius(8)
        .onChange((value: string) => {
          this.indexData.serverIp = value;
        })
        .margin({ bottom: 15 })

        TextInput({
          controller: this.portInputController,
          placeholder: '端口号 (默认8080)'
        })
        .placeholderColor('#999')
        .padding({ left: 15, right: 15 })
        .height(50)
        .width('90%')
        .backgroundColor('#f5f5f5')
        .borderRadius(8)
        .onChange((value: string) => {
          this.indexData.serverPort = value;
        })
        .margin({ bottom: 30 })

        Button() {
          Text('保存配置并连接')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .height('100%')
        }
        .width('90%')
        .height(50)
        .backgroundColor('#0066cc')
        .borderRadius(8)
        .onClick(() => {
          this.saveServerConfig();
        })
      }
      .width('100%')
      .padding({ top: 20 })
      .backgroundColor('#f5f5f5')
      .margin({ left: 20, right: 20 })
      .borderRadius(12)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder MainPage() {
    Column() {
      // 顶部状态栏
      Row() {
        Text(`服务器: ${ServerConfig.getServerAddress()}`)
          .fontSize(12)
          .fontColor('#666')
        
        if (this.indexData.isConnected) {
          Text('● 已连接')
            .fontSize(12)
            .fontColor('#28a745')
            .margin({ left: 10 })
        } else {
          Text('○ 未连接')
            .fontSize(12)
            .fontColor('#dc3545')
            .margin({ left: 10 })
        }
      }
      .width('100%')
      .height(40)
      .padding({ left: 20, right: 20 })
      .justifyContent(FlexAlign.Start)
      .alignItems(VerticalAlign.Center)

      // 设备网格 - Wrap cards in containers that support width/spacing
      Scroll() {
        Column() {
          LazyForEach(this.deviceGroupsDataSource, (item: DeviceGroup) => {
            Row() {
              this.DeviceCard(item)
            }
            .width('95%') // Width applied to container
            .margin({ bottom: 15 }) // Margin applied to container
          }, (item: DeviceGroup) => item.groupName)
        }
        .padding({ top: 15, left: 15, right: 15 })
        .width('100%')
      }
      .width('100%')
      .height(0)
      .scrollBar(BarState.Off)
      .layoutWeight(1)

      // AI控制面板
      this.AiControlPanel()
      
      // 底部状态栏
      this.BottomStatusBar()
    }
    .width('100%')
    .height('100%')
  }
  
  @Builder BottomStatusBar() {
    Row() {
      // 设备组数
      Row() {
        Text('设备组数:')
          .fontSize(11)
          .fontColor('#666')
          .margin({ right: 4 })
        Text(`${this.indexData.totalGroups}`)
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333')
      }
      .alignItems(VerticalAlign.Center)
      
      // 在线设备
      Row() {
        Text('在线设备:')
          .fontSize(11)
          .fontColor('#666')
          .margin({ right: 4, left: 10 })
        Text(`${this.indexData.onlineDevices}`)
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333')
      }
      .alignItems(VerticalAlign.Center)
      
      // 控制连接状态
      Row() {
        Text('控制连接:')
          .fontSize(11)
          .fontColor('#666')
          .margin({ right: 4, left: 10 })
        if (this.indexData.isConnected) {
          Text('已连接')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor('#28a745')
        } else {
          Text('未连接')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor('#dc3545')
        }
      }
      .alignItems(VerticalAlign.Center)
      
      // 添加占位元素以推动其他内容靠左
      Text('')
        .layoutWeight(1)
    }
    .width('100%')
    .height(30)
    .padding({ left: 20, right: 20 })
    .backgroundColor('#f8f9fa')
    .justifyContent(FlexAlign.Start)
    .alignItems(VerticalAlign.Center)
  }



  @Builder DeviceCard(group: DeviceGroup) {
    Column() {
      Column() {
        this.DeviceIconAndPowerButton(group)
        this.DeviceInfoSection(group)
      }
    }
    .width('100%')
    .height(140)
    .margin({ bottom: 15 })
    .backgroundColor('#f5f5f5')
    .borderRadius(16)
    .shadow({
      radius: 4,
      color: '#00000020',
      offsetX: 0,
      offsetY: 2
    })
    .onClick(() => {
      try {
        // 使用最新的导航API替代已弃用的pushUrl
        router.pushUrl({
          url: 'pages/DeviceDetail',
          params: { groupName: group.groupName }
        }, router.RouterMode.Single, (err) => {
          if (err) {
            hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to navigate to DeviceDetail: %{public}s', [err.message]);
            this.showToastMessage('页面跳转失败');
          }
        });
      } catch (error) {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to navigate to DeviceDetail: %{public}s', [(error as Error).message]);
        this.showToastMessage('页面跳转失败');
      }
    })
  }
  
  @Builder DeviceIconAndPowerButton(group: DeviceGroup) {
    // 设备图标和电源按钮
    Row() {
      Text(group.icon)
        .fontSize(40)
        .width('100%')
        .height(100)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.getGroupStatusColor(group))
        .borderRadius(16)
      
      if (group.hasControlUnit && !group.isOffline) {
        Button() {
          Text('🔘')
            .fontSize(24)
        }
        .width(36)
        .height(36)
        .backgroundColor('#f5f5f5')
        .borderRadius(18)
        .position({ x: 12, y: 12 })
        .zIndex(10)
        .onClick(() => {
          this.toggleAllUnits(group.groupName);
        })
      }
    }
    .width('100%')
    .height(100)
    .backgroundColor(this.getGroupStatusColor(group))
    .borderRadius(16)
  }
  
  @Builder DeviceInfoSection(group: DeviceGroup) {
    // 设备信息
    Column() {
      Text(group.displayName || group.groupName)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 10, bottom: 5 })

      if (group.location) {
        Text(`📍 ${group.location}`)
          .fontSize(11)
          .fontColor('#666')
      }

      if (group.isOffline) {
        Text('⚠️ 离线')
          .fontSize(10)
          .fontColor('#dc3545')
          .margin({ top: 2 })
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }

  @Builder AiControlPanel() {
    Column() {
      this.AiControlTitle()
      this.AiInputRow()
      this.AiResultDisplay()
    }
    .width('100%')
    .padding({ top: 20, left: 15, right: 15 })
    .backgroundColor('#f5f5f5')
    .margin({ top: 10 })
    .borderRadius(12)
  }
  
  @Builder AiControlTitle() {
    Text('🤖 AI语音文字控制')
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .margin({ bottom: 15 })
  }
  
  @Builder AiInputRow() {
    Row() {
      TextInput({
        controller: this.aiTextInputController,
        placeholder: '请输入指令：打开扫地机/关闭风扇...'
      })
      .placeholderColor('#999')
      .padding({ left: 15, right: 15 })
      .height(50)
      .width('70%')
      .backgroundColor('#f5f5f5')
      .borderRadius(8)
      .onChange((value: string) => {
        this.indexData.aiInputText = value;
      })

      // 华为小艺语音输入按钮
      Button() {
        Text('🎤')
          .fontSize(20)
      }
      .width(50)
      .height(50)
      .backgroundColor('#0066cc')
      .borderRadius(25)
      .onClick(() => {
        this.startVoiceInput();
      })
      .margin({ left: 10 })

      Button() {
        Text('发送')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .width('100%')
          .height('100%')
      }
      .width('20%')
      .height(50)
      .backgroundColor('#28a745')
      .borderRadius(8)
      .onClick(() => {
        this.sendAiCommand();
      })
    }
    .width('100%')
    .margin({ bottom: 15 })
  }
  
  @Builder AiResultDisplay() {
    if (this.indexData.aiResult) {
      Text(this.indexData.aiResult)
        .fontSize(14)
        .margin({ top: 5 })
        .padding({ left: 15, right: 15, top: 10, bottom: 10 })
        .backgroundColor('#f8f9fa')
        .borderRadius(8)
        .width('100%')
        .maxLines(5)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }

  private saveServerConfig() {
    if (!this.indexData.serverIp) {
      this.showToastMessage('请输入服务端IP地址或域名');
      return;
    }
    
    try {
        ServerConfig.setServerAddress(this.indexData.serverIp, parseInt(this.indexData.serverPort || '8080'));
        // 同时设置WebSocket配置，使用固定的8090端口（根据后端配置）
        ServerConfig.setWebSocketConfig(8090, '/');
      } catch (error) {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to set server address: %{public}s', [(error as Error).message]);
        this.showToastMessage('保存服务器配置失败');
        return;
      }
    this.indexData.showConfigPage = false;
    this.connectToServer();
  }

  private connectToServer() {
    // 连接到服务端的逻辑
    this.indexData.isConnected = true;
    this.loadDeviceGroups();
    
    // 初始化WebSocket连接以接收实时状态更新
    this.initWebSocket();
  }

  private initWebSocket(): void {
    const wsService = WebSocketService.getInstance();
    
    // 设置状态更新回调
    wsService.setCallback((message: StateUpdateMessage) => {
      this.handleStateUpdate(message);
    });
    
    // 设置连接状态回调
    wsService.setConnectionCallback((connected: boolean) => {
      this.indexData.isConnected = connected;
      if (!connected) {
        this.showToastMessage('WebSocket连接断开，正在尝试重连...');
      }
    });
    
    // 建立连接
    wsService.connect();
  }

  private handleStateUpdate(message: StateUpdateMessage): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, `Handling state update for unit: ${message.device.unit}, state: ${message.state}`);
    
    const oldDeviceGroups = [...this.indexData.deviceGroups]; // 保存旧数据用于对比
    
    // 更新设备组状态 - 创建新的数组和对象来触发UI更新
    let updatedDeviceGroups = WebSocketService.getInstance().updateDeviceGroupState(
      this.indexData.deviceGroups,
      message
    );
    
    // 检查是否有实际更新发生
    let updateOccurred = false;
    for (let i = 0; i < oldDeviceGroups.length; i++) {
      const oldGroup = oldDeviceGroups[i];
      const newGroup = updatedDeviceGroups[i];
      
      if (JSON.stringify(oldGroup) !== JSON.stringify(newGroup)) {
        updateOccurred = true;
        hilog.info(LOG_DOMAIN, LOG_TAG, `Device group updated: ${newGroup.groupName}, units: ${JSON.stringify(newGroup.units)}`);
      }
    }
    
    if (!updateOccurred) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, `No device group was updated for unit: ${message.device.unit}`);
    }
    
    // Create new array reference to trigger UI update
    // Create new instances of DeviceGroup and DeviceUnit to ensure deep observation
    this.indexData.deviceGroups = updatedDeviceGroups.map(group => {
      const newGroup = new DeviceGroup();
      newGroup.id = group.id;
      newGroup.name = group.name;
      newGroup.groupName = group.groupName;
      newGroup.displayName = group.displayName;
      newGroup.location = group.location;
      newGroup.icon = group.icon;
      newGroup.hasControlUnit = group.hasControlUnit;
      newGroup.isOffline = group.isOffline;
      
      // Copy units with new instances
      if (group.units) {
        newGroup.units = group.units.map(unit => {
          const newUnit = new DeviceUnit();
          newUnit.id = unit.id;
          newUnit.name = unit.name;
          newUnit.type = unit.type;
          newUnit.status = unit.status;
          return newUnit;
        });
      } else {
        newGroup.units = [];
      }
      
      return newGroup;
    });
    
    // 更新数据源
    this.deviceGroupsDataSource.updateData(this.indexData.deviceGroups);
    
    // 更新统计信息
    this.updateDeviceStats();
  }

  private updateDeviceStats(): void {
    this.indexData.totalGroups = this.indexData.deviceGroups.length;
    this.indexData.onlineDevices = this.indexData.deviceGroups.filter(
      group => !group.isOffline
    ).length;
  }

  private async loadDeviceGroups() {
    try {
      const response = await ApiService.getInstance().getDevices();
      // 创建新数组引用以确保UI更新
      if (response.data) {
        // Create new DeviceGroup instances to ensure proper UI updates
        this.indexData.deviceGroups = response.data.map(group => {
          const newGroup = new DeviceGroup();
          newGroup.id = group.id;
          newGroup.name = group.name;
          newGroup.groupName = group.groupName;
          newGroup.displayName = group.displayName;
          newGroup.location = group.location;
          newGroup.icon = group.icon;
          newGroup.hasControlUnit = group.hasControlUnit;
          newGroup.isOffline = group.isOffline;
          
          // Copy units array with new instances
          if (group.units) {
            newGroup.units = group.units.map(unit => {
              const newUnit = new DeviceUnit();
              newUnit.id = unit.id;
              newUnit.name = unit.name;
              newUnit.type = unit.type;
              newUnit.status = unit.status;
              return newUnit;
            });
          } else {
            newGroup.units = [];
          }
          
          return newGroup;
        });
      } else {
        this.indexData.deviceGroups = [];
      }
      this.deviceGroupsDataSource.updateData(this.indexData.deviceGroups);
      this.updateDeviceStats();
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Successfully loaded devices from API');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to load devices: %{public}s', [errorMessage]);
      this.showToastMessage(`加载设备失败: ${errorMessage}`);
      
      // 作为备选方案，使用模拟数据
      this.indexData.deviceGroups = [
        this.createDeviceGroup('living_room', 'living_room', '客厅设备', '客厅', '🛋️', true, false, [
          this.createDeviceUnit('living_main_light', '主灯', 'control', 'ON'),
          this.createDeviceUnit('living_fan', '风扇', 'control', 'OFF')
        ]),
        this.createDeviceGroup('bedroom', 'bedroom', '卧室设备', '主卧', '🏠', true, true, [
          this.createDeviceUnit('bedroom_light', '床头灯', 'control', 'OFFLINE')
        ]),
        this.createDeviceGroup('kitchen', 'kitchen', '厨房设备', '厨房', '🔌', true, false, [
          this.createDeviceUnit('kitchen_light', '厨房灯', 'control', 'ON'),
          this.createDeviceUnit('kitchen_extractor', '油烟机', 'control', 'ON')
        ]),
        this.createDeviceGroup('bathroom', 'bathroom', '浴室设备', '客卫', '🛁', false, false, [])
      ];
      this.deviceGroupsDataSource.updateData(this.indexData.deviceGroups);
      this.updateDeviceStats();
    }
  }

  // Helper methods to create DeviceGroup and DeviceUnit instances
   private createDeviceGroup(id: string, name: string, displayName: string, location: string, icon: string, 
                            hasControlUnit: boolean, isOffline: boolean, units: DeviceUnit[]): DeviceGroup {
     const group = new DeviceGroup();
     group.id = id;
     group.name = name;
     group.groupName = name;
     group.displayName = displayName;
     group.location = location;
     group.icon = icon;
     group.hasControlUnit = hasControlUnit;
     group.isOffline = isOffline;
     group.units = units;
     return group;
   }

   private createDeviceUnit(id: string, name: string, type: 'control' | 'state' | 'text' | 'data', status: string): DeviceUnit {
     const unit = new DeviceUnit();
     unit.id = id;
     unit.name = name;
     unit.type = type;
     unit.status = status;
     return unit;
   }

  private getGroupStatusColor(group: DeviceGroup): ResourceColor {
    // 获取所有control类型的单元
    const controlUnits = group.units?.filter(unit => unit.type === 'control') || [];
    
    // 检查是否有单元处于离线状态
    const hasOfflineUnit = controlUnits.some(unit => unit.status === 'OFFLINE');
    
    // 离线状态为灰色（任何单元离线则整个设备组显示离线）
    if (group.isOffline || hasOfflineUnit) {
      return '#6c757d'; // 灰色 - 离线
    }
    
    if (controlUnits.length === 0) {
      return '#adb5bd'; // 无控制单元，默认灰色
    }
    
    // 统计开启和关闭的单元数量（排除离线单元）
    const onlineControlUnits = controlUnits.filter(unit => unit.status !== 'OFFLINE');
    const onCount = onlineControlUnits.filter(unit => unit.status === 'ON').length;
    const totalCount = onlineControlUnits.length;
    
    if (totalCount === 0) {
      return '#6c757d'; // 所有单元都离线，显示灰色
    }
    
    if (onCount === totalCount) {
      return '#28a745'; // 全部打开 - 绿色
    } else if (onCount > 0) {
      return '#fd7e14'; // 部分打开 - 橘黄色
    } else {
      return '#000000'; // 全部关闭 - 黑色
    }
  }

  private toggleAllUnits(groupName: string) {
    // 实现批量开关设备逻辑
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Toggle all units for group: %{public}s', [groupName]);
    
    // 查找对应的设备组
    const groupIndex = this.indexData.deviceGroups.findIndex(group => group.groupName === groupName);
    if (groupIndex !== -1) {
      // 创建新的设备组副本以触发UI更新
      const updatedGroups = [...this.indexData.deviceGroups];
      const oldGroup = updatedGroups[groupIndex];
      
      // 切换所有控制单元的状态
      if (oldGroup.units && oldGroup.units.length > 0) {
        // 检查当前状态，决定是全部打开还是全部关闭
        // 筛选出control类型的单元
        const controlUnits = oldGroup.units.filter(unit => unit.type === 'control');
        
        if (controlUnits.length > 0) {
        

          // 检查control单元的状态
          const controlUnitsOn = controlUnits.filter(unit => unit.status === 'ON');
          
          // 决定新状态：
          // 1. 所有control单元都是ON -> 全部关闭
          // 2. 所有control单元都是OFF -> 全部打开  
          // 3. 部分control单元ON，部分OFF -> 全部打开
          const newStatus = controlUnitsOn.length === controlUnits.length ? 'OFF' : 'ON';
        
        // 创建新的units数组
        const newUnits = oldGroup.units.map(unit => {
          const newUnit = new DeviceUnit();
          newUnit.id = unit.id;
          newUnit.name = unit.name;
          newUnit.type = unit.type;
          newUnit.status = unit.type === 'control' ? newStatus : unit.status;
          return newUnit;
        });
        
        // 创建新的组对象
        const newGroup = new DeviceGroup();
        newGroup.id = oldGroup.id;
        newGroup.name = oldGroup.name;
        newGroup.groupName = oldGroup.groupName;
        newGroup.displayName = oldGroup.displayName;
        newGroup.location = oldGroup.location;
        newGroup.icon = oldGroup.icon;
        newGroup.hasControlUnit = oldGroup.hasControlUnit;
        newGroup.isOffline = oldGroup.isOffline;
        newGroup.units = newUnits;
        
        // 更新组
        updatedGroups[groupIndex] = newGroup;
        
        // 更新设备组列表 - 创建新数组引用以触发UI更新
        this.indexData.deviceGroups = [...updatedGroups];
        
        // 更新数据源
        this.deviceGroupsDataSource.updateData(this.indexData.deviceGroups);
        
        // 更新统计信息
        this.updateDeviceStats();
        }
      }
    }
    
    this.showToastMessage(`已切换 ${groupName} 组的所有设备`);
  }

  private startVoiceInput() {
    // 使用华为小艺语音输入
    let isSupported = false;
    try {
      isSupported = VoiceInputUtil.getInstance().isVoiceInputSupported();
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to check voice input support: %{public}s', [(error as Error).message]);
      isSupported = false;
    }
    if (!isSupported) {
      this.showToastMessage('设备不支持语音输入');
      return;
    }

    try {
      VoiceInputUtil.getInstance().startVoiceRecognition((result: string) => {
        try {
          this.aiInputText = result;
          this.indexData.aiInputText = result;
          this.showToastMessage(`识别结果: ${result}`);
        } catch (innerError) {
          hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to handle voice result: %{public}s', [(innerError as Error).message]);
          this.showToastMessage('处理语音识别结果时出错');
        }
      });
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Voice recognition failed: %{public}s', [(error as Error).message]);
      this.showToastMessage(`语音识别失败: ${(error as Error).message || '未知错误'}`);
    }
  }

  private sendAiCommand() {
    try {
      // 原有的方法逻辑
      // 发送AI指令
      if (!this.indexData.aiInputText.trim()) {
        this.showToastMessage('请输入AI指令');
        return;
      }
      
      this.indexData.aiResult = `正在处理指令: "${this.indexData.aiInputText}"`;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Sending AI command: %{public}s', [this.indexData.aiInputText]);
      
      // 调用API服务发送AI指令
      ApiService.getInstance().sendAiCommand(this.indexData.aiInputText)
        .then((response: ApiResponse) => {
          // 修改后的代码
          const resultText = response.data ? (typeof response.data === 'object' && response.data !== null && Object.keys(response.data).includes('result') ? (response.data as Record<string, string>).result || '执行成功' : response.message || '执行成功') : response.message || '执行成功';

          this.indexData.aiResult = `AI响应: ${resultText}`;
          this.showToastMessage('AI指令发送成功');
        })
        .catch((error: Error) => {
          hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to send AI command: %{public}s', [error.message || 'Unknown error']);
          this.indexData.aiResult = `AI处理失败: ${error.message || 'Unknown error'}`;
          this.showToastMessage(`AI指令发送失败: ${error.message || 'Unknown error'}`);
        });
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Unexpected error in sendAiCommand: %{public}s', [(error as Error).message]);
      this.indexData.aiResult = `AI指令发送失败: ${(error as Error).message || '未知错误'}`;
      this.showToastMessage(`AI指令发送失败: ${(error as Error).message || '未知错误'}`);
    }
  }
}