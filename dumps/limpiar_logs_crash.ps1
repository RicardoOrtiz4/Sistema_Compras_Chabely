$base = Join-Path $env:TEMP 'sistema_compras_chabely\diagnostics'
$appLog = Join-Path $base 'app.log'
$errorLog = Join-Path $base 'errors.log'
$repoRoot = Split-Path $PSScriptRoot -Parent
$buildRoot = Join-Path $repoRoot 'build\windows'
$nativeCrashFiles = @()

if (Test-Path $buildRoot) {
  $nativeCrashFiles = Get-ChildItem -Path $buildRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'native_crash.log' -or $_.Name -like 'native_crash_*.dmp' }
}

Write-Host "Base de logs: $base"
Write-Host "Build de Windows: $buildRoot"

if (Test-Path $appLog) {
  Remove-Item -LiteralPath $appLog -Force
  Write-Host "Eliminado: $appLog"
} else {
  Write-Host "No existe: $appLog"
}

if (Test-Path $errorLog) {
  Remove-Item -LiteralPath $errorLog -Force
  Write-Host "Eliminado: $errorLog"
} else {
  Write-Host "No existe: $errorLog"
}

if ($nativeCrashFiles.Count -gt 0) {
  foreach ($file in $nativeCrashFiles) {
    Remove-Item -LiteralPath $file.FullName -Force
    Write-Host "Eliminado: $($file.FullName)"
  }
} else {
  Write-Host 'No existen native_crash.log o native_crash_*.dmp en build\windows'
}
