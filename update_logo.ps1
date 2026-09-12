Add-Type -AssemblyName System.Drawing

$src = "C:\Users\Cryxus\AppData\Roaming\Claude\local-agent-mode-sessions\60f4662f-9ead-4ba3-85ae-22c005c1ffb1\9ff69d48-5793-4fea-a9f6-39c8a228a9cf\local_e8d876c9-c26b-476f-aabd-bdd9e4dec130\uploads\512x512 Solo logo.png"
$project = "C:\Users\Cryxus\Desktop\AppWeb\Servimoto\servimoto_app"

Write-Host "Copiando logo (512x512) a assets y web..."
Copy-Item $src "$project\assets\logo.png" -Force
Copy-Item $src "$project\assets\assets\logo.png" -Force
Copy-Item $src "$project\web\favicon.png" -Force
Copy-Item $src "$project\web\icons\Icon-512.png" -Force
Copy-Item $src "$project\web\icons\Icon-maskable-512.png" -Force

function Resize-Image {
    param($sourcePath, $destPath, $width, $height)
    $img = [System.Drawing.Image]::FromFile($sourcePath)
    $bmp = New-Object System.Drawing.Bitmap($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.DrawImage($img, 0, 0, $width, $height)
    $bmp.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bmp.Dispose()
    $img.Dispose()
    Write-Host "Creado: $destPath"
}

Write-Host "Generando versiones 192x192..."
Resize-Image $src "$project\web\icons\Icon-192.png" 192 192
Resize-Image $src "$project\web\icons\Icon-maskable-192.png" 192 192

Write-Host ""
Write-Host "Listo! Logo actualizado en todas las rutas:" -ForegroundColor Green
Write-Host "  assets/logo.png (512x512)"
Write-Host "  assets/assets/logo.png (512x512)"
Write-Host "  web/favicon.png (512x512)"
Write-Host "  web/icons/Icon-192.png (192x192)"
Write-Host "  web/icons/Icon-512.png (512x512)"
Write-Host "  web/icons/Icon-maskable-192.png (192x192)"
Write-Host "  web/icons/Icon-maskable-512.png (512x512)"
