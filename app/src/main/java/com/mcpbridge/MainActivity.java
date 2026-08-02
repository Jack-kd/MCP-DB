package com.mcpbridge;

import android.content.BroadcastReceiver;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.text.method.LinkMovementMethod;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import androidx.localbroadcastmanager.content.LocalBroadcastManager;
/* loaded from: classes3.dex */
public class MainActivity extends AppCompatActivity {
    private static final int REQUEST_NOTIFICATION = 1001;
    private Button btnCopy;
    private Button btnStart;
    private Button btnStop;
    private EditText etLocalPort;
    private EditText etRemoteServer;
    private EditText etSecret;
    private SharedPreferences prefs;
    private View statusDot;
    private TunnelReceiver tunnelReceiver;
    private TextView tvLog;
    private TextView tvMcpUrl;
    private TextView tvPublicUrl;
    private TextView tvStatus;

    /* JADX INFO: Access modifiers changed from: protected */
    @Override // androidx.fragment.app.FragmentActivity, androidx.activity.ComponentActivity, androidx.core.app.ComponentActivity, android.app.Activity
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        this.prefs = getSharedPreferences("mcp_bridge", 0);
        this.etLocalPort = (EditText) findViewById(R.id.et_local_port);
        this.etRemoteServer = (EditText) findViewById(R.id.et_remote_server);
        this.etSecret = (EditText) findViewById(R.id.et_secret);
        this.btnStart = (Button) findViewById(R.id.btn_start);
        this.btnStop = (Button) findViewById(R.id.btn_stop);
        this.btnCopy = (Button) findViewById(R.id.btn_copy);
        this.tvStatus = (TextView) findViewById(R.id.tv_status);
        this.tvPublicUrl = (TextView) findViewById(R.id.tv_public_url);
        this.tvMcpUrl = (TextView) findViewById(R.id.tv_mcp_url);
        this.tvLog = (TextView) findViewById(R.id.tv_log);
        this.statusDot = findViewById(R.id.status_dot);
        this.tvPublicUrl.setMovementMethod(LinkMovementMethod.getInstance());
        this.tvMcpUrl.setMovementMethod(LinkMovementMethod.getInstance());
        this.etLocalPort.setText(this.prefs.getString("local_port", "8787"));
        this.etRemoteServer.setText(this.prefs.getString("remote_server", "bore.pub"));
        this.etSecret.setText(this.prefs.getString("secret", ""));
        this.btnStart.setOnClickListener(new View.OnClickListener() { // from class: com.mcpbridge.MainActivity$$ExternalSyntheticLambda0
            @Override // android.view.View.OnClickListener
            public final void onClick(View view) {
                MainActivity.this.m205lambda$onCreate$0$commcpbridgeMainActivity(view);
            }
        });
        this.btnStop.setOnClickListener(new View.OnClickListener() { // from class: com.mcpbridge.MainActivity$$ExternalSyntheticLambda1
            @Override // android.view.View.OnClickListener
            public final void onClick(View view) {
                MainActivity.this.m206lambda$onCreate$1$commcpbridgeMainActivity(view);
            }
        });
        this.btnCopy.setOnClickListener(new View.OnClickListener() { // from class: com.mcpbridge.MainActivity$$ExternalSyntheticLambda2
            @Override // android.view.View.OnClickListener
            public final void onClick(View view) {
                MainActivity.this.m207lambda$onCreate$2$commcpbridgeMainActivity(view);
            }
        });
        updateUI(false);
    }

    /* JADX INFO: Access modifiers changed from: package-private */
    /* renamed from: lambda$onCreate$0$com-mcpbridge-MainActivity  reason: not valid java name */
    public /* synthetic */ void m205lambda$onCreate$0$commcpbridgeMainActivity(View v) {
        startTunnel();
    }

    /* JADX INFO: Access modifiers changed from: package-private */
    /* renamed from: lambda$onCreate$1$com-mcpbridge-MainActivity  reason: not valid java name */
    public /* synthetic */ void m206lambda$onCreate$1$commcpbridgeMainActivity(View v) {
        stopTunnel();
    }

    /* JADX INFO: Access modifiers changed from: package-private */
    /* renamed from: lambda$onCreate$2$com-mcpbridge-MainActivity  reason: not valid java name */
    public /* synthetic */ void m207lambda$onCreate$2$commcpbridgeMainActivity(View v) {
        copyMcpUrl();
    }

    /* JADX INFO: Access modifiers changed from: protected */
    @Override // androidx.fragment.app.FragmentActivity, android.app.Activity
    public void onResume() {
        super.onResume();
        this.tunnelReceiver = new TunnelReceiver();
        IntentFilter filter = new IntentFilter();
        filter.addAction(TunnelService.ACTION_STATUS);
        filter.addAction(TunnelService.ACTION_LOG);
        filter.addAction(TunnelService.ACTION_URL);
        LocalBroadcastManager.getInstance(this).registerReceiver(this.tunnelReceiver, filter);
    }

    /* JADX INFO: Access modifiers changed from: protected */
    @Override // androidx.fragment.app.FragmentActivity, android.app.Activity
    public void onPause() {
        super.onPause();
        if (this.tunnelReceiver != null) {
            LocalBroadcastManager.getInstance(this).unregisterReceiver(this.tunnelReceiver);
            this.tunnelReceiver = null;
        }
    }

    private void startTunnel() {
        String port = this.etLocalPort.getText().toString().trim();
        String server = this.etRemoteServer.getText().toString().trim();
        String secret = this.etSecret.getText().toString().trim();
        if (port.isEmpty()) {
            Toast.makeText(this, "请输入本地端口号", 0).show();
        } else if (server.isEmpty()) {
            Toast.makeText(this, "请输入远程服务器地址", 0).show();
        } else {
            this.prefs.edit().putString("local_port", port).putString("remote_server", server).putString("secret", secret).apply();
            this.tvLog.setText("");
            Intent intent = new Intent(this, TunnelService.class);
            intent.putExtra("local_port", port);
            intent.putExtra("remote_server", server);
            intent.putExtra("secret", secret);
            startForegroundService(intent);
        }
    }

    private void stopTunnel() {
        Intent intent = new Intent(this, TunnelService.class);
        stopService(intent);
        updateUI(false);
    }

    private void copyMcpUrl() {
        String url = this.tvMcpUrl.getText().toString();
        if (url.startsWith("http")) {
            ClipboardManager clipboard = (ClipboardManager) getSystemService("clipboard");
            ClipData clip = ClipData.newPlainText("MCP URL", url);
            clipboard.setPrimaryClip(clip);
            Toast.makeText(this, "已复制到剪贴板", 0).show();
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void updateUI(boolean running) {
        if (running) {
            this.btnStart.setEnabled(false);
            this.btnStop.setEnabled(true);
            this.btnStart.setAlpha(0.5f);
            this.btnStop.setAlpha(1.0f);
            this.tvStatus.setText("运行中");
            this.tvStatus.setTextColor(getColor(R.color.ios_green));
            this.statusDot.setBackgroundResource(R.drawable.status_dot_green);
            return;
        }
        this.btnStart.setEnabled(true);
        this.btnStop.setEnabled(false);
        this.btnStart.setAlpha(1.0f);
        this.btnStop.setAlpha(0.5f);
        this.tvStatus.setText("已停止");
        this.tvStatus.setTextColor(getColor(R.color.ios_red));
        this.statusDot.setBackgroundResource(R.drawable.status_dot_red);
        this.tvPublicUrl.setText("等待连接…");
        this.tvMcpUrl.setText("等待连接…");
        this.btnCopy.setEnabled(false);
    }

    /* loaded from: classes3.dex */
    private class TunnelReceiver extends BroadcastReceiver {
        private TunnelReceiver() {
        }

        @Override // android.content.BroadcastReceiver
        public void onReceive(Context context, Intent intent) {
            String error;
            String action = intent.getAction();
            if (TunnelService.ACTION_STATUS.equals(action)) {
                boolean isRunning = intent.getBooleanExtra("running", false);
                MainActivity.this.updateUI(isRunning);
                if (!isRunning && (error = intent.getStringExtra("error")) != null) {
                    MainActivity.this.tvLog.append("[错误] " + error + "\n");
                }
            } else if (TunnelService.ACTION_LOG.equals(action)) {
                String log = intent.getStringExtra("log");
                if (log != null) {
                    MainActivity.this.tvLog.append(log + "\n");
                    try {
                        int scrollAmount = MainActivity.this.tvLog.getLayout().getLineTop(MainActivity.this.tvLog.getLineCount()) - MainActivity.this.tvLog.getHeight();
                        if (scrollAmount > 0) {
                            MainActivity.this.tvLog.scrollTo(0, scrollAmount);
                        }
                    } catch (NullPointerException e) {
                    }
                }
            } else if (TunnelService.ACTION_URL.equals(action)) {
                String publicUrl = intent.getStringExtra("public_url");
                String mcpUrl = intent.getStringExtra("mcp_url");
                if (publicUrl != null) {
                    MainActivity.this.tvPublicUrl.setText(publicUrl);
                }
                if (mcpUrl != null) {
                    MainActivity.this.tvMcpUrl.setText(mcpUrl);
                    MainActivity.this.btnCopy.setEnabled(true);
                }
                MainActivity.this.updateUI(true);
            }
        }
    }
}
