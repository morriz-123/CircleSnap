# CircleTrack
# Watches your screen for a circle (the purple x2 by default, or any circle you
# teach it) and clicks it when it shows up. Runs as its own program next to the
# game: it only looks at the screen and moves/clicks the mouse. It never touches
# the game's files or memory.
#
# Start it by double-clicking "Start CircleTrack.bat".

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
    public const string Name = "CircleTrack";
    public const string Version = "1.4.0";
    public const string DefaultUpdateUrl = "https://raw.githubusercontent.com/morriz-123/CircleSnap/main/";
    // Updates must be signed with the developer's private key (kept off GitHub).
    public const string PublicKey = "<RSAKeyValue><Modulus>qi5iTvS2ilQbLdEFsIC1LrKFO2th9Kwsw0D8JJ9DojxOjKB4iYHQhbFW5nAqxFupMTLlswRJiEaYG39r7WulHNJ6iSOmPFLtW1YFlf88V7pFXuO6zof2IDgmXhKLfImcL3edY6c+BgFm6C4XES9/2btlzpcXnI2JDfRcE4iZlb7tYnyzMTTRsX78svQmHQ6roARY+LTkhOkytdl7ouWgCaiwBMINLpVcFeMzhE5kMLGiPW64iV3VrlQuK4vtGRN0YZYq1iXHmGjdt9qi1NwRU6FvMnU311hfhKCxix0Y44aI3vLed92z/Ye+Rt7gtB2weNbYBOAX7LbG1/rohezvIQ==</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>";
    public const string Changelog =
        "v1.4.0\n" +
        "- New name: CircleTrack, with a new eye logo\n" +
        "- Deep ocean look, cleaner layout, shiny buttons\n" +
        "- MODULE button: pick which engine clicks for you\n" +
        "- New Tracker module: confirms targets, follows moving circles, checks every click and never stops\n" +
        "- Human movement: different speeds, misses on purpose and corrects\n" +
        "- New Other tab\n" +
        "\n" +
        "v1.3.0\n" +
        "- Settings tab, keybinds, help on every setting\n" +
        "- Signed updates and a Repair button for modified copies\n" +
        "- Updates show up while the app is open\n" +
        "\n" +
        "v1.2.0\n" +
        "- Update log tab and update banner\n" +
        "\n" +
        "v1.1.0\n" +
        "- Learn target: teach it any circle\n" +
        "- Human movement option\n" +
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
    public static double MissChance = 0.4;

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

    static double Ease(int kind, double t) {
        if (kind == 0) return t < 0.5 ? 4 * t * t * t : 1 - Math.Pow(-2 * t + 2, 3) / 2;    // cubic
        if (kind == 1) return t < 0.5 ? 16 * Math.Pow(t, 5) : 1 - Math.Pow(-2 * t + 2, 5) / 2; // quint: fast middle
        if (kind == 2) return -(Math.Cos(Math.PI * t) - 1) / 2;                              // sine: smooth
        return 1 - Math.Pow(1 - t, 3);                                                        // ease-out: quick start
    }

    // One human-like stroke: curved path, its own speed and easing, small shake.
    static void Stroke(double tx, double ty, double speed, double bend) {
        Point s = Native.Cursor();
        double dx = tx - s.X, dy = ty - s.Y, dist = Math.Sqrt(dx * dx + dy * dy);
        if (dist < 3) { MoveTo(tx, ty); return; }
        double px = -dy / dist, py = dx / dist;
        double b1 = (rng.NextDouble() - 0.5) * bend * dist, b2 = (rng.NextDouble() - 0.5) * bend * 0.7 * dist;
        double c1x = s.X + dx * (0.2 + rng.NextDouble() * 0.2) + px * b1, c1y = s.Y + dy * (0.2 + rng.NextDouble() * 0.2) + py * b1;
        double c2x = s.X + dx * (0.65 + rng.NextDouble() * 0.2) + px * b2, c2y = s.Y + dy * (0.65 + rng.NextDouble() * 0.2) + py * b2;
        int ms = (int)Math.Max(70, Math.Min(1500, (140 + dist * 0.5 + rng.Next(0, 130)) * speed));
        int steps = Math.Max(10, ms / 8);
        int kind = rng.Next(4);
        var sw = Stopwatch.StartNew();
        for (int i = 1; i <= steps; i++) {
            double t = i / (double)steps, e = Ease(kind, t), u = 1 - e;
            double x = u * u * u * s.X + 3 * u * u * e * c1x + 3 * u * e * e * c2x + e * e * e * tx;
            double y = u * u * u * s.Y + 3 * u * u * e * c1y + 3 * u * e * e * c2y + e * e * e * ty;
            double jit = (1 - e) * 1.5;
            MoveTo(x + (rng.NextDouble() - 0.5) * jit, y + (rng.NextDouble() - 0.5) * jit);
            int wait = (int)(ms * t) + rng.Next(-2, 3) - (int)sw.ElapsedMilliseconds;
            if (wait > 0) Thread.Sleep(wait);
        }
        MoveTo(tx, ty);
    }

    // Moves like a person: varied speed every time, sometimes misses the
    // circle on purpose, notices, and corrects onto it. Always ends inside.
    static string HumanPath(int x, int y, int radius) {
        Point s = Native.Cursor();
        double speed = 0.55 + rng.NextDouble() * 1.05;
        bool miss = radius >= 10 && rng.NextDouble() < MissChance;
        if (!miss) { Stroke(x, y, speed, 0.25 + rng.NextDouble() * 0.35); return null; }
        double ang = Math.Atan2(y - s.Y, x - s.X);
        if (rng.NextDouble() < 0.35) ang += (rng.NextDouble() < 0.5 ? 1 : -1) * (0.6 + rng.NextDouble() * 0.9); // miss to the side
        double off = radius * (1.25 + rng.NextDouble() * 0.7);
        double mx = x + Math.Cos(ang) * off, my = y + Math.Sin(ang) * off;
        Stroke(mx, my, speed * 0.85, 0.3 + rng.NextDouble() * 0.3);
        Thread.Sleep(rng.Next(90, 280));                       // "oops"
        Stroke(x, y, 0.45 + rng.NextDouble() * 0.5, 0.15);     // correct, a bit slower
        return "missed, corrected";
    }

    public static string Click(int x, int y, int radius, bool human) {
        timeBeginPeriod(1);
        try {
            bool focused = FocusWindowAt(x, y);
            string note = null;
            if (human && radius > 6) {
                double a = rng.NextDouble() * 2 * Math.PI, r = rng.NextDouble() * radius * 0.28;
                x += (int)(Math.Cos(a) * r); y += (int)(Math.Sin(a) * r);
            }
            if (human) note = HumanPath(x, y, radius); else FastMove(x, y);
            Send(MOVE, 1, 0); Thread.Sleep(12); Send(MOVE, -1, 0); Thread.Sleep(12);
            MoveTo(x, y);
            Thread.Sleep(human ? rng.Next(60, 190) : 50);
            Send(LEFTDOWN, 0, 0);
            Thread.Sleep(human ? rng.Next(60, 150) : 90);
            Send(LEFTUP, 0, 0);
            if (focused) note = (note == null ? "" : note + ", ") + "focused game";
            return note;
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

    public string Describe() { return BuiltIn ? "" : Diameter + " px circle"; }

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
    public int Radius { get { return Math.Min(Box.Width, Box.Height) / 2; } }
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

    // Colour + shape + (optional) look. All matches, best first.
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

    // The very first method: look for an exact copy of a picture (same size).
    public static Hit FindPicture(Bitmap screen, Bitmap tpl, Rectangle exclude) {
        int sw = screen.Width, sh = screen.Height, tw = tpl.Width, th = tpl.Height;
        if (tw > sw || th > sh || tw < 4 || th < 4) return null;
        int[] s = Pixels(screen), t = Pixels(tpl);
        int total = tw * th, n = Math.Min(120, total);
        long sr = 0, sg = 0, sb = 0;
        foreach (int c in t) { sr += (c >> 16) & 255; sg += (c >> 8) & 255; sb += c & 255; }
        int mr = (int)(sr / total), mg = (int)(sg / total), mb = (int)(sb / total);
        int[] order = new int[total], dist = new int[total];
        for (int i = 0; i < total; i++) { int c = t[i]; order[i] = i; dist[i] = -(Math.Abs(((c >> 16) & 255) - mr) + Math.Abs(((c >> 8) & 255) - mg) + Math.Abs((c & 255) - mb)); }
        Array.Sort(dist, order);
        var rnd = new Random(1);
        int[] ox = new int[n], oy = new int[n], col = new int[n];
        for (int i = 0; i < n; i++) { int idx = (i < n / 2) ? order[i] : rnd.Next(total); ox[i] = idx % tw; oy[i] = idx / tw; col[i] = t[idx]; }
        const int tol = 40;
        int maxMiss = (int)(n * 0.12), best = maxMiss + 1, bx = -1, by = -1;
        for (int y = 0; y <= sh - th; y++)
            for (int x = 0; x <= sw - tw; x++) {
                if (exclude.Contains(x + tw / 2, y + th / 2)) continue;
                int miss = 0;
                for (int i = 0; i < n; i++) {
                    int p = s[(y + oy[i]) * sw + x + ox[i]], q = col[i];
                    if (Math.Abs(((p >> 16) & 255) - ((q >> 16) & 255)) > tol || Math.Abs(((p >> 8) & 255) - ((q >> 8) & 255)) > tol || Math.Abs((p & 255) - (q & 255)) > tol)
                        if (++miss >= best) break;
                }
                if (miss < best) { best = miss; bx = x; by = y; }
            }
        if (bx < 0) return null;
        return new Hit { Box = new Rectangle(bx, by, tw, th), Score = 1 - best / (double)n };
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

// ---- the clicking engines ("modules"), from the first version to the newest ----
public class ModuleInfo { public string Name, Ver, Desc; public bool IsNew; }

public static class Modules {
    public static readonly ModuleInfo[] All = {
        new ModuleInfo { Name = "Picture Match", Ver = "v0.1", Desc = "The very first version. Looks for an exact picture of your learned target." },
        new ModuleInfo { Name = "Purple Finder", Ver = "v1.0", Desc = "Finds round purple circles with text inside. Simple and fast." },
        new ModuleInfo { Name = "Smart Learner", Ver = "v1.1", Desc = "Matches the circle you taught it by colour, shape and look." },
        new ModuleInfo { Name = "Tracker", Ver = "v1.4", IsNew = true, Desc = "Confirms every target, follows moving circles, checks each click landed, retries and never stops." }
    };
    public const int Latest = 3;
}

// Runs on its own thread so the window never freezes. Every step is guarded:
// errors are logged and it backs off and carries on; a watchdog restarts it
// if it ever stalls.
public class Engine {
    public volatile bool Running;
    public volatile int Module = Modules.Latest;
    public volatile int Delay = 3;
    public volatile bool Human;
    public Target Target = new Target();
    public Rectangle Exclude;                   // our own window, screen coords
    public Action<string> Log;
    public Action<string, int> State;           // word, colour index
    public Action Clicked;
    public DateTime Heartbeat = DateTime.Now;

    Thread worker; int generation; int errors;
    DateTime nextScan = DateTime.MinValue;
    // tracker memory
    Point candPos; DateTime candTime = DateTime.MinValue; bool hasCand;
    Point lastSeen; DateTime lastSeenTime = DateTime.MinValue; int lastRadius = 40;
    bool warnedPicture;

    public void Start() {
        int gen = Interlocked.Increment(ref generation);
        Heartbeat = DateTime.Now;
        worker = new Thread(() => Loop(gen)) { IsBackground = true, Name = "CircleTrack engine", Priority = ThreadPriority.AboveNormal };
        worker.Start();
    }
    public void Restart() { Start(); } // the old thread sees the new generation and exits

    void Say(string m) { try { if (Log != null) Log(m); } catch { } }
    void Show(string w, int c) { try { if (State != null) State(w, c); } catch { } }

    void Loop(int gen) {
        while (gen == generation) {
            Heartbeat = DateTime.Now;
            try {
                if (!Running || DateTime.Now < nextScan) { Thread.Sleep(30); continue; }
                Step();
                if (errors > 0) { Say("engine recovered"); errors = 0; Show("RUNNING", 1); }
            } catch (ThreadAbortException) { return; }
            catch (Exception ex) {
                errors++;
                Say("engine error (" + errors + "): " + ex.Message + " - recovering");
                Show("RECOVERING", 5);
                hasCand = false;
                try { GC.Collect(); } catch { }
                Thread.Sleep(Math.Min(3000, 200 * errors));
            }
        }
    }

    // ---------- helpers ----------
    List<Hit> ScanRect(Rectangle area, Target t) {
        area.Intersect(Native.VirtualScreen);
        if (area.Width < 8 || area.Height < 8) return new List<Hit>();
        using (var bmp = Native.Grab(area)) {
            var ex = Exclude; ex.Offset(-area.Left, -area.Top);
            var hits = Detector.Find(bmp, ex, t);
            foreach (var h in hits) h.Box.Offset(area.Left, area.Top);
            return hits;
        }
    }
    List<Hit> ScanAll(Target t) { return ScanRect(Native.VirtualScreen, t); }

    void DoClick(Point c, int radius, double score) {
        Show("CLICKING", 2);
        string note = Mouse.Click(c.X, c.Y, radius, Human);
        Say("click  (" + c.X + ", " + c.Y + ")  " + score.ToString("0.00") + (note != null ? "  " + note : ""));
        if (Clicked != null) try { Clicked(); } catch { }
        Show("RUNNING", 1);
    }

    void Wait() { nextScan = DateTime.Now.AddSeconds(Delay); }

    static double Dist(Point a, Point b) { double dx = a.X - b.X, dy = a.Y - b.Y; return Math.Sqrt(dx * dx + dy * dy); }

    // ---------- one step of the selected module ----------
    void Step() {
        Target t = Target;
        int m = Module;
        if (m == 0) StepPicture(t);
        else if (m == 1) StepSimple(new Target());
        else if (m == 2) StepSimple(t);
        else StepTracker(t);
    }

    void StepPicture(Target t) {
        if (t.BuiltIn || t.Picture == null) {
            if (!warnedPicture) { Say("Picture Match needs a learned target - using Purple Finder"); warnedPicture = true; }
            StepSimple(new Target()); return;
        }
        Rectangle vs = Native.VirtualScreen;
        Hit h;
        using (var bmp = Native.Grab(vs)) { var ex = Exclude; ex.Offset(-vs.Left, -vs.Top); h = Detector.FindPicture(bmp, t.Picture, ex); }
        if (h == null) { nextScan = DateTime.Now.AddMilliseconds(300); return; }
        h.Box.Offset(vs.Left, vs.Top);
        DoClick(h.Center, h.Radius, h.Score); Wait();
    }

    void StepSimple(Target t) {
        var hits = ScanAll(t);
        if (hits.Count == 0) { nextScan = DateTime.Now.AddMilliseconds(300); return; }
        DoClick(hits[0].Center, hits[0].Radius, hits[0].Score); Wait();
    }

    // Tracker: look near where it was last seen first (fast), confirm the
    // target on two frames (no flicker false hits), lead moving targets,
    // then check the click landed and retry if it didn't.
    void StepTracker(Target t) {
        List<Hit> hits = null;
        bool recent = (DateTime.Now - lastSeenTime).TotalSeconds < 3;
        if (recent) {
            int s = Math.Max(320, lastRadius * 7);
            hits = ScanRect(new Rectangle(lastSeen.X - s / 2, lastSeen.Y - s / 2, s, s), t);
        }
        if (hits == null || hits.Count == 0) hits = ScanAll(t);
        if (hits.Count == 0) { hasCand = false; nextScan = DateTime.Now.AddMilliseconds(110); return; }

        // prefer the hit closest to what we were already following
        Hit best = hits[0];
        if (hasCand) {
            double bd = double.MaxValue;
            foreach (var h in hits) { double d = Dist(h.Center, candPos); if (d < bd && h.Score >= hits[0].Score - 0.1) { bd = d; best = h; } }
        }
        Point c = best.Center; int r = Math.Max(6, best.Radius);
        lastSeen = c; lastSeenTime = DateTime.Now; lastRadius = r;

        double dt = (DateTime.Now - candTime).TotalSeconds;
        if (!hasCand || dt > 0.8 || Dist(c, candPos) > Math.Max(14, r * 1.5)) {
            hasCand = true; candPos = c; candTime = DateTime.Now;
            nextScan = DateTime.Now.AddMilliseconds(60);   // look again to confirm
            return;
        }

        // confirmed: predict where it will be when the mouse arrives
        double vx = (c.X - candPos.X) / Math.Max(0.03, dt), vy = (c.Y - candPos.Y) / Math.Max(0.03, dt);
        double lead = Human ? 0.45 : 0.12;
        double lx = vx * lead, ly = vy * lead, ll = Math.Sqrt(lx * lx + ly * ly), cap = r * 1.5;
        if (ll > cap) { lx *= cap / ll; ly *= cap / ll; }
        Point aim = new Point((int)(c.X + lx), (int)(c.Y + ly));
        if (ll > 3) Say("target moving - leading the click by " + (int)ll + "px");

        for (int attempt = 1; attempt <= 3; attempt++) {
            Heartbeat = DateTime.Now;
            DoClick(aim, r, best.Score);
            Thread.Sleep(260);
            int s = Math.Max(240, r * 6);
            var after = ScanRect(new Rectangle(aim.X - s / 2, aim.Y - s / 2, s, s), t);
            Hit still = null;
            foreach (var h in after) if (Dist(h.Center, aim) < Math.Max(18, r * 1.2)) { still = h; break; }
            if (still == null) { Say("click landed"); break; }
            if (attempt == 3) { Say("target stayed after 3 clicks - waiting"); break; }
            Say("target still there - retry " + (attempt + 1) + "/3");
            aim = still.Center; r = Math.Max(6, still.Radius);
        }
        hasCand = false;
        Wait();
    }
}

// ---- security: only trust updates signed with the developer's private key ----
public static class Security {
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
        wc.Headers[HttpRequestHeader.UserAgent] = "circletrack-updater";
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
        string tmp = Path.Combine(Path.GetTempPath(), "circletrack-update-" + Guid.NewGuid().ToString("N"));
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
    public static readonly Color Txt    = Color.FromArgb(236, 244, 255);
    public static readonly Color Dim    = Color.FromArgb(150, 175, 205);
    public static readonly Color Faint  = Color.FromArgb(95, 125, 160);
    public static readonly Color Accent = Color.FromArgb(56, 189, 248);
    public static readonly Color Deep   = Color.FromArgb(30, 64, 175);
    public static readonly Color Glass  = Color.FromArgb(120, 8, 22, 48);
    public static readonly Color Edge   = Color.FromArgb(70, 120, 190, 255);
    public static readonly Color Warn   = Color.FromArgb(251, 191, 36);
    public static readonly Color Halt   = Color.FromArgb(248, 113, 113);
    public static readonly Color[] Status = {
        Color.FromArgb(148, 163, 184),  // 0 idle
        Color.FromArgb(52, 211, 153),   // 1 running
        Color.FromArgb(96, 165, 250),   // 2 clicking
        Color.FromArgb(251, 191, 36),   // 3 learning
        Color.FromArgb(34, 211, 238),   // 4 updating
        Color.FromArgb(244, 114, 182)   // 5 recovering
    };
}

// The ocean background, drawn once and shared by every panel so it looks seamless.
public static class Ocean {
    static Bitmap cache; static Size cacheSize;
    public static Bitmap Get(Size s) {
        if (cache != null && cacheSize == s) return cache;
        if (s.Width < 1 || s.Height < 1) s = new Size(1, 1);
        var b = new Bitmap(s.Width, s.Height, PixelFormat.Format32bppPArgb);
        using (var g = Graphics.FromImage(b)) {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            var r = new Rectangle(0, 0, s.Width, s.Height);
            using (var br = new LinearGradientBrush(r, Color.FromArgb(3, 10, 32), Color.FromArgb(8, 52, 96), 60f)) {
                var cb = new ColorBlend(4);
                cb.Colors = new[] { Color.FromArgb(3, 9, 30), Color.FromArgb(6, 28, 70), Color.FromArgb(9, 62, 110), Color.FromArgb(6, 90, 120) };
                cb.Positions = new[] { 0f, 0.4f, 0.75f, 1f };
                br.InterpolationColors = cb;
                g.FillRectangle(br, r);
            }
            Glow(g, new RectangleF(s.Width * 0.45f, -s.Height * 0.35f, s.Width * 0.9f, s.Height * 0.8f), Color.FromArgb(70, 34, 211, 238));
            Glow(g, new RectangleF(-s.Width * 0.3f, s.Height * 0.55f, s.Width * 0.8f, s.Height * 0.7f), Color.FromArgb(60, 37, 99, 235));
            Glow(g, new RectangleF(s.Width * 0.2f, s.Height * 0.25f, s.Width * 0.6f, s.Height * 0.5f), Color.FromArgb(22, 125, 211, 252));
            // soft waves
            for (int i = 0; i < 6; i++) {
                using (var p = new Pen(Color.FromArgb(10 + i * 2, 160, 220, 255), 1.2f)) {
                    var pts = new List<PointF>();
                    float baseY = s.Height * (0.18f + i * 0.14f), amp = 6 + i * 2, len = s.Width / (1.3f + i * 0.2f);
                    for (int x = -10; x <= s.Width + 10; x += 8) pts.Add(new PointF(x, baseY + amp * (float)Math.Sin((x + i * 47) / len * Math.PI * 2)));
                    g.DrawCurve(p, pts.ToArray());
                }
            }
        }
        if (cache != null) cache.Dispose();
        cache = b; cacheSize = s;
        return b;
    }
    static void Glow(Graphics g, RectangleF r, Color c) {
        using (var path = new GraphicsPath()) {
            path.AddEllipse(r);
            using (var br = new PathGradientBrush(path)) {
                br.CenterColor = c; br.SurroundColors = new[] { Color.FromArgb(0, c) };
                g.FillPath(br, path);
            }
        }
    }
    // Paint the part of the ocean that sits behind control c.
    public static void PaintBehind(Graphics g, Control c) {
        Form f = c.FindForm();
        if (f == null) { g.Clear(Color.FromArgb(5, 20, 50)); return; }
        Point off = f == c ? Point.Empty : f.PointToClient(c.PointToScreen(Point.Empty));
        var bmp = Get(f.ClientSize);
        g.DrawImage(bmp, new Rectangle(0, 0, c.Width, c.Height), new Rectangle(off.X, off.Y, c.Width, c.Height), GraphicsUnit.Pixel);
    }
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
        return Color.FromArgb((int)(a.A + (b.A - a.A) * t), (int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t));
    }
}

// The eye-with-tracker logo, with tiny water particles flowing in and out.
public static class Logo {
    public static void Paint(Graphics g, RectangleF box, double time, bool particles) {
        g.SmoothingMode = SmoothingMode.AntiAlias;
        float s = Math.Min(box.Width, box.Height), cx = box.X + box.Width / 2, cy = box.Y + box.Height / 2;
        float w = s * 0.86f, h = s * 0.5f;
        Color deep = Color.FromArgb(29, 78, 216), light = Color.FromArgb(56, 189, 248);
        var rnd = new Random(7);
        if (particles) { // back half of the particles (behind the eye)
            for (int i = 0; i < 34; i++) Particle(g, rnd, i, time, cx, cy, s, false);
        }
        using (var eye = new GraphicsPath()) {
            eye.AddBezier(cx - w / 2, cy, cx - w / 4, cy - h * 0.95f, cx + w / 4, cy - h * 0.95f, cx + w / 2, cy);
            eye.AddBezier(cx + w / 2, cy, cx + w / 4, cy + h * 0.95f, cx - w / 4, cy + h * 0.95f, cx - w / 2, cy);
            eye.CloseFigure();
            using (var fill = new LinearGradientBrush(new RectangleF(cx - w / 2, cy - h / 2, w, h), Color.FromArgb(70, light), Color.FromArgb(25, deep), 90f))
                g.FillPath(fill, eye);
            using (var pen = new Pen(new LinearGradientBrush(new RectangleF(cx - w / 2, cy - h / 2, w, h), light, deep, 30f), Math.Max(1.4f, s * 0.055f)))
                g.DrawPath(pen, eye);
        }
        float ir = s * 0.2f;
        using (var pen = new Pen(new LinearGradientBrush(new RectangleF(cx - ir, cy - ir, ir * 2, ir * 2), light, deep, 45f), Math.Max(1.2f, s * 0.06f)))
            g.DrawEllipse(pen, cx - ir, cy - ir, ir * 2, ir * 2);
        float pr = s * 0.075f;
        using (var br = new LinearGradientBrush(new RectangleF(cx - pr, cy - pr, pr * 2, pr * 2), light, deep, 45f)) g.FillEllipse(br, cx - pr, cy - pr, pr * 2, pr * 2);
        // tracker lines through the eye
        using (var pen = new Pen(Color.FromArgb(230, light), Math.Max(1f, s * 0.035f))) {
            float a = s * 0.5f, gap = ir * 1.25f;
            g.DrawLine(pen, cx - a, cy, cx - gap, cy); g.DrawLine(pen, cx + gap, cy, cx + a, cy);
            g.DrawLine(pen, cx, cy - a * 0.78f, cx, cy - gap); g.DrawLine(pen, cx, cy + gap, cx, cy + a * 0.78f);
        }
        if (particles) { rnd = new Random(7); for (int i = 0; i < 34; i++) Particle(g, rnd, i, time, cx, cy, s, true); }
    }
    // Particles spiral in toward the eye and back out, with depth (size/alpha).
    static void Particle(Graphics g, Random rnd, int i, double time, float cx, float cy, float s, bool front) {
        double speed = 0.18 + rnd.NextDouble() * 0.25, phase = rnd.NextDouble(), ang0 = rnd.NextDouble() * Math.PI * 2, tilt = 0.15 + rnd.NextDouble() * 0.85;
        double life = (time * speed + phase) % 1.0;
        double inward = i % 2 == 0 ? life : 1 - life;                  // half flow in, half flow out
        double rad = s * (0.24 + 0.36 * inward);
        double ang = ang0 + time * (0.8 + speed) * (i % 3 == 0 ? -1 : 1);
        double z = Math.Sin(ang);                                        // depth
        if ((z >= 0) != front) return;
        float x = cx + (float)(Math.Cos(ang) * rad), y = cy + (float)(Math.Sin(ang) * rad * tilt);
        float size = (float)Math.Max(0.6, s * (0.007 + 0.011 * (z + 1) / 2));
        int alpha = (int)(Math.Sin(life * Math.PI) * (front ? 220 : 110));
        if (alpha <= 4) return;
        using (var br = new SolidBrush(Color.FromArgb(alpha, 165, 230, 255))) g.FillEllipse(br, x - size, y - size, size * 2, size * 2);
    }
    public static Bitmap Draw(int size) {
        var b = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(b)) { g.Clear(Color.Transparent); Paint(g, new RectangleF(0, 0, size, size), 0, false); }
        return b;
    }
    public static Icon MakeIcon() { using (var b = Draw(64)) return Icon.FromHandle(b.GetHicon()); }
}

// A panel that shows the ocean behind it (plus an optional tint), so nothing looks boxed in.
public class OceanPanel : Panel {
    public Color Tint = Color.Empty;
    public OceanPanel() {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
    }
    protected override void OnPaintBackground(PaintEventArgs e) { }
    protected override void OnPaint(PaintEventArgs e) {
        Ocean.PaintBehind(e.Graphics, this);
        if (Tint != Color.Empty) using (var br = new SolidBrush(Tint)) e.Graphics.FillRectangle(br, ClientRectangle);
    }
}

// Rounded glass card.
public class Card : OceanPanel {
    public Color Fill = Theme.Glass, Border = Theme.Edge;
    public float Radius = 12;
    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics;
        if (Parent is OceanPanel || Parent is Form) {
            // draw what the parent shows behind us (ocean + parent tint)
            Ocean.PaintBehind(g, this);
            var pp = Parent as OceanPanel;
            if (pp != null && pp.Tint != Color.Empty) using (var br = new SolidBrush(pp.Tint)) g.FillRectangle(br, ClientRectangle);
            var pc = Parent as Card;
            if (pc != null) using (var br = new SolidBrush(pc.Fill)) g.FillRectangle(br, ClientRectangle);
        }
        g.SmoothingMode = SmoothingMode.AntiAlias;
        float k = g.DpiX / 96f;
        using (var path = Gfx.Round(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), Radius * k)) {
            using (var br = new SolidBrush(Fill)) g.FillPath(br, path);
            using (var hl = new LinearGradientBrush(new RectangleF(0, 0, Width, Math.Max(2, Height)), Color.FromArgb(18, 255, 255, 255), Color.FromArgb(0, 255, 255, 255), 90f))
                g.FillPath(hl, path);
            if (Border != Color.Empty) using (var p = new Pen(Border)) g.DrawPath(p, path);
        }
    }
}

// Base for custom controls: transparent background (shows the card/ocean), hover/press.
public class Smooth : Control {
    protected bool Hover, Down;
    public Smooth() {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint |
                 ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
        BackColor = Color.Transparent; TabStop = false; Cursor = Cursors.Hand;
    }
    protected override void OnMouseEnter(EventArgs e) { Hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { Hover = false; Down = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { if (e.Button == MouseButtons.Left) { Down = true; Invalidate(); } base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { Down = false; Invalidate(); base.OnMouseUp(e); }
    protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
    protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }
    protected static float K(Graphics g) { return g.DpiX / 96f; }
    protected static void Prep(Graphics g) {
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
    }
}

// Rounded button. Style 0 = shiny ocean blue, 1 = glass, 2 = dark, 3 = shiny teal.
public class HubButton : Smooth {
    public int Style;
    public float Radius = 9;
    public double Glint = -1;   // 0..1 = glint sweeping across, <0 = none
    public string Sub;
    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics; Prep(g);
        float k = K(g);
        if (Width < 4 || Height < 4) return;
        var r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
        Color top, bot;
        if (Style == 0) { top = Color.FromArgb(46, 132, 255); bot = Color.FromArgb(14, 52, 150); }
        else if (Style == 3) { top = Color.FromArgb(20, 200, 210); bot = Color.FromArgb(8, 92, 140); }
        else if (Style == 2) { top = Color.FromArgb(225, 14, 22, 40); bot = Color.FromArgb(225, 6, 12, 26); }
        else { top = Color.FromArgb(60, 140, 190, 255); bot = Color.FromArgb(40, 60, 110, 200); }
        if (!Enabled) { top = Color.FromArgb(30, 150, 170, 200); bot = top; }
        else if (Down) { top = Gfx.Mix(top, Color.Black, 0.22f); bot = Gfx.Mix(bot, Color.Black, 0.22f); }
        else if (Hover) { top = Gfx.Mix(top, Color.White, 0.14f); bot = Gfx.Mix(bot, Color.White, 0.1f); }
        bool shiny = (Style == 0 || Style == 3) && Enabled;
        using (var path = Gfx.Round(r, Radius * k)) {
            using (var br = new LinearGradientBrush(r, top, bot, 90f)) g.FillPath(br, path);
            if (shiny) {
                var hr = new RectangleF(r.X + 2 * k, r.Y + 1.5f * k, r.Width - 4 * k, r.Height * 0.46f);
                using (var hp = Gfx.Round(hr, Math.Max(1, Radius * k - 2)))
                using (var hb = new LinearGradientBrush(new RectangleF(hr.X, hr.Y - 1, hr.Width, hr.Height + 2), Color.FromArgb(90, 255, 255, 255), Color.FromArgb(4, 255, 255, 255), 90f))
                    g.FillPath(hb, hp);
                if (Glint >= 0 && Glint <= 1) {
                    var old = g.Clip; g.SetClip(path, CombineMode.Intersect);
                    float gx = (float)(-r.Height + Glint * (r.Width + 2 * r.Height)), gw = r.Height * 0.7f;
                    using (var gp = new GraphicsPath()) {
                        gp.AddPolygon(new[] { new PointF(gx, r.Bottom), new PointF(gx + gw, r.Bottom), new PointF(gx + gw + r.Height, r.Top), new PointF(gx + r.Height, r.Top) });
                        using (var gb = new LinearGradientBrush(new RectangleF(gx, r.Top, gw + r.Height, r.Height), Color.FromArgb(0, 255, 255, 255), Color.FromArgb(0, 255, 255, 255), 0f)) {
                            var cb = new ColorBlend(3);
                            cb.Colors = new[] { Color.FromArgb(0, 255, 255, 255), Color.FromArgb(120, 255, 255, 255), Color.FromArgb(0, 255, 255, 255) };
                            cb.Positions = new[] { 0f, 0.5f, 1f };
                            gb.InterpolationColors = cb;
                            g.FillPath(gb, gp);
                        }
                    }
                    g.Clip = old;
                }
            }
            using (var pen = new Pen(Color.FromArgb(shiny ? 90 : 60, 190, 225, 255))) g.DrawPath(pen, path);
        }
        Color fc = Enabled ? ForeColor : Theme.Faint;
        if (string.IsNullOrEmpty(Sub))
            TextRenderer.DrawText(g, Text, Font, ClientRectangle, fc, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
        else {
            var top2 = new Rectangle(0, 0, Width, (int)(Height * 0.56f));
            var bot2 = new Rectangle(0, (int)(Height * 0.6f), Width, (int)(Height * 0.36f));
            TextRenderer.DrawText(g, Text, Font, top2, fc, TextFormatFlags.HorizontalCenter | TextFormatFlags.Bottom | TextFormatFlags.SingleLine);
            using (var f = new Font("Segoe UI", 8.5f, FontStyle.Bold))
                TextRenderer.DrawText(g, Sub, f, bot2, Color.FromArgb(200, 230, 245, 255), TextFormatFlags.HorizontalCenter | TextFormatFlags.Top | TextFormatFlags.SingleLine);
        }
    }
}

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
        using (var path = Gfx.Round(r, r.Height / 2)) {
            if (on) using (var br = new LinearGradientBrush(r, Color.FromArgb(34, 211, 238), Color.FromArgb(37, 99, 235), 0f)) g.FillPath(br, path);
            else using (var br = new SolidBrush(Color.FromArgb(Hover ? 80 : 55, 150, 180, 220))) g.FillPath(br, path);
        }
        float d = r.Height - 6, x = on ? r.Right - d - 3 : r.X + 3;
        g.FillEllipse(Brushes.White, x, r.Y + 3, d, d);
    }
}

public class HelpDot : Smooth {
    public string Help;
    public Action<HelpDot, bool> HoverChanged;
    public HelpDot() { Cursor = Cursors.Help; }
    protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); if (HoverChanged != null) HoverChanged(this, true); }
    protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); if (HoverChanged != null) HoverChanged(this, false); }
    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics; Prep(g);
        var r = new RectangleF(1, 1, Width - 3, Height - 3);
        using (var br = new SolidBrush(Hover ? Color.White : Color.FromArgb(70, 170, 210, 255))) g.FillEllipse(br, r);
        using (var f = new Font("Segoe UI", 7.5f, FontStyle.Bold))
            TextRenderer.DrawText(g, "?", f, Rectangle.Round(r), Hover ? Color.FromArgb(8, 30, 70) : Color.White,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
    }
}

public class NavItem : Smooth {
    public bool Selected; public int Icon;
    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics; Prep(g);
        float k = K(g);
        var r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
        if (Selected || Hover)
            using (var path = Gfx.Round(r, 10 * k))
            using (var br = new LinearGradientBrush(r, Color.FromArgb(Selected ? 90 : 40, 56, 189, 248), Color.FromArgb(Selected ? 40 : 15, 37, 99, 235), 0f))
                g.FillPath(br, path);
        if (Selected) using (var br = new SolidBrush(Theme.Accent)) g.FillRectangle(br, 0, Height * 0.28f, 3 * k, Height * 0.44f);
        Color c = Selected ? Theme.Txt : Theme.Dim;
        float cx = 22 * k, cy = Height / 2f, s = 7 * k;
        using (var p = new Pen(c, 1.6f * k)) {
            if (Icon == 0) { g.DrawEllipse(p, cx - s, cy - s, 2 * s, 2 * s); using (var b2 = new SolidBrush(c)) g.FillEllipse(b2, cx - 2 * k, cy - 2 * k, 4 * k, 4 * k); }
            else if (Icon == 1) {
                g.DrawEllipse(p, cx - s * 0.55f, cy - s * 0.55f, s * 1.1f, s * 1.1f);
                for (int i = 0; i < 8; i++) { double a = i * Math.PI / 4; g.DrawLine(p, cx + (float)Math.Cos(a) * s * 0.75f, cy + (float)Math.Sin(a) * s * 0.75f, cx + (float)Math.Cos(a) * s * 1.05f, cy + (float)Math.Sin(a) * s * 1.05f); }
            } else if (Icon == 2) { for (int i = -1; i <= 1; i++) g.DrawLine(p, cx - s, cy + i * s * 0.6f, cx + s, cy + i * s * 0.6f); }
            else { using (var b2 = new SolidBrush(c)) for (int i = -1; i <= 1; i++) g.FillEllipse(b2, cx + i * s * 0.8f - 1.6f * k, cy - 1.6f * k, 3.2f * k, 3.2f * k); }
        }
        var tr = new Rectangle((int)(40 * k), 0, Width - (int)(40 * k), Height);
        TextRenderer.DrawText(g, Text, Font, tr, c, TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
    }
}

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

public class TitleButton : Smooth {
    public bool IsClose;
    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics; Prep(g); float k = K(g);
        if (Hover) using (var br = new SolidBrush(IsClose ? Color.FromArgb(210, 220, 50, 70) : Color.FromArgb(50, 150, 200, 255))) g.FillRectangle(br, ClientRectangle);
        float cx = Width / 2f, cy = Height / 2f, s = 5 * k;
        using (var p = new Pen(Hover ? Color.White : Theme.Dim, 1.4f * k)) {
            if (IsClose) { g.DrawLine(p, cx - s, cy - s, cx + s, cy + s); g.DrawLine(p, cx + s, cy - s, cx - s, cy + s); }
            else g.DrawLine(p, cx - s, cy, cx + s, cy);
        }
    }
}

// Animated logo in the title bar.
public class LogoView : Smooth {
    public double Time;
    public LogoView() { Cursor = Cursors.Default; }
    protected override void OnPaint(PaintEventArgs e) { Logo.Paint(e.Graphics, new RectangleF(0, 0, Width, Height), Time, true); }
}

// Text list without the white Windows scrollbar: mouse-wheel scrolling and a thin glass thumb.
public class ScrollView : Smooth {
    public class Line { public string Text; public Color Color; public bool Bold; public float Size; public int Gap; }
    readonly List<Line> lines = new List<Line>();
    float scroll; int contentH;
    public bool Mono;
    public ScrollView() { Cursor = Cursors.Default; SetStyle(ControlStyles.Selectable, true); }
    public void SetLines(List<Line> l) { lines.Clear(); lines.AddRange(l); scroll = 0; Invalidate(); }
    public void Prepend(Line l, int max) { lines.Insert(0, l); while (lines.Count > max) lines.RemoveAt(lines.Count - 1); Invalidate(); }
    public int Count { get { return lines.Count; } }
    protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); try { Focus(); } catch { } }
    protected override void OnMouseWheel(MouseEventArgs e) {
        scroll = Math.Max(0, Math.Min(Math.Max(0, contentH - Height), scroll - e.Delta / 120f * 40));
        Invalidate(); base.OnMouseWheel(e);
    }
    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics; Prep(g); float k = K(g);
        int pad = (int)(4 * k), w = Width - (int)(14 * k), y = pad - (int)scroll;
        foreach (var l in lines) {
            using (var f = new Font(Mono ? "Consolas" : "Segoe UI", l.Size > 0 ? l.Size : 9f, l.Bold ? FontStyle.Bold : FontStyle.Regular)) {
                y += (int)(l.Gap * k);
                var sz = TextRenderer.MeasureText(g, l.Text.Length == 0 ? " " : l.Text, f, new Size(w, 10000), TextFormatFlags.WordBreak | TextFormatFlags.NoPadding);
                if (y + sz.Height > 0 && y < Height)
                    TextRenderer.DrawText(g, l.Text, f, new Rectangle(pad, y, w, sz.Height), l.Color, TextFormatFlags.WordBreak | TextFormatFlags.NoPadding);
                y += sz.Height + (int)(3 * k);
            }
        }
        contentH = y + (int)scroll + pad;
        if (contentH > Height) {
            float th = Math.Max(24 * k, Height * Height / (float)contentH), ty = (Height - th) * (scroll / Math.Max(1, contentH - Height));
            using (var path = Gfx.Round(new RectangleF(Width - 5 * k, ty, 3 * k, th), 1.5f * k))
            using (var br = new SolidBrush(Color.FromArgb(Hover ? 110 : 55, 160, 210, 255))) g.FillPath(br, path);
        }
    }
}

// One row in the module dropdown.
public class ModuleRow : Smooth {
    public ModuleInfo Info; public bool Selected;
    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics; Prep(g); float k = K(g);
        var r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
        if (Selected || Hover)
            using (var path = Gfx.Round(r, 10 * k))
            using (var br = new SolidBrush(Color.FromArgb(Selected ? 70 : 35, 56, 189, 248))) g.FillPath(br, path);
        if (Selected) using (var br = new SolidBrush(Theme.Accent)) g.FillRectangle(br, 0, Height * 0.25f, 3 * k, Height * 0.5f);
        using (var fb = new Font("Segoe UI", 10.5f, FontStyle.Bold))
        using (var fs = new Font("Segoe UI", 8.5f)) {
            int x = (int)(16 * k), y = (int)(9 * k);
            var nsz = TextRenderer.MeasureText(g, Info.Name, fb, Size.Empty, TextFormatFlags.NoPadding);
            TextRenderer.DrawText(g, Info.Name, fb, new Point(x, y), Theme.Txt, TextFormatFlags.NoPadding);
            int vx = x + nsz.Width + (int)(8 * k);
            TextRenderer.DrawText(g, Info.Ver, fs, new Point(vx, y + (int)(3 * k)), Theme.Faint, TextFormatFlags.NoPadding);
            if (Info.IsNew) {
                int px = vx + TextRenderer.MeasureText(g, Info.Ver, fs, Size.Empty, TextFormatFlags.NoPadding).Width + (int)(8 * k);
                var pr = new RectangleF(px, y + 1 * k, 38 * k, 17 * k);
                using (var pp = Gfx.Round(pr, 8.5f * k))
                using (var pb = new LinearGradientBrush(pr, Color.FromArgb(34, 211, 238), Color.FromArgb(59, 130, 246), 0f)) g.FillPath(pb, pp);
                using (var fn = new Font("Segoe UI", 7.5f, FontStyle.Bold))
                    TextRenderer.DrawText(g, "NEW", fn, Rectangle.Round(pr), Color.White, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            }
            TextRenderer.DrawText(g, Info.Desc, fs, new Rectangle(x, y + nsz.Height + (int)(4 * k), Width - x - (int)(36 * k), Height), Theme.Dim, TextFormatFlags.WordBreak | TextFormatFlags.NoPadding);
            if (Selected)
                using (var p = new Pen(Theme.Accent, 2f * k)) {
                    float cx = Width - 20 * k, cy = Height / 2f;
                    g.DrawLines(p, new[] { new PointF(cx - 6 * k, cy), new PointF(cx - 2 * k, cy + 4 * k), new PointF(cx + 6 * k, cy - 5 * k) });
                }
        }
    }
}

public class UpdateForm : Form {
    Label step; Panel track, fill; HubButton closeBtn;
    public UpdateForm(string version, bool repair) {
        FormBorderStyle = FormBorderStyle.None; StartPosition = FormStartPosition.CenterParent;
        AutoScaleDimensions = new SizeF(96f, 96f); AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(380, 150); BackColor = Color.FromArgb(6, 22, 52); ShowInTaskbar = false; Font = new Font("Segoe UI", 10f);
        Controls.Add(new Label { Text = (repair ? "Repairing v" : "Updating to v") + version, Font = new Font("Segoe UI", 13f, FontStyle.Bold),
            ForeColor = Theme.Txt, Location = new Point(20, 18), AutoSize = true });
        step = new Label { Text = "Starting", ForeColor = Theme.Dim, Location = new Point(20, 56), Size = new Size(340, 40) };
        track = new Panel { Location = new Point(20, 100), Size = new Size(340, 6), BackColor = Color.FromArgb(20, 50, 90) };
        fill = new Panel { Location = new Point(0, 0), Size = new Size(0, 6), BackColor = Theme.Accent };
        track.Controls.Add(fill);
        closeBtn = new HubButton { Text = "Close", Style = 1, Location = new Point(280, 114), Size = new Size(80, 28), ForeColor = Theme.Txt, Visible = false };
        closeBtn.Click += (s, e) => Close();
        Controls.Add(step); Controls.Add(track); Controls.Add(closeBtn);
    }
    protected override void OnPaint(PaintEventArgs e) {
        base.OnPaint(e);
        using (var p = new Pen(Theme.Edge)) e.Graphics.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
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
        using (var p = new Pen(Color.FromArgb(56, 189, 248), 4)) e.Graphics.DrawRectangle(p, 2, 2, Width - 5, Height - 5);
    }
}

// ======================= the main window =======================
public class App : Form {
    readonly string folder, scriptPath, settingsPath, targetPngPath;
    readonly Engine engine = new Engine();
    HubButton startBtn, moduleBtn, learnBtn, testBtn, resetBtn, bannerBtn, startKeyBtn, stopKeyBtn, minusBtn, plusBtn, repairBtn;
    Label statusWord, countLbl, targetName, bannerLbl, delayVal, tipLbl, modLbl;
    Card banner, tip, moduleMenu;
    OceanPanel content;
    OceanPanel[] pages;
    NavItem[] navs;
    ModuleRow[] moduleRows;
    ScrollView log, changelog;
    PictureBox targetPic;
    LogoView logoView;
    Toggle humanTgl, topTgl;
    System.Windows.Forms.Timer uiTimer, keyTimer, learnTimer, updateTimer, animTimer;
    bool loaded, busy;
    int clicks, learnCountdown, startKey = 0x78, stopKey = 0x79, capturing;
    bool[] keyWas = new bool[256];
    Release pendingUpdate, pendingRepair;
    readonly Stopwatch clock = Stopwatch.StartNew();

    public static void Run(string folder, string scriptPath) {
        Native.SetProcessDPIAware();
        Application.EnableVisualStyles();
        Application.ThreadException += (s, e) => { };   // never crash the window
        Application.Run(new App(folder, scriptPath));
    }

    protected override CreateParams CreateParams {
        get { var cp = base.CreateParams; cp.ClassStyle |= 0x20000; cp.Style |= 0x20000; return cp; }
    }
    protected override void OnHandleCreated(EventArgs e) {
        base.OnHandleCreated(e);
        try { int round = 2; Native.DwmSetWindowAttribute(Handle, 33, ref round, 4); } catch { }
    }
    protected override void OnPaintBackground(PaintEventArgs e) { Ocean.PaintBehind(e.Graphics, this); }

    // ---- factories ----
    Label L(Control parent, string text, int x, int y, int w, int h, Color c, float size, bool bold) {
        var l = new Label { Text = text, Location = new Point(x, y), ForeColor = c, BackColor = Color.Transparent,
            Font = new Font("Segoe UI", size, bold ? FontStyle.Bold : FontStyle.Regular) };
        if (w > 0) l.Size = new Size(w, h); else l.AutoSize = true;
        parent.Controls.Add(l);
        return l;
    }
    HubButton Btn(Control parent, string text, int style, int x, int y, int w, int h) {
        var b = new HubButton { Text = text, Style = style, Location = new Point(x, y), Size = new Size(w, h), ForeColor = Color.White,
            Font = new Font("Segoe UI", 9f, FontStyle.Bold) };
        parent.Controls.Add(b);
        return b;
    }
    Card CardAt(Control parent, int x, int y, int w, int h) {
        var c = new Card { Location = new Point(x, y), Size = new Size(w, h) };
        parent.Controls.Add(c);
        return c;
    }
    void Dot(Control parent, int x, int y, string help) {
        var d = new HelpDot { Location = new Point(x, y), Size = new Size(17, 17), Help = help };
        d.HoverChanged = ShowTip;
        parent.Controls.Add(d);
    }
    OceanPanel Page() {
        var p = new OceanPanel { Location = new Point(16, 14), Size = new Size(480, 492), Visible = false };
        content.Controls.Add(p);
        return p;
    }

    public App(string folder, string scriptPath) {
        this.folder = folder ?? ".";
        this.scriptPath = string.IsNullOrEmpty(scriptPath) ? Path.Combine(this.folder, "CircleTrack.ps1") : scriptPath;
        settingsPath = Path.Combine(this.folder, "circletrack-settings.txt");
        targetPngPath = Path.Combine(this.folder, "circletrack-target.png");

        Text = Info.Name;
        try { Icon = Logo.MakeIcon(); } catch { }
        Font = new Font("Segoe UI", 9.5f);
        AutoScaleDimensions = new SizeF(96f, 96f);
        AutoScaleMode = AutoScaleMode.Dpi;
        FormBorderStyle = FormBorderStyle.None;
        DoubleBuffered = true;
        BackColor = Color.FromArgb(5, 20, 50); ForeColor = Theme.Txt;
        ClientSize = new Size(680, 560);
        StartPosition = FormStartPosition.CenterScreen;
        KeyPreview = true;

        // ---- title bar ----
        var bar = new OceanPanel { Location = new Point(0, 0), Size = new Size(680, 48), Tint = Color.FromArgb(70, 0, 5, 20) };
        Controls.Add(bar);
        logoView = new LogoView { Location = new Point(12, 6), Size = new Size(36, 36) };
        bar.Controls.Add(logoView);
        var title = L(bar, Info.Name, 52, 12, 0, 0, Theme.Txt, 12f, true);
        var minB = new TitleButton { Location = new Point(592, 0), Size = new Size(44, 48) };
        var closeB = new TitleButton { Location = new Point(636, 0), Size = new Size(44, 48), IsClose = true };
        minB.Click += (s, e) => WindowState = FormWindowState.Minimized;
        closeB.Click += (s, e) => Close();
        bar.Controls.Add(minB); bar.Controls.Add(closeB);
        MouseEventHandler drag = (s, e) => { if (e.Button == MouseButtons.Left) { Native.ReleaseCapture(); Native.SendMessage(Handle, 0xA1, (IntPtr)2, IntPtr.Zero); } };
        bar.MouseDown += drag; title.MouseDown += drag; logoView.MouseDown += drag;

        // ---- sidebar ----
        var side = new OceanPanel { Location = new Point(0, 48), Size = new Size(168, 512), Tint = Color.FromArgb(55, 0, 5, 20) };
        Controls.Add(side);
        string[] names = { "Clicker", "Settings", "Update log", "Other" };
        navs = new NavItem[names.Length];
        for (int i = 0; i < names.Length; i++) {
            int idx = i;
            navs[i] = new NavItem { Text = names[i], Icon = i, Location = new Point(10, 14 + i * 44), Size = new Size(148, 38), Font = new Font("Segoe UI", 9.5f, FontStyle.Bold) };
            navs[i].Click += (s, e) => ShowPage(idx);
            side.Controls.Add(navs[i]);
        }
        modLbl = L(side, "Modified copy", 16, 430, 136, 18, Theme.Halt, 8.5f, true); modLbl.Visible = false;
        repairBtn = Btn(side, "Repair", 1, 14, 452, 140, 30); repairBtn.Visible = false;
        repairBtn.Click += (s, e) => { if (pendingRepair != null) RunInstall(pendingRepair, true); };

        // ---- content ----
        content = new OceanPanel { Location = new Point(168, 48), Size = new Size(512, 512) };
        Controls.Add(content);
        banner = CardAt(content, 16, 14, 480, 50); banner.Fill = Color.FromArgb(235, 251, 191, 36); banner.Border = Color.FromArgb(120, 255, 230, 150); banner.Visible = false;
        bannerLbl = L(banner, "Update available", 16, 14, 300, 22, Color.FromArgb(30, 25, 5), 10.5f, true);
        bannerBtn = Btn(banner, "Update now", 2, 356, 10, 112, 30);
        bannerBtn.Click += (s, e) => { if (pendingUpdate != null) RunInstall(pendingUpdate, false); };

        pages = new[] { Page(), Page(), Page(), Page() };
        BuildClicker(pages[0]);
        BuildSettings(pages[1]);
        BuildLog(pages[2]);
        BuildOther(pages[3]);

        tip = new Card { Fill = Color.FromArgb(240, 4, 14, 34), Border = Theme.Edge, Radius = 10, Visible = false, Size = new Size(240, 60) };
        tipLbl = new Label { Location = new Point(10, 8), Size = new Size(220, 44), ForeColor = Theme.Txt, BackColor = Color.Transparent, Font = new Font("Segoe UI", 8.5f) };
        tip.Controls.Add(tipLbl);
        Controls.Add(tip);

        // ---- engine wiring ----
        engine.Log = m => UI(() => AddLog(m));
        engine.State = (w, c) => UI(() => SetStatus(w, c));
        engine.Clicked = () => UI(() => { clicks++; countLbl.Text = clicks + " clicks"; });
        engine.Start();

        // ---- timers ----
        uiTimer = new System.Windows.Forms.Timer { Interval = 250 };
        uiTimer.Tick += (s, e) => UiTick();
        uiTimer.Start();
        keyTimer = new System.Windows.Forms.Timer { Interval = 40 };
        keyTimer.Tick += (s, e) => { try { KeyTick(); } catch { } };
        keyTimer.Start();
        learnTimer = new System.Windows.Forms.Timer { Interval = 1000 };
        learnTimer.Tick += (s, e) => LearnTick();
        updateTimer = new System.Windows.Forms.Timer { Interval = 60 * 1000 };
        updateTimer.Tick += (s, e) => CheckForUpdate();
        animTimer = new System.Windows.Forms.Timer { Interval = 33 };
        animTimer.Tick += (s, e) => Animate();
        animTimer.Start();

        Shown += (s, e) => {
            ActiveControl = null;
            var once = new System.Windows.Forms.Timer { Interval = 1200 };
            once.Tick += (s2, e2) => { once.Stop(); CheckForUpdate(); updateTimer.Start(); };
            once.Start();
        };
        FormClosing += (s, e) => { engine.Running = false; uiTimer.Stop(); keyTimer.Stop(); learnTimer.Stop(); updateTimer.Stop(); animTimer.Stop(); SaveSettings(); };

        SetTarget(new Target());
        ShowChangelog(Info.Changelog);
        LoadSettings();
        UpdateKeyLabels();
        UpdateModuleButton();
        ShowPage(0);
        SetStatus("IDLE", 0);
        loaded = true;
        AddLog("ready  v" + Info.Version + "  module: " + Modules.All[engine.Module].Name);
    }

    void UI(Action a) { try { if (IsHandleCreated && !IsDisposed) BeginInvoke(a); } catch { } }

    // ---------------- pages ----------------
    void BuildClicker(OceanPanel p) {
        var sc = CardAt(p, 0, 0, 480, 72);
        var cap = L(sc, "STATUS:", 18, 20, 0, 0, Theme.Dim, 15f, true);
        statusWord = L(sc, "IDLE", 18 + cap.PreferredWidth, 20, 220, 32, Theme.Status[0], 15f, true);
        countLbl = L(sc, "0 clicks", 300, 24, 162, 26, Theme.Txt, 11f, true); countLbl.TextAlign = ContentAlignment.MiddleRight;

        startBtn = Btn(p, "START", 0, 0, 86, 234, 60);
        startBtn.Radius = 14; startBtn.Font = new Font("Segoe UI", 13f, FontStyle.Bold);
        startBtn.Click += (s, e) => ToggleRunning("button");
        moduleBtn = Btn(p, "MODULE", 3, 246, 86, 234, 60);
        moduleBtn.Radius = 14; moduleBtn.Font = new Font("Segoe UI", 12f, FontStyle.Bold);
        moduleBtn.Click += (s, e) => ToggleModuleMenu();

        var lc = CardAt(p, 0, 160, 480, 330);
        log = new ScrollView { Location = new Point(12, 12), Size = new Size(456, 306), Mono = true };
        lc.Controls.Add(log);

        moduleMenu = new Card { Location = new Point(0, 154), Size = new Size(480, 16 + Modules.All.Length * 70), Fill = Color.FromArgb(245, 5, 18, 44), Visible = false };
        moduleRows = new ModuleRow[Modules.All.Length];
        for (int i = 0; i < Modules.All.Length; i++) {
            int idx = i;
            moduleRows[i] = new ModuleRow { Info = Modules.All[i], Location = new Point(8, 8 + i * 70), Size = new Size(464, 66) };
            moduleRows[i].Click += (s, e) => SelectModule(idx);
            moduleMenu.Controls.Add(moduleRows[i]);
        }
        p.Controls.Add(moduleMenu);
        moduleMenu.BringToFront();
    }

    void BuildSettings(OceanPanel p) {
        L(p, "KEYBINDS", 4, 0, 0, 0, Theme.Faint, 8.5f, true);
        var kc = CardAt(p, 0, 20, 480, 92);
        var a = L(kc, "Start", 18, 16, 0, 0, Theme.Txt, 10f, false);
        Dot(kc, 18 + a.PreferredWidth + 6, 18, "Press this key anywhere (even in the game) to start clicking. Click the box, then press the key you want.");
        startKeyBtn = Btn(kc, "F9", 1, 340, 11, 124, 30);
        startKeyBtn.Click += (s, e) => BeginCapture(1);
        var b = L(kc, "Turn off", 18, 56, 0, 0, Theme.Txt, 10f, false);
        Dot(kc, 18 + b.PreferredWidth + 6, 58, "Press this key anywhere to stop clicking right away. If both keys are the same, it switches on and off.");
        stopKeyBtn = Btn(kc, "F10", 1, 340, 51, 124, 30);
        stopKeyBtn.Click += (s, e) => BeginCapture(2);

        L(p, "TARGET", 4, 126, 0, 0, Theme.Faint, 8.5f, true);
        var tc = CardAt(p, 0, 146, 480, 100);
        targetPic = new PictureBox { Location = new Point(14, 14), Size = new Size(72, 72), SizeMode = PictureBoxSizeMode.Zoom, BackColor = Color.Transparent };
        tc.Controls.Add(targetPic);
        targetName = L(tc, "", 102, 16, 300, 22, Theme.Txt, 10.5f, true);
        Dot(tc, 446, 16, "The circle CircleTrack clicks. Press Learn target, then hover the circle in your game for 3 seconds. Test shows a box around what it finds without clicking.");
        learnBtn = Btn(tc, "Learn target", 0, 102, 54, 126, 32);
        learnBtn.Click += (s, e) => StartLearn();
        testBtn = Btn(tc, "Test", 1, 236, 54, 84, 32);
        testBtn.Click += (s, e) => DoTest();
        resetBtn = Btn(tc, "Reset", 1, 328, 54, 84, 32);
        resetBtn.Click += (s, e) => { SetTarget(new Target()); try { File.Delete(targetPngPath); } catch { } SaveSettings(); AddLog("target reset to built-in x2"); };

        L(p, "CLICKING", 4, 260, 0, 0, Theme.Faint, 8.5f, true);
        var cc = CardAt(p, 0, 280, 480, 132);
        var d1 = L(cc, "Delay after click", 18, 16, 0, 0, Theme.Txt, 10f, false);
        Dot(cc, 18 + d1.PreferredWidth + 6, 18, "How many seconds to wait after a click before looking for the next circle.");
        minusBtn = Btn(cc, "-", 1, 366, 10, 30, 28);
        delayVal = L(cc, "3s", 398, 10, 34, 28, Theme.Txt, 10.5f, true); delayVal.TextAlign = ContentAlignment.MiddleCenter;
        plusBtn = Btn(cc, "+", 1, 434, 10, 30, 28);
        minusBtn.Click += (s, e) => SetDelay(engine.Delay - 1);
        plusBtn.Click += (s, e) => SetDelay(engine.Delay + 1);
        var d2 = L(cc, "Human movement", 18, 57, 0, 0, Theme.Txt, 10f, false);
        Dot(cc, 18 + d2.PreferredWidth + 6, 59, "Moves like a person: a different speed and curve every time, sometimes misses the circle on purpose and then corrects onto it. It always ends up clicking it.");
        humanTgl = new Toggle { Location = new Point(418, 54), Size = new Size(46, 24) };
        humanTgl.Changed += (s, e) => { engine.Human = humanTgl.On; SaveSettings(); };
        cc.Controls.Add(humanTgl);
        var d3 = L(cc, "Always on top", 18, 98, 0, 0, Theme.Txt, 10f, false);
        Dot(cc, 18 + d3.PreferredWidth + 6, 100, "Keeps this window above the game so you can always see it. Don't let it cover the circle.");
        topTgl = new Toggle { Location = new Point(418, 95), Size = new Size(46, 24) };
        topTgl.Changed += (s, e) => { TopMost = topTgl.On; SaveSettings(); };
        cc.Controls.Add(topTgl);

        SoonCard(p, 426);
    }

    void SoonCard(OceanPanel p, int y) {
        var mc = CardAt(p, 0, y, 480, 44);
        mc.Fill = Color.FromArgb(60, 8, 22, 48); mc.Border = Color.FromArgb(40, 120, 190, 255);
        var soon = L(mc, "More coming soon", 18, 12, 0, 0, Theme.Faint, 10f, false);
        mc.Controls.Add(new Smiley { Location = new Point(18 + soon.PreferredWidth + 3, 13), Size = new Size(18, 18) });
    }

    void BuildLog(OceanPanel p) {
        var c = CardAt(p, 0, 0, 480, 490);
        changelog = new ScrollView { Location = new Point(16, 14), Size = new Size(448, 462) };
        c.Controls.Add(changelog);
    }

    void BuildOther(OceanPanel p) { SoonCard(p, 0); }

    void ShowPage(int i) {
        for (int j = 0; j < pages.Length; j++) { pages[j].Visible = j == i; navs[j].Selected = j == i; navs[j].Invalidate(); }
        tip.Visible = false; moduleMenu.Visible = false;
    }

    // ---------------- modules ----------------
    void ToggleModuleMenu() {
        for (int i = 0; i < moduleRows.Length; i++) { moduleRows[i].Selected = i == engine.Module; moduleRows[i].Invalidate(); }
        moduleMenu.Visible = !moduleMenu.Visible;
        if (moduleMenu.Visible) moduleMenu.BringToFront();
    }
    void SelectModule(int i) {
        engine.Module = i;
        moduleMenu.Visible = false;
        UpdateModuleButton();
        AddLog("module  " + Modules.All[i].Name + " " + Modules.All[i].Ver);
        SaveSettings();
    }
    void UpdateModuleButton() { moduleBtn.Text = "MODULE"; moduleBtn.Sub = Modules.All[engine.Module].Name; moduleBtn.Invalidate(); }

    // ---------------- animation: logo particles + button glint ----------------
    void Animate() {
        if (WindowState == FormWindowState.Minimized) return;
        double t = clock.Elapsed.TotalSeconds;
        logoView.Time = t; logoView.Invalidate();
        foreach (var b in new[] { startBtn, moduleBtn, learnBtn }) {
            if (b == null || !b.Visible) continue;
            double phase = (t + (b == moduleBtn ? 1.3 : b == learnBtn ? 2.1 : 0)) % 3.6;
            double g = phase < 1.1 ? phase / 1.1 : -1;
            if (g != b.Glint) { b.Glint = g; b.Invalidate(); }
        }
    }

    // ---------------- help tooltips ----------------
    void ShowTip(HelpDot d, bool show) {
        if (!show) { tip.Visible = false; return; }
        float k; using (var gg = CreateGraphics()) k = gg.DpiX / 96f;
        int w = (int)(240 * k), pad = (int)(11 * k);
        Size ts = TextRenderer.MeasureText(d.Help, tipLbl.Font, new Size(w - 2 * pad, 1000), TextFormatFlags.WordBreak);
        tip.Size = new Size(w, ts.Height + 2 * pad);
        tipLbl.Location = new Point(pad, pad); tipLbl.Size = new Size(w - 2 * pad, ts.Height + 2);
        tipLbl.Text = d.Help;
        Point at = PointToClient(d.Parent.PointToScreen(d.Location));
        int x = at.X + d.Width + (int)(8 * k), y = at.Y - (tip.Height - d.Height) / 2;
        if (x + tip.Width > ClientSize.Width - 4) x = at.X - tip.Width - (int)(8 * k);
        y = Math.Max((int)(50 * k), Math.Min(y, ClientSize.Height - tip.Height - 4));
        tip.Location = new Point(x, y);
        tip.Visible = true; tip.BringToFront();
    }

    // ---------------- status / log ----------------
    void SetStatus(string word, int c) { statusWord.Text = word; statusWord.ForeColor = Theme.Status[Math.Max(0, Math.Min(Theme.Status.Length - 1, c))]; }

    void AddLog(string msg) {
        log.Prepend(new ScrollView.Line { Text = DateTime.Now.ToString("HH:mm:ss") + "  " + msg, Color = Color.FromArgb(200, 222, 245), Size = 9f }, 400);
    }

    void SetDelay(int v) { engine.Delay = Math.Max(1, Math.Min(60, v)); delayVal.Text = engine.Delay + "s"; SaveSettings(); }

    // ---------------- periodic UI work + watchdog ----------------
    void UiTick() {
        try {
            var r = WindowState == FormWindowState.Minimized ? Rectangle.Empty : Bounds;
            var ex = r; if (tip.Visible) { } engine.Exclude = ex;
            if (engine.Running && (DateTime.Now - engine.Heartbeat).TotalSeconds > 10) {
                AddLog("watchdog: engine was stuck - restarted it");
                engine.Restart();
            }
        } catch { }
    }

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
    }
    void BeginCapture(int which) { capturing = which; UpdateKeyLabels(); }
    void KeyTick() {
        for (int vk = 8; vk < 255; vk++) {
            bool down = Native.KeyDown(vk);
            bool pressed = down && !keyWas[vk];
            keyWas[vk] = down;
            if (!pressed) continue;
            if (capturing != 0) {
                if (vk == 0x10 || vk == 0x11 || vk == 0x12) continue;
                if (vk != 0x1B) { if (capturing == 1) startKey = vk; else stopKey = vk; AddLog("keybind  " + (capturing == 1 ? "start" : "turn off") + " = " + KeyName(vk)); }
                capturing = 0; UpdateKeyLabels(); SaveSettings();
                return;
            }
            if (vk == startKey && vk == stopKey) ToggleRunning(KeyName(vk));
            else if (vk == startKey && !engine.Running) ToggleRunning(KeyName(vk));
            else if (vk == stopKey && engine.Running) ToggleRunning(KeyName(vk));
        }
    }

    // ---------------- target ----------------
    static Bitmap BuiltInPicture() {
        var b = new Bitmap(72, 72);
        using (var g = Graphics.FromImage(b)) {
            g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
            using (var br = new LinearGradientBrush(new Rectangle(4, 4, 64, 64), Color.FromArgb(196, 140, 255), Color.FromArgb(140, 70, 225), 90f)) g.FillEllipse(br, 4, 4, 64, 64);
            using (var f = new Font("Arial", 22, FontStyle.Bold, GraphicsUnit.Pixel)) {
                var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
                g.DrawString("x2", f, Brushes.White, new RectangleF(4, 4, 64, 64), sf);
            }
        }
        return b;
    }
    void SetTarget(Target t) {
        engine.Target = t;
        targetPic.Image = t.BuiltIn ? BuiltInPicture() : t.Picture;
        targetName.Text = t.BuiltIn ? t.Name : t.Name + "  (" + t.Diameter + " px)";
        resetBtn.Enabled = !t.BuiltIn;
    }

    // ---------------- start / stop ----------------
    void ToggleRunning(string by) {
        if (busy) return;
        engine.Running = !engine.Running;
        moduleMenu.Visible = false;
        if (engine.Running) { startBtn.Text = "STOP"; SetStatus("RUNNING", 1); AddLog("started (" + by + ")  " + Modules.All[engine.Module].Name); }
        else { startBtn.Text = "START"; SetStatus("IDLE", 0); AddLog("stopped (" + by + ")"); }
    }

    void DoTest() {
        try {
            Rectangle vs = Native.VirtualScreen;
            List<Hit> hits;
            var sw = Stopwatch.StartNew();
            using (var shot = Native.Grab(vs)) { var ex = Bounds; ex.Offset(-vs.Left, -vs.Top); hits = Detector.Find(shot, ex, engine.Target); }
            if (hits.Count > 0) {
                var box = hits[0].Box; box.Offset(vs.Left, vs.Top);
                new Flash(box).Show();
                AddLog("test  found " + hits.Count + "  best (" + (box.X + box.Width / 2) + ", " + (box.Y + box.Height / 2) + ")  " + hits[0].Score.ToString("0.00") + "  " + sw.ElapsedMilliseconds + "ms");
            } else AddLog("test  nothing found  " + sw.ElapsedMilliseconds + "ms");
        } catch (Exception ex) { AddLog("test failed: " + ex.Message); }
    }

    // ---------------- learning ----------------
    void StartLearn() { learnCountdown = 3; SetStatus("LEARNING 3", 3); learnTimer.Start(); }
    void LearnTick() {
        learnCountdown--;
        if (learnCountdown > 0) { SetStatus("LEARNING " + learnCountdown, 3); return; }
        learnTimer.Stop();
        Point p = Native.Cursor();
        string err = null; Target t = null;
        if (Bounds.Contains(p)) err = "the cursor was on this window";
        else { try { t = Learner.Learn(p, out err); } catch (Exception ex) { err = ex.Message; } }
        SetStatus(engine.Running ? "RUNNING" : "IDLE", engine.Running ? 1 : 0);
        if (t == null) { AddLog("learn  failed: " + err); return; }
        SetTarget(t); SaveSettings();
        AddLog("learn  " + t.Diameter + " px circle saved");
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
                UI(() => {
                    if (!string.IsNullOrEmpty(notes)) ShowChangelog(notes);
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
                });
            } catch (Exception ex) {
                string m = ex.Message;
                UI(() => { if (m.Contains("signed")) AddLog("security: " + m); });
            }
        });
        th.IsBackground = true; th.Start();
    }

    void ShowBanner(Release r) {
        bannerLbl.Text = "Update available: v" + r.Version;
        if (banner.Visible) return;
        banner.Visible = true;
        int shift = banner.Height + (int)(banner.Height * 12 / 50.0);
        foreach (var pg in pages) pg.Top += shift;
        Height += shift; content.Height += shift;
        foreach (Control c in Controls) if (c is OceanPanel && c.Left == 0 && c.Top > 0) c.Height += shift;
        Invalidate(true);
        Native.FlashWindow(Handle, true);
    }

    void RunInstall(Release r, bool repair) {
        if (busy) return;
        if (engine.Running) ToggleRunning("update");
        busy = true;
        SetStatus("UPDATING", 4);
        SaveSettings();
        var uf = new UpdateForm(r.Version, repair);
        uf.Shown += (s, e) => {
            var th = new Thread(() => {
                try {
                    Updater.Install(r, folder, (pct, text) => uf.BeginInvoke((Action)(() => uf.SetProgress(pct, text))));
                    uf.BeginInvoke((Action)(() => uf.SetProgress(100, "Restarting")));
                    Thread.Sleep(700);
                    UI(() => { Relaunch(); Application.Exit(); });
                } catch (Exception ex) {
                    string m = ex.Message;
                    uf.BeginInvoke((Action)(() => uf.Fail("Update failed: " + m)));
                    UI(() => { busy = false; SetStatus("IDLE", 0); AddLog("update failed: " + m); });
                }
            });
            th.IsBackground = true; th.Start();
        };
        uf.ShowDialog(this);
    }

    void Relaunch() {
        string target = Path.Combine(folder, "CircleTrack.ps1");
        if (!File.Exists(target)) target = scriptPath;
        var psi = new ProcessStartInfo("powershell.exe", "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + target + "\"");
        psi.UseShellExecute = false; psi.CreateNoWindow = true;
        Process.Start(psi);
    }

    void ShowChangelog(string text) {
        var list = new List<ScrollView.Line>();
        foreach (var raw in text.Replace("\r", "").Split('\n')) {
            string line = raw.TrimEnd();
            if (line.Length == 0) continue;
            bool head = line.StartsWith("v") && line.Length > 1 && char.IsDigit(line[1]);
            if (head) list.Add(new ScrollView.Line { Text = line + (line.TrimStart('v').StartsWith(Info.Version) ? "   (you have this)" : ""), Color = Theme.Txt, Bold = true, Size = 12f, Gap = list.Count == 0 ? 0 : 12 });
            else list.Add(new ScrollView.Line { Text = (line.StartsWith("- ") ? (char)0x2022 + "  " + line.Substring(2) : line), Color = Color.FromArgb(190, 215, 240), Size = 9.5f });
        }
        changelog.SetLines(list);
    }

    // ---------------- settings ----------------
    void LoadSettings() {
        try {
            string path = settingsPath;
            if (!File.Exists(path)) path = Path.Combine(folder, "circlesnap-settings.txt"); // from CircleSnap
            if (!File.Exists(path)) return;
            string png = File.Exists(targetPngPath) ? targetPngPath : Path.Combine(folder, "circlesnap-target.png");
            var d = new Dictionary<string, string>();
            foreach (var line in File.ReadAllLines(path)) {
                int eq = line.IndexOf('=');
                if (eq > 0) d[line.Substring(0, eq)] = line.Substring(eq + 1);
            }
            string v;
            if (d.TryGetValue("cooldown", out v)) SetDelay(int.Parse(v));
            if (d.TryGetValue("human", out v)) humanTgl.On = v == "1";
            if (d.TryGetValue("top", out v)) topTgl.On = v == "1";
            if (d.TryGetValue("startKey", out v)) startKey = int.Parse(v);
            if (d.TryGetValue("stopKey", out v)) stopKey = int.Parse(v);
            if (d.TryGetValue("module", out v)) { int m = int.Parse(v); if (m >= 0 && m < Modules.All.Length) engine.Module = m; }
            if (d.TryGetValue("window", out v)) {
                var xy = v.Split(',');
                var pos = new Point(int.Parse(xy[0]), int.Parse(xy[1]));
                if (Screen.FromPoint(pos).WorkingArea.Contains(pos)) { StartPosition = FormStartPosition.Manual; Location = pos; }
            }
            if (d.TryGetValue("target", out v) && v == "learned" && File.Exists(png)) {
                Bitmap pic;
                using (var tmp = new Bitmap(png)) pic = new Bitmap(tmp);
                SetTarget(Target.Load(d, pic));
            }
        } catch (Exception ex) { AddLog("settings: " + ex.Message); }
    }

    void SaveSettings() {
        if (!loaded) return;
        try {
            var pos = WindowState == FormWindowState.Normal ? Location : RestoreBounds.Location;
            var o = new List<string> {
                "cooldown=" + engine.Delay, "human=" + (humanTgl.On ? 1 : 0), "top=" + (topTgl.On ? 1 : 0),
                "startKey=" + startKey, "stopKey=" + stopKey, "module=" + engine.Module, "window=" + pos.X + "," + pos.Y };
            var t = engine.Target;
            if (!t.BuiltIn) { t.Save(o); t.Picture.Save(targetPngPath, ImageFormat.Png); }
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
        [System.Windows.Forms.MessageBox]::Show("CircleTrack hit an error:`n`n$($_.Exception.Message)", "CircleTrack") | Out-Null
    }
}
