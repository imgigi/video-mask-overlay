using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace WindowsMaskOverlay;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        using var app = new TrayApp();
        Application.Run();
    }
}

internal enum OverlayLevel
{
    Normal,
    TopMost,
    StrongTopMost
}

internal sealed class TrayApp : IDisposable
{
    private readonly OverlayForm overlay = new();
    private readonly NotifyIcon tray = new();
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 16 };
    private readonly ContextMenuStrip menu = new();
    private ToolStripMenuItem targetRoot = null!;
    private ToolStripTextBox hexInput = null!;
    private ToolStripTextBox opacityInput = null!;
    private IntPtr targetWindow;
    private OverlayLevel level = OverlayLevel.Normal;

    public TrayApp()
    {
        tray.Icon = SystemIcons.Application;
        tray.Text = "遮罩";
        tray.Visible = true;
        tray.ContextMenuStrip = menu;

        BuildMenu();
        overlay.Show();

        timer.Tick += (_, _) => Tick();
        timer.Start();
    }

    public void Dispose()
    {
        timer.Stop();
        tray.Visible = false;
        tray.Dispose();
        overlay.Dispose();
        menu.Dispose();
    }

    private void BuildMenu()
    {
        menu.Items.Clear();

        var enabled = new ToolStripMenuItem("启用遮罩") { Checked = overlay.EnabledOverlay, CheckOnClick = true };
        enabled.CheckedChanged += (_, _) => overlay.EnabledOverlay = enabled.Checked;
        menu.Items.Add(enabled);

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(LevelItem("普通", OverlayLevel.Normal));
        menu.Items.Add(LevelItem("置顶", OverlayLevel.TopMost));
        menu.Items.Add(LevelItem("强力置顶", OverlayLevel.StrongTopMost));

        menu.Items.Add(new ToolStripSeparator());
        targetRoot = new ToolStripMenuItem("目标窗口");
        menu.Items.Add(targetRoot);
        RefreshTargets();

        var refreshTargets = new ToolStripMenuItem("刷新窗口列表");
        refreshTargets.Click += (_, _) => RefreshTargets();
        menu.Items.Add(refreshTargets);

        menu.Items.Add(new ToolStripSeparator());
        var white = new ToolStripMenuItem("白色");
        white.Click += (_, _) => SetColor(Color.White);
        menu.Items.Add(white);

        var black = new ToolStripMenuItem("黑色");
        black.Click += (_, _) => SetColor(Color.Black);
        menu.Items.Add(black);

        hexInput = new ToolStripTextBox { Text = "#FFFFFF", ToolTipText = "Hex 颜色，例如 #FFFFFF" };
        hexInput.KeyDown += (_, e) =>
        {
            if (e.KeyCode == Keys.Enter)
            {
                ApplyHex();
                e.SuppressKeyPress = true;
            }
        };
        hexInput.Leave += (_, _) => ApplyHex();
        menu.Items.Add(new ToolStripLabel("Hex"));
        menu.Items.Add(hexInput);

        menu.Items.Add(new ToolStripSeparator());
        var opacityTrackBar = new TrackBar
        {
            Minimum = 0,
            Maximum = 100,
            Value = 90,
            TickFrequency = 10,
            Width = 180
        };
        opacityTrackBar.Scroll += (_, _) =>
        {
            overlay.OpacityPercent = opacityTrackBar.Value;
            opacityInput.Text = opacityTrackBar.Value.ToString();
        };
        menu.Items.Add(new ToolStripLabel("透明度"));
        menu.Items.Add(new ToolStripControlHost(opacityTrackBar));

        opacityInput = new ToolStripTextBox { Text = "90", ToolTipText = "透明度 0-100" };
        opacityInput.KeyDown += (_, e) =>
        {
            if (e.KeyCode == Keys.Enter)
            {
                ApplyOpacity(opacityTrackBar);
                e.SuppressKeyPress = true;
            }
        };
        opacityInput.Leave += (_, _) => ApplyOpacity(opacityTrackBar);
        menu.Items.Add(opacityInput);

        menu.Items.Add(new ToolStripSeparator());
        var chooseImage = new ToolStripMenuItem("选择图片...");
        chooseImage.Click += (_, _) => ChooseImage();
        menu.Items.Add(chooseImage);

        menu.Items.Add(new ToolStripSeparator());
        var quit = new ToolStripMenuItem("退出");
        quit.Click += (_, _) => Application.Exit();
        menu.Items.Add(quit);
    }

    private ToolStripMenuItem LevelItem(string title, OverlayLevel itemLevel)
    {
        var item = new ToolStripMenuItem(title) { Checked = level == itemLevel };
        item.Click += (_, _) =>
        {
            level = itemLevel;
            BuildMenu();
            Tick();
        };
        return item;
    }

    private void RefreshTargets()
    {
        targetRoot.DropDownItems.Clear();

        var manual = new ToolStripMenuItem("手动范围") { Checked = targetWindow == IntPtr.Zero };
        manual.Click += (_, _) =>
        {
            targetWindow = IntPtr.Zero;
            RefreshTargets();
        };
        targetRoot.DropDownItems.Add(manual);

        foreach (var window in NativeMethods.ListWindows().Take(30))
        {
            var item = new ToolStripMenuItem(window.Title) { Checked = targetWindow == window.Handle };
            item.Click += (_, _) =>
            {
                targetWindow = window.Handle;
                overlay.ResetImageLayout();
                RefreshTargets();
            };
            targetRoot.DropDownItems.Add(item);
        }
    }

    private void Tick()
    {
        if (targetWindow != IntPtr.Zero && NativeMethods.GetWindowRect(targetWindow, out var rect))
        {
            overlay.TargetBounds = Rectangle.FromLTRB(rect.Left, rect.Top, rect.Right, rect.Bottom);
        }

        overlay.ApplyLevel(level, targetWindow);
    }

    private void SetColor(Color color)
    {
        overlay.MaskColor = color;
        overlay.ClearImage();
        hexInput.Text = $"#{color.R:X2}{color.G:X2}{color.B:X2}";
    }

    private void ApplyHex()
    {
        var text = hexInput.Text.Trim();
        if (text.StartsWith("#"))
        {
            text = text[1..];
        }

        if (text.Length == 6 && int.TryParse(text, System.Globalization.NumberStyles.HexNumber, null, out var value))
        {
            SetColor(Color.FromArgb((value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff));
        }
    }

    private void ApplyOpacity(TrackBar trackBar)
    {
        if (!int.TryParse(opacityInput.Text.Trim(), out var value))
        {
            value = overlay.OpacityPercent;
        }

        value = Math.Clamp(value, 0, 100);
        overlay.OpacityPercent = value;
        trackBar.Value = value;
        opacityInput.Text = value.ToString();
    }

    private void ChooseImage()
    {
        using var dialog = new OpenFileDialog
        {
            Filter = "图片|*.png;*.jpg;*.jpeg;*.bmp;*.gif|所有文件|*.*"
        };

        if (dialog.ShowDialog() == DialogResult.OK)
        {
            overlay.LoadImage(dialog.FileName);
        }
    }
}

internal sealed class OverlayForm : Form
{
    private Image? image;
    private Rectangle imageBounds;
    private Rectangle targetBounds = new(200, 200, 900, 520);

    public OverlayForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        BackColor = Color.White;
        MaskColor = Color.White;
        OpacityPercent = 90;
        EnabledOverlay = true;
        Bounds = targetBounds;
        DoubleBuffered = true;
    }

    public bool EnabledOverlay { get; set; }
    public Color MaskColor { get; set; }
    public int OpacityPercent { get; set; }

    public Rectangle TargetBounds
    {
        get => targetBounds;
        set
        {
            if (targetBounds == value)
            {
                return;
            }

            targetBounds = value;
            ResetImageLayout();
            UpdateBounds();
        }
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= NativeMethods.WS_EX_TOOLWINDOW | NativeMethods.WS_EX_LAYERED | NativeMethods.WS_EX_TRANSPARENT | NativeMethods.WS_EX_NOACTIVATE;
            return cp;
        }
    }

    public void LoadImage(string path)
    {
        image?.Dispose();
        image = Image.FromFile(path);
        ResetImageLayout();
        UpdateBounds();
    }

    public void ClearImage()
    {
        image?.Dispose();
        image = null;
        UpdateBounds();
    }

    public void ResetImageLayout()
    {
        if (image == null)
        {
            return;
        }

        var height = Math.Max(1, targetBounds.Height);
        var width = (int)Math.Round(height * image.Width / (double)Math.Max(1, image.Height));
        imageBounds = new Rectangle(targetBounds.Left, targetBounds.Top, width, height);
    }

    public void ApplyLevel(OverlayLevel level, IntPtr targetWindow)
    {
        if (!EnabledOverlay)
        {
            Hide();
            return;
        }

        if (!Visible)
        {
            Show();
        }

        var insertAfter = level switch
        {
            OverlayLevel.TopMost => NativeMethods.HWND_TOPMOST,
            OverlayLevel.StrongTopMost => NativeMethods.HWND_TOPMOST,
            _ => targetWindow == IntPtr.Zero ? NativeMethods.HWND_TOP : targetWindow
        };

        NativeMethods.SetWindowPos(Handle, insertAfter, Left, Top, Width, Height, NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_NOMOVE | NativeMethods.SWP_NOSIZE | NativeMethods.SWP_SHOWWINDOW);
        Invalidate();
    }

    private void UpdateBounds()
    {
        Bounds = image == null ? targetBounds : Rectangle.Union(targetBounds, imageBounds);
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.HighQuality;
        e.Graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;

        if (!EnabledOverlay)
        {
            return;
        }

        var localTarget = ToLocal(targetBounds);
        if (image == null)
        {
            using var brush = new SolidBrush(Color.FromArgb(Alpha(), MaskColor));
            e.Graphics.FillRectangle(brush, localTarget);
            return;
        }

        var localImage = ToLocal(imageBounds);
        using var opaqueAttributes = ImageAttributes(1f);
        using var translucentAttributes = ImageAttributes(OpacityPercent / 100f);

        var outside = new Region(localImage);
        outside.Exclude(localTarget);
        e.Graphics.Clip = outside;
        e.Graphics.DrawImage(image, localImage, 0, 0, image.Width, image.Height, GraphicsUnit.Pixel, opaqueAttributes);

        e.Graphics.ResetClip();
        e.Graphics.SetClip(localTarget);
        e.Graphics.DrawImage(image, localImage, 0, 0, image.Width, image.Height, GraphicsUnit.Pixel, translucentAttributes);
        e.Graphics.ResetClip();
    }

    private Rectangle ToLocal(Rectangle rect)
    {
        return new Rectangle(rect.Left - Left, rect.Top - Top, rect.Width, rect.Height);
    }

    private int Alpha()
    {
        return Math.Clamp((int)Math.Round(OpacityPercent / 100.0 * 255), 0, 255);
    }

    private static System.Drawing.Imaging.ImageAttributes ImageAttributes(float opacity)
    {
        var matrix = new System.Drawing.Imaging.ColorMatrix { Matrix33 = opacity };
        var attributes = new System.Drawing.Imaging.ImageAttributes();
        attributes.SetColorMatrix(matrix, System.Drawing.Imaging.ColorMatrixFlag.Default, System.Drawing.Imaging.ColorAdjustType.Bitmap);
        return attributes;
    }
}

internal readonly record struct WindowInfo(IntPtr Handle, string Title);

internal static class NativeMethods
{
    public const int WS_EX_TRANSPARENT = 0x20;
    public const int WS_EX_LAYERED = 0x80000;
    public const int WS_EX_TOOLWINDOW = 0x80;
    public const int WS_EX_NOACTIVATE = 0x08000000;
    public const uint SWP_NOMOVE = 0x0002;
    public const uint SWP_NOSIZE = 0x0001;
    public const uint SWP_NOACTIVATE = 0x0010;
    public const uint SWP_SHOWWINDOW = 0x0040;
    public static readonly IntPtr HWND_TOP = new(0);
    public static readonly IntPtr HWND_TOPMOST = new(-1);

    public static IEnumerable<WindowInfo> ListWindows()
    {
        var currentProcess = Environment.ProcessId;
        var windows = new List<WindowInfo>();
        EnumWindows((handle, _) =>
        {
            if (!IsWindowVisible(handle) || GetWindowTextLength(handle) == 0)
            {
                return true;
            }

            GetWindowThreadProcessId(handle, out var processId);
            if (processId == currentProcess)
            {
                return true;
            }

            var builder = new StringBuilder(GetWindowTextLength(handle) + 1);
            GetWindowText(handle, builder, builder.Capacity);
            var title = builder.ToString();
            if (!string.IsNullOrWhiteSpace(title))
            {
                windows.Add(new WindowInfo(handle, title));
            }

            return true;
        }, IntPtr.Zero);

        return windows;
    }

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint flags);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr extraData);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out int processId);

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
}

[StructLayout(LayoutKind.Sequential)]
internal struct RECT
{
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}
