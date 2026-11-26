param([switch]$SelfTest, [switch]$TestDomains, [switch]$TestSubs, [switch]$TestServer, [switch]$TestDelete, [switch]$TestConnect, [switch]$TestPingStop)

if ($env:NOMIND_TEST -eq 'server') { $TestServer = $true }
elseif ($env:NOMIND_TEST -eq 'subs') { $TestSubs = $true }
elseif ($env:NOMIND_TEST -eq 'domains') { $TestDomains = $true }
elseif ($env:NOMIND_TEST -eq 'settings') { $TestSettings = $true }
elseif ($env:NOMIND_TEST -eq 'delete') { $TestDelete = $true }
elseif ($env:NOMIND_TEST -eq 'connect') { $TestConnect = $true }
elseif ($env:NOMIND_TEST -eq 'pingstop') { $TestPingStop = $true }

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
. (Join-Path $PSScriptRoot 'engine.ps1')

# один экземпляр за раз
if (!$SelfTest) {
    $script:AppMutex = New-Object System.Threading.Mutex($false, 'NOMIND_Connect_App_Mutex')
    if (!$script:AppMutex.WaitOne(0)) {
        # vtoroy zapusk: esli okno svernuto v trey - poprosim pokazat ego
        try { [IO.File]::WriteAllText((Join-Path $script:Run 'show.flag'), '1') } catch { }
        return
    }
}

[Windows.Forms.Application]::EnableVisualStyles()
[Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# ---------------- error reporting ----------------

function Write-UiError([string]$where, $ex) {
    try {
        $m = (Get-Date -Format 'HH:mm:ss') + '  ' + $where + ': ' + $ex.Message + "`r`n" + $ex.StackTrace
        [IO.File]::AppendAllText((Join-Path $script:Run 'gui.err.log'), ($m + "`r`n"), (New-Object Text.UTF8Encoding($true)))
    } catch { }
}
[Windows.Forms.Application]::SetUnhandledExceptionMode([Windows.Forms.UnhandledExceptionMode]::CatchException)
[Windows.Forms.Application]::add_ThreadException({
    param($s, $e)
    Write-UiError 'ui' $e.Exception
})
[AppDomain]::CurrentDomain.add_UnhandledException({
    param($s, $e)
    Write-UiError 'appdomain' $e.ExceptionObject
})

# ---------------- guard autostart ----------------
# Strazh pri vhode v sistemu snimaet sistemnyy proksi, esli xray ne zapushchen
# (posle zhestkogo vyklyucheniya PC internet ne propadaet). Registriruem ego,
# esli v avtozapuske net rabotayushchey zapisi.

function Ensure-GuardAutostart {
    try {
        if ((Get-AppSetting 'guardAutostart' $true) -eq $false) { return }
        $vbs = Join-Path $PSScriptRoot 'NOMINDGuard.vbs'
        if (!(Test-Path $vbs)) { return }
        $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        $name = 'NOMIND Connect Guard'
        $cur = ''
        try { $cur = [string](Get-ItemProperty $key -Name $name -ErrorAction SilentlyContinue).$name } catch { }
        if ($cur -match '"([^"]+)"') {
            if (Test-Path $Matches[1]) { return }
        } elseif ($cur) {
            return
        }
        Set-ItemProperty $key -Name $name -Value ('wscript.exe "' + $vbs + '"') -Type String
    } catch { }
}

# ---------------- nастройки и автозапуск ----------------

$script:RunKey   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$script:RunApp   = 'NOMIND Connect'
$script:RunGuard = 'NOMIND Connect Guard'

function Get-RunValue([string]$name) {
    try { return [string](Get-ItemProperty $script:RunKey -Name $name -ErrorAction SilentlyContinue).$name } catch { return '' }
}

function Set-RunValue([string]$name, [string]$value) {
    try {
        if ($value) { Set-ItemProperty $script:RunKey -Name $name -Value $value -Type String }
        else { Remove-ItemProperty $script:RunKey -Name $name -ErrorAction SilentlyContinue }
    } catch { }
}

function Get-AppSetting([string]$name, $default) {
    try {
        $s = Get-Settings
        if (!$s) { return $default }
        $p = $s.PSObject.Properties[$name]
        if ($p -and $null -ne $p.Value) { return $p.Value }
    } catch { }
    return $default
}

function Set-AppSetting([string]$name, $value) {
    try {
        $s = Get-Settings
        if (!$s) { $s = New-Object psobject }
        $s | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
        Save-Settings $s
    } catch { }
}

# ---------------- palette ----------------

$C = @{
    Bg        = [Drawing.Color]::FromArgb(20, 18, 21)
    Head      = [Drawing.Color]::FromArgb(26, 23, 28)
    Card      = [Drawing.Color]::FromArgb(32, 29, 35)
    Card2     = [Drawing.Color]::FromArgb(42, 38, 46)
    Line      = [Drawing.Color]::FromArgb(58, 53, 64)
    Text      = [Drawing.Color]::FromArgb(236, 231, 234)
    Muted     = [Drawing.Color]::FromArgb(154, 146, 156)
    Gold      = [Drawing.Color]::FromArgb(186, 94, 130)
    GoldDim   = [Drawing.Color]::FromArgb(128, 76, 100)
    Pink      = [Drawing.Color]::FromArgb(216, 152, 176)
    Rose      = [Drawing.Color]::FromArgb(94, 60, 76)
    Violet    = [Drawing.Color]::FromArgb(130, 114, 148)
    VioletDim = [Drawing.Color]::FromArgb(90, 78, 100)
    Peach     = [Drawing.Color]::FromArgb(202, 172, 146)
    Sea       = [Drawing.Color]::FromArgb(96, 154, 158)
    Yellow    = [Drawing.Color]::FromArgb(226, 188, 88)
    Dead      = [Drawing.Color]::FromArgb(122, 74, 82)
    Neon      = [Drawing.Color]::FromArgb(236, 108, 150)
    NeonDeep  = [Drawing.Color]::FromArgb(140, 56, 94)
    SeaDim    = [Drawing.Color]::FromArgb(64, 108, 114)
    Green     = [Drawing.Color]::FromArgb(104, 186, 118)
    Red       = [Drawing.Color]::FromArgb(209, 86, 92)
}

$installed = @((New-Object Drawing.Text.InstalledFontCollection).Families | ForEach-Object { $_.Name })
function Pick-Font([string[]]$names, [float]$size, $style = [Drawing.FontStyle]::Regular) {
    foreach ($n in $names) {
        if ($installed -contains $n) { return (New-Object Drawing.Font($n, $size, $style)) }
    }
    return (New-Object Drawing.Font('Segoe UI', $size, $style))
}

# Roboto is shipped inside the app folder, so it looks the same on any PC
$script:FontDir = Join-Path $PSScriptRoot 'fonts'
$script:PFC = New-Object Drawing.Text.PrivateFontCollection
if (Test-Path $script:FontDir) {
    foreach ($fn in @('Roboto-Light.ttf', 'Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Manrope.ttf')) {
        $fp = Join-Path $script:FontDir $fn
        if (Test-Path $fp) { try { $script:PFC.AddFontFile($fp) } catch { } }
    }
}
$script:Fam = @{}
foreach ($f in $script:PFC.Families) { $script:Fam[$f.Name] = $f }

function New-UI-Font([string]$family, [float]$size, $style = [Drawing.FontStyle]::Regular) {
    if ($script:Fam.ContainsKey($family)) {
        $fam = $script:Fam[$family]
        if (!$fam.IsStyleAvailable($style)) { $style = [Drawing.FontStyle]::Regular }
        return (New-Object Drawing.Font($fam, $size, $style))
    }
    return (New-Object Drawing.Font('Segoe UI', $size, $style))
}

$FHead  = New-UI-Font 'Manrope SemiBold' 26
$FTitle = New-UI-Font 'Manrope SemiBold' 13.5
$FLabel = New-UI-Font 'Manrope Medium' 11
$FBody  = New-UI-Font 'Manrope Medium' 12.5
$FMono  = Pick-Font @('Cascadia Mono', 'Consolas', 'Segoe UI') 11.5
$FPing  = New-UI-Font 'Manrope SemiBold' 12
$FSmall = New-UI-Font 'Manrope Medium' 10

function Spaced([string]$s) {
    return (($s.ToUpper() -split '') -join ' ').Trim()
}

$script:Pings = @{}
$script:Real = @{}
$script:Timer = $null
$script:Mode = 'global'

function Display-Name([string]$n) {
    $code = Get-FlagCode $n
    $rest = Strip-NodeFlags (Clear-NodeName $n)
    if ($code) { return ($code + '  ' + $rest) }
    return $rest
}

# ---------------- dark titlebar ----------------

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class Dark {
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr h, string sub, string id);
    public static void Scroll(IntPtr h) {
        try { SetWindowTheme(h, "DarkMode_Explorer", null); } catch {}
    }
    public static void Title(IntPtr h) {
        int v = 1;
        try { DwmSetWindowAttribute(h, 20, ref v, 4); } catch {}
        try { DwmSetWindowAttribute(h, 19, ref v, 4); } catch {}
    }
}
'@

Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class SlimListBox : ListBox {
    [DllImport("user32.dll")] static extern bool ShowScrollBar(IntPtr h, int bar, bool show);

    public SlimListBox() {
    }

    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            cp.Style &= ~0x00200000;
            return cp;
        }
    }

    protected override void WndProc(ref Message m) {
        base.WndProc(ref m);
        if (m.Msg == 0x0085 || m.Msg == 0x0005) {
            ShowScrollBar(Handle, 1, false);
        }
    }
}

public class NMWheel : IMessageFilter {    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);

    static Dictionary<IntPtr, int> rest = new Dictionary<IntPtr, int>();
    public static int LinesPerNotch = 3;

    static Control Find(Control root, Point p, Control best) {
        foreach (Control c in root.Controls) {
            if (!c.Visible || !c.Enabled) continue;
            bool scrollable = (c is ListBox);
            TextBoxBase tb = c as TextBoxBase;
            if (tb != null) scrollable = tb.Multiline;
            if (scrollable) {
                Rectangle r = c.RectangleToScreen(c.ClientRectangle);
                if (c is ListBox) r.Width += 22;
                if (r.Contains(p)) best = c;
            }
            best = Find(c, p, best);
        }
        return best;
    }

    public bool PreFilterMessage(ref Message m) {
        if (m.Msg != 0x020A) return false;
        int delta = (short)((m.WParam.ToInt64() >> 16) & 0xFFFF);
        if (delta == 0) return false;
        Point p = Cursor.Position;
        Control target = null;
        foreach (Form f in Application.OpenForms) {
            if (!f.Visible) continue;
            target = Find(f, p, target);
        }
        if (target == null) return false;

        int acc;
        if (!rest.TryGetValue(target.Handle, out acc)) acc = 0;
        acc += delta;
        int notches = acc / 120;
        rest[target.Handle] = acc - notches * 120;
        if (notches == 0) return true;
        int step = -notches * LinesPerNotch;

        ListBox lb = target as ListBox;
        if (lb != null) {
            int ih = Math.Max(1, lb.ItemHeight);
            int visible = Math.Max(1, lb.ClientSize.Height / ih);
            int maxTop = Math.Max(0, lb.Items.Count - visible);
            int top = lb.TopIndex + step;
            if (top < 0) top = 0;
            if (top > maxTop) top = maxTop;
            if (top != lb.TopIndex) lb.TopIndex = top;
            return true;
        }

        TextBoxBase tb2 = target as TextBoxBase;
        if (tb2 != null) {
            SendMessage(tb2.Handle, 0x00B6, IntPtr.Zero, (IntPtr)step);
            return true;
        }
        return false;
    }
}

public class DarkMenuTable : ProfessionalColorTable {
    public override Color ToolStripDropDownBackground { get { return Color.FromArgb(32, 29, 35); } }
    public override Color ImageMarginGradientBegin { get { return Color.FromArgb(32, 29, 35); } }
    public override Color ImageMarginGradientMiddle { get { return Color.FromArgb(32, 29, 35); } }
    public override Color ImageMarginGradientEnd { get { return Color.FromArgb(32, 29, 35); } }
    public override Color MenuItemSelected { get { return Color.FromArgb(48, 43, 53); } }
    public override Color MenuItemSelectedGradientBegin { get { return Color.FromArgb(48, 43, 53); } }
    public override Color MenuItemSelectedGradientEnd { get { return Color.FromArgb(48, 43, 53); } }
    public override Color MenuItemBorder { get { return Color.FromArgb(186, 94, 130); } }
    public override Color MenuBorder { get { return Color.FromArgb(88, 80, 96); } }
    public override Color SeparatorDark { get { return Color.FromArgb(58, 53, 64); } }
    public override Color SeparatorLight { get { return Color.FromArgb(20, 18, 21); } }
}
'@
Add-Type -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing' -TypeDefinition @'
using System;
using System.Drawing;
using System.Windows.Forms;
using System.Runtime.InteropServices;

// Podpis s myagkoy tenyu i nenavyazchivoy obvodkoy - chtoby tekst ne vyglyadel ploskim.
public class ShadowLabel : Label {
    public bool TextFx = true;
    public int ShadowX = 1;
    public int ShadowY = 2;

    public ShadowLabel() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.ResizeRedraw, true);
        SetStyle(ControlStyles.SupportsTransparentBackColor, true);
    }

    private static Color Darken(Color c, double k) {
        return Color.FromArgb((int)(c.R * k), (int)(c.G * k), (int)(c.B * k));
    }

    private TextFormatFlags Flags() {
        TextFormatFlags f = TextFormatFlags.NoPrefix;
        switch (TextAlign) {
            case ContentAlignment.TopLeft: f |= TextFormatFlags.Top | TextFormatFlags.Left; break;
            case ContentAlignment.TopCenter: f |= TextFormatFlags.Top | TextFormatFlags.HorizontalCenter; break;
            case ContentAlignment.TopRight: f |= TextFormatFlags.Top | TextFormatFlags.Right; break;
            case ContentAlignment.MiddleLeft: f |= TextFormatFlags.VerticalCenter | TextFormatFlags.Left; break;
            case ContentAlignment.MiddleCenter: f |= TextFormatFlags.VerticalCenter | TextFormatFlags.HorizontalCenter; break;
            case ContentAlignment.MiddleRight: f |= TextFormatFlags.VerticalCenter | TextFormatFlags.Right; break;
            case ContentAlignment.BottomLeft: f |= TextFormatFlags.Bottom | TextFormatFlags.Left; break;
            case ContentAlignment.BottomCenter: f |= TextFormatFlags.Bottom | TextFormatFlags.HorizontalCenter; break;
            default: f |= TextFormatFlags.Bottom | TextFormatFlags.Right; break;
        }
        if (AutoSize) { f |= TextFormatFlags.SingleLine; }
        else if (AutoEllipsis) { f |= TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine; }
        else { f |= TextFormatFlags.WordBreak; }
        return f;
    }

    public override Size GetPreferredSize(Size proposedSize) {
        Size s = base.GetPreferredSize(proposedSize);
        if (AutoSize) { s.Width += 3; s.Height += 4; }
        return s;
    }

    protected override void OnPaint(PaintEventArgs e) {
        base.OnPaintBackground(e);
        if (string.IsNullOrEmpty(Text)) { return; }
        Color bg = BackColor;
        if (bg.A < 255) {
            Control p = Parent;
            bg = (p != null && p.BackColor.A == 255) ? p.BackColor : Color.FromArgb(24, 22, 26);
        }
        Rectangle r = new Rectangle(Padding.Left, Padding.Top, Width - Padding.Horizontal, Height - Padding.Vertical);
        if (r.Width <= 0 || r.Height <= 0) { return; }
        TextFormatFlags f = Flags();
        Graphics g = e.Graphics;
        g.TextRenderingHint = (BackColor.A < 255) ? System.Drawing.Text.TextRenderingHint.AntiAliasGridFit : System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        if (TextFx) {
            Color outline = Darken(bg, 0.55);
            for (int dx = -1; dx <= 1; dx++) {
                for (int dy = -1; dy <= 1; dy++) {
                    if (dx == 0 && dy == 0) { continue; }
                    TextRenderer.DrawText(g, Text, Font, new Rectangle(r.X + dx, r.Y + dy, r.Width, r.Height), outline, f);
                }
            }
            Color sh = Darken(bg, 0.35);
            TextRenderer.DrawText(g, Text, Font, new Rectangle(r.X + ShadowX, r.Y + ShadowY, r.Width, r.Height), sh, f);
        }
        TextRenderer.DrawText(g, Text, Font, r, ForeColor, f);
    }
}

// Knopka s tem zhe myagkim tekstom: ten + obvodka, no bez tyazhelyh gradientov.
public class ShadowButton : Button {
    private bool hover = false;
    private bool down = false;

    public ShadowButton() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.ResizeRedraw, true);
        FlatStyle = FlatStyle.Flat;
    }

    private static Color Darken(Color c, double k) {
        return Color.FromArgb((int)(c.R * k), (int)(c.G * k), (int)(c.B * k));
    }

    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; down = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { down = true; Invalidate(); base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        Color bg = BackColor;
        if (down && FlatAppearance.MouseDownBackColor != Color.Empty) { bg = FlatAppearance.MouseDownBackColor; }
        else if (hover && FlatAppearance.MouseOverBackColor != Color.Empty) { bg = FlatAppearance.MouseOverBackColor; }
        using (SolidBrush b = new SolidBrush(bg)) { g.FillRectangle(b, ClientRectangle); }
        int bs = Math.Max(1, FlatAppearance.BorderSize);
        Color bc = FlatAppearance.BorderColor;
        if (bc == Color.Empty) { bc = Color.FromArgb(58, 53, 64); }
        using (Pen p = new Pen(bc, bs)) {
            g.DrawRectangle(p, bs / 2, bs / 2, Width - bs, Height - bs);
        }
        Rectangle r = new Rectangle(4, 2, Width - 8, Height - 4);
        if (r.Width <= 0 || r.Height <= 0) { return; }
        TextFormatFlags f = TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis;
        Color outline = Darken(bg, 0.55);
        for (int dx = -1; dx <= 1; dx++) {
            for (int dy = -1; dy <= 1; dy++) {
                if (dx == 0 && dy == 0) { continue; }
                TextRenderer.DrawText(g, Text, Font, new Rectangle(r.X + dx, r.Y + dy, r.Width, r.Height), outline, f);
            }
        }
        Color sh = Darken(bg, 0.35);
        TextRenderer.DrawText(g, Text, Font, new Rectangle(r.X + 1, r.Y + 2, r.Width, r.Height), sh, f);
        TextRenderer.DrawText(g, Text, Font, r, ForeColor, f);
    }
}

public class WinStyle {
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int idx, int val);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
    public static void Freeze(IntPtr h) { SendMessage(h, 0x000B, IntPtr.Zero, IntPtr.Zero); }
    public static void Thaw(IntPtr h) { SendMessage(h, 0x000B, (IntPtr)1, IntPtr.Zero); }
    public static void SetIcon(IntPtr h, IntPtr ico, int kind) { SendMessage(h, 0x0080, (IntPtr)kind, ico); }
    public static void HideVScroll(IntPtr h) {
        try {
            int s = GetWindowLong(h, -16);
            SetWindowLong(h, -16, s & ~0x00200000);
        } catch {}
    }
}
public class TaskbarId {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SetCurrentProcessExplicitAppUserModelID(string id);
    public static void Set(string id) { try { SetCurrentProcessExplicitAppUserModelID(id); } catch {} }
}
'@

# ---------------- painting helpers ----------------

function New-Card([int]$x, [int]$y, [int]$w, [int]$h, $parent) {
    $p = New-Object Windows.Forms.Panel
    $p.Location = New-Object Drawing.Point($x, $y)
    $p.Size = New-Object Drawing.Size($w, $h)
    $p.BackColor = $script:C.Card
    $p.Add_Paint({
        param($s, $e)
        $pen = New-Object Drawing.Pen($script:C.Line, 2)
        $e.Graphics.DrawRectangle($pen, 1, 1, ($s.Width - 3), ($s.Height - 3))
        $pen.Dispose()
    })
    $parent.Controls.Add($p)
    return $p
}

$script:Scrolls = @()
$script:ScrollTimer = $null

function Move-SlimTo($sb, [int]$y) {
    $lb = $sb.Tag.lb
    $ih = [Math]::Max(1, $lb.ItemHeight)
    $visible = [Math]::Max(1, [int][Math]::Floor($lb.ClientSize.Height / $ih))
    $total = $lb.Items.Count
    if ($total -le $visible) { return }
    $trackH = [single]($sb.Height - 8)
    $thumbH = [single][Math]::Max(26, $trackH * $visible / $total)
    $frac = ($y - 4 - $thumbH / 2) / [single]($trackH - $thumbH)
    if ($frac -lt 0) { $frac = 0 }
    if ($frac -gt 1) { $frac = 1 }
    $newTop = [int][Math]::Round($frac * ($total - $visible))
    if ($newTop -ne $lb.TopIndex) {
        [WinStyle]::Freeze($lb.Handle)
        $lb.TopIndex = $newTop
        [WinStyle]::Thaw($lb.Handle)
        $lb.Invalidate()
    }
    $sb.Invalidate()
}

function Draw-SlimScroll($sb, $e) {
    $lb = $sb.Tag.lb
    $g = $e.Graphics
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $w = [single]$sb.Width
    $h = [single]$sb.Height
    $tw = [single]4
    $track = New-RoundPath (($w - $tw) / 2) 2 $tw ($h - 4) ($tw / 2)
    $tb = New-Object Drawing.SolidBrush($script:C.Card2)
    $g.FillPath($tb, $track)
    $tb.Dispose(); $track.Dispose()

    $ih = [Math]::Max(1, $lb.ItemHeight)
    $visible = [Math]::Max(1, [int][Math]::Floor($lb.ClientSize.Height / $ih))
    $total = $lb.Items.Count
    if ($total -le $visible) { return }
    $trackH = [single]($h - 8)
    $thumbH = [single][Math]::Max(26, $trackH * $visible / $total)
    $maxTop = $total - $visible
    $top = [Math]::Min([Math]::Max($lb.TopIndex, 0), $maxTop)
    $thumbY = [single](4 + ($trackH - $thumbH) * ($top / [single]$maxTop))
    $thw = [single]8
    $thx = [single](($w - $thw) / 2)
    $thumb = New-RoundPath $thx $thumbY $thw $thumbH ($thw / 2)
    $p1 = New-Object Drawing.PointF($thx, $thumbY)
    $p2 = New-Object Drawing.PointF(($thx + $thw), ($thumbY + $thumbH))
    $br = New-Object Drawing.Drawing2D.LinearGradientBrush($p1, $p2, $script:C.Neon, $script:C.GoldDim)
    $g.FillPath($br, $thumb)
    $br.Dispose(); $thumb.Dispose()
}

function Update-SlimScroll($sb) {
    $lb = $sb.Tag.lb
    if (!$lb) { return }
    if ($lb.Items.Count -eq 0) { $sb.Visible = $false; return }
    $ih = [Math]::Max(1, $lb.ItemHeight)
    $visible = [Math]::Max(1, [int][Math]::Floor($lb.ClientSize.Height / $ih))
    $sb.Visible = ($lb.Items.Count -gt $visible)
    $sb.Invalidate()
}

function Add-SlimScroll($lb, $hostCtl) {
    $sb = New-Object Windows.Forms.Panel
    $sb.Width = 14
    $sb.Height = [Math]::Max(40, ($lb.Height - 4))
    $sb.Left = $lb.Left + $lb.Width + 2
    $sb.Top = $lb.Top + 2
    $sb.BackColor = $lb.BackColor
    try {
        $dbProp = [Windows.Forms.Control].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance, NonPublic')
        if ($dbProp) { $dbProp.SetValue($sb, $true, $null) }
    } catch { }
    $sb.Tag = @{ lb = $lb; drag = $false; lastTop = -1 }
    $sb.Cursor = 'Hand'
    $sb.Add_Paint({ param($s, $e) Draw-SlimScroll $s $e })
    $sb.Add_MouseDown({ param($s, $e) $s.Tag.drag = $true; Move-SlimTo $s $e.Y })
    $sb.Add_MouseMove({ param($s, $e) if ($s.Tag.drag) { Move-SlimTo $s $e.Y } })
    $sb.Add_MouseUp({ param($s, $e) $s.Tag.drag = $false })
    $sb.Add_MouseLeave({ param($s, $e) $s.Tag.drag = $false })
    $hostCtl.Controls.Add($sb)
    $sb.BringToFront()

    $lb.Add_Resize({
        param($s, $e)
        foreach ($b in @($script:Scrolls)) {
            if ($b.Tag.lb -eq $s) {
                $b.Left = $s.Left + $s.Width + 2
                $b.Top = $s.Top + 2
                $b.Height = [Math]::Max(40, ($s.Height - 4))
                Update-SlimScroll $b
            }
        }
    })
    $lb.Add_HandleCreated({ param($s, $e) [WinStyle]::HideVScroll($s.Handle) })

    $script:Scrolls += $sb
    if (!$script:ScrollTimer) {
        $script:ScrollTimer = New-Object Windows.Forms.Timer
        $script:ScrollTimer.Interval = 80
        $script:ScrollTimer.Add_Tick({
            foreach ($b in @($script:Scrolls)) {
                $lb = $b.Tag.lb
                if ($lb -and $b.Visible) {
                    $t = [int]$lb.TopIndex
                    if ($b.Tag.lastTop -ne $t) { $b.Tag.lastTop = $t; $b.Invalidate() }
                }
            }
        })
        $script:ScrollTimer.Start()
    }
    return $sb
}

# Myagkaya ten i obvodka dlya teksta, kotoryy risuem cherez Graphics.DrawString.
function Draw-TextFx($g, [string]$text, $font, $brush, $rect, $sf) {
    if (!$text) { return }
    $out = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(85, 7, 6, 9))
    foreach ($o in @(@(-1, 0), @(1, 0), @(0, -1), @(0, 1))) {
        $r = New-Object Drawing.RectangleF(($rect.X + $o[0]), ($rect.Y + $o[1]), $rect.Width, $rect.Height)
        $g.DrawString($text, $font, $out, $r, $sf)
    }
    $sh = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(125, 5, 4, 7))
    $r2 = New-Object Drawing.RectangleF(($rect.X + 1), ($rect.Y + 2), $rect.Width, $rect.Height)
    $g.DrawString($text, $font, $sh, $r2, $sf)
    $out.Dispose(); $sh.Dispose()
    $g.DrawString($text, $font, $brush, $rect, $sf)
}

# To zhe, no dlya teksta v tochke (levyy verhniy ugol).
function Draw-TextFxAt($g, [string]$text, $font, $brush, [single]$x, [single]$y) {
    if (!$text) { return }
    $out = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(85, 7, 6, 9))
    foreach ($o in @(@(-1, 0), @(1, 0), @(0, -1), @(0, 1))) {
        $g.DrawString($text, $font, $out, [single]($x + $o[0]), [single]($y + $o[1]))
    }
    $sh = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(125, 5, 4, 7))
    $g.DrawString($text, $font, $sh, [single]($x + 1), [single]($y + 2))
    $out.Dispose(); $sh.Dispose()
    $g.DrawString($text, $font, $brush, [single]$x, [single]$y)
}

function Style-Button($b, [bool]$primary = $false, $border = $null) {
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 3
    $b.FlatAppearance.BorderColor = $script:C.Line
    $b.FlatAppearance.MouseOverBackColor = $script:C.Card2
    $b.FlatAppearance.MouseDownBackColor = $script:C.Card2
    if ($primary) {
        $b.BackColor = $script:C.Gold
        $b.ForeColor = [Drawing.Color]::FromArgb(253, 246, 249)
        $b.FlatAppearance.BorderColor = $script:C.Gold
        $b.FlatAppearance.MouseOverBackColor = $script:C.Pink
        $b.FlatAppearance.MouseDownBackColor = $script:C.Pink
        $b.Font = $FTitle
    } else {
        $b.BackColor = $script:C.Card
        $b.ForeColor = $script:C.Text
        $b.Font = $FBody
        if ($border) { $b.FlatAppearance.BorderColor = $border }
    }
    $b.Cursor = 'Hand'
}

# Svoi dialog vmesto standartnogo MessageBox - chtoby podtverzhdeniya i oshibki
# vyglyadeli v stile prilozheniya (temnyy fon, rozovyy aktsent).
function Show-NomindBox {
    param(
        [string]$Title = 'NOMIND CONNECT',
        [string]$Message = '',
        [string]$Yes = 'OK',
        [string]$No = '',
        [switch]$Danger
    )
    $w = 480
    $textW = $w - 48
    $txtSize = [Windows.Forms.TextRenderer]::MeasureText([string]$Message, $FBody, (New-Object Drawing.Size($textW, 2000)), 'WordBreak')
    $msgH = [Math]::Max(24, [int]$txtSize.Height + 4)
    $h = 140 + $msgH

    $dlg = New-Object Windows.Forms.Form
    $dlg.Text = 'NOMIND Connect'
    $dlg.ClientSize = New-Object Drawing.Size($w, $h)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedSingle'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.ShowInTaskbar = $false
    $dlg.KeyPreview = $true
    $dlg.BackColor = $script:C.Bg
    $dlg.ForeColor = $script:C.Text
    $dlg.Font = $FBody
    $dlg.Add_Shown({ [Dark]::Title($dlg.Handle) })
    if ($form.Icon) { $dlg.Icon = $form.Icon }

    # rozovaya poloska sverkhu - aktsent v stile prilozheniya
    $line = New-Object Windows.Forms.Panel
    $line.Location = New-Object Drawing.Point(0, 0)
    $line.Size = New-Object Drawing.Size($w, 3)
    $line.BackColor = $(if ($Danger) { $script:C.Red } else { $script:C.Neon })
    $dlg.Controls.Add($line)

    $t = New-Object ShadowLabel
    $t.AutoSize = $false
    $t.Location = New-Object Drawing.Point(24, 22)
    $t.Size = New-Object Drawing.Size($textW, 26)
    $t.Font = $FTitle
    $t.ForeColor = $(if ($Danger) { $script:C.Pink } else { $script:C.Text })
    $t.Text = Spaced $Title
    $dlg.Controls.Add($t)

    $m = New-Object ShadowLabel
    $m.AutoSize = $false
    $m.Location = New-Object Drawing.Point(24, 58)
    $m.Size = New-Object Drawing.Size($textW, $msgH)
    $m.Font = $FBody
    $m.ForeColor = $script:C.Muted
    $m.Text = [string]$Message
    $dlg.Controls.Add($m)

    $script:BoxResult = 'No'
    $by = $h - 24 - 38

    $bYes = New-Object ShadowButton
    $bYes.Text = $Yes
    $bYes.Size = New-Object Drawing.Size($(if ($No) { 180 } else { 160 }), 38)
    $bYes.Location = New-Object Drawing.Point(($w - 24 - $bYes.Width), $by)
    Style-Button $bYes $true
    if ($Danger) {
        $bYes.BackColor = $script:C.Red
        $bYes.FlatAppearance.BorderColor = $script:C.Red
        $bYes.FlatAppearance.MouseOverBackColor = $script:C.Pink
        $bYes.FlatAppearance.MouseDownBackColor = $script:C.Pink
    }
    $bYes.Add_Click({ $script:BoxResult = 'Yes'; $dlg.Close() })
    $dlg.Controls.Add($bYes)

    if ($No) {
        $bNo = New-Object ShadowButton
        $bNo.Text = $No
        $bNo.Size = New-Object Drawing.Size(150, 38)
        $bNo.Location = New-Object Drawing.Point(($bYes.Left - 12 - $bNo.Width), $by)
        Style-Button $bNo
        $bNo.Add_Click({ $script:BoxResult = 'No'; $dlg.Close() })
        $dlg.Controls.Add($bNo)
    }

    $dlg.AcceptButton = $bYes
    if ($No) { $dlg.CancelButton = $bNo }
    $dlg.Add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq [Windows.Forms.Keys]::Escape) { $script:BoxResult = 'No'; $s.Close() }
    })

    [void]$dlg.ShowDialog($(if ([Windows.Forms.Form]::ActiveForm -and [Windows.Forms.Form]::ActiveForm -ne $dlg) { [Windows.Forms.Form]::ActiveForm } else { $form }))
    $dlg.Dispose()
    return $script:BoxResult
}

# ---------------- main form ----------------

$form = New-Object Windows.Forms.Form
$form.Text = 'NOMIND Connect'
$form.FormBorderStyle = 'FixedSingle'
$form.ClientSize = New-Object Drawing.Size(1000, 830)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $script:C.Bg
$form.ForeColor = $script:C.Text
$form.Font = $FBody
$form.MaximizeBox = $false

$script:IcoPath = Join-Path $PSScriptRoot 'nomind.ico'
$script:IcoBig = $null
$script:IcoSmall = $null
if (Test-Path $script:IcoPath) {
    try { $script:IcoBig = New-Object Drawing.Icon($script:IcoPath, 32, 32) } catch { }
    try { $script:IcoSmall = New-Object Drawing.Icon($script:IcoPath, 16, 16) } catch { }
    if ($script:IcoBig) { $form.Icon = $script:IcoBig }
    elseif ($script:IcoSmall) { $form.Icon = $script:IcoSmall }
}

# svoi AppUserModelID: zadacha v paneli zadach ne lipaet k powershell.exe
try { [TaskbarId]::Set('NOMIND.Connect') } catch { }

$form.Add_HandleCreated({
    param($s, $e)
    try {
        if ($script:IcoBig) { [WinStyle]::SetIcon($s.Handle, $script:IcoBig.Handle, 1) }
        if ($script:IcoSmall) {
            [WinStyle]::SetIcon($s.Handle, $script:IcoSmall.Handle, 0)
            [WinStyle]::SetIcon($s.Handle, $script:IcoSmall.Handle, 2)
        }
    } catch { }
})

# header
$pHead = New-Object Windows.Forms.Panel
$pHead.Dock = 'Top'; $pHead.Height = 118
$pHead.BackColor = $script:C.Head

$lblTitle = New-Object Windows.Forms.Panel
$lblTitle.Location = New-Object Drawing.Point(24, 8)
$lblTitle.BackColor = $script:C.Head
$script:TitleText = 'NOMIND CONNECT'
$tw = [Windows.Forms.TextRenderer]::MeasureText($script:TitleText, $FHead).Width
$lblTitle.Size = New-Object Drawing.Size(($tw + 22), 48)
$lblTitle.Add_Paint({
    param($s, $e)
    try {
        $g = $e.Graphics
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $sf = New-Object Drawing.StringFormat
        $sf.Alignment = [Drawing.StringAlignment]::Center
        $sf.LineAlignment = [Drawing.StringAlignment]::Center
        for ($r = 4; $r -ge 1; $r--) {
            $a = 12 + (4 - $r) * 12
            $gb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb($a, $script:C.Neon.R, $script:C.Neon.G, $script:C.Neon.B))
            foreach ($o in @(@(-$r, -$r), @($r, -$r), @(-$r, $r), @($r, $r), @(-$r, 0), @($r, 0), @(0, -$r), @(0, $r))) {
                $rr = New-Object Drawing.RectangleF([float]$o[0], [float]$o[1], [float]$s.Width, [float]$s.Height)
                $g.DrawString($script:TitleText, $FHead, $gb, $rr, $sf)
            }
            $gb.Dispose()
        }
        $core = New-Object Drawing.RectangleF(0, 0, [float]$s.Width, [float]$s.Height)
        $b1 = New-Object Drawing.SolidBrush($script:C.Text)
        $g.DrawString($script:TitleText, $FHead, $b1, $core, $sf)
        $b1.Dispose()
        $sf.Dispose()
    } catch { }
})

$lblState = New-Object ShadowLabel
$lblState.AutoSize = $true
$lblState.Location = New-Object Drawing.Point(26, 72)
$lblState.Font = $FLabel
$lblState.ForeColor = $script:C.Muted
$lblState.Text = Spaced 'отключено'

$lblInfo = New-Object ShadowLabel
$lblInfo.AutoSize = $true
$lblInfo.Location = New-Object Drawing.Point(150, 72)
$lblInfo.Font = $FBody
$lblInfo.ForeColor = $script:C.Muted
$lblInfo.Text = 'выберите сервер и нажмите «подключить»'

$lblExit = New-Object ShadowLabel
$lblExit.AutoSize = $false
$lblExit.Dock = 'Bottom'
$lblExit.Height = 26
$lblExit.Padding = New-Object Windows.Forms.Padding(0, 0, 20, 1)
$lblExit.TextAlign = 'MiddleRight'
$lblExit.Font = $FMono
$lblExit.ForeColor = $script:C.GoldDim
$lblExit.Text = ''

$pHead.Controls.AddRange(@($lblTitle, $lblState, $lblInfo, $lblExit))

$pAccent = New-Object Windows.Forms.Panel
$pAccent.Dock = 'Bottom'
$pAccent.Height = 2
$pAccent.Add_Paint({
    param($s, $e)
    $r = New-Object Drawing.Rectangle(0, 0, $s.Width, $s.Height)
    $br = New-Object Drawing.Drawing2D.LinearGradientBrush($r, $script:C.Gold, $script:C.Peach, 0)
    $e.Graphics.FillRectangle($br, $r)
    $br.Dispose()
})
$pHead.Controls.Add($pAccent)

$script:SheepPath = Join-Path $PSScriptRoot 'nomind.png'

# Gorizontalnaya kartinka dlya shapki: ovechka-puteshestvennitsa i siluety gorodov.
# Vse risuem vektorom odin raz v bitmap - nikakih kvadratnyh ikonok na fone.
function New-HeadScene {
    $w = 380; $h = 76
    $bm = New-Object Drawing.Bitmap $w, $h
    $g = [Drawing.Graphics]::FromImage($bm)
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $base = 70

    $brSand   = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(216, 170, 118))
    $brSandD  = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(178, 130, 84))
    $brTerra  = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(198, 124, 96))
    $brTerraD = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(158, 92, 72))
    $brTeal   = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(110, 176, 172))
    $brTealD  = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(76, 132, 132))
    $brGold   = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(218, 180, 104))
    $brGoldD  = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(174, 136, 72))
    $brCream  = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(238, 226, 206))
    $brCreamD = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(206, 190, 166))
    $brDark   = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(34, 29, 36))
    $brPink   = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(236, 108, 150))
    $brFar    = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(46, 40, 50))

    $outline = New-Object Drawing.Pen([Drawing.Color]::FromArgb(215, 36, 30, 38), [single]1.15)
    $outline.StartCap = [Drawing.Drawing2D.LineCap]::Round
    $outline.EndCap = [Drawing.Drawing2D.LineCap]::Round
    $pinkPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(235, 236, 108, 150), [single]1.8)
    $pinkPen.StartCap = [Drawing.Drawing2D.LineCap]::Round
    $pinkPen.EndCap = [Drawing.Drawing2D.LineCap]::Round

    # dalekiy gorod (legkiy siluet, chtoby ne chitalos kak diagramma)
    $farPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(80, 92, 80, 96), [single]1.0)
    foreach ($b in @(@(294, 58, 9, 12), @(306, 52, 7, 18), @(316, 60, 11, 10), @(330, 50, 6, 20), @(340, 61, 12, 9), @(356, 55, 7, 15), @(366, 60, 10, 10))) {
        $x0 = [single]$b[0]; $y0 = [single]$b[1]; $bw = [single]$b[2]; $bh = [single]$b[3]
        $g.FillRectangle($brFar, $x0, $y0, $bw, $bh)
        $g.DrawLine($farPen, $x0, $y0, ($x0 + $bw / 2), ($y0 - 4))
        $g.DrawLine($farPen, ($x0 + $bw / 2), ($y0 - 4), ($x0 + $bw), $y0)
    }
    $farPen.Dispose()

    # marshrut: punktir i bumazhnyy samoletik
    $dash = New-Object Drawing.Pen([Drawing.Color]::FromArgb(110, 236, 108, 150), [single]1.1)
    $dash.DashStyle = [Drawing.Drawing2D.DashStyle]::Dash
    $g.DrawBezier($dash, [single]74, [single]28, [single]152, [single]2, [single]244, [single]2, [single]326, [single]13)
    $dash.Dispose()
    $plane = New-Object Drawing.Drawing2D.GraphicsPath
    $plane.AddPolygon(@(
        (New-Object Drawing.PointF([single]348, [single]13)),
        (New-Object Drawing.PointF([single]327, [single]5)),
        (New-Object Drawing.PointF([single]332, [single]13)),
        (New-Object Drawing.PointF([single]327, [single]21))
    ))
    $g.FillPath($brPink, $plane)
    $plane.Dispose()

    # Eyfeleva bashnya
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $p.FillMode = [Drawing.Drawing2D.FillMode]::Alternate
    $p.AddBezier([single]74, [single]$base, [single]80, [single]46, [single]90, [single]26, [single]96, [single]15)
    $p.AddLine([single]96, [single]15, [single]104, [single]15)
    $p.AddBezier([single]104, [single]15, [single]110, [single]26, [single]120, [single]46, [single]126, [single]$base)
    $p.AddLine([single]126, [single]$base, [single]74, [single]$base)
    $p.CloseFigure()
    $p.AddLine([single]88, [single]$base, [single]88, [single]64)
    $p.AddArc([single]88, [single]54, [single]24, [single]20, 180, 180)
    $p.AddLine([single]112, [single]$base, [single]88, [single]$base)
    $p.CloseFigure()
    $g.FillPath($brSand, $p)
    $g.DrawPath($outline, $p)
    $p.Dispose()
    $mast = New-Object Drawing.Pen([Drawing.Color]::FromArgb(235, 216, 170, 118), [single]2.0)
    $mast.StartCap = [Drawing.Drawing2D.LineCap]::Round
    $mast.EndCap = [Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($mast, [single]100, [single]15, [single]100, [single]8)
    $mast.Dispose()
    $g.FillEllipse($brTerra, [single]98, [single]5, [single]4, [single]4)
    $deck = New-Object Drawing.Pen([Drawing.Color]::FromArgb(200, 238, 226, 206), [single]1.4)
    $g.DrawLine($deck, [single]84, [single]52, [single]116, [single]52)
    $g.DrawLine($deck, [single]89, [single]41, [single]111, [single]41)
    $g.DrawLine($deck, [single]94, [single]30, [single]106, [single]30)
    $g.DrawLine($deck, [single]97, [single]21, [single]103, [single]21)
    $deck.Dispose()
    $lat = New-Object Drawing.Pen([Drawing.Color]::FromArgb(150, 178, 130, 84), [single]1.1)
    $g.DrawLine($lat, [single]84, [single]52, [single]89, [single]41)
    $g.DrawLine($lat, [single]116, [single]52, [single]111, [single]41)
    $g.DrawLine($lat, [single]89, [single]41, [single]94, [single]30)
    $g.DrawLine($lat, [single]111, [single]41, [single]106, [single]30)
    $g.DrawLine($lat, [single]94, [single]30, [single]97, [single]21)
    $g.DrawLine($lat, [single]106, [single]30, [single]103, [single]21)
    $lat.Dispose()

    # Kolizey
    $col = @(
        (New-Object Drawing.PointF([single]127, [single]$base)),
        (New-Object Drawing.PointF([single]127, [single]51)),
        (New-Object Drawing.PointF([single]132, [single]47)),
        (New-Object Drawing.PointF([single]158, [single]47)),
        (New-Object Drawing.PointF([single]164, [single]53)),
        (New-Object Drawing.PointF([single]175, [single]55)),
        (New-Object Drawing.PointF([single]175, [single]$base))
    )
    $g.FillPolygon($brSand, $col)
    $g.DrawPolygon($outline, $col)
    foreach ($ax in @(132, 139, 146, 153, 160, 167)) {
        $ay = $(if ($ax -lt 160) { 51 } else { 57 })
        $g.FillRectangle($brDark, [single]$ax, [single]$ay, [single]4, [single]6)
        $g.FillEllipse($brDark, [single]$ax, [single]($ay - 2), [single]4, [single]4)
    }
    foreach ($ax in @(132, 139, 146, 153, 160, 167)) {
        $g.FillRectangle($brDark, [single]$ax, [single]61, [single]4, [single]7)
        $g.FillEllipse($brDark, [single]$ax, [single]59, [single]4, [single]4)
    }
    $g.DrawLine($outline, [single]127, [single]59, [single]175, [single]59)

    # Statuya Svobody
    $g.FillRectangle($brSandD, [single]197, [single]61, [single]16, [single]9)
    $g.DrawRectangle($outline, [single]197, [single]61, [single]16, [single]9)
    $robe = @(
        (New-Object Drawing.PointF([single]195, [single]61)),
        (New-Object Drawing.PointF([single]199, [single]40)),
        (New-Object Drawing.PointF([single]211, [single]40)),
        (New-Object Drawing.PointF([single]216, [single]61))
    )
    $g.FillPolygon($brTeal, $robe)
    $g.DrawPolygon($outline, $robe)
    $fold = New-Object Drawing.Pen([Drawing.Color]::FromArgb(170, 76, 132, 132), [single]1.0)
    $g.DrawLine($fold, [single]203, [single]42, [single]201, [single]61)
    $g.DrawLine($fold, [single]208, [single]42, [single]210, [single]61)
    $fold.Dispose()
    $g.FillEllipse($brTeal, [single]201, [single]31, [single]9, [single]9)
    $g.DrawEllipse($outline, [single]201, [single]31, [single]9, [single]9)
    $crown = New-Object Drawing.Pen([Drawing.Color]::FromArgb(230, 110, 176, 172), [single]1.3)
    $g.DrawLine($crown, [single]203, [single]32, [single]198, [single]26)
    $g.DrawLine($crown, [single]205, [single]31, [single]203, [single]24)
    $g.DrawLine($crown, [single]207, [single]31, [single]207, [single]23)
    $g.DrawLine($crown, [single]209, [single]31, [single]211, [single]24)
    $g.DrawLine($crown, [single]211, [single]33, [single]215, [single]27)
    $crown.Dispose()
    $arm = New-Object Drawing.Pen([Drawing.Color]::FromArgb(235, 110, 176, 172), [single]2.2)
    $arm.StartCap = [Drawing.Drawing2D.LineCap]::Round
    $arm.EndCap = [Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($arm, [single]210, [single]44, [single]220, [single]30)
    $arm.Dispose()
    $g.DrawLine($outline, [single]220, [single]30, [single]220, [single]25)
    $g.FillRectangle($brGold, [single]217.5, [single]23, [single]5, [single]3)
    $g.FillEllipse($brGold, [single]217.5, [single]18, [single]5, [single]6)
    $g.FillEllipse($brCream, [single]219, [single]19.5, [single]2, [single]3)
    $g.FillRectangle($brCream, [single]189, [single]34, [single]6, [single]9)
    $g.DrawRectangle($outline, [single]189, [single]34, [single]6, [single]9)
    $g.DrawLine($outline, [single]197, [single]45, [single]194, [single]38)

    # Bolshie chasy (Big Ben)
    $g.FillRectangle($brGold, [single]248, [single]24, [single]20, [single]42)
    $g.DrawRectangle($outline, [single]248, [single]24, [single]20, [single]42)
    $g.FillRectangle($brGoldD, [single]263, [single]24, [single]5, [single]42)
    $g.FillRectangle($brGoldD, [single]246, [single]63, [single]24, [single]7)
    $g.DrawRectangle($outline, [single]246, [single]63, [single]24, [single]7)
    $roof = @(
        (New-Object Drawing.PointF([single]245, [single]24)),
        (New-Object Drawing.PointF([single]258, [single]9)),
        (New-Object Drawing.PointF([single]271, [single]24))
    )
    $g.FillPolygon($brTealD, $roof)
    $g.DrawPolygon($outline, $roof)
    $mast2 = New-Object Drawing.Pen([Drawing.Color]::FromArgb(235, 218, 180, 104), [single]1.8)
    $mast2.StartCap = [Drawing.Drawing2D.LineCap]::Round
    $mast2.EndCap = [Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($mast2, [single]258, [single]9, [single]258, [single]3)
    $mast2.Dispose()
    $g.FillEllipse($brGold, [single]256.5, [single]1, [single]3, [single]3)
    foreach ($wy in @(42, 52)) {
        $g.FillRectangle($brDark, [single]253, [single]$wy, [single]4, [single]6)
        $g.FillRectangle($brDark, [single]259, [single]$wy, [single]4, [single]6)
    }
    $g.FillEllipse($brCream, [single]252, [single]26, [single]13, [single]13)
    $g.DrawEllipse($outline, [single]252, [single]26, [single]13, [single]13)
    $hands = New-Object Drawing.Pen([Drawing.Color]::FromArgb(235, 36, 30, 38), [single]1.2)
    $g.DrawLine($hands, [single]258.5, [single]32.5, [single]258.5, [single]28.5)
    $g.DrawLine($hands, [single]258.5, [single]32.5, [single]261, [single]33.5)
    $hands.Dispose()

    # ovechka-puteshestvennitsa
    $savedState = $g.Save()
    $g.TranslateTransform([single]-6, [single]0)
    foreach ($c in @(@(-14, 0, 8), @(-6, -8, 9), @(3, -9, 9), @(11, -2, 8), @(6, 6, 8), @(-5, 7, 8), @(-13, 7, 6), @(0, 0, 11))) {
        $r = $c[2]
        $g.FillEllipse($brCreamD, [single](40 + $c[0] - $r), [single](51 + $c[1] - $r + 1), [single](2 * $r), [single](2 * $r))
    }
    foreach ($c in @(@(-14, 0, 8), @(-6, -8, 9), @(3, -9, 9), @(11, -2, 8), @(6, 6, 8), @(-5, 7, 8), @(-13, 7, 6), @(0, 0, 11))) {
        $r = $c[2]
        $g.FillEllipse($brCream, [single](40 + $c[0] - $r), [single](51 + $c[1] - $r), [single](2 * $r), [single](2 * $r))
    }
    $leg = New-Object Drawing.Pen([Drawing.Color]::FromArgb(220, 62, 54, 64), [single]2.2)
    $leg.StartCap = [Drawing.Drawing2D.LineCap]::Round
    $leg.EndCap = [Drawing.Drawing2D.LineCap]::Round
    foreach ($lx in @(36, 43, 50, 56)) {
        $g.DrawLine($leg, [single]$lx, [single]60, [single]$lx, [single]69)
    }
    $leg.Dispose()
    $g.FillEllipse($brDark, [single]50, [single]41, [single]17, [single]15)
    $g.DrawEllipse($pinkPen, [single]50, [single]41, [single]17, [single]15)
    foreach ($ear in @(@(46, 41, 7, 5), @(64, 40, 8, 5))) {
        $g.FillEllipse($brDark, [single]$ear[0], [single]$ear[1], [single]$ear[2], [single]$ear[3])
        $g.DrawEllipse($pinkPen, [single]$ear[0], [single]$ear[1], [single]$ear[2], [single]$ear[3])
    }
    $g.FillEllipse($brCream, [single]55, [single]46, [single]4, [single]4)
    $g.FillEllipse($brCream, [single]61, [single]45.5, [single]4, [single]4)
    $g.FillEllipse($brDark, [single]56.4, [single]47.4, [single]1.8, [single]1.8)
    $g.FillEllipse($brDark, [single]62.4, [single]46.9, [single]1.8, [single]1.8)
    $g.DrawArc($pinkPen, [single]56, [single]50, [single]6, [single]4, 20, 140)
    $g.FillRectangle($brTerra, [single]66, [single]58, [single]13, [single]11)
    $g.DrawRectangle($outline, [single]66, [single]58, [single]13, [single]11)
    $g.DrawLine($outline, [single]66, [single]62, [single]79, [single]62)
    $g.DrawArc($outline, [single]69, [single]54, [single]7, [single]7, 180, 180)
    $g.FillRectangle($brPink, [single]74, [single]64, [single]3, [single]3)
    $g.Restore($savedState)

    $brSand.Dispose(); $brSandD.Dispose(); $brTerra.Dispose(); $brTerraD.Dispose()
    $brTeal.Dispose(); $brTealD.Dispose(); $brGold.Dispose(); $brGoldD.Dispose()
    $brCream.Dispose(); $brCreamD.Dispose(); $brDark.Dispose(); $brPink.Dispose()
    $brFar.Dispose(); $outline.Dispose(); $pinkPen.Dispose()
    $g.Dispose()
    return $bm
}

$script:HeadScene = $null
try { $script:HeadScene = New-HeadScene } catch { $script:HeadScene = $null }

$pHead.Add_Paint({
    param($s, $e)
    try {
        if (!$script:HeadScene) { return }
        $e.Graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $e.Graphics.DrawImage($script:HeadScene, ($s.Width - 496), 8)
    } catch { }
})

$lblExit.BackColor = [Drawing.Color]::Transparent

# ---------------- shesternya: nastroyki ----------------

$pGear = New-Object Windows.Forms.Panel
$pGear.Size = New-Object Drawing.Size(40, 40)
$pGear.Location = New-Object Drawing.Point(($form.ClientSize.Width - 40 - 18), 36)
$pGear.BackColor = [Drawing.Color]::Transparent
$pGear.Cursor = 'Hand'
$pGear.Tag = @{ hover = $false }

$pGear.Add_Paint({
    param($s, $e)
    try {
        $g = $e.Graphics
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $col = $(if ($s.Tag.hover) { $script:C.Pink } else { $script:C.Muted })
        $cx = [single]($s.Width / 2.0)
        $cy = [single]($s.Height / 2.0)
        $penRing = New-Object Drawing.Pen($col, [single]4.2)
        $g.DrawEllipse($penRing, ($cx - 9.0), ($cy - 9.0), 18.0, 18.0)
        $penRing.Dispose()
        $penTooth = New-Object Drawing.Pen($col, [single]4.6)
        $penTooth.StartCap = [Drawing.Drawing2D.LineCap]::Round
        $penTooth.EndCap = [Drawing.Drawing2D.LineCap]::Round
        for ($i = 0; $i -lt 8; $i++) {
            $a = $i * [Math]::PI / 4.0
            $x1 = $cx + [Math]::Cos($a) * 9.6
            $y1 = $cy + [Math]::Sin($a) * 9.6
            $x2 = $cx + [Math]::Cos($a) * 14.2
            $y2 = $cy + [Math]::Sin($a) * 14.2
            $g.DrawLine($penTooth, [single]$x1, [single]$y1, [single]$x2, [single]$y2)
        }
        $penTooth.Dispose()
    } catch { }
})

$pGear.Add_MouseEnter({ param($s, $e) $s.Tag.hover = $true; $s.Invalidate() })
$pGear.Add_MouseLeave({ param($s, $e) $s.Tag.hover = $false; $s.Invalidate() })
$pGear.Add_Click({ Show-SettingsDialog })

$pHead.Controls.Add($pGear)
$pGear.BringToFront()

# ---------------- ikonka "obnovit podpisku" ----------------

$pSync = New-Object Windows.Forms.Panel
$pSync.Size = New-Object Drawing.Size(40, 40)
$pSync.Location = New-Object Drawing.Point(($pGear.Left - 46), 36)
$pSync.BackColor = [Drawing.Color]::Transparent
$pSync.Cursor = 'Hand'
$pSync.Tag = @{ hover = $false }

$pSync.Add_Paint({
    param($s, $e)
    try {
        $g = $e.Graphics
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $col = $(if ($s.Tag.hover) { $script:C.Pink } else { $script:C.Muted })
        $cx = [single]($s.Width / 2.0)
        $cy = [single]($s.Height / 2.0)
        $r = [single]9.0
        $pen = New-Object Drawing.Pen($col, [single]3.2)
        $pen.StartCap = [Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [Drawing.Drawing2D.LineCap]::Round
        $g.DrawArc($pen, ($cx - $r), ($cy - $r), (2 * $r), (2 * $r), 55, 280)
        $pen.Dispose()
        $a = 335 * [Math]::PI / 180.0
        $tipX = $cx + [Math]::Cos($a) * $r
        $tipY = $cy + [Math]::Sin($a) * $r
        $tx = -[Math]::Sin($a); $ty = [Math]::Cos($a)
        $nx = [Math]::Cos($a); $ny = [Math]::Sin($a)
        $br = New-Object Drawing.SolidBrush($col)
        $pts = @(
            (New-Object Drawing.PointF([single]$tipX, [single]$tipY)),
            (New-Object Drawing.PointF([single]($tipX - $tx * 8 + $nx * 4.6), [single]($tipY - $ty * 8 + $ny * 4.6))),
            (New-Object Drawing.PointF([single]($tipX - $tx * 8 - $nx * 4.6), [single]($tipY - $ty * 8 - $ny * 4.6)))
        )
        $g.FillPolygon($br, $pts)
        $br.Dispose()
    } catch { }
})

$pSync.Add_MouseEnter({ param($s, $e) $s.Tag.hover = $true; $s.Invalidate() })
$pSync.Add_MouseLeave({ param($s, $e) $s.Tag.hover = $false; $s.Invalidate() })
$pSync.Add_Click({ Start-SubRefresh })

$pHead.Controls.Add($pSync)
$pSync.BringToFront()

# podskazki k ikonkam
$script:Tips = New-Object Windows.Forms.ToolTip
$script:Tips.SetToolTip($pSync, 'Обновить подписку и проверить срок')
$script:Tips.SetToolTip($pGear, 'Настройки')

# stroka so srokom podpiski pod statusom
$lblSubBadge = New-Object ShadowLabel
$lblSubBadge.AutoSize = $false
$lblSubBadge.Location = New-Object Drawing.Point(26, 94)
$lblSubBadge.Size = New-Object Drawing.Size(460, 20)
$lblSubBadge.Font = $FLabel
$lblSubBadge.ForeColor = $script:C.GoldDim
$lblSubBadge.Text = ''
$pHead.Controls.Add($lblSubBadge)
$lblSubBadge.BringToFront()

# bottom
$pBottom = New-Object Windows.Forms.Panel
$pBottom.Dock = 'Bottom'; $pBottom.Height = 216
$pBottom.BackColor = $script:C.Bg

$pBtns = New-Object Windows.Forms.FlowLayoutPanel
$pBtns.Dock = 'Top'; $pBtns.Height = 54
$pBtns.Padding = New-Object Windows.Forms.Padding(24, 6, 0, 0)
$pBtns.WrapContents = $false
$pBtns.BackColor = $script:C.Bg

function New-RoundPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$rad) {
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $d = $rad * 2
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc(($x + $w - $d), $y, $d, $d, 270, 90)
    $path.AddArc(($x + $w - $d), ($y + $h - $d), $d, $d, 0, 90)
    $path.AddArc($x, ($y + $h - $d), $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

$script:ConnectOn = $false

function New-NeonButton([string]$text, [int]$w, [int]$h) {
    $b = New-Object Windows.Forms.Panel
    $b.Text = $text
    $b.Size = New-Object Drawing.Size($w, $h)
    $b.Margin = New-Object Windows.Forms.Padding(0, 0, 8, 0)
    $b.BackColor = $script:C.Bg
    $b.Cursor = 'Hand'
    $b.Tag = @{ hover = $false; down = $false }

    $b.Add_Paint({
        param($s, $e)
        try {
            $g = $e.Graphics
            $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $st = $s.Tag
            $on = $script:ConnectOn
            $pad = 5
            $boost = 1.0
            if ($st.hover) { $boost = 1.7 }
            if ($st.down) { $boost = 0.7 }

            $halo = New-RoundPath $pad ($pad + 1) ($s.Width - 2 * $pad - 1) ($s.Height - 2 * $pad - 3) 10
            $a1 = [int](44 * $boost); if ($a1 -gt 80) { $a1 = 80 }
            $a2 = [int](72 * $boost); if ($a2 -gt 120) { $a2 = 120 }
            $a3 = [int](104 * $boost); if ($a3 -gt 160) { $a3 = 160 }
            foreach ($h in @(@($a1, 16), @($a2, 9), @($a3, 4))) {
                $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb($h[0], $script:C.Neon.R, $script:C.Neon.G, $script:C.Neon.B), $h[1])
                $g.DrawPath($pen, $halo)
                $pen.Dispose()
            }
            $halo.Dispose()

            $bx = $pad; $by = $pad
            $bw = $s.Width - 2 * $pad - 1
            $bh = $s.Height - 2 * $pad - 1
            if ($st.down) { $bx += 1; $by += 1 }
            $path = New-RoundPath $bx $by $bw $bh 9

            if ($on) {
                $fill = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(48, 31, 40))
                $g.FillPath($fill, $path)
                $fill.Dispose()
                $pen2 = New-Object Drawing.Pen([Drawing.Color]::FromArgb(238, 142, 178), 2)
                $g.DrawPath($pen2, $path)
                $pen2.Dispose()
            } else {
                $c1 = if ($st.hover) { [Drawing.Color]::FromArgb(240, 116, 160) } else { [Drawing.Color]::FromArgb(214, 96, 138) }
                $c2 = if ($st.hover) { [Drawing.Color]::FromArgb(170, 64, 106) } else { [Drawing.Color]::FromArgb(140, 56, 94) }
                $p1 = New-Object Drawing.PointF($bx, $by)
                $p2 = New-Object Drawing.PointF(($bx + $bw), ($by + $bh))
                $lg = New-Object Drawing.Drawing2D.LinearGradientBrush($p1, $p2, $c1, $c2)
                $g.FillPath($lg, $path)
                $lg.Dispose()
                $pen2 = New-Object Drawing.Pen([Drawing.Color]::FromArgb(246, 148, 184), 2)
                $g.DrawPath($pen2, $path)
                $pen2.Dispose()
            }

            $sf = New-Object Drawing.StringFormat
            $sf.Alignment = [Drawing.StringAlignment]::Center
            $sf.LineAlignment = [Drawing.StringAlignment]::Center
            $rect = New-Object Drawing.RectangleF($bx, $by, $bw, $bh)
            $rim = New-Object Drawing.Pen([Drawing.Color]::FromArgb(190, 255, 226, 240), 1)
            $inner = New-RoundPath ($bx + 1.5) ($by + 1.5) ($bw - 3) ($bh - 3) 8
            $g.DrawPath($rim, $inner)
            $rim.Dispose(); $inner.Dispose()
            $glow = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(80, 255, 206, 228))
            foreach ($dx in -1, 0, 1) {
                foreach ($dy in -1, 0, 1) {
                    if ($dx -eq 0 -and $dy -eq 0) { continue }
                    $r2 = New-Object Drawing.RectangleF(($bx + $dx), ($by + $dy), $bw, $bh)
                    $g.DrawString([string]$s.Text, $FTitle, $glow, $r2, $sf)
                }
            }
            $glow.Dispose()
            $tb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 250, 252))
            $g.DrawString([string]$s.Text, $FTitle, $tb, $rect, $sf)
            $tb.Dispose(); $sf.Dispose(); $path.Dispose()
        } catch { }
    })

    $b.Add_MouseEnter({ param($s, $e) $s.Tag.hover = $true; $s.Invalidate() })
    $b.Add_MouseLeave({ param($s, $e) $s.Tag.hover = $false; $s.Tag.down = $false; $s.Invalidate() })
    $b.Add_MouseDown({ param($s, $e) $s.Tag.down = $true; $s.Invalidate() })
    $b.Add_MouseUp({ param($s, $e) $s.Tag.down = $false; $s.Invalidate() })

    $pBtns.Controls.Add($b)
    return $b
}

function New-PillButton([string]$text, [int]$w, [int]$h, $border) {
    $need = [Windows.Forms.TextRenderer]::MeasureText($text, $FTitle).Width + 46
    if ($w -lt $need) { $w = $need }
    $b = New-Object Windows.Forms.Panel
    $b.Text = $text
    $b.Size = New-Object Drawing.Size($w, $h)
    $b.Margin = New-Object Windows.Forms.Padding(0, 2, 8, 0)
    $b.BackColor = $script:C.Bg
    $b.Cursor = 'Hand'
    $b.Tag = @{ hover = $false; down = $false; border = $border }

    $b.Add_Paint({
        param($s, $e)
        try {
            $g = $e.Graphics
            $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $st = $s.Tag
            $bc = $s.Tag.border
            $bx = 1; $by = 3
            $bw = $s.Width - 3
            $bh = $s.Height - 7
            if ($st.down) { $by += 1 }
            $path = New-RoundPath $bx $by $bw $bh 9

            if ($st.busy) {
                $halo = New-RoundPath $bx $by $bw $bh 9
                foreach ($h in @(@(46, 6), @(34, 3))) {
                    $gp = New-Object Drawing.Pen([Drawing.Color]::FromArgb($h[0], $bc.R, $bc.G, $bc.B), $h[1])
                    $g.DrawPath($gp, $halo)
                    $gp.Dispose()
                }
                $halo.Dispose()
            }

            $fillCol = $script:C.Card
            if ($st.hover) { $fillCol = $script:C.Card2 }
            $fill = New-Object Drawing.SolidBrush($fillCol)
            $g.FillPath($fill, $path)
            $fill.Dispose()

            if ($st.busy) {
                # "dyhanie" knopki, poka idet proverka pinga
                $k = 0.5 + 0.5 * [Math]::Sin([double]$script:Pulse)
                $a = [int](30 + 46 * $k)
                $ov = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb($a, $bc.R, $bc.G, $bc.B))
                $g.FillPath($ov, $path)
                $ov.Dispose()
            }

            $pen = New-Object Drawing.Pen($bc, 2)
            $g.DrawPath($pen, $path)
            $pen.Dispose()

            $sf = New-Object Drawing.StringFormat
            $sf.Alignment = [Drawing.StringAlignment]::Center
            $sf.LineAlignment = [Drawing.StringAlignment]::Center
            $rect = New-Object Drawing.RectangleF($bx, $by, $bw, $bh)
            $tb = New-Object Drawing.SolidBrush($(if ($st.hover -or $st.busy) { $bc } else { $script:C.Text }))
            Draw-TextFx $g ([string]$s.Text) $FTitle $tb $rect $sf
            $tb.Dispose(); $sf.Dispose(); $path.Dispose()
        } catch { }
    })

    $b.Add_MouseEnter({ param($s, $e) $s.Tag.hover = $true; $s.Invalidate() })
    $b.Add_MouseLeave({ param($s, $e) $s.Tag.hover = $false; $s.Tag.down = $false; $s.Invalidate() })
    $b.Add_MouseDown({ param($s, $e) $s.Tag.down = $true; $s.Invalidate() })
    $b.Add_MouseUp({ param($s, $e) $s.Tag.down = $false; $s.Invalidate() })
    $pBtns.Controls.Add($b)
    return $b
}

function New-Btn([string]$text, [int]$w, [bool]$primary = $false, $border = $null) {
    $b = New-Object ShadowButton
    $b.Text = $text
    $fnt = if ($primary) { $FTitle } else { $FBody }
    $need = [Windows.Forms.TextRenderer]::MeasureText($text, $fnt).Width + 58
    if ($need -gt $w) { $w = $need }
    $b.Size = New-Object Drawing.Size($w, 36)
    $b.Margin = New-Object Windows.Forms.Padding(0, 0, 8, 0)
    Style-Button $b $primary $border
    $pBtns.Controls.Add($b)
    return $b
}

$btnConnect = New-NeonButton 'ПОДКЛЮЧИТЬ' 178 42
$btnTest    = New-PillButton 'Проверить все' 0 42 $script:C.Sea
$btnTestOne = New-PillButton 'Тест узла' 0 42 $script:C.SeaDim
$btnAdd     = New-PillButton 'Сервер' 0 42 $script:C.Peach
$btnDel     = New-PillButton 'Удалить' 0 42 $script:C.Red
$btnSub     = New-PillButton 'Подписка' 0 42 $script:C.Violet

# ---------------- tray ----------------

function Show-AppWindow {
    try {
        if ($form.WindowState -eq [Windows.Forms.FormWindowState]::Minimized) { $form.WindowState = 'Normal' }
        $form.Show()
        $form.Activate()
        $form.BringToFront()
    } catch { }
}

$trayMenu = New-Object Windows.Forms.ContextMenuStrip
try { $trayMenu.Renderer = New-Object Windows.Forms.ToolStripProfessionalRenderer((New-Object DarkMenuTable)) } catch { }
$trayMenu.BackColor = $script:C.Card
$trayMenu.ShowImageMargin = $false

function New-TrayItem([string]$text, $color) {
    $mi = New-Object Windows.Forms.ToolStripMenuItem($text)
    $mi.ForeColor = $color
    $mi.Font = $FBody
    $mi.BackColor = $script:C.Card
    return $mi
}

$miTrayOpen = New-TrayItem 'Открыть окно' $script:C.Pink
$miTrayOpen.Add_Click({ Show-AppWindow })
$script:TrayConn = New-TrayItem 'Подключить VPN' $script:C.Text
$script:TrayConn.Add_Click({ Do-ToggleConnect })
$miTrayPing = New-TrayItem 'Проверить все серверы' $script:C.Sea
$miTrayPing.Add_Click({ Do-PingAll })
$miTraySettings = New-TrayItem 'Настройки…' $script:C.Gold
$miTraySettings.Add_Click({ Show-AppWindow; Show-SettingsDialog })
$miTraySep = New-Object Windows.Forms.ToolStripSeparator
$miTrayExit = New-TrayItem 'Выход (выключить VPN)' $script:C.Red
$miTrayExit.Add_Click({ $script:Exiting = $true; $form.Close() })

$trayMenu.Items.AddRange(@($miTrayOpen, $script:TrayConn, $miTrayPing, $miTraySettings, $miTraySep, $miTrayExit))

$script:Tray = New-Object Windows.Forms.NotifyIcon
if ($script:IcoSmall) { $script:Tray.Icon = $script:IcoSmall }
elseif ($form.Icon) { $script:Tray.Icon = $form.Icon }
$script:Tray.Text = 'NOMIND Connect'
$script:Tray.ContextMenuStrip = $trayMenu
$script:Tray.Visible = $true
$script:Tray.Add_DoubleClick({ Show-AppWindow })
$script:Tray.Add_MouseClick({ param($s, $e) if ($e.Button -eq [Windows.Forms.MouseButtons]::Left) { Show-AppWindow } })

$txtLog = New-Object Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.Dock = 'Fill'
$txtLog.Font = $FMono
$txtLog.BackColor = $script:C.Card
$txtLog.ForeColor = $script:C.Muted
$txtLog.BorderStyle = 'FixedSingle'
$txtLog.Add_HandleCreated({ param($s, $e) [Dark]::Scroll($s.Handle) })

$pLogWrap = New-Object Windows.Forms.Panel
$pLogWrap.Dock = 'Fill'
$pLogWrap.Padding = New-Object Windows.Forms.Padding(24, 8, 24, 18)
$pLogWrap.Controls.Add($txtLog)

$pBottom.Controls.AddRange(@($pLogWrap, $pBtns))

function Log([string]$msg) {
    $line = ('{0}   {1}' -f (Get-Date -Format 'HH:mm:ss'), $msg)
    try {
        $txtLog.AppendText($line + "`r`n")
        $txtLog.SelectionStart = $txtLog.TextLength
        $txtLog.ScrollToCaret()
    } catch { }
    [Windows.Forms.Application]::DoEvents()
}

# ---------------- servers card ----------------

$cardServers = New-Card 24 116 520 480 $form
$lblServers = New-Object ShadowLabel
$lblServers.AutoSize = $true
$lblServers.Location = New-Object Drawing.Point(18, 14)
$lblServers.Font = $FLabel
$lblServers.ForeColor = $script:C.Muted
$lblServers.Text = Spaced 'серверы'
$cardServers.Controls.Add($lblServers)

$lblSrvCount = New-Object ShadowLabel
$lblSrvCount.AutoSize = $false
$lblSrvCount.Size = New-Object Drawing.Size(170, 20)
$lblSrvCount.TextAlign = 'MiddleRight'
$lblSrvCount.Location = New-Object Drawing.Point(332, 12)
$lblSrvCount.Font = $FLabel
$lblSrvCount.ForeColor = $script:C.GoldDim
$lblSrvCount.Text = ''
$cardServers.Controls.Add($lblSrvCount)

$lstServers = New-Object SlimListBox
$lstServers.Location = New-Object Drawing.Point(10, 44)
$lstServers.Size = New-Object Drawing.Size(478, 420)
$lstServers.BorderStyle = 'None'
$lstServers.BackColor = $script:C.Card
$lstServers.ForeColor = $script:C.Text
$lstServers.DrawMode = 'OwnerDrawFixed'
$lstServers.ItemHeight = 34
$lstServers.SelectionMode = 'MultiExtended'
$lstServers.IntegralHeight = $false
$lstServers.ScrollAlwaysVisible = $true
$lstServers.Font = $FBody
$lstServers.Add_HandleCreated({ param($s, $e) [Dark]::Scroll($s.Handle) })
$cardServers.Controls.Add($lstServers)
$script:SrvScroll = Add-SlimScroll $lstServers $cardServers
$script:Folded = @{}

function Draw-Flag($g, [string]$code, [single]$x, [single]$y, [single]$w, [single]$h) {
    $c = ([string]$code).Trim().ToUpper()
    if ($c.Length -ne 2) { return }   # net flaga - nichego ne risuem (nikakikh kvadratikov)
    $bar = {
        param($by, $bh, $col)
        $b = New-Object Drawing.SolidBrush($col)
        $g.FillRectangle($b, $x, $by, $w, $bh)
        $b.Dispose()
    }
    $box = {
        param($by, $bh, $col)
        $b = New-Object Drawing.SolidBrush($col)
        $g.FillRectangle($b, $x, $by, $w, $bh)
        $b.Dispose()
    }
    $third = $h / 3
    $half = $h / 2
    switch ($c) {
        'NL' { & $bar $y $third ([Drawing.Color]::FromArgb(174, 28, 40)); & $bar ($y + $third) $third ([Drawing.Color]::White); & $bar ($y + 2 * $third) $third ([Drawing.Color]::FromArgb(33, 70, 139)) }
        'DE' { & $bar $y $third ([Drawing.Color]::Black); & $bar ($y + $third) $third ([Drawing.Color]::FromArgb(221, 0, 0)); & $bar ($y + 2 * $third) $third ([Drawing.Color]::FromArgb(255, 206, 0)) }
        'AT' { & $bar $y $third ([Drawing.Color]::FromArgb(237, 41, 57)); & $bar ($y + $third) $third ([Drawing.Color]::White); & $bar ($y + 2 * $third) $third ([Drawing.Color]::FromArgb(237, 41, 57)) }
        'PL' { & $bar $y $half ([Drawing.Color]::White); & $bar ($y + $half) $half ([Drawing.Color]::FromArgb(220, 20, 60)) }
        'EE' { & $bar $y $third ([Drawing.Color]::FromArgb(0, 114, 206)); & $bar ($y + $third) $third ([Drawing.Color]::Black); & $bar ($y + 2 * $third) $third ([Drawing.Color]::White) }
        'SE' {
            & $bar $y $h ([Drawing.Color]::FromArgb(0, 106, 167))
            $b = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(254, 204, 0))
            $g.FillRectangle($b, $x, ($y + $h / 2 - 1.5), $w, 3)
            $g.FillRectangle($b, ($x + $w * 0.32), $y, ($w * 0.22), $h)
            $b.Dispose()
        }
        'DK' {
            & $bar $y $h ([Drawing.Color]::FromArgb(200, 16, 46))
            $b = New-Object Drawing.SolidBrush([Drawing.Color]::White)
            $g.FillRectangle($b, $x, ($y + $h / 2 - 1.5), $w, 3)
            $g.FillRectangle($b, ($x + $w * 0.32), $y, ($w * 0.22), $h)
            $b.Dispose()
        }
        'FI' {
            & $bar $y $h ([Drawing.Color]::White)
            $b = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(0, 47, 108))
            $g.FillRectangle($b, $x, ($y + $h / 2 - 2), $w, 4)
            $g.FillRectangle($b, ($x + $w * 0.3), $y, ($w * 0.24), $h)
            $b.Dispose()
        }
        'US' {
            for ($i = 0; $i -lt 7; $i++) {
                $b = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(178, 34, 52))
                $g.FillRectangle($b, $x, ($y + ($h / 7) * $i), $w, ($h / 7))
                $b.Dispose()
            }
            $b = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(60, 59, 110))
            $g.FillRectangle($b, $x, $y, ($w * 0.45), ($h * 0.55))
            $b.Dispose()
        }
        'FR' {
            $t = $w / 3
            $b1 = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(0, 35, 149)); $g.FillRectangle($b1, $x, $y, $t, $h); $b1.Dispose()
            $b2 = New-Object Drawing.SolidBrush([Drawing.Color]::White); $g.FillRectangle($b2, ($x + $t), $y, $t, $h); $b2.Dispose()
            $b3 = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(237, 41, 57)); $g.FillRectangle($b3, ($x + 2 * $t), $y, ($w - 2 * $t), $h); $b3.Dispose()
        }
        'IT' {
            $t = $w / 3
            $b1 = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(0, 146, 70)); $g.FillRectangle($b1, $x, $y, $t, $h); $b1.Dispose()
            $b2 = New-Object Drawing.SolidBrush([Drawing.Color]::White); $g.FillRectangle($b2, ($x + $t), $y, $t, $h); $b2.Dispose()
            $b3 = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(206, 43, 55)); $g.FillRectangle($b3, ($x + 2 * $t), $y, ($w - 2 * $t), $h); $b3.Dispose()
        }
        'TR' {
            & $bar $y $h ([Drawing.Color]::FromArgb(227, 10, 23))
            $b = New-Object Drawing.SolidBrush([Drawing.Color]::White)
            $g.FillEllipse($b, ($x + $w * 0.3), ($y + $h * 0.28), ($h * 0.44), ($h * 0.44))
            $b.Dispose()
        }
        'CH' {
            & $bar $y $h ([Drawing.Color]::FromArgb(213, 43, 30))
            $b = New-Object Drawing.SolidBrush([Drawing.Color]::White)
            $g.FillRectangle($b, ($x + $w / 2 - 1.5), ($y + $h * 0.2), 3, ($h * 0.6))
            $g.FillRectangle($b, ($x + $w * 0.28), ($y + $h / 2 - 1.5), ($w * 0.44), 3)
            $b.Dispose()
        }
        default {
            $b = New-Object Drawing.SolidBrush($script:C.Card2)
            $g.FillRectangle($b, $x, $y, $w, $h)
            $b.Dispose()
            if ($c) {
                $f = New-UI-Font 'Manrope SemiBold' 7.5
                $tb = New-Object Drawing.SolidBrush($script:C.Muted)
                $sf = New-Object Drawing.StringFormat
                $sf.Alignment = [Drawing.StringAlignment]::Center
                $sf.LineAlignment = [Drawing.StringAlignment]::Center
                $g.DrawString($c, $f, $tb, (New-Object Drawing.RectangleF($x, $y, $w, $h)), $sf)
                $tb.Dispose(); $sf.Dispose(); $f.Dispose()
            }
        }
    }
    $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(90, 84, 96), 1)
    $g.DrawRectangle($pen, $x, $y, $w, $h)
    $pen.Dispose()
}

function Draw-ServerItem($s, $e) {
    try {
        if ($e.Index -lt 0) { return }
        $item = $s.Items[$e.Index]
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $selected = (($e.State -band [Windows.Forms.DrawItemState]::Selected) -ne 0)
        $bg = if ($selected) { $script:C.Card2 } else { $script:C.Card }
        $brush = New-Object Drawing.SolidBrush($bg)
        $g.FillRectangle($brush, $e.Bounds)
        $brush.Dispose()

        if ($item.Header) {
            $sep = New-Object Drawing.Pen($script:C.Line, 1)
            $g.DrawLine($sep, $e.Bounds.X, $e.Bounds.Y, $e.Bounds.Right, $e.Bounds.Y)
            $sep.Dispose()
            $dot = New-Object Drawing.SolidBrush($item.GroupColor)
            $bx = [single]($e.Bounds.X + 14)
            $by = [single]($e.Bounds.Y + 12)
            if ($item.Collapsed) {
                $g.FillPolygon($dot, @(
                    (New-Object Drawing.PointF($bx, $by)),
                    (New-Object Drawing.PointF($bx, [single]($by + 10))),
                    (New-Object Drawing.PointF([single]($bx + 7), [single]($by + 5)))
                ))
            } else {
                $g.FillPolygon($dot, @(
                    (New-Object Drawing.PointF([single]($bx + 1), $by)),
                    (New-Object Drawing.PointF([single]($bx + 9), $by)),
                    (New-Object Drawing.PointF([single]($bx + 5), [single]($by + 6)))
                ))
            }
            $dot.Dispose()
            $bT = New-Object Drawing.SolidBrush($script:C.Text)
            Draw-TextFxAt $g ([string]$item.GroupTitle) $FLabel $bT ([single]($e.Bounds.X + 30)) ([single]($e.Bounds.Y + 8))
            $bT.Dispose()
            $until = [string]$item.GroupUntil
            if ($until) {
                $bU = New-Object Drawing.SolidBrush($item.GroupColor)
                $us = $g.MeasureString($until, $FLabel)
                Draw-TextFxAt $g $until $FLabel $bU ([single]($e.Bounds.Right - 18 - $us.Width)) ([single]($e.Bounds.Y + 8))
                $bU.Dispose()
            }
            return
        }

        $bName = New-Object Drawing.SolidBrush($script:C.Text)
        $bMute = New-Object Drawing.SolidBrush($script:C.Muted)
        $bBad  = New-Object Drawing.SolidBrush($script:C.Red)
        $bDead = New-Object Drawing.SolidBrush($script:C.Dead)
        $bGood = New-Object Drawing.SolidBrush($script:C.Green)
        $bSlow = New-Object Drawing.SolidBrush($script:C.Red)
        $bMid  = New-Object Drawing.SolidBrush($script:C.Yellow)

        $x = $e.Bounds.X + 16
        $y = $e.Bounds.Y + 6
        Draw-Flag $g ([string]$item.Code) ([single]($e.Bounds.X + 14)) ([single]($e.Bounds.Y + 10)) ([single]22) ([single]15)
        Draw-TextFxAt $g ([string]$item.Name) $FBody $bName ([single]($e.Bounds.X + 48)) ([single]$y)

        $pingText = [string]$item.Ping
        $pb = $bMute
        if ($pingText -eq 'нет') { $pb = $bDead }
        elseif ($pingText -eq 'не грузит') { $pb = $bDead }
        elseif ($item.Real) {
            $msVal = 0
            if ([int]::TryParse(($pingText -replace '[^0-9]', ''), [ref]$msVal)) {
                if ($msVal -le 450) { $pb = $bGood }
                elseif ($msVal -le 700) { $pb = $bMid }
                else { $pb = $bSlow }
            } else {
                $pb = $bSlow
            }
        }
        $size = $g.MeasureString($pingText, $FPing)
        Draw-TextFxAt $g $pingText $FPing $pb ([single]($e.Bounds.Right - 18 - $size.Width)) ([single]($y + 1))

        $bName.Dispose(); $bMute.Dispose(); $bBad.Dispose(); $bDead.Dispose(); $bGood.Dispose(); $bSlow.Dispose(); $bMid.Dispose()
    } catch {
        try {
            $m = (Get-Date -Format 'HH:mm:ss') + '  ' + $_.Exception.Message + '  |  ' + $_.ScriptStackTrace
            [IO.File]::AppendAllText((Join-Path $script:Run 'gui.err.log'), $m + "`r`n")
        } catch { }
    }
}

$lstServers.Add_DrawItem({ param($s, $e) Draw-ServerItem $s $e })

# golovki grupp ne vybirayutsya - pereskakivaem na blizhayshiy server
$lstServers.Add_SelectedIndexChanged({
    try {
        $i = $lstServers.SelectedIndex
        if ($i -lt 0 -or $i -ge $lstServers.Items.Count) { return }
        $it = $lstServers.Items[$i]
        if (!$it -or !$it.Header) { return }
        $j = $i + 1
        while ($j -lt $lstServers.Items.Count -and $lstServers.Items[$j].Header) { $j++ }
        if ($j -ge $lstServers.Items.Count) {
            $j = $i - 1
            while ($j -ge 0 -and $lstServers.Items[$j].Header) { $j-- }
        }
        if ($j -ge 0 -and $j -lt $lstServers.Items.Count) { $lstServers.SelectedIndex = $j }
    } catch { }
})

# klik po golovke gruppy svorachivaet / raskryvaet podpisku
$lstServers.Add_MouseDown({
    param($s, $e)
    try {
        if ($e.Button -ne [Windows.Forms.MouseButtons]::Left) { return }
        $i = $s.IndexFromPoint($e.Location)
        if ($i -lt 0 -or $i -ge $s.Items.Count) { return }
        $it = $s.Items[$i]
        if (!$it -or !$it.Header) { return }
        $gk = [string]$it.GroupKey
        if ($script:Folded[$gk]) { $script:Folded.Remove($gk) } else { $script:Folded[$gk] = $true }
        $sel = ''
        if ($s.SelectedIndex -ge 0 -and $s.SelectedIndex -lt $s.Items.Count) { $sel = [string]$s.Items[$s.SelectedIndex].Key }
        Refresh-Servers $sel
    } catch { }
})

$lstServers.Add_SelectedIndexChanged({ })

# ---------------- right click menu on a server ----------------

$srvMenu = New-Object Windows.Forms.ContextMenuStrip
$srvMenu.Renderer = New-Object Windows.Forms.ToolStripProfessionalRenderer((New-Object DarkMenuTable))
$srvMenu.BackColor = $script:C.Card
$srvMenu.ForeColor = $script:C.Text
$srvMenu.ShowImageMargin = $false
$srvMenu.Font = $FBody
$srvMenu.Padding = New-Object Windows.Forms.Padding(6, 5, 6, 5)

function New-MenuItem([string]$text, [Drawing.Color]$col) {
    $mi = New-Object Windows.Forms.ToolStripMenuItem($text)
    $mi.ForeColor = $col
    $mi.BackColor = $script:C.Card
    $mi.Font = $FBody
    $mi.Padding = New-Object Windows.Forms.Padding(4, 4, 4, 4)
    return $mi
}

$miVless = New-MenuItem 'Копировать vless-ссылку' $script:C.Pink
$miCopyName = New-MenuItem 'Копировать имя' $script:C.Muted
$miCopyAddr = New-MenuItem 'Копировать адрес' $script:C.Muted
$miTestNode = New-MenuItem 'Тест узла' $script:C.Sea
$miDelNode = New-MenuItem 'Удалить' $script:C.Red
$miSep = New-Object Windows.Forms.ToolStripSeparator

$srvMenu.Items.AddRange(@($miVless, $miCopyName, $miCopyAddr, $miSep, $miTestNode, $miDelNode))

$miVless.Add_Click({
    if (!$script:MenuNode) { return }
    try {
        $link = ConvertTo-VlessLink $script:MenuNode
        [Windows.Forms.Clipboard]::SetText($link)
        Log ('скопирована vless-ссылка: ' + (Display-Name $script:MenuNode.name))
    } catch {
        Log ('не смог собрать ссылку: ' + $_.Exception.Message)
    }
})

$miCopyName.Add_Click({
    if (!$script:MenuNode) { return }
    try {
        [Windows.Forms.Clipboard]::SetText([string](Display-Name $script:MenuNode.name))
        Log ('скопировано имя: ' + (Display-Name $script:MenuNode.name))
    } catch { }
})

$miCopyAddr.Add_Click({
    if (!$script:MenuNode) { return }
    try {
        [Windows.Forms.Clipboard]::SetText((Get-ServerKey $script:MenuNode))
        Log ('скопирован адрес: ' + (Get-ServerKey $script:MenuNode))
    } catch { }
})

$miTestNode.Add_Click({ if ($script:MenuNode) { Do-TestSelected (Get-ServerKey $script:MenuNode) } })
$miDelNode.Add_Click({ if ($script:MenuNode) { Do-DeleteSelected } })

$lstServers.Add_MouseDown({
    param($s, $e)
    if ($e.Button -ne [Windows.Forms.MouseButtons]::Right) { return }
    $i = $s.IndexFromPoint($e.X, $e.Y)
    if ($i -lt 0 -or $i -ge $s.Items.Count) { return }
    $it = $s.Items[$i]
    if (!$it -or $it.Header) { return }
    # pravaya knopka na odnom iz vybrannyh - sokhranyaem mnozhestvennyy vybor
    if (!$s.GetSelected($i)) { $s.SelectedIndex = $i }
    $script:MenuNode = $it.Node
    $srvMenu.Show($s, $e.Location)
})

# Delete udalyaet vse vybrannye servery
$lstServers.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq [Windows.Forms.Keys]::Delete) {
        $e.SuppressKeyPress = $true
        Do-DeleteSelected
    }
})

# dvoynoy klik po serveru = podklyuchitsya k nemu
$lstServers.Add_DoubleClick({
    try {
        $i = $lstServers.IndexFromPoint($lstServers.PointToClient([Windows.Forms.Cursor]::Position))
        if ($i -lt 0 -or $i -ge $lstServers.Items.Count) { return }
        $it = $lstServers.Items[$i]
        if (!$it -or $it.Header -or !$it.Node) { return }
        $lstServers.SelectedIndex = $i
        $script:MenuNode = $it.Node
        Log ('двойной клик: подключаюсь к ' + (Display-Name $it.Node.name))
        Do-Connect
    } catch {
        try {
            [IO.File]::AppendAllText((Join-Path $script:Run 'gui.err.log'), ((Get-Date -Format 'HH:mm:ss') + '  dblclick: ' + $_.Exception.Message + "`r`n" + $_.ScriptStackTrace + "`r`n"), (New-Object Text.UTF8Encoding($true)))
        } catch { }
    }
})

# ---------------- right column: modes ----------------

$cardMode = New-Card 560 116 416 288 $form
$lblMode = New-Object ShadowLabel
$lblMode.AutoSize = $true
$lblMode.Location = New-Object Drawing.Point(18, 14)
$lblMode.Font = $FLabel
$lblMode.ForeColor = $script:C.Muted
$lblMode.Text = Spaced 'режим'
$cardMode.Controls.Add($lblMode)

function New-ModeCard([int]$y, [string]$title, [string]$desc, [int]$hh = 118) {
    $p = New-Object Windows.Forms.Panel
    $p.Location = New-Object Drawing.Point(14, $y)
    $p.Size = New-Object Drawing.Size(388, $hh)
    $p.BackColor = $script:C.Card
    $p.Cursor = 'Hand'

    $t = New-Object ShadowLabel
    $t.AutoSize = $true
    $t.Location = New-Object Drawing.Point(30, 12)
    $t.Font = $FTitle
    $t.ForeColor = $script:C.Text
    $t.Text = $title
    $t.Cursor = 'Hand'

    $d = New-Object ShadowLabel
    $d.Location = New-Object Drawing.Point(30, 42)
    $d.Size = New-Object Drawing.Size(344, ($hh - 46))
    $d.Font = $FBody
    $d.ForeColor = $script:C.Muted
    $d.Text = $desc
    $d.Cursor = 'Hand'

    $p.Controls.AddRange(@($t, $d))
    $p.Add_Paint({
        param($s, $e)
        $on = ($s.Tag -eq 'on')
        $col = if ($on) { $script:C.Gold } else { $script:C.Line }
        $pen = New-Object Drawing.Pen($col, 2)
        $e.Graphics.DrawRectangle($pen, 1, 1, ($s.Width - 3), ($s.Height - 3))
        $pen.Dispose()
        $dot = New-Object Drawing.SolidBrush($(if ($on) { $script:C.Gold } else { $script:C.Card2 }))
        $e.Graphics.FillEllipse($dot, 10, 18, 10, 10)
        $dot.Dispose()
        if ($on) {
            $ring = New-Object Drawing.Pen($script:C.Gold, 1)
            $e.Graphics.DrawEllipse($ring, 10, 18, 10, 10)
            $ring.Dispose()
        }
    })
    $p.Add_Click({ param($s, $e) Set-ModeFromCard $s })
    $t.Add_Click({ param($s, $e) Set-ModeFromCard $s.Parent })
    $d.Add_Click({ param($s, $e) Set-ModeFromCard $s.Parent })
    return $p
}

$mdGlobal = New-ModeCard 30 'Всё, кроме русских сайтов' 'Все зарубежные сайты и всё, что заблокировано в РФ, — через VPN. Русские сайты (.ru, .рф) — напрямую.' 134
$mdSmart  = New-ModeCard 168 'Только выбранные сайты' 'Через VPN идут только домены из списка ниже. Остальное — напрямую.' 106
$cardMode.Controls.AddRange(@($mdGlobal, $mdSmart))

$lblGames = New-Object ShadowLabel
$lblGames.AutoSize = $false
$lblGames.Location = New-Object Drawing.Point(578, 414)
$lblGames.Size = New-Object Drawing.Size(402, 68)
$lblGames.Font = $FBody
$lblGames.ForeColor = $script:C.GoldDim
$lblGames.Text = 'Игры (CS2 и другие) идут напрямую — они не используют системный прокси, пинг не растёт.'

# ---------------- right column: domains ----------------

$cardDom = New-Card 560 486 416 110 $form
$lblDom = New-Object ShadowLabel
$lblDom.AutoSize = $false
$lblDom.Location = New-Object Drawing.Point(18, 12)
$lblDom.Size = New-Object Drawing.Size(360, 20)
$lblDom.Font = $FLabel
$lblDom.ForeColor = $script:C.Muted
$lblDom.Text = Spaced 'сайты через vpn'
$cardDom.Controls.Add($lblDom)

$txtAdd = New-Object Windows.Forms.TextBox
$txtAdd.Location = New-Object Drawing.Point(16, 40)
$txtAdd.Size = New-Object Drawing.Size(214, 30)
$txtAdd.Font = $FBody
$txtAdd.BackColor = $script:C.Card2
$txtAdd.ForeColor = $script:C.Text
$txtAdd.BorderStyle = 'FixedSingle'
$cardDom.Controls.Add($txtAdd)

$btnQuickAdd = New-Object ShadowButton
$btnQuickAdd.Text = '+'
$btnQuickAdd.Location = New-Object Drawing.Point(238, 39)
$btnQuickAdd.Size = New-Object Drawing.Size(40, 32)
$btnQuickAdd.Font = New-UI-Font 'Manrope SemiBold' 13
$btnQuickAdd.FlatStyle = 'Flat'
$btnQuickAdd.FlatAppearance.BorderColor = $script:C.Line
$btnQuickAdd.BackColor = $script:C.Card2
$btnQuickAdd.ForeColor = $script:C.Gold
$btnQuickAdd.Cursor = 'Hand'
$cardDom.Controls.Add($btnQuickAdd)

$btnAllDom = New-Object ShadowButton
$btnAllDom.Text = 'Все сайты…'
$btnAllDom.Location = New-Object Drawing.Point(276, 39)
$btnAllDom.Size = New-Object Drawing.Size(120, 32)
$btnAllDom.FlatStyle = 'Flat'
$btnAllDom.FlatAppearance.BorderColor = $script:C.Line
$btnAllDom.BackColor = $script:C.Card
$btnAllDom.ForeColor = $script:C.Text
$btnAllDom.Cursor = 'Hand'
$cardDom.Controls.Add($btnAllDom)

$lblDomCount = New-Object ShadowLabel
$lblDomCount.AutoSize = $true
$lblDomCount.Location = New-Object Drawing.Point(18, 80)
$lblDomCount.Font = $FBody
$lblDomCount.ForeColor = $script:C.Muted
$lblDomCount.Text = '0 доменов'
$cardDom.Controls.Add($lblDomCount)

$form.Controls.AddRange(@($cardServers, $cardMode, $lblGames, $cardDom, $pBottom, $pHead))

# ---------------- logic ----------------

function Get-Selected {
    if ($lstServers.SelectedIndex -lt 0) { return $null }
    $it = $lstServers.Items[$lstServers.SelectedIndex]
    if (!$it -or $it.Header) { return $null }
    return (Find-Server ([string]$it.Key) (Get-Servers))
}

# vse vybrannye servery (Ctrl/Shift), bez zagolovkov grupp
function Get-SelectedKeys {
    $keys = New-Object System.Collections.ArrayList
    foreach ($i in @($lstServers.SelectedIndices)) {
        if ($i -lt 0 -or $i -ge $lstServers.Items.Count) { continue }
        $it = $lstServers.Items[$i]
        if (!$it -or $it.Header) { continue }
        $k = [string]$it.Key
        if ($k -and !$keys.Contains($k)) { [void]$keys.Add($k) }
    }
    return @($keys)
}

function Get-SelectedServers {
    $keys = @(Get-SelectedKeys)
    $out = @()
    foreach ($n in Get-Servers) {
        if ($keys -contains (Get-ServerKey $n)) { $out += $n }
    }
    return $out
}

# ---------------- background ping scan ----------------

$script:PingFile = Join-Path $script:Run 'auto-ping.json'
$script:PingFiles = @()
$script:PingProcs = @()
$script:PingSeen = @{}
$script:PingEveryMin = 10
$script:PingWaitTo = $null
$script:PingParts = 3
$script:Pulse = 0.0

function Test-PingBusy {
    foreach ($p in @($script:PingProcs)) {
        if (!$p) { continue }
        try { if (!$p.HasExited) { return $true } } catch { continue }
    }
    return $false
}

# knopka "proverit vse" pokazyvaet sostoyanie: spit / svetitsya poka idet proverka
function Update-PingButton {
    try {
        if (!$btnTest) { return }
        $busy = Test-PingBusy
        $btnTest.Tag.busy = $busy
        $btnTest.Text = $(if ($busy) { 'проверка…' } else { 'Проверить все' })
        $btnTest.Invalidate()
    } catch { }
}

function Start-PingScan([string]$onlyKey = '') {
    if (Test-PingBusy) { return }
    $script:PingSeen = @{}
    $script:PingWaitTo = $null
    $script:PingProcs = @()
    $script:PingFiles = @()
    $eng = Join-Path $PSScriptRoot 'engine.ps1'
    # puti v kavychkah: v papke s probelom ("NOMIND Connect") inache argumenty raskidyvayutsya
    try {
        if ($onlyKey) {
            $f = $script:PingFile
            try { Remove-Item $f -Force -ErrorAction SilentlyContinue } catch { }
            $argStr = '-NoProfile -ExecutionPolicy Bypass -File "' + $eng + '" -Action pingall -OutFile "' + $f + '" -Server "' + $onlyKey + '"'
            $script:PingProcs = @(Start-Process -FilePath 'powershell.exe' -ArgumentList $argStr -WindowStyle Hidden -PassThru)
            $script:PingFiles = @($f)
        } else {
            # neskolko processov parallelno - proverka idet v 3-4 raza bystree
            $n = [Math]::Max(1, [int]$script:PingParts)
            $procs = @()
            $files = @()
            try { Remove-Item $script:PingFile -Force -ErrorAction SilentlyContinue } catch { }
            for ($k = 0; $k -lt $n; $k++) {
                $f = Join-Path $script:Run ('auto-ping.' + $k + '.json')
                try { Remove-Item $f -Force -ErrorAction SilentlyContinue } catch { }
                $files += $f
                $argStr = '-NoProfile -ExecutionPolicy Bypass -File "' + $eng + '" -Action pingall -OutFile "' + $f + '" -Part ' + $k + ' -Parts ' + $n
                $procs += Start-Process -FilePath 'powershell.exe' -ArgumentList $argStr -WindowStyle Hidden -PassThru
            }
            $script:PingProcs = @($procs)
            $script:PingFiles = @($files)
        }
        try { $lblInfo.Text = 'проверяю серверы в фоне…' } catch { }
        Update-PingButton
    } catch {
        $script:PingProcs = @()
        Update-PingButton
        Log ('не смог запустить проверку пинга: ' + $_.Exception.Message)
    }
}

function Stop-PingScan {
    foreach ($p in @($script:PingProcs)) {
        try { if ($p -and !$p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } } catch { }
    }
    # ubiraem xray, ostavshiesya ot prervannoy proverki
    try {
        Get-CimInstance Win32_Process -Filter "Name='xray.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match 'ping\d*-config\.json' } |
            ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch { } }
    } catch { }
    # to, chto uzhe uspeli proverit, pokazyvaem srazu
    try { foreach ($k in @(Read-PingScan)) { Set-PingInPlace $k } } catch { }
    $script:PingProcs = @()
    $script:PingWaitTo = $null
    Update-PingButton
    try { $lblInfo.Text = 'проверка остановлена' } catch { }
    Log 'проверка пингов остановлена'
}

function Set-PingInPlace([string]$key) {
    for ($i = 0; $i -lt $lstServers.Items.Count; $i++) {
        if ($lstServers.Items[$i].Key -ne $key) { continue }
        $it = $lstServers.Items[$i]
        $it.Ping = Get-PingText $key
        $it.Sort = Get-SortValue $key
        $it.Real = $script:Real.ContainsKey($key)
        $lstServers.Invalidate()
        return
    }
}

function Read-PingFile([string]$file) {
    $changed = @()
    if (!$file -or !(Test-Path $file)) { return $changed }
    $raw = ''
    try {
        $fs = [IO.File]::Open($file, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
            $raw = $sr.ReadToEnd()
            $sr.Dispose()
        } finally { $fs.Dispose() }
    } catch { return $changed }
    if (!$raw -or $raw.Trim() -eq '') { return $changed }
    $parsed = $null
    try { $parsed = $raw | ConvertFrom-Json } catch { return $changed }
    if (!$parsed) { return $changed }
    foreach ($r in @($parsed)) {
        if (!$r -or !$r.Key) { continue }
        $k = [string]$r.Key
        if ($script:PingSeen.ContainsKey($k)) { continue }
        $script:PingSeen[$k] = $true
        $tcp = [int]$r.Tcp
        $real = [int]$r.Real
        $script:Pings[$k] = $tcp
        if ($real -ge 0) { $script:Real[$k] = $real }
        elseif ($tcp -ge 0) { $script:Real[$k] = -1 }
        $changed += $k
    }
    return $changed
}

function Read-PingScan {
    $changed = @()
    foreach ($f in @($script:PingFiles)) {
        $changed += @(Read-PingFile $f)
    }
    return $changed
}

function Get-SortValue([string]$key) {
    if ($script:Real.ContainsKey($key)) {
        $v = $script:Real[$key]
        if ($v -ge 0) { return [double]$v }
        return 999999
    }
    if ($script:Pings.ContainsKey($key)) {
        $v = $script:Pings[$key]
        if ($v -ge 0) { return [double]$v }
        return 999998
    }
    return 999997
}

function Get-SubService([string]$url) {
    $h = Get-SubHost $url
    if (!$h) { return 'подписка' }
    return $h
}

function Get-SubUntil($info) {
    if (!$info) { return 'не проверялась' }
    if ([long]$info.expire -le 0) { return 'срок не указан' }
    try {
        $dt = [DateTimeOffset]::FromUnixTimeSeconds([long]$info.expire).ToLocalTime()
        if ($dt.DateTime -lt (Get-Date)) { return ('истёк ' + $dt.ToString('dd.MM.yyyy')) }
        return ('до ' + $dt.ToString('dd.MM.yyyy'))
    } catch { }
    return 'срок не указан'
}

function Refresh-Servers([string]$selectKey = '') {
    # zapominaem vybrannye servery, chtoby ne sbrosit mnozhestvennyy vybor pri obnovlenii pinga
    $prevKeys = @()
    try {
        foreach ($i in @($lstServers.SelectedIndices)) {
            if ($i -ge 0 -and $i -lt $lstServers.Items.Count) {
                $pit = $lstServers.Items[$i]
                if ($pit -and !$pit.Header -and $pit.Key) { $prevKeys += [string]$pit.Key }
            }
        }
    } catch { }
    $lstServers.BeginUpdate()
    $lstServers.Items.Clear()
    $s = Get-Settings
    $subOrder = @{}
    $subCount = 0
    if ($s -and $s.subs) {
        foreach ($sb in @($s.subs)) {
            $u = [string]$sb.url
            if ($u -and !$subOrder.ContainsKey($u)) { $subOrder[$u] = $subCount; $subCount++ }
        }
    }
    $items = @()
    $anyGroup = $false
    foreach ($n in Get-Servers) {
        $key = Get-ServerKey $n
        $ping = Get-PingText $key
        $code = Get-FlagCode $n.name
        $name = Strip-NodeFlags (Clear-NodeName $n.name)
        if (!$name) { $name = [string]$n.host }
        # "Авто" — vsegda pervyy v spiske, nezavisimo ot pinga
        $pin = 1
        if ($name -match '^\s*(авто|auto)\b') { $pin = 0 }
        $subUrl = ''
        try { $subUrl = [string]$n.sub } catch { }
        $rank = 1000
        $gTitle = 'добавлены вручную'
        $gUntil = ''
        $gColor = $script:C.Muted
        if ($subUrl) {
            $anyGroup = $true
            if ($subOrder.ContainsKey($subUrl)) { $rank = [int]$subOrder[$subUrl] } else { $rank = 900 }
            $gTitle = Get-SubService $subUrl
            $inf = $null
            if ($s -and $s.subInfo) {
                $p = $s.subInfo.PSObject.Properties[$subUrl]
                if ($p) { $inf = $p.Value }
            }
            $gUntil = Get-SubUntil $inf
            $gColor = $script:C.Pink
        }
        $item = [pscustomobject]@{
            Header = $false; Key = $key; Node = $n; Code = $code; Name = $name; Ping = $ping
            Real = $script:Real.ContainsKey($key); Sort = (Get-SortValue $key); Idx = $items.Count; Pin = $pin
            GroupRank = $rank; GroupTitle = $gTitle; GroupUntil = $gUntil; GroupColor = $gColor
        }
        $items += $item
    }
    if (-not $anyGroup) {
        foreach ($it in $items) { $it.GroupTitle = ''; $it.GroupUntil = '' }
    }

    $lastGroup = $null
    $serverCount = 0
    $firstServerIndex = -1
    $selIndex = -1
    $skipGroup = $false
    foreach ($item in @($items | Sort-Object -Property GroupRank, Pin, Sort, Idx)) {
        $g = ([string]$item.GroupRank + '|' + [string]$item.GroupTitle)
        if ($anyGroup -and $g -ne $lastGroup) {
            $folded = ($script:Folded.ContainsKey($g) -and $script:Folded[$g])
            $hdr = [pscustomobject]@{
                Header = $true; Key = ''; Node = $null; Code = ''; Name = ''; Ping = ''
                Real = $false; Sort = 0; Idx = 0; GroupRank = $item.GroupRank
                GroupKey = $g; Collapsed = $folded
                GroupTitle = $item.GroupTitle; GroupUntil = $item.GroupUntil; GroupColor = $item.GroupColor
            }
            [void]$lstServers.Items.Add($hdr)
            $lastGroup = $g
            $skipGroup = $folded
        }
        $serverCount++
        if ($skipGroup) { continue }
        [void]$lstServers.Items.Add($item)
        if ($firstServerIndex -lt 0) { $firstServerIndex = $lstServers.Items.Count - 1 }
        if ($selectKey -and $item.Key -eq $selectKey) { $selIndex = $lstServers.Items.Count - 1 }
    }
    $lstServers.EndUpdate()
    if ($selectKey -and $selIndex -ge 0) {
        $lstServers.ClearSelected()
        $lstServers.SelectedIndex = $selIndex
    } elseif (!$selectKey -and $prevKeys.Count -gt 0) {
        $lstServers.ClearSelected()
        for ($i = 0; $i -lt $lstServers.Items.Count; $i++) {
            $it = $lstServers.Items[$i]
            if ($it -and !$it.Header -and ($prevKeys -contains [string]$it.Key)) { $lstServers.SetSelected($i, $true) }
        }
        if ($lstServers.SelectedIndices.Count -eq 0 -and $firstServerIndex -ge 0) { $lstServers.SelectedIndex = $firstServerIndex }
    } elseif ($lstServers.SelectedIndex -lt 0 -and $firstServerIndex -ge 0) {
        $lstServers.SelectedIndex = $firstServerIndex
    }
    $n = $serverCount
    $mod100 = $n % 100
    $mod10 = $n % 10
    $word = 'серверов'
    if ($mod10 -eq 1 -and $mod100 -ne 11) { $word = 'сервер' }
    elseif ($mod10 -ge 2 -and $mod10 -le 4 -and ($mod100 -lt 12 -or $mod100 -gt 14)) { $word = 'сервера' }
    $lblSrvCount.Text = ('{0} {1}' -f $n, $word)
    if ($script:SrvScroll) { Update-SlimScroll $script:SrvScroll }
}

function Get-PingText([string]$key) {
    if ($script:Real.ContainsKey($key)) {
        $v = $script:Real[$key]
        if ($v -lt 0) { return 'не грузит' }
        return ([string]$v + ' ms')
    }
    if ($script:Pings.ContainsKey($key)) {
        $v = $script:Pings[$key]
        if ($v -lt 0) { return 'нет' }
        return ([string]$v + ' ms')
    }
    return '—'
}

function Set-RowPing([string]$key) {
    if (@(Get-SelectedKeys).Count -gt 0) { Refresh-Servers }
    else { Refresh-Servers $key }
}

function Refresh-DomCount {
    $n = (Get-Domains).Count
    $lblDomCount.Text = ('{0} доменов в списке' -f $n)
}

function Set-Mode([string]$mode, [switch]$Restart, [switch]$NoSave) {
    $old = $script:Mode
    $script:Mode = $mode
    $mdGlobal.Tag = ''
    $mdSmart.Tag = ''
    if ($mode -eq 'smart') { $mdSmart.Tag = 'on' } else { $mdGlobal.Tag = 'on' }
    $mdGlobal.Invalidate()
    $mdSmart.Invalidate()
    if (!$NoSave) {
        $s = Get-Settings
        $s.mode = $mode
        Save-Settings $s
    }
    if ($Restart -and $old -ne $mode) { Restart-Tunnel 'режим изменён' }
}

function Set-ModeFromCard($card) {
    try {
        if ($card -eq $mdSmart -or $card.Parent -eq $mdSmart) { Set-Mode 'smart' -Restart }
        else { Set-Mode 'global' -Restart }
    } catch {
        try {
            $p = Join-Path $script:Run 'mode.err.log'
            [IO.File]::AppendAllText($p, ((Get-Date -Format 'HH:mm:ss') + '  ' + $_.Exception.Message + "`r`n" + $_.ScriptStackTrace + "`r`n`r`n"), (New-Object Text.UTF8Encoding($true)))
        } catch { }
    }
}

function Update-State {
    $st = Get-State
    if ($st.Running) {
        $lblState.Text = Spaced 'подключено'
        $lblState.ForeColor = $script:C.Sea
        $name = if ($st.Server) { Display-Name $st.Server.name } else { $st.ServerKey }
        $lblInfo.Text = ($name + '   ·   ' + $st.ServerKey)
        $btnConnect.Text = 'ОТКЛЮЧИТЬ'
        $script:ConnectOn = $true
        $btnConnect.Invalidate()
        if ($script:ExitFor -ne $st.ServerKey) {
            $s = Get-Settings
            $tr = Get-Trace ([int]$s.httpPort) 'https://chatgpt.com/cdn-cgi/trace'
            if ($tr.Ip) {
                $lblExit.Text = ('выход  ' + $tr.Ip + '  ·  ' + $tr.Loc)
                $script:ExitFor = $st.ServerKey
            }
        }
    } else {
        $lblState.Text = Spaced 'отключено'
        $lblState.ForeColor = $script:C.Muted
        $lblInfo.Text = 'выберите сервер и нажмите «подключить»'
        $lblExit.Text = ''
        $script:ExitFor = ''
        $btnConnect.Text = 'ПОДКЛЮЧИТЬ'
        $script:ConnectOn = $false
        $btnConnect.Invalidate()
    }
    if ($st.ProxyOn -and !$st.Running) {
        $lblInfo.Text = 'прокси включён, а xray нет — нажмите «подключить»'
    }
    $lblInfo.Left = $lblState.Left + $lblState.Width + 18
    try {
        if ($script:Tray) {
            $script:Tray.Text = $(if ($st.Running) { 'NOMIND Connect — VPN включён' } else { 'NOMIND Connect — VPN выключен' })
        }
        if ($script:TrayConn) {
            $script:TrayConn.Text = $(if ($st.Running) { 'Отключить VPN' } else { 'Подключить VPN' })
        }
    } catch { }
}

function Do-Connect {
    $node = Get-Selected
    if (!$node) {
        # nichego ne vybrano - berem posledniy server iz nastroek
        $s0 = Get-Settings
        if ($s0 -and $s0.server) { $node = Find-Server ([string]$s0.server) (Get-Servers) }
    }
    if (!$node) {
        Show-NomindBox -Title 'нужен сервер' -Message 'Сначала выберите сервер в списке — без него подключаться некуда.' | Out-Null
        return
    }
    $s = Get-Settings
    $s | Add-Member -NotePropertyName server -NotePropertyValue (Get-ServerKey $node) -Force
    $s.mode = $script:Mode
    Save-Settings $s
    $dom = Get-Domains
    try {
        $lblState.Text = Spaced 'подключаюсь'
        $lblState.ForeColor = $script:C.Gold
        [Windows.Forms.Application]::DoEvents()
        Log ('сервер: ' + (Display-Name $node.name) + '   ' + (Get-ServerKey $node))
        Log ('режим: ' + $(if ($s.mode -eq 'global') { 'всё, кроме русских сайтов' } else { 'только выбранные сайты' }))
        $p = Start-Engine $node $s $dom
        Log ('xray запущен, pid ' + $p.Id)
        Enable-SystemProxy ([int]$s.httpPort) | Out-Null
        Log ('системный прокси включён: 127.0.0.1:' + $s.httpPort)
        $tr = Get-Trace ([int]$s.httpPort) 'https://chatgpt.com/cdn-cgi/trace'
        if ($tr.Ip) {
            $lblExit.Text = ('выход  ' + $tr.Ip + '  ·  ' + $tr.Loc)
            Log ('выход: ' + $tr.Ip + '   loc=' + $tr.Loc)
        } else {
            Log 'выход не определился — узел медленный или не пускает'
        }
    } catch {
        Log ('ОШИБКА: ' + $_.Exception.Message)
        try { Stop-Engine | Out-Null } catch { }
        try { Disable-SystemProxy | Out-Null } catch { }
        Show-NomindBox -Title 'не удалось подключиться' -Message ($_.Exception.Message) -Danger | Out-Null
    }
    Update-State
}

function Do-Disconnect {
    Log 'отключаю…'
    Stop-Engine | Out-Null
    Disable-SystemProxy | Out-Null
    Log 'xray остановлен, системный прокси выключен'
    Update-State
}

# правила применяются на лету: если туннель поднят — перезапускаем xray с новым конфигом.
# системный прокси при этом не выключается, поэтому браузеры/игры просто переживают
# короткую (меньше секунды) повторную инициализацию, без ручного «отключить/подключить».
function Restart-Tunnel([string]$why = 'конфиг изменён') {
    $modeText = $(if ($script:Mode -eq 'smart') { 'только выбранные сайты' } else { 'всё, кроме русских сайтов' })
    $st = Get-State
    if (!$st.Running) {
        Log ($why + ' — сохранено, применится при подключении')
        return
    }
    $node = $st.Server
    if (!$node) { $node = Get-Selected }
    if (!$node) {
        Log ($why + ' — сохранено, но сервер для перезапуска не найден')
        return
    }
    $s = Get-Settings
    $s.mode = $script:Mode
    if ($st.ServerKey) { $s | Add-Member -NotePropertyName server -NotePropertyValue $st.ServerKey -Force }
    Save-Settings $s
    try {
        $lblState.Text = Spaced 'перезапускаю'
        $lblState.ForeColor = $script:C.Gold
        [Windows.Forms.Application]::DoEvents()
        Log ($why + ' (' + $modeText + ') — перезапускаю туннель, прокси не выключаю')
        # Start-Engine сам аккуратно гасит старый xray и поднимает новый на тех же портах,
        # поэтому системный прокси остаётся включённым и разрыва для приложений нет.
        $dom = Get-Domains
        $p = Start-Engine $node $s $dom
        Log ('xray запущен заново, pid ' + $p.Id)
        Enable-SystemProxy ([int]$s.httpPort) | Out-Null
        $script:ExitFor = ''
        $tr = Get-Trace ([int]$s.httpPort) 'https://chatgpt.com/cdn-cgi/trace'
        if ($tr.Ip) {
            $lblExit.Text = ('выход  ' + $tr.Ip + '  ·  ' + $tr.Loc)
            Log ('выход: ' + $tr.Ip + '   loc=' + $tr.Loc)
        } else {
            Log 'выход не определился — узел медленный или не пускает'
        }
    } catch {
        Log ('ОШИБКА перезапуска: ' + $_.Exception.Message)
        try { Stop-Engine | Out-Null } catch { }
        try { Disable-SystemProxy | Out-Null } catch { }
        Show-NomindBox -Title 'не удалось перезапустить' -Message ('Туннель не перезапустился с новыми правилами:' + "`r`n" + $_.Exception.Message) -Danger | Out-Null
    }
    Update-State
}

# изменение списка сайтов применяем сразу: перезапускаем ядро на тех же портах,
# системный прокси не выключаем — вручную отключать/подключать не нужно
function Apply-DomainChanges([string]$why = 'список сайтов изменён') {
    if ($script:Mode -ne 'smart') {
        Log ($why + ' — режим «всё, кроме русских сайтов»: список сайтов на маршрутизацию не влияет, но туннель обновляю')
    }
    Restart-Tunnel $why
}

# ---------------- domain parsing ----------------

function ConvertTo-DomainList([string]$text) {
    $out = New-Object System.Collections.ArrayList
    $bad = New-Object System.Collections.ArrayList
    foreach ($raw in ($text -split "[`r`n,;\s]+")) {
        $d = $raw.Trim()
        if (!$d) { continue }
        $d = $d.ToLower()
        $d = $d -replace '^[a-z]+://', ''
        $d = ($d -split '/')[0]
        $d = ($d -split '\?')[0]
        $d = $d -replace ':\d+$', ''
        $d = $d -replace '^\*\.', ''
        $d = $d -replace '^www\.', ''
        if ($d -match '^[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$') {
            [void]$out.Add($d)
        } elseif ($d) {
            [void]$bad.Add($raw.Trim())
        }
    }
    return [pscustomobject]@{ Domains = @($out); Bad = @($bad) }
}

function Add-Domains([string]$text) {
    $parsed = ConvertTo-DomainList $text
    if ($parsed.Domains.Count -eq 0) {
        return [pscustomobject]@{ Added = 0; Skipped = 0; Bad = $parsed.Bad }
    }
    $cur = @(Get-Domains)
    $set = @{}
    foreach ($d in $cur) { $set[$d.ToLower()] = $true }
    $added = 0
    foreach ($d in $parsed.Domains) {
        if (!$set.ContainsKey($d)) {
            $cur += $d
            $set[$d] = $true
            $added++
        }
    }
    if ($added -gt 0) { Save-Domains $cur }
    return [pscustomobject]@{ Added = $added; Skipped = ($parsed.Domains.Count - $added); Bad = $parsed.Bad }
}

# ---------------- domains editor ----------------

function Brand-Of([string]$d) {
    $parts = @($d -split '\.')
    if ($parts.Count -le 2) { return $d }
    $two = $parts[$parts.Count - 2] + '.' + $parts[$parts.Count - 1]
    $second = @('co', 'org', 'net', 'ac', 'gov', 'com', 'edu')
    if (($second -contains $parts[$parts.Count - 2]) -and $parts.Count -ge 3) {
        return ($parts[$parts.Count - 3] + '.' + $two)
    }
    return $two
}

function Find-Similar([string]$q, [string[]]$list, [int]$max = 6) {
    $q = $q.Trim().ToLower()
    if ($q.Length -lt 2) { return @() }
    $res = New-Object System.Collections.ArrayList
    foreach ($d in $list) {
        if ($d -eq $q) { continue }
        $hit = $false
        if ($d.Contains($q)) { $hit = $true }
        elseif ($q.Contains($d)) { $hit = $true }
        elseif ((Brand-Of $d) -eq (Brand-Of $q)) { $hit = $true }
        if ($hit) { [void]$res.Add($d) }
    }
    $sorted = @($res | Sort-Object { $_.Length }, { $_ })
    if ($sorted.Count -eq 0) { return @() }
    if ($sorted.Count -gt $max) { $sorted = $sorted[0..($max - 1)] }
    return $sorted
}

# ---------------- nастройки ----------------

function New-ToggleRow([int]$y, [string]$title, [string]$desc, [bool]$on, [scriptblock]$onChange, [int]$width = 500) {
    $p = New-Object Windows.Forms.Panel
    $p.Location = New-Object Drawing.Point(18, $y)
    $p.Size = New-Object Drawing.Size($width, 64)
    $p.BackColor = $script:C.Card
    $p.Cursor = 'Hand'
    $p.Tag = [pscustomobject]@{ On = $on; Change = $onChange }

    $t = New-Object ShadowLabel
    $t.AutoSize = $false
    $t.Location = New-Object Drawing.Point(14, 11)
    $t.Size = New-Object Drawing.Size(($width - 100), 22)
    $t.Font = $FTitle
    $t.ForeColor = $script:C.Text
    $t.Text = $title
    $t.Cursor = 'Hand'

    $d = New-Object ShadowLabel
    $d.AutoSize = $false
    $d.Location = New-Object Drawing.Point(14, 36)
    $d.Size = New-Object Drawing.Size(($width - 96), 20)
    $d.Font = $FLabel
    $d.ForeColor = $script:C.Muted
    $d.Text = $desc
    $d.Cursor = 'Hand'

    $p.Controls.AddRange(@($t, $d))

    $p.Add_Paint({
        param($s, $e)
        try {
            $g = $e.Graphics
            $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $onNow = [bool]$s.Tag.On
            $x = $s.Width - 62
            $yy = 21
            $br = New-Object Drawing.SolidBrush($(if ($onNow) { $script:C.Gold } else { $script:C.Line }))
            $path = New-Object Drawing.Drawing2D.GraphicsPath
            $path.AddArc($x, $yy, 22, 22, 90, 180)
            $path.AddArc(($x + 22), $yy, 22, 22, 270, 180)
            $path.CloseFigure()
            $g.FillPath($br, $path)
            $path.Dispose()
            $br.Dispose()
            $kx = if ($onNow) { $x + 24 } else { $x + 2 }
            $kb = New-Object Drawing.SolidBrush($(if ($onNow) { $script:C.Head } else { $script:C.Muted }))
            $g.FillEllipse($kb, $kx, ($yy + 2), 18, 18)
            $kb.Dispose()
        } catch { }
    })

    $p.Add_Click({
        param($s, $e)
        $tag = $s.Tag
        $tag.On = -not $tag.On
        $s.Invalidate()
        try { & $tag.Change ([bool]$tag.On) } catch { Write-UiError 'toggle' $_.Exception }
    })

    $t.Add_Click({
        param($s, $e)
        $panel = $s.Parent
        $tag = $panel.Tag
        $tag.On = -not $tag.On
        $panel.Invalidate()
        try { & $tag.Change ([bool]$tag.On) } catch { Write-UiError 'toggle' $_.Exception }
    })

    $d.Add_Click({
        param($s, $e)
        $panel = $s.Parent
        $tag = $panel.Tag
        $tag.On = -not $tag.On
        $panel.Invalidate()
        try { & $tag.Change ([bool]$tag.On) } catch { Write-UiError 'toggle' $_.Exception }
    })

    return $p
}

function Show-SettingsDialog {
    $dlg = New-Object Windows.Forms.Form
    $dlg.Text = 'NOMIND Connect — настройки'
    $dlg.ClientSize = New-Object Drawing.Size(600, 470)
    $dlg.FormBorderStyle = 'FixedSingle'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.StartPosition = 'CenterParent'
    $dlg.BackColor = $script:C.Bg
    $dlg.ForeColor = $script:C.Text
    $dlg.Font = $FBody
    $dlg.ShowInTaskbar = $false
    $dlg.Add_Shown({ [Dark]::Title($dlg.Handle) })
    if ($form.Icon) { $dlg.Icon = $form.Icon }

    $appOn   = [bool](Get-RunValue $script:RunApp)
    $guardOn = [bool](Get-RunValue $script:RunGuard)

    $rowApp = New-ToggleRow 16 'Запускать при входе в Windows' 'Появится в трее сразу после входа в Windows.' $appOn {
        param($on)
        $vbs = Join-Path $script:Root 'NOMINDConnect.vbs'
        Set-RunValue $script:RunApp $(if ($on) { 'wscript.exe "' + $vbs + '"' } else { '' })
        Log ($(if ($on) { 'автозапуск включён' } else { 'автозапуск выключен' }))
    } 564

    $rowGuard = New-ToggleRow 84 'Сторож: не терять интернет' 'После жёсткого выключения ПК сам снимет прокси.' $guardOn {
        param($on)
        $vbs = Join-Path $script:Root 'NOMINDGuard.vbs'
        Set-RunValue $script:RunGuard $(if ($on) { 'wscript.exe "' + $vbs + '"' } else { '' })
        Set-AppSetting 'guardAutostart' $on
        Log ($(if ($on) { 'сторож включён' } else { 'сторож выключен' }))
    } 564

    $rowTray = New-ToggleRow 152 'Сворачивать в трей при закрытии' 'Крестик прячет окно в трей, VPN продолжает работать.' ([bool](Get-AppSetting 'closeToTray' $true)) {
        param($on)
        $script:CloseToTray = $on
        Set-AppSetting 'closeToTray' $on
        Log ($(if ($on) { 'закрытие прячет окно в трей' } else { 'закрытие завершает программу' }))
    } 564

    $rowAds = New-ToggleRow 220 'Блокировать рекламу' 'Рекламные домены не грузятся через VPN-туннель.' ([bool](Get-AppSetting 'blockAds' $false)) {
        param($on)
        Set-AppSetting 'blockAds' $on
        Log ($(if ($on) { 'блокировка рекламы включена' } else { 'блокировка рекламы выключена' }))
        Restart-Tunnel 'настройки изменены'
    } 564

    $lblHint = New-Object ShadowLabel
    $lblHint.AutoSize = $false
    $lblHint.Location = New-Object Drawing.Point(20, 298)
    $lblHint.Size = New-Object Drawing.Size(560, 72)
    $lblHint.ForeColor = $script:C.GoldDim
    $lblHint.Font = $FBody
    $lblHint.Text = 'Настройки сохраняются сразу. Автозапуск и сторож действуют со следующего входа в Windows. Блокировка рекламы перезапустит туннель, если VPN уже подключён.'

    $btnOk = New-Object ShadowButton
    $btnOk.Text = 'Готово'
    Style-Button $btnOk $true
    $wOk = [Windows.Forms.TextRenderer]::MeasureText('Готово', $FTitle).Width + 56
    $btnOk.Size = New-Object Drawing.Size($wOk, 38)
    $btnOk.Left = $dlg.ClientSize.Width - 18 - $wOk
    $btnOk.Top = $dlg.ClientSize.Height - 18 - 38
    $btnOk.Add_Click({ $dlg.Close() })

    $dlg.Controls.AddRange(@($rowApp, $rowGuard, $rowTray, $rowAds, $lblHint, $btnOk))
    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnOk
    [void]$dlg.ShowDialog($form)
}


function Show-DomainEditor {
    $dlg = New-Object Windows.Forms.Form
    $dlg.Text = 'NOMIND Connect — сайты через VPN'
    $dlg.ClientSize = New-Object Drawing.Size(1060, 700)
    $dlg.MinimumSize = New-Object Drawing.Size(880, 560)
    $dlg.StartPosition = 'CenterParent'
    $dlg.BackColor = $script:C.Bg
    $dlg.ForeColor = $script:C.Text
    $dlg.Font = $FBody
    $dlg.ShowInTaskbar = $false
    $dlg.Add_Shown({ [Dark]::Title($dlg.Handle) })
    if ($form.Icon) { $dlg.Icon = $form.Icon }

    $drawRow = {
        param($s, $e, $goldText)
        if ($e.Index -lt 0) { return }
        $g = $e.Graphics
        $sel = (($e.State -band [Windows.Forms.DrawItemState]::Selected) -ne 0)
        $bgc = if ($sel) { $script:C.Card2 } else { $script:C.Card }
        $br = New-Object Drawing.SolidBrush($bgc)
        $g.FillRectangle($br, $e.Bounds)
        $br.Dispose()
        if ($sel) {
            $bar = New-Object Drawing.SolidBrush($script:C.Gold)
            $g.FillRectangle($bar, $e.Bounds.X, ($e.Bounds.Y + 4), 3, ($e.Bounds.Height - 8))
            $bar.Dispose()
        }
        $fg = if ($sel -and $goldText) { $script:C.Gold } else { $script:C.Text }
        $tb = New-Object Drawing.SolidBrush($fg)
        $g.DrawString([string]$s.Items[$e.Index], $s.Font, $tb, [float]($e.Bounds.X + 10), [float]($e.Bounds.Y + 3))
        $tb.Dispose()
    }

    $t1 = New-Object ShadowLabel
    $t1.AutoSize = $true
    $t1.Location = New-Object Drawing.Point(24, 16)
    $t1.Font = $FHead
    $t1.ForeColor = $script:C.Text
    $t1.Text = 'САЙТЫ ЧЕРЕЗ VPN'
    $dlg.Controls.Add($t1)

    $lTotal = New-Object ShadowLabel
    $lTotal.AutoSize = $false
    $lTotal.Location = New-Object Drawing.Point(760, 30)
    $lTotal.Anchor = 'Top, Right'
    $lTotal.Size = New-Object Drawing.Size(276, 22)
    $lTotal.TextAlign = 'MiddleRight'
    $lTotal.Font = $FLabel
    $lTotal.ForeColor = $script:C.GoldDim
    $lTotal.Text = ''
    $dlg.Controls.Add($lTotal)

    $txtNew = New-Object Windows.Forms.TextBox
    $txtNew.Location = New-Object Drawing.Point(24, 92)
    $txtNew.Size = New-Object Drawing.Size(560, 32)
    $txtNew.Font = $FBody
    $txtNew.BackColor = $script:C.Card2
    $txtNew.ForeColor = $script:C.Text
    $txtNew.BorderStyle = 'FixedSingle'
    $dlg.Controls.Add($txtNew)

    # knopki: shirina schitaetsya po tekstu (inache na krupnom shrifte/DPI slova obrezayutsya)
    $btnAddDom = New-Object ShadowButton
    $btnAddDom.Text = 'Добавить'
    Style-Button $btnAddDom $true

    $btnPaste2 = New-Object ShadowButton
    $btnPaste2.Text = 'Из буфера'
    Style-Button $btnPaste2 $false $script:C.Sea

    $btnDelSel = New-Object ShadowButton
    $btnDelSel.Text = 'Удалить'
    Style-Button $btnDelSel $false $script:C.Red

    $btnDone = New-Object ShadowButton
    $btnDone.Text = 'ОК'
    Style-Button $btnDone $false $script:C.Gold

    $bh = 36
    $gap = 8
    $wOk = [Windows.Forms.TextRenderer]::MeasureText('ОК', $FBody).Width + 44
    $wDel = [Windows.Forms.TextRenderer]::MeasureText('Удалить', $FBody).Width + 52
    $wPaste = [Windows.Forms.TextRenderer]::MeasureText('Из буфера', $FBody).Width + 52
    $wAdd = [Windows.Forms.TextRenderer]::MeasureText('Добавить', $FTitle).Width + 52
    $right = $dlg.ClientSize.Width - 24
    $btnDone.Size = New-Object Drawing.Size($wOk, $bh)
    $btnDone.Left = $right - $wOk
    $btnDelSel.Size = New-Object Drawing.Size($wDel, $bh)
    $btnDelSel.Left = $btnDone.Left - $gap - $wDel
    $btnPaste2.Size = New-Object Drawing.Size($wPaste, $bh)
    $btnPaste2.Left = $btnDelSel.Left - $gap - $wPaste
    $btnAddDom.Size = New-Object Drawing.Size($wAdd, $bh)
    $btnAddDom.Left = $btnPaste2.Left - $gap - $wAdd
    foreach ($b in @($btnAddDom, $btnPaste2, $btnDelSel, $btnDone)) {
        $b.Top = 91
        $b.Anchor = 'Top, Right'
        $dlg.Controls.Add($b)
    }
    $txtNew.Width = [Math]::Max(220, ($btnAddDom.Left - 12 - 24))
    $txtNew.Height = 32
    $txtNew.Anchor = 'Top, Left, Right'

    $lHint = New-Object ShadowLabel
    $lHint.AutoSize = $false
    $lHint.Location = New-Object Drawing.Point(24, 132)
    $lHint.Size = New-Object Drawing.Size(1012, 20)
    $lHint.Font = $FBody
    $lHint.ForeColor = $script:C.Muted
    $lHint.Text = 'Введите домен или вставьте ссылку — при вводе покажу, что уже есть в списке.'
    $dlg.Controls.Add($lHint)

    $pSug = New-Object Windows.Forms.Panel
    $pSug.Location = New-Object Drawing.Point(24, 230)
    $pSug.Size = New-Object Drawing.Size(720, 168)
    $pSug.BackColor = $script:C.Bg
    $pSug.Visible = $false
    $pSug.Add_Paint({
        param($s, $e)
        try {
            $g = $e.Graphics
            $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $path = New-RoundPath 1 1 ($s.Width - 3) ($s.Height - 3) 9
            $fill = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(48, 43, 53))
            $g.FillPath($fill, $path)
            $fill.Dispose()
            $pen = New-Object Drawing.Pen($script:C.Gold, 2)
            $g.DrawPath($pen, $path)
            $pen.Dispose()
            $path.Dispose()
        } catch { }
    })
    $dlg.Controls.Add($pSug)

    $lSugTitle = New-Object ShadowLabel
    $lSugTitle.AutoSize = $false
    $lSugTitle.Location = New-Object Drawing.Point(14, 7)
    $lSugTitle.Size = New-Object Drawing.Size(690, 18)
    $lSugTitle.Font = $FLabel
    $lSugTitle.ForeColor = $script:C.Gold
    $lSugTitle.BackColor = [Drawing.Color]::FromArgb(48, 43, 53)
    $lSugTitle.Text = 'похожие уже в списке'
    $pSug.Controls.Add($lSugTitle)

    $lstSug = New-Object SlimListBox
    $lstSug.Location = New-Object Drawing.Point(10, 28)
    $lstSug.Size = New-Object Drawing.Size(674, 122)
    $lstSug.BackColor = [Drawing.Color]::FromArgb(48, 43, 53)
    $lstSug.ForeColor = $script:C.Pink
    $lstSug.BorderStyle = 'None'
    $lstSug.Font = $FMono
    $lstSug.ItemHeight = [int]($FMono.GetHeight() + 4)
    $lstSug.IntegralHeight = $false
    $lstSug.SelectionMode = 'One'
    $pSug.Controls.Add($lstSug)
    $script:SugScroll = Add-SlimScroll $lstSug $pSug

    $lFilter = New-Object ShadowLabel
    $lFilter.AutoSize = $true
    $lFilter.Location = New-Object Drawing.Point(24, 168)
    $lFilter.Font = $FLabel
    $lFilter.ForeColor = $script:C.Muted
    $lFilter.Text = Spaced 'поиск'
    $dlg.Controls.Add($lFilter)

    $txtFilter = New-Object Windows.Forms.TextBox
    $txtFilter.Location = New-Object Drawing.Point(24, 192)
    $txtFilter.Size = New-Object Drawing.Size(1012, 30)
    $txtFilter.BackColor = $script:C.Card2
    $txtFilter.ForeColor = $script:C.Text
    $txtFilter.BorderStyle = 'FixedSingle'
    $txtFilter.Font = $FBody
    $dlg.Controls.Add($txtFilter)

    $pDomFrame = New-Object Windows.Forms.Panel
    $pDomFrame.Location = New-Object Drawing.Point(23, 229)
    $pDomFrame.Anchor = 'Top, Bottom, Left, Right'
    $pDomFrame.Size = New-Object Drawing.Size(1014, 418)
    $pDomFrame.BackColor = $script:C.Card
    $pDomFrame.Add_Paint({
        param($s, $e)
        $pen = New-Object Drawing.Pen($script:C.Line, 2)
        $e.Graphics.DrawRectangle($pen, 1, 1, ($s.Width - 3), ($s.Height - 3))
        $pen.Dispose()
    })
    $dlg.Controls.Add($pDomFrame)

    $lstDomains = New-Object SlimListBox
    $lstDomains.Location = New-Object Drawing.Point(25, 231)
    $lstDomains.Anchor = 'Top, Bottom, Left, Right'
    $lstDomains.Size = New-Object Drawing.Size(988, 414)
    $lstDomains.BackColor = $script:C.Card
    $lstDomains.ForeColor = $script:C.Text
    $lstDomains.BorderStyle = 'None'
    $lstDomains.Font = $FMono
    $lstDomains.SelectionMode = 'MultiExtended'
    $lstDomains.IntegralHeight = $false
    $lstDomains.DrawMode = 'OwnerDrawFixed'
    $lstDomains.ItemHeight = [int]($FMono.GetHeight() + 4)
    $lstDomains.Add_DrawItem({ param($s, $e) & $drawRow $s $e $false })
    $dlg.Controls.Add($lstDomains)
    $lstDomains.BringToFront()
    $script:DomScroll = Add-SlimScroll $lstDomains $dlg

    $lNote = New-Object ShadowLabel
    $lNote.AutoSize = $false
    $lNote.Location = New-Object Drawing.Point(24, 656)
    $lNote.Anchor = 'Bottom, Left, Right'
    $lNote.Size = New-Object Drawing.Size(1012, 22)
    $lNote.ForeColor = $script:C.Muted
    $lNote.Text = 'Del — удалить выбранные · двойной клик — скопировать в буфер'
    $dlg.Controls.Add($lNote)

    function Refresh-All {
        $all = @(Get-Domains | Sort-Object)
        $lTotal.Text = ('{0} сайтов' -f $all.Count)
        $lstDomains.BeginUpdate()
        $lstDomains.Items.Clear()
        $q = $txtFilter.Text.Trim().ToLower()
        $fromInput = $false
        if ($q -eq '') {
            $q = $txtNew.Text.Trim().ToLower()
            $q = $q -replace '^[a-z]+://', ''
            $q = ($q -split '/')[0]
            $fromInput = ($q -ne '')
        }
        $shown = 0
        foreach ($d in $all) {
            if ($q -eq '' -or $d.Contains($q)) { [void]$lstDomains.Items.Add($d); $shown++ }
        }
        $lstDomains.EndUpdate()
        if ($script:DomScroll) { Update-SlimScroll $script:DomScroll }
        $lNote.Text = ('Показано: {0} · Del — удалить выбранные · двойной клик — скопировать' -f $shown)
        if ($fromInput) {
            $lNote.Text = ('Показано: {0} из {1} по вводу «{2}» · сотрите текст — вернутся все' -f $shown, $all.Count, $q)
        }
    }

    $script:SugOpen = $false
    $script:DomBase = $null

    function Close-Suggest {
        if ($script:SugOpen -and $script:DomBase) {
            $pDomFrame.Top = $script:DomBase.FT
            $pDomFrame.Height = $script:DomBase.FH
            $lstDomains.Top = $script:DomBase.LT
            $lstDomains.Height = $script:DomBase.LH
            $script:SugOpen = $false
        }
        $pSug.Visible = $false
    }

    function Open-Suggest([int]$h) {
        if (-not $script:SugOpen) {
            $script:DomBase = @{
                FT = $pDomFrame.Top; FH = $pDomFrame.Height
                LT = $lstDomains.Top; LH = $lstDomains.Height
            }
            $script:SugOpen = $true
        }
        $shift = $h + 10
        $pDomFrame.Top = $script:DomBase.FT + $shift
        $pDomFrame.Height = [Math]::Max(150, ($script:DomBase.FH - $shift))
        $lstDomains.Top = $pDomFrame.Top + 2
        $lstDomains.Height = $pDomFrame.Height - 4
        $pSug.Visible = $true
        $pSug.BringToFront()
    }

    function Update-Suggest {
        $typed = $txtNew.Text.Trim().ToLower()
        Close-Suggest
        $lstSug.Items.Clear()
        if ($typed -eq '') {
            $lHint.ForeColor = $script:C.Muted
            $lHint.Text = 'Введите домен или вставьте ссылку — при вводе покажу, что уже есть в списке.'
            return
        }
        $all = @(Get-Domains)
        $clean = $typed -replace '^[a-z]+://', ''
        $clean = ($clean -split '/')[0]
        if ($all -contains $clean) {
            $lHint.ForeColor = $script:C.Gold
            $lHint.Text = ('такой домен уже есть: ' + $clean)
            return
        }
        $sim = @(Find-Similar $clean $all)
        if ($sim.Count -gt 0) {
            $lHint.ForeColor = $script:C.Gold
            $lHint.Text = ('похожие уже в списке: ' + $sim.Count + ' — список ниже сдвинут, ничего не перекрыто')
            foreach ($s in $sim) { [void]$lstSug.Items.Add($s) }
            $rows = [Math]::Min(6, $sim.Count)
            $h = 36 + $rows * $lstSug.ItemHeight + 12
            $pSug.Size = New-Object Drawing.Size(720, $h)
            $lstSug.Size = New-Object Drawing.Size(674, ($h - 46))
            Open-Suggest $h
            if ($script:SugScroll) {
                $script:SugScroll.Top = $lstSug.Top + 2
                $script:SugScroll.Height = [Math]::Max(30, ($lstSug.Height - 4))
                Update-SlimScroll $script:SugScroll
            }
        } else {
            $lHint.ForeColor = $script:C.Muted
            $lHint.Text = 'новый домен — можно добавлять'
        }
    }

    $txtNew.Add_TextChanged({ Update-Suggest; Refresh-All })
    $txtFilter.Add_TextChanged({ Refresh-All })

    $lstSug.Add_Click({
        if ($lstSug.SelectedItem) {
            $txtNew.Text = [string]$lstSug.SelectedItem
            Close-Suggest
        }
    })

    $btnAddDom.Add_Click({
        $r = Add-Domains $txtNew.Text
        if ($r.Added -gt 0) {
            Log ('добавлено сайтов: ' + $r.Added)
            $txtNew.Clear()
            $txtFilter.Clear()
            Close-Suggest
        } elseif ($r.Skipped -gt 0) {
            Log 'такой домен уже есть — не добавил'
        } elseif ($r.Bad.Count -gt 0) {
            Log ('не понял: ' + ($r.Bad -join ', '))
        }
        Refresh-All
        Refresh-DomCount
        Update-Suggest
    })

    $txtNew.Add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq 'Return') {
            $e.SuppressKeyPress = $true
            $btnAddDom.PerformClick()
        }
        if ($e.KeyCode -eq 'Escape') { Close-Suggest }
    })

    $btnPaste2.Add_Click({
        try { $t = [Windows.Forms.Clipboard]::GetText() } catch { $t = '' }
        if ($t) { $txtNew.Text = $t }
    })

    $btnDelSel.Add_Click({
        $sel = @($lstDomains.SelectedItems)
        if ($sel.Count -eq 0) { return }
        $drop = @{}
        foreach ($x in $sel) { $drop[[string]$x] = $true }
        $keepList = @((Get-Domains) | Where-Object { !$drop.ContainsKey($_) })
        Save-Domains $keepList
        Log ('удалено доменов: ' + $sel.Count)
        Refresh-All
        Refresh-DomCount
    })

    $lstDomains.Add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq 'Delete') { $e.SuppressKeyPress = $true; $btnDelSel.PerformClick() }
    })

    $lstDomains.Add_DoubleClick({
        if ($lstDomains.SelectedItem) {
            try { [Windows.Forms.Clipboard]::SetText([string]$lstDomains.SelectedItem) } catch { }
            Log ('скопировано: ' + [string]$lstDomains.SelectedItem)
        }
    })

    $btnDone.Add_Click({ $dlg.Close() })

    if ($TestDomains) { $txtNew.Text = 'inst' }
    Refresh-All
    $beforeDom = @(Get-Domains)
    [void]$dlg.ShowDialog($form)
    Refresh-DomCount
    $afterDom = @(Get-Domains)
    if ((($beforeDom -join "`n") -ne ($afterDom -join "`n"))) { Apply-DomainChanges 'список сайтов изменён' }
}

function Add-ServerLink([string]$raw) {
    $res = [pscustomobject]@{ Added = 0; Skipped = 0; Bad = 0 }
    $parts = @([string]$raw -split "[\s]+" | Where-Object { $_ })
    foreach ($p in $parts) {
        if (!$p.StartsWith('vless://')) { $res.Bad++; continue }
        try { $node = ConvertFrom-VlessLink $p } catch { $res.Bad++; continue }
        $list = Get-Servers
        if (Find-Server (Get-ServerKey $node) $list) { $res.Skipped++; continue }
        $list += $node
        Save-Servers $list
        $key = Get-ServerKey $node
        $script:Pings[$key] = (Test-ServerTcp $node)
        $script:Real.Remove($key) | Out-Null
        $res.Added++
        Refresh-Servers $key
        Log ('добавлен сервер: ' + (Display-Name $node.name) + '   ' + $key)
    }
    return $res
}

function Show-ServerDialog {
    $dlg = New-Object Windows.Forms.Form
    $dlg.Text = 'NOMIND Connect — добавить сервер'
    $dlg.ClientSize = New-Object Drawing.Size(640, 430)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedSingle'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:C.Bg
    $dlg.ForeColor = $script:C.Text
    $dlg.Font = $FBody
    $dlg.ShowInTaskbar = $false
    $dlg.Add_Shown({ [Dark]::Title($dlg.Handle) })
    if ($form.Icon) { $dlg.Icon = $form.Icon }

    $t1 = New-Object ShadowLabel
    $t1.AutoSize = $true
    $t1.Location = New-Object Drawing.Point(24, 16)
    $t1.Font = $FHead
    $t1.ForeColor = $script:C.Text
    $t1.Text = 'СЕРВЕР'
    $dlg.Controls.Add($t1)

    $h1 = New-Object ShadowLabel
    $h1.AutoSize = $false
    $h1.Location = New-Object Drawing.Point(24, 62)
    $h1.Size = New-Object Drawing.Size(592, 22)
    $h1.ForeColor = $script:C.Muted
    $h1.Text = 'Вставьте ссылку vless:// одного узла.'
    $dlg.Controls.Add($h1)

    $inpSrv = New-Object Windows.Forms.TextBox
    $inpSrv.Multiline = $true
    $inpSrv.WordWrap = $true
    $inpSrv.ScrollBars = 'None'
    $inpSrv.Location = New-Object Drawing.Point(24, 88)
    $inpSrv.Size = New-Object Drawing.Size(592, 96)
    $inpSrv.BackColor = $script:C.Card2
    $inpSrv.ForeColor = $script:C.Text
    $inpSrv.BorderStyle = 'FixedSingle'
    $inpSrv.Font = $FMono
    $dlg.Controls.Add($inpSrv)

    $hNote = New-Object ShadowLabel
    $hNote.AutoSize = $false
    $hNote.Location = New-Object Drawing.Point(24, 194)
    $hNote.Size = New-Object Drawing.Size(592, 92)
    $hNote.ForeColor = $script:C.GoldDim
    $hNote.Text = 'Сервер — это один конкретный узел (одна ссылка vless://). Подписка — это ссылка от провайдера, по которой серверов приходит сразу много, и они обновляются сами. Если провайдер дал подписку — жмите «Подписка», а не сюда.'
    $dlg.Controls.Add($hNote)

    $lStatus = New-Object ShadowLabel
    $lStatus.AutoSize = $false
    $lStatus.Location = New-Object Drawing.Point(24, 292)
    $lStatus.Size = New-Object Drawing.Size(592, 40)
    $lStatus.ForeColor = $script:C.Muted
    $lStatus.Text = ''
    $dlg.Controls.Add($lStatus)

    $btnOk = New-Object ShadowButton
    $btnOk.Text = 'Добавить'
    $btnOk.Location = New-Object Drawing.Point(24, 340)
    $btnOk.Size = New-Object Drawing.Size(160, 38)
    Style-Button $btnOk $true
    $dlg.Controls.Add($btnOk)

    $btnPaste = New-Object ShadowButton
    $btnPaste.Text = 'Из буфера'
    $btnPaste.Location = New-Object Drawing.Point(194, 340)
    $btnPaste.Size = New-Object Drawing.Size(130, 38)
    Style-Button $btnPaste $false $script:C.Sea
    $dlg.Controls.Add($btnPaste)

    $btnCancel = New-Object ShadowButton
    $btnCancel.Text = 'Закрыть'
    $btnCancel.Location = New-Object Drawing.Point(334, 340)
    $btnCancel.Size = New-Object Drawing.Size(120, 38)
    Style-Button $btnCancel
    $dlg.Controls.Add($btnCancel)

    $btnPaste.Add_Click({
        try {
            $t = [Windows.Forms.Clipboard]::GetText()
            if ($t) { $inpSrv.Text = $t.Trim() }
        } catch { }
    })

    $btnOk.Add_Click({
        $txt = $inpSrv.Text.Trim()
        if ($txt -eq '') {
            $lStatus.ForeColor = $script:C.Muted
            $lStatus.Text = 'вставьте ссылку vless://'
            return
        }
        $lStatus.ForeColor = $script:C.Text
        $lStatus.Text = 'добавляю и проверяю…'
        [Windows.Forms.Application]::DoEvents()
        $r = Add-ServerLink $txt
        if ($r.Added -gt 0) {
            $lStatus.ForeColor = $script:C.Green
            $msg = 'добавлено серверов: ' + $r.Added
            if ($r.Skipped -gt 0) { $msg += ', уже были: ' + $r.Skipped }
            if ($r.Bad -gt 0) { $msg += ', не разобрал: ' + $r.Bad }
            $lStatus.Text = $msg
            $inpSrv.Clear()
        } elseif ($r.Skipped -gt 0) {
            $lStatus.ForeColor = $script:C.Yellow
            $lStatus.Text = 'такой сервер уже есть в списке'
        } else {
            $lStatus.ForeColor = $script:C.Red
            $lStatus.Text = 'это не ссылка vless:// — скопируйте её целиком'
        }
    })

    $btnCancel.Add_Click({ $dlg.Close() })
    $dlg.CancelButton = $btnCancel

    $inpSrv.Add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq 'Return' -and $e.Control) { $e.SuppressKeyPress = $true; $btnOk.PerformClick() }
    })

    [void]$dlg.ShowDialog($form)
}

# ---------------- subscriptions: srok i obnovlenie ----------------

$script:SubFile = Join-Path $script:Run 'subs.json'
$script:SubProc = $null
$script:SubWaitTo = $null

function Plural([int]$n, [string]$one, [string]$few, [string]$many) {
    $m = [Math]::Abs($n) % 100
    $m1 = [Math]::Abs($n) % 10
    if ($m -ge 11 -and $m -le 14) { return $many }
    if ($m1 -eq 1) { return $one }
    if ($m1 -ge 2 -and $m1 -le 4) { return $few }
    return $many
}

function Format-Gb([long]$bytes) {
    if ($bytes -le 0) { return '' }
    $gb = $bytes / 1GB
    if ($gb -ge 100) { return ([string][Math]::Round($gb, 0) + ' ГБ') }
    return ([string][Math]::Round($gb, 1) + ' ГБ')
}

function Get-SubInfo([string]$url) {
    try {
        $s = Get-Settings
        if (!$s -or !$s.subInfo) { return $null }
        $p = $s.subInfo.PSObject.Properties[$url]
        if ($p) { return $p.Value }
    } catch { }
    return $null
}

function Get-SubDays($info) {
    if (!$info -or [long]$info.expire -le 0) { return $null }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $raw = ([long]$info.expire - $now) / 86400.0
    # srok pokazyvaem v bolshuyu storonu: 12 dney, a ne 11 iz-za paru chasov
    if ($raw -ge 0) { return [int][Math]::Ceiling($raw) }
    return [int][Math]::Truncate($raw)
}

function Get-SubState($info) {
    $st = [pscustomobject]@{
        Days      = $null
        DaysText  = 'ещё не проверялась'
        Color     = $script:C.Muted
        Traffic   = ''
        Checked   = ''
    }
    if (!$info) { return $st }
    try {
        $ck = [long]$info.checked
        if ($ck -gt 0) {
            $dt = [DateTimeOffset]::FromUnixTimeSeconds($ck).ToLocalTime()
            if ($dt.Date -eq (Get-Date).Date) { $st.Checked = 'проверено сегодня' }
            else { $st.Checked = ('проверено ' + $dt.ToString('dd.MM')) }
        }
    } catch { }
    if ([long]$info.total -gt 0) {
        $st.Traffic = ((Format-Gb ([long]$info.used)) + ' из ' + (Format-Gb ([long]$info.total)))
    }
    $days = Get-SubDays $info
    if ($null -eq $days) {
        $st.DaysText = 'срок не указан панелью'
        $st.Color = $script:C.Muted
        return $st
    }
    $st.Days = $days
    if ($days -lt 0) {
        $ago = [Math]::Abs($days)
        $st.DaysText = ('истекла ' + $ago + ' ' + (Plural $ago 'день' 'дня' 'дней') + ' назад')
        $st.Color = $script:C.Red
    } elseif ($days -eq 0) {
        $st.DaysText = 'истекает сегодня'
        $st.Color = $script:C.Red
    } else {
        $st.DaysText = ('осталось ' + $days + ' ' + (Plural $days 'день' 'дня' 'дней'))
        $st.Color = $(if ($days -le 3) { $script:C.Red } elseif ($days -le 7) { $script:C.Yellow } else { $script:C.Green })
    }
    return $st
}

function Get-SubHost([string]$url) {
    try { return ([Uri]$url).Host } catch { }
    return $url
}

function Get-SubTitle([string]$url) {
    try {
        $u = [Uri]$url
        $p = $u.AbsolutePath.Trim('/')
        if ($p) { return ($u.Host + ' · ' + $p) }
        return $u.Host
    } catch { }
    return $url
}

function Update-SubBadge {
    try {
        $s = Get-Settings
        $subs = @()
        if ($s -and $s.subs) { $subs = @($s.subs) }
        if ($subs.Count -eq 0) { $lblSubBadge.Text = ''; return }
        $daysList = @()
        foreach ($sub in $subs) {
            $st = Get-SubState (Get-SubInfo ([string]$sub.url))
            if ($null -ne $st.Days) { $daysList += [int]$st.Days }
        }
        $lead = 'подписка'
        if ($subs.Count -gt 1) {
            $lead = ([string]$subs.Count + ' ' + (Plural $subs.Count 'подписка' 'подписки' 'подписок'))
        }
        if ($daysList.Count -eq 0) {
            $lblSubBadge.Text = ($lead + ' · срок не проверен — нажмите значок обновления')
            $lblSubBadge.ForeColor = $script:C.GoldDim
            return
        }
        $best = ($daysList | Measure-Object -Minimum).Minimum
        if ($best -lt 0) {
            $lblSubBadge.Text = ($lead + ' · истекла')
            $lblSubBadge.ForeColor = $script:C.Red
        } elseif ($best -eq 0) {
            $lblSubBadge.Text = ($lead + ' · истекает сегодня')
            $lblSubBadge.ForeColor = $script:C.Red
        } else {
            $lblSubBadge.Text = ($lead + ' · осталось ' + $best + ' ' + (Plural $best 'день' 'дня' 'дней'))
            $lblSubBadge.ForeColor = $(if ($best -le 3) { $script:C.Red } elseif ($best -le 7) { $script:C.Yellow } else { $script:C.Green })
        }
    } catch { }
}

function Start-SubRefresh {
    if ($script:SubProc -and !$script:SubProc.HasExited) { Log 'подписка уже проверяется — подождите'; return }
    $s = Get-Settings
    $subs = @()
    if ($s -and $s.subs) { $subs = @($s.subs) }
    if ($subs.Count -eq 0) {
        # znachok obnovleniya tolko obnovlyaet - okno podpisok otkryvaet knopka "Podpiska"
        Log 'подписка не добавлена — добавьте её кнопкой «Подписка»'
        $lblSubBadge.Text = 'подписка не добавлена — добавьте кнопкой «Подписка»'
        $lblSubBadge.ForeColor = $script:C.GoldDim
        return
    }
    try { Remove-Item $script:SubFile -Force -ErrorAction SilentlyContinue } catch { }
    $script:SubWaitTo = $null
    $eng = Join-Path $PSScriptRoot 'engine.ps1'
    $argStr = '-NoProfile -ExecutionPolicy Bypass -File "' + $eng + '" -Action subs -OutFile "' + $script:SubFile + '"'
    try {
        $script:SubProc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argStr -WindowStyle Hidden -PassThru
        Log 'проверяю подписку: срок и новые серверы…'
    } catch {
        $script:SubProc = $null
        Log ('не смог запустить проверку подписки: ' + $_.Exception.Message)
    }
}

function Complete-SubRefresh {
    $raw = ''
    try {
        if (Test-Path $script:SubFile) {
            $fs = [IO.File]::Open($script:SubFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try {
                $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
                $raw = $sr.ReadToEnd()
                $sr.Dispose()
            } finally { $fs.Dispose() }
        }
    } catch { }
    $script:SubProc = $null
    $script:SubWaitTo = $null
    if (!$raw -or !$raw.Trim()) {
        Log 'подписка не ответила — попробуйте позже'
        Update-SubBadge
        return
    }
    $added = 0
    try {
        foreach ($r in @($raw | ConvertFrom-Json)) {
            $hostName = [string]$r.Url
            try { $hostName = ([Uri]$r.Url).Host } catch { }
            if ($r.Error) { Log ('подписка ' + $hostName + ': ошибка — ' + $r.Error) }
            else {
                $added += [int]$r.Added
                Log ('подписка ' + $hostName + ': проверена, серверов +' + [int]$r.Added)
            }
        }
    } catch { }
    if ($added -gt 0) {
        $sel = ''
        if ($lstServers.SelectedIndex -ge 0) { $sel = $lstServers.Items[$lstServers.SelectedIndex].Key }
        Refresh-Servers $sel
        Log ('серверов теперь: ' + (Get-Servers).Count)
    }
    Update-SubBadge
}

function Show-SubscriptionDialog {
    $dlg = New-Object Windows.Forms.Form
    $dlg.Text = 'NOMIND Connect — подписки'
    $dlg.ClientSize = New-Object Drawing.Size(680, 648)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedSingle'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:C.Bg
    $dlg.ForeColor = $script:C.Text
    $dlg.Font = $FBody
    $dlg.ShowInTaskbar = $false
    $dlg.Add_Shown({ [Dark]::Title($dlg.Handle) })
    if ($form.Icon) { $dlg.Icon = $form.Icon }

    $t1 = New-Object ShadowLabel
    $t1.AutoSize = $true
    $t1.Location = New-Object Drawing.Point(24, 16)
    $t1.Font = $FHead
    $t1.ForeColor = $script:C.Text
    $t1.Text = 'ПОДПИСКИ'
    $dlg.Controls.Add($t1)

    $h1 = New-Object ShadowLabel
    $h1.AutoSize = $false
    $h1.Location = New-Object Drawing.Point(24, 64)
    $h1.Size = New-Object Drawing.Size(632, 20)
    $h1.Font = $FLabel
    $h1.ForeColor = $script:C.Muted
    $h1.Text = 'Вставьте одну или несколько ссылок и нажмите «Добавить».'
    $dlg.Controls.Add($h1)

    $inpUrl = New-Object Windows.Forms.TextBox
    $inpUrl.Multiline = $true
    $inpUrl.WordWrap = $true
    $inpUrl.ScrollBars = 'None'
    $inpUrl.Location = New-Object Drawing.Point(24, 86)
    $inpUrl.Size = New-Object Drawing.Size(632, 68)
    $inpUrl.BackColor = $script:C.Card2
    $inpUrl.ForeColor = $script:C.Text
    $inpUrl.BorderStyle = 'FixedSingle'
    $inpUrl.Font = $FMono
    $dlg.Controls.Add($inpUrl)

    $s = Get-Settings
    $saved = @()
    if ($s -and $s.subs) { $saved = @($s.subs) }

    $l2 = New-Object ShadowLabel
    $l2.AutoSize = $true
    $l2.Location = New-Object Drawing.Point(24, 162)
    $l2.Font = $FLabel
    $l2.ForeColor = $script:C.Muted
    $l2.Text = Spaced 'hwid'
    $dlg.Controls.Add($l2)

    $h2 = New-Object ShadowLabel
    $h2.AutoSize = $true
    $h2.Location = New-Object Drawing.Point(82, 162)
    $h2.Font = $FLabel
    $h2.ForeColor = $script:C.Muted
    $h2.Text = 'необязательно — если панель привязывает ключ к устройству'
    $dlg.Controls.Add($h2)

    $inpHwid = New-Object Windows.Forms.TextBox
    $inpHwid.Location = New-Object Drawing.Point(24, 184)
    $inpHwid.Size = New-Object Drawing.Size(632, 28)
    $inpHwid.BackColor = $script:C.Card2
    $inpHwid.ForeColor = $script:C.Text
    $inpHwid.BorderStyle = 'FixedSingle'
    $inpHwid.Font = $FMono
    if ($s -and $s.hwid) { $inpHwid.Text = $s.hwid }
    $dlg.Controls.Add($inpHwid)

    $hNote = New-Object ShadowLabel
    $hNote.AutoSize = $false
    $hNote.Location = New-Object Drawing.Point(24, 220)
    $hNote.Size = New-Object Drawing.Size(632, 40)
    $hNote.Font = $FLabel
    $hNote.ForeColor = $script:C.GoldDim
    $hNote.Text = ('HWID — номер устройства для панели подписки.' + "`r`n" + 'Не знаете, что это — оставьте поле пустым.')
    $dlg.Controls.Add($hNote)

    # spisok podpisok: kazhdaya otdelno, so svoim srokom i trafikom
    $cardSub = New-Object Windows.Forms.Panel
    $cardSub.Location = New-Object Drawing.Point(24, 264)
    $cardSub.Size = New-Object Drawing.Size(632, 236)
    $cardSub.BackColor = $script:C.Card
    $dlg.Controls.Add($cardSub)

    $tSub = New-Object ShadowLabel
    $tSub.AutoSize = $true
    $tSub.Location = New-Object Drawing.Point(14, 10)
    $tSub.Font = $FLabel
    $tSub.ForeColor = $script:C.Muted
    $tSub.Text = Spaced 'мои подписки'
    $cardSub.Controls.Add($tSub)

    $lblCount = New-Object ShadowLabel
    $lblCount.AutoSize = $false
    $lblCount.Location = New-Object Drawing.Point(300, 9)
    $lblCount.Size = New-Object Drawing.Size(200, 18)
    $lblCount.TextAlign = 'MiddleRight'
    $lblCount.Font = $FSmall
    $lblCount.ForeColor = $script:C.GoldDim
    $lblCount.Text = ''
    $cardSub.Controls.Add($lblCount)

    $btnPrev = New-Object ShadowLabel
    $btnPrev.AutoSize = $false
    $btnPrev.Location = New-Object Drawing.Point(510, 6)
    $btnPrev.Size = New-Object Drawing.Size(24, 22)
    $btnPrev.Font = $FTitle
    $btnPrev.ForeColor = $script:C.Muted
    $btnPrev.TextAlign = 'MiddleCenter'
    $btnPrev.Text = '‹'
    $btnPrev.Cursor = 'Hand'
    $btnPrev.Visible = $false
    $cardSub.Controls.Add($btnPrev)

    $lblPage = New-Object ShadowLabel
    $lblPage.AutoSize = $false
    $lblPage.Location = New-Object Drawing.Point(534, 9)
    $lblPage.Size = New-Object Drawing.Size(70, 18)
    $lblPage.Font = $FSmall
    $lblPage.ForeColor = $script:C.Muted
    $lblPage.TextAlign = 'MiddleCenter'
    $lblPage.Text = ''
    $cardSub.Controls.Add($lblPage)

    $btnNext = New-Object ShadowLabel
    $btnNext.AutoSize = $false
    $btnNext.Location = New-Object Drawing.Point(604, 6)
    $btnNext.Size = New-Object Drawing.Size(24, 22)
    $btnNext.Font = $FTitle
    $btnNext.ForeColor = $script:C.Muted
    $btnNext.TextAlign = 'MiddleCenter'
    $btnNext.Text = '›'
    $btnNext.Cursor = 'Hand'
    $btnNext.Visible = $false
    $cardSub.Controls.Add($btnNext)

    $pRows = New-Object Windows.Forms.Panel
    $pRows.Location = New-Object Drawing.Point(6, 34)
    $pRows.Size = New-Object Drawing.Size(620, 192)
    $pRows.BackColor = $script:C.Card
    $cardSub.Controls.Add($pRows)

    $lStatus = New-Object ShadowLabel
    $lStatus.AutoSize = $false
    $lStatus.Location = New-Object Drawing.Point(24, 508)
    $lStatus.Size = New-Object Drawing.Size(632, 36)
    $lStatus.Font = $FLabel
    $lStatus.ForeColor = $script:C.Muted
    $lStatus.Text = ''
    $dlg.Controls.Add($lStatus)

    $btnLoad = New-Object ShadowButton
    $btnLoad.Text = 'Добавить'
    $btnLoad.Location = New-Object Drawing.Point(24, 552)
    $btnLoad.Size = New-Object Drawing.Size(170, 38)
    Style-Button $btnLoad $true
    $dlg.Controls.Add($btnLoad)

    $btnRefresh = New-Object ShadowButton
    $btnRefresh.Text = 'Обновить всё'
    $btnRefresh.Location = New-Object Drawing.Point(204, 552)
    $btnRefresh.Size = New-Object Drawing.Size(170, 38)
    Style-Button $btnRefresh $false $script:C.Sea
    $dlg.Controls.Add($btnRefresh)

    $btnClose = New-Object ShadowButton
    $btnClose.Text = 'Закрыть'
    $btnClose.Location = New-Object Drawing.Point(536, 552)
    $btnClose.Size = New-Object Drawing.Size(120, 38)
    Style-Button $btnClose
    $dlg.Controls.Add($btnClose)

    $lNote = New-Object ShadowLabel
    $lNote.AutoSize = $false
    $lNote.Location = New-Object Drawing.Point(24, 600)
    $lNote.Size = New-Object Drawing.Size(632, 20)
    $lNote.Font = $FSmall
    $lNote.ForeColor = $script:C.GoldDim
    $lNote.Text = ''
    $dlg.Controls.Add($lNote)

    $ui = @{ page = 0; perPage = 4 }

    # pererisovyvaem stroki tolko kogda chto-to izmenilos
    $render = {
        $s2 = Get-Settings
        $subs2 = @()
        if ($s2 -and $s2.subs) { $subs2 = @($s2.subs) }
        $total = $subs2.Count
        $pages = [Math]::Max(1, [int][Math]::Ceiling($total / [double]$ui.perPage))
        if ($ui.page -ge $pages) { $ui.page = $pages - 1 }
        if ($ui.page -lt 0) { $ui.page = 0 }

        $states = @()
        foreach ($sb in $subs2) {
            $inf = Get-SubInfo ([string]$sb.url)
            $states += [pscustomobject]@{ Url = [string]$sb.url; State = (Get-SubState $inf) }
        }
        $sig = [string]$ui.page + '|' + (($states | ForEach-Object { $_.Url + '>' + $_.State.DaysText + '>' + $_.State.Traffic }) -join '|')

        $btnPrev.Visible = ($pages -gt 1)
        $btnNext.Visible = ($pages -gt 1)
        $lblPage.Text = $(if ($pages -gt 1) { ([string]($ui.page + 1) + ' / ' + [string]$pages) } else { '' })
        $lblCount.Text = $(if ($total -gt 0) { ([string]$total + ' ' + (Plural $total 'подписка' 'подписки' 'подписок')) } else { '' })

        if ($pRows.Tag -eq $sig) { return }
        $pRows.Tag = $sig
        $pRows.SuspendLayout()
        $pRows.Controls.Clear()

        if ($total -eq 0) {
            $ph = New-Object ShadowLabel
            $ph.AutoSize = $false
            $ph.Location = New-Object Drawing.Point(12, 10)
            $ph.Size = New-Object Drawing.Size(592, 22)
            $ph.Font = $FLabel
            $ph.ForeColor = $script:C.Muted
            $ph.Text = 'подписок пока нет — вставьте ссылку выше и нажмите «Добавить»'
            $pRows.Controls.Add($ph)
        } else {
            $from = $ui.page * $ui.perPage
            $last = [Math]::Min($total, $from + $ui.perPage)
            for ($i = $from; $i -lt $last; $i++) {
                $it = $states[$i]
                $st = $it.State
                $y = ($i - $from) * 47

                $row = New-Object Windows.Forms.Panel
                $row.Location = New-Object Drawing.Point(0, $y)
                $row.Size = New-Object Drawing.Size(620, 47)
                $row.BackColor = $script:C.Card
                $row.Add_Paint({
                    param($sp, $ep)
                    $pen = New-Object Drawing.Pen($script:C.Line, 1)
                    $ep.Graphics.DrawLine($pen, 0, ($sp.Height - 1), $sp.Width, ($sp.Height - 1))
                    $pen.Dispose()
                })

                $nm = New-Object ShadowLabel
                $nm.AutoSize = $false
                $nm.Location = New-Object Drawing.Point(12, 4)
                $nm.Size = New-Object Drawing.Size(330, 20)
                $nm.Font = $FLabel
                $nm.ForeColor = $script:C.Text
                $nm.Text = (Get-SubTitle $it.Url)
                $nm.AutoEllipsis = $true
                $row.Controls.Add($nm)

                $dl = New-Object ShadowLabel
                $dl.AutoSize = $false
                $dl.Location = New-Object Drawing.Point(348, 4)
                $dl.Size = New-Object Drawing.Size(224, 20)
                $dl.TextAlign = 'MiddleRight'
                $dl.Font = $FLabel
                $dl.ForeColor = $st.Color
                $dl.Text = $st.DaysText
                $row.Controls.Add($dl)

                $sec = $st.Traffic
                if ($st.Checked) { $sec = $(if ($sec) { $sec + '   ·   ' + $st.Checked } else { $st.Checked }) }
                if (!$sec) { $sec = 'ожидает первой проверки' }
                $tr = New-Object ShadowLabel
                $tr.AutoSize = $false
                $tr.Location = New-Object Drawing.Point(12, 25)
                $tr.Size = New-Object Drawing.Size(562, 17)
                $tr.Font = $FSmall
                $tr.ForeColor = $script:C.Muted
                $tr.Text = $sec
                $tr.AutoEllipsis = $true
                $row.Controls.Add($tr)

                $rm = New-Object Windows.Forms.Panel
                $rm.Location = New-Object Drawing.Point(590, 12)
                $rm.Size = New-Object Drawing.Size(22, 22)
                $rm.BackColor = $script:C.Card
                $rm.Cursor = 'Hand'
                $rm.Tag = @{ hover = $false; url = $it.Url }
                $rm.Add_Paint({
                    param($sp, $ep)
                    $g2 = $ep.Graphics
                    $g2.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
                    $col = $(if ($sp.Tag.hover) { $script:C.Pink } else { $script:C.Muted })
                    $pn = New-Object Drawing.Pen($col, [single]1.6)
                    $pn.StartCap = [Drawing.Drawing2D.LineCap]::Round
                    $pn.EndCap = [Drawing.Drawing2D.LineCap]::Round
                    $g2.DrawLine($pn, 7, 7, 15, 15)
                    $g2.DrawLine($pn, 15, 7, 7, 15)
                    $pn.Dispose()
                })
                $rm.Add_MouseEnter({ param($sp, $ep) $sp.Tag.hover = $true; $sp.Invalidate() })
                $rm.Add_MouseLeave({ param($sp, $ep) $sp.Tag.hover = $false; $sp.Invalidate() })
                $rm.Add_Click({
                    param($sp, $ep)
                    $u = [string]$sp.Tag.url
                    Remove-Subscription $u
                    Log ('подписка удалена: ' + (Get-SubTitle $u))
                    $lStatus.ForeColor = $script:C.Muted
                    $lStatus.Text = 'подписка удалена — её серверы остались в списке'
                    & $render
                    Update-SubBadge
                })
                $row.Controls.Add($rm)

                $pRows.Controls.Add($row)
            }
        }
        $pRows.ResumeLayout()
    }

    $tRender = New-Object Windows.Forms.Timer
    $tRender.Interval = 900
    $tRender.Add_Tick({ try { & $render } catch { } })
    $tRender.Start()
    $dlg.Add_FormClosed({ $tRender.Stop() })

    $btnPrev.Add_Click({ $ui.page = $ui.page - 1; & $render })
    $btnNext.Add_Click({ $ui.page = $ui.page + 1; & $render })

    $btnRefresh.Add_Click({
        $sx = Get-Settings
        $cnt = 0
        if ($sx -and $sx.subs) { $cnt = @($sx.subs).Count }
        if ($cnt -eq 0) {
            $lStatus.ForeColor = $script:C.Red
            $lStatus.Text = 'сначала добавьте подписку'
            return
        }
        Start-SubRefresh
        $lStatus.ForeColor = $script:C.Muted
        $lStatus.Text = 'проверяю подписки — срок, трафик и новые серверы…'
    })

    $btnLoad.Add_Click({
        $urls = @($inpUrl.Text -split "[\r\n]+" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($urls.Count -eq 0) {
            $lStatus.ForeColor = $script:C.Red
            $lStatus.Text = 'вставьте ссылку на подписку'
            return
        }
        $hwid = $inpHwid.Text.Trim()
        $lStatus.ForeColor = $script:C.Text
        $lStatus.Text = 'загружаю…'
        [Windows.Forms.Application]::DoEvents()
        $ok = 0; $skip = 0; $bad = 0; $errs = @()
        foreach ($u in $urls) {
            try {
                $r = Import-Subscription $u $hwid
                $ok += $r.Added; $skip += $r.Skipped; $bad += $r.Bad
                Save-Subscription $u $hwid
            } catch {
                $errs += (Get-SubTitle $u) + ': ' + $_.Exception.Message
            }
        }
        $sc = Get-Settings
        $cnt = 0
        if ($sc -and $sc.subs) { $cnt = @($sc.subs).Count }
        $msg = ('серверов добавлено: ' + $ok)
        if ($skip -gt 0) { $msg += (', уже были: ' + $skip) }
        if ($bad -gt 0) { $msg += (', не поддержаны: ' + $bad) }
        if ($cnt -gt 1) { $msg += (' · подписок: ' + $cnt) }
        $lStatus.ForeColor = $(if ($errs.Count -gt 0) { $script:C.Red } elseif ($ok -gt 0) { $script:C.Green } else { $script:C.Yellow })
        if ($errs.Count -gt 0) {
            $lStatus.Text = 'подписка не добавлена — подробности в окне сообщения'
            try {
                Show-NomindBox -Title 'подписка не добавлена' -Message ($errs -join "`r`n`r`n") -Danger | Out-Null
            } catch { }
        } else {
            $lStatus.Text = $msg
        }
        if ($ok -gt 0 -or $errs.Count -eq 0) {
            $inpUrl.Clear()
            $lNote.Text = 'подписки сохранены — при следующем запуске подставятся автоматически'
        }
        Log ('подписки: ' + $msg)
        $ui.page = [Math]::Max(0, [int][Math]::Floor(($cnt - 1) / [double]$ui.perPage))
        & $render
        $keepKey = Get-Selected
        Refresh-Servers $(if ($keepKey) { Get-ServerKey $keepKey } else { '' })
        Log ('серверов теперь: ' + (Get-Servers).Count)
        Update-SubBadge
    })

    $btnClose.Add_Click({ $dlg.Close() })

    & $render
    [void]$dlg.ShowDialog($form)
}


# ---------------- events ----------------

function Do-ToggleConnect {
    $st = Get-State
    if ($st.Running) { Do-Disconnect } else { Do-Connect }
}

function Do-PingAll {
    if (Test-PingBusy) {
        Stop-PingScan
        return
    }
    Log 'проверяю все серверы в фоне (окно не подвисает)…'
    Start-PingScan
}

function Do-TestSelected([string]$key = '') {
    $node = if ($key) { Find-Server $key (Get-Servers) } else { Get-Selected }
    if (!$node) { Log 'сначала выберите сервер в списке'; return }
    $s = Get-Settings
    $key = Get-ServerKey $node
    $lblInfo.Text = ('тестирую ' + (Display-Name $node.name) + ' …')
    Log ('тест через сервер: ' + (Display-Name $node.name))
    [Windows.Forms.Application]::DoEvents()
    $r = Test-ServerReal $node $s (Get-Domains)
    $script:Real[$key] = [int]$r.Ms
    Set-RowPing $key
    if ($r.Ms -lt 0) { Log '  сервер не ответил' }
    else { Log ('  ответ ' + $r.Ms + ' ms, выход ' + $r.Ip + ' (' + $r.Loc + ')') }
    Update-State
}

function Do-DeleteSelected {
    $keys = @(Get-SelectedKeys)
    if ($keys.Count -eq 0) { return }
    $nodes = @(Get-SelectedServers)
    if ($nodes.Count -eq 0) { return }
    $msg = if ($nodes.Count -eq 1) {
        'Сервер "' + (Display-Name $nodes[0].name) + '" будет убран из списка. Это не изменит сами узлы в панели.'
    } else {
        ('Будут убраны ' + $nodes.Count + ' ' + (Plural $nodes.Count 'сервер' 'сервера' 'серверов') + ' из списка.' + "`r`n" + 'Это не изменит сами узлы в панели.')
    }
    $title = if ($nodes.Count -eq 1) { 'удалить сервер' } else { 'удалить серверы' }
    $r = Show-NomindBox -Title $title -Message $msg -Yes 'Удалить' -No 'Отмена' -Danger
    if ($r -ne 'Yes') { return }
    $keep = @((Get-Servers) | Where-Object { $keys -notcontains (Get-ServerKey $_) })
    Save-Servers $keep
    Refresh-Servers
    if ($nodes.Count -eq 1) { Log ('удалён: ' + (Display-Name $nodes[0].name)) }
    else { Log ('удалено серверов: ' + $nodes.Count) }
}

$btnConnect.Add_Click({ Do-ToggleConnect })

$btnTest.Add_Click({ Do-PingAll })

$btnTestOne.Add_Click({ Do-TestSelected })

$btnAdd.Add_Click({ Show-ServerDialog })

$btnDel.Add_Click({ Do-DeleteSelected })

$btnQuickAdd.Add_Click({
    if ($txtAdd.Text.Trim() -eq '') { return }
    $r = Add-Domains $txtAdd.Text
    if ($r.Added -gt 0) {
        Log ('добавлено сайтов: ' + $r.Added)
        $txtAdd.Clear()
    } else {
        Log ('не добавил: ' + $(if ($r.Bad.Count -gt 0) { ($r.Bad -join ', ') } else { 'такое уже есть' }))
    }
    Refresh-DomCount
    if ($r.Added -gt 0) { Apply-DomainChanges 'добавлены сайты' }
})

$txtAdd.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq 'Return') { $e.SuppressKeyPress = $true; $btnQuickAdd.PerformClick() }
})

$btnAllDom.Add_Click({ Show-DomainEditor })

$btnSub.Add_Click({ Show-SubscriptionDialog })

$script:Exiting = $false
$script:CloseToTray = [bool](Get-AppSetting 'closeToTray' $true)
$script:TrayHinted = $false

$form.Add_FormClosing({
    param($s, $e)
    $why = [string]$e.CloseReason
    try {
        [IO.File]::AppendAllText((Join-Path $script:Run 'tray.log'),
            ((Get-Date -Format 'HH:mm:ss') + '  close: reason=' + $why + ' exiting=' + $script:Exiting + ' closeToTray=' + $script:CloseToTray + "`r`n"),
            (New-Object Text.UTF8Encoding($true)))
    } catch { }
    # TaskManagerClosing/ApplicationExitCall WinForms отдаёт и на обычный WM_CLOSE,
    # поэтом�� настоящий выход определяем по своему флагу (меню трея) и завершению Windows.
    $hard = $script:Exiting -or (-not $script:CloseToTray) -or ($why -eq 'WindowsShutDown')

    if (-not $hard) {
        $e.Cancel = $true
        try { $form.Hide() } catch { }
        if (-not $script:TrayHinted) {
            $script:TrayHinted = $true
            try {
                $script:Tray.ShowBalloonTip(2200, 'NOMIND Connect',
                    'Свернулось в трей — VPN продолжает работать. Клик по овечке вернёт окно.',
                    [Windows.Forms.ToolTipIcon]::Info)
            } catch { }
        }
        return
    }

    try { if ($script:Tray) { $script:Tray.Visible = $false } } catch { }
    try { if (Test-PingBusy) { Stop-PingScan } } catch { }
    # При выключении Windows времени мало: сначала снимаем системный прокси
    # (это две записи в реестр), и только потом гасим xray с ожиданием до 3 с.
    # Иначе Windows успевает убить процесс, и прокси остаётся включённым на мёртвый порт.
    try {
        $bak = Join-Path $script:Run 'proxy-backup.json'
        if (Test-Path $bak) { Disable-SystemProxy | Out-Null }
    } catch { }
    try {
        [IO.File]::AppendAllText((Join-Path $script:Run 'shutdown.log'),
            ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  exit: ' + $why + "`r`n"),
            (New-Object Text.UTF8Encoding($true)))
    } catch { }
    try { Stop-Engine | Out-Null } catch { }
})

$form.Add_Shown({
    trap { Write-UiError 'shown' $_.Exception; break }
    Ensure-GuardAutostart
    [Dark]::Title($form.Handle)
    $s = Get-Settings
    Set-Mode $(if ($s.mode -eq 'smart') { 'smart' } else { 'global' })
    Refresh-Servers $s.server
    Refresh-DomCount
    if (!(Get-EngineProcess) -and (Get-SystemProxy).Enable -eq 1) {
        Disable-SystemProxy | Out-Null
    }
    Update-State
    Log 'NOMIND Connect готов'
    Log ('серверов: ' + (Get-Servers).Count + '   ·   сайтов через VPN: ' + (Get-Domains).Count)
    Log '«Проверить все» — пинг всех серверов · «Тест узла» — только выбранного'

    Update-SubBadge
    if ($s -and $s.subs -and @($s.subs).Count -gt 0) {
        $nowU = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $stale = $false
        foreach ($sb in @($s.subs)) {
            $inf = Get-SubInfo ([string]$sb.url)
            if (!$inf -or [long]$inf.checked -lt ($nowU - 43200)) { $stale = $true }
        }
        if ($stale) { Start-SubRefresh }
    }

    $script:Timer = New-Object Windows.Forms.Timer
    $script:Timer.Interval = 4000
    $script:Timer.Add_Tick({
        $st = Get-State
        if ($st.Running -and $st.ProxyOn) {
            if ($lblState.Text -ne (Spaced 'подключено')) { Update-State }
        } elseif (!$st.Running -and $lblState.Text -eq (Spaced 'подключено')) {
            Log 'xray остановился — выключаю системный прокси'
            Disable-SystemProxy | Out-Null
            Update-State
        }
    })
    $script:Timer.Start()

    # avtoping: v fone, chtoby okno ne lagalo
    $script:PingWatch = New-Object Windows.Forms.Timer
    $script:PingWatch.Interval = 700
    $script:PingWatch.Add_Tick({
        trap {
            try { [IO.File]::AppendAllText((Join-Path $script:Run 'gui.err.log'), ((Get-Date -Format 'HH:mm:ss') + '  watch at: ' + $_.InvocationInfo.PositionMessage + "`r`n"), (New-Object Text.UTF8Encoding($true))) } catch { }
            continue
        }
        if (!(Test-PingBusy)) {
            if (@($script:PingProcs).Count -eq 0) { return }
            if (!$script:PingWaitTo) { $script:PingWaitTo = (Get-Date).AddSeconds(2); return }
            if ((Get-Date) -lt $script:PingWaitTo) { return }
            foreach ($k in @(Read-PingScan)) { Set-PingInPlace $k }
            $script:PingProcs = @()
            $script:PingWaitTo = $null
            Update-PingButton
            Refresh-Servers
            $alive = @($script:Real.Keys | Where-Object { $script:Real[$_] -ge 0 }).Count
            Log ('проверка готова: грузят ' + $alive + ' из ' + (Get-Servers).Count)
            $st = Get-State
            if (!$st.Running) { $lblInfo.Text = 'выберите сервер и нажмите «подключить»' }
            Update-State
            return
        }
        foreach ($k in @(Read-PingScan)) { Set-PingInPlace $k }
    })
    $script:PingWatch.Start()

    # pulsirovanie knopki "proverit vse", poka idet proverka
    $script:PingPulse = New-Object Windows.Forms.Timer
    $script:PingPulse.Interval = 120
    $script:PingPulse.Add_Tick({
        trap { continue }
        if (!(Test-PingBusy)) { return }
        $script:Pulse += 0.26
        try { $btnTest.Invalidate() } catch { }
    })
    $script:PingPulse.Start()

    $script:PingAuto = New-Object Windows.Forms.Timer
    $script:PingAuto.Interval = ($script:PingEveryMin * 60 * 1000)
    $script:PingAuto.Add_Tick({
        if (Test-PingBusy) { return }
        $st = Get-State
        if ($st.Running) { return }
        Log 'плановая проверка пинга'
        Start-PingScan
    })
    $script:PingAuto.Start()

    # proverka podpiski v fone (ikonka sverhu)
    $script:SubWatch = New-Object Windows.Forms.Timer
    $script:SubWatch.Interval = 900
    $script:SubWatch.Add_Tick({
        trap { continue }
        if (!$script:SubProc) { return }
        if (!$script:SubProc.HasExited) { return }
        if (!$script:SubWaitTo) { $script:SubWaitTo = (Get-Date).AddSeconds(2); return }
        if ((Get-Date) -lt $script:SubWaitTo) { return }
        Complete-SubRefresh
    })
    $script:SubWatch.Start()

    # vtoroy zapusk (yarlyk/exe) pokazyvaet uzhe rabotayushchee okno iz treya
    $script:UiTick = New-Object Windows.Forms.Timer
    $script:UiTick.Interval = 700
    $script:UiTick.Add_Tick({
        trap { continue }
        $flag = Join-Path $script:Run 'show.flag'
        if (Test-Path $flag) {
            Remove-Item $flag -Force -ErrorAction SilentlyContinue
            Show-AppWindow
        }
    })
    $script:UiTick.Start()

    Start-PingScan

    # testovyy huk: avtomaticheski podklyuchitsya k pervomu serveru (dlya proverki)
    if ($TestConnect) {
        $script:TC = New-Object Windows.Forms.Timer
        $script:TC.Interval = 1500
        $script:TC.Add_Tick({
            $script:TC.Stop()
            try {
                for ($i = 0; $i -lt $lstServers.Items.Count; $i++) {
                    $it = $lstServers.Items[$i]
                    if ($it -and !$it.Header -and $it.Node) { $lstServers.SelectedIndex = $i; break }
                }
                Do-Connect
                [IO.File]::AppendAllText((Join-Path $script:Run 'gui.err.log'), ((Get-Date -Format 'HH:mm:ss') + '  testconnect: running=' + (Get-State).Running + "`r`n"), (New-Object Text.UTF8Encoding($true)))
            } catch {
                Write-UiError 'testconnect' $_.Exception
            }
        })
        $script:TC.Start()
    }

    # testovyy huk: ostanovka proverki pinga povtornym nazhatiem
    if ($TestPingStop) {
        $script:TPS = New-Object Windows.Forms.Timer
        $script:TPS.Interval = 2000
        $script:TPSState = 0
        $script:TPS.Add_Tick({
            try {
                if ($script:TPSState -eq 0) {
                    $script:TPSState = 1
                    [IO.File]::AppendAllText((Join-Path $script:Run 'gui.err.log'), ((Get-Date -Format 'HH:mm:ss') + '  pingstop: busy before=' + (Test-PingBusy) + "`r`n"), (New-Object Text.UTF8Encoding($true)))
                    Do-PingAll
                } else {
                    $script:TPS.Stop()
                    Start-Sleep -Milliseconds 400
                    $n = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*-Action pingall*' }).Count
                    [IO.File]::AppendAllText((Join-Path $script:Run 'gui.err.log'), ((Get-Date -Format 'HH:mm:ss') + '  pingstop: busy after=' + (Test-PingBusy) + ' procs=' + $n + "`r`n"), (New-Object Text.UTF8Encoding($true)))
                }
            } catch { Write-UiError 'pingstop' $_.Exception }
        })
        $script:TPS.Start()
    }
    if ($TestDomains) {
        $script:TD = New-Object Windows.Forms.Timer
        $script:TD.Interval = 600
        $script:TD.Add_Tick({ $script:TD.Stop(); Show-DomainEditor })
        $script:TD.Start()
    }

    if ($TestSettings) {
        $script:TSet = New-Object Windows.Forms.Timer
        $script:TSet.Interval = 600
        $script:TSet.Add_Tick({ $script:TSet.Stop(); Show-SettingsDialog })
        $script:TSet.Start()
    }

    if ($TestSubs) {
        $script:TS = New-Object Windows.Forms.Timer
        $script:TS.Interval = 600
        $script:TS.Add_Tick({ $script:TS.Stop(); Show-SubscriptionDialog })
        $script:TS.Start()
    }

    if ($TestServer) {
        $script:TV = New-Object Windows.Forms.Timer
        $script:TV.Interval = 600
        $script:TV.Add_Tick({
            $script:TV.Stop()
            try { Show-ServerDialog } catch {
                [IO.File]::AppendAllText((Join-Path $script:Run 'gui.err.log'), ((Get-Date -Format 'HH:mm:ss') + '  dialog: ' + $_.Exception.Message + '  |  ' + $_.ScriptStackTrace + "`r`n"))
            }
        })
        $script:TV.Start()
    }

    if ($TestDelete) {
        $script:TDel = New-Object Windows.Forms.Timer
        $script:TDel.Interval = 900
        $script:TDel.Add_Tick({
            $script:TDel.Stop()
            try {
                $picked = 0
                for ($i = 0; $i -lt $lstServers.Items.Count -and $picked -lt 2; $i++) {
                    $it = $lstServers.Items[$i]
                    if (!$it -or $it.Header) { continue }
                    $lstServers.SetSelected($i, $true)
                    $picked++
                }
                Do-DeleteSelected
            } catch {
                [IO.File]::AppendAllText((Join-Path $script:Run 'gui.err.log'), ((Get-Date -Format 'HH:mm:ss') + '  delete: ' + $_.Exception.Message + '  |  ' + $_.ScriptStackTrace + "`r`n"))
            }
        })
        $script:TDel.Start()
    }
})

if ($SelfTest) {
    if ($TestDomains) {
        $r = Add-Domains "https://www.instagram.com/reels/  chatgpt.com, *.twitch.tv`nfoobar"
        Write-Output ('add-domains: added=' + $r.Added + ' skipped=' + $r.Skipped + ' bad=' + ($r.Bad -join '|'))
        $all = @(Get-Domains)
        Write-Output ('instagram.com in list: ' + ($all -contains 'instagram.com'))
        Write-Output ('twitch.tv in list: ' + ($all -contains 'twitch.tv'))
    }
    Set-Mode 'global' -NoSave
    Refresh-Servers
    Refresh-DomCount
    Update-State
    Write-Output ('selftest ok: servers=' + @($lstServers.Items | Where-Object { !$_.Header }).Count + ' domains=' + (Get-Domains).Count)
    $form.Dispose()
    return
}

[Windows.Forms.Application]::AddMessageFilter((New-Object NMWheel))
try {
    [Windows.Forms.Application]::Run($form)
} catch {
    $m = 'main: ' + $_.Exception.Message + '  |  ' + $_.ScriptStackTrace
    try { [IO.File]::AppendAllText((Join-Path $script:Run 'gui.err.log'), ((Get-Date -Format 'HH:mm:ss') + '  ' + $m + "`r`n")) } catch { }
    [Windows.Forms.MessageBox]::Show($m, 'NOMIND Connect', 'OK', 'Error') | Out-Null
}

# Страховка: как бы ни завершился цикл сообщений, прокси нашего туннеля
# не должен остаться включённым на мёртвый порт.
try {
    $bak = Join-Path $script:Run 'proxy-backup.json'
    if (Test-Path $bak) { Disable-SystemProxy | Out-Null }
} catch { }
try { Stop-Engine | Out-Null } catch { }

# vyhod: ubiraem ikonku iz treya i otpuskaem mutex
try { if ($script:Tray) { $script:Tray.Visible = $false; $script:Tray.Dispose() } } catch { }
try { if ($script:AppMutex) { $script:AppMutex.ReleaseMutex() } } catch { }
try { $form.Dispose() } catch { }
