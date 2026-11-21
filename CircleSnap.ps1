# CircleSnap
# Watches your screen for a circle (the purple x2 by default, or any circle you
# teach it) and clicks it when it shows up. Runs as its own program next to the
# game: it only looks at the screen and moves/clicks the mouse. It never touches
# the game's files or memory.
#
# Start it by double-clicking "Start CircleSnap.bat".

param([switch]$NoRun)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing, System.Windows.Forms

if (-not ('TwoX.App' -as [type])) {
Add-Type -ReferencedAssemblies System.Drawing, System.Windows.Forms -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

namespace TwoX {

public static class Info {
    public const string Name = "CircleSnap";
    public const string Version = "1.3.0";
    public const string DefaultUpdateUrl = "https://raw.githubusercontent.com/morriz-123/CircleSnap/main/";
    // Updates must be signed with the developer's private key (kept off GitHub).
    public const string PublicKey = "<RSAKeyValue><Modulus>qi5iTvS2ilQbLdEFsIC1LrKFO2th9Kwsw0D8JJ9DojxOjKB4iYHQhbFW5nAqxFupMTLlswRJiEaYG39r7WulHNJ6iSOmPFLtW1YFlf88V7pFXuO6zof2IDgmXhKLfImcL3edY6c+BgFm6C4XES9/2btlzpcXnI2JDfRcE4iZlb7tYnyzMTTRsX78svQmHQ6roARY+LTkhOkytdl7ouWgCaiwBMINLpVcFeMzhE5kMLGiPW64iV3VrlQuK4vtGRN0YZYq1iXHmGjdt9qi1NwRU6FvMnU311hfhKCxix0Y44aI3vLed92z/Ye+Rt7gtB2weNbYBOAX7LbG1/rohezvIQ==</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>";
    public const string Changelog =
        "v1.3.0\n" +
        "- New look: sidebar, rounded buttons, custom title bar\n" +
        "- Settings tab: Start / Turn off keybinds, target, delay, human movement, always on top\n" +
        "- Hover the ? next to a setting to see what it does\n" +
        "- STATUS: IDLE / RUNNING / CLICKING / LEARNING / UPDATING\n" +
        "- Updates show up while the app is open (checks every minute)\n" +
        "- Signed updates: only installs updates signed by the developer\n" +
        "- Warns if your copy was modified, with a Repair button\n" +
        "\n" +
        "v1.2.0\n" +
        "- New name and logo: CircleSnap\n" +
        "- Update log tab\n" +
        "- Big banner when a new version is out\n" +
        "\n" +
        "v1.1.0\n" +
        "- Learn target: hover any circle to teach it (works in other games)\n" +
        "- Human movement option, scans all monitors, dark look and logs\n" +
        "\n" +
        "v1.0.0\n" +
        "- First version: finds and clicks the purple x2\n";
}

// #####################################################################
// ############################  BACK END  #############################
// #####################################################################

public static class Native {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool FlashWindow(IntPtr h, bool invert);
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }

    public static bool KeyDown(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }
    public static Point Cursor() { POINT p; GetCursorPos(out p); return new Point(p.X, p.Y); }
    public static Rectangle VirtualScreen { get { return SystemInformation.VirtualScreen; } }

    public static Bitmap Grab(Rectangle r) {
        var bmp = new Bitmap(r.Width, r.Height, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(r.Left, r.Top, 0, 0, r.Size);
        return bmp;
    }
    public static Bitmap GrabAll() { return Grab(VirtualScreen); }
}

public static class Mouse {
    // Real input events (SendInput): Roblox reads raw mouse input.
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public MOUSEINPUT mi; }
    [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Native.POINT p);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint flags);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint ms);
    [DllImport("winmm.dll")] static extern uint timeEndPeriod(uint ms);

    const uint MOVE = 0x0001, LEFTDOWN = 0x0002, LEFTUP = 0x0004, VIRTUALDESK = 0x4000, ABSOLUTE = 0x8000;
    static readonly Random rng = new Random();

    static void Send(uint flags, int dx, int dy) {
        var inp = new INPUT[] { new INPUT { type = 0, mi = new MOUSEINPUT { dx = dx, dy = dy, dwFlags = flags } } };
        SendInput(1, inp, Marshal.SizeOf(typeof(INPUT)));
    }

    public static void MoveTo(double x, double y) {
        Rectangle vs = Native.VirtualScreen;
        int nx = (int)Math.Round((x - vs.Left) * 65535.0 / Math.Max(1, vs.Width - 1));
        int ny = (int)Math.Round((y - vs.Top) * 65535.0 / Math.Max(1, vs.Height - 1));
        Send(MOVE | ABSOLUTE | VIRTUALDESK, nx, ny);
    }

    static bool FocusWindowAt(int x, int y) {
        IntPtr win = GetAncestor(WindowFromPoint(new Native.POINT { X = x, Y = y }), 2);
        if (win == IntPtr.Zero || win == GetForegroundWindow()) return false;
        keybd_event(0x12, 0, 0, UIntPtr.Zero); keybd_event(0x12, 0, 2, UIntPtr.Zero);
        SetForegroundWindow(win);
        Thread.Sleep(150);
        return true;
    }

    static void FastMove(int x, int y) {
        MoveTo(x - 12, y - 12); Thread.Sleep(20);
        for (int i = 0; i < 6; i++) { Send(MOVE, 2, 2); Thread.Sleep(8); }
        MoveTo(x, y); Thread.Sleep(30);
    }

    static void HumanMove(int tx, int ty) {
        Point s = Native.Cursor();
        double dx = tx - s.X, dy = ty - s.Y, dist = Math.Sqrt(dx * dx + dy * dy);
        if (dist < 4) { MoveTo(tx, ty); return; }
        double ux = dx / dist, uy = dy / dist, px = -uy, py = ux;
        double over = dist > 120 ? rng.Next(4, 11) : 0;
        double ex = tx + ux * over, ey = ty + uy * over;
        double b1 = (rng.NextDouble() - 0.5) * 0.5 * dist, b2 = (rng.NextDouble() - 0.5) * 0.35 * dist;
        double c1x = s.X + dx * 0.3 + px * b1, c1y = s.Y + dy * 0.3 + py * b1;
        double c2x = s.X + dx * 0.75 + px * b2, c2y = s.Y + dy * 0.75 + py * b2;
        int ms = (int)Math.Min(950, 170 + dist * 0.55 + rng.Next(0, 140));
        int steps = Math.Max(14, ms / 9);
        var sw = Stopwatch.StartNew();
        for (int i = 1; i <= steps; i++) {
            double t = i / (double)steps;
            double e = t < 0.5 ? 4 * t * t * t : 1 - Math.Pow(-2 * t + 2, 3) / 2;
            double u = 1 - e;
            double x = u * u * u * s.X + 3 * u * u * e * c1x + 3 * u * e * e * c2x + e * e * e * ex;
            double y = u * u * u * s.Y + 3 * u * u * e * c1y + 3 * u * e * e * c2y + e * e * e * ey;
            double jit = (1 - e) * 1.4;
            MoveTo(x + (rng.NextDouble() - 0.5) * jit, y + (rng.NextDouble() - 0.5) * jit);
            int wait = (int)(ms * t) + rng.Next(-2, 3) - (int)sw.ElapsedMilliseconds;
            if (wait > 0) Thread.Sleep(wait);
        }
        if (over > 0) {
            Thread.Sleep(rng.Next(25, 70));
            Point now = Native.Cursor();
            for (int i = 1; i <= 5; i++) {
                double t = i / 5.0;
                MoveTo(now.X + (tx - now.X) * t, now.Y + (ty - now.Y) * t);
                Thread.Sleep(rng.Next(8, 16));
            }
        }
        MoveTo(tx, ty);
    }

    public static string Click(int x, int y, int radius, bool human) {
        timeBeginPeriod(1);
        try {
            bool focused = FocusWindowAt(x, y);
            if (human && radius > 6) {
                double a = rng.NextDouble() * 2 * Math.PI, r = rng.NextDouble() * radius * 0.25;
                x += (int)(Math.Cos(a) * r); y += (int)(Math.Sin(a) * r);
            }
            if (human) HumanMove(x, y); else FastMove(x, y);
            Send(MOVE, 1, 0); Thread.Sleep(12); Send(MOVE, -1, 0); Thread.Sleep(12);
            MoveTo(x, y);
            Thread.Sleep(human ? rng.Next(70, 170) : 50);
            Send(LEFTDOWN, 0, 0);
            Thread.Sleep(human ? rng.Next(65, 140) : 90);
            Send(LEFTUP, 0, 0);
            return focused ? "focused game" : null;
        } finally { timeEndPeriod(1); }
    }
}

public static class ColorUtil {
    public static void ToHsv(int c, out double h, out double s, out double v) {
        int r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
        int max = Math.Max(r, Math.Max(g, b)), min = Math.Min(r, Math.Min(g, b));
        v = max / 255.0;
        s = max == 0 ? 0 : (max - min) / (double)max;
        if (max == min) { h = 0; return; }
        double d = max - min;
        if (max == r) h = 60 * (((g - b) / d) % 6);
        else if (max == g) h = 60 * (((b - r) / d) + 2);
        else h = 60 * (((r - g) / d) + 4);
        if (h < 0) h += 360;
    }
    public static double HueDist(double a, double b) { double d = Math.Abs(a - b) % 360; return d > 180 ? 360 - d : d; }
    public static string Hex(Color c) { return "#" + c.R.ToString("X2") + c.G.ToString("X2") + c.B.ToString("X2"); }
    public static double Pct(List<double> v, double p) {
        if (v.Count == 0) return 0;
        v.Sort();
        return v[(int)Math.Max(0, Math.Min(v.Count - 1, p * (v.Count - 1)))];
    }
    public static double Clamp(double x, double lo, double hi) { return x < lo ? lo : (x > hi ? hi : x); }
}

// Small picture "fingerprint" of a circle, to tell different circles apart.
public static class Sig {
    public const int N = 24;
    public static float[] Of(Bitmap src, Rectangle r) {
        using (var small = new Bitmap(N, N, PixelFormat.Format32bppArgb)) {
            using (var g = Graphics.FromImage(small)) {
                g.InterpolationMode = InterpolationMode.HighQualityBilinear;
                g.PixelOffsetMode = PixelOffsetMode.Half;
                g.DrawImage(src, new Rectangle(0, 0, N, N), r, GraphicsUnit.Pixel);
            }
            var f = new float[N * N * 3];
            for (int y = 0; y < N; y++)
                for (int x = 0; x < N; x++) {
                    Color c = small.GetPixel(x, y); int i = (y * N + x) * 3;
                    f[i] = c.R; f[i + 1] = c.G; f[i + 2] = c.B;
                }
            return f;
        }
    }
    public static double Compare(float[] a, float[] b) {
        double sum = 0; int n = 0;
        for (int y = 0; y < N; y++)
            for (int x = 0; x < N; x++) {
                double nx = (x + 0.5) / N * 2 - 1, ny = (y + 0.5) / N * 2 - 1;
                if (nx * nx + ny * ny > 0.85) continue;
                int i = (y * N + x) * 3;
                for (int k = 0; k < 3; k++) { sum += Math.Abs(a[i + k] - b[i + k]); n++; }
            }
        return n == 0 ? 0 : Math.Max(0, 1 - (sum / n) / 80.0);
    }
}

public class Target {
    public string Name = "Purple x2 (built-in)";
    public bool BuiltIn = true;
    public bool UseHue = true;
    public double Hue = 275, HueRange = 30, MinSat = 0.18, MinVal = 0.22, StrongSat = 0.35;
    public int R, G, B; public double RgbTol = 50;
    public int MinSize = 34, MaxSize = 400, Diameter;
    public bool NeedInner = true, Round = true;
    public float[] Sig;
    public double MinScore = 0.62;
    public Bitmap Picture;
    public Color Shown = Color.FromArgb(160, 90, 235);

    public int Level(int c) {
        if (UseHue) {
            double h, s, v; ColorUtil.ToHsv(c, out h, out s, out v);
            if (s < MinSat || v < MinVal) return 0;
            if (ColorUtil.HueDist(h, Hue) > HueRange) return 0;
            return s >= StrongSat ? 2 : 1;
        }
        int r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
        double d = Math.Sqrt((r - R) * (r - R) + (g - G) * (g - G) + (b - B) * (b - B));
        if (d > RgbTol) return 0;
        return d <= RgbTol * 0.6 ? 2 : 1;
    }

    public string Describe() {
        if (BuiltIn) return "Default target. Press Learn target to use a different circle.";
        return Diameter + " px  |  " + (Round ? "round" : "not round") + "  |  " + ColorUtil.Hex(Shown);
    }

    static string D(double x) { return x.ToString("0.####", CultureInfo.InvariantCulture); }
    static double P(Dictionary<string, string> d, string k) { return double.Parse(d[k], CultureInfo.InvariantCulture); }

    public void Save(List<string> o) {
        o.Add("target=learned");
        o.Add("t.useHue=" + (UseHue ? 1 : 0)); o.Add("t.hue=" + D(Hue)); o.Add("t.hueRange=" + D(HueRange));
        o.Add("t.minSat=" + D(MinSat)); o.Add("t.minVal=" + D(MinVal)); o.Add("t.strongSat=" + D(StrongSat));
        o.Add("t.rgb=" + R + "," + G + "," + B); o.Add("t.rgbTol=" + D(RgbTol));
        o.Add("t.size=" + MinSize + "," + MaxSize + "," + Diameter);
        o.Add("t.inner=" + (NeedInner ? 1 : 0)); o.Add("t.round=" + (Round ? 1 : 0));
        o.Add("t.minScore=" + D(MinScore)); o.Add("t.shown=" + Shown.ToArgb());
    }

    public static Target Load(Dictionary<string, string> d, Bitmap pic) {
        var t = new Target { BuiltIn = false, Name = "Learned circle" };
        t.UseHue = d["t.useHue"] == "1"; t.Hue = P(d, "t.hue"); t.HueRange = P(d, "t.hueRange");
        t.MinSat = P(d, "t.minSat"); t.MinVal = P(d, "t.minVal"); t.StrongSat = P(d, "t.strongSat");
        var rgb = d["t.rgb"].Split(','); t.R = int.Parse(rgb[0]); t.G = int.Parse(rgb[1]); t.B = int.Parse(rgb[2]);
        t.RgbTol = P(d, "t.rgbTol");
        var sz = d["t.size"].Split(','); t.MinSize = int.Parse(sz[0]); t.MaxSize = int.Parse(sz[1]); t.Diameter = int.Parse(sz[2]);
        t.NeedInner = d["t.inner"] == "1"; t.Round = d["t.round"] == "1";
        t.MinScore = P(d, "t.minScore"); t.Shown = Color.FromArgb(int.Parse(d["t.shown"]));
        t.Picture = pic;
        t.Sig = global::TwoX.Sig.Of(pic, new Rectangle(0, 0, pic.Width, pic.Height));
        return t;
    }
}

public class Hit {
    public Rectangle Box; public double Score;
    public Point Center { get { return new Point(Box.X + Box.Width / 2, Box.Y + Box.Height / 2); } }
}

public static class Detector {
    public static StringBuilder Debug;

    public static int[] Pixels(Bitmap b) {
        var d = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        var arr = new int[b.Width * b.Height];
        Marshal.Copy(d.Scan0, arr, 0, arr.Length);
        b.UnlockBits(d);
        return arr;
    }

    public static List<Hit> Find(Bitmap bmp, Rectangle exclude, Target t) {
        var hits = new List<Hit>();
        int W = bmp.Width, H = bmp.Height;
        int[] px = Pixels(bmp);
        const int S = 2;
        int mw = W / S, mh = H / S;
        bool[] mask = new bool[mw * mh], strong = new bool[mw * mh];
        for (int y = 0; y < mh; y++)
            for (int x = 0; x < mw; x++) {
                int sx = x * S, sy = y * S;
                if (exclude.Contains(sx, sy)) continue;
                int lvl = t.Level(px[sy * W + sx]);
                mask[y * mw + x] = lvl > 0; strong[y * mw + x] = lvl == 2;
            }
        bool[] seen = new bool[mw * mh];
        int[] stack = new int[mw * mh];
        for (int start = 0; start < mask.Length; start++) {
            if (!mask[start] || seen[start]) continue;
            int sp = 0; stack[sp++] = start; seen[start] = true;
            int count = 0, minx = mw, maxx = 0, miny = mh, maxy = 0;
            while (sp > 0) {
                int i = stack[--sp]; count++;
                int x = i % mw, y = i / mw;
                if (x < minx) minx = x; if (x > maxx) maxx = x;
                if (y < miny) miny = y; if (y > maxy) maxy = y;
                if (x > 0      && mask[i - 1]  && !seen[i - 1])  { seen[i - 1] = true;  stack[sp++] = i - 1; }
                if (x < mw - 1 && mask[i + 1]  && !seen[i + 1])  { seen[i + 1] = true;  stack[sp++] = i + 1; }
                if (y > 0      && mask[i - mw] && !seen[i - mw]) { seen[i - mw] = true; stack[sp++] = i - mw; }
                if (y < mh - 1 && mask[i + mw] && !seen[i + mw]) { seen[i + mw] = true; stack[sp++] = i + mw; }
            }
            int bw = maxx - minx + 1, bh = maxy - miny + 1;
            string dbg = (Debug != null && bw * S >= 30 && bh * S >= 30) ? "shape at (" + minx * S + "," + miny * S + ") " + bw * S + "x" + bh * S + ": " : null;
            if (bw * S < t.MinSize || bh * S < t.MinSize || bw * S > t.MaxSize || bh * S > t.MaxSize) { if (dbg != null) Debug.AppendLine(dbg + "size"); continue; }
            double score = 1.0;
            if (t.Round) {
                double aspect = bw / (double)bh;
                if (aspect < 0.75 || aspect > 1.33) { if (dbg != null) Debug.AppendLine(dbg + "aspect"); continue; }
                double fill = count / (double)(bw * bh);
                if (fill < 0.35 || fill > 0.90) { if (dbg != null) Debug.AppendLine(dbg + "fill"); continue; }
                double ccx = (minx + maxx) / 2.0, ccy = (miny + maxy) / 2.0, rx = bw / 2.0, ry = bh / 2.0;
                int ringOn = 0; const int RING = 72;
                for (int k = 0; k < RING; k++) {
                    double a = k * 2 * Math.PI / RING;
                    int x = (int)Math.Round(ccx + Math.Cos(a) * rx * 0.80), y = (int)Math.Round(ccy + Math.Sin(a) * ry * 0.80);
                    if (x >= 0 && x < mw && y >= 0 && y < mh && mask[y * mw + x]) ringOn++;
                }
                if (ringOn < RING * 0.75) { if (dbg != null) Debug.AppendLine(dbg + "ring"); continue; }
                int outAll = 0, outOn = 0;
                for (int y = miny; y <= maxy; y++)
                    for (int x = minx; x <= maxx; x++) {
                        double nx = (x - ccx) / rx, ny = (y - ccy) / ry;
                        if (nx * nx + ny * ny > 1.15 * 1.15) { outAll++; if (strong[y * mw + x]) outOn++; }
                    }
                if (outAll > 0 && outOn > outAll * 0.15) { if (dbg != null) Debug.AppendLine(dbg + "outside"); continue; }
                score = ringOn / (double)RING;
            }
            if (t.NeedInner) {
                int inAll = 0, inOff = 0;
                for (int y = miny + bh / 4; y <= maxy - bh / 4; y++)
                    for (int x = minx + bw / 4; x <= maxx - bw / 4; x++) { inAll++; if (!mask[y * mw + x]) inOff++; }
                if (inAll == 0 || inOff < inAll * 0.06) { if (dbg != null) Debug.AppendLine(dbg + "no detail"); continue; }
            }
            var box = new Rectangle(minx * S, miny * S, bw * S, bh * S);
            if (t.Sig != null) {
                score = global::TwoX.Sig.Compare(global::TwoX.Sig.Of(bmp, box), t.Sig);
                if (score < t.MinScore) { if (dbg != null) Debug.AppendLine(dbg + "looks different " + score.ToString("0.00")); continue; }
            }
            if (dbg != null) Debug.AppendLine(dbg + "MATCH " + score.ToString("0.00"));
            hits.Add(new Hit { Box = box, Score = score });
        }
        hits.Sort((a, b) => b.Score.CompareTo(a.Score));
        return hits;
    }
}

public static class Learner {
    public static Target Learn(Point screenPt, out string error) {
        Rectangle area = new Rectangle(screenPt.X - 450, screenPt.Y - 450, 900, 900);
        area.Intersect(Native.VirtualScreen);
        using (Bitmap bmp = Native.Grab(area))
            return LearnFrom(bmp, new Point(screenPt.X - area.Left, screenPt.Y - area.Top), out error);
    }

    public static Target LearnFrom(Bitmap bmp, Point p, out string error) {
        error = null;
        int W = bmp.Width, H = bmp.Height;
        int[] px = Detector.Pixels(bmp);
        const int R0 = 28;
        int total = 0, sat = 0;
        double[] bins = new double[36];
        var near = new List<int>();
        for (int y = Math.Max(0, p.Y - R0); y <= Math.Min(H - 1, p.Y + R0); y++)
            for (int x = Math.Max(0, p.X - R0); x <= Math.Min(W - 1, p.X + R0); x++) {
                if ((x - p.X) * (x - p.X) + (y - p.Y) * (y - p.Y) > R0 * R0) continue;
                int c = px[y * W + x]; total++; near.Add(c);
                double h, s, v; ColorUtil.ToHsv(c, out h, out s, out v);
                if (s >= 0.25 && v >= 0.25) { sat++; bins[(int)(h / 10) % 36] += s; }
            }
        if (total == 0) { error = "the cursor is off the screen"; return null; }

        var t = new Target { BuiltIn = false, Name = "Learned circle", MinScore = 0.70 };
        t.UseHue = sat >= total * 0.2;
        if (t.UseHue) {
            int best = 0;
            for (int i = 1; i < 36; i++) if (bins[i] > bins[best]) best = i;
            double cs = 0, sn = 0;
            foreach (int c in near) {
                double h, s, v; ColorUtil.ToHsv(c, out h, out s, out v);
                if (s < 0.25 || v < 0.25) continue;
                int db = Math.Abs((int)(h / 10) % 36 - best); if (db > 18) db = 36 - db;
                if (db > 1) continue;
                cs += Math.Cos(h * Math.PI / 180) * s; sn += Math.Sin(h * Math.PI / 180) * s;
            }
            double hue = Math.Atan2(sn, cs) * 180 / Math.PI; if (hue < 0) hue += 360;
            t.Hue = hue; t.HueRange = 25; t.MinSat = 0.15; t.MinVal = 0.15; t.StrongSat = 0.15;
        } else {
            var counts = new Dictionary<int, int>();
            foreach (int c in near) {
                int k = ((((c >> 16) & 255) >> 5) << 6) | ((((c >> 8) & 255) >> 5) << 3) | ((c & 255) >> 5);
                int n; counts.TryGetValue(k, out n); counts[k] = n + 1;
            }
            int bestK = -1, bestN = 0;
            foreach (var kv in counts) if (kv.Value > bestN) { bestN = kv.Value; bestK = kv.Key; }
            long sr = 0, sg = 0, sb = 0; int m = 0;
            foreach (int c in near) {
                int k = ((((c >> 16) & 255) >> 5) << 6) | ((((c >> 8) & 255) >> 5) << 3) | ((c & 255) >> 5);
                if (k != bestK) continue;
                sr += (c >> 16) & 255; sg += (c >> 8) & 255; sb += c & 255; m++;
            }
            t.R = (int)(sr / m); t.G = (int)(sg / m); t.B = (int)(sb / m); t.RgbTol = 45;
        }

        bool[] mask = new bool[W * H];
        for (int i = 0; i < mask.Length; i++) mask[i] = t.Level(px[i]) > 0;
        int seed = -1, bestD = int.MaxValue;
        for (int y = Math.Max(0, p.Y - R0); y <= Math.Min(H - 1, p.Y + R0); y++)
            for (int x = Math.Max(0, p.X - R0); x <= Math.Min(W - 1, p.X + R0); x++) {
                int d2 = (x - p.X) * (x - p.X) + (y - p.Y) * (y - p.Y);
                if (d2 < bestD && mask[y * W + x]) { bestD = d2; seed = y * W + x; }
            }
        if (seed < 0) { error = "no clear colour under the cursor"; return null; }

        bool[] inBlob = new bool[W * H];
        int[] stack = new int[W * H];
        var blob = new List<int>();
        int sp = 0; stack[sp++] = seed; inBlob[seed] = true;
        int minx = W, maxx = 0, miny = H, maxy = 0;
        while (sp > 0) {
            int i = stack[--sp]; blob.Add(i);
            int x = i % W, y = i / W;
            if (x < minx) minx = x; if (x > maxx) maxx = x;
            if (y < miny) miny = y; if (y > maxy) maxy = y;
            if (x > 0     && mask[i - 1] && !inBlob[i - 1]) { inBlob[i - 1] = true; stack[sp++] = i - 1; }
            if (x < W - 1 && mask[i + 1] && !inBlob[i + 1]) { inBlob[i + 1] = true; stack[sp++] = i + 1; }
            if (y > 0     && mask[i - W] && !inBlob[i - W]) { inBlob[i - W] = true; stack[sp++] = i - W; }
            if (y < H - 1 && mask[i + W] && !inBlob[i + W]) { inBlob[i + W] = true; stack[sp++] = i + W; }
        }
        int bw = maxx - minx + 1, bh = maxy - miny + 1;
        if (bw < 14 || bh < 14) { error = "that shape is too small (" + bw + "x" + bh + ")"; return null; }
        if (minx == 0 || miny == 0 || maxx == W - 1 || maxy == H - 1) { error = "that colour spreads into the background - is the cursor on the circle?"; return null; }

        int stepPx = Math.Max(1, blob.Count / 20000);
        long ar = 0, ag = 0, ab = 0; int an = 0;
        if (t.UseHue) {
            var dh = new List<double>(); var ss = new List<double>(); var vv = new List<double>();
            for (int j = 0; j < blob.Count; j += stepPx) {
                int c = px[blob[j]]; double h, s, v; ColorUtil.ToHsv(c, out h, out s, out v);
                dh.Add(ColorUtil.HueDist(h, t.Hue)); ss.Add(s); vv.Add(v);
                ar += (c >> 16) & 255; ag += (c >> 8) & 255; ab += c & 255; an++;
            }
            t.HueRange = ColorUtil.Clamp(ColorUtil.Pct(dh, 0.95) + 6, 10, 40);
            t.MinSat = Math.Max(0.08, ColorUtil.Pct(ss, 0.05) - 0.04);
            t.MinVal = Math.Max(0.10, ColorUtil.Pct(vv, 0.05) - 0.05);
            t.StrongSat = Math.Max(t.MinSat, ColorUtil.Pct(ss, 0.40));
        } else {
            var dd = new List<double>();
            for (int j = 0; j < blob.Count; j += stepPx) {
                int c = px[blob[j]]; int r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
                dd.Add(Math.Sqrt((r - t.R) * (r - t.R) + (g - t.G) * (g - t.G) + (b - t.B) * (b - t.B)));
                ar += r; ag += g; ab += b; an++;
            }
            t.RgbTol = ColorUtil.Clamp(ColorUtil.Pct(dd, 0.95) + 10, 25, 90);
        }
        t.Shown = Color.FromArgb((int)(ar / an), (int)(ag / an), (int)(ab / an));

        double ccx = (minx + maxx) / 2.0, ccy = (miny + maxy) / 2.0, rx = bw / 2.0, ry = bh / 2.0;
        int ringOn = 0;
        for (int k = 0; k < 72; k++) {
            double a = k * 2 * Math.PI / 72;
            int x = (int)Math.Round(ccx + Math.Cos(a) * rx * 0.80), y = (int)Math.Round(ccy + Math.Sin(a) * ry * 0.80);
            if (inBlob[y * W + x]) ringOn++;
        }
        double aspect = bw / (double)bh;
        t.Round = ringOn >= 72 * 0.75 && aspect >= 0.75 && aspect <= 1.33;
        int inAll = 0, inOff = 0;
        for (int y = miny + bh / 4; y <= maxy - bh / 4; y++)
            for (int x = minx + bw / 4; x <= maxx - bw / 4; x++) { inAll++; if (!inBlob[y * W + x]) inOff++; }
        t.NeedInner = inAll > 0 && inOff >= inAll * 0.06;
        t.Diameter = (bw + bh) / 2;
        t.MinSize = Math.Max(16, (int)(t.Diameter * 0.35));
        t.MaxSize = Math.Min(1400, (int)(t.Diameter * 2.6) + 10);
        var box = new Rectangle(minx, miny, bw, bh);
        t.Picture = bmp.Clone(box, PixelFormat.Format32bppArgb);
        t.Sig = global::TwoX.Sig.Of(bmp, box);
        return t;
    }
}

// ---- security: only trust updates signed with the developer's private key ----
public static class Security {
    // The signed text = every line of latest.txt except "sig=", trimmed, joined with \n.
    public static string Canonical(string manifest) {
        var keep = new List<string>();
        foreach (var raw in manifest.Replace("\r", "").Split('\n')) {
            string l = raw.Trim();
            if (l.Length == 0 || l.StartsWith("sig=")) continue;
            keep.Add(l);
        }
        return string.Join("\n", keep.ToArray());
    }
    public static bool Verify(string manifest, string sigBase64) {
        if (string.IsNullOrEmpty(sigBase64)) return false;
        try {
            using (var rsa = new RSACryptoServiceProvider()) {
                rsa.FromXmlString(Info.PublicKey);
                return rsa.VerifyData(Encoding.UTF8.GetBytes(Canonical(manifest)), "SHA256", Convert.FromBase64String(sigBase64));
            }
        } catch { return false; }
    }
    static readonly Regex SafeName = new Regex(@"^[A-Za-z0-9 ._-]{1,64}\.(ps1|bat|txt)$");
    public static bool IsSafeFileName(string n) { return SafeName.IsMatch(n) && !n.Contains(".."); }
    public static bool IsAllowedUrl(string url) {
        return url.StartsWith("https://") || url.StartsWith("http://localhost") || url.StartsWith("http://127.0.0.1");
    }
}

public class Release {
    public string Version, Notes, BaseUrl;
    public List<string[]> Files = new List<string[]>();
}

public static class Updater {
    static WebClient Client() {
        ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072;
        var wc = new WebClient();
        wc.Headers[HttpRequestHeader.UserAgent] = "circlesnap-updater";
        wc.Headers[HttpRequestHeader.CacheControl] = "no-cache";
        return wc;
    }
    static string Bust() { return "?t=" + DateTime.UtcNow.Ticks; }

    public static Release Fetch(string baseUrl) {
        if (!Security.IsAllowedUrl(baseUrl)) throw new Exception("update address must be https");
        string text;
        using (var wc = Client()) text = wc.DownloadString(baseUrl + "latest.txt" + Bust());
        var r = new Release { BaseUrl = baseUrl };
        string sig = null;
        foreach (var raw in text.Split('\n')) {
            string line = raw.Trim(); int eq = line.IndexOf('=');
            if (eq <= 0) continue;
            string k = line.Substring(0, eq).Trim(), v = line.Substring(eq + 1).Trim();
            if (k == "version") r.Version = v;
            else if (k == "notes") r.Notes = v;
            else if (k == "sig") sig = v;
            else if (k == "file") {
                var parts = v.Split('|');
                string name = parts[0].Trim();
                if (!Security.IsSafeFileName(name)) throw new Exception("blocked file name in update: " + name);
                r.Files.Add(new string[] { name, parts.Length > 1 ? parts[1].Trim().ToLowerInvariant() : "" });
            }
        }
        if (r.Version == null || r.Files.Count == 0) throw new Exception("update info is incomplete");
        foreach (var f in r.Files) if (f[1].Length != 64) throw new Exception("update file has no checksum: " + f[0]);
        if (!Security.Verify(text, sig)) throw new Exception("update is not signed by the developer - ignored");
        new Version(r.Version);
        return r;
    }

    // Checksum that ignores line endings and trailing blank lines.
    public static string Sha256(string path) {
        byte[] raw = File.ReadAllBytes(path);
        var list = new List<byte>(raw.Length + 1);
        foreach (byte b in raw) if (b != 13) list.Add(b);
        while (list.Count > 0 && (list[list.Count - 1] == 10 || list[list.Count - 1] == 32 || list[list.Count - 1] == 9)) list.RemoveAt(list.Count - 1);
        list.Add(10);
        using (var sha = SHA256.Create()) {
            var sb = new StringBuilder();
            foreach (byte b in sha.ComputeHash(list.ToArray())) sb.Append(b.ToString("x2"));
            return sb.ToString();
        }
    }

    // Files in this folder that don't match the official release.
    public static List<string> Modified(Release r, string folder) {
        var bad = new List<string>();
        foreach (var f in r.Files) {
            string p = Path.Combine(folder, f[0]);
            if (!File.Exists(p) || Sha256(p) != f[1]) bad.Add(f[0]);
        }
        return bad;
    }

    public static string FetchText(string baseUrl, string name) {
        using (var wc = Client()) { wc.Encoding = Encoding.UTF8; return wc.DownloadString(baseUrl + Uri.EscapeDataString(name) + Bust()); }
    }

    public static void Install(Release r, string folder, Action<int, string> progress) {
        string tmp = Path.Combine(Path.GetTempPath(), "circlesnap-update-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tmp);
        try {
            using (var wc = Client()) {
                for (int i = 0; i < r.Files.Count; i++) {
                    string name = r.Files[i][0], hash = r.Files[i][1];
                    progress(5 + 70 * i / r.Files.Count, "Downloading " + name);
                    string dst = Path.Combine(tmp, name);
                    wc.DownloadFile(r.BaseUrl + Uri.EscapeDataString(name) + Bust(), dst);
                    if (Sha256(dst) != hash) throw new Exception(name + " didn't download correctly (checksum)");
                }
            }
            progress(80, "Installing");
            var done = new List<string>();
            try {
                foreach (var f in r.Files) {
                    string dest = Path.Combine(folder, f[0]);
                    if (File.Exists(dest)) File.Copy(dest, dest + ".bak", true);
                    done.Add(dest);
                    File.Copy(Path.Combine(tmp, f[0]), dest, true);
                }
            } catch {
                foreach (var d in done) if (File.Exists(d + ".bak")) File.Copy(d + ".bak", d, true);
                throw;
            }
            foreach (var d in done) if (File.Exists(d + ".bak")) File.Delete(d + ".bak");
            progress(100, "Installed");
        } finally {
            try { Directory.Delete(tmp, true); } catch { }
        }
    }
}

// #####################################################################
// ############################  FRONT END  ############################
// #####################################################################

public static class Theme {
    public static readonly Color Title  = Color.FromArgb(14, 15, 18);
    public static readonly Color Side   = Color.FromArgb(18, 19, 23);
    public static readonly Color Bg     = Color.FromArgb(24, 25, 30);
    public static readonly Color Card   = Color.FromArgb(32, 34, 40);
    public static readonly Color Line   = Color.FromArgb(46, 49, 57);
    public static readonly Color Txt    = Color.FromArgb(232, 233, 236);
    public static readonly Color Dim    = Color.FromArgb(138, 143, 153);
    public static readonly Color Faint  = Color.FromArgb(88, 92, 102);
    public static readonly Color Accent = Color.FromArgb(47, 111, 237);
    public static readonly Color BlueT  = Color.FromArgb(37, 84, 190);
    public static readonly Color BlueB  = Color.FromArgb(20, 44, 112);
    public static readonly Color Btn    = Color.FromArgb(44, 47, 55);
    public static readonly Color Go     = Color.FromArgb(67, 181, 105);
    public static readonly Color Halt   = Color.FromArgb(232, 80, 80);
    public static readonly Color Warn   = Color.FromArgb(240, 178, 50);
    public static readonly Color Cyan   = Color.FromArgb(34, 193, 195);
    public static readonly Color Info   = Color.FromArgb(90, 150, 255);
}

public static class Gfx {
    public static GraphicsPath Round(RectangleF r, float rad) {
        var p = new GraphicsPath();
        float d = Math.Min(rad * 2, Math.Min(r.Width, r.Height));
        if (d <= 1) { p.AddRectangle(r); return p; }
        p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }
    public static Color Mix(Color a, Color b, float t) {
        return Color.FromArgb((int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t));
    }
}

public static class Logo {
    public static Bitmap Draw(int size) {
        var b = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(b)) {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);
            using (var path = Gfx.Round(new RectangleF(0, 0, size - 1, size - 1), size * 0.24f))
            using (var br = new LinearGradientBrush(new Rectangle(0, 0, size, size), Color.FromArgb(32, 201, 151), Color.FromArgb(24, 119, 242), 45f))
                g.FillPath(br, path);
            float c = size / 2f, ring = size * 0.29f, w = Math.Max(1.5f, size * 0.085f);
            using (var p = new Pen(Color.White, w)) g.DrawEllipse(p, c - ring, c - ring, ring * 2, ring * 2);
            float dot = size * 0.10f;
            g.FillEllipse(Brushes.White, c - dot, c - dot, dot * 2, dot * 2);
            using (var p = new Pen(Color.FromArgb(220, 255, 255, 255), Math.Max(1f, size * 0.05f))) {
                float a = size * 0.12f, z = size * 0.02f;
                g.DrawLine(p, c, a - z, c, a + size * 0.08f);
                g.DrawLine(p, c, size - a + z, c, size - a - size * 0.08f);
                g.DrawLine(p, a - z, c, a + size * 0.08f, c);
                g.DrawLine(p, size - a + z, c, size - a - size * 0.08f, c);
            }
        }
        return b;
    }
    public static Icon MakeIcon() { using (var b = Draw(64)) return Icon.FromHandle(b.GetHicon()); }
}

// Base for all custom-drawn controls: smooth painting, hover/press state.
public class Smooth : Control {
    protected bool Hover, Down;
    public Smooth() {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint |
                 ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
        TabStop = false; Cursor = Cursors.Hand;
    }
    protected override void OnMouseEnter(EventArgs e) { Hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { Hover = false; Down = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { if (e.Button == MouseButtons.Left) { Down = true; Invalidate(); } base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { Down = false; Invalidate(); base.OnMouseUp(e); }
    protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
    protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }
    protected static float K(Graphics g) { return g.DpiX / 96f; }
    protected void Prep(Graphics g) {
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        g.Clear(Parent != null ? Parent.BackColor : BackColor);
    }
}

// Rounded card that holds other controls.
public class Card : Panel {
    public Color Fill = Theme.Card, Border = Color.Empty;
    public float Radius = 10;
    public Card() {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
    }
    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(Parent != null ? Parent.BackColor : BackColor);
        float k = g.DpiX / 96f;
        using (var path = Gfx.Round(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), Radius * k)) {
            using (var br = new SolidBrush(Fill)) g.FillPath(br, path);
            if (Border != Color.Empty) using (var p = new Pen(Border)) g.DrawPath(p, path);
        }
    }
}

// Rounded button. Style 0 = shiny blue, 1 = flat dark, 2 = amber-banner dark.
public class HubButton : Smooth {
    public int Style;
    public float Radius = 8;
    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics; Prep(g);
        float k = K(g);
        if (Width < 4 || Height < 4) return;
        var r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
        Color top, bot;
        if (Style == 0) { top = Theme.BlueT; bot = Theme.BlueB; }
        else if (Style == 2) { top = Color.FromArgb(34, 35, 40); bot = Color.FromArgb(22, 23, 27); }
        else { top = Theme.Btn; bot = Gfx.Mix(Theme.Btn, Color.Black, 0.12f); }
        if (!Enabled) { top = Theme.Card; bot = Theme.Card; }
        else if (Down) { top = Gfx.Mix(top, Color.Black, 0.2f); bot = Gfx.Mix(bot, Color.Black, 0.2f); }
        else if (Hover) { top = Gfx.Mix(top, Color.White, 0.12f); bot = Gfx.Mix(bot, Color.White, 0.1f); }
        using (var path = Gfx.Round(r, Radius * k)) {
            using (var br = new LinearGradientBrush(r, top, bot, 90f)) g.FillPath(br, path);
            if (Style == 0 && Enabled) { // the shine
                var hr = new RectangleF(r.X + 2 * k, r.Y + 1.5f * k, r.Width - 4 * k, r.Height * 0.46f);
                using (var hp = Gfx.Round(hr, Math.Max(1, Radius * k - 2)))
                using (var hb = new LinearGradientBrush(new RectangleF(hr.X, hr.Y - 1, hr.Width, hr.Height + 2), Color.FromArgb(78, 255, 255, 255), Color.FromArgb(6, 255, 255, 255), 90f))
                    g.FillPath(hb, hp);
            }
            using (var pen = new Pen(Color.FromArgb(Style == 0 ? 70 : 30, 255, 255, 255))) g.DrawPath(pen, path);
        }
        TextRenderer.DrawText(g, Text, Font, ClientRectangle, Enabled ? ForeColor : Theme.Faint,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
    }
}

// On/off switch.
public class Toggle : Smooth {
    bool on;
    public event EventHandler Changed;
    public bool On {
        get { return on; }
        set { if (on == value) return; on = value; Invalidate(); if (Changed != null) Changed(this, EventArgs.Empty); }
    }
    protected override void OnClick(EventArgs e) { On = !On; base.OnClick(e); }
    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics; Prep(g);
        var r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
        Color track = on ? Theme.Accent : Color.FromArgb(58, 61, 70);
        if (Hover) track = Gfx.Mix(track, Color.White, 0.1f);
        using (var path = Gfx.Round(r, r.Height / 2)) using (var br = new SolidBrush(track)) g.FillPath(br, path);
        float d = r.Height - 6, x = on ? r.Right - d - 3 : r.X + 3;
        g.FillEllipse(Brushes.White, x, r.Y + 3, d, d);
    }
}

// Filled "?" that turns white on hover and shows an explanation.
public class HelpDot : Smooth {
    public string Help;
    public Action<HelpDot, bool> HoverChanged;
    public HelpDot() { Cursor = Cursors.Help; }
    protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); if (HoverChanged != null) HoverChanged(this, true); }
    protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); if (HoverChanged != null) HoverChanged(this, false); }
    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics; Prep(g);
        var r = new RectangleF(1, 1, Width - 3, Height - 3);
        using (var br = new SolidBrush(Hover ? Color.White : Color.FromArgb(64, 68, 78))) g.FillEllipse(br, r);
        using (var f = new Font("Segoe UI", 7.5f, FontStyle.Bold))
            TextRenderer.DrawText(g, "?", f, Rectangle.Round(r), Hover ? Theme.Bg : Color.FromArgb(205, 208, 215),
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
    }
}

// Sidebar tab.
public class NavItem : Smooth {
    public bool Selected; public int Icon;
    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics; Prep(g);
        float k = K(g);
        var r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
        if (Selected || Hover)
            using (var path = Gfx.Round(r, 8 * k)) using (var br = new SolidBrush(Selected ? Color.FromArgb(34, 37, 46) : Color.FromArgb(26, 28, 34))) g.FillPath(br, path);
        if (Selected) using (var br = new SolidBrush(Theme.Accent)) g.FillRectangle(br, 0, Height * 0.25f, 3 * k, Height * 0.5f);
        Color c = Selected ? Theme.Txt : Theme.Dim;
        float cx = 22 * k, cy = Height / 2f, s = 7 * k;
        using (var p = new Pen(c, 1.6f * k)) {
            if (Icon == 0) { g.DrawEllipse(p, cx - s, cy - s, 2 * s, 2 * s); g.FillEllipse(new SolidBrush(c), cx - 2 * k, cy - 2 * k, 4 * k, 4 * k); }
            else if (Icon == 1) {
                g.DrawEllipse(p, cx - s * 0.55f, cy - s * 0.55f, s * 1.1f, s * 1.1f);
                for (int i = 0; i < 8; i++) { double a = i * Math.PI / 4; g.DrawLine(p, cx + (float)Math.Cos(a) * s * 0.75f, cy + (float)Math.Sin(a) * s * 0.75f, cx + (float)Math.Cos(a) * s * 1.05f, cy + (float)Math.Sin(a) * s * 1.05f); }
            } else { for (int i = -1; i <= 1; i++) g.DrawLine(p, cx - s, cy + i * s * 0.6f, cx + s, cy + i * s * 0.6f); }
        }
        var tr = new Rectangle((int)(40 * k), 0, Width - (int)(40 * k), Height);
        TextRenderer.DrawText(g, Text, Font, tr, c, TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
    }
}

// Small greyed-out smiley face.
public class Smiley : Smooth {
    public Smiley() { Cursor = Cursors.Default; }
    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics; Prep(g); float k = K(g);
        var r = new RectangleF(1.5f * k, 1.5f * k, Width - 3 * k, Height - 3 * k);
        using (var p = new Pen(Theme.Faint, 1.4f * k)) {
            g.DrawEllipse(p, r);
            g.DrawArc(p, r.X + r.Width * 0.25f, r.Y + r.Height * 0.3f, r.Width * 0.5f, r.Height * 0.45f, 20, 140);
        }
        using (var br = new SolidBrush(Theme.Faint)) {
            float d = Math.Max(1.5f, r.Width * 0.12f);
            g.FillEllipse(br, r.X + r.Width * 0.32f - d / 2, r.Y + r.Height * 0.36f - d / 2, d, d);
            g.FillEllipse(br, r.X + r.Width * 0.68f - d / 2, r.Y + r.Height * 0.36f - d / 2, d, d);
        }
    }
}

// Minimize / close buttons in the custom title bar.
public class TitleButton : Smooth {
    public bool IsClose;
    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics; float k = K(g);
        g.Clear(Hover ? (IsClose ? Color.FromArgb(200, 50, 50) : Color.FromArgb(36, 38, 45)) : Theme.Title);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        float cx = Width / 2f, cy = Height / 2f, s = 5 * k;
        using (var p = new Pen(Hover ? Color.White : Theme.Dim, 1.4f * k)) {
            if (IsClose) { g.DrawLine(p, cx - s, cy - s, cx + s, cy + s); g.DrawLine(p, cx + s, cy - s, cx - s, cy + s); }
            else g.DrawLine(p, cx - s, cy, cx + s, cy);
        }
    }
}

public class UpdateForm : Form {
    Label step; Panel track, fill; HubButton closeBtn;
    public UpdateForm(string version, bool repair) {
        FormBorderStyle = FormBorderStyle.None; StartPosition = FormStartPosition.CenterParent;
        AutoScaleDimensions = new SizeF(96f, 96f); AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(380, 150); BackColor = Theme.Bg; ShowInTaskbar = false; Font = new Font("Segoe UI", 10f);
        Controls.Add(new Label { Text = (repair ? "Repairing v" : "Updating to v") + version, Font = new Font("Segoe UI", 13f, FontStyle.Bold),
            ForeColor = Theme.Txt, Location = new Point(20, 18), AutoSize = true });
        step = new Label { Text = "Starting", ForeColor = Theme.Dim, Location = new Point(20, 56), Size = new Size(340, 40) };
        track = new Panel { Location = new Point(20, 100), Size = new Size(340, 6), BackColor = Theme.Line };
        fill = new Panel { Location = new Point(0, 0), Size = new Size(0, 6), BackColor = Theme.Accent };
        track.Controls.Add(fill);
        closeBtn = new HubButton { Text = "Close", Style = 1, Location = new Point(280, 114), Size = new Size(80, 28), ForeColor = Theme.Txt, Visible = false };
        closeBtn.Click += (s, e) => Close();
        Controls.Add(step); Controls.Add(track); Controls.Add(closeBtn);
    }
    protected override void OnPaint(PaintEventArgs e) {
        base.OnPaint(e);
        using (var p = new Pen(Theme.Line)) e.Graphics.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
    }
    public void SetProgress(int pct, string text) { fill.Width = track.Width * pct / 100; step.Text = text; }
    public void Fail(string msg) { step.ForeColor = Theme.Halt; step.Text = msg; closeBtn.Visible = true; }
}

public class Flash : Form {
    public Flash(Rectangle r) {
        FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true;
        StartPosition = FormStartPosition.Manual; Bounds = Rectangle.Inflate(r, 8, 8);
        BackColor = Color.FromArgb(1, 2, 3); TransparencyKey = BackColor;
        var t = new System.Windows.Forms.Timer { Interval = 1300 };
        t.Tick += (s, e) => { t.Stop(); Close(); };
        t.Start();
    }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get { var cp = base.CreateParams; cp.ExStyle |= 0x20 | 0x80 | 0x08000000; return cp; }
    }
    protected override void OnPaint(PaintEventArgs e) {
        using (var p = new Pen(Color.FromArgb(255, 60, 60), 4)) e.Graphics.DrawRectangle(p, 2, 2, Width - 5, Height - 5);
    }
}

// ======================= the main window =======================
public class App : Form {
    readonly string folder, scriptPath, settingsPath, targetPngPath;
    Target target = new Target();
    HubButton startBtn, learnBtn, testBtn, resetBtn, bannerBtn, startKeyBtn, stopKeyBtn, minusBtn, plusBtn, repairBtn;
    Label statusWord, statusSub, countLbl, targetName, targetInfo, bannerLbl, bannerSub, changelogSrc, delayVal, tipLbl, modLbl;
    Card banner, tip;
    Panel content;
    Panel[] pages;
    NavItem[] navs;
    RichTextBox changelogBox;
    PictureBox targetPic;
    Toggle humanTgl, topTgl;
    ListBox log;
    System.Windows.Forms.Timer scanTimer, keyTimer, learnTimer, updateTimer;
    bool running, loaded, busy;
    int clicks, learnCountdown, delay = 3, startKey = 0x78, stopKey = 0x79, capturing; // capturing: 0 none, 1 start, 2 stop
    bool[] keyWas = new bool[256];
    DateTime nextScan = DateTime.MinValue, lastClickTime = DateTime.MinValue;
    Point lastClickPos;
    Release pendingUpdate, pendingRepair;

    public static void Run(string folder, string scriptPath) {
        Native.SetProcessDPIAware();
        Application.EnableVisualStyles();
        Application.Run(new App(folder, scriptPath));
    }

    protected override CreateParams CreateParams {
        get { var cp = base.CreateParams; cp.ClassStyle |= 0x20000; cp.Style |= 0x20000; return cp; } // drop shadow, minimize from taskbar
    }
    protected override void OnHandleCreated(EventArgs e) {
        base.OnHandleCreated(e);
        try { int round = 2; Native.DwmSetWindowAttribute(Handle, 33, ref round, 4); } catch { }
    }

    // ---- little factories ----
    Label L(Control parent, string text, int x, int y, int w, int h, Color c, float size, bool bold) {
        var l = new Label { Text = text, Location = new Point(x, y), ForeColor = c, BackColor = Color.Transparent,
            Font = new Font("Segoe UI", size, bold ? FontStyle.Bold : FontStyle.Regular) };
        if (w > 0) l.Size = new Size(w, h); else l.AutoSize = true;
        parent.Controls.Add(l);
        return l;
    }
    HubButton Btn(Control parent, string text, int style, int x, int y, int w, int h) {
        var b = new HubButton { Text = text, Style = style, Location = new Point(x, y), Size = new Size(w, h), ForeColor = Theme.Txt,
            BackColor = parent.BackColor, Font = new Font("Segoe UI", 9f, FontStyle.Bold) };
        parent.Controls.Add(b);
        return b;
    }
    Card CardAt(Control parent, int x, int y, int w, int h) {
        var c = new Card { Location = new Point(x, y), Size = new Size(w, h), BackColor = parent.BackColor };
        parent.Controls.Add(c);
        return c;
    }
    HelpDot Dot(Control parent, int x, int y, string help) {
        var d = new HelpDot { Location = new Point(x, y), Size = new Size(17, 17), Help = help, BackColor = Theme.Card };
        d.HoverChanged = ShowTip;
        parent.Controls.Add(d);
        return d;
    }

    public App(string folder, string scriptPath) {
        this.folder = folder ?? ".";
        this.scriptPath = string.IsNullOrEmpty(scriptPath) ? Path.Combine(this.folder, "CircleSnap.ps1") : scriptPath;
        settingsPath = Path.Combine(this.folder, "circlesnap-settings.txt");
        targetPngPath = Path.Combine(this.folder, "circlesnap-target.png");

        Text = Info.Name;
        try { Icon = Logo.MakeIcon(); } catch { }
        Font = new Font("Segoe UI", 9.5f);
        AutoScaleDimensions = new SizeF(96f, 96f);
        AutoScaleMode = AutoScaleMode.Dpi;
        FormBorderStyle = FormBorderStyle.None;
        BackColor = Theme.Bg; ForeColor = Theme.Txt;
        ClientSize = new Size(640, 540);
        StartPosition = FormStartPosition.CenterScreen;
        KeyPreview = true;

        // ---- custom title bar ----
        var bar = new Panel { Location = new Point(0, 0), Size = new Size(640, 40), BackColor = Theme.Title };
        Controls.Add(bar);
        var logo = new PictureBox { Image = Logo.Draw(48), Location = new Point(12, 9), Size = new Size(22, 22), SizeMode = PictureBoxSizeMode.Zoom, BackColor = Theme.Title };
        bar.Controls.Add(logo);
        var title = L(bar, Info.Name, 40, 10, 0, 0, Theme.Txt, 10.5f, true);
        L(bar, "v" + Info.Version, 40 + title.PreferredWidth + 2, 13, 0, 0, Theme.Faint, 8.5f, false);
        var minB = new TitleButton { Location = new Point(560, 0), Size = new Size(40, 40) };
        var closeB = new TitleButton { Location = new Point(600, 0), Size = new Size(40, 40), IsClose = true };
        minB.Click += (s, e) => WindowState = FormWindowState.Minimized;
        closeB.Click += (s, e) => Close();
        bar.Controls.Add(minB); bar.Controls.Add(closeB);
        MouseEventHandler drag = (s, e) => { if (e.Button == MouseButtons.Left) { Native.ReleaseCapture(); Native.SendMessage(Handle, 0xA1, (IntPtr)2, IntPtr.Zero); } };
        bar.MouseDown += drag; title.MouseDown += drag; logo.MouseDown += drag;

        // ---- sidebar ----
        var side = new Panel { Location = new Point(0, 40), Size = new Size(156, 500), BackColor = Theme.Side };
        Controls.Add(side);
        string[] names = { "Clicker", "Settings", "Update log" };
        navs = new NavItem[3];
        for (int i = 0; i < 3; i++) {
            int idx = i;
            navs[i] = new NavItem { Text = names[i], Icon = i, Location = new Point(10, 12 + i * 42), Size = new Size(136, 36),
                BackColor = Theme.Side, Font = new Font("Segoe UI", 9.5f, FontStyle.Bold) };
            navs[i].Click += (s, e) => ShowPage(idx);
            side.Controls.Add(navs[i]);
        }
        modLbl = L(side, "Modified copy", 14, 420, 130, 18, Theme.Halt, 8.5f, true); modLbl.Visible = false;
        repairBtn = Btn(side, "Repair", 1, 14, 440, 128, 28); repairBtn.Visible = false;
        repairBtn.Click += (s, e) => { if (pendingRepair != null) RunInstall(pendingRepair, true); };
        L(side, "F9 start  |  F10 stop", 14, 476, 0, 0, Theme.Faint, 8f, false).Name = "keyHint";

        // ---- content ----
        content = new Panel { Location = new Point(156, 40), Size = new Size(484, 500), BackColor = Theme.Bg };
        Controls.Add(content);
        banner = CardAt(content, 16, 12, 452, 50); banner.Fill = Theme.Warn; banner.Visible = false;
        bannerLbl = L(banner, "Update available", 14, 7, 280, 20, Color.FromArgb(25, 25, 25), 10f, true);
        bannerSub = L(banner, "", 14, 27, 290, 17, Color.FromArgb(70, 55, 15), 8.5f, false);
        bannerBtn = Btn(banner, "Update now", 2, 330, 10, 110, 30); bannerBtn.BackColor = Theme.Warn;
        bannerBtn.Click += (s, e) => { if (pendingUpdate != null) RunInstall(pendingUpdate, false); };

        pages = new Panel[3];
        for (int i = 0; i < 3; i++) {
            pages[i] = new Panel { Location = new Point(16, 12), Size = new Size(452, 476), BackColor = Theme.Bg, Visible = false };
            content.Controls.Add(pages[i]);
        }
        BuildClicker(pages[0]);
        BuildSettings(pages[1]);
        BuildLog(pages[2]);

        tip = new Card { Fill = Color.FromArgb(10, 11, 14), Border = Theme.Line, Radius = 8, Visible = false, Size = new Size(230, 60), BackColor = Theme.Bg };
        tipLbl = new Label { Location = new Point(10, 8), Size = new Size(210, 44), ForeColor = Theme.Txt, BackColor = Color.Transparent, Font = new Font("Segoe UI", 8.5f) };
        tip.Controls.Add(tipLbl);
        Controls.Add(tip);

        // ---- timers ----
        scanTimer = new System.Windows.Forms.Timer { Interval = 100 };
        scanTimer.Tick += (s, e) => { if (running && !busy && DateTime.Now >= nextScan) DoScan(true); };
        scanTimer.Start();
        keyTimer = new System.Windows.Forms.Timer { Interval = 40 };
        keyTimer.Tick += (s, e) => KeyTick();
        keyTimer.Start();
        learnTimer = new System.Windows.Forms.Timer { Interval = 1000 };
        learnTimer.Tick += (s, e) => LearnTick();
        updateTimer = new System.Windows.Forms.Timer { Interval = 60 * 1000 }; // live: checks every minute
        updateTimer.Tick += (s, e) => CheckForUpdate();

        Shown += (s, e) => {
            ActiveControl = null;
            var once = new System.Windows.Forms.Timer { Interval = 1200 };
            once.Tick += (s2, e2) => { once.Stop(); CheckForUpdate(); updateTimer.Start(); };
            once.Start();
        };
        FormClosing += (s, e) => { scanTimer.Stop(); keyTimer.Stop(); learnTimer.Stop(); updateTimer.Stop(); SaveSettings(); };

        SetTarget(target);
        ShowChangelog(Info.Changelog);
        LoadSettings();
        UpdateKeyLabels();
        ShowPage(0);
        SetStatus("IDLE", Theme.Dim, "Press START or your Start key");
        loaded = true;
        AddLog("ready  v" + Info.Version);
    }

    // ---------------- pages ----------------
    void BuildClicker(Panel p) {
        var sc = CardAt(p, 0, 0, 452, 74);
        var cap = L(sc, "STATUS:", 16, 14, 0, 0, Theme.Dim, 14f, true);
        statusWord = L(sc, "IDLE", 16 + cap.PreferredWidth, 14, 220, 30, Theme.Dim, 14f, true);
        statusSub = L(sc, "", 18, 46, 300, 18, Theme.Dim, 8.5f, false);
        countLbl = L(sc, "0", 340, 10, 96, 32, Theme.Txt, 17f, true); countLbl.TextAlign = ContentAlignment.MiddleRight;
        var cl = L(sc, "clicks", 340, 44, 96, 18, Theme.Dim, 8.5f, false); cl.TextAlign = ContentAlignment.MiddleRight;

        startBtn = Btn(p, "START", 0, 0, 88, 452, 58);
        startBtn.Radius = 14; startBtn.Font = new Font("Segoe UI", 13f, FontStyle.Bold); startBtn.ForeColor = Color.White;
        startBtn.Click += (s, e) => ToggleRunning("button");

        L(p, "LOGS", 2, 160, 0, 0, Theme.Faint, 8.5f, true);
        var lc = CardAt(p, 0, 180, 452, 296);
        log = new ListBox { Location = new Point(10, 10), Size = new Size(432, 276), BackColor = Theme.Card, ForeColor = Color.FromArgb(185, 190, 199),
            BorderStyle = BorderStyle.None, Font = new Font("Consolas", 9f), IntegralHeight = false, TabStop = false };
        lc.Controls.Add(log);
    }

    void BuildSettings(Panel p) {
        // keybinds
        L(p, "KEYBINDS", 2, 0, 0, 0, Theme.Faint, 8.5f, true);
        var kc = CardAt(p, 0, 20, 452, 92);
        var a = L(kc, "Start", 16, 15, 0, 0, Theme.Txt, 9.5f, false);
        Dot(kc, 16 + a.PreferredWidth + 6, 17, "Press this key anywhere (even in the game) to start clicking. Click the box, then press the key you want.");
        startKeyBtn = Btn(kc, "F9", 1, 316, 10, 120, 30);
        startKeyBtn.Click += (s, e) => BeginCapture(1);
        var b = L(kc, "Turn off", 16, 55, 0, 0, Theme.Txt, 9.5f, false);
        Dot(kc, 16 + b.PreferredWidth + 6, 57, "Press this key anywhere to stop clicking right away. If both keys are the same, it switches on and off.");
        stopKeyBtn = Btn(kc, "F10", 1, 316, 50, 120, 30);
        stopKeyBtn.Click += (s, e) => BeginCapture(2);

        // target
        L(p, "TARGET", 2, 124, 0, 0, Theme.Faint, 8.5f, true);
        var tc = CardAt(p, 0, 144, 452, 100);
        targetPic = new PictureBox { Location = new Point(14, 14), Size = new Size(72, 72), SizeMode = PictureBoxSizeMode.Zoom, BackColor = Theme.Bg };
        tc.Controls.Add(targetPic);
        targetName = L(tc, "", 100, 12, 300, 20, Theme.Txt, 10f, true);
        Dot(tc, 420, 14, "The circle CircleSnap clicks. Press Learn target, then hover the circle in your game for 3 seconds. Test shows a red box around what it finds without clicking.");
        targetInfo = L(tc, "", 100, 34, 330, 18, Theme.Dim, 8.5f, false);
        learnBtn = Btn(tc, "Learn target", 0, 100, 58, 120, 30);
        learnBtn.Click += (s, e) => StartLearn();
        testBtn = Btn(tc, "Test", 1, 228, 58, 80, 30);
        testBtn.Click += (s, e) => DoScan(false);
        resetBtn = Btn(tc, "Reset", 1, 316, 58, 80, 30);
        resetBtn.Click += (s, e) => { SetTarget(new Target()); try { File.Delete(targetPngPath); } catch { } SaveSettings(); AddLog("target reset to built-in x2"); };

        // clicking
        L(p, "CLICKING", 2, 256, 0, 0, Theme.Faint, 8.5f, true);
        var cc = CardAt(p, 0, 276, 452, 132);
        var d1 = L(cc, "Delay after click", 16, 15, 0, 0, Theme.Txt, 9.5f, false);
        Dot(cc, 16 + d1.PreferredWidth + 6, 17, "How many seconds to wait after a click before looking for the next circle.");
        minusBtn = Btn(cc, "-", 1, 340, 9, 30, 28);
        delayVal = L(cc, "3s", 372, 9, 34, 28, Theme.Txt, 10f, true); delayVal.TextAlign = ContentAlignment.MiddleCenter;
        plusBtn = Btn(cc, "+", 1, 408, 9, 30, 28);
        minusBtn.Click += (s, e) => SetDelay(delay - 1);
        plusBtn.Click += (s, e) => SetDelay(delay + 1);
        var d2 = L(cc, "Human movement", 16, 56, 0, 0, Theme.Txt, 9.5f, false);
        Dot(cc, 16 + d2.PreferredWidth + 6, 58, "Moves the mouse in a natural curve with changing speed and lands a little off-center, like a person, instead of gliding straight to the circle.");
        humanTgl = new Toggle { Location = new Point(394, 53), Size = new Size(44, 24), BackColor = Theme.Card };
        humanTgl.Changed += (s, e) => SaveSettings();
        cc.Controls.Add(humanTgl);
        var d3 = L(cc, "Always on top", 16, 97, 0, 0, Theme.Txt, 9.5f, false);
        Dot(cc, 16 + d3.PreferredWidth + 6, 99, "Keeps this window above the game so you can always see it. Don't let it cover the circle.");
        topTgl = new Toggle { Location = new Point(394, 94), Size = new Size(44, 24), BackColor = Theme.Card };
        topTgl.Changed += (s, e) => { TopMost = topTgl.On; SaveSettings(); };
        cc.Controls.Add(topTgl);

        // coming soon
        var mc = CardAt(p, 0, 420, 452, 42);
        mc.Fill = Color.FromArgb(27, 28, 33);
        var soon = L(mc, "More coming soon", 16, 11, 0, 0, Theme.Faint, 9.5f, false);
        mc.Controls.Add(new Smiley { Location = new Point(16 + soon.PreferredWidth + 2, 12), Size = new Size(17, 17), BackColor = mc.Fill });
    }

    void BuildLog(Panel p) {
        var c = CardAt(p, 0, 0, 452, 450);
        changelogBox = new RichTextBox { Location = new Point(14, 12), Size = new Size(424, 426), BackColor = Theme.Card, ForeColor = Theme.Txt,
            BorderStyle = BorderStyle.None, ReadOnly = true, Font = new Font("Segoe UI", 9.5f), TabStop = false, DetectUrls = false };
        c.Controls.Add(changelogBox);
        changelogSrc = L(p, "Built-in notes", 2, 456, 400, 18, Theme.Faint, 8.5f, false);
    }

    void ShowPage(int i) {
        for (int j = 0; j < pages.Length; j++) { pages[j].Visible = j == i; navs[j].Selected = j == i; navs[j].Invalidate(); }
        tip.Visible = false;
    }

    // ---------------- help tooltips ----------------
    void ShowTip(HelpDot d, bool show) {
        if (!show) { tip.Visible = false; return; }
        float k = DeviceDpiScale();
        int w = (int)(230 * k), pad = (int)(10 * k);
        Size ts = TextRenderer.MeasureText(d.Help, tipLbl.Font, new Size(w - 2 * pad, 1000), TextFormatFlags.WordBreak);
        tip.Size = new Size(w, ts.Height + 2 * pad);
        tipLbl.Location = new Point(pad, pad); tipLbl.Size = new Size(w - 2 * pad, ts.Height + 2);
        tipLbl.Text = d.Help;
        Point at = PointToClient(d.Parent.PointToScreen(d.Location));
        int x = at.X + d.Width + (int)(8 * k), y = at.Y - (tip.Height - d.Height) / 2;
        if (x + tip.Width > ClientSize.Width - 4) x = at.X - tip.Width - (int)(8 * k);
        y = Math.Max((int)(44 * k), Math.Min(y, ClientSize.Height - tip.Height - 4));
        tip.Location = new Point(x, y);
        tip.Visible = true; tip.BringToFront();
    }
    float DeviceDpiScale() { using (var g = CreateGraphics()) return g.DpiX / 96f; }

    // ---------------- status / log ----------------
    void SetStatus(string word, Color c, string sub) { statusWord.Text = word; statusWord.ForeColor = c; statusSub.Text = sub; }

    void AddLog(string msg) {
        log.Items.Insert(0, DateTime.Now.ToString("HH:mm:ss") + "  " + msg);
        while (log.Items.Count > 300) log.Items.RemoveAt(log.Items.Count - 1);
    }

    void SetDelay(int v) { delay = Math.Max(1, Math.Min(60, v)); delayVal.Text = delay + "s"; SaveSettings(); }

    // ---------------- keybinds ----------------
    static string KeyName(int vk) {
        string s = ((Keys)vk).ToString();
        if (s.StartsWith("D") && s.Length == 2 && char.IsDigit(s[1])) s = s.Substring(1);
        if (s.StartsWith("Oem")) s = s.Substring(3);
        return s;
    }

    void UpdateKeyLabels() {
        startKeyBtn.Text = capturing == 1 ? "Press a key..." : KeyName(startKey);
        stopKeyBtn.Text = capturing == 2 ? "Press a key..." : KeyName(stopKey);
        var hint = Controls.Find("keyHint", true);
        if (hint.Length > 0) hint[0].Text = KeyName(startKey) + " start  |  " + KeyName(stopKey) + " stop";
    }

    void BeginCapture(int which) { capturing = which; UpdateKeyLabels(); }

    void KeyTick() {
        for (int vk = 8; vk < 255; vk++) {
            if (vk >= 1 && vk <= 6) continue;
            bool down = Native.KeyDown(vk);
            bool pressed = down && !keyWas[vk];
            keyWas[vk] = down;
            if (!pressed) continue;
            if (capturing != 0) {
                if (vk == 0x10 || vk == 0x11 || vk == 0x12) continue; // wait for the specific L/R key
                if (vk != 0x1B) { if (capturing == 1) startKey = vk; else stopKey = vk; AddLog("keybind  " + (capturing == 1 ? "start" : "turn off") + " = " + KeyName(vk)); }
                capturing = 0; UpdateKeyLabels(); SaveSettings();
                return;
            }
            if (vk == startKey && vk == stopKey) ToggleRunning(KeyName(vk));
            else if (vk == startKey && !running) ToggleRunning(KeyName(vk));
            else if (vk == stopKey && running) ToggleRunning(KeyName(vk));
        }
    }

    // ---------------- target ----------------
    static Bitmap BuiltInPicture() {
        var b = new Bitmap(72, 72);
        using (var g = Graphics.FromImage(b)) {
            g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
            using (var br = new SolidBrush(Color.FromArgb(165, 95, 235))) g.FillEllipse(br, 4, 4, 64, 64);
            using (var f = new Font("Arial", 22, FontStyle.Bold, GraphicsUnit.Pixel)) {
                var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
                g.DrawString("x2", f, Brushes.White, new RectangleF(4, 4, 64, 64), sf);
            }
        }
        return b;
    }

    void SetTarget(Target t) {
        target = t;
        targetPic.Image = t.BuiltIn ? BuiltInPicture() : t.Picture;
        targetName.Text = t.Name;
        targetInfo.Text = t.Describe();
        resetBtn.Enabled = !t.BuiltIn;
    }

    Rectangle MyAreaIn(Rectangle vs) {
        if (WindowState == FormWindowState.Minimized) return Rectangle.Empty;
        var b = Bounds; b.Offset(-vs.Left, -vs.Top); return b;
    }

    // ---------------- start / stop ----------------
    void ToggleRunning(string by) {
        running = !running;
        if (running) {
            startBtn.Text = "STOP";
            nextScan = DateTime.Now;
            SetStatus("RUNNING", Theme.Go, "Watching for the target");
            AddLog("started (" + by + ")");
        } else {
            startBtn.Text = "START";
            SetStatus("IDLE", Theme.Dim, "Press START or your Start key");
            AddLog("stopped (" + by + ")");
        }
    }

    // ---------------- scanning ----------------
    void DoScan(bool click) {
        Rectangle vs = Native.VirtualScreen;
        List<Hit> hits;
        var sw = Stopwatch.StartNew();
        using (var shot = Native.GrabAll()) hits = Detector.Find(shot, MyAreaIn(vs), target);
        long ms = sw.ElapsedMilliseconds;
        Hit best = hits.Count > 0 ? hits[0] : null;
        Point c = best != null ? new Point(best.Center.X + vs.Left, best.Center.Y + vs.Top) : Point.Empty;

        if (!click) {
            if (best != null) {
                var box = best.Box; box.Offset(vs.Left, vs.Top);
                new Flash(box).Show();
                AddLog("test  found " + hits.Count + "  best (" + c.X + ", " + c.Y + ")  score " + best.Score.ToString("0.00") + "  " + ms + "ms");
            } else AddLog("test  nothing found  " + ms + "ms");
            return;
        }
        if (best == null) {
            SetStatus("RUNNING", Theme.Go, "Watching for the target");
            nextScan = DateTime.Now.AddMilliseconds(350);
            return;
        }
        bool again = Math.Abs(c.X - lastClickPos.X) < 15 && Math.Abs(c.Y - lastClickPos.Y) < 15 && (DateTime.Now - lastClickTime).TotalSeconds < delay + 2;
        SetStatus("CLICKING", Theme.Info, "Clicking at " + c.X + ", " + c.Y);
        statusWord.Refresh();
        string note = Mouse.Click(c.X, c.Y, Math.Min(best.Box.Width, best.Box.Height) / 2, humanTgl.On);
        clicks++; countLbl.Text = clicks.ToString();
        lastClickPos = c; lastClickTime = DateTime.Now;
        AddLog((again ? "click again" : "click") + "  (" + c.X + ", " + c.Y + ")  score " + best.Score.ToString("0.00")
               + (humanTgl.On ? "  human" : "") + (note != null ? "  " + note : ""));
        SetStatus("RUNNING", Theme.Go, "Clicked - waiting " + delay + "s for the next one");
        nextScan = DateTime.Now.AddSeconds(delay);
    }

    // ---------------- learning ----------------
    void StartLearn() {
        learnCountdown = 3;
        SetStatus("LEARNING", Theme.Warn, "Hover the circle and hold still  3");
        learnTimer.Start();
    }

    void LearnTick() {
        learnCountdown--;
        if (learnCountdown > 0) { statusSub.Text = "Hover the circle and hold still  " + learnCountdown; return; }
        learnTimer.Stop();
        Point p = Native.Cursor();
        string err = null; Target t = null;
        if (Bounds.Contains(p)) err = "the cursor was on this window";
        else { try { t = Learner.Learn(p, out err); } catch (Exception ex) { err = ex.Message; } }
        RestoreStatus();
        if (t == null) { AddLog("learn  failed: " + err); return; }
        SetTarget(t);
        SaveSettings();
        AddLog("learn  " + t.Describe());
    }

    void RestoreStatus() {
        if (running) SetStatus("RUNNING", Theme.Go, "Watching for the target");
        else SetStatus("IDLE", Theme.Dim, "Press START or your Start key");
    }

    // ---------------- updates (live) ----------------
    string UpdateUrl() {
        try {
            string f = Path.Combine(folder, "update-url.txt");
            if (File.Exists(f)) { string s = File.ReadAllText(f).Trim(); if (s.Length > 0) return s; }
        } catch { }
        return Info.DefaultUpdateUrl;
    }

    void CheckForUpdate() {
        if (busy) return;
        string baseUrl = UpdateUrl();
        if (string.IsNullOrEmpty(baseUrl)) return;
        if (!baseUrl.EndsWith("/")) baseUrl += "/";
        var th = new Thread(() => {
            try {
                Release r = Updater.Fetch(baseUrl);
                int cmp = new Version(r.Version).CompareTo(new Version(Info.Version));
                List<string> bad = cmp == 0 ? Updater.Modified(r, folder) : null;
                string notes = null;
                try { notes = Updater.FetchText(baseUrl, "changelog.txt"); } catch { }
                BeginInvoke((Action)(() => {
                    if (!string.IsNullOrEmpty(notes)) { ShowChangelog(notes); changelogSrc.Text = "Latest notes from the internet"; }
                    if (cmp > 0) {
                        if (pendingUpdate == null || pendingUpdate.Version != r.Version) AddLog("update available  v" + r.Version);
                        pendingUpdate = r; ShowBanner(r);
                    }
                    if (bad != null) {
                        bool modified = bad.Count > 0;
                        if (modified && pendingRepair == null) AddLog("warning: this copy doesn't match the official release (" + string.Join(", ", bad.ToArray()) + ")");
                        pendingRepair = modified ? r : null;
                        modLbl.Visible = modified; repairBtn.Visible = modified;
                    }
                }));
            } catch (Exception ex) {
                string m = ex.Message;
                try { BeginInvoke((Action)(() => { if (m.Contains("signed")) AddLog("security: " + m); })); } catch { }
            }
        });
        th.IsBackground = true; th.Start();
    }

    void ShowBanner(Release r) {
        bannerLbl.Text = "Update available: v" + r.Version;
        bannerSub.Text = string.IsNullOrEmpty(r.Notes) ? "See Update log for what's new" : r.Notes;
        if (banner.Visible) return;
        banner.Visible = true;
        int shift = banner.Height + (int)(banner.Height * 10 / 50.0);
        foreach (var pg in pages) pg.Top += shift;
        Height += shift; content.Height += shift;
        foreach (Control c in Controls) if (c is Panel && c.Left == 0 && c.Top > 0 && c != content) c.Height += shift;
        Native.FlashWindow(Handle, true);
    }

    void RunInstall(Release r, bool repair) {
        if (busy) return;
        busy = true;
        if (running) ToggleRunning("update");
        SetStatus("UPDATING", Theme.Cyan, repair ? "Repairing files" : "Installing v" + r.Version);
        SaveSettings();
        var uf = new UpdateForm(r.Version, repair);
        uf.Shown += (s, e) => {
            var th = new Thread(() => {
                try {
                    Updater.Install(r, folder, (pct, text) => uf.BeginInvoke((Action)(() => uf.SetProgress(pct, text))));
                    uf.BeginInvoke((Action)(() => uf.SetProgress(100, "Restarting")));
                    Thread.Sleep(700);
                    BeginInvoke((Action)(() => { Relaunch(); Application.Exit(); }));
                } catch (Exception ex) {
                    string m = ex.Message;
                    uf.BeginInvoke((Action)(() => uf.Fail("Update failed: " + m)));
                    BeginInvoke((Action)(() => { busy = false; RestoreStatus(); AddLog("update failed: " + m); }));
                }
            });
            th.IsBackground = true; th.Start();
        };
        uf.ShowDialog(this);
    }

    void Relaunch() {
        var psi = new ProcessStartInfo("powershell.exe", "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + scriptPath + "\"");
        psi.UseShellExecute = false; psi.CreateNoWindow = true;
        Process.Start(psi);
    }

    void ShowChangelog(string text) {
        changelogBox.Clear();
        foreach (var raw in text.Replace("\r", "").Split('\n')) {
            string line = raw.TrimEnd();
            bool head = line.StartsWith("v") && line.Length > 1 && char.IsDigit(line[1]);
            changelogBox.SelectionFont = head ? new Font("Segoe UI", 11f, FontStyle.Bold) : new Font("Segoe UI", 9.5f);
            changelogBox.SelectionColor = head ? Theme.Txt : Color.FromArgb(185, 190, 199);
            if (head && line.TrimStart('v').StartsWith(Info.Version)) line += "   (you have this)";
            changelogBox.AppendText((line.StartsWith("- ") ? "  " + (char)0x2022 + " " + line.Substring(2) : line) + "\n");
        }
        changelogBox.SelectionStart = 0; changelogBox.ScrollToCaret();
    }

    // ---------------- settings ----------------
    void LoadSettings() {
        try {
            if (!File.Exists(settingsPath)) return;
            var d = new Dictionary<string, string>();
            foreach (var line in File.ReadAllLines(settingsPath)) {
                int eq = line.IndexOf('=');
                if (eq > 0) d[line.Substring(0, eq)] = line.Substring(eq + 1);
            }
            string v;
            if (d.TryGetValue("cooldown", out v)) SetDelay(int.Parse(v));
            if (d.TryGetValue("human", out v)) humanTgl.On = v == "1";
            if (d.TryGetValue("top", out v)) topTgl.On = v == "1";
            if (d.TryGetValue("startKey", out v)) startKey = int.Parse(v);
            if (d.TryGetValue("stopKey", out v)) stopKey = int.Parse(v);
            if (d.TryGetValue("window", out v)) {
                var xy = v.Split(',');
                var pos = new Point(int.Parse(xy[0]), int.Parse(xy[1]));
                if (Screen.FromPoint(pos).WorkingArea.Contains(pos)) { StartPosition = FormStartPosition.Manual; Location = pos; }
            }
            if (d.TryGetValue("target", out v) && v == "learned" && File.Exists(targetPngPath)) {
                Bitmap pic;
                using (var tmp = new Bitmap(targetPngPath)) pic = new Bitmap(tmp);
                SetTarget(Target.Load(d, pic));
            }
        } catch (Exception ex) { AddLog("settings: " + ex.Message); }
    }

    void SaveSettings() {
        if (!loaded) return;
        try {
            var pos = WindowState == FormWindowState.Normal ? Location : RestoreBounds.Location;
            var o = new List<string> {
                "cooldown=" + delay, "human=" + (humanTgl.On ? 1 : 0), "top=" + (topTgl.On ? 1 : 0),
                "startKey=" + startKey, "stopKey=" + stopKey, "window=" + pos.X + "," + pos.Y };
            if (!target.BuiltIn) { target.Save(o); target.Picture.Save(targetPngPath, ImageFormat.Png); }
            File.WriteAllLines(settingsPath, o.ToArray());
        } catch { }
    }
}
}
'@
}

if (-not $NoRun) {
    try {
        [TwoX.App]::Run($PSScriptRoot, $PSCommandPath)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("CircleSnap hit an error:`n`n$($_.Exception.Message)", "CircleSnap") | Out-Null
    }
}
