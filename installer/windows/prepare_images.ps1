param([string]$OutputDirectory, [string]$Version = '0.07')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'dist\installer-images' }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
function MakeImage($Source, $Destination, $Width, $Height, $Heading, $Subheading) {
  $original = [Drawing.Image]::FromFile((Join-Path $root ('imgs\' + $Source)))
  $bitmap = [Drawing.Bitmap]::new($Width, $Height, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [Drawing.Graphics]::FromImage($bitmap)
  $font = [Drawing.Font]::new('Segoe UI', 11, [Drawing.FontStyle]::Bold)
  $small = [Drawing.Font]::new('Segoe UI', 9)
  $white = [Drawing.SolidBrush]::new([Drawing.Color]::White)
  try {
    $g.Clear([Drawing.Color]::FromArgb(23, 36, 54))
    $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $top = 8
    if ($Heading) {
      $g.DrawString($Heading, $font, $white, [Drawing.RectangleF]::new(12, 16, $Width-24, 64))
      $g.DrawString($Subheading, $small, $white, [Drawing.RectangleF]::new(12, 82, $Width-24, 90))
      $top = 180
    }
    $scale = [Math]::Min(($Width-16)/$original.Width, ($Height-$top-8)/$original.Height)
    $w = [int]($original.Width*$scale); $h = [int]($original.Height*$scale)
    $g.DrawImage($original, [int](($Width-$w)/2), [int]($top+($Height-$top-$h)/2), $w, $h)
    $bitmap.Save((Join-Path $OutputDirectory $Destination), [Drawing.Imaging.ImageFormat]::Bmp)
  } finally { $g.Dispose(); $bitmap.Dispose(); $original.Dispose(); $font.Dispose(); $small.Dispose(); $white.Dispose() }
}
MakeImage 'tres_maquinas_3d.png' 'welcome.bmp' 246 471 "MultiSuite $Version" 'Projetar, preparar, simular e fabricar.'
$files = @('multicnc_novo_layout.png', 'Makepcb01.png', 'Makerouter01.png', 'simucnc_router_ao_vivo.png', 'Laserpcb01.png', 'Laserart01.png')
for ($i=0; $i -lt $files.Count; $i++) { MakeImage $files[$i] ("slide$i.bmp") 900 350 '' '' }
