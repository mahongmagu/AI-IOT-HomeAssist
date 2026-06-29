import hilog from '@ohos.hilog';

export class ServerConfig {
  private static serverAddress: string = '';
  private static serverPort: number = 3000; // HTTP API port
  private static wsPort: number = 8090; // WebSocket port
  private static wsPath: string = '/'; // WebSocket path
  private static isConfiguredFlag: boolean = false;

  static isConfigured(): boolean {
    // 检查服务器地址是否已配置（非空）
    const isConfigured = ServerConfig.isConfiguredFlag && 
                        ServerConfig.serverAddress !== '' && 
                        ServerConfig.serverAddress !== null && 
                        ServerConfig.serverAddress !== undefined;
    hilog.info(0x0000, 'ServerConfig', 'isConfigured called: flag=%{public}s, address=%{public}s, result=%{public}s', 
      [ServerConfig.isConfiguredFlag.toString(), ServerConfig.serverAddress, isConfigured.toString()]);
    return isConfigured;
  }

  static setServerAddress(address: string, port: number): void {
    // 验证地址和端口
    if (!address || address.trim() === '') {
      hilog.error(0x0000, 'ServerConfig', 'Cannot set empty server address!');
      throw new Error('服务器地址不能为空');
    }
    
    if (port < 1 || port > 65535) {
      hilog.error(0x0000, 'ServerConfig', 'Invalid port number: %{public}d', [port]);
      throw new Error('端口号必须在1-65535之间');
    }
    
    ServerConfig.serverAddress = address;
    ServerConfig.serverPort = port;
    ServerConfig.isConfiguredFlag = true;
    
    // 在实际应用中，这里应该保存到持久化存储
    hilog.info(0x0000, 'ServerConfig', 'Server configured: %{public}s:%{public}d', address, port);
    hilog.info(0x0000, 'ServerConfig', 'isConfiguredFlag set to: %{public}s', [ServerConfig.isConfiguredFlag.toString()]);
  }

  static setWebSocketConfig(wsPort: number, wsPath: string): void {
    ServerConfig.wsPort = wsPort;
    ServerConfig.wsPath = wsPath;
    hilog.info(0x0000, 'ServerConfig', 'WebSocket configured: port=%{public}d, path=%{public}s', wsPort, wsPath);
  }

  static getServerAddress(): string {
    return `${ServerConfig.serverAddress}:${ServerConfig.serverPort}`;
  }

  static getApiBaseUrl(): string {
    // 添加验证，确保服务器地址不为空
    if (!ServerConfig.serverAddress || ServerConfig.serverAddress.trim() === '') {
      hilog.error(0x0000, 'ServerConfig', 'Server address is empty!');
      throw new Error('服务器地址未配置，请先设置服务器地址');
    }
    return `http://${ServerConfig.serverAddress}:${ServerConfig.serverPort}`;
  }

  static getWebSocketUrl(): string | null {
    if (!ServerConfig.serverAddress) {
      return null;
    }
    return `ws://${ServerConfig.serverAddress}:${ServerConfig.wsPort}${ServerConfig.wsPath}`;
  }

  static getWebSocketPort(): number {
    return ServerConfig.wsPort;
  }

  static getWebSocketPath(): string {
    return ServerConfig.wsPath;
  }
}