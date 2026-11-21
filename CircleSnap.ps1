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
using System.Threading;
using System.Windows.Forms;

namespace TwoX {

public static class Info {
    public const string Name = "CircleSnap";
    public const string Version = "1.2.0";
    // Web folder that holds latest.txt + the app files (see make-release.ps1).
    // An "update-url.txt" file next to the app overrides this.
    public const string DefaultUpdateUrl = "https://raw.githubusercontent.com/morriz-123/CircleSnap/main/";
    // Shown in the Update log tab when there's no internet (the online changelog.txt replaces it).
    public const string Changelog =
        "v1.2.0\n" +
        "- New name and logo: CircleSnap\n" +
        "- Update log tab\n" +
        "- Big banner when a new version is out\n" +
        "\n" +
        "v1.1.0\n" +
        "- Learn target: hover any circle to teach it (works in other games)\n" +
        "- Test shows a red box around what it found\n" +
        "- Human movement option\n" +
        "- Scans all monitors\n" +
        "- New dark look and Logs\n" +
        "\n" +
        "v1.0.0\n" +
        "- First version: finds and clicks the purple x2\n";
}

// The app logo: a target ring with a dot, on a teal tile.
public static class Logo {
    public static Bitmap Draw(int size) {
        var b = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(b)) {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);
            float r = size * 0.24f;
            using (var path = new GraphicsPath()) {
                path.AddArc(0, 0, r * 2, r * 2, 180, 90);
                path.AddArc(size - r * 2 - 1, 0, r * 2, r * 2, 270, 90);
                path.AddArc(size - r * 2 - 1, size - r * 2 - 1, r * 2, r * 2, 0, 90);
                path.AddArc(0, size - r * 2 - 1, r * 2, r * 2, 90, 90);
                path.CloseFigure();
                using (var br = new LinearGradientBrush(new Rectangle(0, 0, size, size),
                        Color.FromArgb(32, 201, 151), Color.FromArgb(24, 119, 242), 45f))
                    g.FillPath(br, path);
            }
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

public static class Theme {
    public static readonly Color Bg    = Color.FromArgb(23, 24, 27);
    public static readonly Color Card  = Color.FromArgb(34, 35, 39);
    public static readonly Color Line  = Color.FromArgb(48, 50, 56);
    public static readonly Color Txt   = Color.FromArgb(230, 230, 232);
    public static readonly Color Dim   = Color.FromArgb(139, 143, 152);
    public static readonly Color Go    = Color.FromArgb(59, 165, 93);
    public static readonly Color Halt  = Color.FromArgb(222, 72, 72);
    public static readonly Color Act   = Color.FromArgb(70, 118, 200);
    public static readonly Color Warn  = Color.FromArgb(240, 178, 50);
    public static readonly Color Btn   = Color.FromArgb(52, 54, 60);
    public static readonly Color LogBg = Color.FromArgb(15, 16, 18);
    public static readonly Color LogTx = Color.FromArgb(181, 186, 193);
}

// ======================= screen + keyboard =======================
public static class Native {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }

    public static bool KeyDown(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }
    public static Point Cursor() { POINT p; GetCursorPos(out p); return new Point(p.X, p.Y); }

    // All monitors together.
    public static Rectangle VirtualScreen { get { return SystemInformation.VirtualScreen; } }

    public static Bitmap Grab(Rectangle r) {
        var bmp = new Bitmap(r.Width, r.Height, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(r.Left, r.Top, 0, 0, r.Size);
        return bmp;
    }
    public static Bitmap GrabAll() { return Grab(VirtualScreen); }
}

// ======================= mouse =======================
public static class Mouse {
    // Real input events (SendInput). Roblox reads raw mouse input, which a plain
    // cursor teleport doesn't create, so we move the mouse like a real one.
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
        keybd_event(0x12, 0, 0, UIntPtr.Zero); keybd_event(0x12, 0, 2, UIntPtr.Zero); // Alt tap allows the switch
        SetForegroundWindow(win);
        Thread.Sleep(150);
        return true;
    }

    static void FastMove(int x, int y) {
        MoveTo(x - 12, y - 12); Thread.Sleep(20);
        for (int i = 0; i < 6; i++) { Send(MOVE, 2, 2); Thread.Sleep(8); }
        MoveTo(x, y); Thread.Sleep(30);
    }

    // Curved path, speeds up then slows down, slight shake, small overshoot.
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
            int due = (int)(ms * t) + rng.Next(-2, 3);
            int wait = due - (int)sw.ElapsedMilliseconds;
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

    // Returns a short note for the log, or null.
    public static string Click(int x, int y, int radius, bool human) {
        timeBeginPeriod(1);
        try {
            bool focused = FocusWindowAt(x, y);
            if (human && radius > 6) { // people don't hit the exact center
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
// ======================= colour helpers =======================
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
    // 1.0 = identical, 0 = nothing alike. Only compares the inside of the circle.
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

// ======================= what we're looking for =======================
public class Target {
    public string Name = "Purple x2 (built-in)";
    public bool BuiltIn = true;
    public bool UseHue = true;
    public double Hue = 275, HueRange = 30, MinSat = 0.18, MinVal = 0.22, StrongSat = 0.35;
    public int R, G, B; public double RgbTol = 50;
    public int MinSize = 34, MaxSize = 400, Diameter;
    public bool NeedInner = true, Round = true;
    public float[] Sig;            // null = no look check
    public double MinScore = 0.62;
    public Bitmap Picture;
    public Color Shown = Color.FromArgb(160, 90, 235);

    // 0 = no, 1 = weak match (pale/shine), 2 = strong match
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
        if (BuiltIn) return "Hover a circle in your game and press Learn target to use a different one.";
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

// ======================= finding circles =======================
public static class Detector {
    public static System.Text.StringBuilder Debug; // set by tests to see why shapes were rejected

    public static int[] Pixels(Bitmap b) {
        var d = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        var arr = new int[b.Width * b.Height];
        Marshal.Copy(d.Scan0, arr, 0, arr.Length);
        b.UnlockBits(d);
        return arr;
    }

    // All matches, best first. 'exclude' (in bitmap coordinates) is skipped.
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
                if (aspect < 0.75 || aspect > 1.33) { if (dbg != null) Debug.AppendLine(dbg + "aspect " + aspect.ToString("0.00")); continue; }
                double fill = count / (double)(bw * bh);
                if (fill < 0.35 || fill > 0.90) { if (dbg != null) Debug.AppendLine(dbg + "fill " + fill.ToString("0.00")); continue; }
                // solid ring near the edge
                double ccx = (minx + maxx) / 2.0, ccy = (miny + maxy) / 2.0, rx = bw / 2.0, ry = bh / 2.0;
                int ringOn = 0; const int RING = 72;
                for (int k = 0; k < RING; k++) {
                    double a = k * 2 * Math.PI / RING;
                    int x = (int)Math.Round(ccx + Math.Cos(a) * rx * 0.80), y = (int)Math.Round(ccy + Math.Sin(a) * ry * 0.80);
                    if (x >= 0 && x < mw && y >= 0 && y < mh && mask[y * mw + x]) ringOn++;
                }
                if (ringOn < RING * 0.75) { if (dbg != null) Debug.AppendLine(dbg + "ring " + ringOn + "/" + RING); continue; }
                // nothing strongly coloured outside the circle
                int outAll = 0, outOn = 0;
                for (int y = miny; y <= maxy; y++)
                    for (int x = minx; x <= maxx; x++) {
                        double nx = (x - ccx) / rx, ny = (y - ccy) / ry;
                        if (nx * nx + ny * ny > 1.15 * 1.15) { outAll++; if (strong[y * mw + x]) outOn++; }
                    }
                if (outAll > 0 && outOn > outAll * 0.15) { if (dbg != null) Debug.AppendLine(dbg + "outside " + outOn + "/" + outAll); continue; }
                score = ringOn / (double)RING;
            }
            if (t.NeedInner) {
                int inAll = 0, inOff = 0;
                for (int y = miny + bh / 4; y <= maxy - bh / 4; y++)
                    for (int x = minx + bw / 4; x <= maxx - bw / 4; x++) { inAll++; if (!mask[y * mw + x]) inOff++; }
                if (inAll == 0 || inOff < inAll * 0.06) { if (dbg != null) Debug.AppendLine(dbg + "no detail inside"); continue; }
            }
            var box = new Rectangle(minx * S, miny * S, bw * S, bh * S);
            if (t.Sig != null) {
                score = global::TwoX.Sig.Compare(global::TwoX.Sig.Of(bmp, box), t.Sig);
                if (score < t.MinScore) { if (dbg != null) Debug.AppendLine(dbg + "looks different, score " + score.ToString("0.00")); continue; }
            }
            if (dbg != null) Debug.AppendLine(dbg + "MATCH " + score.ToString("0.00"));
            hits.Add(new Hit { Box = box, Score = score });
        }
        hits.Sort((a, b) => b.Score.CompareTo(a.Score));
        return hits;
    }
}

// ======================= learning a circle from the cursor =======================
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

        // 1. main colour around the cursor
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

        // 2. the shape under the cursor
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
        if (minx == 0 || miny == 0 || maxx == W - 1 || maxy == H - 1) {
            error = "that colour spreads into the background - is the cursor on the circle?"; return null;
        }

        // 3. tighten the colour rules to this exact circle
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

        // 4. is it round? does it have something inside (text/icon)?
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
// ======================= updates =======================
public class Release {
    public string Version, Notes, BaseUrl;
    public List<string[]> Files = new List<string[]>(); // { name, sha256 }
}

public static class Updater {
    static WebClient Client() {
        ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; // TLS 1.2
        var wc = new WebClient();
        wc.Headers[HttpRequestHeader.UserAgent] = "circlesnap-updater";
        wc.Headers[HttpRequestHeader.CacheControl] = "no-cache";
        return wc;
    }
    static string Bust() { return "?t=" + DateTime.UtcNow.Ticks; }

    public static Release Fetch(string baseUrl) {
        string text;
        using (var wc = Client()) text = wc.DownloadString(baseUrl + "latest.txt" + Bust());
        var r = new Release { BaseUrl = baseUrl };
        foreach (var raw in text.Split('\n')) {
            string line = raw.Trim(); int eq = line.IndexOf('=');
            if (eq <= 0) continue;
            string k = line.Substring(0, eq).Trim(), v = line.Substring(eq + 1).Trim();
            if (k == "version") r.Version = v;
            else if (k == "notes") r.Notes = v;
            else if (k == "file") {
                var parts = v.Split('|');
                string name = parts[0].Trim();
                if (name.Length == 0 || name.Contains("/") || name.Contains("\\") || name.Contains("..") || name.Contains(":"))
                    throw new Exception("bad file name in latest.txt: " + name);
                r.Files.Add(new string[] { name, parts.Length > 1 ? parts[1].Trim().ToLowerInvariant() : "" });
            }
        }
        if (r.Version == null || r.Files.Count == 0) throw new Exception("latest.txt is incomplete");
        new Version(r.Version); // throws if not a version number
        return r;
    }

    // Checksum that ignores line endings and trailing blank lines, so files
    // edited/stored on GitHub (which may switch CRLF/LF) still match.
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
                    if (hash.Length > 0 && Sha256(dst) != hash) throw new Exception(name + " didn't download correctly (checksum)");
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

public class UpdateForm : Form {
    Label step; Panel track, fill; Button closeBtn;
    public UpdateForm(string version) {
        FormBorderStyle = FormBorderStyle.None; StartPosition = FormStartPosition.CenterParent;
        AutoScaleDimensions = new SizeF(96f, 96f); AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(380, 150); BackColor = Theme.Bg; ShowInTaskbar = false; Font = new Font("Segoe UI", 10f);
        Controls.Add(new Label { Text = "Updating to v" + version, Font = new Font("Segoe UI", 13f, FontStyle.Bold),
            ForeColor = Theme.Txt, Location = new Point(20, 18), AutoSize = true });
        step = new Label { Text = "Starting", ForeColor = Theme.Dim, Location = new Point(20, 56), Size = new Size(340, 40) };
        track = new Panel { Location = new Point(20, 100), Size = new Size(340, 6), BackColor = Theme.Line };
        fill = new Panel { Location = new Point(0, 0), Size = new Size(0, 6), BackColor = Theme.Go };
        track.Controls.Add(fill);
        closeBtn = new Button { Text = "Close", Location = new Point(280, 114), Size = new Size(80, 28), BackColor = Theme.Btn,
            ForeColor = Theme.Txt, FlatStyle = FlatStyle.Flat, Visible = false };
        closeBtn.FlatAppearance.BorderSize = 0;
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

// Red box shown for a moment around what Test found. Click-through.
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
        get { var cp = base.CreateParams; cp.ExStyle |= 0x20 | 0x80 | 0x08000000; return cp; } // transparent, toolwindow, noactivate
    }
    protected override void OnPaint(PaintEventArgs e) {
        using (var p = new Pen(Color.FromArgb(255, 60, 60), 4)) e.Graphics.DrawRectangle(p, 2, 2, Width - 5, Height - 5);
    }
}

// ======================= the main window =======================
public class App : Form {
    readonly string folder, scriptPath, settingsPath, targetPngPath;
    Target target = new Target();
    Button startBtn, learnBtn, testBtn, resetBtn, bannerBtn, tabMain, tabLog;
    Label statusLbl, subLbl, countLbl, targetName, targetInfo, bannerLbl, bannerSub, changelogSrc;
    Panel banner, pageMain, pageLog, tabLine;
    RichTextBox changelogBox;
    PictureBox targetPic;
    NumericUpDown delayBox;
    CheckBox humanBox, topBox;
    ListBox log;
    System.Windows.Forms.Timer scanTimer, keyTimer, learnTimer, updateTimer;
    bool running, f9Was, loaded;
    int clicks, learnCountdown;
    DateTime nextScan = DateTime.MinValue, lastClickTime = DateTime.MinValue;
    Point lastClickPos;
    Release pendingUpdate;

    public static void Run(string folder, string scriptPath) {
        Native.SetProcessDPIAware();
        Application.EnableVisualStyles();
        Application.Run(new App(folder, scriptPath));
    }

    Label L(string text, int x, int y, int w, int h, Color c, float size, bool bold) {
        var l = new Label { Text = text, Location = new Point(x, y), ForeColor = c, BackColor = Color.Transparent,
            Font = new Font("Segoe UI", size, bold ? FontStyle.Bold : FontStyle.Regular) };
        if (w > 0) l.Size = new Size(w, h); else l.AutoSize = true;
        return l;
    }
    Button B(string text, int x, int y, int w, int h, Color back) {
        var b = new Button { Text = text, Location = new Point(x, y), Size = new Size(w, h), BackColor = back,
            ForeColor = Theme.Txt, FlatStyle = FlatStyle.Flat, Cursor = Cursors.Hand, TabStop = false };
        b.FlatAppearance.BorderSize = 0;
        b.FlatAppearance.MouseOverBackColor = ControlPaint.Light(back, 0.15f);
        return b;
    }
    Button Tab(string text, int x, int w) {
        var b = B(text, x, 56, w, 30, Theme.Bg);
        b.FlatAppearance.MouseOverBackColor = Theme.Card;
        b.Font = new Font("Segoe UI", 9.5f, FontStyle.Bold);
        return b;
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
        FormBorderStyle = FormBorderStyle.FixedSingle; MaximizeBox = false;
        BackColor = Theme.Bg; ForeColor = Theme.Txt;
        ClientSize = new Size(420, 646);
        StartPosition = FormStartPosition.CenterScreen;

        // ---- header: logo + name + version ----
        Controls.Add(new PictureBox { Image = Logo.Draw(60), Location = new Point(16, 12), Size = new Size(32, 32),
            SizeMode = PictureBoxSizeMode.Zoom, BackColor = Color.Transparent });
        var title = L(Info.Name, 54, 11, 0, 0, Theme.Txt, 15f, true);
        Controls.Add(title);
        Controls.Add(L("v" + Info.Version, 54 + title.PreferredWidth + 2, 21, 0, 0, Theme.Dim, 9f, false));

        // ---- tabs ----
        tabMain = Tab("Clicker", 12, 84);
        tabLog = Tab("Update log", 98, 104);
        tabMain.Click += (s, e) => ShowTab(true);
        tabLog.Click += (s, e) => ShowTab(false);
        tabLine = new Panel { BackColor = Theme.Act, Size = new Size(84, 2), Location = new Point(12, 86) };
        Controls.Add(tabMain); Controls.Add(tabLog); Controls.Add(tabLine);
        Controls.Add(new Panel { BackColor = Theme.Line, Location = new Point(16, 88), Size = new Size(388, 1) });

        // ---- update banner (hidden until an update is found) ----
        banner = new Panel { Location = new Point(16, 96), Size = new Size(388, 52), BackColor = Theme.Warn, Visible = false };
        bannerLbl = L("Update available", 12, 7, 250, 20, Color.FromArgb(25, 25, 25), 10.5f, true);
        bannerSub = L("", 12, 28, 250, 18, Color.FromArgb(60, 50, 20), 8.5f, false);
        bannerBtn = B("Update now", 270, 11, 106, 30, Color.FromArgb(28, 29, 32));
        bannerBtn.Font = new Font("Segoe UI", 9.5f, FontStyle.Bold);
        bannerBtn.Click += (s, e) => StartUpdate();
        banner.Controls.AddRange(new Control[] { bannerLbl, bannerSub, bannerBtn });
        Controls.Add(banner);

        // ---- page 1: clicker ----
        pageMain = new Panel { Location = new Point(0, 96), Size = new Size(420, 550), BackColor = Theme.Bg };
        Controls.Add(pageMain);
        var P = pageMain.Controls;

        var card = new Panel { Location = new Point(16, 4), Size = new Size(388, 62), BackColor = Theme.Card };
        statusLbl = L("Idle", 12, 9, 270, 22, Theme.Dim, 11.5f, true);
        subLbl = L("Press START or F9", 12, 35, 270, 18, Theme.Dim, 9f, false);
        countLbl = L("0", 276, 3, 100, 34, Theme.Txt, 18f, true); countLbl.TextAlign = ContentAlignment.MiddleRight;
        var cap = L("clicks", 276, 37, 100, 18, Theme.Dim, 8.5f, false); cap.TextAlign = ContentAlignment.MiddleRight;
        card.Controls.AddRange(new Control[] { statusLbl, subLbl, countLbl, cap });
        P.Add(card);

        startBtn = B("START", 16, 76, 388, 46, Theme.Go);
        startBtn.Font = new Font("Segoe UI", 12f, FontStyle.Bold);
        startBtn.Click += (s, e) => ToggleRunning("button");
        P.Add(startBtn);

        learnBtn = B("Learn target", 16, 132, 190, 34, Theme.Act);
        learnBtn.Click += (s, e) => StartLearn();
        testBtn = B("Test", 214, 132, 190, 34, Theme.Btn);
        testBtn.Click += (s, e) => DoScan(false);
        P.Add(learnBtn); P.Add(testBtn);

        var tcard = new Panel { Location = new Point(16, 176), Size = new Size(388, 72), BackColor = Theme.Card };
        targetPic = new PictureBox { Location = new Point(10, 10), Size = new Size(52, 52), SizeMode = PictureBoxSizeMode.Zoom, BackColor = Theme.Bg };
        targetName = L("", 72, 10, 226, 20, Theme.Txt, 10f, true);
        targetInfo = L("", 72, 32, 226, 34, Theme.Dim, 8.5f, false);
        resetBtn = B("Reset", 308, 22, 68, 28, Theme.Btn);
        resetBtn.Click += (s, e) => { SetTarget(new Target()); try { File.Delete(targetPngPath); } catch { } SaveSettings(); AddLog("target reset to built-in x2"); };
        tcard.Controls.AddRange(new Control[] { targetPic, targetName, targetInfo, resetBtn });
        P.Add(tcard);

        P.Add(L("Delay after click", 16, 264, 0, 0, Theme.Txt, 9.5f, false));
        delayBox = new NumericUpDown { Location = new Point(132, 261), Size = new Size(50, 24), Minimum = 1, Maximum = 60, Value = 3,
            BackColor = Theme.Card, ForeColor = Theme.Txt, BorderStyle = BorderStyle.FixedSingle };
        delayBox.ValueChanged += (s, e) => SaveSettings();
        P.Add(delayBox);
        P.Add(L("sec", 186, 264, 0, 0, Theme.Dim, 9.5f, false));
        humanBox = new CheckBox { Text = "Human movement", Location = new Point(16, 294), AutoSize = true, ForeColor = Theme.Txt };
        humanBox.CheckedChanged += (s, e) => SaveSettings();
        topBox = new CheckBox { Text = "Always on top", Location = new Point(214, 294), AutoSize = true, ForeColor = Theme.Txt };
        topBox.CheckedChanged += (s, e) => { TopMost = topBox.Checked; SaveSettings(); };
        P.Add(humanBox); P.Add(topBox);

        P.Add(L("Logs", 16, 326, 0, 0, Theme.Dim, 9f, true));
        var logBorder = new Panel { Location = new Point(16, 346), Size = new Size(388, 172), BackColor = Theme.Line, Padding = new Padding(1) };
        log = new ListBox { Dock = DockStyle.Fill, BackColor = Theme.LogBg, ForeColor = Theme.LogTx, BorderStyle = BorderStyle.None,
            Font = new Font("Consolas", 9f), IntegralHeight = false, TabStop = false };
        logBorder.Controls.Add(log);
        P.Add(logBorder);
        P.Add(L("F9  start / stop", 16, 526, 0, 0, Theme.Dim, 8.5f, false));

        // ---- page 2: update log ----
        pageLog = new Panel { Location = new Point(0, 96), Size = new Size(420, 550), BackColor = Theme.Bg, Visible = false };
        Controls.Add(pageLog);
        var clBorder = new Panel { Location = new Point(16, 4), Size = new Size(388, 514), BackColor = Theme.Line, Padding = new Padding(1) };
        changelogBox = new RichTextBox { Dock = DockStyle.Fill, BackColor = Theme.Card, ForeColor = Theme.Txt, BorderStyle = BorderStyle.None,
            ReadOnly = true, Font = new Font("Segoe UI", 9.5f), TabStop = false, DetectUrls = false };
        clBorder.Controls.Add(changelogBox);
        pageLog.Controls.Add(clBorder);
        changelogSrc = L("Built-in notes", 16, 526, 388, 18, Theme.Dim, 8.5f, false);
        pageLog.Controls.Add(changelogSrc);
        ShowChangelog(Info.Changelog);
        ShowTab(true);

        // timers
        scanTimer = new System.Windows.Forms.Timer { Interval = 100 };
        scanTimer.Tick += (s, e) => { if (running && DateTime.Now >= nextScan) DoScan(true); };
        scanTimer.Start();
        keyTimer = new System.Windows.Forms.Timer { Interval = 50 };
        keyTimer.Tick += (s, e) => { bool d = Native.KeyDown(0x78); if (d && !f9Was) ToggleRunning("F9"); f9Was = d; };
        keyTimer.Start();
        learnTimer = new System.Windows.Forms.Timer { Interval = 1000 };
        learnTimer.Tick += (s, e) => LearnTick();
        updateTimer = new System.Windows.Forms.Timer { Interval = 30 * 60 * 1000 };
        updateTimer.Tick += (s, e) => CheckForUpdate();

        // Space/Enter never press our buttons (Space = jump in game).
        KeyPreview = true;
        KeyEventHandler eat = (s, e) => { if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter) { e.Handled = true; e.SuppressKeyPress = true; } };
        KeyDown += eat; KeyUp += eat;

        Shown += (s, e) => {
            ActiveControl = log;
            var once = new System.Windows.Forms.Timer { Interval = 1500 };
            once.Tick += (s2, e2) => { once.Stop(); CheckForUpdate(); updateTimer.Start(); };
            once.Start();
        };
        FormClosing += (s, e) => { scanTimer.Stop(); keyTimer.Stop(); learnTimer.Stop(); updateTimer.Stop(); SaveSettings(); };

        SetTarget(target);
        LoadSettings();
        loaded = true;
        AddLog("ready  v" + Info.Version);
    }

    // ---------- tabs, banner, changelog ----------
    void ShowTab(bool main) {
        pageMain.Visible = main; pageLog.Visible = !main;
        tabMain.ForeColor = main ? Theme.Txt : Theme.Dim;
        tabLog.ForeColor = main ? Theme.Dim : Theme.Txt;
        Button on = main ? tabMain : tabLog;
        tabLine.Left = on.Left; tabLine.Width = on.Width;
    }

    void ShowBanner(Release r) {
        bannerLbl.Text = "Update available: v" + r.Version;
        bannerSub.Text = string.IsNullOrEmpty(r.Notes) ? "See the Update log tab for what's new" : r.Notes;
        if (banner.Visible) return;
        banner.Visible = true;
        int shift = banner.Height + (int)(banner.Height * 8 / 52.0);
        pageMain.Top += shift; pageLog.Top += shift;
        ClientSize = new Size(ClientSize.Width, ClientSize.Height + shift);
        FlashWindow();
    }

    [DllImport("user32.dll")] static extern bool FlashWindow(IntPtr h, bool invert);
    void FlashWindow() { try { FlashWindow(Handle, true); } catch { } }

    void ShowChangelog(string text) {
        changelogBox.Clear();
        foreach (var raw in text.Replace("\r", "").Split('\n')) {
            string line = raw.TrimEnd();
            bool head = line.StartsWith("v") && line.Length > 1 && char.IsDigit(line[1]);
            changelogBox.SelectionFont = head ? new Font("Segoe UI", 11f, FontStyle.Bold) : new Font("Segoe UI", 9.5f);
            changelogBox.SelectionColor = head ? Theme.Txt : Theme.LogTx;
            if (head && line.TrimStart('v').StartsWith(Info.Version)) line += "   (you have this)";
            changelogBox.AppendText((line.StartsWith("- ") ? "  " + (char)0x2022 + " " + line.Substring(2) : line) + "\n");
        }
        changelogBox.SelectionStart = 0; changelogBox.ScrollToCaret();
    }

    // ---------- small helpers ----------
    void SetStatus(string main, string sub, Color c) { statusLbl.Text = main; statusLbl.ForeColor = c; subLbl.Text = sub; }

    void AddLog(string msg) {
        log.Items.Insert(0, DateTime.Now.ToString("HH:mm:ss") + "  " + msg);
        while (log.Items.Count > 300) log.Items.RemoveAt(log.Items.Count - 1);
    }

    static Bitmap BuiltInPicture() {
        var b = new Bitmap(52, 52);
        using (var g = Graphics.FromImage(b)) {
            g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
            using (var br = new SolidBrush(Color.FromArgb(165, 95, 235))) g.FillEllipse(br, 3, 3, 46, 46);
            using (var f = new Font("Arial", 16, FontStyle.Bold, GraphicsUnit.Pixel)) {
                var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
                g.DrawString("x2", f, Brushes.White, new RectangleF(3, 3, 46, 46), sf);
            }
        }
        return b;
    }

    void SetTarget(Target t) {
        target = t;
        targetPic.Image = t.BuiltIn ? BuiltInPicture() : t.Picture;
        targetName.Text = t.Name;
        targetInfo.Text = t.Describe();
        resetBtn.Visible = !t.BuiltIn;
    }

    Rectangle MyAreaIn(Rectangle vs) {
        if (WindowState == FormWindowState.Minimized) return Rectangle.Empty;
        var b = Bounds; b.Offset(-vs.Left, -vs.Top); return b;
    }

    // ---------- start / stop ----------
    void ToggleRunning(string by) {
        running = !running;
        if (running) {
            startBtn.Text = "STOP"; startBtn.BackColor = Theme.Halt;
            startBtn.FlatAppearance.MouseOverBackColor = ControlPaint.Light(Theme.Halt, 0.15f);
            nextScan = DateTime.Now;
            SetStatus("Watching", "Clicks the target when it shows up", Theme.Act);
            AddLog("started (" + by + ")");
        } else {
            startBtn.Text = "START"; startBtn.BackColor = Theme.Go;
            startBtn.FlatAppearance.MouseOverBackColor = ControlPaint.Light(Theme.Go, 0.15f);
            SetStatus("Idle", "Press START or F9", Theme.Dim);
            AddLog("stopped (" + by + ")");
        }
    }

    // ---------- scanning ----------
    void DoScan(bool click) {
        Rectangle vs = Native.VirtualScreen;
        List<Hit> hits;
        var sw = Stopwatch.StartNew();
        using (var shot = Native.GrabAll()) hits = Detector.Find(shot, MyAreaIn(vs), target);
        long ms = sw.ElapsedMilliseconds;
        Hit best = hits.Count > 0 ? hits[0] : null;
        Point c = best != null ? new Point(best.Center.X + vs.Left, best.Center.Y + vs.Top) : Point.Empty;
        int cooldown = (int)delayBox.Value;

        if (!click) {
            if (best != null) {
                var box = best.Box; box.Offset(vs.Left, vs.Top);
                new Flash(box).Show();
                SetStatus("Found", hits.Count + " match" + (hits.Count > 1 ? "es" : "") + ", best at " + c.X + ", " + c.Y, Theme.Go);
                AddLog("test  found " + hits.Count + "  best (" + c.X + ", " + c.Y + ")  score " + best.Score.ToString("0.00") + "  " + ms + "ms");
            } else {
                SetStatus("Nothing found", target.BuiltIn ? "Is the x2 on screen? Or use Learn target." : "Is the target on screen?", Theme.Warn);
                AddLog("test  nothing found  " + ms + "ms");
            }
            return;
        }

        if (best == null) {
            SetStatus("Watching", "Clicks the target when it shows up", Theme.Act);
            nextScan = DateTime.Now.AddMilliseconds(350);
            return;
        }
        bool again = Math.Abs(c.X - lastClickPos.X) < 15 && Math.Abs(c.Y - lastClickPos.Y) < 15
                     && (DateTime.Now - lastClickTime).TotalSeconds < cooldown + 2;
        string note = Mouse.Click(c.X, c.Y, Math.Min(best.Box.Width, best.Box.Height) / 2, humanBox.Checked);
        clicks++; countLbl.Text = clicks.ToString();
        lastClickPos = c; lastClickTime = DateTime.Now;
        AddLog((again ? "click again" : "click") + "  (" + c.X + ", " + c.Y + ")  score " + best.Score.ToString("0.00")
               + (humanBox.Checked ? "  human" : "") + (note != null ? "  " + note : ""));
        SetStatus("Clicked", "Waiting " + cooldown + "s, then watching again", Theme.Go);
        nextScan = DateTime.Now.AddSeconds(cooldown);
    }

    // ---------- learning ----------
    void StartLearn() {
        learnCountdown = 3;
        SetStatus("Hover the circle  3", "Put your cursor on the circle and hold still", Theme.Warn);
        learnTimer.Start();
    }

    void LearnTick() {
        learnCountdown--;
        if (learnCountdown > 0) { statusLbl.Text = "Hover the circle  " + learnCountdown; return; }
        learnTimer.Stop();
        Point p = Native.Cursor();
        if (Bounds.Contains(p)) { SetStatus("Couldn't learn", "The cursor was on this window", Theme.Halt); AddLog("learn  cursor was on this window"); return; }
        string err;
        Target t = null;
        try { t = Learner.Learn(p, out err); } catch (Exception ex) { err = ex.Message; }
        if (t == null) { SetStatus("Couldn't learn", err, Theme.Halt); AddLog("learn  failed: " + err); return; }
        SetTarget(t);
        SaveSettings();
        SetStatus("Target learned", t.Round ? "Press Test to check it" : "Doesn't look round - Test it first", t.Round ? Theme.Go : Theme.Warn);
        AddLog("learn  " + t.Describe());
    }

    // ---------- updates ----------
    string UpdateUrl() {
        try {
            string f = Path.Combine(folder, "update-url.txt");
            if (File.Exists(f)) { string s = File.ReadAllText(f).Trim(); if (s.Length > 0) return s; }
        } catch { }
        return Info.DefaultUpdateUrl;
    }

    void CheckForUpdate() {
        string baseUrl = UpdateUrl();
        if (string.IsNullOrEmpty(baseUrl)) return;
        if (!baseUrl.EndsWith("/")) baseUrl += "/";
        var th = new Thread(() => {
            try {
                Release r = Updater.Fetch(baseUrl);
                bool newer = new Version(r.Version) > new Version(Info.Version);
                string notes = null;
                try { notes = Updater.FetchText(baseUrl, "changelog.txt"); } catch { }
                BeginInvoke((Action)(() => {
                    if (!string.IsNullOrEmpty(notes)) { ShowChangelog(notes); changelogSrc.Text = "Latest notes from the internet"; }
                    if (newer) {
                        pendingUpdate = r;
                        ShowBanner(r);
                        AddLog("update available  v" + r.Version + (string.IsNullOrEmpty(r.Notes) ? "" : "  - " + r.Notes));
                    } else if (pendingUpdate == null) AddLog("up to date");
                }));
            } catch (Exception ex) {
                try { BeginInvoke((Action)(() => AddLog("update check failed: " + ex.Message))); } catch { }
            }
        });
        th.IsBackground = true; th.Start();
    }

    void StartUpdate() {
        if (pendingUpdate == null) return;
        if (running) ToggleRunning("update");
        SaveSettings();
        Release r = pendingUpdate;
        var uf = new UpdateForm(r.Version);
        uf.Shown += (s, e) => {
            var th = new Thread(() => {
                try {
                    Updater.Install(r, folder, (pct, text) => uf.BeginInvoke((Action)(() => uf.SetProgress(pct, text))));
                    uf.BeginInvoke((Action)(() => uf.SetProgress(100, "Restarting")));
                    Thread.Sleep(800);
                    BeginInvoke((Action)(() => { Relaunch(); Application.Exit(); }));
                } catch (Exception ex) {
                    uf.BeginInvoke((Action)(() => uf.Fail("Update failed: " + ex.Message)));
                }
            });
            th.IsBackground = true; th.Start();
        };
        uf.ShowDialog(this);
    }

    void Relaunch() {
        var psi = new ProcessStartInfo("powershell.exe",
            "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + scriptPath + "\"");
        psi.UseShellExecute = false; psi.CreateNoWindow = true;
        Process.Start(psi);
    }

    // ---------- settings ----------
    void LoadSettings() {
        try {
            if (!File.Exists(settingsPath)) return;
            var d = new Dictionary<string, string>();
            foreach (var line in File.ReadAllLines(settingsPath)) {
                int eq = line.IndexOf('=');
                if (eq > 0) d[line.Substring(0, eq)] = line.Substring(eq + 1);
            }
            string v;
            if (d.TryGetValue("cooldown", out v)) delayBox.Value = Math.Max(1, Math.Min(60, int.Parse(v)));
            if (d.TryGetValue("human", out v)) humanBox.Checked = v == "1";
            if (d.TryGetValue("top", out v)) topBox.Checked = v == "1";
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
                "cooldown=" + delayBox.Value, "human=" + (humanBox.Checked ? 1 : 0), "top=" + (topBox.Checked ? 1 : 0),
                "window=" + pos.X + "," + pos.Y };
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
