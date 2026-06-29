import hilog from '@ohos.hilog';
import { ServerConfig } from '../model/ServerConfig';
import http from '@ohos.net.http';

import { DeviceIcons } from '../config/DeviceIcons';

// API响应接口
import { DeviceGroup, DeviceUnit, ScheduleTask } from '../model/DeviceModel';

// 定义API响应的接口类型
export interface ApiResponse<T = object | string | number | boolean | null> {
  success: boolean;
  message?: string;
  data?: T;
}

// 定义API响应数据结构的接口
// 服务器配置项的接口定义
export interface ServerConfigUnitItem {
  id?: string;
  name?: string;
  type?: string;
  status?: string;
}

export interface ServerConfigUnit {
  id?: string;
  name?: string;
  type?: string;
  status?: string;
  displayName?: string;
  location?: string;
  units?: ServerConfigUnitItem[];
}

export type ServerConfigGroup = Record<string, ServerConfigUnit>;

export interface ApiResponseBody {
  code?: number;
  msg?: string;
  success?: boolean;
  message?: string;
  data?: object | string | number | boolean | null | DeviceGroup[];
  configs?: ServerConfigGroup;
}

export interface AiApiResponseBody {
  code: number;
  msg?: string;
  message?: string;
  details?: object[];
  data?: object;
}

// 用于设备相关API的响应类型
export type DeviceApiResponse = ApiResponse<DeviceGroup[]>;

// 定时任务响应数据接口
export interface ScheduleTaskResponseData {
  taskId: string;
  scheduledAt: string;
}

// 常量定义
const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'ApiService';
const HTTP_TIMEOUT: number = 30000; // HTTP请求超时时间（毫秒）增加到30秒

export class ApiService {
  private static instance: ApiService | null = null;
  private httpRequest: http.HttpRequest = http.createHttp();
  private destroyed: boolean = false;

  static getInstance(): ApiService {
    if (!ApiService.instance) {
      ApiService.instance = new ApiService();
    }
    return ApiService.instance;
  }

  /**
   * 销毁服务实例，释放资源
   */
  destroy(): void {
    if (!this.destroyed) {
      try {
        if (this.httpRequest) {
          this.httpRequest.destroy();
        }
        this.destroyed = true;
        ApiService.instance = null;
      } catch (error) {
        console.error('Error during ApiService destruction:', error);
      }
    }
  }

  // 检查服务是否已销毁
  private checkDestroyed(): void {
    if (this.destroyed) {
      throw new Error('ApiService has been destroyed and cannot be used');
    }
  }

  // 验证登录参数
  private validateLoginInput(username: string, password: string): void {
    if (!username || typeof username !== 'string' || username.trim() === '') {
      throw new Error('用户名不能为空');
    }
    if (!password || typeof password !== 'string' || password.trim() === '') {
      throw new Error('密码不能为空');
    }
    
    // 防止潜在的注入攻击，限制长度和字符类型
    if (username.length > 100) {
      throw new Error('用户名长度不能超过100个字符');
    }
    if (password.length > 100) {
      throw new Error('密码长度不能超过100个字符');
    }
    
    // 验证用户名格式（只允许字母数字下划线）
    if (!/^[a-zA-Z0-9_]+$/.test(username)) {
      throw new Error('用户名只能包含字母、数字和下划线');
    }
  }

  // 验证设备组和单元ID
  private validateDeviceInput(deviceGroup: string, unitId: string): void {
    if (!deviceGroup || typeof deviceGroup !== 'string' || deviceGroup.trim() === '') {
      throw new Error('设备组不能为空');
    }
    if (!unitId || typeof unitId !== 'string' || unitId.trim() === '') {
      throw new Error('设备单元ID不能为空');
    }
    
    // 限制长度
    if (deviceGroup.length > 50) {
      throw new Error('设备组名称长度不能超过50个字符');
    }
    if (unitId.length > 50) {
      throw new Error('设备单元ID长度不能超过50个字符');
    }
    
    // 验证格式（只允许字母数字和连字符）
    if (!/^[a-zA-Z0-9_-]+$/.test(deviceGroup)) {
      throw new Error('设备组名称只能包含字母、数字、下划线和连字符');
    }
    if (!/^[a-zA-Z0-9_-]+$/.test(unitId)) {
      throw new Error('设备单元ID只能包含字母、数字、下划线和连字符');
    }
  }

  // 验证控制命令
  private validateCommandInput(command: string): void {
    if (!command || typeof command !== 'string' || command.trim() === '') {
      throw new Error('控制命令不能为空');
    }
    
    if (command.length > 20) {
      throw new Error('控制命令长度不能超过20个字符');
    }
    
    // 只允许特定的命令值
    const validCommands = ['ON', 'OFF', 'TOGGLE'];
    if (!validCommands.includes(command.toUpperCase())) {
      throw new Error('控制命令只能是 ON、OFF 或 TOGGLE');
    }
  }

  // 验证AI命令
  private validateAICommandInput(command: string): void {
    if (!command || typeof command !== 'string' || command.trim() === '') {
      throw new Error('AI命令不能为空');
    }
    
    if (command.length > 500) {
      throw new Error('AI命令长度不能超过500个字符');
    }
  }

  // 登录认证
  async login(username: string, password: string): Promise<ApiResponse> {
    this.checkDestroyed();
    this.validateLoginInput(username, password);
    
    // 添加调试日志
    const baseUrl = ServerConfig.getApiBaseUrl();
    const url = `${baseUrl}/api/auth`;
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Login URL: %{public}s', [url]);
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json'
      },
      extraData: JSON.stringify({
        username: username,
        password: password
      }),
      connectTimeout: HTTP_TIMEOUT,
      readTimeout: HTTP_TIMEOUT
    };

    return new Promise<ApiResponse>((resolve, reject) => {
      this.httpRequest.request(url, options).then((response: http.HttpResponse) => {
        if (response.responseCode === 200) {
          try {
            const parsedResult: ApiResponseBody = JSON.parse(response.result as string);
            
            // 根据后端实际返回格式：{code: 200, msg: "..."}
            // 来源：V11/index.html 登录流程
            const result: ApiResponse = {
              success: parsedResult.code === 200 || parsedResult.success === true,
              message: parsedResult.msg || parsedResult.message,
              data: parsedResult.data || null
            };
            resolve(result);
          } catch (error) {
            // 如果解析失败，返回一个默认的ApiResponse
            resolve({
              success: true,
              message: 'Request successful',
              data: null
            });
          }
        } else {
          const errorMessage = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
          reject(new Error(`HTTP ${response.responseCode}: ${errorMessage}`));
        }
      }).catch((error: Error) => {
        // 添加详细的错误日志
        hilog.error(LOG_DOMAIN, LOG_TAG, 'HTTP request failed for URL: %{public}s', [url]);
        hilog.error(LOG_DOMAIN, LOG_TAG, 'HTTP request error: %{public}s', [error.message]);
        hilog.error(LOG_DOMAIN, LOG_TAG, 'HTTP request error stack: %{public}s', [error.stack || 'No stack trace']);
        
        // 检查是否是URL格式错误
        if (error.message.includes('URL') || error.message.includes('url') || error.message.includes('hostname')) {
          reject(new Error(`URL格式错误: ${url}。请检查服务器地址和端口是否正确。`));
        } else {
          reject(error);
        }
      });
    });
  }

  // 获取设备列表
  async getDevices(): Promise<DeviceApiResponse> {
    this.checkDestroyed();
    const url = `${ServerConfig.getApiBaseUrl()}/api/config`;
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      connectTimeout: HTTP_TIMEOUT,
      readTimeout: HTTP_TIMEOUT
    };

    return new Promise<DeviceApiResponse>((resolve, reject) => {
      this.httpRequest.request(url, options).then((response: http.HttpResponse) => {
        if (response.responseCode === 200) {
          try {
            const responseStr = typeof response.result === 'string' ? response.result : String(response.result);
            const parsedResult: ApiResponseBody = JSON.parse(responseStr);
            
            // 处理服务端返回的设备配置格式
            const serverConfigs: ServerConfigGroup = parsedResult.configs || {};
            const deviceGroups: DeviceGroup[] = this.transformServerConfigToDeviceGroups(serverConfigs);
            
            const result: DeviceApiResponse = {
              success: parsedResult.success ?? true,
              message: parsedResult.message,
              data: deviceGroups
            };
            resolve(result);
          } catch (error) {
            // 如果解析失败，返回一个默认的ApiResponse
            resolve({
              success: true,
              message: 'Request successful',
              data: []
            });
          }
        } else {
          const errorMessage = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
          reject(new Error(`HTTP ${response.responseCode}: ${errorMessage}`));
        }
      }).catch((error: Error) => {
        reject(error);
      });
    });
  }

  private validateDeviceUnitType(type: string | undefined): 'control' | 'state' | 'text' | 'data' | undefined {
    if (!type) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'validateDeviceUnitType: type is undefined/null, defaulting to control');
      return undefined;
    }

    const lowerType = type.toLowerCase();
    if (lowerType === 'control' || lowerType === 'state' || lowerType === 'text' || lowerType === 'data') {
      hilog.info(LOG_DOMAIN, LOG_TAG, `validateDeviceUnitType: ${type} -> ${lowerType}`);
      return lowerType;
    }
    
    hilog.warn(LOG_DOMAIN, LOG_TAG, `validateDeviceUnitType: unknown type ${type}, defaulting to control`);
    return undefined;
  }

  // 将服务端配置格式转换为鸿蒙应用设备组格式
  private transformServerConfigToDeviceGroups(serverConfigs: ServerConfigGroup): DeviceGroup[] {
    const deviceGroups: DeviceGroup[] = [];
    
    const keys = Object.keys(serverConfigs);
    for (let i = 0; i < keys.length; i++) {
      const groupName = keys[i];
      const config = serverConfigs[groupName];
      // 跳过特殊字段
      if (groupName === 'lastUpdated') continue;
      
      if (config && typeof config === 'object') {
        const group: DeviceGroup = new DeviceGroup();
        group.id = config.id || groupName;
        group.name = config.name || groupName;
        group.groupName = groupName;
        group.displayName = config.displayName || config.name || groupName;
        group.location = config.location || '';
        
        // 设置默认图标
        group.icon = this.getIconByDeviceType(groupName);
        
        // 转换设备单元
        if (Array.isArray(config.units)) {
          group.units = config.units.map((unit: ServerConfigUnitItem) => {
            const deviceUnit = new DeviceUnit();
            deviceUnit.id = unit?.id || '';
            deviceUnit.name = unit?.name || '';
            // 添加详细日志
            hilog.info(LOG_DOMAIN, LOG_TAG, `Transforming unit: id=${unit?.id}, name=${unit?.name}, type=${unit?.type}`);
            deviceUnit.type = this.validateDeviceUnitType(unit?.type) || 'control';
            hilog.info(LOG_DOMAIN, LOG_TAG, `  -> Final type: ${deviceUnit.type}`);
            deviceUnit.status = unit?.status || 'OFF';
            return deviceUnit;
          });
          
          // 判断是否包含控制类型的设备
          group.hasControlUnit = config.units.some((unit: ServerConfigUnitItem) => unit?.type === 'control');
          
          // 初始状态为在线（实际状态需要后续更新）
          group.isOffline = false;
        } else {
          group.units = [];
          group.hasControlUnit = false;
          group.isOffline = false;
        }
        
        deviceGroups.push(group);
      }
    }
    
    return deviceGroups;
  }
  
  // 根据设备类型返回对应图标
  private getIconByDeviceType(deviceType: string): string {
    const item = DeviceIcons.find(i => i.key.toLowerCase() === deviceType.toLowerCase());
    return item?.icon ?? '🏠';
  }

  // 控制设备单元
  async controlUnit(deviceGroup: string, unitId: string, command: string): Promise<ApiResponse> {
    this.checkDestroyed();
    this.validateDeviceInput(deviceGroup, unitId);
    this.validateCommandInput(command);
    const url = `${ServerConfig.getApiBaseUrl()}/api/control-slot`;
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json'
      },
      extraData: JSON.stringify({
        slot: unitId,
        cmd: command
      }),
      connectTimeout: HTTP_TIMEOUT,
      readTimeout: HTTP_TIMEOUT
    };

    return new Promise<ApiResponse>((resolve, reject) => {
      this.httpRequest.request(url, options).then((response: http.HttpResponse) => {
        if (response.responseCode === 200) {
          try {
            const responseStr = typeof response.result === 'string' ? response.result : String(response.result);
            const parsedResult: ApiResponseBody = JSON.parse(responseStr);
            const result: ApiResponse = {
              success: parsedResult.success ?? true,
              message: parsedResult.message,
              data: parsedResult.data
            };
            resolve(result);
          } catch (error) {
            // 如果解析失败，返回一个默认的ApiResponse
            resolve({
              success: true,
              message: 'Request successful',
              data: response.result as object
            });
          }
        } else {
          const errorMessage = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
          reject(new Error(`HTTP ${response.responseCode}: ${errorMessage}`));
        }
      }).catch((error: Error) => {
        reject(error);
      });
    });
  }

  // 发送AI指令
  async sendAiCommand(command: string): Promise<ApiResponse> {
    this.checkDestroyed();
    this.validateAICommandInput(command);
    const url = `${ServerConfig.getApiBaseUrl()}/api/ai-advanced`;
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json'
      },
      extraData: JSON.stringify({
        text: command
      }),
      connectTimeout: HTTP_TIMEOUT,
      readTimeout: 60000
    };

    return new Promise<ApiResponse>((resolve, reject) => {
      this.httpRequest.request(url, options).then((response: http.HttpResponse) => {
        if (response.responseCode === 200) {
          try {
            const responseString = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
            const parsedResult: AiApiResponseBody = JSON.parse(responseString);
            const result: ApiResponse = {
              success: parsedResult.code === 200,
              message: parsedResult.msg || parsedResult.message,
              data: parsedResult.details || parsedResult.data
            };
            resolve(result);
          } catch (error) {
            resolve({
              success: true,
              message: 'Request successful',
              data: response.result as object
            });
          }
        } else {
          const errorMessage = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
          reject(new Error(`HTTP ${response.responseCode}: ${errorMessage}`));
        }
      }).catch((error: Error) => {
        reject(error);
      });
    });
  }

  // 获取服务器配置
  async getServerConfig(): Promise<ApiResponse> {
    this.checkDestroyed();
    const url = `${ServerConfig.getApiBaseUrl()}/api/config`;
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      connectTimeout: HTTP_TIMEOUT,
      readTimeout: HTTP_TIMEOUT
    };

    return new Promise<ApiResponse>((resolve, reject) => {
      this.httpRequest.request(url, options).then((response: http.HttpResponse) => {
        if (response.responseCode === 200) {
          try {
            const result: ApiResponseBody = typeof response.result === 'string' ? JSON.parse(response.result) : response.result;
            // 如果已是 ApiResponse 结构则直接返回，否则包装
            if (result && typeof result === 'object' && result.success !== undefined) {
              const apiResult: ApiResponse = {
                success: result.success,
                message: result.message,
                data: result.data
              };
              resolve(apiResult);
            } else {
              resolve({ success: true, message: 'Request successful', data: result as object });
            }
          } catch (err) {
            resolve({ success: true, message: 'Request successful', data: response.result as object });
          }
        } else {
          reject(new Error(`HTTP ${response.responseCode}: ${response.result}`));
        }
      }).catch((error: Error) => {
        reject(error);
      });
    });
  }

  // 更新设备单元值（text类型）
  async setTextValue(unitId: string, value: string): Promise<ApiResponse> {
    this.checkDestroyed();
    if (!unitId || typeof unitId !== 'string' || unitId.trim() === '') {
      throw new Error('设备单元ID不能为空');
    }
    if (value === undefined || value === null) {
      throw new Error('值不能为空');
    }
    const url = `${ServerConfig.getApiBaseUrl()}/api/set-text`;
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json'
      },
      extraData: JSON.stringify({
        slot: unitId,
        value: value
      }),
      connectTimeout: HTTP_TIMEOUT,
      readTimeout: HTTP_TIMEOUT
    };

    return new Promise<ApiResponse>((resolve, reject) => {
      this.httpRequest.request(url, options).then((response: http.HttpResponse) => {
        if (response.responseCode === 200) {
          try {
            const responseStr = typeof response.result === 'string' ? response.result : String(response.result);
            const parsedResult: ApiResponseBody = JSON.parse(responseStr);
            const result: ApiResponse = {
              success: parsedResult.success ?? true,
              message: parsedResult.message,
              data: parsedResult.data
            };
            resolve(result);
          } catch (error) {
            resolve({
              success: true,
              message: 'Request successful',
              data: response.result as object
            });
          }
        } else {
          const errorMessage = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
          reject(new Error(`HTTP ${response.responseCode}: ${errorMessage}`));
        }
      }).catch((error: Error) => {
        reject(error);
      });
    });
  }

  // 更新设备单元值（data类型）
  async setDataValue(unitId: string, value: string): Promise<ApiResponse> {
    this.checkDestroyed();
    if (!unitId || typeof unitId !== 'string' || unitId.trim() === '') {
      throw new Error('设备单元ID不能为空');
    }
    if (value === undefined || value === null) {
      throw new Error('值不能为空');
    }
    const url = `${ServerConfig.getApiBaseUrl()}/api/set-data`;
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json'
      },
      extraData: JSON.stringify({
        slot: unitId,
        value: value
      }),
      connectTimeout: HTTP_TIMEOUT,
      readTimeout: HTTP_TIMEOUT
    };

    return new Promise<ApiResponse>((resolve, reject) => {
      this.httpRequest.request(url, options).then((response: http.HttpResponse) => {
        if (response.responseCode === 200) {
          try {
            const responseStr = typeof response.result === 'string' ? response.result : String(response.result);
            const parsedResult: ApiResponseBody = JSON.parse(responseStr);
            const result: ApiResponse = {
              success: parsedResult.success ?? true,
              message: parsedResult.message,
              data: parsedResult.data
            };
            resolve(result);
          } catch (error) {
            resolve({
              success: true,
              message: 'Request successful',
              data: response.result as object
            });
          }
        } else {
          const errorMessage = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
          reject(new Error(`HTTP ${response.responseCode}: ${errorMessage}`));
        }
      }).catch((error: Error) => {
        reject(error);
      });
    });
  }

  // 更新设备单元值（兼容旧接口，根据类型调用对应接口）
  async updateUnit(deviceGroup: string, unitId: string, value: string, unitType?: string): Promise<ApiResponse> {
    this.checkDestroyed();
    // 根据单元类型调用不同的接口
    if (unitType === 'text') {
      return this.setTextValue(unitId, value);
    } else if (unitType === 'data') {
      return this.setDataValue(unitId, value);
    } else {
      // 默认使用data接口
      return this.setDataValue(unitId, value);
    }
  }
}