<#
.SYNOPSIS
    Generates assets\icon.ico: a green keycap with swap arrows, in every size
    Windows uses (16-64 px as 32-bit bitmaps, 128 and 256 px as PNG).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\make-icon.ps1
    powershell -ExecutionPolicy Bypass -File tools\make-icon.ps1 -Preview preview.png
#>
param(
    [string]$Out = (Join-Path $PSScriptRoot '..\assets\icon.ico'),
    [string]$Preview = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$Sizes = 16, 20, 24, 32, 40, 48, 64, 128, 256

function Color([string]$hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }

function RoundRect([double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = [float](2 * $r)
    $p.AddArc([float]$x, [float]$y, $d, $d, 180, 90)
    $p.AddArc([float]($x + $w - $d), [float]$y, $d, $d, 270, 90)
    $p.AddArc([float]($x + $w - $d), [float]($y + $h - $d), $d, $d, 0, 90)
    $p.AddArc([float]$x, [float]($y + $h - $d), $d, $d, 90, 90)
    $p.CloseFigure()
    $p
}

function VGradient([double]$y, [double]$h, [string]$top, [string]$bottom) {
    $r = New-Object System.Drawing.RectangleF 0, ([float]$y - 1), 10, ([float]$h + 2)
    New-Object System.Drawing.Drawing2D.LinearGradientBrush $r, (Color $top), (Color $bottom), 90
}

function Draw-Icon([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    # Everything is designed on a 256 grid; small sizes get a slightly
    # simpler, bolder version so the arrows stay readable.
    $small = $size -le 24
    $k = $size / 256.0
    function U([double]$v) { $v * $k }

    # Keycap body (the darker "skirt") and top face
    $body = RoundRect (U 8) (U 12) (U 240) (U 236) (U 56)
    $b = VGradient (U 12) (U 236) '#22A84A' '#11632B'
    $g.FillPath($b, $body)
    $faceH = if ($small) { 186 } else { 180 }
    $face = RoundRect (U 30) (U 20) (U 196) (U $faceH) (U 40)
    $f = VGradient (U 20) (U $faceH) '#5AE57E' '#30D158'
    $g.FillPath($f, $face)

    # Swap arrows (white, round caps)
    $w = if ($small) { [Math]::Max(1.7, (U 26)) } else { U 18 }
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), ([float]$w)
    $pen.StartCap = $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    if ($small) { $y1 = 80; $y2 = 140; $head = 30; $x1 = 66; $x2 = 190 }
    else        { $y1 = 86; $y2 = 136; $head = 25; $x1 = 78; $x2 = 178 }
    $g.DrawLine($pen, [float](U $x1), [float](U $y1), [float](U ($x2 - 2)), [float](U $y1))
    $g.DrawLines($pen, [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF ([float](U ($x2 - $head))), ([float](U ($y1 - $head)))),
        (New-Object System.Drawing.PointF ([float](U $x2)), ([float](U $y1))),
        (New-Object System.Drawing.PointF ([float](U ($x2 - $head))), ([float](U ($y1 + $head))))))
    $g.DrawLine($pen, [float](U $x2), [float](U $y2), [float](U ($x1 + 2)), [float](U $y2))
    $g.DrawLines($pen, [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF ([float](U ($x1 + $head))), ([float](U ($y2 - $head)))),
        (New-Object System.Drawing.PointF ([float](U $x1)), ([float](U $y2))),
        (New-Object System.Drawing.PointF ([float](U ($x1 + $head))), ([float](U ($y2 + $head))))))

    foreach ($o in $pen, $b, $f, $body, $face, $g) { $o.Dispose() }
    $bmp
}

# 32-bit DIB entry: BITMAPINFOHEADER + bottom-up BGRA rows + empty AND mask
function Get-DibBytes([System.Drawing.Bitmap]$bmp) {
    $n = $bmp.Width
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter $ms
    $bw.Write([int]40); $bw.Write([int]$n); $bw.Write([int]($n * 2))
    $bw.Write([int16]1); $bw.Write([int16]32); $bw.Write([int]0)
    $bw.Write([int]($n * $n * 4)); $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0)
    $rect = New-Object System.Drawing.Rectangle 0, 0, $n, $n
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $row = New-Object byte[] ($n * 4)
    for ($yy = $n - 1; $yy -ge 0; $yy--) {
        [System.Runtime.InteropServices.Marshal]::Copy([IntPtr]($data.Scan0.ToInt64() + $yy * $data.Stride), $row, 0, $n * 4)
        $bw.Write($row)
    }
    $bmp.UnlockBits($data)
    $maskRow = [int]([Math]::Ceiling($n / 32.0) * 4)
    $bw.Write((New-Object byte[] ($maskRow * $n)))
    $bw.Flush()
    $ms.ToArray()
}

function Get-PngBytes([System.Drawing.Bitmap]$bmp) {
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $ms.ToArray()
}

$images = foreach ($s in $Sizes) {
    $bmp = Draw-Icon $s
    [byte[]]$bytes = if ($s -ge 128) { Get-PngBytes $bmp } else { Get-DibBytes $bmp }
    [pscustomobject]@{ Size = $s; Bytes = $bytes; Bitmap = $bmp }
}

$fs = [System.IO.File]::Create([System.IO.Path]::GetFullPath($Out))
$bw = New-Object System.IO.BinaryWriter $fs
$bw.Write([int16]0); $bw.Write([int16]1); $bw.Write([int16]$images.Count)
$offset = 6 + 16 * $images.Count
foreach ($img in $images) {
    $dim = if ($img.Size -ge 256) { 0 } else { $img.Size }
    $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([int16]1); $bw.Write([int16]32); $bw.Write([int]$img.Bytes.Length); $bw.Write([int]$offset)
    $offset += $img.Bytes.Length
}
foreach ($img in $images) { $bw.Write([byte[]]$img.Bytes) }
$bw.Close()
Write-Host "Wrote $Out ($($images.Count) sizes)"

if ($Preview) {
    # Every size at 1:1 on a light and a dark strip, to check legibility
    $wTotal = [int](($Sizes | Measure-Object -Sum).Sum + 12 * ($Sizes.Count + 1))
    $sheet = New-Object System.Drawing.Bitmap $wTotal, 560
    $g = [System.Drawing.Graphics]::FromImage($sheet)
    $g.Clear((Color '#F3F3F3'))
    $g.FillRectangle((New-Object System.Drawing.SolidBrush (Color '#202020')), 0, 280, $wTotal, 280)
    $x = 12
    foreach ($img in $images) {
        $g.DrawImageUnscaled($img.Bitmap, $x, 12)
        $g.DrawImageUnscaled($img.Bitmap, $x, 292)
        $x += $img.Size + 12
    }
    $g.Dispose()
    $sheet.Save([System.IO.Path]::GetFullPath($Preview), [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "Preview: $Preview"
}
