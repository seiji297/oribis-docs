#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)]
    [string]$PublicKey
)

$ErrorActionPreference = "Stop"

Write-Host "[1] ensure ssh directory"
$sshDir = "C:\ProgramData\ssh"
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null

Write-Host "[2] ensure host keys"
ssh-keygen -A | Out-Null

Write-Host "[3] ensure sshd_config"
$config = Join-Path $sshDir "sshd_config"
if (-not (Test-Path $config)) {
    $defaultConfig = "C:\Windows\System32\OpenSSH\sshd_config_default"
    if (Test-Path $defaultConfig) {
        Copy-Item $defaultConfig $config -Force
    } else {
        @"
Port 22
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::
PubkeyAuthentication yes
PasswordAuthentication yes
Subsystem sftp sftp-server.exe
Match Group administrators
       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
"@ | Set-Content -Path $config -Encoding ascii
    }
}

Write-Host "[4] write administrators_authorized_keys"
$adminKeys = Join-Path $sshDir "administrators_authorized_keys"
Set-Content -Path $adminKeys -Value $PublicKey -Encoding ascii

Write-Host "[5] set strict ACL"
icacls $adminKeys /inheritance:r | Out-Null
icacls $adminKeys /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null

Write-Host "[6] firewall"
if (-not (Get-NetFirewallRule -Name "sshd" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name sshd -DisplayName "OpenSSH Server sshd" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}

Write-Host "[7] service"
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd

Write-Host "[8] verify"
Get-Service sshd
netstat -ano | findstr ":22"

