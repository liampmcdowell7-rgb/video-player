# Regenerates the neutral placeholder app icon and Top Shelf image (Windows PowerShell 5.1+).
# Usage:  powershell -NoProfile -File scripts\generate-icons.ps1
# Output: App\Assets.xcassets\App Icon & Top Shelf Image.brandassets
#
# Design: grayscale only, no text, no brand colour. Three layers for tvOS parallax:
#   Back   = opaque full-bleed flat gray
#   Middle = translucent lighter disc (clear edges, varied opacity)
#   Front  = white play-symbol triangle
# Content stays inside the centre safe zone (<= 50% of height) so the focus effect
# does not crop it. Layers are unmasked rectangles; the system applies rounding.
# Sizes: small icon 400x240 @1x / 800x480 @2x, large icon 1280x768 @1x / 2560x1536 @2x,
# Top Shelf static fallback 2320x720 @1x / 4640x1440 @2x (plus 1920x720 for older tooling).
param([string]$Root = (Split-Path -Parent $PSScriptRoot))
Add-Type -AssemblyName System.Drawing
$cat = Join-Path $Root "App\Assets.xcassets"
$brand = Join-Path $cat "App Icon & Top Shelf Image.brandassets"
if (Test-Path $cat) { Remove-Item -Recurse -Force $cat }

function Save-Png($path, $w, $h, $kind) {
  New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
  $bmp = New-Object System.Drawing.Bitmap($w, $h)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $cx = $w / 2.0; $cy = $h / 2.0; $u = [Math]::Min($w, $h)
  switch ($kind) {
    'back'   { $g.Clear([System.Drawing.Color]::FromArgb(255, 58, 58, 60)) }
    'shelf'  { $g.Clear([System.Drawing.Color]::FromArgb(255, 58, 58, 60)) }
    'middle' {
      $g.Clear([System.Drawing.Color]::Transparent)
      $r = $u * 0.30
      $br = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150, 174, 174, 178))
      $g.FillEllipse($br, [single]($cx - $r), [single]($cy - $r), [single](2 * $r), [single](2 * $r))
    }
    'front'  {
      $g.Clear([System.Drawing.Color]::Transparent)
      $s = $u * 0.30
      $pts = [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF([single]($cx - $s * 0.38), [single]($cy - $s * 0.55))),
        (New-Object System.Drawing.PointF([single]($cx - $s * 0.38), [single]($cy + $s * 0.55))),
        (New-Object System.Drawing.PointF([single]($cx + $s * 0.62), [single]$cy)))
      $g.FillPolygon([System.Drawing.Brushes]::White, $pts)
    }
  }
  $g.Dispose(); $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}
function Write-Json($path, $text) {
  New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}
$info = '"info" : { "author" : "xcode", "version" : 1 }'

Write-Json (Join-Path $cat "Contents.json") "{ $info }"
Write-Json (Join-Path $brand "Contents.json") @"
{
  "assets" : [
    { "filename" : "App Icon - Large.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "1280x768" },
    { "filename" : "App Icon - Small.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "400x240" },
    { "filename" : "Top Shelf Image.imageset", "idiom" : "tv", "role" : "top-shelf-image", "size" : "1920x720" },
    { "filename" : "Top Shelf Image Wide.imageset", "idiom" : "tv", "role" : "top-shelf-image-wide", "size" : "2320x720" }
  ],
  $info
}
"@

$stacks = @(@("App Icon - Large", 1280, 768), @("App Icon - Small", 400, 240))
foreach ($spec in $stacks) {
  $stack = Join-Path $brand ($spec[0] + ".imagestack")
  Write-Json (Join-Path $stack "Contents.json") "{ `"layers`" : [ { `"filename`" : `"Front.imagestacklayer`" }, { `"filename`" : `"Middle.imagestacklayer`" }, { `"filename`" : `"Back.imagestacklayer`" } ], $info }"
  foreach ($layer in @("Front", "Middle", "Back")) {
    $ld = Join-Path $stack "$layer.imagestacklayer"
    Write-Json (Join-Path $ld "Contents.json") "{ $info }"
    $set = Join-Path $ld "Content.imageset"
    Write-Json (Join-Path $set "Contents.json") "{ `"images`" : [ { `"filename`" : `"$layer.png`", `"idiom`" : `"tv`", `"scale`" : `"1x`" }, { `"filename`" : `"$layer@2x.png`", `"idiom`" : `"tv`", `"scale`" : `"2x`" } ], $info }"
    Save-Png (Join-Path $set "$layer.png") $spec[1] $spec[2] ($layer.ToLower())
    Save-Png (Join-Path $set "$layer@2x.png") (2 * $spec[1]) (2 * $spec[2]) ($layer.ToLower())
  }
}
foreach ($spec in @(@("Top Shelf Image", 1920, 720), @("Top Shelf Image Wide", 2320, 720))) {
  $set = Join-Path $brand ($spec[0] + ".imageset")
  $fn = ($spec[0] -replace ' ', '')
  Write-Json (Join-Path $set "Contents.json") "{ `"images`" : [ { `"filename`" : `"$fn.png`", `"idiom`" : `"tv`", `"scale`" : `"1x`" }, { `"filename`" : `"$fn@2x.png`", `"idiom`" : `"tv`", `"scale`" : `"2x`" } ], $info }"
  Save-Png (Join-Path $set "$fn.png") $spec[1] $spec[2] 'shelf'
  Save-Png (Join-Path $set "$fn@2x.png") (2 * $spec[1]) (2 * $spec[2]) 'shelf'
}
Write-Host "Icons generated."
