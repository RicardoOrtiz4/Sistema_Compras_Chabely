$base = Join-Path $env:TEMP 'sistema_compras_chabely\diagnostics'
$appLog = Join-Path $base 'app.log'
$errorLog = Join-Path $base 'errors.log'
$repoRoot = Split-Path $PSScriptRoot -Parent
$buildRoot = Join-Path $repoRoot 'build\windows'
$nativeLogs = @()
$nativeDumps = @()

if (Test-Path $buildRoot) {
  $nativeLogs = Get-ChildItem -Path $buildRoot -Recurse -Filter 'native_crash.log' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
  $nativeDumps = Get-ChildItem -Path $buildRoot -Recurse -Filter 'native_crash_*.dmp' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
}

Write-Host "Base de logs: $base"
Write-Host "Build de Windows: $buildRoot"
Write-Host ''

Write-Host '===== APP LOG ====='
if (Test-Path $appLog) {
  Get-Content -LiteralPath $appLog -Tail 250
} else {
  Write-Host 'app.log no existe'
}

Write-Host ''
Write-Host '===== ERROR LOG ====='
if (Test-Path $errorLog) {
  Get-Content -LiteralPath $errorLog -Tail 250
} else {
  Write-Host 'errors.log no existe'
}

Write-Host ''
Write-Host '===== NATIVE CRASH LOGS ====='
if ($nativeLogs.Count -gt 0) {
  foreach ($log in $nativeLogs) {
    Write-Host ''
    Write-Host "Archivo: $($log.FullName)"
    Get-Content -LiteralPath $log.FullName -Tail 250
  }
} else {
  Write-Host 'native_crash.log no existe en build\\windows'
}

Write-Host ''
Write-Host '===== NATIVE CRASH DUMPS ====='
if ($nativeDumps.Count -gt 0) {
  $nativeDumps |
    Select-Object FullName, Length, LastWriteTime |
    Format-Table -AutoSize
} else {
  Write-Host 'No hay minidumps native_crash_*.dmp en build\\windows'
}
