import UIAbility from '@ohos.app.ability.UIAbility';
import hilog from '@ohos.hilog';
import window from '@ohos.window';
import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import { ScreenAdaptUtil } from '../utils/ScreenAdaptUtil';
import { LoginStorage } from '../utils/LoginStorage';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    hilog.info(0x0000, 'testTag', 'Ability onCreate');
    // 使用参数，避免警告
    console.info('Want: ' + JSON.stringify(want));
    console.info('LaunchParam: ' + JSON.stringify(launchParam));
    
    // 初始化登录存储工具（异步）
    LoginStorage.getInstance().init(this.context).catch((error: Error) => {
      hilog.error(0x0000, 'testTag', 'Failed to initialize LoginStorage: %{public}s',
        [error instanceof Error ? error.message : String(error)]);
    });
    
    // 请求麦克风权限
    this.requestMicrophonePermission();
  }
  
  // 请求麦克风权限
  private async requestMicrophonePermission(): Promise<void> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const permissions: Permissions[] = ['ohos.permission.MICROPHONE'];
      
      // 请求用户授权
      const grantStatus = await atManager.requestPermissionsFromUser(this.context, permissions);
      
      hilog.info(0x0000, 'testTag', 'Microphone permission request result: %{public}s', 
        JSON.stringify(grantStatus));
      
      if (grantStatus.authResults[0] === 0) {
        hilog.info(0x0000, 'testTag', 'Microphone permission granted');
      } else {
        hilog.warn(0x0000, 'testTag', 'Microphone permission denied');
      }
    } catch (error) {
      hilog.error(0x0000, 'testTag', 'Failed to request microphone permission: %{public}s', 
        JSON.stringify(error));
    }
  }

  onDestroy() {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
    // 销毁屏幕适配工具
    ScreenAdaptUtil.getInstance().destroy();
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    // Main window is created, set main page for the window stage
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 初始化屏幕适配工具（支持折叠屏自动适配）
    ScreenAdaptUtil.getInstance().init(this.context);

    windowStage.loadContent('pages/Index', (err, data) => {
      if (err.code) {
        hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
      hilog.info(0x0000, 'testTag', 'Succeeded in loading the content. Data: %{public}s', JSON.stringify(data) ?? '');
    });
  }

  onWindowStageDestroy() {
    // Main window is destroyed
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground() {
    // Ability has brought to foreground
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground() {
    // Ability has back to background
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackground');
  }
}