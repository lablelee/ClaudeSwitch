# ClaudeSwitch.psm1 - Windows PowerShell module
# Handles profile switching for Claude Code (Personal / Bedrock / Foundry)
# Secrets stored via Windows DPAPI (user+machine encrypted files)

$script:ProfilesPath   = Join-Path $HOME '.claude-profiles.json'
$script:ClaudeHome     = Join-Path $HOME '.claude'
$script:SecretsDir     = Join-Path $HOME '.claude-secrets'

$script:AllClaudeEnvVars = @(
    'ANTHROPIC_API_KEY','ANTHROPIC_BASE_URL',
    'CLAUDE_CODE_USE_BEDROCK','ANTHROPIC_BEDROCK_BASE_URL','CLAUDE_CODE_SKIP_BEDROCK_AUTH',
    'CLAUDE_CODE_USE_FOUNDRY','ANTHROPIC_FOUNDRY_BASE_URL','ANTHROPIC_FOUNDRY_RESOURCE',
    'ANTHROPIC_FOUNDRY_API_KEY','CLAUDE_CODE_SKIP_FOUNDRY_AUTH',
    'AWS_PROFILE','AWS_ACCESS_KEY_ID','AWS_SECRET_ACCESS_KEY','AWS_SESSION_TOKEN',
    'AWS_REGION','AWS_DEFAULT_REGION',
    'CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS','DISABLE_PROMPT_CACHING',
    'ANTHROPIC_DEFAULT_OPUS_MODEL','ANTHROPIC_DEFAULT_SONNET_MODEL',
    'ANTHROPIC_DEFAULT_HAIKU_MODEL','ANTHROPIC_SMALL_FAST_MODEL'
)

# --- Output helpers -----------------------------------------------------------
function Write-Header {
    param([string]$Text, [ConsoleColor]$Color = 'Cyan')
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkGray
    Write-Host "  $Text" -ForegroundColor $Color
    Write-Host ("=" * 60) -ForegroundColor DarkGray
}
function Write-Step { param([string]$T) Write-Host "  >> $T" -ForegroundColor White }
function Write-OK   { param([string]$T) Write-Host "  [OK] $T" -ForegroundColor Green }
function Write-Warn { param([string]$T) Write-Host "  [WARN] $T" -ForegroundColor Yellow }
function Write-Err  { param([string]$T) Write-Host "  [ERR] $T" -ForegroundColor Red }

# --- Secret storage (Windows DPAPI) ------------------------------------------
function Get-SecretPath {
    param([string]$ProfileName, [string]$Key)
    return Join-Path $script:SecretsDir "${ProfileName}-${Key}.enc"
}

function Save-Secret {
    param([string]$ProfileName, [string]$Key, [string]$Value)
    if (-not (Test-Path $script:SecretsDir)) {
        New-Item -ItemType Directory -Path $script:SecretsDir | Out-Null
        # Restrict permissions to current user only
        $acl = Get-Acl $script:SecretsDir
        $acl.SetAccessRuleProtection($true, $false)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $env:USERNAME, 'FullControl', 'Allow')
        $acl.AddAccessRule($rule)
        Set-Acl $script:SecretsDir $acl -ErrorAction SilentlyContinue
    }
    $secure    = ConvertTo-SecureString $Value -AsPlainText -Force
    $encrypted = $secure | ConvertFrom-SecureString
    $path      = Get-SecretPath $ProfileName $Key
    Set-Content $path $encrypted -Encoding UTF8
}

function Read-Secret {
    param([string]$ProfileName, [string]$Key)
    $path = Get-SecretPath $ProfileName $Key
    if (-not (Test-Path $path)) { return $null }
    try {
        $encrypted = Get-Content $path -Raw
        $secure    = $encrypted | ConvertTo-SecureString
        return [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    } catch {
        return $null
    }
}

function Remove-Secret {
    param([string]$ProfileName, [string]$Key)
    $path = Get-SecretPath $ProfileName $Key
    if (Test-Path $path) { Remove-Item $path -Force }
}

function Request-AndSaveSecret {
    param([string]$ProfileName, [string]$Key, [string]$Prompt)
    Write-Host ""
    Write-Host "  $Prompt" -ForegroundColor Cyan
    $secure = Read-Host "  Enter value" -AsSecureString
    $plain  = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    if ([string]::IsNullOrWhiteSpace($plain)) {
        Write-Warn "Empty value - secret not saved."
        return $null
    }
    Save-Secret $ProfileName $Key $plain
    Write-OK "Saved securely (DPAPI encrypted, this machine only)."
    return $plain
}

# --- Profile file -------------------------------------------------------------
function Get-ClaudeProfiles {
    if (-not (Test-Path $script:ProfilesPath)) {
        Write-Warn "No profiles file found at $($script:ProfilesPath)"
        return $null
    }
    try { return Get-Content $script:ProfilesPath -Raw | ConvertFrom-Json }
    catch { Write-Err "Failed to parse profiles JSON: $_"; return $null }
}

function New-ClaudeProfilesFile {
    if (Test-Path $script:ProfilesPath) {
        $ans = Read-Host "  File already exists. Overwrite? (y/N)"
        if ($ans -notmatch '^[Yy]') { Write-Warn "Aborted."; return }
    }
    $template = @'
{
  "_readme": "Config only - no secrets here. Secrets stored in OS credential store.",
  "profiles": {
    "personal": {
      "description": "Claude Max - personal subscription (OAuth login)",
      "backend": "anthropic",
      "env": {}
    },
    "bedrock": {
      "description": "AWS Bedrock - R&D / testing account",
      "backend": "bedrock",
      "awsProfile": "rnd-bedrock",
      "awsRegion": "us-east-1",
      "pinnedModels": {
        "sonnet": "us.anthropic.claude-sonnet-4-6",
        "haiku":  "us.anthropic.claude-haiku-4-5-20251001-v1:0",
        "opus":   "us.anthropic.claude-opus-4-6-v1"
      },
      "env": {
        "CLAUDE_CODE_USE_BEDROCK": "1",
        "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1",
        "DISABLE_PROMPT_CACHING": "1"
      }
    },
    "foundry": {
      "description": "Microsoft Azure Foundry - company deployment",
      "backend": "foundry",
      "foundryResource": "your-foundry-resource-name",
      "pinnedModels": {
        "sonnet": "claude-sonnet-4-6",
        "haiku":  "claude-haiku-4-5",
        "opus":   "claude-opus-4-6"
      },
      "env": {
        "CLAUDE_CODE_USE_FOUNDRY": "1",
        "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1",
        "DISABLE_PROMPT_CACHING": "1"
      }
    }
  }
}
'@
    $template | Set-Content $script:ProfilesPath -Encoding UTF8
    Write-OK "Created $($script:ProfilesPath)"
    Write-Warn "Edit foundryResource and awsProfile values, then re-run."
}

# --- Process management -------------------------------------------------------
function Stop-ClaudeProcesses {
    $killed = 0
    Get-Process -Name "claude" -ErrorAction SilentlyContinue | ForEach-Object {
        $path = $_.Path
        $isDesktopApp = $path -like "*WindowsApps*" -or
                        $path -like "*Program Files*" -or
                        $path -like "*AnthropicClaude*" -or
                        $path -like "*Claude.app*"
        $isCliTool = $path -like "*npm*" -or
                     $path -like "*node_modules*" -or
                     $path -like "*AppData*\npm*" -or
                     [string]::IsNullOrEmpty($path)
        if (-not $isDesktopApp -and $isCliTool) {
            Write-Step "Stopping Claude Code CLI (PID $($_.Id))..."
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            $killed++
        } elseif ($isDesktopApp) {
            Write-Step "Skipping Claude desktop app (PID $($_.Id)) - spared."
        }
    }
    Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -like "*npm*" -or $_.MainWindowTitle -like "*claude*"
    } | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        $killed++
    }
    if ($killed -eq 0) { Write-Step "No Claude Code CLI processes found." }
    else { Write-OK "Stopped $killed process(es)."; Start-Sleep -Milliseconds 500 }
}

# --- Env var management -------------------------------------------------------
function Clear-ClaudeEnvVars {
    $cleared = 0
    foreach ($name in $script:AllClaudeEnvVars) {
        if (Test-Path "env:$name") {
            Remove-Item "env:$name" -ErrorAction SilentlyContinue
            $cleared++
        }
    }
    Write-OK "Cleared $cleared env var(s)."
}

function Apply-ProfileEnvVars {
    param([PSCustomObject]$Profile, [string]$ProfileName)

    # Apply env block from JSON
    foreach ($pair in $Profile.env.PSObject.Properties) {
        [System.Environment]::SetEnvironmentVariable($pair.Name, $pair.Value, 'Process')
        Write-Step "Set $($pair.Name) = $($pair.Value)"
    }

    switch ($Profile.backend) {
        'bedrock' {
            [System.Environment]::SetEnvironmentVariable('CLAUDE_CODE_USE_BEDROCK','1','Process')
            if ($Profile.awsProfile) {
                [System.Environment]::SetEnvironmentVariable('AWS_PROFILE',$Profile.awsProfile,'Process')
                Write-Step "Set AWS_PROFILE = $($Profile.awsProfile)"
            }
            if ($Profile.awsRegion) {
                [System.Environment]::SetEnvironmentVariable('AWS_REGION',$Profile.awsRegion,'Process')
                [System.Environment]::SetEnvironmentVariable('AWS_DEFAULT_REGION',$Profile.awsRegion,'Process')
                Write-Step "Set AWS_REGION = $($Profile.awsRegion)"
            }
            if ($Profile.pinnedModels) {
                if ($Profile.pinnedModels.sonnet) {
                    [System.Environment]::SetEnvironmentVariable('ANTHROPIC_DEFAULT_SONNET_MODEL',$Profile.pinnedModels.sonnet,'Process')
                    Write-Step "Pinned Sonnet = $($Profile.pinnedModels.sonnet)"
                }
                if ($Profile.pinnedModels.haiku) {
                    [System.Environment]::SetEnvironmentVariable('ANTHROPIC_DEFAULT_HAIKU_MODEL',$Profile.pinnedModels.haiku,'Process')
                    Write-Step "Pinned Haiku  = $($Profile.pinnedModels.haiku)"
                }
                if ($Profile.pinnedModels.opus) {
                    [System.Environment]::SetEnvironmentVariable('ANTHROPIC_DEFAULT_OPUS_MODEL',$Profile.pinnedModels.opus,'Process')
                    Write-Step "Pinned Opus   = $($Profile.pinnedModels.opus)"
                }
            }
        }
        'foundry' {
            [System.Environment]::SetEnvironmentVariable('CLAUDE_CODE_USE_FOUNDRY','1','Process')
            if ($Profile.foundryResource -and $Profile.foundryResource -ne 'your-foundry-resource-name') {
                [System.Environment]::SetEnvironmentVariable('ANTHROPIC_FOUNDRY_RESOURCE',$Profile.foundryResource,'Process')
                Write-Step "Set ANTHROPIC_FOUNDRY_RESOURCE = $($Profile.foundryResource)"
            }
            # Load API key from secret store
            $apiKey = Read-Secret $ProfileName 'foundry-key'
            if ($apiKey) {
                [System.Environment]::SetEnvironmentVariable('ANTHROPIC_FOUNDRY_API_KEY',$apiKey,'Process')
                Write-Step "Set ANTHROPIC_FOUNDRY_API_KEY = [from secure store]"
            } else {
                Write-Warn "No Foundry API key in secure store. Will prompt during pre-flight."
            }
            if ($Profile.pinnedModels) {
                if ($Profile.pinnedModels.sonnet) {
                    [System.Environment]::SetEnvironmentVariable('ANTHROPIC_DEFAULT_SONNET_MODEL',$Profile.pinnedModels.sonnet,'Process')
                    Write-Step "Pinned Sonnet = $($Profile.pinnedModels.sonnet)"
                }
                if ($Profile.pinnedModels.haiku) {
                    [System.Environment]::SetEnvironmentVariable('ANTHROPIC_DEFAULT_HAIKU_MODEL',$Profile.pinnedModels.haiku,'Process')
                    Write-Step "Pinned Haiku  = $($Profile.pinnedModels.haiku)"
                }
                if ($Profile.pinnedModels.opus) {
                    [System.Environment]::SetEnvironmentVariable('ANTHROPIC_DEFAULT_OPUS_MODEL',$Profile.pinnedModels.opus,'Process')
                    Write-Step "Pinned Opus   = $($Profile.pinnedModels.opus)"
                }
            }
        }
        default {
            Write-Step "Backend: Anthropic direct (OAuth / Claude Max)"
        }
    }
}

# --- Pre-flight checks --------------------------------------------------------
function Test-Prerequisites {
    $ok = $true
    # Claude Code is the whole point - must be installed
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Err "Claude Code CLI not found."
        Write-Err "This tool manages Claude Code profiles. Install it first:"
        Write-Err "  npm install -g @anthropic-ai/claude-code"
        $ok = $false
    }
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Err "Node.js not found. Install from: https://nodejs.org"
        $ok = $false
    }
    return $ok
}

function Test-ProfileReadiness {
    param([PSCustomObject]$Profile, [string]$ProfileName)
    $ok = $true
    switch ($Profile.backend) {
        'bedrock' {
            if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
                Write-Err "AWS CLI not found. Install: https://aws.amazon.com/cli/"
                $ok = $false
            } else {
                $profiles = aws configure list-profiles 2>&1
                if ($profiles -notcontains $Profile.awsProfile) {
                    Write-Warn "AWS profile '$($Profile.awsProfile)' not found."
                    Write-Warn "Run: aws configure sso --profile $($Profile.awsProfile)"
                    $ok = $false
                } else {
                    Write-OK "AWS profile '$($Profile.awsProfile)' found."
                    $identity = aws sts get-caller-identity --profile $Profile.awsProfile 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warn "AWS session expired. Launching SSO login..."
                        aws sso login --profile $Profile.awsProfile
                        if ($LASTEXITCODE -ne 0) {
                            Write-Err "SSO login failed or was cancelled."
                            $ok = $false
                        } else {
                            Write-OK "SSO login successful."
                        }
                    } else {
                        Write-OK "AWS credentials valid."
                    }
                }
            }
        }
        'foundry' {
            if ($Profile.foundryResource -eq 'your-foundry-resource-name' -or
                [string]::IsNullOrEmpty($Profile.foundryResource)) {
                Write-Err "foundryResource not set. Edit $($script:ProfilesPath)"
                $ok = $false
            } else {
                Write-OK "Foundry resource: $($Profile.foundryResource)"
            }
            # Check for API key in secret store
            $apiKey = Read-Secret $ProfileName 'foundry-key'
            if (-not $apiKey) {
                $apiKey = Request-AndSaveSecret $ProfileName 'foundry-key' `
                    "Foundry API key not found. Enter your API key for profile '$ProfileName':"
                if (-not $apiKey) { $ok = $false }
            } else {
                Write-OK "Foundry API key found in secure store."
            }
        }
        default {
            $tokenFile = Join-Path $script:ClaudeHome '.credentials.json'
            if (-not (Test-Path $tokenFile)) {
                Write-Warn "No Claude credentials found. Run: claude login"
            } else {
                Write-OK "Claude credentials found."
            }
        }
    }
    return $ok
}

# --- Interactive menu ---------------------------------------------------------
function Show-Menu {
    param([array]$ProfileNames, [hashtable]$Profiles)
    Write-Header "Claude Code - Profile Switcher"
    Write-Host ""
    $i = 1
    $ProfileNames | ForEach-Object {
        $p       = $Profiles[$_]
        $backend = $p.backend.ToUpper()
        Write-Host "  [$i] " -NoNewline -ForegroundColor Cyan
        Write-Host "$_".PadRight(12) -NoNewline -ForegroundColor White
        Write-Host "($backend)".PadRight(12) -NoNewline -ForegroundColor DarkYellow
        Write-Host "$($p.description)" -ForegroundColor DarkGray
        $i++
    }
    Write-Host ""
    Write-Host "  [S] Status   [D] Diagnostics   [K] Manage secrets   [Q] Quit" -ForegroundColor DarkGray
    Write-Host ""
    return (Read-Host "  Choose")
}

# --- Main switch function -----------------------------------------------------
function Switch-ClaudeProfile {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)] [string]$ProfileName,
        [switch]$Force
    )

    # Check claude is installed before doing anything
    if (-not (Test-Prerequisites)) { return }

    $config = Get-ClaudeProfiles
    if (-not $config) { return }

    $profileNames = $config.profiles.PSObject.Properties.Name
    $profileMap   = @{}
    $profileNames | ForEach-Object { $profileMap[$_] = $config.profiles.$_ }

    if (-not $ProfileName) {
        $choice = Show-Menu -ProfileNames $profileNames -Profiles $profileMap
        switch ($choice.ToUpper().Trim()) {
            'Q' { Write-Host "  Bye!" -ForegroundColor DarkGray; return }
            'S' { Show-ClaudeProfile; return }
            'D' { Test-ClaudeSetup; return }
            'K' { Manage-Secrets -ProfileNames $profileNames; return }
            default {
                if ($choice -match '^\d+$') {
                    $idx = [int]$choice - 1
                    if ($idx -lt 0 -or $idx -ge $profileNames.Count) {
                        Write-Err "Invalid choice."; return
                    }
                    $ProfileName = $profileNames[$idx]
                } else {
                    $ProfileName = $choice.Trim()
                }
            }
        }
    }

    if ($profileNames -notcontains $ProfileName) {
        Write-Err "Profile '$ProfileName' not found. Available: $($profileNames -join ', ')"
        return
    }

    $prof = $profileMap[$ProfileName]
    Write-Header "Switching to: $ProfileName" Yellow
    Write-Host "  $($prof.description)" -ForegroundColor DarkGray
    Write-Host ""

    Write-Step "[1/4] Pre-flight checks..."
    $ready = Test-ProfileReadiness -Profile $prof -ProfileName $ProfileName
    if (-not $ready -and -not $Force) {
        Write-Host ""
        Write-Err "Pre-flight failed. Fix issues above or use -Force to skip."
        return
    }

    Write-Step "[2/4] Stopping Claude Code processes..."
    Stop-ClaudeProcesses

    Write-Step "[3/4] Clearing all profile env vars..."
    Clear-ClaudeEnvVars

    Write-Step "[4/4] Applying profile '$ProfileName'..."
    Apply-ProfileEnvVars -Profile $prof -ProfileName $ProfileName
    Set-StatusLineForProfile -Backend $prof.backend

    Write-Header "Active Profile: $ProfileName" Green
    Show-ClaudeProfile

    Write-Host ""
    Write-Step "Waiting 2 seconds before launch..."
    Start-Sleep -Seconds 2
    Write-Step "Launching Claude Code..."
    Write-Host ""
    & claude
}

# --- Secret management UI -----------------------------------------------------
function Manage-Secrets {
    param([array]$ProfileNames)
    Write-Header "Manage Secrets"
    Write-Host ""
    Write-Host "  Secrets are encrypted with Windows DPAPI (your user account only)." -ForegroundColor DarkGray
    Write-Host "  They cannot be read by other users or on other machines." -ForegroundColor DarkGray
    Write-Host ""
    $ProfileNames | ForEach-Object {
        $pname = $_
        $foundryKey = Read-Secret $pname 'foundry-key'
        $awsAccess  = Read-Secret $pname 'aws-access-key'
        $status = if ($foundryKey) { "[foundry-key: stored]" } else { "[foundry-key: not set]" }
        Write-Host "  $pname - $status" -ForegroundColor Cyan
    }
    Write-Host ""
    $pname = Read-Host "  Enter profile name to update its secret (or Enter to cancel)"
    if ([string]::IsNullOrWhiteSpace($pname)) { return }
    Write-Host "  [1] Set Foundry API key" -ForegroundColor Cyan
    Write-Host "  [2] Clear Foundry API key" -ForegroundColor Cyan
    Write-Host "  [3] Cancel" -ForegroundColor DarkGray
    $choice = Read-Host "  Choose"
    switch ($choice) {
        '1' { Request-AndSaveSecret $pname 'foundry-key' "Enter Foundry API key for '$pname':" }
        '2' { Remove-Secret $pname 'foundry-key'; Write-OK "Cleared foundry-key for '$pname'." }
    }
}

# --- Status display -----------------------------------------------------------
function Show-ClaudeProfile {
    $active = @{}
    foreach ($name in $script:AllClaudeEnvVars) {
        $val = [System.Environment]::GetEnvironmentVariable($name, 'Process')
        if ($val) { $active[$name] = $val }
    }
    if ($active.Count -eq 0) {
        Write-Host "  No profile env vars active (Claude Max / OAuth)" -ForegroundColor DarkGray
        return
    }
    $active.GetEnumerator() | Sort-Object Name | ForEach-Object {
        $display = if ($_.Name -like '*KEY*' -or $_.Name -like '*SECRET*') { '[hidden]' } else { $_.Value }
        Write-Host "  $($_.Name.PadRight(42)) = $display" -ForegroundColor DarkCyan
    }
}

# --- Diagnostics -------------------------------------------------------------
function Test-ClaudeSetup {
    Write-Header "Claude Code - Setup Diagnostics"

    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if ($claude) { Write-OK "claude CLI: $($claude.Source)" }
    else { Write-Err "claude CLI not found. Run: npm install -g @anthropic-ai/claude-code" }

    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) { Write-OK "node: $(node --version)" }
    else { Write-Err "node not found. Install: https://nodejs.org" }

    $aws = Get-Command aws -ErrorAction SilentlyContinue
    if ($aws) { Write-OK "aws CLI: $(aws --version 2>&1)" }
    else { Write-Warn "aws CLI not found (needed for Bedrock only)" }

    if (Test-Path $script:ProfilesPath) { Write-OK "Profiles: $($script:ProfilesPath)" }
    else { Write-Warn "No profiles file. Run: New-ClaudeProfilesFile" }

    if (Test-Path $script:SecretsDir) { Write-OK "Secrets dir: $($script:SecretsDir)" }
    else { Write-Warn "No secrets stored yet (will prompt on first use)" }

    $ps1Dest = Join-Path $script:ClaudeHome 'statusline-command.ps1'
    if (Test-Path $ps1Dest) { Write-OK "Statusline installed: $ps1Dest" }
    else { Write-Warn "Statusline not installed. Run: Install-StatusLine" }

    Write-Host ""
    Write-Step "Active env vars:"
    Show-ClaudeProfile
}

# --- Statusline installer -----------------------------------------------------
function Install-StatusLine {
    $claudeDir    = Join-Path $HOME '.claude'
    $actualDir    = $PSScriptRoot
    $jsonDest     = Join-Path $claudeDir 'settings.json'
    $personalFile = Join-Path $claudeDir 'personal-statusline.txt'
    $ourCmd       = "powershell -NoProfile -File ~/.claude/statusline-command.ps1"

    if (-not (Test-Path $claudeDir)) {
        New-Item -ItemType Directory -Path $claudeDir | Out-Null
    }

    # Copy our PS1 statusline script
    $src  = Join-Path $actualDir 'statusline-command.ps1'
    $dest = Join-Path $claudeDir 'statusline-command.ps1'
    if (-not (Test-Path $src)) {
        Write-Warn "statusline-command.ps1 not found - skipping statusline install."
        return
    }
    Copy-Item $src $dest -Force
    Write-OK "Installed statusline-command.ps1 -> $dest"

    # Check for existing statusline
    $existingCmd = ""
    $existingSettings = $null
    if (Test-Path $jsonDest) {
        try {
            $existingSettings = Get-Content $jsonDest -Raw | ConvertFrom-Json
            $existingCmd = $existingSettings.statusLine.command
        } catch {}
    }

    $hasExisting = $existingCmd -and $existingCmd -notlike "*statusline-command*"

    if ($hasExisting) {
        Write-Host ""
        Write-Host "  You already have a statusline configured:" -ForegroundColor Cyan
        Write-Host "  $existingCmd" -ForegroundColor White
        Write-Host ""
        Write-Host "  [1] Keep yours on Personal, use ours on Bedrock/Foundry (recommended)" -ForegroundColor Cyan
        Write-Host "  [2] Replace with ours on all profiles" -ForegroundColor Cyan
        Write-Host "  [3] Skip statusline setup" -ForegroundColor DarkGray
        Write-Host ""
        $choice = Read-Host "  Choose (1/2/3)"

        switch ($choice.Trim()) {
            "3" { Write-Warn "Skipping statusline setup."; return }
            "2" {
                # Replace on all profiles - just install ours globally
                Write-Step "Installing our statusline for all profiles..."
            }
            default {
                # Option 1 (default) - save theirs for Personal, ours for API profiles
                Set-Content $personalFile $existingCmd -Encoding UTF8
                Write-OK "Saved your original statusline to: $personalFile"
                Write-OK "It will be used on Personal profile automatically."
            }
        }
    }

    # Write/merge settings.json
    if ($null -ne $existingSettings) {
        $existingSettings | Add-Member -Force -NotePropertyName 'statusLine' `
            -NotePropertyValue ([PSCustomObject]@{ type = "command"; command = $ourCmd })
        $existingAllow = @()
        if ($existingSettings.permissions -and $existingSettings.permissions.allow) {
            $existingAllow = @($existingSettings.permissions.allow)
        }
        $existingDeny = @()
        if ($existingSettings.permissions -and $existingSettings.permissions.deny) {
            $existingDeny = @($existingSettings.permissions.deny)
        }
        $mergedAllow = @($existingAllow + $ourCmd) | Select-Object -Unique
        $existingSettings | Add-Member -Force -NotePropertyName 'permissions' `
            -NotePropertyValue ([PSCustomObject]@{ allow = $mergedAllow; deny = $existingDeny })
        $existingSettings | ConvertTo-Json -Depth 10 | Set-Content $jsonDest -Encoding UTF8
        Write-OK "Merged into existing settings.json (all other settings preserved)"
    } else {
        [PSCustomObject]@{
            statusLine  = [PSCustomObject]@{ type = "command"; command = $ourCmd }
            permissions = [PSCustomObject]@{ allow = @($ourCmd) }
        } | ConvertTo-Json -Depth 10 | Set-Content $jsonDest -Encoding UTF8
        Write-OK "Created settings.json -> $jsonDest"
    }

    Write-OK "Statusline installed. Restart Claude Code to activate."
}

function Set-StatusLineForProfile {
    # Called by Switch-ClaudeProfile to swap statusline based on profile
    param([string]$Backend)
    $claudeDir    = Join-Path $HOME '.claude'
    $jsonDest     = Join-Path $claudeDir 'settings.json'
    $personalFile = Join-Path $claudeDir 'personal-statusline.txt'
    $ourCmd       = "powershell -NoProfile -File ~/.claude/statusline-command.ps1"

    if (-not (Test-Path $jsonDest)) { return }

    try {
        $settings = Get-Content $jsonDest -Raw | ConvertFrom-Json
    } catch { return }

    if ($Backend -eq 'anthropic') {
        # Switching to Personal - restore original if saved
        if (Test-Path $personalFile) {
            $personalCmd = (Get-Content $personalFile -Raw).Trim()
            if ($personalCmd) {
                $settings | Add-Member -Force -NotePropertyName 'statusLine' `
                    -NotePropertyValue ([PSCustomObject]@{ type = "command"; command = $personalCmd })
                $settings | ConvertTo-Json -Depth 10 | Set-Content $jsonDest -Encoding UTF8
                Write-Step "Restored your personal statusline."
                return
            }
        }
        # No saved personal statusline - keep ours (user chose option 2 or had none)
    } else {
        # Switching to Bedrock/Foundry - use ours
        $settings | Add-Member -Force -NotePropertyName 'statusLine' `
            -NotePropertyValue ([PSCustomObject]@{ type = "command"; command = $ourCmd })
        $settings | ConvertTo-Json -Depth 10 | Set-Content $jsonDest -Encoding UTF8
        Write-Step "Activated ClaudeSwitch statusline for $Backend."
    }
}

Export-ModuleMember -Function @(
    'Switch-ClaudeProfile','Show-ClaudeProfile','Test-ClaudeSetup',
    'New-ClaudeProfilesFile','Stop-ClaudeProcesses','Install-StatusLine',
    'Manage-Secrets','Save-Secret','Read-Secret','Remove-Secret',
    'Set-StatusLineForProfile'
)
