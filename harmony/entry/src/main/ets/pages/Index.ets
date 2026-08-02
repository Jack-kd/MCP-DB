import { BoreClient, BoreCallback } from '../model/BoreClient';
import { preferences } from '@kit.ArkData';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction, router } from '@kit.ArkUI';
import { emitter } from '@kit.BasicServicesKit';

const PREF_NAME = 'mcp_bridge';

@Entry
@Component
struct Index {
  @State localPort: string = '8787';
  @State remoteServer: string = 'bore.pub';
  @State secret: string = '';
  @State isRunning: boolean = false;
  @State publicUrl: string = '等待连接…';
  @State mcpUrl: string = '等待连接…';
  @State logText: string = '';
  @State statusText: string = '已停止';
  @State statusColor: string = '#FF3B30';
  @State statusDotColor: string = '#FF3B30';
  @State btnStartEnabled: boolean = true;
  @State btnStopEnabled: boolean = false;
  @State btnCopyEnabled: boolean = false;
  @State btnStartOpacity: number = 1.0;
  @State btnStopOpacity: number = 0.5;

  private boreClient: BoreClient | null = null;
  private dataPrefs: preferences.Preferences | null = null;

  async aboutToAppear(): Promise<void> {
    // 加载保存的配置
    try {
      this.dataPrefs = await preferences.getPreferences(getContext(), PREF_NAME);
      this.localPort = await this.dataPrefs.get('local_port', '8787') as string;
      this.remoteServer = await this.dataPrefs.get('remote_server', 'bore.pub') as string;
      this.secret = await this.dataPrefs.get('secret', '') as string;
    } catch (e) {
      console.warn('MCPBridge', `加载配置失败: ${e}`);
    }

    // 监听隧道事件
    emitter.on('tunnel_status', (data: emitter.EventData) => {
      const event = data.data as Record<string, Object>;
      this.isRunning = event['running'] as boolean;
      this.updateUIForRunning(this.isRunning);
      const error = event['error'] as string;
      if (!this.isRunning && error) {
        this.logText += `[错误] ${error}\n`;
      }
    });

    emitter.on('tunnel_log', (data: emitter.EventData) => {
      const event = data.data as Record<string, Object>;
      const log = event['log'] as string;
      if (log) {
        this.logText += log + '\n';
      }
    });

    emitter.on('tunnel_url', (data: emitter.EventData) => {
      const event = data.data as Record<string, Object>;
      const publicUrl = event['public_url'] as string;
      const mcpUrl = event['mcp_url'] as string;
      if (publicUrl) {
        this.publicUrl = publicUrl;
      }
      if (mcpUrl) {
        this.mcpUrl = mcpUrl;
        this.btnCopyEnabled = true;
      }
      this.updateUIForRunning(true);
    });
  }

  aboutToDisappear(): void {
    emitter.off('tunnel_status');
    emitter.off('tunnel_log');
    emitter.off('tunnel_url');
    if (this.boreClient) {
      this.boreClient.stop();
      this.boreClient = null;
    }
  }

  updateUIForRunning(running: boolean): void {
    if (running) {
      this.btnStartEnabled = false;
      this.btnStopEnabled = true;
      this.btnStartOpacity = 0.5;
      this.btnStopOpacity = 1.0;
      this.statusText = '运行中';
      this.statusColor = '#34C759';
      this.statusDotColor = '#34C759';
    } else {
      this.btnStartEnabled = true;
      this.btnStopEnabled = false;
      this.btnStartOpacity = 1.0;
      this.btnStopOpacity = 0.5;
      this.statusText = '已停止';
      this.statusColor = '#FF3B30';
      this.statusDotColor = '#FF3B30';
      this.publicUrl = '等待连接…';
      this.mcpUrl = '等待连接…';
      this.btnCopyEnabled = false;
    }
  }

  async startTunnel(): Promise<void> {
    if (!this.localPort || this.localPort.trim().length === 0) {
      promptAction.showToast({ message: '请输入本地端口号', duration: 2000 });
      return;
    }
    if (!this.remoteServer || this.remoteServer.trim().length === 0) {
      promptAction.showToast({ message: '请输入远程服务器地址', duration: 2000 });
      return;
    }

    // 保存配置
    try {
      if (this.dataPrefs) {
        await this.dataPrefs.put('local_port', this.localPort.trim());
        await this.dataPrefs.put('remote_server', this.remoteServer.trim());
        await this.dataPrefs.put('secret', this.secret.trim());
        await this.dataPrefs.flush();
      }
    } catch (e) {
      console.warn('MCPBridge', `保存配置失败: ${e}`);
    }

    this.logText = '';

    const localPortNum = parseInt(this.localPort.trim());
    const callback: BoreCallback = {
      onConnected: (publicUrl: string, mcpUrl: string): void => {
        const eventData: emitter.EventData = {
          data: {
            'public_url': publicUrl,
            'mcp_url': mcpUrl
          }
        };
        emitter.emit({ eventId: 0 }, eventData);
      },
      onDisconnected: (): void => {
        this.logText += '[隧道已断开]\n';
        const eventData: emitter.EventData = {
          data: { 'running': false }
        };
        emitter.emit({ eventId: 0 }, eventData);
      },
      onError: (error: string): void => {
        this.logText += `[错误] ${error}\n`;
      },
      onLog: (message: string): void => {
        const eventData: emitter.EventData = {
          data: { 'log': message }
        };
        emitter.emit({ eventId: 0 }, eventData);
      }
    };

    this.boreClient = new BoreClient(
      this.remoteServer.trim(),
      localPortNum,
      0,
      this.secret.trim(),
      callback
    );
    this.boreClient.start();
    this.updateUIForRunning(true);
  }

  stopTunnel(): void {
    if (this.boreClient) {
      this.boreClient.stop();
      this.boreClient = null;
    }
    this.updateUIForRunning(false);
  }

  copyMcpUrl(): void {
    if (this.mcpUrl.startsWith('http')) {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.mcpUrl);
      const pasteboardSystem = pasteboard.getSystemPasteboard();
      pasteboardSystem.setData(pasteData, (err) => {
        if (err) {
          promptAction.showToast({ message: '复制失败', duration: 2000 });
        } else {
          promptAction.showToast({ message: '已复制到剪贴板', duration: 2000 });
        }
      });
    }
  }

  build() {
    Scroll() {
      Column() {
        // 标题区域
        this.buildHeader();

        // 状态卡片
        this.buildSectionHeader('状态');
        this.buildStatusCard();

        // 配置卡片
        this.buildSectionHeader('隧道配置');
        this.buildConfigCard();

        // 按钮
        this.buildButtons();

        // 连接地址卡片
        this.buildSectionHeader('连接地址');
        this.buildUrlCard();

        // 运行日志
        this.buildSectionHeader('运行日志');
        this.buildLogArea();

        // 使用说明
        this.buildInstructions();
      }
      .width('100%')
      .padding({ top: 12, bottom: 40, left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F2F2F7')
    .scrollBar(BarState.Off)
  }

  @Builder
  buildHeader() {
    Row() {
      Stack() {
        Row()
          .width(56)
          .height(56)
          .borderRadius(14)
          .backgroundColor('#FFFFFF')
          .shadow({ radius: 8, color: '#10000000', offsetY: 2 });

        Text('🔗')
          .fontSize(26)
          .width(56)
          .height(56)
          .textAlign(TextAlign.Center)
      }
      .margin({ right: 14 })

      Column() {
        Text('MCP Bridge')
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor('#000000')

        Text('MT管理器 MCP 内网穿透')
          .fontSize(15)
          .fontColor('#8E8E93')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: 20 })
  }

  @Builder
  buildSectionHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor('#8E8E93')
      .letterSpacing(0.02)
      .width('100%')
      .margin({ bottom: 6, left: 16 })
  }

  @Builder
  buildStatusCard() {
    Column() {
      Row() {
        Circle({ width: 10, height: 10 })
          .fill(this.statusDotColor)

        Text(this.statusText)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.statusColor)
          .layoutWeight(1)
          .margin({ left: 10 })

        Text('●')
          .fontSize(20)
          .fontColor('#C7C7CC')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
    .margin({ bottom: 24 })
  }

  @Builder
  buildConfigCard() {
    Column() {
      // 本地端口
      Column() {
        Text('本地端口')
          .fontSize(13)
          .fontColor('#8E8E93')
          .width('100%')
          .margin({ top: 14, bottom: 6 })

        TextInput({ text: this.localPort, placeholder: '8787' })
          .fontSize(16)
          .fontColor('#000000')
          .height(40)
          .type(InputType.Number)
          .maxLength(5)
          .backgroundColor('#F2F2F7')
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .onChange((value: string) => {
            this.localPort = value;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Divider()
        .color('#E5E5EA')
        .strokeWidth(0.5)
        .margin({ left: 16, top: 12, bottom: 12 })

      // 远程服务器
      Column() {
        Text('远程服务器')
          .fontSize(13)
          .fontColor('#8E8E93')
          .width('100%')
          .margin({ bottom: 6 })

        TextInput({ text: this.remoteServer, placeholder: 'bore.pub' })
          .fontSize(16)
          .fontColor('#000000')
          .height(40)
          .type(InputType.Normal)
          .backgroundColor('#F2F2F7')
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .onChange((value: string) => {
            this.remoteServer = value;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Divider()
        .color('#E5E5EA')
        .strokeWidth(0.5)
        .margin({ left: 16, top: 12, bottom: 12 })

      // 认证密钥
      Column() {
        Text('认证密钥')
          .fontSize(13)
          .fontColor('#8E8E93')
          .width('100%')
          .margin({ bottom: 6 })

        TextInput({ text: this.secret, placeholder: '公共服务器留空' })
          .fontSize(16)
          .fontColor('#000000')
          .height(40)
          .type(InputType.Password)
          .backgroundColor('#F2F2F7')
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .placeholderColor('#C7C7CC')
          .onChange((value: string) => {
            this.secret = value;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 14 })
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
    .margin({ bottom: 24 })
  }

  @Builder
  buildButtons() {
    Column() {
      Button('启动隧道')
        .width('100%')
        .height(50)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .backgroundColor('#007AFF')
        .borderRadius(14)
        .enabled(this.btnStartEnabled)
        .opacity(this.btnStartOpacity)
        .onClick(() => {
          this.startTunnel();
        })

      Button('停止隧道')
        .width('100%')
        .height(50)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FF3B30')
        .backgroundColor('#FFFFFF')
        .borderRadius(14)
        .border({ width: 1, color: '#C6C6C8' })
        .enabled(this.btnStopEnabled)
        .opacity(this.btnStopOpacity)
        .margin({ top: 10, bottom: 24 })
        .onClick(() => {
          this.stopTunnel();
        })
    }
    .width('100%')
  }

  @Builder
  buildUrlCard() {
    Column() {
      // 公网地址
      Text('公网地址')
        .fontSize(13)
        .fontColor('#8E8E93')
        .width('100%')
        .margin({ bottom: 4 })

      Text(this.publicUrl)
        .fontSize(15)
        .fontColor('#007AFF')
        .fontFamily('monospace')
        .width('100%')
        .margin({ bottom: 14 })
        .copyOption(CopyOptions.LocalDevice)

      Divider()
        .color('#E5E5EA')
        .strokeWidth(0.5)
        .margin({ bottom: 14 })

      // MCP 连接地址
      Text('MCP 连接地址')
        .fontSize(13)
        .fontColor('#8E8E93')
        .width('100%')
        .margin({ bottom: 4 })

      Text(this.mcpUrl)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#34C759')
        .fontFamily('monospace')
        .width('100%')
        .padding(12)
        .backgroundColor('#F2F2F7')
        .borderRadius(8)
        .margin({ bottom: 14 })
        .copyOption(CopyOptions.LocalDevice)

      Button('复制 MCP 地址')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .backgroundColor('#007AFF')
        .borderRadius(14)
        .enabled(this.btnCopyEnabled)
        .onClick(() => {
          this.copyMcpUrl();
        })
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
    .margin({ bottom: 24 })
  }

  @Builder
  buildLogArea() {
    Text(this.logText || '等待启动…')
      .fontSize(12)
      .fontColor('#98FB98')
      .fontFamily('monospace')
      .width('100%')
      .height(200)
      .padding(14)
      .backgroundColor('#1C1C1E')
      .borderRadius(10)
      .textAlign(TextAlign.Start)
      .copyOption(CopyOptions.LocalDevice)
  }

  @Builder
  buildInstructions() {
    Text('使用步骤\n1. 在 MT管理器中启动 APK MCP 服务\n2. 记住端口号（默认 8787）\n3. 点击「启动隧道」\n4. 复制 MCP 地址，粘贴到 iMa Copilot 中连接\n5. 保持本应用后台运行\n\n本应用纯 ArkTS 实现 bore 协议，无需 Termux 或外部二进制')
      .fontSize(13)
      .fontColor('#8E8E93')
      .width('100%')
      .lineHeight(20)
      .margin({ top: 20, left: 8, right: 8 })
  }
}