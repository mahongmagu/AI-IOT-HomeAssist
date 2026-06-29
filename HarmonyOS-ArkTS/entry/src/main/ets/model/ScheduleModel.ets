// 定时任务数据模型

// 定时任务类型枚举
export enum ScheduleType {
  ONCE = 'once',       // 一次性任务
  DAILY = 'daily',     // 每天任务
  WEEKLY = 'weekly',   // 每周任务
  INTERVAL = 'interval' // 周期性任务
}

// 定时任务状态
export enum ScheduleStatus {
  ENABLED = 'enabled',   // 启用
  DISABLED = 'disabled'  // 禁用
}

// 定时任务接口
export interface Schedule {
  id: string;              // 任务ID
  name: string;            // 任务名称
  unitId: string;          // 设备单元ID
  cmd: string;             // 执行命令 (ON/OFF) - 大写
  time?: string;           // 执行时间 (ISO格式)
  recurring?: boolean;     // 是否重复 - boolean类型
  interval?: number;       // 重复间隔 (毫秒)
  weekdays?: number[];     // 周几执行 (0-6, 0=周日)
  enabled?: boolean;       // 是否启用
  createdAt?: string;      // 创建时间 (ISO格式)
  timer?: object;          // 定时器对象 (服务端使用)
}

// 定时任务列表响应
export interface ScheduleListResponse {
  code: number;
  msg?: string;
  schedules: Record<string, Schedule>;
}

// 创建/更新定时任务请求
export interface ScheduleRequest {
  id?: string;             // 任务ID (更新时需要)
  name?: string;           // 任务名称
  unitId: string;          // 设备单元ID
  cmd: string;             // 执行命令 (ON/OFF) - 大写
  time?: string;           // 执行时间
  recurring?: boolean;     // 是否重复 - boolean类型
  interval?: number;       // 重复间隔
  weekdays?: number[];     // 周几执行
}

// 定时任务启用/禁用请求
export interface ScheduleEnableRequest {
  enable: boolean;
}

// 定时任务API响应
export interface ScheduleApiResponse {
  code: number;
  msg?: string;
  data?: Schedule;
}

// 定时任务工具类
export class ScheduleUtil {
  // 获取定时任务类型显示文本
  static getTypeLabel(schedule: Schedule): string {
    if (schedule.recurring || (schedule.interval !== undefined && schedule.interval > 0)) {
      if (schedule.interval === 86400000) {
        return '每天';
      } else if (schedule.interval === 604800000) {
        return '每周';
      } else if (schedule.interval && schedule.interval > 0) {
        return '周期性';
      }
    }
    return '一次性';
  }

  // 获取定时任务时间显示文本
  static getTimeDisplay(schedule: Schedule): string {
    if (!schedule.time) {
      return '未知时间';
    }

    const date = new Date(schedule.time);
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    const timeStr = `${hours}:${minutes}`;

    // 根据interval判断类型
    if (schedule.recurring && schedule.interval !== undefined && schedule.interval > 0) {
      if (schedule.interval === 86400000) {
        // 每天
        return `每天 ${timeStr}`;
      } else if (schedule.interval === 604800000) {
        // 每周
        if (schedule.weekdays && schedule.weekdays.length > 0) {
          const weekNames = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
          const daysStr = schedule.weekdays.map(d => weekNames[d]).join('、');
          return `每周 ${daysStr} ${timeStr}`;
        }
        return `每周 ${timeStr}`;
      } else {
        // 自定义周期
        const intervalMinutes = Math.floor(schedule.interval / 60000);
        if (intervalMinutes < 60) {
          return `每${intervalMinutes}分钟`;
        } else {
          const intervalHours = Math.floor(intervalMinutes / 60);
          return `每${intervalHours}小时`;
        }
      }
    } else {
      // 一次性任务，显示完整日期时间
      const year = date.getFullYear();
      const month = String(date.getMonth() + 1).padStart(2, '0');
      const day = String(date.getDate()).padStart(2, '0');
      return `${year}-${month}-${day} ${timeStr}`;
    }
  }

  // 将本地时间转换为UTC ISO格式
  static localTimeToUTC(hour: number, minute: number): string {
    const now = new Date();
    now.setHours(hour, minute, 0, 0);
    
    // 如果时间已过，设置为明天
    if (now.getTime() <= Date.now()) {
      now.setDate(now.getDate() + 1);
    }
    
    return now.toISOString();
  }

  // 计算下一个执行时间（用于每周任务）
  static getNextWeeklyTime(hour: number, minute: number, weekdays: number[]): string {
    const now = new Date();
    
    for (let offset = 0; offset < 14; offset++) {
      const candidate = new Date(now);
      candidate.setDate(now.getDate() + offset);
      candidate.setHours(hour, minute, 0, 0);
      
      const weekday = candidate.getDay();
      if (weekdays.includes(weekday) && candidate.getTime() > now.getTime()) {
        return candidate.toISOString();
      }
    }
    
    // 如果找不到，返回一周后的第一个匹配日
    const firstMatch = new Date(now);
    firstMatch.setDate(now.getDate() + 7);
    firstMatch.setHours(hour, minute, 0, 0);
    return firstMatch.toISOString();
  }
  
  // 获取定时任务显示时间（用于列表显示）
  static getDisplayTime(schedule: Schedule): string {
    return ScheduleUtil.getTimeDisplay(schedule);
  }
  
  // 创建默认定时任务
  static createDefault(unitId: string): Schedule {
    return {
      id: '',
      name: '新定时任务',
      unitId: unitId,
      cmd: 'ON',              // 大写ON
      time: new Date().toISOString(),
      recurring: true,        // boolean类型
      interval: 86400000,     // 默认每天（86400000毫秒）
      enabled: true
    };
  }
}
