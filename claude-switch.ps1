# claude-switch.ps1 - Windows entry point for ClaudeSwitch
param(
    [Parameter(Position=0)] [string]$Profile,
    [switch]$Force,
    [switch]$Setup,
    [switch]$Status,
    [switch]$Secrets
)

# Fix execution policy for current user if needed (non-admin safe)
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -eq 'Restricted' -or $policy -eq 'Undefined') {
    Write-Host "  Fixing PowerShell execution policy for current user..." -ForegroundColor Yellow
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Write-Host "  Done." -ForegroundColor Green
}

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModulePath = Join-Path $ScriptDir 'ClaudeSwitch.psm1'

if (-not (Test-Path $ModulePath)) {
    Write-Host "ERROR: ClaudeSwitch.psm1 not found next to this script." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Import-Module $ModulePath -Force

# First run: create profiles file
$ProfilesPath = Join-Path $HOME '.claude-profiles.json'
if (-not (Test-Path $ProfilesPath)) {
    Write-Host ""
    Write-Host "  First run - creating profiles config..." -ForegroundColor Yellow
    New-ClaudeProfilesFile
    Write-Host ""
    Write-Host "  Edit $ProfilesPath then re-run." -ForegroundColor Cyan
    Write-Host "  Opening file now..." -ForegroundColor DarkGray
    Start-Process code $ProfilesPath -ErrorAction SilentlyContinue
    if (-not $?) { Start-Process notepad $ProfilesPath }
    exit 0
}

# Auto-install statusline if not yet installed
$statusDest = Join-Path $HOME '.claude\statusline-command.ps1'
if (-not (Test-Path $statusDest)) {
    Write-Host "  Installing statusline for Claude Code..." -ForegroundColor DarkGray
    Install-StatusLine
}

if ($Setup)   { Test-ClaudeSetup;  exit 0 }
if ($Status)  { Show-ClaudeProfile; exit 0 }
if ($Secrets) { 
    $config = Get-ClaudeProfiles
    if ($config) {
        Manage-Secrets -ProfileNames $config.profiles.PSObject.Properties.Name
    }
    exit 0
}

$switchParams = @{}
if ($Force) { $switchParams['Force'] = $true }

if ($Profile) {
    Switch-ClaudeProfile -ProfileName $Profile @switchParams
} else {
    Switch-ClaudeProfile @switchParams
}
