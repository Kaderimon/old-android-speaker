package com.w200.nowplaying;

import android.app.Activity;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.SystemClock;
import android.text.TextUtils;
import android.util.Base64;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.URL;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Random;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;

/**
 * W200 home screen: a lock-screen style clock plus "now playing" for the two receivers.
 *  - Spotify: Soloist's local WebSocket API (ws://127.0.0.1:47123)
 *  - AirPlay: shairport-sync's metadata pipe (/data/local/tmp/w200/shairport-metadata)
 * The touchscreen is broken, so there is nothing to tap; it only displays.
 */
public class NowPlaying extends Activity {
    static final String WS_HOST = "127.0.0.1";
    static final int WS_PORT = 47123;
    static final String META_PIPE = "/data/local/tmp/w200/shairport-metadata";

    static final int SPOTIFY_GREEN = 0xFF1DB954;
    static final int AIRPLAY_BLUE = 0xFF4DA3FF;

    /** Everything we know about what one source is playing (UI thread only). */
    static class Track {
        String title = "", artist = "", album = "", from = "";
        String artKey;          // cover URL (Spotify) or "pict" counter (AirPlay)
        Bitmap art;
        long durMs, posMs, anchor;  // position posMs at SystemClock.elapsedRealtime() == anchor
        float speed;
        boolean active, playing;
        long changed;           // elapsedRealtime of the last play/pause change
        long position() {
            long p = posMs + (playing ? (long) ((SystemClock.elapsedRealtime() - anchor) * speed) : 0);
            if (durMs > 0 && p > durMs) p = durMs;
            return Math.max(0, p);
        }
    }

    final Track spotify = new Track();
    final Track airplay = new Track();
    Handler ui;
    TextView clock, date, title, artist, album, source, times, idle;
    ImageView art;
    ProgressView progress;
    LinearLayout column, nowBox;
    boolean keepOn;
    Track shown;
    final Random rnd = new Random();
    long lastShift;
    volatile OutputStream wsOut;

    // ------------------------------------------------------------------ UI

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        ui = new Handler();
        Window w = getWindow();
        w.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN
                | WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED);

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);

        column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        column.setGravity(Gravity.CENTER_HORIZONTAL);
        column.setPadding(dp(24), dp(20), dp(24), dp(16));

        Typeface light = Typeface.create("sans-serif-light", Typeface.NORMAL);
        clock = text(76, Color.WHITE, light);
        date = text(19, 0xFFAAAAAA, light);
        column.addView(clock);
        column.addView(date);

        nowBox = new LinearLayout(this);
        nowBox.setOrientation(LinearLayout.VERTICAL);
        nowBox.setGravity(Gravity.CENTER_HORIZONTAL);
        LinearLayout.LayoutParams nbp = new LinearLayout.LayoutParams(-1, -2);
        nbp.topMargin = dp(20);
        column.addView(nowBox, nbp);

        art = new ImageView(this);
        art.setScaleType(ImageView.ScaleType.CENTER_CROP);
        art.setBackgroundColor(0xFF161616);
        nowBox.addView(art, new LinearLayout.LayoutParams(dp(220), dp(220)));

        title = text(22, Color.WHITE, Typeface.DEFAULT_BOLD);
        artist = text(18, 0xFFCCCCCC, null);
        album = text(15, 0xFF888888, null);
        artist.setMaxLines(1);
        album.setMaxLines(1);
        LinearLayout.LayoutParams tp = new LinearLayout.LayoutParams(-1, -2);
        tp.topMargin = dp(14);
        nowBox.addView(title, tp);
        nowBox.addView(artist);
        nowBox.addView(album);

        progress = new ProgressView(this);
        LinearLayout.LayoutParams pp = new LinearLayout.LayoutParams(-1, dp(4));
        pp.topMargin = dp(16);
        nowBox.addView(progress, pp);
        times = text(13, 0xFF888888, null);
        nowBox.addView(times);
        source = text(16, SPOTIFY_GREEN, null);
        source.setMaxLines(1);
        LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(-1, -2);
        sp.topMargin = dp(10);
        nowBox.addView(source, sp);

        idle = text(18, 0xFF666666, light);
        idle.setText("Ready for AirPlay & Spotify\n“W200”");
        LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(-1, -2);
        ip.topMargin = dp(80);
        column.addView(idle, ip);

        root.addView(column, new FrameLayout.LayoutParams(-1, -1));
        setContentView(root);

        render();
        ui.post(tick);
        startThread("spotify-ws", new Runnable() { public void run() { spotifyLoop(); } });
        startThread("airplay-meta", new Runnable() { public void run() { airplayLoop(); } });
    }

    TextView text(float sp, int color, Typeface tf) {
        TextView t = new TextView(this);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(color);
        t.setGravity(Gravity.CENTER_HORIZONTAL);
        t.setSingleLine(false);
        t.setMaxLines(2);
        t.setEllipsize(TextUtils.TruncateAt.END);
        if (tf != null) t.setTypeface(tf);
        return t;
    }

    int dp(float v) { return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics()); }

    final Runnable tick = new Runnable() {
        public void run() {
            Date now = new Date();
            boolean h24 = android.text.format.DateFormat.is24HourFormat(NowPlaying.this);
            clock.setText(new SimpleDateFormat(h24 ? "HH:mm" : "h:mm").format(now));
            date.setText(android.text.format.DateFormat.format("EEEE, d MMMM", now));
            renderProgress();
            // anti burn-in: move everything a few pixels once a minute
            long t = SystemClock.elapsedRealtime();
            if (t - lastShift > 60000) {
                lastShift = t;
                column.setTranslationX(rnd.nextInt(dp(16) + 1) - dp(8));
                column.setTranslationY(rnd.nextInt(dp(16) + 1) - dp(8));
            }
            ui.postDelayed(this, 500);
        }
    };

    /** Which source to show: a playing one wins; otherwise the most recently paused (for 10 min). */
    Track pick() {
        long now = SystemClock.elapsedRealtime();
        Track best = null;
        for (Track t : new Track[] { spotify, airplay }) {
            if (!t.active || t.title.length() == 0) continue;
            if (!t.playing && now - t.changed > 10 * 60 * 1000L) continue;
            if (best == null || (t.playing && !best.playing) || (t.playing == best.playing && t.changed > best.changed)) best = t;
        }
        return best;
    }

    void render() {
        Track t = pick();
        shown = t;
        boolean show = t != null;
        nowBox.setVisibility(show ? View.VISIBLE : View.GONE);
        idle.setVisibility(show ? View.GONE : View.VISIBLE);
        boolean playing = show && t.playing;
        if (playing != keepOn) {        // keep the screen on only while music plays
            keepOn = playing;
            if (playing) getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            else getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        }
        if (!show) return;
        title.setText(t.title);
        artist.setText(t.artist);
        album.setText(t.album);
        album.setVisibility(t.album.length() > 0 ? View.VISIBLE : View.GONE);
        art.setImageBitmap(t.art);
        boolean isSpotify = t == spotify;
        String label = (isSpotify ? "● Spotify" : "● AirPlay") + (t.from.length() > 0 ? "  ·  " + t.from : "");
        if (!t.playing) label += "  (paused)";
        source.setText(label);
        source.setTextColor(isSpotify ? SPOTIFY_GREEN : AIRPLAY_BLUE);
        progress.color = isSpotify ? SPOTIFY_GREEN : AIRPLAY_BLUE;
        renderProgress();
    }

    void renderProgress() {
        Track t = shown;
        if (t == null) return;
        long pos = t.position();
        progress.fraction = t.durMs > 0 ? (float) pos / t.durMs : 0f;
        progress.invalidate();
        times.setText(t.durMs > 0 ? fmt(pos) + "  /  " + fmt(t.durMs) : "");
    }

    static String fmt(long ms) {
        long s = ms / 1000;
        return (s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60);
    }

    @Override public void onBackPressed() { /* home screen: nothing to go back to */ }

    @Override public boolean onKeyDown(int code, KeyEvent e) {
        if (code == KeyEvent.KEYCODE_BACK) return true;
        return super.onKeyDown(code, e);
    }

    static class ProgressView extends View {
        float fraction;
        int color = SPOTIFY_GREEN;
        final Paint p = new Paint();
        ProgressView(Context c) { super(c); }
        @Override protected void onDraw(Canvas c) {
            int w = getWidth(), h = getHeight();
            p.setColor(0xFF333333);
            c.drawRect(0, 0, w, h, p);
            p.setColor(color);
            c.drawRect(0, 0, w * Math.max(0f, Math.min(1f, fraction)), h, p);
        }
    }

    void startThread(String name, Runnable r) {
        Thread t = new Thread(r, name);
        t.setDaemon(true);
        t.start();
    }

    void post(Runnable r) { ui.post(r); }

    // ------------------------------------------------------------------ Spotify (Soloist WebSocket)

    void spotifyLoop() {
        while (true) {
            Socket s = null;
            try {
                s = new Socket();
                s.connect(new InetSocketAddress(WS_HOST, WS_PORT), 3000);
                InputStream in = s.getInputStream();
                OutputStream out = s.getOutputStream();
                byte[] key = new byte[16];
                rnd.nextBytes(key);
                String req = "GET / HTTP/1.1\r\nHost: " + WS_HOST + ":" + WS_PORT + "\r\nUpgrade: websocket\r\n"
                        + "Connection: Upgrade\r\nSec-WebSocket-Key: " + Base64.encodeToString(key, Base64.NO_WRAP)
                        + "\r\nSec-WebSocket-Version: 13\r\n\r\n";
                out.write(req.getBytes("US-ASCII"));
                out.flush();
                String head = readHttpHead(in);
                if (!head.startsWith("HTTP/1.1 101")) throw new IOException("handshake: " + head);
                wsOut = out;
                sendCommand("get_state");
                DataInputStream din = new DataInputStream(in);
                ByteArrayOutputStream msg = new ByteArrayOutputStream();
                int msgOp = 0;
                while (true) {
                    int b0 = din.readUnsignedByte(), b1 = din.readUnsignedByte();
                    int op = b0 & 0x0F;
                    long len = b1 & 0x7F;
                    if (len == 126) len = din.readUnsignedShort();
                    else if (len == 127) len = din.readLong();
                    byte[] mask = null;
                    if ((b1 & 0x80) != 0) { mask = new byte[4]; din.readFully(mask); }
                    byte[] data = new byte[(int) len];
                    din.readFully(data);
                    if (mask != null) for (int i = 0; i < data.length; i++) data[i] ^= mask[i & 3];
                    if (op == 8) throw new IOException("closed");
                    if (op == 9) { sendFrame(0xA, data); continue; }
                    if (op == 0xA) continue;
                    if (op != 0) { msg.reset(); msgOp = op; }
                    msg.write(data);
                    if ((b0 & 0x80) != 0 && msgOp == 1) {
                        final String text = new String(msg.toByteArray(), "UTF-8");
                        msg.reset();
                        onSpotifyMessage(text);
                    }
                }
            } catch (Exception e) {
                wsOut = null;
                post(new Runnable() { public void run() { spotify.active = false; render(); } });
            } finally {
                try { if (s != null) s.close(); } catch (IOException ignored) { }
            }
            SystemClock.sleep(3000);
        }
    }

    static String readHttpHead(InputStream in) throws IOException {
        StringBuilder sb = new StringBuilder();
        int c;
        while ((c = in.read()) != -1) {
            sb.append((char) c);
            if (sb.length() >= 4 && sb.substring(sb.length() - 4).equals("\r\n\r\n")) break;
            if (sb.length() > 8192) break;
        }
        return sb.toString();
    }

    synchronized void sendFrame(int op, byte[] payload) {
        OutputStream out = wsOut;
        if (out == null) return;
        try {
            ByteArrayOutputStream f = new ByteArrayOutputStream();
            f.write(0x80 | op);
            int n = payload.length;
            if (n < 126) f.write(0x80 | n);
            else { f.write(0x80 | 126); f.write(n >> 8); f.write(n & 0xFF); }
            byte[] mask = new byte[4];
            rnd.nextBytes(mask);
            f.write(mask);
            for (int i = 0; i < n; i++) f.write(payload[i] ^ mask[i & 3]);
            out.write(f.toByteArray());
            out.flush();
        } catch (IOException ignored) { }
    }

    void sendCommand(String cmd) {
        try { sendFrame(1, ("{\"type\":\"command\",\"command\":\"" + cmd + "\"}").getBytes("UTF-8")); }
        catch (IOException ignored) { }
    }

    void onSpotifyMessage(String text) {
        final JSONObject o;
        try { o = new JSONObject(text); } catch (Exception e) { return; }
        String type = o.optString("type");
        if ("playback_state".equals(type)) {
            post(new Runnable() { public void run() { applySpotifyState(o); } });
        } else if ("position_sync".equals(type)) {
            post(new Runnable() { public void run() { applySpotifyPosition(o.optJSONObject("position")); } });
        } else if ("auth_state".equals(type)) {
            if (!o.optBoolean("logged_in")) post(new Runnable() { public void run() { spotify.active = false; render(); } });
            else sendCommand("get_state");
        } else if (!"command_result".equals(type) && !"queue_changed".equals(type) && !"error".equals(type)) {
            sendCommand("get_state");   // track/playback/volume/device/context changed: fetch a full snapshot
        }
    }

    void applySpotifyState(JSONObject o) {
        Track t = spotify;
        String status = o.optString("status");
        boolean wasPlaying = t.playing;
        t.playing = "playing".equals(status) || "buffering".equals(status);
        t.active = o.optBoolean("is_active") && !"idle".equals(status);
        if (wasPlaying != t.playing) t.changed = SystemClock.elapsedRealtime();
        JSONObject item = o.optJSONObject("item");
        if (item != null) {
            t.title = name(item);
            // parent/creators/playback live under item.decorations (fall back to item itself)
            JSONObject deco = item.optJSONObject("decorations");
            if (deco == null) deco = item;
            StringBuilder ar = new StringBuilder();
            JSONArray cr = deco.has("creators") ? deco.optJSONArray("creators") : item.optJSONArray("creators");
            if (cr != null) for (int i = 0; i < cr.length(); i++) {
                JSONObject c = cr.optJSONObject(i);
                String n = c == null ? "" : name(c.optJSONObject("entity"));
                if (n.length() > 0) { if (ar.length() > 0) ar.append(", "); ar.append(n); }
            }
            t.artist = ar.toString();
            JSONObject parent = deco.has("parent") ? deco.optJSONObject("parent") : item.optJSONObject("parent");
            t.album = parent == null ? "" : name(parent.optJSONObject("entity"));
            JSONObject pb = deco.has("playback") ? deco.optJSONObject("playback") : item.optJSONObject("playback");
            t.durMs = pb == null ? 0 : pb.optLong("duration_ms");
            String url = coverUrl(item);
            if (url != null && !url.equals(t.artKey)) { t.artKey = url; t.art = null; loadCover(url); }
        }
        t.from = contextLabel(o.optJSONObject("context"));
        applySpotifyPosition(o.optJSONObject("position"));
        if (t.changed == 0) t.changed = SystemClock.elapsedRealtime();
        render();
    }

    void applySpotifyPosition(JSONObject p) {
        if (p == null) return;
        Track t = spotify;
        long pos = p.optLong("position_ms"), ts = p.optLong("timestamp_ms");
        t.speed = (float) p.optDouble("speed", 1.0);
        if (ts > 0) pos += (long) ((System.currentTimeMillis() - ts) * t.speed);
        t.posMs = pos;
        t.anchor = SystemClock.elapsedRealtime();
        if (t.speed == 0) t.speed = 1;      // paused snapshots carry speed 0; we stop via t.playing
        renderProgress();
    }

    static String name(JSONObject e) {
        if (e == null) return "";
        JSONObject d = e.optJSONObject("decorations");
        JSONObject id = d == null ? null : d.optJSONObject("identity");
        return id == null ? "" : id.optString("name");
    }

    static String coverUrl(JSONObject item) {
        JSONObject d = item.optJSONObject("decorations");
        JSONObject vi = d == null ? null : d.optJSONObject("visual_identity");
        JSONArray cov = vi == null ? null : vi.optJSONArray("cover");
        if (cov == null) return null;
        String fallback = null;
        for (int i = 0; i < cov.length(); i++) {
            JSONObject c = cov.optJSONObject(i);
            if (c == null) continue;
            if ("large".equals(c.optString("size"))) return c.optString("url");
            if (fallback == null) fallback = c.optString("url");
        }
        return fallback;
    }

    static String contextLabel(JSONObject ctx) {
        if (ctx == null) return "";
        String n = name(ctx);
        if (n.length() > 0) return n;
        String uri = ctx.optString("uri");
        if (uri.startsWith("spotify:station:")) return "Radio";
        if (uri.startsWith("spotify:playlist:")) return "Playlist";
        if (uri.startsWith("spotify:album:")) return "Album";
        if (uri.startsWith("spotify:artist:")) return "Artist";
        if (uri.contains(":collection")) return "Liked Songs";
        return "";
    }

    void loadCover(final String url) {
        startThread("cover", new Runnable() {
            public void run() {
                final Bitmap bm = download(url);
                post(new Runnable() {
                    public void run() {
                        if (url.equals(spotify.artKey)) { spotify.art = bm; render(); }
                    }
                });
            }
        });
    }

    /** Cover art: Spotify's image CDN also serves plain HTTP, which avoids Android 4.2's dated
     *  HTTPS stack (old CA list, TLS 1.2 off by default). HTTPS with TLS 1.2 is the fallback. */
    static Bitmap download(String url) {
        if (url.startsWith("https://i.scdn.co/")) {
            Bitmap b = fetch("http://" + url.substring(8));
            if (b != null) return b;
        }
        return fetch(url);
    }

    static Bitmap fetch(String url) {
        try {
            HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
            if (c instanceof HttpsURLConnection) {
                SSLContext ctx = SSLContext.getInstance("TLS");
                ctx.init(null, null, null);
                ((HttpsURLConnection) c).setSSLSocketFactory(new Tls12Factory(ctx.getSocketFactory()));
            }
            c.setConnectTimeout(8000);
            c.setReadTimeout(8000);
            InputStream in = c.getInputStream();
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            byte[] buf = new byte[16384];
            int n;
            while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
            in.close();
            return decode(bo.toByteArray());
        } catch (Exception e) {
            return null;
        }
    }

    static Bitmap decode(byte[] data) {
        BitmapFactory.Options o = new BitmapFactory.Options();
        o.inJustDecodeBounds = true;
        BitmapFactory.decodeByteArray(data, 0, data.length, o);
        int sample = 1;
        while (o.outWidth / (sample * 2) >= 540) sample *= 2;
        o = new BitmapFactory.Options();
        o.inSampleSize = sample;
        return BitmapFactory.decodeByteArray(data, 0, data.length, o);
    }

    static class Tls12Factory extends SSLSocketFactory {
        final SSLSocketFactory d;
        Tls12Factory(SSLSocketFactory d) { this.d = d; }
        Socket fix(Socket s) {
            if (s instanceof SSLSocket) ((SSLSocket) s).setEnabledProtocols(((SSLSocket) s).getSupportedProtocols());
            return s;
        }
        public String[] getDefaultCipherSuites() { return d.getDefaultCipherSuites(); }
        public String[] getSupportedCipherSuites() { return d.getSupportedCipherSuites(); }
        public Socket createSocket(Socket s, String h, int p, boolean a) throws IOException { return fix(d.createSocket(s, h, p, a)); }
        public Socket createSocket(String h, int p) throws IOException { return fix(d.createSocket(h, p)); }
        public Socket createSocket(String h, int p, InetAddress la, int lp) throws IOException { return fix(d.createSocket(h, p, la, lp)); }
        public Socket createSocket(InetAddress h, int p) throws IOException { return fix(d.createSocket(h, p)); }
        public Socket createSocket(InetAddress h, int p, InetAddress la, int lp) throws IOException { return fix(d.createSocket(h, p, la, lp)); }
    }

    // ------------------------------------------------------------------ AirPlay (shairport-sync metadata pipe)

    static final Pattern ITEM = Pattern.compile(
            "<type>([0-9a-f]{8})</type><code>([0-9a-f]{8})</code><length>(\\d+)</length>(?:<data encoding=\"base64\">([^<]*)</data>)?");

    void airplayLoop() {
        while (true) {
            BufferedReader r = null;
            try {
                // blocks until shairport-sync opens the pipe for writing
                r = new BufferedReader(new InputStreamReader(new FileInputStream(META_PIPE), "US-ASCII"));
                StringBuilder item = new StringBuilder();
                String line;
                while ((line = r.readLine()) != null) {
                    item.append(line.trim());
                    if (line.contains("</item>")) {
                        Matcher m = ITEM.matcher(item);
                        if (m.find()) {
                            String type = hex4(m.group(1)), code = hex4(m.group(2));
                            byte[] data = m.group(4) == null ? new byte[0] : Base64.decode(m.group(4), Base64.DEFAULT);
                            onAirplayItem(type, code, data);
                        }
                        item.setLength(0);
                    }
                }
            } catch (Exception ignored) {
            } finally {
                try { if (r != null) r.close(); } catch (IOException ignored) { }
            }
            SystemClock.sleep(2000);
        }
    }

    static String hex4(String h) {
        char[] c = new char[4];
        for (int i = 0; i < 4; i++) c[i] = (char) Integer.parseInt(h.substring(i * 2, i * 2 + 2), 16);
        return new String(c);
    }

    void onAirplayItem(final String type, final String code, final byte[] data) {
        final String s;
        try { s = new String(data, "UTF-8"); } catch (Exception e) { return; }
        if ("ssnc".equals(type) && "PICT".equals(code)) {
            final Bitmap bm = data.length > 0 ? decode(data) : null;
            post(new Runnable() { public void run() { airplay.art = bm; render(); } });
            return;
        }
        post(new Runnable() {
            public void run() {
                Track t = airplay;
                long now = SystemClock.elapsedRealtime();
                if ("core".equals(type)) {
                    if ("minm".equals(code)) t.title = s;
                    else if ("asar".equals(code)) t.artist = s;
                    else if ("asal".equals(code)) t.album = s;
                    else return;
                } else if ("ssnc".equals(type)) {
                    if ("snam".equals(code)) t.from = s;                       // sender, e.g. "Jane's iPhone"
                    else if ("pbeg".equals(code) || "abeg".equals(code)) { t.active = true; t.playing = true; t.changed = now; }
                    else if ("pend".equals(code) || "aend".equals(code)) { t.active = false; t.playing = false; t.changed = now; }
                    else if ("pfls".equals(code)) { t.posMs = t.position(); t.anchor = now; t.playing = false; t.changed = now; }
                    else if ("prsm".equals(code)) { t.anchor = now; t.playing = true; t.active = true; t.changed = now; }
                    else if ("prgr".equals(code)) {                          // "start/current/end" in 44.1 kHz frames
                        String[] p = s.trim().split("/");
                        if (p.length == 3) {
                            long st = Long.parseLong(p[0]), cur = Long.parseLong(p[1]), en = Long.parseLong(p[2]);
                            // RTP timestamps are 32-bit and may wrap around
                            t.posMs = ((cur - st) & 0xFFFFFFFFL) * 1000 / 44100;
                            t.durMs = ((en - st) & 0xFFFFFFFFL) * 1000 / 44100;
                            t.anchor = now; t.speed = 1; t.playing = true; t.active = true;
                        }
                    } else return;
                } else return;
                render();
            }
        });
    }
}
