#Requires -Version 5.1
param(
    [string]$IncomingDir = "C:\oribis-qa\oribis\__incoming__"
)

$ErrorActionPreference = "Stop"

$launchVbs = Join-Path $IncomingDir "run-oribis-visible.vbs"
$captureVbs = Join-Path $IncomingDir "run-interactive-capture-hidden.vbs"

if (-not (Test-Path $launchVbs)) {
    throw "missing: $launchVbs"
}
if (-not (Test-Path $captureVbs)) {
    throw "missing: $captureVbs"
}

schtasks /Create /TN OribisLaunchVisible /SC ONCE /ST 23:59 /TR "wscript.exe `"$launchVbs`"" /F /IT | Out-Null
schtasks /Create /TN OribisInteractiveCaptureHidden /SC ONCE /ST 23:59 /TR "wscript.exe `"$captureVbs`"" /F /IT | Out-Null

Write-Host "[ok] registered interactive tasks"
Write-Host "  OribisLaunchVisible"
Write-Host "  OribisInteractiveCaptureHidden"

