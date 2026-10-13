@echo off
title Local AI App
set "APP_DIR=%~dp0"

where ollama >nul 2>&1
if not errorlevel 1 goto run
if exist "%LOCALAPPDATA%\Programs\Ollama\ollama.exe" goto addpath
echo Ollama is not installed. Run local_ai.bat first to install it and download a model.
pause
exit /b

:addpath
set "PATH=%PATH%;%LOCALAPPDATA%\Programs\Ollama"

:run
set "OLLAMA_ORIGINS=*"
ollama list >nul 2>&1
if not errorlevel 1 goto serve
echo Ollama is not running. Opening the Ollama app...
set "LNK=C:\Users\DELL\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Ollama.lnk"
if not exist "%LNK%" set "LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Ollama.lnk"
if exist "%LNK%" goto openlnk
start "Ollama Engine" /min ollama serve
goto waitinit
:openlnk
start "" "%LNK%"
:waitinit
set /a N=0

:wait
ollama list >nul 2>&1
if not errorlevel 1 goto serve
set /a N+=1
if %N% GEQ 40 goto fail
timeout /t 1 >nul
goto wait

:fail
echo Could not start Ollama. Open the Ollama app from the Start menu, then run this file again.
pause
exit /b

:serve
echo Opening Local AI...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = Get-Content -LiteralPath '%~f0' -Raw; iex ($s.Substring($s.IndexOf('#PS'+'-START') + 9))"
pause
exit /b

#PS-START
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class Win {
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int k);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string n);
}
'@
$null = [Win]::SetProcessDPIAware()
$overlayOK = $true
try {
    Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
// Transparent, click-through, always-on-top layer that draws the blue click ripples on the real screen.
public class Overlay : Form {
    List<float[]> r = new List<float[]>();
    public Overlay() {
        FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true;
        StartPosition = FormStartPosition.Manual; BackColor = Color.Black; TransparencyKey = Color.Black;
        AutoScaleMode = AutoScaleMode.None; DoubleBuffered = true;
    }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get { CreateParams p = base.CreateParams; p.ExStyle |= 0x080000A8; return p; }
    }
    public void Add(int x, int y) { r.Add(new float[] { x, y, Environment.TickCount }); }
    public void Tick() {
        int now = Environment.TickCount;
        r.RemoveAll(a => now - a[2] > 3000);
        if (r.Count > 0) { Opacity = Math.Max(0.05, 1.0 - (now - r[r.Count - 1][2]) / 3000.0); }
        Invalidate();
    }
    protected override void OnPaint(PaintEventArgs e) {
        int now = Environment.TickCount;
        foreach (float[] a in r) {
            float t = (now - a[2]) / 3000f, rad = 12 + 70 * t;
            using (Pen p = new Pen(Color.FromArgb(30, 144, 255), 6)) e.Graphics.DrawEllipse(p, a[0] - rad, a[1] - rad, rad * 2, rad * 2);
            using (SolidBrush b = new SolidBrush(Color.FromArgb(30, 144, 255))) e.Graphics.FillEllipse(b, a[0] - 7, a[1] - 7, 14, 14);
        }
    }
}
'@
} catch {
    $overlayOK = $false
    Write-Host "Click ripple overlay is unavailable (the agent still works): $_" -ForegroundColor Yellow
}

$file = Join-Path $env:APP_DIR 'local_ai_app.html'
if (-not (Test-Path $file)) {
    Write-Host 'local_ai_app.html must be in the same folder as this file.' -ForegroundColor Red
    return
}
$l = $null
$port = 8123
while ($port -le 8140) {
    $try = New-Object System.Net.HttpListener
    $try.Prefixes.Add("http://127.0.0.1:$port/")
    try { $try.Start(); $l = $try; break } catch { $port++ }
}
if (-not $l) {
    Write-Host 'Could not open a local port between 8123 and 8140.' -ForegroundColor Red
    return
}
$url = "http://127.0.0.1:$port/"
$token = [guid]::NewGuid().ToString('N')
$ov = $null
$sess = $null

$VK = @{ ctrl=0x11; control=0x11; alt=0x12; shift=0x10; win=0x5B; windows=0x5B; enter=0x0D; return=0x0D; tab=0x09; space=0x20
         backspace=0x08; delete=0x2E; del=0x2E; insert=0x2D; up=0x26; down=0x28; left=0x25; right=0x27; home=0x24; end=0x23
         pageup=0x21; pagedown=0x22; capslock=0x14 }
1..12 | ForEach-Object { $VK["f$_"] = 0x6F + $_ }
$EXT = @(0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2D, 0x2E)

function Send-Bytes($c, $bytes, $type) {
    $c.Response.ContentType = $type
    $c.Response.ContentLength64 = $bytes.Length
    $c.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $c.Response.Close()
}
function Send-Json($c, $o) { Send-Bytes $c ([Text.Encoding]::UTF8.GetBytes(($o | ConvertTo-Json -Compress -Depth 4))) 'application/json' }
function End-Session {
    if ($global:ov) { $global:ov.Close(); $global:ov.Dispose() }
    $global:ov = $null
    $global:sess = $null
}
# Types text exactly as given (special SendKeys characters are escaped). Returns $true if Esc stopped it.
function Type-Text($s) {
    foreach ($ch in $s.ToCharArray()) {
        if ([Win]::GetAsyncKeyState(0x1B) -band 0x8000) { return $true }
        $k = [string]$ch
        if ($k -match '[+^%~(){}\[\]]') { $k = '{' + $k + '}' }
        elseif ($ch -eq "`n") { $k = '{ENTER}' }
        elseif ($ch -eq "`r") { continue }
        [System.Windows.Forms.SendKeys]::SendWait($k)
        Start-Sleep -Milliseconds 30
    }
    return $false
}
# Presses a key or shortcut such as "enter", "ctrl+s", "win+r", "alt+tab", "f5". Esc is reserved for the emergency stop.
function Press-Keys($spec) {
    $codes = @()
    foreach ($p in ($spec.ToLower() -split '\+')) {
        $p = $p.Trim()
        if ($p -eq 'esc' -or $p -eq 'escape') { throw 'Esc is reserved for the emergency stop' }
        if ($VK.ContainsKey($p)) { $codes += [int]$VK[$p] }
        elseif ($p -match '^[a-z0-9]$') { $codes += [int][char]$p.ToUpper() }
        else { throw "unknown key: $p" }
    }
    if ($codes.Count -eq 0) { throw 'no keys given' }
    foreach ($k in $codes) {
        $f = 0; if ($EXT -contains $k) { $f = 1 }
        [Win]::keybd_event([byte]$k, 0, $f, [UIntPtr]::Zero)
    }
    Start-Sleep -Milliseconds 60
    [array]::Reverse($codes)
    foreach ($k in $codes) {
        $f = 2; if ($EXT -contains $k) { $f = 3 }
        [Win]::keybd_event([byte]$k, 0, $f, [UIntPtr]::Zero)
    }
}
$uiaOK = $true
try { Add-Type -AssemblyName UIAutomationClient; Add-Type -AssemblyName UIAutomationTypes } catch { $uiaOK = $false }
# Lists clickable items (buttons, fields, links...) in the front window and the taskbar, in screenshot coordinates.
function Get-Marks {
    $list = @()
    if (-not $uiaOK) { return $list }
    try {
        $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
        $k = [Math]::Min(1.0, 1024.0 / $b.Width)
        $AE = [System.Windows.Automation.AutomationElement]
        $CT = [System.Windows.Automation.ControlType]
        $conds = foreach ($t in @($CT::Button, $CT::Edit, $CT::Hyperlink, $CT::MenuItem, $CT::TabItem, $CT::CheckBox, $CT::RadioButton, $CT::ComboBox, $CT::ListItem, $CT::SplitButton)) {
            [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, $t)
        }
        $or = [System.Windows.Automation.OrCondition]::new([System.Windows.Automation.Condition[]]@($conds))
        $off = [System.Windows.Automation.PropertyCondition]::new($AE::IsOffscreenProperty, $false)
        $cond = [System.Windows.Automation.AndCondition]::new($off, $or)
        $roots = @()
        $fg = [Win]::GetForegroundWindow()
        if ($fg -ne [IntPtr]::Zero) { $roots += $AE::FromHandle($fg) }
        $tray = [Win]::FindWindow('Shell_TrayWnd', $null)
        if ($tray -ne [IntPtr]::Zero) { $roots += $AE::FromHandle($tray) }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        foreach ($root in $roots) {
            foreach ($el in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)) {
                if ($list.Count -ge 60 -or $sw.ElapsedMilliseconds -gt 5000) { break }
                $r = $el.Current.BoundingRectangle
                if ($r.IsEmpty -or $r.Width -lt 6 -or $r.Height -lt 6) { continue }
                $cx = $r.X + $r.Width / 2; $cy = $r.Y + $r.Height / 2
                if ($cx -lt $b.X -or $cy -lt $b.Y -or $cx -ge $b.X + $b.Width -or $cy -ge $b.Y + $b.Height) { continue }
                $name = [string]$el.Current.Name
                if (-not $name) { $name = [string]$el.Current.AutomationId }
                if ($name.Length -gt 40) { $name = $name.Substring(0, 40) }
                $list += @{ id = $list.Count + 1; type = ($el.Current.ControlType.ProgrammaticName -replace 'ControlType\.', ''); name = $name; x = [int](($cx - $b.X) * $k); y = [int](($cy - $b.Y) * $k); w = [int]($r.Width * $k); h = [int]($r.Height * $k) }
            }
        }
    } catch { Write-Host "Could not list clickable items: $_" -ForegroundColor Yellow }
    return $list
}
function Get-Shot($maxw = 1024, $quality = 70) {
    $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object Drawing.Bitmap $b.Width, $b.Height
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [Drawing.Point]::Empty, $b.Size)
    $g.Dispose()
    $k = [Math]::Min(1.0, [double]$maxw / $b.Width)
    $w = [int]($b.Width * $k); $h = [int]($b.Height * $k)
    $small = New-Object Drawing.Bitmap $bmp, $w, $h
    $enc = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $ep = New-Object Drawing.Imaging.EncoderParameters 1
    $ep.Param[0] = [Drawing.Imaging.EncoderParameter]::new([Drawing.Imaging.Encoder]::Quality, [long]$quality)
    $ms = New-Object IO.MemoryStream
    $small.Save($ms, $enc, $ep)
    $bmp.Dispose(); $small.Dispose()
    return @{ ok = $true; img = [Convert]::ToBase64String($ms.ToArray()); w = $w; h = $h }
}

try { Start-Process msedge -ArgumentList "--app=$url" } catch { Start-Process $url }
Write-Host "Local AI is running at $url" -ForegroundColor Green
Write-Host 'Keep this window open while you use the app. Close it to stop.'

while ($l.IsListening) {
    $t = $l.GetContextAsync()
    while (-not $t.Wait(30)) {
        if ($ov) { $ov.Tick() }
        [Windows.Forms.Application]::DoEvents()
        if ($sess -and [DateTime]::Now -gt $sess.end) { End-Session }
    }
    $c = $t.Result
    $path = $c.Request.Url.AbsolutePath
    if ($c.Request.HttpMethod -eq 'GET' -and $path -eq '/') {
        $html = [IO.File]::ReadAllText($file).Replace('__TOKEN__', $token)
        Send-Bytes $c ([Text.Encoding]::UTF8.GetBytes($html)) 'text/html; charset=utf-8'
    }
    elseif ($c.Request.HttpMethod -eq 'POST') {
        # Every action needs this app's own page: matching origin plus the secret token.
        $out = @{ ok = $false; error = 'unknown request' }
        try {
            if ($c.Request.Headers['Origin'] -ne "http://127.0.0.1:$port") { throw 'blocked origin' }
            $sr = New-Object IO.StreamReader($c.Request.InputStream, [Text.Encoding]::UTF8)
            $req = $sr.ReadToEnd() | ConvertFrom-Json
            if ($req.token -ne $token) { throw 'blocked token' }
            switch ($path) {
                '/type' {
                    # Type for me: letters and spaces only, 100 words at most.
                    $txt = ([string]$req.text) -replace '[^A-Za-z ]', ' ' -replace '\s+', ' '
                    $words = @($txt.Trim() -split ' ' | Where-Object { $_ } | Select-Object -First 100)
                    Write-Host "Typing $($words.Count) words in 5 seconds..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 5
                    $stopped = Type-Text ($words -join ' ')
                    $out = @{ ok = $true; words = $words.Count; stopped = $stopped }
                }
                '/agent/start' {
                    End-Session
                    $secs = [Math]::Min(300, [Math]::Max(5, [int]$req.secs))
                    $mx = [Math]::Min(20, [Math]::Max(1, [int]$req.maxClicks))
                    $sess = @{ end = [DateTime]::Now.AddSeconds($secs + 3); clicks = 0; max = $mx; keys = 0 }
                    if ($overlayOK) {
                        try {
                            $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
                            $ov = New-Object Overlay
                            $ov.SetBounds($b.X, $b.Y, $b.Width, $b.Height)
                            $ov.Show()
                        } catch { $ov = $null; Write-Host "Overlay failed: $_" -ForegroundColor Yellow }
                    }
                    Write-Host "Screen Agent started: $secs seconds, up to $mx clicks. Hold Esc to stop." -ForegroundColor Yellow
                    $out = @{ ok = $true }
                }
                '/agent/shot' {
                    if (-not $sess) { throw 'no active session' }
                    $out = Get-Shot
                }
                '/agent/act' {
                    if (-not $sess) { throw 'no active session' }
                    if ([Win]::GetAsyncKeyState(0x1B) -band 0x8000) { End-Session; throw 'stopped with Esc' }
                    switch ($req.type) {
                        'click' {
                            if ($sess.clicks -ge $sess.max) { throw 'click limit reached' }
                            $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
                            $x = [int][Math]::Round([double]$req.x * $b.Width / [double]$req.w)
                            $y = [int][Math]::Round([double]$req.y * $b.Height / [double]$req.h)
                            $x = [Math]::Min($b.Width - 1, [Math]::Max(0, $x))
                            $y = [Math]::Min($b.Height - 1, [Math]::Max(0, $y))
                            $sess.clicks++
                            if ($ov) { $ov.Add($x, $y) }
                            [Win]::SetCursorPos($b.X + $x, $b.Y + $y) | Out-Null
                            Start-Sleep -Milliseconds 80
                            $dn = 2; $up = 4; if ($req.button -eq 'right') { $dn = 8; $up = 16 }
                            $n = 1; if ($req.double) { $n = 2 }
                            for ($i = 0; $i -lt $n; $i++) {
                                [Win]::mouse_event($dn, 0, 0, 0, [UIntPtr]::Zero)
                                [Win]::mouse_event($up, 0, 0, 0, [UIntPtr]::Zero)
                                Start-Sleep -Milliseconds 70
                            }
                            Write-Host "Click at ($x, $y)"
                            $out = @{ ok = $true; clicks = $sess.clicks }
                        }
                        'key' {
                            if ($sess.keys -ge 100) { throw 'key limit reached' }
                            $sess.keys++
                            Press-Keys ([string]$req.keys)
                            Write-Host "Keys: $($req.keys)"
                            $out = @{ ok = $true }
                        }
                        'type' {
                            if ($sess.keys -ge 100) { throw 'key limit reached' }
                            $txt = [string]$req.text
                            if ($txt.Length -gt 300) { $txt = $txt.Substring(0, 300) }
                            $sess.keys++
                            $stopped = Type-Text $txt
                            Write-Host "Typed $($txt.Length) characters"
                            $out = @{ ok = $true; typed = $txt; stopped = $stopped }
                        }
                        default { throw 'unknown action' }
                    }
                }
                '/agent/marks' {
                    if (-not $sess) { throw 'no active session' }
                    $out = @{ ok = $true; marks = @(Get-Marks) }
                }
                '/agent/stop' {
                    End-Session
                    $out = @{ ok = $true }
                }
                '/screen/shot' {
                    $mw = [Math]::Min(3840, [Math]::Max(320, [int]$req.maxw))
                    $out = Get-Shot $mw 85
                }
                '/sys' {
                    $os = Get-CimInstance Win32_OperatingSystem
                    $gpu = $null
                    try {
                        $line = (& nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>$null | Select-Object -First 1)
                        if ($line) { $p = $line -split ',\s*'; $gpu = @{ util = [int]$p[0]; used = [int]$p[1]; total = [int]$p[2] } }
                    } catch {}
                    $out = @{ ok = $true; ram = @{ total = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 1); free = [Math]::Round($os.FreePhysicalMemory / 1MB, 1) }; gpu = $gpu }
                }
                '/fetch' {
                    $u = [string]$req.url
                    if ($u -notmatch '^https?://') { throw 'only http and https links are allowed' }
                    $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 15
                    $t = [string]$r.Content
                    $t = [regex]::Replace($t, '(?is)<(script|style|noscript)[^>]*>.*?</\1>', ' ')
                    $t = [regex]::Replace($t, '<[^>]+>', ' ')
                    $t = ([System.Net.WebUtility]::HtmlDecode($t) -replace '\s+', ' ').Trim()
                    if ($t.Length -gt 12000) { $t = $t.Substring(0, 12000) }
                    $out = @{ ok = $true; text = $t }
                }
                '/ollama/open' {
                    $up = $false
                    try { Invoke-WebRequest -Uri 'http://127.0.0.1:11434/' -UseBasicParsing -TimeoutSec 2 | Out-Null; $up = $true } catch {}
                    if (-not $up) {
                        $lnk = 'C:\Users\DELL\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Ollama.lnk'
                        if (-not (Test-Path $lnk)) { $lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Ollama.lnk' }
                        Write-Host 'Ollama is not running. Opening it...' -ForegroundColor Yellow
                        if (Test-Path $lnk) { Start-Process $lnk } else { Start-Process ollama -ArgumentList 'serve' -WindowStyle Minimized }
                    }
                    $out = @{ ok = $true; running = $up }
                }
            }
        } catch {
            Write-Host "Request failed: $_" -ForegroundColor Red
            $out = @{ ok = $false; error = "$_" }
        }
        Send-Json $c $out
    }
    else {
        $c.Response.StatusCode = 404
        $c.Response.Close()
    }
}
