import { ServiceExtensionAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BoreClient, BoreCallback } from '../model/BoreClient';
import { emitter } from '@kit.BasicServicesKit';

const TAG = 'TunnelServiceAbility';

export default class TunnelServiceAbility extends ServiceExtensionAbility {
  private boreClient: BoreClient | null = null;

  onCreate(want: Want): void {
    hilog.info(0x0000, TAG, 'ServiceAbility onCreate');
  }

  onRequest(want: Want, startId: number): void {
    hilog.info(0x0000, TAG, `ServiceAbility onRequest, startId: ${startId}`);

    const localPort = want.parameters?.['local_port'] as number;
    const remoteServer = want.parameters?.['remote_server'] as string;
    const secret = want.parameters?.['secret'] as string;
    const action = want.parameters?.['action'] as string;

    if (action === 'stop') {
      this.stopTunnel();
      return;
    }

    if (!localPort || !remoteServer) {
      this.emitStatus(false, '参数缺失');
      this.stopSelf();
      return;
    }

    this.startTunnel(remoteServer, localPort, secret || '');
  }

  private startTunnel(server: string, port: number, secret: string): void {
    const callback: BoreCallback = {
      onConnected: (publicUrl: string, mcpUrl: string): void => {
        this.emitUrl(publicUrl, mcpUrl);
        hilog.info(0x0000, TAG, `隧道已连接: ${mcpUrl}`);
      },
      onDisconnected: (): void => {
        this.emitLog('[隧道已断开]');
        this.emitStatus(false);
        this.stopSelf();
      },
      onError: (error: string): void => {
        this.emitLog(`[错误] ${error}`);
      },
      onLog: (message: string): void => {
        this.emitLog(message);
      }
    };

    this.boreClient = new BoreClient(server, port, 0, secret, callback);
    this.boreClient.start();
    this.emitStatus(true);
  }

  private stopTunnel(): void {
    if (this.boreClient) {
      this.boreClient.stop();
      this.boreClient = null;
    }
    this.emitStatus(false);
    this.stopSelf();
  }

  private emitStatus(running: boolean, error?: string): void {
    const eventData: emitter.EventData = {
      data: {
        'running': running,
        'error': error || ''
      }
    };
    emitter.emit({ eventId: 0 }, eventData);
  }

  private emitLog(log: string): void {
    const eventData: emitter.EventData = {
      data: { 'log': log }
    };
    emitter.emit({ eventId: 0 }, eventData);
  }

  private emitUrl(publicUrl: string, mcpUrl: string): void {
    const eventData: emitter.EventData = {
      data: {
        'public_url': publicUrl,
        'mcp_url': mcpUrl
      }
    };
    emitter.emit({ eventId: 0 }, eventData);
  }

  private stopSelf(): void {
    const context = this.context;
    context.terminateSelf();
  }

  onDestroy(): void {
    hilog.info(0x0000, TAG, 'ServiceAbility onDestroy');
    if (this.boreClient) {
      this.boreClient.stop();
      this.boreClient = null;
    }
  }
}