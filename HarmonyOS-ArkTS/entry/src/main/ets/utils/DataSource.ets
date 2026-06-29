// 数据源工具类，用于LazyForEach的数据包装
import { DeviceGroup, DeviceUnit } from '../model/DeviceModel';

// 数据变化监听器接口
interface DataChangeListener {
  onDataReloaded?(): void;
  onDataAdded?(index: number): void;
  onDataMoved?(from: number, to: number): void;
  onDataDeleted?(index: number): void;
  onDataChanged?(index: number): void;
}

// DeviceGroup数据源类
export class DeviceGroupDataSource {
  private data: DeviceGroup[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(data: DeviceGroup[]) {
    this.data = data || [];
  }

  totalCount(): number {
    return this.data.length;
  }

  getData(index: number): DeviceGroup | undefined {
    if (index < 0 || index >= this.data.length) {
      return undefined;
    }
    return this.data[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (listener && !this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  // 更新数据
  updateData(newData: DeviceGroup[]): void {
    this.data = newData || [];
    this.notifyDataReloaded();
  }

  // 添加数据
  addData(item: DeviceGroup): void {
    this.data.push(item);
    this.notifyDataAdded(this.data.length - 1);
  }

  // 删除数据
  deleteData(index: number): void {
    if (index >= 0 && index < this.data.length) {
      this.data.splice(index, 1);
      this.notifyDataDeleted(index);
    }
  }

  // 更新单个数据项
  updateItem(index: number, item: DeviceGroup): void {
    if (index >= 0 && index < this.data.length) {
      this.data[index] = item;
      this.notifyDataChanged(index);
    }
  }

  // 通知监听器数据已重新加载
  private notifyDataReloaded(): void {
    this.listeners.forEach(listener => {
      listener.onDataReloaded?.();
    });
  }

  // 通知监听器数据已添加
  private notifyDataAdded(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataAdded?.(index);
    });
  }

  // 通知监听器数据已删除
  private notifyDataDeleted(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataDeleted?.(index);
    });
  }

  // 通知监听器数据已更改
  private notifyDataChanged(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataChanged?.(index);
    });
  }

  // 通知监听器数据已移动
  private notifyDataMoved(from: number, to: number): void {
    this.listeners.forEach(listener => {
      listener.onDataMoved?.(from, to);
    });
  }
}

// DeviceUnit数据源类
export class DeviceUnitDataSource {
  private data: DeviceUnit[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(data: DeviceUnit[]) {
    this.data = data || [];
  }

  totalCount(): number {
    return this.data.length;
  }

  getData(index: number): DeviceUnit | undefined {
    if (index < 0 || index >= this.data.length) {
      return undefined;
    }
    return this.data[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (listener && !this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  // 更新数据
  updateData(newData: DeviceUnit[]): void {
    this.data = newData || [];
    this.notifyDataReloaded();
  }

  // 添加数据
  addData(item: DeviceUnit): void {
    this.data.push(item);
    this.notifyDataAdded(this.data.length - 1);
  }

  // 删除数据
  deleteData(index: number): void {
    if (index >= 0 && index < this.data.length) {
      this.data.splice(index, 1);
      this.notifyDataDeleted(index);
    }
  }

  // 更新单个数据项
  updateItem(index: number, item: DeviceUnit): void {
    if (index >= 0 && index < this.data.length) {
      this.data[index] = item;
      this.notifyDataChanged(index);
    }
  }

  // 通知监听器数据已重新加载
  private notifyDataReloaded(): void {
    this.listeners.forEach(listener => {
      listener.onDataReloaded?.();
    });
  }

  // 通知监听器数据已添加
  private notifyDataAdded(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataAdded?.(index);
    });
  }

  // 通知监听器数据已删除
  private notifyDataDeleted(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataDeleted?.(index);
    });
  }

  // 通知监听器数据已更改
  private notifyDataChanged(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataChanged?.(index);
    });
  }

  // 通知监听器数据已移动
  private notifyDataMoved(from: number, to: number): void {
    this.listeners.forEach(listener => {
      listener.onDataMoved?.(from, to);
    });
  }
}