import hilog from '@ohos.hilog';
import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ServerConfig } from '../model/ServerConfig';
import { DeviceGroup, DeviceUnit } from '../model/DeviceModel';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'WebSocketService';

export interface DeviceInfo {
  type: string;
  id: string;
  category: string;
  unit: string;
  unitType: string;
  topicType?: string;
  online?: boolean;
}

export interface StateUpdateMessage {
  type: string;
  device: DeviceInfo;
  state: string;
  topic: string;
  timestamp: string;
}

export interface HeartbeatMessage {
  type: string;
  timestamp: number;
}

export class WebSocketService {
  private static instance: WebSocketService | null = null;
  private isConnected: boolean = false;
  private reconnectAttempts: number = 0;
  private maxReconnectAttempts: number = 5;
  private reconnectDelay: number = 3000;
  private connectionTimeout: number = 10000; // 连接超时时间（毫秒）
  private stateUpdateCallback: ((message: StateUpdateMessage) => void) | null = null;
  private connectionCallback: ((connected: boolean) => void) | null = null;
  private socket: webSocket.WebSocket | null = null;
  private heartbeatTimer: number | undefined = undefined;
  private connectionTimer: number | undefined = undefined;

  private constructor() {}

  static getInstance(): WebSocketService {
    if (!WebSocketService.instance) {
      WebSocketService.instance = new WebSocketService();
    }
    return WebSocketService.instance;
  }

  setCallback(callback: (message: StateUpdateMessage) => void): void {
    this.stateUpdateCallback = callback;
  }

  getCallback(): ((message: StateUpdateMessage) => void) | null {
    return this.stateUpdateCallback;
  }

  setConnectionCallback(callback: (connected: boolean) => void): void {
    this.connectionCallback = callback;
  }

  connect(): void {
    if (this.isConnected) {
      return;
    }

    // 清除之前的连接定时器
    if (this.connectionTimer !== undefined) {
      clearTimeout(this.connectionTimer);
      this.connectionTimer = undefined;
    }

    const wsUrl = this.buildWsUrl();
    if (!wsUrl) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Cannot build WebSocket URL - server not configured');
      return;
    }

    hilog.info(LOG_DOMAIN, LOG_TAG, `Connecting to WebSocket: ${wsUrl}`);

    try {
      // Create WebSocket instance
      this.socket = webSocket.createWebSocket();
      const socket = this.socket as webSocket.WebSocket;
      
      // Set up event listeners


      socket.on('message', (err: BusinessError, data: string | ArrayBuffer) => {
        if (err) {
          const errorMsg = err?.message || 'Unknown error';
          const errorCode = err?.code || 'N/A';
          hilog.error(LOG_DOMAIN, LOG_TAG, `WebSocket message error: ${errorMsg}, code: ${errorCode}`);
          return;
        }
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Received WebSocket message');
        try {
          if (typeof data === 'string') {
            const parsedData: object = JSON.parse(data);
            // Check if parsedData has the required properties of StateUpdateMessage
            if (this.isValidStateUpdateMessage(parsedData)) {
              const message = parsedData as StateUpdateMessage;
              this.stateUpdateCallback?.(message);
            } else {
              hilog.warn(LOG_DOMAIN, LOG_TAG, 'Received message is not in expected StateUpdateMessage format');
            }
          } else {
            // Handle object case - validate it as a StateUpdateMessage
            const validatedMessage = this.validateAsStateUpdateMessage(data);
            if (validatedMessage) {
              this.stateUpdateCallback?.(validatedMessage);
            } else {
              hilog.warn(LOG_DOMAIN, LOG_TAG, 'Received message is not in expected StateUpdateMessage format');
            }
          }
        } catch (error) {
          const errorMsg = error instanceof Error ? error.message : 'Unknown error';
          hilog.error(LOG_DOMAIN, LOG_TAG, `Error parsing WebSocket message: ${errorMsg}`);
        }
      });

      this.socket.on('close', (err: BusinessError, value: webSocket.CloseResult) => {
        // 清除连接超时定时器
        if (this.connectionTimer !== undefined) {
          clearTimeout(this.connectionTimer);
          this.connectionTimer = undefined;
        }
        
        const errorMsg = err?.message || 'No error';
        const errorCode = value?.code || 'N/A';
        const reason = value?.reason || 'Unknown reason';
        hilog.info(LOG_DOMAIN, LOG_TAG, `WebSocket closed: code=${errorCode}, reason=${reason}, error=${errorMsg}`);
        this.isConnected = false;
        this.connectionCallback?.(false);
        
        // Attempt to reconnect
        if (this.reconnectAttempts < this.maxReconnectAttempts) {
          this.reconnectAttempts++;
          hilog.info(LOG_DOMAIN, LOG_TAG, `Attempting to reconnect (${this.reconnectAttempts}/${this.maxReconnectAttempts})`);
          setTimeout(() => {
            this.connect();
          }, this.reconnectDelay);
        } else {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'Max reconnection attempts reached');
        }
      });

      this.socket.on('error', (err: BusinessError) => {
        // 清除连接超时定时器
        if (this.connectionTimer !== undefined) {
          clearTimeout(this.connectionTimer);
          this.connectionTimer = undefined;
        }
        
        const errorMsg = err?.message || 'Unknown error';
        const errorCode = err?.code || 'N/A';
        hilog.error(LOG_DOMAIN, LOG_TAG, `WebSocket error: ${errorMsg}, code: ${errorCode}`);
        this.isConnected = false;
        this.connectionCallback?.(false);
      });

      this.socket.on('open', (err: BusinessError, value: Object) => {
        // 清除连接超时定时器
        if (this.connectionTimer !== undefined) {
          clearTimeout(this.connectionTimer);
          this.connectionTimer = undefined;
        }
        
        if (err) {
          const errorMsg = err?.message || 'Unknown error';
          const errorCode = err?.code || 'N/A';
          hilog.error(LOG_DOMAIN, LOG_TAG, `WebSocket open error: ${errorMsg}, code: ${errorCode}`);
          this.isConnected = false;
          this.connectionCallback?.(false);
          return;
        }
        hilog.info(LOG_DOMAIN, LOG_TAG, 'WebSocket connected');
        this.isConnected = true;
        this.reconnectAttempts = 0;
        this.connectionCallback?.(true);
        
        // Start heartbeat
        this.startHeartbeat();
      });

      // Connect to WebSocket (headers not supported, use URL query params for auth)
      try {
        // 设置连接超时定时器
        this.connectionTimer = setTimeout(() => {
          if (!this.isConnected && this.socket) {
            hilog.warn(LOG_DOMAIN, LOG_TAG, 'WebSocket connection timeout after 10 seconds');
            try {
              const socket = this.socket as webSocket.WebSocket;
              socket.close((err: BusinessError) => {
                if (err) {
                  hilog.error(LOG_DOMAIN, LOG_TAG, `Error closing WebSocket on timeout: ${err.message}`);
                }
              });
            } catch (error) {
              const errorMsg = error instanceof Error ? error.message : 'Unknown error';
              hilog.error(LOG_DOMAIN, LOG_TAG, `Exception closing WebSocket on timeout: ${errorMsg}`);
            }
            this.socket = null;
            this.isConnected = false;
            this.connectionCallback?.(false);
            
            // 清除定时器
            if (this.connectionTimer !== undefined) {
              clearTimeout(this.connectionTimer);
              this.connectionTimer = undefined;
            }
          }
        }, this.connectionTimeout);
        
        socket.connect(wsUrl, (err: BusinessError, value: boolean) => {
          // 清除连接超时定时器
          if (this.connectionTimer !== undefined) {
            clearTimeout(this.connectionTimer);
            this.connectionTimer = undefined;
          }
          
          if (err) {
            const errorMsg = err?.message || 'Unknown error';
            const errorCode = err?.code || 'N/A';
            hilog.error(LOG_DOMAIN, LOG_TAG, `WebSocket connect failed: ${errorMsg}, code: ${errorCode}`);
            this.isConnected = false;
            this.connectionCallback?.(false);
          }
        });
      } catch (error) {
        // 清除连接超时定时器
        if (this.connectionTimer !== undefined) {
          clearTimeout(this.connectionTimer);
          this.connectionTimer = undefined;
        }
        
        const errorMsg = error instanceof Error ? error.message : 'Unknown error';
        hilog.error(LOG_DOMAIN, LOG_TAG, `WebSocket connect exception: ${errorMsg}`);
        this.isConnected = false;
        this.connectionCallback?.(false);
      }
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : 'Unknown error';
      hilog.error(LOG_DOMAIN, LOG_TAG, `Failed to create WebSocket connection: ${errorMsg}`);
      this.isConnected = false;
      this.connectionCallback?.(false);
    }
  }

  private startHeartbeat(): void {
    this.stopHeartbeat(); // Clear any existing timer
    
    const timerId: number = setInterval(() => {
      if (this.isConnected && this.socket) {
        const socket = this.socket as webSocket.WebSocket;
        try {
          // Send a ping/heartbeat message
          const heartbeatMsg = JSON.stringify({ type: 'ping', timestamp: Date.now() });
          socket.send(heartbeatMsg, (err: BusinessError, value: boolean) => {
            if (err) {
              const errorMsg = err?.message || 'Unknown error';
              const errorCode = err?.code || 'N/A';
              hilog.error(LOG_DOMAIN, LOG_TAG, `Error sending heartbeat: ${errorMsg}, code: ${errorCode}`);
            }
          });
        } catch (error) {
          const errorMsg = error instanceof Error ? error.message : 'Unknown error';
          hilog.error(LOG_DOMAIN, LOG_TAG, `Error sending heartbeat: ${errorMsg}`);
        }
      }
    }, 30000);
    
    // Store the timer ID by converting it to number
    this.heartbeatTimer = Number(timerId);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer !== undefined) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = undefined;
    }
  }

  disconnect(): void {
    this.isConnected = false;
    
    // 清除连接超时定时器
    if (this.connectionTimer !== undefined) {
      clearTimeout(this.connectionTimer);
      this.connectionTimer = undefined;
    }
    
    if (this.socket) {
      const socket = this.socket as webSocket.WebSocket;
      try {
        socket.close((err: BusinessError) => {
          if (err) {
            const errorMsg = err?.message || 'Unknown error';
            const errorCode = err?.code || 'N/A';
            hilog.error(LOG_DOMAIN, LOG_TAG, `Error closing WebSocket: ${errorMsg}, code: ${errorCode}`);
          }
        });
      } catch (error) {
        const errorMsg = error instanceof Error ? error.message : 'Unknown error';
        hilog.error(LOG_DOMAIN, LOG_TAG, `Error closing WebSocket: ${errorMsg}`);
      }
      this.socket = null;
    }
    
    this.stopHeartbeat();
    this.reconnectAttempts = 0;
    this.connectionCallback?.(false);
  }

  isSocketConnected(): boolean {
    return this.isConnected;
  }

  send(message: StateUpdateMessage | HeartbeatMessage | string): void {
    if (!this.isConnected || !this.socket) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Cannot send message - WebSocket not connected');
      return;
    }
    
    const socket = this.socket as webSocket.WebSocket;
    try {
      const msgStr = typeof message === 'string' ? message : JSON.stringify(message);
      socket.send(msgStr, (err: BusinessError, value: boolean) => {
        if (err) {
          const errorMsg = err?.message || 'Unknown error';
          const errorCode = err?.code || 'N/A';
          hilog.error(LOG_DOMAIN, LOG_TAG, `Error sending message: ${errorMsg}, code: ${errorCode}`);
          // Check for fatal errors that indicate connection is lost
          if (errorMsg.includes('session is closed') || 
              errorMsg.includes('wsi is nullptr') || 
              errorMsg.includes('Unknown Other Error')) {
            hilog.warn(LOG_DOMAIN, LOG_TAG, 'Fatal WebSocket error detected, forcing disconnect');
            this.isConnected = false;
            this.connectionCallback?.(false);
          }
        }
      });
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : 'Unknown error';
      hilog.error(LOG_DOMAIN, LOG_TAG, `Error sending message: ${errorMsg}`);
    }
  }

  private buildWsUrl(): string | null {
    const wsUrl = ServerConfig.getWebSocketUrl();
    if (!wsUrl) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Cannot build WebSocket URL - server address not configured');
      return null;
    }
    
    hilog.info(LOG_DOMAIN, LOG_TAG, `Built WebSocket URL: ${wsUrl}`);
    return wsUrl;
  }

  updateDeviceGroupState(deviceGroups: DeviceGroup[], message: StateUpdateMessage): DeviceGroup[] {
    const unitId = message.device.unit;
    
    hilog.info(LOG_DOMAIN, LOG_TAG, 
      `updateDeviceGroupState: unitId=${unitId}, state=${message.state}`);
    
    // 双重匹配策略：前缀匹配 + 遍历匹配
    const matchedGroupIndex = this.findMatchingGroupIndex(deviceGroups, unitId);
    
    if (matchedGroupIndex !== -1) {
      const originalGroup = deviceGroups[matchedGroupIndex];
      
      // 创建更新后的单元数组（复制对象以触发响应式更新）
      const updatedUnits = originalGroup.units.map(unit => {
        if (unit.id === unitId) {
          hilog.info(LOG_DOMAIN, LOG_TAG, 
            `  Updating unit ${unit.id} status from ${unit.status} to ${message.state}`);
          // 创建新的单元对象（手动复制属性，ArkTS不支持对象展开）
          const newUnit = new DeviceUnit();
          newUnit.id = unit.id;
          newUnit.name = unit.name;
          newUnit.type = unit.type;
          newUnit.status = message.state;
          return newUnit;
        }
        return unit;
      });
      
      // 更新离线状态：只有control类型的单元变为OFFLINE时，才设置设备组的isOffline为true
      const targetUnit = originalGroup.units.find(unit => unit.id === unitId);
      const isOffline = (message.device.online === false || message.state === 'OFFLINE') && 
                       (targetUnit?.type === 'control');
      
      hilog.info(LOG_DOMAIN, LOG_TAG, 
        `Updated group ${originalGroup.id}, isOffline=${isOffline} (unit type: ${targetUnit?.type})`);
      
      // 创建新的设备组对象以触发响应式更新（手动复制属性，ArkTS不支持对象展开）
      const updatedGroup = new DeviceGroup();
      updatedGroup.id = originalGroup.id;
      updatedGroup.name = originalGroup.name;
      updatedGroup.displayName = originalGroup.displayName;
      updatedGroup.location = originalGroup.location;
      updatedGroup.units = updatedUnits;
      updatedGroup.groupName = originalGroup.groupName;
      updatedGroup.icon = originalGroup.icon;
      updatedGroup.hasControlUnit = originalGroup.hasControlUnit;
      updatedGroup.isOffline = isOffline;
      
      // 创建新数组并替换更新的组
      const newDeviceGroups = [...deviceGroups];
      newDeviceGroups[matchedGroupIndex] = updatedGroup;
      
      return newDeviceGroups;
    } else {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 
        `No matching group found for unitId: ${unitId}`);
    }

    // 返回新数组引用以触发 V2 装饰器响应式更新
    return [...deviceGroups];
  }

  private findMatchingGroupIndex(deviceGroups: DeviceGroup[], unitId: string): number {
    // 策略1：前缀匹配（优先）
    const prefixGroupId = unitId.split('_')[0];
    const prefixIndex = deviceGroups.findIndex(group => group.id === prefixGroupId);
    
    if (prefixIndex !== -1) {
      hilog.debug(LOG_DOMAIN, LOG_TAG, 
        `Found group via prefix matching: ${deviceGroups[prefixIndex].id}`);
      return prefixIndex;
    }
    
    // 策略2：遍历匹配（回退）
    const traversalIndex = deviceGroups.findIndex(group => {
      return group.units.some(unit => unit.id === unitId);
    });
    
    if (traversalIndex !== -1) {
      hilog.debug(LOG_DOMAIN, LOG_TAG, 
        `Found group via traversal matching: ${deviceGroups[traversalIndex].id}`);
      return traversalIndex;
    }
    
    return -1;
  }

  checkGroupOfflineStatus(group: DeviceGroup): boolean {
    const controlUnits = group.units?.filter(unit => unit.type === 'control') || [];
    if (controlUnits.length === 0) {
      return false;
    }
    return controlUnits.some(unit => unit.status === 'OFFLINE');
  }

  private isValidStateUpdateMessage(data: object): boolean {
    if (data === null || typeof data !== 'object') {
      return false;
    }
    
    // Type guard checks for StateUpdateMessage properties
    const typedData = data as Partial<StateUpdateMessage>;
    if (typeof typedData.type !== 'string') {
      return false;
    }
    
    if (!typedData.device) {
      return false;
    }
    
    if (typeof typedData.state !== 'string') {
      return false;
    }
    
    if (typeof typedData.topic !== 'string') {
      return false;
    }
    
    if (typeof typedData.timestamp !== 'string') {
      return false;
    }
    
    return true;
  }

  private validateAsStateUpdateMessage(data: object): StateUpdateMessage | null {
    if (this.isValidStateUpdateMessage(data)) {
      return data as StateUpdateMessage;
    }
    return null;
  }
}