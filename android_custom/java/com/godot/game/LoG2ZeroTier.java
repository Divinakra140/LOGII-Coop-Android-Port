package com.godot.game;

import android.util.Log;

import com.zerotier.sockets.ZeroTierEventListener;
import com.zerotier.sockets.ZeroTierNative;
import com.zerotier.sockets.ZeroTierSocket;

import java.io.File;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Embedded ZeroTier node (libzt) for GLOBAL MULTIPLAYER (adapted from the PokeWilds port). No ZeroTier app, account or
 * address entry is needed on the device, and nobody administers a network:
 * the game uses a ZeroTier ad-hoc network, which has no controller, no member
 * list and no member limit. It carries only IPv6 TCP/UDP to the game's port.
 *
 * The game's own transport keeps using ordinary TCP sockets. This class only
 * carries those bytes across the ZeroTier network through loopback:
 *   host:  ZeroTier listener  -> 127.0.0.1:<game port>
 *   guest: 127.0.0.1:<random> -> ZeroTier connection to the host
 * Ad-hoc networks cannot broadcast, so the lobby list comes from the lobby
 * directory service instead (see scripts/online.gd).
 *
 * Every method is static and uses only String/int/boolean so GDScript can call
 * it through JavaClassWrapper, like the other bridges.
 */
public final class LoG2ZeroTier {
    private static final String TAG = "LoG2ZeroTier";
    private static final int EAGAIN = 11;
    private static final int ONLINE_TIMEOUT_MS = 60000;
    private static final int NETWORK_TIMEOUT_MS = 90000;
    private static final int CONNECT_TIMEOUT_MS = 15000;
    private static final int PACE_BYTES = 4096;

    // The game always talks to 127.0.0.1. Android's getLoopbackAddress() is
    // ::1, which a 127.0.0.1 connection cannot reach.
    private static final InetAddress LOOPBACK = loopback();

    private static InetAddress loopback() {
        try {
            return InetAddress.getByAddress(new byte[] {127, 0, 0, 1});
        } catch (Exception impossible) {
            throw new IllegalStateException(impossible);
        }
    }

    private static final Object LOCK = new Object();
    // libzt reports errors through one global value shared by all threads, so
    // socket calls from different threads must not overlap or they read each
    // other's results. Every such call here is non-blocking and takes this lock.
    private static final Object ZT = new Object();

    private static int ztRead(int fd, byte[] buffer) {
        synchronized (ZT) { return ZeroTierNative.zts_bsd_read_length(fd, buffer, buffer.length); }
    }

    private static int ztWrite(int fd, byte[] data) {
        synchronized (ZT) { return ZeroTierNative.zts_bsd_write(fd, data); }
    }

    private static void ztClose(int fd) {
        synchronized (ZT) { ZeroTierNative.zts_bsd_close(fd); }
    }
    private static volatile String state = "stopped";
    private static volatile String address = "";
    private static volatile String message = "";
    private static volatile long networkId = 0;
    private static volatile boolean ready = false;
    private static boolean started = false;

    private static volatile int hostGeneration = 0;
    private static volatile int joinGeneration = 0;
    private static ServerSocket joinListener;
    private static final AtomicInteger links = new AtomicInteger();

    private LoG2ZeroTier() {}

    /** False when this APK was built without the libzt library. */
    public static boolean available() {
        try {
            Class.forName("com.zerotier.sockets.ZeroTierNative");
            return true;
        } catch (Throwable error) {
            Log.w(TAG, "libzt is not available", error);
            return false;
        }
    }

    /**
     * Starts the node once and joins the ad-hoc network that allows only
     * gamePort. Every copy using the same port lands on the same network.
     * Returns "" or an error.
     */
    public static String start(final String storagePath, int gamePort) {
        if (gamePort <= 0 || gamePort > 65535) {
            fail("Invalid multiplayer port.");
            return message;
        }
        // ffSSSSEEEE000000: controller-less network, destination ports SSSS..EEEE.
        final long id = 0xff00000000000000L | ((long) gamePort << 40) | ((long) gamePort << 24);
        synchronized (LOCK) {
            if (started) return "";
            started = true;
        }
        networkId = id;
        state = "starting";
        message = "";
        Thread thread = new Thread(new Runnable() {
            @Override public void run() { bringUp(storagePath, id); }
        }, "log2-zt-start");
        thread.setDaemon(true);
        thread.start();
        return "";
    }

    private static void bringUp(String storagePath, long id) {
        try {
            File storage = new File(storagePath);
            if (!storage.isDirectory() && !storage.mkdirs()) {
                fail("ZeroTier storage could not be created.");
                return;
            }
            ZeroTierNative.zts_init_from_storage(storage.getAbsolutePath());
            ZeroTierNative.zts_init_set_event_handler(new ZeroTierEventListener() {
                @Override public void onZeroTierEvent(long eventId, int code) { onEvent(code); }
            });
            int error = ZeroTierNative.zts_node_start();
            if (error != ZeroTierNative.ZTS_ERR_OK) {
                fail("ZeroTier could not start (" + error + ").");
                return;
            }
            if (!await(ONLINE_TIMEOUT_MS, false)) {
                fail("Could not reach ZeroTier. Check the internet connection.");
                return;
            }
            state = "joining";
            ZeroTierNative.zts_net_join(id);
            if (!await(NETWORK_TIMEOUT_MS, true)) {
                if (!"error".equals(state)) fail("The multiplayer network did not respond.");
                return;
            }
            String assigned = ZeroTierNative.zts_addr_get_str(id, ZeroTierNative.ZTS_AF_INET6);
            if (assigned == null || assigned.isEmpty()) {
                fail("The multiplayer network did not assign an address.");
                return;
            }
            address = assigned;
            message = "";
            state = "ready";
            ready = true;
        } catch (Throwable error) {
            Log.e(TAG, "ZeroTier start failed", error);
            fail("ZeroTier failed to start.");
        }
    }

    private static boolean await(int timeoutMs, boolean network) throws InterruptedException {
        long deadline = System.currentTimeMillis() + timeoutMs;
        while (System.currentTimeMillis() < deadline) {
            if ("error".equals(state)) return false;
            if (network) {
                if (ZeroTierNative.zts_net_transport_is_ready(networkId) == 1
                        && ZeroTierNative.zts_addr_is_assigned(networkId, ZeroTierNative.ZTS_AF_INET6) == 1) return true;
            } else if (ZeroTierNative.zts_node_is_online() == 1) {
                return true;
            }
            Thread.sleep(100);
        }
        return false;
    }

    private static void onEvent(int code) {
        if (code == ZeroTierNative.ZTS_EVENT_NETWORK_NOT_FOUND) fail("The multiplayer network was not found.");
        else if (code == ZeroTierNative.ZTS_EVENT_NETWORK_ACCESS_DENIED) fail("The multiplayer network refused this device.");
        else if (code == ZeroTierNative.ZTS_EVENT_NETWORK_CLIENT_TOO_OLD) fail("This game version is too old for the multiplayer network.");
        else if (code == ZeroTierNative.ZTS_EVENT_NODE_FATAL_ERROR) fail("ZeroTier identity error. Reinstalling resets it.");
    }

    private static void fail(String reason) {
        ready = false;
        message = reason;
        state = "error";
        Log.w(TAG, reason);
    }

    /** "state\taddress\tmessage"; state is stopped, starting, joining, ready or error. */
    public static String status() {
        String note = message;
        // Asked live each time, and asked of the game's own network. The node
        // reports itself "offline" about thirty seconds after starting, which
        // only means it no longer hears ZeroTier's central servers; players
        // stay linked to each other and the game carries on. Showing that as
        // "Reconnecting..." was a false alarm that never went away.
        if (ready && note.isEmpty() && ZeroTierNative.zts_net_transport_is_ready(networkId) != 1) note = "Reconnecting...";
        return state + "\t" + address + "\t" + note;
    }

    private static boolean awaitReady(Generation generation) {
        try {
            while (generation.current() && !ready) {
                if ("error".equals(state)) return false;
                Thread.sleep(100);
            }
        } catch (InterruptedException error) {
            return false;
        }
        return generation.current();
    }

    private interface Generation { boolean current(); }

    // ---------------------------------------------------------------- host

    /** Accept ZeroTier connections on ztPort and forward each to the local game server. */
    public static boolean hostOpen(final int ztPort, final int localPort) {
        final int generation = ++hostGeneration;
        Thread thread = new Thread(new Runnable() {
            @Override public void run() {
                Generation live = new Generation() {
                    @Override public boolean current() { return hostGeneration == generation; }
                };
                if (!awaitReady(live)) return;
                ZeroTierSocket server;
                try {
                    server = new ZeroTierSocket(ZeroTierNative.ZTS_AF_INET6, ZeroTierNative.ZTS_SOCK_STREAM, 0);
                } catch (Exception error) {
                    Log.e(TAG, "host socket failed", error);
                    return;
                }
                int listener = server.getNativeFileDescriptor();
                try {
                    ZeroTierNative.zts_set_reuse_addr(listener, 1);
                    int error = ZeroTierNative.zts_bind(listener, "::", ztPort);
                    if (error < 0) { Log.e(TAG, "host bind failed " + error); return; }
                    server.listen(8);
                    ZeroTierNative.zts_set_blocking(listener, 0);
                    while (live.current()) {
                        int accepted;
                        try {
                            synchronized (ZT) { accepted = server.accept().getNativeFileDescriptor(); }
                        } catch (Exception waiting) {
                            // Nobody is connecting right now.
                            Thread.sleep(25);
                            continue;
                        }
                        if (accepted < 0 || accepted == listener) {
                            // Never treat the listener itself as a player.
                            Thread.sleep(25);
                            continue;
                        }
                        Socket local = new Socket();
                        try {
                            local.connect(new InetSocketAddress(LOOPBACK, localPort), 3000);
                        } catch (Exception refused) {
                            Log.w(TAG, "host: game server on port " + localPort + " refused the forwarded player: " + refused);
                            ztClose(accepted);
                            closeQuietly(local);
                            continue;
                        }
                        Log.i(TAG, "host: player connected over ZeroTier");
                        link("host", local, accepted, live);
                    }
                } catch (Exception stopped) {
                    Log.w(TAG, "host listener stopped", stopped);
                } finally {
                    ztClose(listener);
                }
            }
        }, "log2-zt-host");
        thread.setDaemon(true);
        thread.start();
        return true;
    }

    public static void hostClose() {
        hostGeneration++;
    }

    // --------------------------------------------------------------- guest

    /**
     * Opens a loopback port. A connection made to it is carried to
     * remoteAddress:remotePort on the ZeroTier network. Returns the loopback
     * port, or 0 on failure.
     */
    public static int connectOpen(final String remoteAddress, final int remotePort) {
        connectClose();
        final int generation = ++joinGeneration;
        final ServerSocket listener;
        try {
            listener = new ServerSocket(0, 2, LOOPBACK);
            listener.setSoTimeout(500);
        } catch (Exception error) {
            Log.e(TAG, "loopback listener failed", error);
            return 0;
        }
        synchronized (LOCK) { joinListener = listener; }
        Thread thread = new Thread(new Runnable() {
            @Override public void run() {
                Generation live = new Generation() {
                    @Override public boolean current() { return joinGeneration == generation; }
                };
                try {
                    while (live.current()) {
                        Socket local;
                        try {
                            local = listener.accept();
                        } catch (SocketTimeoutException waiting) {
                            continue;
                        }
                        if (!awaitReady(live)) { closeQuietly(local); break; }
                        Log.i(TAG, "join: connecting to " + remoteAddress + " port " + remotePort);
                        long began = System.currentTimeMillis();
                        int remote = ZeroTierNative.zts_bsd_socket(ZeroTierNative.ZTS_AF_INET6, ZeroTierNative.ZTS_SOCK_STREAM, 0);
                        if (remote < 0) { closeQuietly(local); continue; }
                        int error = ZeroTierNative.zts_connect(remote, remoteAddress, remotePort, CONNECT_TIMEOUT_MS);
                        if (error < 0) {
                            Log.w(TAG, "ZeroTier connect failed " + error);
                            ztClose(remote);
                            closeQuietly(local);
                            continue;
                        }
                        Log.i(TAG, "join: connected after " + (System.currentTimeMillis() - began) + " ms");
                        link("join", local, remote, live);
                    }
                } catch (Exception closed) {
                    // Listener closed by connectClose().
                } finally {
                    try { listener.close(); } catch (Exception ignored) {}
                }
            }
        }, "log2-zt-join");
        thread.setDaemon(true);
        thread.start();
        return listener.getLocalPort();
    }

    public static void connectClose() {
        joinGeneration++;
        synchronized (LOCK) {
            if (joinListener != null) {
                try { joinListener.close(); } catch (Exception ignored) {}
                joinListener = null;
            }
        }
    }

    // ---------------------------------------------------------------- link

    /**
     * One thread owns both ends, so a ZeroTier socket is never used from two
     * threads at once. The ZeroTier side is non-blocking and the loop only
     * pauses (for a millisecond, on the local socket) when neither direction
     * has data, so position updates are passed on as soon as they arrive.
     */
    private static void link(final String role, final Socket local, final int remote, final Generation owner) {
        Thread thread = new Thread(new Runnable() {
            @Override public void run() {
                links.incrementAndGet();
                String ended = "stopped";
                long toRemote = 0;
                long toLocal = 0;
                long reportAt = System.currentTimeMillis() + 10000;
                long reportedRemote = 0;
                long reportedLocal = 0;
                long slowest = 0;
                long lastOut = System.currentTimeMillis();
                long lastIn = lastOut;
                long quietOut = 0;
                long quietIn = 0;
                try {
                    local.setTcpNoDelay(true);
                    local.setSoTimeout(1);
                    ZeroTierNative.zts_set_no_delay(remote, 1);
                    ZeroTierNative.zts_set_blocking(remote, 0);
                    InputStream in = local.getInputStream();
                    OutputStream out = local.getOutputStream();
                    // Small steps with a 1 ms pause between them: a large message
                    // enters ZeroTier over a few hundredths of a second instead of
                    // in one burst, which the network layer otherwise drops parts of.
                    byte[] up = new byte[PACE_BYTES];
                    byte[] down = new byte[32768];
                    while (owner.current()) {
                        long began = System.nanoTime();
                        boolean moved = false;
                        if (in.available() > 0) {
                            int count = in.read(up);
                            if (count < 0) { ended = "game closed its side"; break; }
                            if (count > 0) {
                                long at = System.currentTimeMillis();
                                if (at - lastOut > quietOut) quietOut = at - lastOut;
                                if (!writeAll(remote, up, count)) { ended = "ZeroTier write failed"; break; }
                                lastOut = System.currentTimeMillis();
                                toRemote += count;
                                moved = true;
                                if (in.available() > 0) Thread.sleep(1);
                            }
                        }
                        int received = ztRead(remote, down);
                        if (received > 0) {
                            long at = System.currentTimeMillis();
                            if (at - lastIn > quietIn) quietIn = at - lastIn;
                            lastIn = at;
                            out.write(down, 0, received);
                            toLocal += received;
                            moved = true;
                        }
                        else if (received == 0) { ended = "other player closed the connection"; break; }
                        else if (received != -EAGAIN) { ended = "ZeroTier read error " + received; break; }
                        if (!moved) {
                            // Idle: wait up to 1 ms on the local socket, which also notices it closing.
                            try {
                                int count = in.read(up);
                                if (count < 0) { ended = "game closed its side"; break; }
                                if (count > 0) {
                                    long at = System.currentTimeMillis();
                                    if (at - lastOut > quietOut) quietOut = at - lastOut;
                                    if (!writeAll(remote, up, count)) { ended = "ZeroTier write failed"; break; }
                                    lastOut = System.currentTimeMillis();
                                    toRemote += count;
                                }
                            } catch (SocketTimeoutException idle) {
                                // Nothing to carry this millisecond.
                            }
                        }
                        long took = (System.nanoTime() - began) / 1000000;
                        if (took > slowest) slowest = took;
                        long now = System.currentTimeMillis();
                        if (now >= reportAt) {
                            Log.i(TAG, role + ": last 10s sent " + (toRemote - reportedRemote) / 1024 + " KB, received "
                                    + (toLocal - reportedLocal) / 1024 + " KB, slowest pass " + slowest
                                    + " ms, longest silence: game->net " + quietOut + " ms, net->game " + quietIn + " ms");
                            quietOut = 0;
                            quietIn = 0;
                            reportAt = now + 10000;
                            reportedRemote = toRemote;
                            reportedLocal = toLocal;
                            slowest = 0;
                        }
                    }
                } catch (Exception closed) {
                    ended = "local socket error: " + closed;
                } finally {
                    Log.i(TAG, role + ": link ended (" + ended + "), sent " + toRemote + " bytes, received " + toLocal);
                    closeQuietly(local);
                    ztClose(remote);
                    links.decrementAndGet();
                }
            }
        }, "log2-zt-link");
        thread.setDaemon(true);
        thread.start();
    }

    private static boolean writeAll(int remote, byte[] buffer, int count) throws InterruptedException {
        // libzt's offset write is unreliable; always hand it an exact array.
        byte[] pending = count == buffer.length ? buffer : Arrays.copyOf(buffer, count);
        long deadline = System.currentTimeMillis() + 20000;
        while (pending.length > 0) {
            int written = ztWrite(remote, pending);
            if (written == pending.length) return true;
            if (written > 0) {
                pending = Arrays.copyOfRange(pending, written, pending.length);
            } else if (written == -EAGAIN || written == 0) {
                if (System.currentTimeMillis() > deadline) return false;
                Thread.sleep(1);
            } else {
                return false;
            }
        }
        return true;
    }

    private static void closeQuietly(Socket socket) {
        try { socket.close(); } catch (Exception ignored) {}
    }

    // ------------------------------------------------------ lobby directory

    // The lobby list is fetched here rather than with Godot's HTTPRequest:
    // Godot 4.7 leaks a /dev/urandom handle for every TLS connection it opens.
    private static final ExecutorService HTTP = Executors.newFixedThreadPool(2, runnable -> {
        Thread thread = new Thread(runnable, "log2-lobby-http");
        thread.setDaemon(true);
        return thread;
    });
    private static final ConcurrentHashMap<Integer, String> httpResults = new ConcurrentHashMap<>();
    private static final AtomicInteger httpIds = new AtomicInteger();

    private static volatile String lobbyKey = "";

    /** The lobby list's password for the next httpStart(); "" sends none. */
    public static void setLobbyKey(String key) {
        lobbyKey = key == null ? "" : key;
    }

    /** Starts a GET (empty body) or JSON POST. Returns an id for httpTake(). */
    public static int httpStart(final String address, final String body) {
        final int id = httpIds.incrementAndGet();
        final String key = lobbyKey;
        HTTP.execute(new Runnable() {
            @Override public void run() {
                String result = "0\n";
                HttpURLConnection connection = null;
                try {
                    connection = (HttpURLConnection) new URL(address).openConnection();
                    connection.setConnectTimeout(8000);
                    connection.setReadTimeout(8000);
                    connection.setUseCaches(false);
                    if (!key.isEmpty()) connection.setRequestProperty("X-Lobby-Key", key);
                    if (body != null && !body.isEmpty()) {
                        byte[] data = body.getBytes(StandardCharsets.UTF_8);
                        connection.setRequestMethod("POST");
                        connection.setRequestProperty("Content-Type", "application/json");
                        connection.setDoOutput(true);
                        connection.setFixedLengthStreamingMode(data.length);
                        try (OutputStream out = connection.getOutputStream()) { out.write(data); }
                    }
                    int code = connection.getResponseCode();
                    InputStream stream = code >= 400 ? connection.getErrorStream() : connection.getInputStream();
                    ByteArrayOutputStream text = new ByteArrayOutputStream();
                    if (stream != null) {
                        byte[] buffer = new byte[4096];
                        int count;
                        while ((count = stream.read(buffer)) > 0 && text.size() < 262144) text.write(buffer, 0, count);
                        stream.close();
                    }
                    result = code + "\n" + new String(text.toByteArray(), StandardCharsets.UTF_8);
                } catch (Exception error) {
                    Log.w(TAG, "lobby directory request failed: " + error);
                } finally {
                    if (connection != null) connection.disconnect();
                }
                if (httpResults.size() < 64) httpResults.put(id, result);
            }
        });
        return id;
    }

    /** "" while pending, else "status\nbody" once; status 0 means it failed. */
    public static String httpTake(int id) {
        String result = httpResults.remove(id);
        return result == null ? "" : result;
    }

    public static int linkCount() {
        return links.get();
    }
}
