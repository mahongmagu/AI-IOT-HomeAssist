import router from '@ohos.router';
import hilog from '@ohos.hilog';
import promptAction from '@ohos.promptAction';
import { BusinessError } from '@kit.BasicServicesKit';
import { ApiCompatibilityUtil } from '../utils/ApiCompatibilityUtil';
import { ScreenAdaptUtil, BreakpointType } from '../utils/ScreenAdaptUtil';

import { ServerConfig } from '../model/ServerConfig';
import { VoiceInputUtil } from '../utils/VoiceInputUtil';
import { ApiService, ApiResponse } from '../services/ApiService';
import { WebSocketService, StateUpdateMessage } from '../services/WebSocketService';
import { IndexData } from '../model/IndexData';
import { DeviceGroup, DeviceUnit } from '../model/DeviceModel';
import { DeviceGroupDataSource } from '../utils/DataSource';
import { LoginStorage, LoginCredentials } from '../utils/LoginStorage';

// 常量定义
const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'Index';

// 控制结果接口
interface ControlResult {
  success: boolean;
  unitId: string;
  error?: Error;
}

@Entry
@ComponentV2
struct Index {
  @Local indexData: IndexData = new IndexData();
  @Local isServerConfigured: boolean = ServerConfig.isConfigured();
  @Local gridColumns: number = 2; // 响应式列数
  @Local showMenu: boolean = false; // 控制菜单显示
  @Local showConfigDialog: boolean = false; // 控制配置对话框显示
  private deviceGroupsDataSource: DeviceGroupDataSource = new DeviceGroupDataSource([]);
  
  private ipInputController: TextInputController = new TextInputController();
  private portInputController: TextInputController = new TextInputController();
  private usernameInputController: TextInputController = new TextInputController();
  private passwordInputController: TextInputController = new TextInputController();
  private aiTextInputController: TextInputController = new TextInputController();
  private aiInputText: string = '';
  
  // 配置对话框临时数据
  private configServerIp: string = '';
  private configServerPort: string = '';
  private configUsername: string = '';
  private configPassword: string = '';
  
  private loginStorage: LoginStorage = LoginStorage.getInstance();
  
  // 断点变化监听器
  private breakpointListener: (breakpoint: BreakpointType) => void = (breakpoint: BreakpointType) => {
    this.gridColumns = ScreenAdaptUtil.getDeviceGroupColumns();
    hilog.info(LOG_DOMAIN, LOG_TAG, `Breakpoint changed to ${breakpoint}, columns updated to ${this.gridColumns}`);
  };
  
  // Method to show toast using promptAction with compatibility check
  private showToastMessage(message: string): void {
    // 检查设备是否支持promptAction
    if (!ApiCompatibilityUtil.isPromptActionSupported()) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'PromptAction not supported on this device');
      return;
    }
    
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
    // 初始化屏幕适配列数
    this.gridColumns = ScreenAdaptUtil.getDeviceGroupColumns();
    hilog.info(LOG_DOMAIN, LOG_TAG, `Screen adapted: device type=${ScreenAdaptUtil.getDeviceType()}, columns=${this.gridColumns}`);
    
    // 注册断点变化监听器，实现响应式布局
    ScreenAdaptUtil.getInstance().addBreakpointListener(this.breakpointListener);
    
    // 初始化登录存储
    // 注意：这里需要获取UIAbility的context，暂时使用全局context
    // 在实际使用中，需要在EntryAbility中初始化LoginStorage
    this.isServerConfigured = ServerConfig.isConfigured();
    
    // 尝试自动登录
    this.tryAutoLogin();
  }

  // 当页面重新显示时（从详情页返回），刷新设备状态
  onShow() {
    if (ServerConfig.isConfigured() && !this.indexData.showConfigPage) {
      this.loadDeviceGroups();
    }
  }

  aboutToDisappear() {
    // 移除断点变化监听器
    ScreenAdaptUtil.getInstance().removeBreakpointListener(this.breakpointListener);
    
    // 页面消失时关闭WebSocket连接
    WebSocketService.getInstance().disconnect();
  }

  build() {
    Column() {
      // 基于响应式状态决定显示哪个页面
      if (!this.isServerConfigured) {
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
        Text('登录')
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
          placeholder: '服务端口号 (默认3002)'
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
        .margin({ bottom: 15 })

        TextInput({
          controller: this.usernameInputController,
          placeholder: '请输入用户名'
        })
        .placeholderColor('#999')
        .padding({ left: 15, right: 15 })
        .height(50)
        .width('90%')
        .backgroundColor('#f5f5f5')
        .borderRadius(8)
        .onChange((value: string) => {
          this.indexData.username = value;
        })
        .margin({ bottom: 15 })

        TextInput({
          controller: this.passwordInputController,
          placeholder: '请输入密码'
        })
        .type(InputType.Password)
        .placeholderColor('#999')
        .padding({ left: 15, right: 15 })
        .height(50)
        .width('90%')
        .backgroundColor('#f5f5f5')
        .borderRadius(8)
        .onChange((value: string) => {
          this.indexData.password = value;
        })
        .margin({ bottom: 15 })

        // 显示剩余尝试次数或锁定时间
        if (this.indexData.isAccountLocked) {
          Text(`账户已锁定，请${Math.floor(this.indexData.remainingLockTime / 60)}分${this.indexData.remainingLockTime % 60}秒后再试`)
            .fontSize(12)
            .fontColor('#dc3545')
            .margin({ bottom: 15 })
        } else if (this.indexData.remainingAttempts < 5) {
          Text(`剩余尝试次数: ${this.indexData.remainingAttempts}`)
            .fontSize(12)
            .fontColor('#dc3545')
            .margin({ bottom: 15 })
        }

        Button() {
          Text(this.indexData.isAccountLocked ? '账户已锁定' : '登录')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .height('100%')
        }
        .width('90%')
        .height(50)
        .backgroundColor(this.indexData.isAccountLocked ? '#999' : '#0066cc')
        .borderRadius(8)
        .enabled(!this.indexData.isAccountLocked)
        .onClick(() => {
          if (!this.indexData.isAccountLocked) {
            this.saveServerConfig();
          }
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
    Stack() {
      Column() {
        // 标题栏
        Row() {
          // 菜单图标
          Button() {
            Text('☰')
              .fontSize(20)
              .fontColor('#333')
          }
          .width(40)
          .height(40)
          .backgroundColor(Color.Transparent)
          .borderRadius(20)
          .onClick(() => {
            this.showMenu = !this.showMenu;
          })

          // 标题
          Text('AI智能控制助手')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          // 右侧占位符，用于平衡布局
          Text('')
            .width(40)
            .height(40)
        }
        .width('100%')
        .height(60)
        .padding({ left: 16, right: 16 })
        .backgroundColor('#f8f9fa')
        .border({
          width: { bottom: 1 },
          color: '#e0e0e0'
        })
        .shadow({
          radius: 2,
          color: '#00000010',
          offsetX: 0,
          offsetY: 1
        })
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)

        // 下拉菜单
        if (this.showMenu) {
          Column() {
            Text('配置')
              .fontSize(16)
              .fontColor('#333')
              .width('100%')
              .padding({ top: 12, bottom: 12, left: 20, right: 20 })
              .backgroundColor('#ffffff')
              .onClick(() => {
                this.showMenu = false;
                this.openConfigDialog();
              })
            Divider()
              .strokeWidth(1)
              .color('#f0f0f0')
            Text('定时任务')
              .fontSize(16)
              .fontColor('#333')
              .width('100%')
              .padding({ top: 12, bottom: 12, left: 20, right: 20 })
              .backgroundColor('#ffffff')
              .onClick(() => {
                this.showMenu = false;
                this.showToastMessage('定时任务功能待实现');
              })
          }
          .width(120)
          .backgroundColor('#ffffff')
          .border({
            width: 1,
            color: '#e0e0e0'
          })
          .borderRadius(8)
          .shadow({
            radius: 4,
            color: '#00000020',
            offsetX: 0,
            offsetY: 2
          })
          .position({ x: 16, y: 60 })
          .zIndex(100)
        }

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

        // 设备网格 - 支持折叠屏时根据屏幕宽度动态调整列数
        Scroll() {
          Grid() {
            LazyForEach(this.deviceGroupsDataSource, (item: DeviceGroup) => {
              GridItem() {
                this.DeviceCard(item)
              }
            }, (item: DeviceGroup) => `${item.id}-${item.isOffline}-${item.units?.map(u => u.status).join(',')}`)
          }
          .columnsTemplate(ScreenAdaptUtil.generateColumnsTemplate(this.gridColumns))
          .padding({ top: 15, left: 15, right: 15 })
          .width('100%')
          .rowsGap(15)
          .columnsGap(15)
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

      // 配置对话框 - 覆盖在页面上方
      if (this.showConfigDialog) {
        Column() {
          this.ConfigDialog()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#00000050')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .zIndex(200)
      }
    }
    .width('100%')
    .height('100%')
  }
  
  @Builder ConfigDialog() {
    Column() {
      Text('配置')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 30 })

      Column() {
        TextInput({
          text: this.configServerIp,
          placeholder: '请输入服务端IP地址或域名'
        })
        .placeholderColor('#999')
        .padding({ left: 15, right: 15 })
        .height(50)
        .width('100%')
        .backgroundColor('#f5f5f5')
        .borderRadius(8)
        .onChange((value: string) => {
          this.configServerIp = value;
        })
        .margin({ bottom: 15 })

        TextInput({
          text: this.configServerPort,
          placeholder: '服务端口号 (默认3002)'
        })
        .placeholderColor('#999')
        .padding({ left: 15, right: 15 })
        .height(50)
        .width('100%')
        .backgroundColor('#f5f5f5')
        .borderRadius(8)
        .onChange((value: string) => {
          this.configServerPort = value;
        })
        .margin({ bottom: 15 })

        TextInput({
          text: this.configUsername,
          placeholder: '请输入用户名'
        })
        .placeholderColor('#999')
        .padding({ left: 15, right: 15 })
        .height(50)
        .width('100%')
        .backgroundColor('#f5f5f5')
        .borderRadius(8)
        .onChange((value: string) => {
          this.configUsername = value;
        })
        .margin({ bottom: 15 })

        TextInput({
          text: this.configPassword,
          placeholder: '请输入密码'
        })
        .type(InputType.Password)
        .placeholderColor('#999')
        .padding({ left: 15, right: 15 })
        .height(50)
        .width('100%')
        .backgroundColor('#f5f5f5')
        .borderRadius(8)
        .onChange((value: string) => {
          this.configPassword = value;
        })
        .margin({ bottom: 20 })

        Row() {
          Button() {
            Text('取消')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
          }
          .width('45%')
          .height(50)
          .backgroundColor('#999')
          .borderRadius(8)
          .onClick(() => {
            this.showConfigDialog = false;
          })
          .margin({ right: '5%' })

          Button() {
            Text('保存')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
          }
          .width('45%')
          .height(50)
          .backgroundColor('#0066cc')
          .borderRadius(8)
          .onClick(() => {
            this.saveConfig();
          })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
    }
    .width('85%')
    .padding({ top: 30, bottom: 30 })
    .backgroundColor('#ffffff')
    .borderRadius(12)
    .shadow({
      radius: 8,
      color: '#00000030',
      offsetX: 0,
      offsetY: 4
    })
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
      // 检查设备是否支持路由功能
      if (!ApiCompatibilityUtil.isRouterSupported()) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'Router not supported on this device');
        this.showToastMessage('当前设备不支持页面跳转');
        return;
      }
      
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
        .height('100%')
        .textAlign(TextAlign.Center)
        .align(Alignment.Center)
      
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
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }
  
  @Builder DeviceInfoSection(group: DeviceGroup) {
    // 设备信息
    Row() {
      Row() {
        Text(group.displayName || group.groupName)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
        
        if (group.location) {
          Text(`📍 ${group.location}`)
            .fontSize(11)
            .fontColor('#666')
            .margin({ left: 6 })
        }
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Start)

      if (group.isOffline) {
        Text('⚠️ 离线')
          .fontSize(10)
          .fontColor('#dc3545')
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 10 })
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
      .layoutWeight(1)
      .backgroundColor('#ffffff')
      .borderRadius(25)
      .onChange((value: string) => {
        this.indexData.aiInputText = value;
      })

      Button() {
        Text('🎤')
          .fontSize(20)
      }
      .width(44)
      .height(44)
      .backgroundColor(Color.Transparent)
      .borderWidth(2)
      .borderColor('#6c757d')
      .borderRadius(22)
      .shadow({
        radius: 4,
        color: '#6c757d40',
        offsetX: 0,
        offsetY: 2
      })
      .onClick(() => {
        this.startVoiceInput();
      })
      .margin({ left: 8 })

      Button() {
        Text('发送')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
      }
      .width(60)
      .height(44)
      .backgroundColor('#28a745')
      .borderRadius(22)
      .linearGradient({
        angle: 90,
        colors: [['#4CAF50', 0.0], ['#2E7D32', 1.0]]
      })
      .shadow({
        radius: 6,
        color: '#2E7D3240',
        offsetX: 0,
        offsetY: 3
      })
      .onClick(() => {
        this.sendAiCommand();
      })
      .margin({ left: 8 })
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
    // 添加调试日志
    hilog.info(LOG_DOMAIN, LOG_TAG, 'saveServerConfig called with serverIp: %{public}s, serverPort: %{public}s, username: %{public}s', 
      [this.indexData.serverIp, this.indexData.serverPort, this.indexData.username]);
    
    // 检查服务器地址是否为空或只包含空格
    const trimmedServerIp = this.indexData.serverIp?.trim();
    if (!trimmedServerIp) {
      this.showToastMessage('请输入服务端IP地址或域名');
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Server IP is empty or contains only whitespace');
      return;
    }
    
    // 验证服务器地址格式
    // 允许IP地址（如192.168.1.1）、域名（如example.com）或localhost
    const serverAddressRegex = /^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$|^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$|^localhost$|^[a-zA-Z0-9\-]+$/;
    
    if (!serverAddressRegex.test(trimmedServerIp)) {
      this.showToastMessage('服务器地址格式不正确，请输入有效的IP地址或域名');
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Server IP format invalid: %{public}s', [trimmedServerIp]);
      return;
    }
    
    // 验证端口号
    const portStr = this.indexData.serverPort || '3002';
    const port = parseInt(portStr);
    if (isNaN(port) || port < 1 || port > 65535) {
      this.showToastMessage('端口号必须在1-65535之间');
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Port number invalid: %{public}s', [portStr]);
      return;
    }
    
    if (!this.indexData.username || !this.indexData.password) {
      this.showToastMessage('请输入用户名和密码');
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Username or password is empty');
      return;
    }
    
    try {
      // 使用trim后的地址
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Setting server address: %{public}s:%{public}d', [trimmedServerIp, port]);
      
      ServerConfig.setServerAddress(trimmedServerIp, port);
      // 同时设置WebSocket配置，使用固定的8090端口（根据后端配置）
      ServerConfig.setWebSocketConfig(8090, '/');
      
      // 记录设置后的URL
      const apiBaseUrl = ServerConfig.getApiBaseUrl();
      hilog.info(LOG_DOMAIN, LOG_TAG, 'API Base URL set to: %{public}s', [apiBaseUrl]);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'ServerConfig.isConfigured() = %{public}s', [ServerConfig.isConfigured().toString()]);
      
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to set server address: %{public}s', [(error as Error).message]);
      this.showToastMessage('保存服务器配置失败: ' + (error as Error).message);
      return;
    }
    
    // 执行登录
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Calling performLogin after successful server config');
    this.performLogin();
  }

  /**
   * 尝试自动登录
   */
  private async tryAutoLogin(): Promise<void> {
    try {
      // 检查是否有保存的凭据
      const credentials = await this.loginStorage.loadCredentials();
      
      if (credentials) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Found saved credentials, attempting auto-login');
        this.indexData.isAutoLogin = true;
        
        // 填充表单数据
        this.indexData.serverIp = credentials.serverAddress;
        this.indexData.serverPort = credentials.serverPort.toString();
        this.indexData.username = credentials.username;
        this.indexData.password = credentials.password;
        
        // 设置服务器配置
        ServerConfig.setServerAddress(credentials.serverAddress, credentials.serverPort);
        ServerConfig.setWebSocketConfig(8090, '/');
        
        // 执行登录
        await this.performLogin();
      } else {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'No saved credentials found, showing login page');
        // 检查账户锁定状态
        await this.checkLockStatus();
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Auto-login failed: %{public}s',
        [error instanceof Error ? error.message : String(error)]);
    }
  }

  /**
   * 执行登录
   */
  private async performLogin(): Promise<void> {
    // 添加调试日志
    hilog.info(LOG_DOMAIN, LOG_TAG, 'performLogin called with serverIp: %{public}s, username: %{public}s', 
      [this.indexData.serverIp, this.indexData.username]);
    
    // 检查账户是否被锁定
    const isLocked = await this.loginStorage.isAccountLocked();
    if (isLocked) {
      await this.checkLockStatus();
      this.showToastMessage('账户已锁定，请稍后再试');
      return;
    }
    
    // 验证输入
    const serverIp = this.indexData.serverIp?.trim();
    if (!serverIp || !this.indexData.username || !this.indexData.password) {
      this.showToastMessage('请填写完整登录信息');
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Missing login info: serverIp=%{public}s, username=%{public}s', 
        [serverIp || '(empty)', this.indexData.username || '(empty)']);
      return;
    }
    
    // 检查服务器是否已配置
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Checking if server is configured...');
    if (!ServerConfig.isConfigured()) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Server not configured! ServerConfig.isConfigured() returned false');
      this.showToastMessage('服务器地址未配置，请先设置服务器地址');
      return;
    }
    
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Server is configured, proceeding with login');
    
    try {
      // 调用API服务进行登录
      const response = await ApiService.getInstance().login(
        this.indexData.username,
        this.indexData.password
      );
      
      if (response.success) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Login successful');
        
        // 登录成功，清除失败记录
        await this.loginStorage.clearLoginFailureRecord();
        
        // 保存登录凭据到加密存储
        const credentials: LoginCredentials = {
          serverAddress: this.indexData.serverIp,
          serverPort: parseInt(this.indexData.serverPort || '3002'),
          username: this.indexData.username,
          password: this.indexData.password
        };
        
        await this.loginStorage.saveCredentials(credentials);
        
        // 更新响应式状态以触发UI更新
        this.isServerConfigured = true;
        
        // 连接到服务器加载设备
        this.connectToServer();
        
        this.showToastMessage('登录成功');
      } else {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Login failed: %{public}s', [response.message || 'Unknown error']);
        
        // 登录失败，记录失败次数
        const record = await this.loginStorage.recordLoginFailure();
        
        // 更新UI状态
        await this.checkLockStatus();
        
        this.showToastMessage(response.message || '登录失败');
      }
    } catch (error) {
      // 添加详细的错误日志
      if (error instanceof Error) {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Login error (Error object): %{public}s', [error.message]);
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Login error stack: %{public}s', [error.stack || 'No stack trace']);
      } else {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Login error (non-Error object): %{public}s', [JSON.stringify(error)]);
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Login error type: %{public}s', [typeof error]);
      }
      
      // 记录失败
      await this.loginStorage.recordLoginFailure();
      await this.checkLockStatus();
      
      // 显示更详细的错误信息
      let errorMessage = '登录失败：';
      if (error instanceof Error) {
        errorMessage += error.message;
      } else if (typeof error === 'object' && error !== null) {
        errorMessage += JSON.stringify(error);
      } else {
        errorMessage += String(error);
      }
      this.showToastMessage(errorMessage);
    }
  }

  /**
   * 检查账户锁定状态
   */
  private async checkLockStatus(): Promise<void> {
    const isLocked = await this.loginStorage.isAccountLocked();
    this.indexData.isAccountLocked = isLocked;
    
    if (isLocked) {
      const remainingTime = await this.loginStorage.getRemainingLockTime();
      this.indexData.remainingLockTime = remainingTime;
      this.indexData.remainingAttempts = 0;
    } else {
      const remainingAttempts = await this.loginStorage.getRemainingAttempts();
      this.indexData.remainingAttempts = remainingAttempts;
      this.indexData.remainingLockTime = 0;
    }
  }

  private connectToServer() {
    // 连接到服务端的逻辑
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
      if (connected) {
        // 连接成功后刷新设备列表，确保断连期间的变更都能同步
        this.loadDeviceGroups();
        this.showToastMessage('WebSocket已连接');
      } else {
        this.showToastMessage('WebSocket连接断开，正在尝试重连...');
      }
    });
    
    // 建立连接
    wsService.connect();
  }

  private handleStateUpdate(message: StateUpdateMessage): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, `Handling state update for unit: ${message.device.unit}, state: ${message.state}`);
    
    // 获取更新后的设备组数组（确保创建新引用）
    const updatedGroups = WebSocketService.getInstance().updateDeviceGroupState(
      this.indexData.deviceGroups,
      message
    );
    
    // 确保创建完全新的数组引用以触发V2装饰器检测
    this.indexData.deviceGroups = [...updatedGroups];
    
    // 强制更新数据源 - 使用新的数组引用
    this.deviceGroupsDataSource.updateData([...this.indexData.deviceGroups]);
    
    // 更新统计信息
    this.updateDeviceStats();
    
    hilog.info(LOG_DOMAIN, LOG_TAG, `Updated deviceGroups count: ${this.indexData.deviceGroups.length}`);
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
      if (response.data) {
        // 直接赋值，V2装饰器会自动检测变化
        this.indexData.deviceGroups = response.data;
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
    
    // 添加详细日志显示所有单元的类型和状态
    hilog.info(LOG_DOMAIN, LOG_TAG, 
      `getGroupStatusColor: ${group.id}, all units: ${group.units?.map(u => `${u.id}:${u.type}:${u.status}`).join(', ')}`);
    hilog.info(LOG_DOMAIN, LOG_TAG, 
      `  control units: ${controlUnits.map(u => `${u.id}:${u.type}:${u.status}`).join(', ')}`);
    
    // 检查是否有单元处于离线状态
    const hasOfflineUnit = controlUnits.some(unit => unit.status === 'OFFLINE');
    
    // 离线状态为灰色（任何单元离线则整个设备组显示离线）
    if (group.isOffline || hasOfflineUnit) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 
        `getGroupStatusColor: ${group.id} -> #6c757d (offline), units: ${controlUnits.map(u => `${u.id}:${u.status}`).join(', ')}`);
      return '#6c757d'; // 灰色 - 离线
    }
    
    if (controlUnits.length === 0) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 
        `getGroupStatusColor: ${group.id} -> #adb5bd (no control units)`);
      return '#adb5bd'; // 无控制单元，默认灰色
    }
    
    // 统计开启和关闭的单元数量（排除离线单元）
    const onlineControlUnits = controlUnits.filter(unit => unit.status !== 'OFFLINE');
    const onCount = onlineControlUnits.filter(unit => unit.status === 'ON').length;
    const totalCount = onlineControlUnits.length;
    
    if (totalCount === 0) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 
        `getGroupStatusColor: ${group.id} -> #6c757d (all offline)`);
      return '#6c757d'; // 所有单元都离线，显示灰色
    }
    
    if (onCount === totalCount) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 
        `getGroupStatusColor: ${group.id} -> #28a745 (all ON), onCount=${onCount}, totalCount=${totalCount}`);
      return '#28a745'; // 全部打开 - 绿色
    } else if (onCount > 0) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 
        `getGroupStatusColor: ${group.id} -> #fd7e14 (partial), onCount=${onCount}, totalCount=${totalCount}`);
      return '#fd7e14'; // 部分打开 - 橘黄色
    } else {
      hilog.info(LOG_DOMAIN, LOG_TAG, 
        `getGroupStatusColor: ${group.id} -> #000000 (all OFF), onCount=${onCount}, totalCount=${totalCount}`);
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
          
          // 为每个control类型的设备单元发送控制命令
          const controlUnitsToToggle = oldGroup.units.filter(unit => unit.type === 'control');
          if (controlUnitsToToggle.length > 0) {
            // 保存原始状态，用于API调用失败时回滚
            const originalUnits = [...oldGroup.units];
            
            // 批量发送控制命令
            const controlPromises = controlUnitsToToggle.map(unit => {
              return ApiService.getInstance().controlUnit(groupName, unit.id, newStatus)
                .then((response: ApiResponse) => {
                  hilog.info(LOG_DOMAIN, LOG_TAG, 'Successfully controlled unit: %{public}s, command: %{public}s', [unit.id, newStatus]);
                  return { success: true, unitId: unit.id } as ControlResult;
                })
                .catch((error: Error) => {
                  hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to control unit %{public}s: %{public}s', [unit.id, error.message]);
                  return { success: false, unitId: unit.id, error } as ControlResult;
                });
            });
            
            // 等待所有控制命令完成
            Promise.all(controlPromises)
              .then(results => {
                const failedUnits = results.filter(r => !r.success);
                if (failedUnits.length > 0) {
                  // 如果有失败的API调用，回滚UI状态
                  hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to control %{public}d units', [failedUnits.length]);
                  
                  // 恢复原始状态
                  const restoredGroups = [...this.indexData.deviceGroups];
                  const restoredGroupIndex = restoredGroups.findIndex(g => g.groupName === groupName);
                  if (restoredGroupIndex !== -1) {
                    const restoredGroup = new DeviceGroup();
                    restoredGroup.id = oldGroup.id;
                    restoredGroup.name = oldGroup.name;
                    restoredGroup.groupName = oldGroup.groupName;
                    restoredGroup.displayName = oldGroup.displayName;
                    restoredGroup.location = oldGroup.location;
                    restoredGroup.icon = oldGroup.icon;
                    restoredGroup.hasControlUnit = oldGroup.hasControlUnit;
                    restoredGroup.isOffline = oldGroup.isOffline;
                    restoredGroup.units = originalUnits;
                    
                    restoredGroups[restoredGroupIndex] = restoredGroup;
                    this.indexData.deviceGroups = [...restoredGroups];
                    this.deviceGroupsDataSource.updateData(this.indexData.deviceGroups);
                    this.updateDeviceStats();
                  }
                  
                  this.showToastMessage(`部分设备控制失败，已恢复状态`);
                } else {
                  this.showToastMessage(`已切换 ${groupName} 组的所有设备`);
                }
              })
              .catch((error: Error) => {
                hilog.error(LOG_DOMAIN, LOG_TAG, 'Error in batch control: %{public}s', [error.message]);
                // 恢复原始状态
                const restoredGroups = [...this.indexData.deviceGroups];
                const restoredGroupIndex = restoredGroups.findIndex(g => g.groupName === groupName);
                if (restoredGroupIndex !== -1) {
                  const restoredGroup = new DeviceGroup();
                  restoredGroup.id = oldGroup.id;
                  restoredGroup.name = oldGroup.name;
                  restoredGroup.groupName = oldGroup.groupName;
                  restoredGroup.displayName = oldGroup.displayName;
                  restoredGroup.location = oldGroup.location;
                  restoredGroup.icon = oldGroup.icon;
                  restoredGroup.hasControlUnit = oldGroup.hasControlUnit;
                  restoredGroup.isOffline = oldGroup.isOffline;
                  restoredGroup.units = originalUnits;
                  
                  restoredGroups[restoredGroupIndex] = restoredGroup;
                  this.indexData.deviceGroups = [...restoredGroups];
                  this.deviceGroupsDataSource.updateData(this.indexData.deviceGroups);
                  this.updateDeviceStats();
                }
                this.showToastMessage(`设备控制失败: ${error.message}`);
              });
          } else {
            this.showToastMessage(`已切换 ${groupName} 组的所有设备`);
          }
        }
      }
    }
    
    this.showToastMessage(`已切换 ${groupName} 组的所有设备`);
  }

  private async openConfigDialog(): Promise<void> {
    try {
      const credentials = await this.loginStorage.loadCredentials();
      if (credentials) {
        this.configServerIp = credentials.serverAddress;
        this.configServerPort = credentials.serverPort.toString();
        this.configUsername = credentials.username;
        this.configPassword = credentials.password;
      } else {
        this.configServerIp = this.indexData.serverIp || '';
        this.configServerPort = this.indexData.serverPort || '3002';
        this.configUsername = this.indexData.username || '';
        this.configPassword = this.indexData.password || '';
      }
      this.showConfigDialog = true;
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to load credentials for config dialog: %{public}s',
        [error instanceof Error ? error.message : String(error)]);
      this.showConfigDialog = true;
    }
  }

  private async saveConfig(): Promise<void> {
    const trimmedServerIp = this.configServerIp?.trim();
    if (!trimmedServerIp) {
      this.showToastMessage('请输入服务端IP地址或域名');
      return;
    }

    const serverAddressRegex = /^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$|^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$|^localhost$|^[a-zA-Z0-9\-]+$/;
    if (!serverAddressRegex.test(trimmedServerIp)) {
      this.showToastMessage('服务器地址格式不正确，请输入有效的IP地址或域名');
      return;
    }

    const portStr = this.configServerPort || '3002';
    const port = parseInt(portStr);
    if (isNaN(port) || port < 1 || port > 65535) {
      this.showToastMessage('端口号必须在1-65535之间');
      return;
    }

    if (!this.configUsername || !this.configPassword) {
      this.showToastMessage('请输入用户名和密码');
      return;
    }

    try {
      ServerConfig.setServerAddress(trimmedServerIp, port);
      ServerConfig.setWebSocketConfig(8090, '/');

      const credentials: LoginCredentials = {
        serverAddress: trimmedServerIp,
        serverPort: port,
        username: this.configUsername,
        password: this.configPassword
      };

      await this.loginStorage.saveCredentials(credentials);

      this.indexData.serverIp = trimmedServerIp;
      this.indexData.serverPort = port.toString();
      this.indexData.username = this.configUsername;
      this.indexData.password = this.configPassword;

      this.showConfigDialog = false;

      this.showToastMessage('配置已保存，正在重新连接...');

      WebSocketService.getInstance().disconnect();

      await this.performLogin();
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to save config: %{public}s',
        [error instanceof Error ? error.message : String(error)]);
      this.showToastMessage('保存配置失败: ' + (error instanceof Error ? error.message : String(error)));
    }
  }

  private async startVoiceInput() {
    // 检查设备是否支持语音输入
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

    // 如果正在识别，先停止
    if (VoiceInputUtil.getInstance().isRecognizingNow()) {
      VoiceInputUtil.getInstance().stopRecognition();
      this.indexData.aiResult = '语音识别已停止';
      return;
    }

    // 开始语音识别
    this.indexData.aiResult = '正在识别语音，请说话...';
    
    try {
      await VoiceInputUtil.getInstance().startVoiceRecognition({
        onStart: () => {
          hilog.info(LOG_DOMAIN, LOG_TAG, 'Voice recognition started');
          this.indexData.aiResult = '正在识别语音，请说话...';
        },
        
        onResult: (result: string, isFinal: boolean) => {
          hilog.info(LOG_DOMAIN, LOG_TAG, `Voice recognition result: ${result}, isFinal: ${isFinal}`);
          
          // 实时更新识别结果到输入框
          this.aiInputText = result;
          this.indexData.aiInputText = result;
          
          if (isFinal) {
            // 最终结果，显示识别完成
            this.indexData.aiResult = `识别完成: "${result}"`;
          } else {
            // 中间结果，显示正在识别
            this.indexData.aiResult = `正在识别: "${result}"`;
          }
        },
        
        onComplete: () => {
          hilog.info(LOG_DOMAIN, LOG_TAG, 'Voice recognition completed');
          
          // 识别完成后，自动发送指令
          if (this.indexData.aiInputText && this.indexData.aiInputText.trim()) {
            this.indexData.aiResult = `识别完成，正在发送指令: "${this.indexData.aiInputText}"`;
            this.showToastMessage('语音识别完成，正在发送指令');
            
            // 延迟500ms后自动发送，让用户看到识别结果
            setTimeout(() => {
              this.sendAiCommand();
            }, 500);
          } else {
            this.indexData.aiResult = '未识别到有效语音，请重试';
            this.showToastMessage('未识别到有效语音');
          }
        },
        
        onError: (errorCode: number, errorMessage: string) => {
          hilog.error(LOG_DOMAIN, LOG_TAG, `Voice recognition error: ${errorCode}, ${errorMessage}`);
          this.indexData.aiResult = `语音识别失败: ${errorMessage}`;
          this.showToastMessage(`语音识别失败: ${errorMessage}`);
        }
      });
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Voice recognition failed: %{public}s', [(error as Error).message]);
      this.showToastMessage(`语音识别失败: ${(error as Error).message || '未知错误'}`);
      this.indexData.aiResult = '语音识别失败，请重试';
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