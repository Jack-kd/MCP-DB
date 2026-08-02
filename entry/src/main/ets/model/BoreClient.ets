import socket from '@ohos.net.socket';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { BusinessError } from '@ohos.base';
import { util } from '@kit.ArkTS';

const TAG = 'BoreClient';
const CONTROL_PORT = 7835;
const CONNECT_TIMEOUT_MS = 5000;
const MAX_FRAME_LENGTH = 256;

export interface BoreCallback {
  onConnected(publicUrl: string, mcpUrl: string): void;
  onDisconnected(): void;
  onError(error: string): void;
  onLog(message: string): void;
}

export class BoreClient {
  private serverHost: string;
  private localPort: number;
  private requestedRemotePort: number;
  private secret: string;
  private callback: BoreCallback;
  private running: boolean = false;
  private assignedRemotePort: number = 0;
  private controlSocket: socket.TCPSocket | null = null;

  constructor(serverHost: string, localPort: number, requestedRemotePort: number,
    secret: string, callback: BoreCallback) {
    this.serverHost = serverHost;
    this.localPort = localPort;
    this.requestedRemotePort = requestedRemotePort;
    this.secret = secret;
    this.callback = callback;
  }

  public start(): void {
    this.running = true;
    this.runTunnel();
  }

  public stop(): void {
    this.running = false;
    if (this.controlSocket) {
      try {
        this.controlSocket.close();
      } catch (e) {
        console.warn(TAG, `关闭控制连接: ${e}`);
      }
      this.controlSocket = null;
    }
  }

  public isRunning(): boolean {
    return this.running;
  }

  public getAssignedRemotePort(): number {
    return this.assignedRemotePort;
  }

  private log(msg: string): void {
    console.info(TAG, msg);
    this.callback.onLog(msg);
  }

  private error(msg: string): void {
    console.error(TAG, msg);
    this.callback.onError(msg);
  }

  private async runTunnel(): Promise<void> {
    let tcp: socket.TCPSocket | null = null;
    try {
      this.log(`连接到 ${this.serverHost}:${CONTROL_PORT} ...`);

      tcp = socket.constructTCPSocketInstance();
      const connectOptions: socket.TCPConnectOptions = {
        address: {
          address: this.serverHost,
          port: CONTROL_PORT
        },
        timeout: CONNECT_TIMEOUT_MS
      };

      await tcp.connect(connectOptions);
      this.controlSocket = tcp;
      this.log('控制连接已建立');

      // 认证握手
      if (this.secret && this.secret.length > 0) {
        await this.doAuthHandshake(tcp);
      }

      // 发送 Hello
      const helloMsg = `{"Hello":${this.requestedRemotePort}}`;
      await this.sendMessage(tcp, helloMsg);
      this.log(`已发送 Hello(${this.requestedRemotePort})`);

      // 接收响应
      const response = await this.recvMessage(tcp);
      if (response === null) {
        this.error('服务端关闭了连接');
        return;
      }

      if (!response.startsWith('{"Hello"')) {
        if (!response.includes('"Error"')) {
          this.error(`意外的响应: ${response}`);
          return;
        }
        try {
          const json = JSON.parse(response);
          const errMsg = json['Error'] as string;
          this.error(`服务端错误: ${errMsg}`);
        } catch (e) {
          this.error(`JSON解析失败: ${e}`);
        }
        return;
      }

      try {
        const json2 = JSON.parse(response);
        this.assignedRemotePort = json2['Hello'] as number;
        const publicUrl = `tcp://${this.serverHost}:${this.assignedRemotePort}`;
        const mcpUrl = `http://${this.serverHost}:${this.assignedRemotePort}/mcp`;
        this.log(`分配到公网端口: ${this.assignedRemotePort}`);
        this.log(`监听地址: ${this.serverHost}:${this.assignedRemotePort}`);
        this.callback.onConnected(publicUrl, mcpUrl);
      } catch (e) {
        this.error(`JSON解析失败: ${e}`);
        return;
      }

      // 监听循环
      this.log('进入监听循环...');
      while (this.running) {
        const msg = await this.recvMessage(tcp);
        if (msg === null) {
          this.log('控制连接已断开');
          break;
        }

        if (msg === '"Heartbeat"') {
          console.debug(TAG, '收到心跳');
        } else if (msg.startsWith('{"Connection"')) {
          try {
            const json3 = JSON.parse(msg);
            const connId = json3['Connection'] as string;
            this.log(`新连接请求: ${connId.substring(0, 8)}...`);
            this.handleDataConnection(connId);
          } catch (e) {
            this.error(`解析连接消息失败: ${e}`);
          }
        } else if (msg.includes('"Error"')) {
          try {
            const json4 = JSON.parse(msg);
            this.error(`服务端错误: ${json4['Error']}`);
          } catch (e) {
            this.error(`解析错误消息失败: ${e}`);
          }
          break;
        } else {
          console.warn(TAG, `未知消息: ${msg}`);
        }
      }
    } catch (e) {
      if (this.running) {
        const err = e as BusinessError;
        this.error(`隧道异常: ${err.message}`);
        console.error(TAG, `隧道异常: ${JSON.stringify(err)}`);
      }
    } finally {
      this.running = false;
      this.callback.onDisconnected();
    }
  }

  private async doAuthHandshake(tcp: socket.TCPSocket): Promise<void> {
    const challengeMsg = await this.recvMessage(tcp);
    if (challengeMsg === null || !challengeMsg.includes('"Challenge"')) {
      throw new Error(`期望 Challenge 消息但收到: ${challengeMsg}`);
    }

    const json = JSON.parse(challengeMsg);
    const challengeUuid = json['Challenge'] as string;
    this.log('收到认证挑战');

    const answer = await this.computeHmacAnswer(this.secret, challengeUuid);
    const authMsg = `{"Authenticate":"${answer}"}`;
    await this.sendMessage(tcp, authMsg);
    this.log('已发送认证响应');
  }

  private async computeHmacAnswer(secret: string, challengeUuid: string): Promise<string> {
    // Step 1: SHA-256 hash of secret to get key bytes (32 bytes)
    const md = cryptoFramework.createMd('SHA256');
    const secretBytes: cryptoFramework.DataBlob = {
      data: this.stringToUint8Array(secret)
    };
    await md.update(secretBytes);
    const hashResult = await md.digest();

    // Step 2: Create HMAC key from the SHA-256 hash result
    const symKeyGenerator = cryptoFramework.createSymKeyGenerator('HMAC');
    const keyData: cryptoFramework.DataBlob = {
      data: hashResult.data
    };
    const symKey = await symKeyGenerator.convertKey(keyData);

    // Step 3: HMAC-SHA256 the UUID bytes
    const mac = cryptoFramework.createMac('HMAC|SHA256');
    await mac.init(symKey);
    const uuidBytes = this.uuidToBytes(challengeUuid);
    const uuidBlob: cryptoFramework.DataBlob = { data: uuidBytes };
    await mac.update(uuidBlob);
    const macDone = await mac.doFinal();

    return this.bytesToHex(macDone.data);
  }

  private uuidToBytes(uuid: string): Uint8Array {
    const hex = uuid.replace(/-/g, '');
    const bytes = new Uint8Array(16);
    for (let i = 0; i < 16; i++) {
      bytes[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
    }
    return bytes;
  }

  private bytesToHex(bytes: Uint8Array): string {
    let hex = '';
    for (let i = 0; i < bytes.length; i++) {
      const byteHex = bytes[i].toString(16).padStart(2, '0');
      hex += byteHex;
    }
    return hex;
  }

  private stringToUint8Array(str: string): Uint8Array {
    const encoder = new util.TextEncoder();
    return encoder.encodeInto(str);
  }

  private async sendMessage(tcp: socket.TCPSocket, json: string): Promise<void> {
    const encoder = new util.TextEncoder();
    const data = encoder.encodeInto(json);
    if (data.length > MAX_FRAME_LENGTH) {
      throw new Error(`消息过长: ${data.length} > ${MAX_FRAME_LENGTH}`);
    }

    // 添加 null 终止符
    const frame = new Uint8Array(data.length + 1);
    frame.set(data, 0);
    frame[data.length] = 0;

    const options: socket.TCPSendOptions = {
      data: frame.buffer as ArrayBuffer,
      encoding: undefined
    };
    await tcp.send(options);
  }

  private async recvMessage(tcp: socket.TCPSocket): Promise<string | null> {
    const buffer: number[] = [];
    const decoder = new util.TextDecoder('utf-8');

    return new Promise<string | null>((resolve, reject) => {
      const messageCallback = (value: socket.SocketMessageInfo): void => {
        const data = new Uint8Array(value.message);
        for (let i = 0; i < data.length; i++) {
          if (data[i] === 0) {
            // 遇到 null 终止符，消息结束
            const msgBytes = new Uint8Array(buffer);
            const msg = decoder.decodeWithStream(msgBytes.buffer as ArrayBuffer, { stream: false });
            buffer.length = 0;
            tcp.off('message');
            resolve(msg);
            return;
          }
          buffer.push(data[i]);
          if (buffer.length > MAX_FRAME_LENGTH) {
            tcp.off('message');
            reject(new Error('消息超过最大长度 256'));
            return;
          }
        }
      };

      const closeCallback = (): void => {
        tcp.off('message');
        tcp.off('close');
        if (buffer.length > 0) {
          const msgBytes = new Uint8Array(buffer);
          const msg = decoder.decodeWithStream(msgBytes.buffer as ArrayBuffer, { stream: false });
          resolve(msg);
        } else {
          resolve(null);
        }
      };

      tcp.on('message', messageCallback);
      tcp.on('close', closeCallback);
    });
  }

  private async handleDataConnection(connId: string): Promise<void> {
    let dataSocket: socket.TCPSocket | null = null;
    let localSocket: socket.TCPSocket | null = null;
    try {
      // 连接数据通道
      dataSocket = socket.constructTCPSocketInstance();
      await dataSocket.connect({
        address: { address: this.serverHost, port: CONTROL_PORT },
        timeout: CONNECT_TIMEOUT_MS
      });

      // 认证
      if (this.secret && this.secret.length > 0) {
        await this.doAuthHandshake(dataSocket);
      }

      // 发送 Accept
      const acceptMsg = `{"Accept":"${connId}"}`;
      await this.sendMessage(dataSocket, acceptMsg);

      // 连接本地端口
      localSocket = socket.constructTCPSocketInstance();
      await localSocket.connect({
        address: { address: '127.0.0.1', port: this.localPort },
        timeout: CONNECT_TIMEOUT_MS
      });

      // 双向数据转发
      this.pipeBidirectional(dataSocket, localSocket);
    } catch (e) {
      console.warn(TAG, `数据连接 ${connId.substring(0, 8)} 失败: ${e}`);
      this.closeQuietly(dataSocket);
      this.closeQuietly(localSocket);
    }
  }

  private pipeBidirectional(socket1: socket.TCPSocket, socket2: socket.TCPSocket): void {
    // 方向 1: socket1 -> socket2
    this.pipeStreams(socket1, socket2);

    // 方向 2: socket2 -> socket1
    this.pipeStreams(socket2, socket1);
  }

  private pipeStreams(src: socket.TCPSocket, dst: socket.TCPSocket): void {
    src.on('message', (value: socket.SocketMessageInfo) => {
      const sendOptions: socket.TCPSendOptions = {
        data: value.message,
        encoding: undefined
      };
      dst.send(sendOptions).catch((e: BusinessError) => {
        console.debug(TAG, `转发结束: ${e.message}`);
        this.closeQuietly(src);
        this.closeQuietly(dst);
      });
    });

    src.on('close', () => {
      this.closeQuietly(dst);
    });
  }

  private closeQuietly(sock: socket.TCPSocket | null): void {
    if (sock) {
      try {
        sock.close();
      } catch (e) {
        // 忽略关闭错误
      }
    }
  }
}