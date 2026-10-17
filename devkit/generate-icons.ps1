# Regenerate repository-native vector artwork as iOS PNG resources on Windows.
Add-Type -AssemblyName System.Drawing
$projectPath = Split-Path -Parent $PSScriptRoot
$resources = @(
    @{ Directory = 'prefs/TrollVNCPrefs/Resources'; Name = 'icon@2x.png'; Size = 58 },
    @{ Directory = 'prefs/TrollVNCPrefs/Resources'; Name = 'icon@3x.png'; Size = 87 },
    @{ Directory = 'prefs/CCTrollVNC/Resources'; Name = 'SettingsIcon@2x.png'; Size = 58 },
    @{ Directory = 'prefs/CCTrollVNC/Resources'; Name = 'SettingsIcon@3x.png'; Size = 87 },
    @{ Directory = 'prefs/CCTrollVNC/Resources'; Name = 'icon.png'; Size = 36 },
    @{ Directory = 'prefs/CCTrollVNC/Resources'; Name = 'icon@2x.png'; Size = 72 },
    @{ Directory = 'prefs/CCTrollVNC/Resources'; Name = 'icon@3x.png'; Size = 108 }
)
foreach ($resource in $resources) {
    $bitmap = New-Object Drawing.Bitmap($resource.Size, $resource.Size)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.ScaleTransform($resource.Size / 100.0, $resource.Size / 100.0)
    if ($resource.Directory -like '*CCTrollVNC*' -and $resource.Name -like 'icon*') {
        $graphics.Clear([Drawing.Color]::Transparent) # Control Center uses an alpha glyph
    } else {
        $graphics.Clear([Drawing.Color]::FromArgb(17,105,168))
    }
    $pen = New-Object Drawing.Pen([Drawing.Color]::White, 5)
    $pen.StartCap = $pen.EndCap = [Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawRectangle($pen, 33,13,34,63)
    $pen.Width = 4
    foreach ($line in @(@(44,20,56,20),@(45,69,55,69),@(13,40,25,40),@(25,40,20,35),@(25,40,20,45),@(87,51,75,51),@(75,51,80,46),@(75,51,80,56))) {
        $graphics.DrawLine($pen, $line[0],$line[1],$line[2],$line[3])
    }
    $font = New-Object Drawing.Font('Arial', 13, [Drawing.FontStyle]::Bold)
    $format = New-Object Drawing.StringFormat
    $format.Alignment = [Drawing.StringAlignment]::Center
    $graphics.DrawString('DK',$font,[Drawing.Brushes]::White,[Drawing.RectangleF]::new(0,77,100,23),$format)
    $outputPath = Join-Path (Join-Path $projectPath $resource.Directory) $resource.Name
    $bitmap.Save($outputPath,[Drawing.Imaging.ImageFormat]::Png)
    $format.Dispose(); $font.Dispose(); $pen.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
}
