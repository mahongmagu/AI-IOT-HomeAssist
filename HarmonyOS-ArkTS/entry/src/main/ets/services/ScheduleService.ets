// 定时任务API服务
import http from '@ohos.net.http';
import hilog from '@ohos.hilog';
import { ServerConfig } from '../model/ServerConfig';
import {
  Schedule,
  ScheduleListResponse,
  ScheduleRequest,
  ScheduleApiResponse
} from '../model/ScheduleModel';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'ScheduleService';

// API响应基础接口
interface BaseApiResponse {
  code: number;
  msg?: string;
}

export class ScheduleService {
  private static instance: ScheduleService;
  
  private constructor() {}
  
  static getInstance(): ScheduleService {
    if (!ScheduleService.instance) {
      ScheduleService.instance = new ScheduleService();
    }
    return ScheduleService.instance;
  }
  
  // 获取所有定时任务
  async getAllSchedules(): Promise<ScheduleListResponse> {
    const url = `${ServerConfig.getApiBaseUrl()}/api/schedule`;
    
    try {
      const httpRequest = http.createHttp();
      
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Content-Type': 'application/json'
        },
        connectTimeout: 10000,
        readTimeout: 10000
      });
      
      httpRequest.destroy();
      
      if (response.responseCode === 200) {
        const result = JSON.parse(response.result as string) as ScheduleListResponse;
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Get schedules success: %{public}d', [result.code]);
        return result;
      } else {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Get schedules failed: %{public}d', [response.responseCode]);
        return {
          code: response.responseCode,
          msg: `请求失败: ${response.responseCode}`,
          schedules: {}
        };
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Get schedules error: %{public}s', [(error as Error).message]);
      return {
        code: 500,
        msg: (error as Error).message,
        schedules: {}
      };
    }
  }
  
  // 创建定时任务
  async createSchedule(schedule: ScheduleRequest): Promise<ScheduleApiResponse> {
    const url = `${ServerConfig.getApiBaseUrl()}/api/schedule`;
    
    // 调试日志：记录请求数据
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Creating schedule with data: %{public}s', [JSON.stringify(schedule)]);
    
    try {
      const httpRequest = http.createHttp();
      
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json'
        },
        extraData: schedule,
        connectTimeout: 10000,
        readTimeout: 10000
      });
      
      httpRequest.destroy();
      
      if (response.responseCode === 200) {
        const result = JSON.parse(response.result as string) as ScheduleApiResponse;
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Create schedule success: %{public}d', [result.code]);
        return result;
      } else {
        // 记录服务器返回的错误信息
        const errorResult = response.result as string;
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Create schedule failed: %{public}d, response: %{public}s', [response.responseCode, errorResult]);
        return {
          code: response.responseCode,
          msg: errorResult || `请求失败: ${response.responseCode}`
        };
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Create schedule error: %{public}s', [(error as Error).message]);
      return {
        code: 500,
        msg: (error as Error).message
      };
    }
  }
  
  // 创建周期性定时任务
  async createRecurringSchedule(schedule: ScheduleRequest): Promise<ScheduleApiResponse> {
    const url = `${ServerConfig.getApiBaseUrl()}/api/schedule/recurring`;
    
    // 调试日志：记录请求数据
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Creating recurring schedule with data: %{public}s', [JSON.stringify(schedule)]);
    
    try {
      const httpRequest = http.createHttp();
      
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json'
        },
        extraData: schedule,
        connectTimeout: 10000,
        readTimeout: 10000
      });
      
      httpRequest.destroy();
      
      if (response.responseCode === 200) {
        const result = JSON.parse(response.result as string) as ScheduleApiResponse;
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Create recurring schedule success: %{public}d', [result.code]);
        return result;
      } else {
        // 记录服务器返回的错误信息
        const errorResult = response.result as string;
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Create recurring schedule failed: %{public}d, response: %{public}s', [response.responseCode, errorResult]);
        return {
          code: response.responseCode,
          msg: errorResult || `请求失败: ${response.responseCode}`
        };
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Create recurring schedule error: %{public}s', [(error as Error).message]);
      return {
        code: 500,
        msg: (error as Error).message
      };
    }
  }
  
  // 更新定时任务
  async updateSchedule(scheduleId: string, schedule: ScheduleRequest): Promise<ScheduleApiResponse> {
    const url = `${ServerConfig.getApiBaseUrl()}/api/schedule/${scheduleId}`;
    
    try {
      const httpRequest = http.createHttp();
      
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.PUT,
        header: {
          'Content-Type': 'application/json'
        },
        extraData: schedule,
        connectTimeout: 10000,
        readTimeout: 10000
      });
      
      httpRequest.destroy();
      
      if (response.responseCode === 200) {
        const result = JSON.parse(response.result as string) as ScheduleApiResponse;
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Update schedule success: %{public}d', [result.code]);
        return result;
      } else {
        // 记录服务器返回的错误信息
        const errorResult = response.result as string;
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Update schedule failed: %{public}d, response: %{public}s', [response.responseCode, errorResult]);
        return {
          code: response.responseCode,
          msg: errorResult || `请求失败: ${response.responseCode}`
        };
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Update schedule error: %{public}s', [(error as Error).message]);
      return {
        code: 500,
        msg: (error as Error).message
      };
    }
  }
  
  // 删除定时任务
  async deleteSchedule(scheduleId: string): Promise<BaseApiResponse> {
    const url = `${ServerConfig.getApiBaseUrl()}/api/schedule/${scheduleId}`;
    
    try {
      const httpRequest = http.createHttp();
      
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.DELETE,
        header: {
          'Content-Type': 'application/json'
        },
        connectTimeout: 10000,
        readTimeout: 10000
      });
      
      httpRequest.destroy();
      
      if (response.responseCode === 200) {
        const result = JSON.parse(response.result as string) as BaseApiResponse;
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Delete schedule success: %{public}d', [result.code]);
        return result;
      } else {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Delete schedule failed: %{public}d', [response.responseCode]);
        return {
          code: response.responseCode,
          msg: `请求失败: ${response.responseCode}`
        };
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Delete schedule error: %{public}s', [(error as Error).message]);
      return {
        code: 500,
        msg: (error as Error).message
      };
    }
  }
  
  // 启用/禁用定时任务
  async toggleScheduleEnable(scheduleId: string, enabled: boolean): Promise<BaseApiResponse> {
    const url = `${ServerConfig.getApiBaseUrl()}/api/schedule/${scheduleId}/enable`;
    
    try {
      const httpRequest = http.createHttp();
      
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.PUT,
        header: {
          'Content-Type': 'application/json'
        },
        extraData: { enabled },
        connectTimeout: 10000,
        readTimeout: 10000
      });
      
      httpRequest.destroy();
      
      if (response.responseCode === 200) {
        const result = JSON.parse(response.result as string) as BaseApiResponse;
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Toggle schedule enable success: %{public}d', [result.code]);
        return result;
      } else {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Toggle schedule enable failed: %{public}d', [response.responseCode]);
        return {
          code: response.responseCode,
          msg: `请求失败: ${response.responseCode}`
        };
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Toggle schedule enable error: %{public}s', [(error as Error).message]);
      return {
        code: 500,
        msg: (error as Error).message
      };
    }
  }
}
