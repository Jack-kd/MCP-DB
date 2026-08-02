package com.mcpbridge;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import android.util.Log;
import androidx.localbroadcastmanager.content.LocalBroadcastManager;
import com.mcpbridge.BoreClient;
/* loaded from: classes3.dex */
public class TunnelService extends Service {
    public static final String ACTION_LOG = "com.mcpbridge.ACTION_LOG";
    public static final String ACTION_STATUS = "com.mcpbridge.ACTION_STATUS";
    public static final String ACTION_URL = "com.mcpbridge.ACTION_URL";
    private static final String CHANNEL_ID = "mcp_bridge_channel";
    private static final int NOTIFICATION_ID = 1;
    private static final String TAG = "TunnelService";
    private BoreClient boreClient;

    @Override // android.app.Service
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
    }

    @Override // android.app.Service
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) {
            stopSelf();
            return 2;
        }
        startForeground(1, buildNotification("正在初始化隧道..."));
        String localPortStr = intent.getStringExtra("local_port");
        String remoteServer = intent.getStringExtra("remote_server");
        String secret = intent.getStringExtra("secret");
        if (localPortStr == null || remoteServer == null) {
            broadcastStatus(false, "参数缺失");
            stopForeground(1);
            stopSelf();
            return 2;
        }
        try {
            int localPort = Integer.parseInt(localPortStr);
            broadcastStatus(true);
            this.boreClient = new BoreClient(remoteServer, localPort, 0, secret, new BoreClient.Callback() { // from class: com.mcpbridge.TunnelService.1
                @Override // com.mcpbridge.BoreClient.Callback
                public void onConnected(String publicUrl, String mcpUrl) {
                    TunnelService.this.broadcastUrl(publicUrl, mcpUrl);
                    TunnelService.this.updateNotification("运行中: " + mcpUrl);
                }

                @Override // com.mcpbridge.BoreClient.Callback
                public void onLog(String message) {
                    TunnelService.this.broadcastLog(message);
                }

                @Override // com.mcpbridge.BoreClient.Callback
                public void onError(String error) {
                    TunnelService.this.broadcastLog("[错误] " + error);
                }

                @Override // com.mcpbridge.BoreClient.Callback
                public void onDisconnected() {
                    TunnelService.this.broadcastLog("[隧道已断开]");
                    TunnelService.this.broadcastStatus(false);
                    TunnelService.this.stopForeground(1);
                    TunnelService.this.stopSelf();
                }
            });
            this.boreClient.start();
            return 1;
        } catch (NumberFormatException e) {
            broadcastStatus(false, "端口号格式错误");
            stopForeground(1);
            stopSelf();
            return 2;
        }
    }

    @Override // android.app.Service
    public void onDestroy() {
        super.onDestroy();
        if (this.boreClient != null) {
            this.boreClient.stop();
            this.boreClient = null;
        }
    }

    @Override // android.app.Service
    public IBinder onBind(Intent intent) {
        return null;
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void broadcastStatus(boolean isRunning) {
        broadcastStatus(isRunning, null);
    }

    private void broadcastStatus(boolean isRunning, String error) {
        Intent intent = new Intent(ACTION_STATUS);
        intent.putExtra("running", isRunning);
        if (error != null) {
            intent.putExtra("error", error);
        }
        LocalBroadcastManager.getInstance(this).sendBroadcast(intent);
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void broadcastLog(String log) {
        Intent intent = new Intent(ACTION_LOG);
        intent.putExtra("log", log);
        LocalBroadcastManager.getInstance(this).sendBroadcast(intent);
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void broadcastUrl(String publicUrl, String mcpUrl) {
        Intent intent = new Intent(ACTION_URL);
        intent.putExtra("public_url", publicUrl);
        intent.putExtra("mcp_url", mcpUrl);
        LocalBroadcastManager.getInstance(this).sendBroadcast(intent);
    }

    private void createNotificationChannel() {
        NotificationChannel channel = new NotificationChannel(CHANNEL_ID, "MCP Bridge 隧道", 2);
        channel.setDescription("MCP 内网穿透隧道运行状态");
        channel.setShowBadge(false);
        NotificationManager nm = (NotificationManager) getSystemService(NotificationManager.class);
        nm.createNotificationChannel(channel);
    }

    private Notification buildNotification(String text) {
        Intent intent = new Intent(this, MainActivity.class);
        intent.setFlags(603979776);
        PendingIntent pi = PendingIntent.getActivity(this, 0, intent, 201326592);
        Notification.Builder builder = new Notification.Builder(this, CHANNEL_ID);
        return builder.setSmallIcon(17301586).setContentTitle("MCP Bridge").setContentText(text).setContentIntent(pi).setOngoing(true).build();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void updateNotification(String text) {
        try {
            NotificationManager nm = (NotificationManager) getSystemService(NotificationManager.class);
            nm.notify(1, buildNotification(text));
        } catch (Exception e) {
            Log.w(TAG, "更新通知失败: " + e.getMessage());
        }
    }
}
