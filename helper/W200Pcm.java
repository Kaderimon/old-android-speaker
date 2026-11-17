import java.io.DataInputStream;
import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.lang.reflect.Method;
import java.util.ArrayDeque;

/**
 * Plays PCM (signed 16-bit little-endian, stereo) from stdin through android.media.AudioTrack.
 * Run on the phone with:
 *   CLASSPATH=/data/local/tmp/w200/w200pcm.jar app_process /system/bin W200Pcm [rate] [framed]
 *
 * raw mode (default, used by shairport-sync/librespot): stdin is plain PCM.
 * framed mode (used by Soloist via w200pulse): stdin carries frames
 *   "W2AU" <u32 len> <len bytes PCM>    audio
 *   "W2CT" <u32 code>                   control: 1 = pause, 2 = resume, 3 = flush
 * A reader thread drains stdin into a small queue, so pause/skip take effect immediately instead
 * of after the audio already buffered in the pipe has played.
 *
 * Uses reflection so it compiles with a plain JDK (no android.jar needed).
 */
public class W200Pcm {
    static final int STREAM_MUSIC = 3, CHANNEL_OUT_STEREO = 12, ENCODING_PCM_16BIT = 2, MODE_STREAM = 1;

    static Object track;
    static Method write, play, pause, flush;

    public static void main(String[] args) throws Exception {
        int rate = args.length > 0 ? Integer.parseInt(args[0]) : 44100;
        boolean framed = args.length > 1 && "framed".equals(args[1]);
        Class<?> at = Class.forName("android.media.AudioTrack");
        int min = (Integer) at.getMethod("getMinBufferSize", int.class, int.class, int.class)
                .invoke(null, rate, CHANNEL_OUT_STEREO, ENCODING_PCM_16BIT);
        int bufBytes = Math.max(min * 2, rate); // >= ~250 ms
        track = at.getConstructor(int.class, int.class, int.class, int.class, int.class, int.class)
                .newInstance(STREAM_MUSIC, rate, CHANNEL_OUT_STEREO, ENCODING_PCM_16BIT, bufBytes, MODE_STREAM);
        write = at.getMethod("write", byte[].class, int.class, int.class);
        play = at.getMethod("play");
        pause = at.getMethod("pause");
        flush = at.getMethod("flush");
        System.err.println("W200Pcm: rate=" + rate + " minBuf=" + min + " buf=" + bufBytes + (framed ? " framed" : " raw"));
        if (framed) runFramed(rate); else runRaw();
        at.getMethod("stop").invoke(track);
        at.getMethod("release").invoke(track);
    }

    static void writeAll(byte[] b, int off, int len) throws Exception {
        while (len > 0) {
            int w = (Integer) write.invoke(track, b, off, len);
            if (w <= 0) break;
            off += w; len -= w;
        }
    }

    // ---------------------------------------------------------------- raw mode (unchanged behaviour)
    static void runRaw() throws Exception {
        InputStream in = System.in;
        byte[] b = new byte[8192];
        int carry = 0;
        boolean playing = false;
        long lastData = System.currentTimeMillis();
        while (true) {
            // Pause the track after 3 s without input; resume as soon as data arrives.
            if (playing && in.available() == 0) {
                if (System.currentTimeMillis() - lastData > 3000) {
                    pause.invoke(track);
                    playing = false;
                    System.err.println("W200Pcm: idle, paused");
                } else {
                    Thread.sleep(20);
                    continue;
                }
            }
            int n = in.read(b, carry, b.length - carry); // blocks while idle
            if (n < 0) break;
            lastData = System.currentTimeMillis();
            if (!playing) { play.invoke(track); playing = true; }
            n += carry;
            int whole = n & ~3; // whole stereo frames only
            writeAll(b, 0, whole);
            carry = n - whole;
            if (carry > 0) System.arraycopy(b, whole, b, 0, carry);
        }
    }

    // ---------------------------------------------------------------- framed mode
    static final Object lock = new Object();
    static final ArrayDeque<byte[]> queue = new ArrayDeque<byte[]>();
    static int queuedBytes;
    static boolean paused, eof;
    static int maxQueue;

    static void runFramed(int rate) throws Exception {
        maxQueue = rate * 4 / 2;   // ~500 ms of S16 stereo read-ahead
        Thread reader = new Thread(new Runnable() {
            public void run() {
                try { readFrames(new DataInputStream(System.in)); }
                catch (Exception e) { /* EOF or broken pipe */ }
                synchronized (lock) { eof = true; lock.notifyAll(); }
            }
        }, "w200pcm-reader");
        reader.setDaemon(true);
        reader.start();

        boolean playing = false;
        while (true) {
            byte[] chunk;
            synchronized (lock) {
                long idleSince = System.currentTimeMillis();
                while ((queue.isEmpty() || paused) && !eof) {
                    if (playing && !paused && System.currentTimeMillis() - idleSince > 3000) {
                        pause.invoke(track);   // no data for 3 s: let the audio output go idle
                        playing = false;
                    }
                    lock.wait(100);
                }
                if (eof && queue.isEmpty()) break;
                chunk = queue.pollFirst();
                queuedBytes -= chunk.length;
                lock.notifyAll();
            }
            if (!playing) { play.invoke(track); playing = true; }
            writeAll(chunk, 0, chunk.length);
        }
    }

    static int readLE32(DataInputStream in) throws IOException {
        int a = in.readUnsignedByte(), b = in.readUnsignedByte(), c = in.readUnsignedByte(), d = in.readUnsignedByte();
        return a | (b << 8) | (c << 16) | (d << 24);
    }

    static void readFrames(DataInputStream in) throws Exception {
        byte[] magic = new byte[4];
        while (true) {
            in.readFully(magic);
            if (magic[0] != 'W' || magic[1] != '2') throw new IOException("bad frame");
            int v = readLE32(in);
            if (magic[2] == 'A' && magic[3] == 'U') {
                byte[] data = new byte[v & ~3];
                in.readFully(data);
                if ((v & 3) != 0) in.skipBytes(v & 3);
                synchronized (lock) {
                    while (queuedBytes > maxQueue && !paused) lock.wait(50);
                    queue.addLast(data);
                    queuedBytes += data.length;
                    lock.notifyAll();
                }
            } else if (magic[2] == 'C' && magic[3] == 'T') {
                control(v);
            } else {
                throw new IOException("bad frame type");
            }
        }
    }

    static void control(int code) throws Exception {
        synchronized (lock) {
            if (code == 1) {            // pause: stop now, keep what is buffered for resume
                paused = true;
                pause.invoke(track);
            } else if (code == 2) {     // resume
                paused = false;
                play.invoke(track);
            } else if (code == 3) {     // flush: drop everything queued (skip / seek)
                queue.clear();
                queuedBytes = 0;
                pause.invoke(track);
                flush.invoke(track);
                if (!paused) play.invoke(track);
            }
            lock.notifyAll();
        }
    }
}
