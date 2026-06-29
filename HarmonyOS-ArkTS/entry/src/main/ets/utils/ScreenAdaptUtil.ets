import display from '@ohos.display';
import window from '@ohos.window';
import { common } from '@kit.AbilityKit';

/**
 * 断点类型枚举
 * 基于 HarmonyOS 官方断点系统
 * xs: [0, 320vp) - 智能手表
 * sm: [320, 600vp) - 手机竖屏、折叠屏折叠态
 * md: [600, 840vp) - 手机横屏、折叠屏展开态
 * lg: [840, 1440vp) - 平板、折叠屏大屏态
 * xl: [1440, +∞) - PC
 */
export type BreakpointType = 'xs' | 'sm' | 'md' | 'lg' | 'xl';

/**
 * 屏幕适配工具类
 * 用于检测屏幕宽度并根据不同设备类型返回合适的列数
 * 支持折叠屏动态适配
 */
export class ScreenAdaptUtil {
  private static instance: ScreenAdaptUtil | null = null;
  private currentBreakpoint: BreakpointType = 'sm';
  private listeners: Array<(breakpoint: BreakpointType) => void> = [];
  private windowClass: window.Window | null = null;
  
  private constructor() {}
  
  /**
   * 获取单例实例
   */
  static getInstance(): ScreenAdaptUtil {
    if (!ScreenAdaptUtil.instance) {
      ScreenAdaptUtil.instance = new ScreenAdaptUtil();
    }
    return ScreenAdaptUtil.instance;
  }
  
  /**
   * 初始化屏幕适配（在 EntryAbility 中调用）
   * @param context 应用上下文
   */
  init(context: common.UIAbilityContext): void {
    try {
      // 获取主窗口
      this.windowClass = context.windowStage.getMainWindowSync();
      
      // 初始化断点
      this.updateBreakpoint();
      
      // 注册窗口尺寸变化监听
      this.registerWindowSizeChange();
      
      // 注册折叠屏状态变化监听
      this.registerFoldStatusChange();
      
      console.info('ScreenAdaptUtil initialized successfully');
    } catch (error) {
      console.error('Failed to initialize ScreenAdaptUtil:', error);
    }
  }
  
  /**
   * 注册窗口尺寸变化监听
   */
  private registerWindowSizeChange(): void {
    if (!this.windowClass) {
      return;
    }
    
    try {
      this.windowClass.on('windowSizeChange', () => {
        this.updateBreakpoint();
      });
    } catch (error) {
      console.error('Failed to register window size change listener:', error);
    }
  }
  
  /**
   * 注册折叠屏状态变化监听
   */
  private registerFoldStatusChange(): void {
    try {
      display.on('foldStatusChange', () => {
        // 延迟更新，确保屏幕尺寸已更新
        setTimeout(() => {
          this.updateBreakpoint();
        }, 100);
      });
    } catch (error) {
      console.error('Failed to register fold status change listener:', error);
    }
  }
  
  /**
   * 更新当前断点
   */
  private updateBreakpoint(): void {
    const screenWidth = ScreenAdaptUtil.getScreenWidth();
    const newBreakpoint = this.getBreakpointByWidth(screenWidth);
    
    if (newBreakpoint !== this.currentBreakpoint) {
      this.currentBreakpoint = newBreakpoint;
      console.info(`Breakpoint changed to: ${newBreakpoint}, screen width: ${screenWidth}vp`);
      
      // 通知所有监听器
      this.listeners.forEach(listener => {
        listener(newBreakpoint);
      });
    }
  }
  
  /**
   * 根据屏幕宽度获取断点类型
   */
  private getBreakpointByWidth(width: number): BreakpointType {
    if (width < 320) {
      return 'xs';
    } else if (width < 600) {
      return 'sm';
    } else if (width < 840) {
      return 'md';
    } else if (width < 1440) {
      return 'lg';
    } else {
      return 'xl';
    }
  }
  
  /**
   * 添加断点变化监听器
   * @param listener 监听器函数
   */
  addBreakpointListener(listener: (breakpoint: BreakpointType) => void): void {
    this.listeners.push(listener);
  }
  
  /**
   * 移除断点变化监听器
   * @param listener 监听器函数
   */
  removeBreakpointListener(listener: (breakpoint: BreakpointType) => void): void {
    const index = this.listeners.indexOf(listener);
    if (index > -1) {
      this.listeners.splice(index, 1);
    }
  }
  
  /**
   * 获取当前断点类型
   */
  getCurrentBreakpoint(): BreakpointType {
    return this.currentBreakpoint;
  }
  
  /**
   * 获取当前屏幕宽度（vp单位）
   */
  static getScreenWidth(): number {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      // 将物理像素转换为vp（虚拟像素）
      // vp = px / (density / 160) = px * 160 / density
      const screenWidthVp = displayInfo.width * 160 / displayInfo.densityDPI;
      return screenWidthVp;
    } catch (error) {
      console.error('Failed to get screen width:', error);
      // 默认返回普通手机宽度
      return 360;
    }
  }

  /**
   * 根据屏幕宽度判断设备类型
   * @returns 'phone' | 'foldable2' | 'foldable3'
   */
  static getDeviceType(): 'phone' | 'foldable2' | 'foldable3' {
    const screenWidth = ScreenAdaptUtil.getScreenWidth();
    
    // 根据屏幕宽度判断设备类型
    // 普通手机：360-420vp
    // 两折叠：600-900vp
    // 三折叠：900vp以上
    if (screenWidth < 600) {
      return 'phone';
    } else if (screenWidth < 900) {
      return 'foldable2';
    } else {
      return 'foldable3';
    }
  }

  /**
   * 获取设备组页面的列数（响应式）
   * xs: 2列
   * sm: 2列（手机竖屏、折叠屏折叠态）
   * md: 3列（手机横屏、折叠屏展开态）
   * lg: 4列（平板、折叠屏大屏态）
   * xl: 6列（PC）
   */
  static getDeviceGroupColumns(): number {
    const instance = ScreenAdaptUtil.getInstance();
    const breakpoint = instance.getCurrentBreakpoint();
    
    switch (breakpoint) {
      case 'xs':
        return 2;
      case 'sm':
        return 2;
      case 'md':
        return 3;
      case 'lg':
        return 4;
      case 'xl':
        return 6;
      default:
        return 2;
    }
  }

  /**
   * 获取设备单元页面的列数（响应式）
   * xs: 1列
   * sm: 1列
   * md: 2列
   * lg: 3列
   * xl: 4列
   */
  static getDeviceUnitColumns(): number {
    const instance = ScreenAdaptUtil.getInstance();
    const breakpoint = instance.getCurrentBreakpoint();
    
    switch (breakpoint) {
      case 'xs':
        return 1;
      case 'sm':
        return 1;
      case 'md':
        return 2;
      case 'lg':
        return 3;
      case 'xl':
        return 4;
      default:
        return 1;
    }
  }

  /**
   * 生成Grid的columnsTemplate字符串
   * @param columns 列数
   */
  static generateColumnsTemplate(columns: number): string {
    return Array(columns).fill('1fr').join(' ');
  }
  
  /**
   * 销毁实例，释放资源
   */
  destroy(): void {
    if (this.windowClass) {
      try {
        this.windowClass.off('windowSizeChange');
      } catch (error) {
        console.error('Failed to unregister window size change listener:', error);
      }
    }
    
    try {
      display.off('foldStatusChange');
    } catch (error) {
      console.error('Failed to unregister fold status change listener:', error);
    }
    
    this.listeners = [];
    ScreenAdaptUtil.instance = null;
  }
}
