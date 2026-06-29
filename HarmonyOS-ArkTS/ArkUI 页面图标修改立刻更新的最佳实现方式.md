# ArkUI 页面图标修改立刻更新的最佳实现方式

在 ArkUI 中，图标修改后立刻更新的核心是**状态驱动 UI**，通过状态管理装饰器实现响应式更新。以下是最佳实践和完整代码示例。<rsup>1</rsup><rsup>2</rsup>

## 一、核心原理

ArkUI 采用声明式 UI 范式：**UI = f(state)**

当 `@State` 等装饰器修饰的变量发生变化时，框架会自动检测变化并重新渲染依赖该状态的 UI 组件。<rsup>3</rsup><rsup>4</rsup>

## 二、最佳实践方案

### 方案一：基础图标切换（推荐）

```typescript
@Entry
@Component
struct IconTogglePage {
  // 使用 @State 管理图标状态
  @State isPlaying: boolean = false
  
  build() {
    Column({ space: 20 }) {
      // 直接绑定状态变量，自动响应变化
      Image(this.isPlaying ? $r('app.media.pause_icon') : $r('app.media.play_icon'))
        .width(48)
        .height(48)
        .onClick(() => {
          // 修改状态，自动触发 UI 更新
          this.isPlaying = !this.isPlaying
        })
      
      // 文字提示也会同步更新
      Text(this.isPlaying ? '暂停' : '播放')
        .fontSize(16)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
```

### 方案二：图标列表动态更新

```typescript
// 定义图标数据模型
class IconItem {
  id: number
  icon: Resource
  label: string
  isSelected: boolean
  
  constructor(id: number, icon: Resource, label: string) {
    this.id = id
    this.icon = icon
    this.label = label
    this.isSelected = false
  }
}

@Entry
@Component
struct IconListPage {
  // 管理图标列表状态
  @State iconList: IconItem[] = [
    new IconItem(1, $r('app.media.icon_home'), '首页'),
    new IconItem(2, $r('app.media.icon_message'), '消息'),
    new IconItem(3, $r('app.media.icon_profile'), '我的')
  ]
  
  // 当前选中的图标 ID
  @State selectedId: number = 1
  
  build() {
    Column({ space: 20 }) {
      Text('请选择功能')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
      
      // 使用 ForEach 渲染图标列表
      Row({ space: 30 }) {
        ForEach(this.iconList, (item: IconItem) => {
          this.IconItemBuilder(item)
        }, (item: IconItem) => item.id.toString())
      }
      
      // 显示当前选中项
      Text(`当前选中: ${this.iconList.find(i => i.id === this.selectedId)?.label}`)
        .fontSize(16)
        .fontColor('#666666')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
  
  // 使用 @Builder 封装图标项
  @Builder
  IconItemBuilder(item: IconItem) {
    Column({ space: 8 }) {
      Image(item.icon)
        .width(40)
        .height(40)
        // 根据选中状态改变颜色
        .fillColor(item.id === this.selectedId ? '#007DFF' : '#999999')
      
      Text(item.label)
        .fontSize(12)
        .fontColor(item.id === this.selectedId ? '#007DFF' : '#666666')
    }
    .onClick(() => {
      // 更新选中状态，触发 UI 刷新
      this.selectedId = item.id
    })
  }
}
```

### 方案三：带动画的图标切换

```typescript
@Entry
@Component
struct AnimatedIconPage {
  @State isLiked: boolean = false
  @State likeCount: number = 128
  
  build() {
    Column({ space: 20 }) {
      Row({ space: 10 }) {
        // 图标带动画效果
        Image(this.isLiked ? $r('app.media.icon_liked') : $r('app.media.icon_like'))
          .width(32)
          .height(32)
          .fillColor(this.isLiked ? '#FF0000' : '#999999')
          // 添加缩放动画
          .scale({ x: this.isLiked ? 1.2 : 1.0, y: this.isLiked ? 1.2 : 1.0 })
          // 动画配置
          .animation({
            duration: 200,
            curve: Curve.EaseOut
          })
          .onClick(() => {
            // 使用 animateTo 包裹状态修改，实现流畅动画
            animateTo({ duration: 200 }, () => {
              this.isLiked = !this.isLiked
              this.likeCount += this.isLiked ? 1 : -1
            })
          })
        
        Text(`${this.likeCount}`)
          .fontSize(16)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
```

### 方案四：复杂对象图标管理（@Observed + @ObjectLink）

```typescript
// 使用 @Observed 装饰可观察的类
@Observed
class TabItem {
  id: number
  icon: Resource
  selectedIcon: Resource
  label: string
  isSelected: boolean
  
  constructor(id: number, icon: Resource, selectedIcon: Resource, label: string) {
    this.id = id
    this.icon = icon
    this.selectedIcon = selectedIcon
    this.label = label
    this.isSelected = false
  }
}

// 子组件使用 @ObjectLink 接收对象
@Component
struct TabItemComponent {
  @ObjectLink tabItem: TabItem
  onTabClick?: (id: number) => void
  
  build() {
    Column({ space: 4 }) {
      // 根据选中状态显示不同图标
      Image(this.tabItem.isSelected ? this.tabItem.selectedIcon : this.tabItem.icon)
        .width(24)
        .height(24)
      
      Text(this.tabItem.label)
        .fontSize(10)
        .fontColor(this.tabItem.isSelected ? '#007DFF' : '#999999')
    }
    .onClick(() => {
      this.onTabClick?.(this.tabItem.id)
    })
  }
}

@Entry
@Component
struct TabBarPage {
  @State tabList: TabItem[] = [
    new TabItem(1, $r('app.media.tab_home'), $r('app.media.tab_home_selected'), '首页'),
    new TabItem(2, $r('app.media.tab_discover'), $r('app.media.tab_discover_selected'), '发现'),
    new TabItem(3, $r('app.media.tab_mine'), $r('app.media.tab_mine_selected'), '我的')
  ]
  
  // 切换 Tab
  switchTab(id: number) {
    this.tabList.forEach(item => {
      item.isSelected = item.id === id
    })
  }
  
  build() {
    Column() {
      // 内容区域
      Column() {
        Text(`当前页面: ${this.tabList.find(t => t.isSelected)?.label}`)
          .fontSize(24)
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      
      // 底部 TabBar
      Row() {
        ForEach(this.tabList, (item: TabItem) => {
          TabItemComponent({ 
            tabItem: item,
            onTabClick: (id: number) => this.switchTab(id)
          })
        }, (item: TabItem) => item.id.toString())
      }
      .width('100%')
      .height(60)
      .justifyContent(FlexAlign.SpaceEvenly)
      .backgroundColor('#F5F5F5')
    }
    .width('100%')
    .height('100%')
  }
}
```

## 三、关键注意事项

### ⚠️ 常见错误示例

```typescript
// ❌ 错误：在 build 中直接修改状态变量
@Entry
@Component
struct BadExample {
  @State count: number = 0
  
  build() {
    Column() {
      // 错误！会导致无限循环
      Text(`${this.count++}`)
    }
  }
}
```

### ✅ 正确做法

```typescript
@Entry
@Component
struct GoodExample {
  @State count: number = 0
  
  build() {
    Column() {
      Text(`${this.count}`)
        .onClick(() => {
          // 在事件回调中修改状态
          this.count++
        })
    }
  }
}
```

### 性能优化建议

```typescript
@Entry
@Component
struct OptimizedExample {
  @State iconList: string[] = []
  
  // ✅ 使用临时变量优化性能
  updateIcons() {
    let tempList = [...this.iconList]
    tempList.push('new_icon')
    tempList.push('another_icon')
    // 只在最后赋值一次，减少渲染次数
    this.iconList = tempList
  }
  
  build() {
    Column() {
      Button('更新图标')
        .onClick(() => this.updateIcons())
    }
  }
}
```

## 四、总结

| 场景         | 推荐装饰器                  | 说明                     |
| ------------ | --------------------------- | ------------------------ |
| 简单图标切换 | `@State`                    | 最常用，组件内私有状态   |
| 父子组件传递 | `@Prop` / `@Link`           | 父→子单向或双向同步      |
| 跨层级共享   | `@Provide` / `@Consume`     | 适合全局状态如主题、语言 |
| 复杂对象     | `@Observed` + `@ObjectLink` | 需要观察对象内部属性变化 |

**核心原则**：
1. **状态变量必须在事件回调中修改**，不能在 `build()` 中直接修改
2. **使用临时变量减少状态修改次数**，优化性能
3. **选择合适的装饰器**，根据数据共享范围决定
4. **配合动画 API**（`animateTo`、`animation`）实现流畅的图标切换效果