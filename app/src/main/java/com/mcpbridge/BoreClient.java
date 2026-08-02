package com.mcpbridge;

import android.util.Log;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import kotlin.UByte;
import org.json.JSONObject;
/* loaded from: classes3.dex */
public class BoreClient {
    private static final int CONNECT_TIMEOUT_MS = 5000;
    private static final int CONTROL_PORT = 7835;
    private static final int MAX_FRAME_LENGTH = 256;
    private static final String TAG = "BoreClient";
    private final Callback callback;
    private Socket controlSocket;
    private final int localPort;
    private final int requestedRemotePort;
    private final String secret;
    private final String serverHost;
    private volatile boolean running = false;
    private int assignedRemotePort = 0;
    private final ExecutorService executor = Executors.newCachedThreadPool();

    /* loaded from: classes3.dex */
    public interface Callback {
        void onConnected(String str, String str2);

        void onDisconnected();

        void onError(String str);

        void onLog(String str);
    }

    public BoreClient(String serverHost, int localPort, int requestedRemotePort, String secret, Callback callback) {
        this.serverHost = serverHost;
        this.localPort = localPort;
        this.requestedRemotePort = requestedRemotePort;
        this.secret = secret;
        this.callback = callback;
    }

    public void start() {
        this.running = true;
        this.executor.execute(new Runnable() { // from class: com.mcpbridge.BoreClient$$ExternalSyntheticLambda1
            @Override // java.lang.Runnable
            public final void run() {
                BoreClient.this.runTunnel();
            }
        });
    }

    public void stop() {
        this.running = false;
        if (this.controlSocket != null && !this.controlSocket.isClosed()) {
            try {
                this.controlSocket.close();
            } catch (IOException e) {
                Log.w(TAG, "关闭控制连接: " + e.getMessage());
            }
        }
        this.executor.shutdownNow();
    }

    public boolean isRunning() {
        return this.running;
    }

    public int getAssignedRemotePort() {
        return this.assignedRemotePort;
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void runTunnel() {
        InputStream in;
        String response;
        try {
            try {
                log("连接到 " + this.serverHost + ":" + CONTROL_PORT + " ...");
                this.controlSocket = new Socket();
                this.controlSocket.connect(new InetSocketAddress(this.serverHost, (int) CONTROL_PORT), CONNECT_TIMEOUT_MS);
                this.controlSocket.setKeepAlive(true);
                this.controlSocket.setTcpNoDelay(true);
                log("控制连接已建立");
                in = this.controlSocket.getInputStream();
                OutputStream out = this.controlSocket.getOutputStream();
                if (this.secret != null && !this.secret.isEmpty()) {
                    doAuthHandshake(in, out);
                }
                String helloMsg = "{\"Hello\":" + this.requestedRemotePort + "}";
                sendMessage(out, helloMsg);
                log("已发送 Hello(" + this.requestedRemotePort + ")");
                response = recvMessage(in);
            } catch (Exception e) {
                if (this.running) {
                    error("隧道异常: " + e.getMessage());
                    Log.e(TAG, "隧道异常", e);
                }
            }
            if (response == null) {
                error("服务端关闭了连接");
            } else if (!response.startsWith("{\"Hello")) {
                if (!response.contains("\"Error\"")) {
                    error("意外的响应: " + response);
                    return;
                }
                JSONObject json = new JSONObject(response);
                String errMsg = json.getString("Error");
                error("服务端错误: " + errMsg);
            } else {
                JSONObject json2 = new JSONObject(response);
                this.assignedRemotePort = json2.getInt("Hello");
                String publicUrl = "tcp://" + this.serverHost + ":" + this.assignedRemotePort;
                String mcpUrl = "http://" + this.serverHost + ":" + this.assignedRemotePort + "/mcp";
                log("分配到公网端口: " + this.assignedRemotePort);
                log("监听地址: " + this.serverHost + ":" + this.assignedRemotePort);
                this.callback.onConnected(publicUrl, mcpUrl);
                log("进入监听循环...");
                while (true) {
                    if (!this.running) {
                        break;
                    }
                    String msg = recvMessage(in);
                    if (msg == null) {
                        log("控制连接已断开");
                        break;
                    } else if (msg.equals("\"Heartbeat\"")) {
                        Log.d(TAG, "收到心跳");
                    } else if (msg.startsWith("{\"Connection")) {
                        JSONObject json3 = new JSONObject(msg);
                        String connId = json3.getString("Connection");
                        log("新连接请求: " + connId.substring(0, 8) + "...");
                        handleDataConnection(connId);
                    } else if (msg.contains("\"Error\"")) {
                        JSONObject json4 = new JSONObject(msg);
                        error("服务端错误: " + json4.getString("Error"));
                        break;
                    } else {
                        Log.w(TAG, "未知消息: " + msg);
                    }
                }
            }
        } finally {
            this.running = false;
            this.callback.onDisconnected();
        }
    }

    private void doAuthHandshake(InputStream in, OutputStream out) throws Exception {
        String challengeMsg = recvMessage(in);
        if (challengeMsg == null || !challengeMsg.contains("\"Challenge\"")) {
            throw new IOException("期望 Challenge 消息但收到: " + challengeMsg);
        }
        JSONObject json = new JSONObject(challengeMsg);
        String challengeUuid = json.getString("Challenge");
        log("收到认证挑战");
        String answer = computeHmacAnswer(this.secret, challengeUuid);
        String authMsg = "{\"Authenticate\":\"" + answer + "\"}";
        sendMessage(out, authMsg);
        log("已发送认证响应");
    }

    private static String computeHmacAnswer(String secret, String challengeUuid) throws Exception {
        MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
        byte[] keyBytes = sha256.digest(secret.getBytes(StandardCharsets.UTF_8));
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(keyBytes, "HmacSHA256"));
        UUID uuid = UUID.fromString(challengeUuid);
        byte[] uuidBytes = uuidToBytes(uuid);
        byte[] hmacBytes = mac.doFinal(uuidBytes);
        return bytesToHex(hmacBytes);
    }

    private static byte[] uuidToBytes(UUID uuid) {
        long msb = uuid.getMostSignificantBits();
        long lsb = uuid.getLeastSignificantBits();
        byte[] bytes = new byte[16];
        for (int i = 0; i < 8; i++) {
            bytes[i] = (byte) (msb >>> (56 - (i * 8)));
            bytes[i + 8] = (byte) (lsb >>> (56 - (i * 8)));
        }
        return bytes;
    }

    private static String bytesToHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append(String.format("%02x", Integer.valueOf(b & UByte.MAX_VALUE)));
        }
        return sb.toString();
    }

    private void handleDataConnection(final String connId) {
        this.executor.execute(new Runnable() { // from class: com.mcpbridge.BoreClient$$ExternalSyntheticLambda0
            @Override // java.lang.Runnable
            public final void run() {
                BoreClient.this.m198lambda$handleDataConnection$0$commcpbridgeBoreClient(connId);
            }
        });
    }

    /* JADX INFO: Access modifiers changed from: package-private */
    /* renamed from: lambda$handleDataConnection$0$com-mcpbridge-BoreClient  reason: not valid java name */
    public /* synthetic */ void m198lambda$handleDataConnection$0$commcpbridgeBoreClient(String connId) {
        Socket dataSocket = null;
        Socket localSocket = null;
        try {
            try {
                dataSocket = new Socket();
                dataSocket.connect(new InetSocketAddress(this.serverHost, (int) CONTROL_PORT), CONNECT_TIMEOUT_MS);
                dataSocket.setTcpNoDelay(true);
                if (this.secret != null && !this.secret.isEmpty()) {
                    InputStream din = dataSocket.getInputStream();
                    OutputStream dout = dataSocket.getOutputStream();
                    doAuthHandshake(din, dout);
                }
                String acceptMsg = "{\"Accept\":\"" + connId + "\"}";
                OutputStream out = dataSocket.getOutputStream();
                sendMessage(out, acceptMsg);
                localSocket = new Socket();
                localSocket.connect(new InetSocketAddress("127.0.0.1", this.localPort), CONNECT_TIMEOUT_MS);
                localSocket.setTcpNoDelay(true);
                pipeBidirectional(dataSocket, localSocket);
            } catch (Exception e) {
                Log.w(TAG, "数据连接 " + connId.substring(0, 8) + " 失败: " + e.getMessage());
            }
        } finally {
            closeQuietly(dataSocket);
            closeQuietly(localSocket);
        }
    }

    private void pipeBidirectional(final Socket socket1, final Socket socket2) {
        final AtomicBoolean done = new AtomicBoolean(false);
        this.executor.execute(new Runnable() { // from class: com.mcpbridge.BoreClient$$ExternalSyntheticLambda2
            @Override // java.lang.Runnable
            public final void run() {
                BoreClient.this.m199lambda$pipeBidirectional$1$commcpbridgeBoreClient(socket1, socket2, done);
            }
        });
        try {
            try {
                pipeStreams(socket2.getInputStream(), socket1.getOutputStream());
                if (!done.compareAndSet(false, true)) {
                    return;
                }
            } catch (IOException e) {
                Log.d(TAG, "转发2结束: " + e.getMessage());
                if (!done.compareAndSet(false, true)) {
                    return;
                }
            }
            closeQuietly(socket1);
            closeQuietly(socket2);
        } catch (Throwable th) {
            if (done.compareAndSet(false, true)) {
                closeQuietly(socket1);
                closeQuietly(socket2);
            }
            throw th;
        }
    }

    /* JADX INFO: Access modifiers changed from: package-private */
    /* renamed from: lambda$pipeBidirectional$1$com-mcpbridge-BoreClient  reason: not valid java name */
    public /* synthetic */ void m199lambda$pipeBidirectional$1$commcpbridgeBoreClient(Socket socket1, Socket socket2, AtomicBoolean done) {
        try {
            try {
                pipeStreams(socket1.getInputStream(), socket2.getOutputStream());
                if (!done.compareAndSet(false, true)) {
                    return;
                }
            } catch (IOException e) {
                Log.d(TAG, "转发1结束: " + e.getMessage());
                if (!done.compareAndSet(false, true)) {
                    return;
                }
            }
            closeQuietly(socket1);
            closeQuietly(socket2);
        } catch (Throwable th) {
            if (done.compareAndSet(false, true)) {
                closeQuietly(socket1);
                closeQuietly(socket2);
            }
            throw th;
        }
    }

    private void pipeStreams(InputStream in, OutputStream out) throws IOException {
        int len;
        byte[] buffer = new byte[8192];
        while (this.running && (len = in.read(buffer)) != -1) {
            out.write(buffer, 0, len);
            out.flush();
        }
    }

    private void sendMessage(OutputStream out, String json) throws IOException {
        byte[] data = json.getBytes(StandardCharsets.UTF_8);
        if (data.length > 256) {
            throw new IOException("消息过长: " + data.length + " > 256");
        }
        out.write(data);
        out.write(0);
        out.flush();
    }

    private String recvMessage(InputStream in) throws IOException {
        int b;
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        while (this.running && (b = in.read()) != -1) {
            if (b == 0) {
                return buffer.toString(StandardCharsets.UTF_8.name());
            }
            buffer.write(b);
            if (buffer.size() > 256) {
                throw new IOException("消息超过最大长度 256");
            }
        }
        if (buffer.size() > 0) {
            return buffer.toString(StandardCharsets.UTF_8.name());
        }
        return null;
    }

    private void log(String msg) {
        Log.d(TAG, msg);
        this.callback.onLog(msg);
    }

    private void error(String msg) {
        Log.e(TAG, msg);
        this.callback.onError(msg);
    }

    private static void closeQuietly(Socket socket) {
        if (socket != null && !socket.isClosed()) {
            try {
                socket.close();
            } catch (IOException e) {
            }
        }
    }
}
