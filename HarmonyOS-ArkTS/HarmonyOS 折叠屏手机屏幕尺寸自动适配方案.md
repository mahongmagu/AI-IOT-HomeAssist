# HarmonyOS 折叠屏手机屏幕尺寸自动适配方案

## 一、核心概念

折叠屏设备具有三种典型形态：<rsup>1</rsup>
- **折叠态**：屏幕尺寸较小，类似直板机<rsup>2</rsup>
- **展开态**：屏幕尺寸变大，类似平板
- **悬停态**：半折叠状态，可平稳放置桌面

HarmonyOS 通过**响应式布局**实现一套代码多端适配，核心能力包括：<rsup>3</rsup>

| 能力           | 说明                                          |
| -------------- | --------------------------------------------- |
| **断点系统**   | 将窗口宽度划分为不同区间，自动识别设备尺寸    |
| **媒体查询**   | 监听窗口尺寸、横竖屏、深浅色等变化            |
| **栅格布局**   | GridRow/GridCol 实现灵活的列数分配            |
| **响应式组件** | Tabs、Swiper、Grid、List 等组件内置响应式能力 |

---

## 二、断点系统详解

### 2.1 横向断点定义

| 断点名称 | 窗口宽度范围  | 典型设备 <rsup>4</rsup>                             |
| -------- | ------------- | --------------------------------------------------- |
| xs       | [0, 320vp)    | 智能手表                                            |
| sm       | [320, 600vp)  | 手机竖屏、折叠屏折叠态 <rsup>2</rsup><rsup>5</rsup> |
| md       | [600, 840vp)  | 手机横屏、折叠屏展开态 <rsup>5</rsup><rsup>1</rsup> |
| lg       | [840, 1440vp) | 平板、折叠屏大屏态 <rsup>6</rsup>                   |
| xl       | [1440, +∞)    | PC                                                  |

### 2.2 常见折叠屏设备断点

| 设备       | 形态      | 分辨率     | 横向断点 | 纵向断点 |
| ---------- | --------- | ---------- | -------- | -------- |
| Mate X5/X6 | 折叠态    | 345×801vp  | sm       | lg       |
| Mate X5/X6 | 展开态    | 711×798vp  | md       | md       |
| Mate XT    | F态(单屏) | 350×776vp  | sm       | lg       |
| Mate XT    | M态(双屏) | 712×776vp  | md       | md       |
| Mate XT    | G态(三屏) | 1107×776vp | lg       | sm       |
| Pura X Max | 折叠态    | 459×672vp  | sm       | lg       |
| Pura X Max | 展开态    | 939×664vp  | lg       | sm       |

---

## 三、实现方案

### 3.1 监听窗口尺寸变化

```typescript
// EntryAbility.ets
import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.getMainWindow().then((windowClass) => {
      // 获取初始窗口尺寸
      const windowRect = windowClass.getWindowProperties().windowRect;
      this.updateBreakpoint(windowRect.width);
      
      // 监听窗口尺寸变化
      windowClass.on('windowSizeChange', (windowSize: window.Size) => {
        this.updateBreakpoint(windowSize.width);
      });
    });
    
    windowStage.loadContent('pages/Index', (err) => {
      // ...
    });
  }
  
  private updateBreakpoint(windowWidth: number): void {
    // px转vp
    const displayInfo = display.getDefaultDisplaySync();
    const windowWidthVp = windowWidth / displayInfo.densityPixels;
    
    let currentBp: string = '';
    if (windowWidthVp < 320) {
      currentBp = 'xs';
    } else if (windowWidthVp < 600) {
      currentBp = 'sm';
    } else if (windowWidthVp < 840) {
      currentBp = 'md';
    } else if (windowWidthVp < 1440) {
      currentBp = 'lg';
    } else {
      currentBp = 'xl';
    }
    
    // 存储到全局状态
    AppStorage.setOrCreate('currentBreakpoint', currentBp);
  }
}
```

### 3.2 页面中使用断点

```typescript
// Index.ets
@Entry
@Component
struct Index {
  @StorageLink('currentBreakpoint') currentBp: string = 'sm';
  
  build() {
    Column() {
      // 根据断点动态调整布局
      if (this.currentBp === 'sm') {
        // 手机布局：单列
        this.PhoneLayout()
      } else if (this.currentBp === 'md') {
        // 折叠屏展开态：双列
        this.TabletLayout()
      } else {
        // 平板布局：三列或更多
        this.LargeScreenLayout()
      }
    }
    .width('100%')
    .height('100%')
  }
  
  @Builder
  PhoneLayout() {
    List() {
      // 单列列表
    }
    .lanes(1)
  }
  
  @Builder
  TabletLayout() {
    Grid() {
      // 双列网格
    }
    .columnsTemplate('1fr 1fr')
  }
  
  @Builder
  LargeScreenLayout() {
    Grid() {
      // 多列网格
    }
    .columnsTemplate('1fr 1fr 1fr')
  }
}
```

### 3.3 使用栅格组件 GridRow/GridCol

```typescript
import { GridRow, GridCol } from '@kit.ArkUI';

@Entry
@Component
struct ResponsivePage {
  @StorageLink('currentBreakpoint') currentBp: string = 'sm';
  
  build() {
    Column() {
      GridRow({
        columns: { sm: 4, md: 8, lg: 12 },  // 不同断点的栅格数
        gutter: 12,                          // 列间距
        breakpoints: { value: ['600vp', '840vp'] }
      }) {
        ForEach(this.dataList, (item: DataItem) => {
          GridCol({
            span: { sm: 4, md: 4, lg: 3 }  // 不同断点占用的栅格数
          }) {
            this.CardItem(item)
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
```

### 3.4 使用 Navigation 实现分栏布局

```typescript
@Entry
@Component
struct MainPage {
  @StorageLink('currentBreakpoint') currentBp: string = 'sm';
  private pageStack: NavPathStack = new NavPathStack();
  
  build() {
    Navigation(this.pageStack) {
      // 内容区
      Column() {
        Text('内容区域')
      }
    }
    // 根据断点自动切换模式
    .mode(this.currentBp === 'sm' ? NavigationMode.Stack : NavigationMode.Split)
    .navBarWidth(280)
  }
}
```

### 3.5 Tabs 组件响应式适配

```typescript
@Entry
@Component
struct TabsPage {
  @StorageLink('currentBreakpoint') currentBp: string = 'sm';
  
  build() {
    Tabs({
      barPosition: this.currentBp === 'lg' ? BarPosition.Start : BarPosition.End
    }) {
      TabContent() {
        Text('首页内容')
      }
      .tabBar('首页')
      
      TabContent() {
        Text('发现内容')
      }
      .tabBar('发现')
    }
    // 大屏时页签在左侧垂直排列
    .vertical(this.currentBp === 'lg')
    .barWidth(this.currentBp === 'lg' ? 100 : '100%')
    .barHeight(this.currentBp === 'lg' ? '100%' : 56)
  }
}
```

---

## 四、折叠屏特殊适配

### 4.1 监听折叠状态变化

```typescript
import { display } from '@kit.ArkUI';

@Entry
@Component
struct FoldAwarePage {
  @State foldStatus: display.FoldStatus = display.FoldStatus.FOLD_STATUS_UNKNOWN;
  
  aboutToAppear(): void {
    // 监听折叠状态变化
    display.on('foldStatusChange', (status: display.FoldStatus) => {
      this.foldStatus = status;
      console.info(`当前折叠状态: ${status}`);
    });
  }
  
  aboutToDisappear(): void {
    display.off('foldStatusChange');
  }
  
  build() {
    Column() {
      if (this.foldStatus === display.FoldStatus.FOLD_STATUS_EXPANDED) {
        // 展开态布局
        this.ExpandedLayout()
      } else if (this.foldStatus === display.FoldStatus.FOLD_STATUS_HALF_FOLDED) {
        // 悬停态布局
        this.HalfFoldedLayout()
      } else {
        // 折叠态布局
        this.FoldedLayout()
      }
    }
  }
}
```

### 4.2 悬停态折痕避让

悬停态时，中间折痕区域难以操作，需要避让：

```typescript
import { FolderStack } from '@kit.ArkUI';

@Entry
@Component
struct HoverPage {
  build() {
    FolderStack() {
      // 上半屏内容
      Column() {
        Text('上半屏：视频/图片展示')
      }
      
      // 下半屏内容
      Column() {
        Text('下半屏：操作按钮')
      }
    }
    .autoHalfFoldHeight(true)  // 自动适配悬停态高度
  }
}
```

### 4.3 开合连续性保证

确保折叠/展开时页面状态连续，焦点不偏移：

```typescript
@Component
struct ContinuousList {
  @State currentIndex: number = 0;
  private listScroller: Scroller = new Scroller();
  
  aboutToAppear(): void {
    display.on('foldStatusChange', (status: display.FoldStatus) => {
      // 折叠状态变化后，恢复到之前的滚动位置
      this.listScroller.scrollToIndex(this.currentIndex);
    });
  }
  
  build() {
    List({ scroller: this.listScroller }) {
      // 列表内容
    }
    .onScrollIndex((start: number) => {
      // 记录当前可见的第一个索引
      this.currentIndex = start;
    })
  }
}
```

---

## 五、最佳实践

### 5.1 不要依赖设备类型判断布局

```typescript
// ❌ 不推荐：依赖设备类型
if (deviceInfo.deviceType === 'tablet') {
  // 平板布局
}

// ✅ 推荐：使用断点判断
if (this.currentBp === 'lg') {
  // 大屏布局
}
```

### 5.2 图片适配建议

```typescript
Image($r('app.media.banner'))
  .width('100%')
  .height(this.currentBp === 'sm' ? 200 : 300)  // 不同断点不同高度
  .objectFit(ImageFit.Cover)
  .constraintSize({ maxHeight: '50%' })  // 限制最大高度
```

### 5.3 弹窗适配

```typescript
CustomDialog() {
  Column() {
    // 弹窗内容
  }
}
.constraintSize({ maxHeight: '90%' })  // 避免弹窗超出屏幕
.width(this.currentBp === 'sm' ? '80%' : 400)
```

### 5.4 文本适配

```typescript
Text('内容文本')
  .fontSize(this.currentBp === 'sm' ? 14 : 16)
  .maxLines(2)
  .textOverflow({ overflow: TextOverflow.Ellipsis })
```

---

## 六、调试技巧

### 6.1 使用 DevEco Studio 模拟器

1. 打开 DevEco Studio
2. Tools → Device Manager → Emulator
3. 选择 **Foldable** 或 **WideFold** 模拟器
4. 可实时切换折叠/展开状态

### 6.2 多设备同时预览

在 DevEco Studio 中可同时启动多个模拟器，实现多端实时热刷新调试。

---

## 七、总结

| 适配要点       | 说明                                                    |
| -------------- | ------------------------------------------------------- |
| **使用断点**   | 基于窗口宽度判断，不依赖设备类型 <rsup>5</rsup>         |
| **监听变化**   | `window.on('windowSizeChange')` 监听窗口尺寸变化        |
| **响应式组件** | 优先使用 GridRow/GridCol、Navigation、Tabs 等响应式组件 |
| **开合连续**   | 保证折叠/展开时页面状态连续，焦点不偏移                 |
| **悬停适配**   | 使用 FolderStack 避让折痕区域                           |
| **约束尺寸**   | 使用 `constraintSize` 限制组件最大尺寸                  |

通过以上方案，可实现一套代码在折叠屏手机不同屏幕尺寸下的自动适配，达到"一次开发，多端部署"的目标。<rsup>7</rsup>