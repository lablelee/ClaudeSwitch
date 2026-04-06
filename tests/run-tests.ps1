# ClaudeSwitch test suite - PowerShell version
# Run: powershell -File tests/run-tests.ps1

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $ScriptDir
$MockDir   = Join-Path $ScriptDir "mock-data"
$Statusline = Join-Path $RootDir "statusline-command.ps1"

$e  = [char]27
$GR = "$e[0;32m"; $RD = "$e[0;31m"; $YL = "$e[0;33m"
$CY = "$e[0;36m"; $DM = "$e[0;90m"; $RS = "$e[0m"

$script:Pass = 0; $script:Fail = 0; $script:Skip = 0

function Test-Pass  { param([string]$T) $script:Pass++; Write-Host "  ${GR}PASS${RS} $T" }
function Test-Fail  { param([string]$T, [string]$D) $script:Fail++; Write-Host "  ${RD}FAIL${RS} $T"; if ($D) { Write-Host "       ${DM}$D${RS}" } }
function Test-Skip  { param([string]$T) $script:Skip++; Write-Host "  ${YL}SKIP${RS} $T" }
function Test-Section { param([string]$T) Write-Host ""; Write-Host "${CY}=== $T ===${RS}" }

function Invoke-Statusline {
    param([string]$JsonFile, [hashtable]$EnvOverrides = @{})
    $savedEnv = @{}
    foreach ($key in @('CLAUDE_CODE_USE_BEDROCK','CLAUDE_CODE_USE_FOUNDRY','AWS_PROFILE','ANTHROPIC_FOUNDRY_RESOURCE')) {
        $savedEnv[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $null, 'Process')
    }
    foreach ($kv in $EnvOverrides.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, 'Process')
    }
    $output = ""
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $json = Get-Content $JsonFile -Raw -Encoding UTF8
        $output = $json | powershell -NoProfile -Command "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; `$input | & '$Statusline'" 2>&1 | Out-String
    } catch { $output = "ERROR: $_" }
    foreach ($kv in $savedEnv.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, 'Process')
    }
    return $output
}

Write-Host ""
Write-Host "${CY}ClaudeSwitch Test Suite (PowerShell)${RS}"
$osInfo = if ($PSVersionTable.OS) { $PSVersionTable.OS } else { $env:OS }
Write-Host "${DM}PS Version: $($PSVersionTable.PSVersion) | OS: $osInfo${RS}"

# =============================================================================
Test-Section "Prerequisites"
# =============================================================================
if (Test-Path $Statusline) { Test-Pass "statusline-command.ps1 exists" } else { Test-Fail "statusline-command.ps1 not found" }
$ModulePath = Join-Path $RootDir "ClaudeSwitch.psm1"
if (Test-Path $ModulePath) { Test-Pass "ClaudeSwitch.psm1 exists" } else { Test-Fail "ClaudeSwitch.psm1 not found" }
if ($PSVersionTable.PSVersion.Major -ge 5) { Test-Pass "PowerShell $($PSVersionTable.PSVersion)" } else { Test-Fail "PS too old" }

# =============================================================================
Test-Section "Personal - Normal (42.5%)"
# =============================================================================
$output = Invoke-Statusline (Join-Path $MockDir "personal.json")

if ($output -match "PERSONAL") { Test-Pass "Badge: PERSONAL" } else { Test-Fail "Missing badge" $output }
if ($output -match "Opus 4\.6") { Test-Pass "Model: Opus 4.6" } else { Test-Fail "Missing model" $output }
if ($output -match "\(1M\)") { Test-Pass "Context size: (1M)" } else { Test-Fail "Missing (1M)" $output }
if ($output -match "1\.0\.34") { Test-Pass "Version shown" } else { Test-Fail "Missing version" $output }
if ($output.Contains([char]0x250A)) { Test-Pass "Column separator" } else { Test-Fail "Missing separator" $output }
if ($output.Contains([char]0x2586)) { Test-Pass "Progress bar chars" } else { Test-Fail "Missing bar" $output }
if ($output -match "42\.5%") { Test-Pass "Context 42.5%" } else { Test-Fail "Missing %" $output }
if ($output -match "5h") { Test-Pass "5h rate limit" } else { Test-Fail "Missing 5h" $output }
if ($output -match "7d") { Test-Pass "7d rate limit" } else { Test-Fail "Missing 7d" $output }
if ($output -match "context") { Test-Pass "Context label" } else { Test-Fail "Missing context" $output }
if ($output -match "session") { Test-Pass "Session label" } else { Test-Fail "Missing session" $output }
if ($output -match "\+142") { Test-Pass "Lines +142" } else { Test-Fail "Missing +lines" $output }
if ($output -match "\-38") { Test-Pass "Lines -38" } else { Test-Fail "Missing -lines" $output }
if ($output.Contains([char]0x2193)) { Test-Pass "Input arrow" } else { Test-Fail "Missing input arrow" $output }
if ($output.Contains([char]0x2191)) { Test-Pass "Output arrow" } else { Test-Fail "Missing output arrow" $output }
if ($output -match "200k") { Test-Pass "Input tokens" } else { Test-Fail "Missing input tokens" $output }
if ($output -match "30k") { Test-Pass "Output tokens" } else { Test-Fail "Missing output tokens" $output }
if ($output -match "compact") { Test-Fail "Should not show /compact at 42.5%" } else { Test-Pass "No compact (correct)" }

# =============================================================================
Test-Section "Personal - High Context (85.3%)"
# =============================================================================
$output = Invoke-Statusline (Join-Path $MockDir "high-context.json")

if ($output -match "85\.3%") { Test-Pass "Context 85.3%" } else { Test-Fail "Missing 85.3%" $output }
if ($output -match "compact now") { Test-Pass "Compact warning" } else { Test-Fail "Missing /compact now" $output }
if ($output.Contains([char]0x25B8)) { Test-Pass "Warning indicator" } else { Test-Fail "Missing indicator" $output }
if ($output -match "92%") { Test-Pass "5h rate 92%" } else { Test-Fail "Missing 92%" $output }
if ($output -match "75%") { Test-Pass "7d rate 75%" } else { Test-Fail "Missing 75%" $output }
if ($output -match "\+500") { Test-Pass "Lines +500" } else { Test-Fail "Missing +500" $output }
if ($output -match "session") { Test-Pass "Session present" } else { Test-Fail "Missing session" $output }

# =============================================================================
Test-Section "Bedrock (API, no rate limits)"
# =============================================================================
$output = Invoke-Statusline (Join-Path $MockDir "bedrock.json") @{ CLAUDE_CODE_USE_BEDROCK="1"; AWS_PROFILE="rnd-bedrock" }

if ($output -match "BEDROCK") { Test-Pass "Badge: BEDROCK" } else { Test-Fail "Missing badge" $output }
if ($output -match "Sonnet 4\.6") { Test-Pass "Model: Sonnet 4.6" } else { Test-Fail "Missing model" $output }
if ($output -match "\(200k\)") { Test-Pass "Context: (200k)" } else { Test-Fail "Missing (200k)" $output }
if ($output -match "(?<!\d)5h") { Test-Fail "Should not show 5h" } else { Test-Pass "No 5h (correct)" }
if ($output -match "cost") { Test-Pass "Cost shown" } else { Test-Fail "Missing cost" $output }
if ($output -match "1\.23") { Test-Pass "Cost \$1.23" } else { Test-Fail "Missing cost value" $output }
if ($output -match "78\.2%") { Test-Pass "Context 78.2%" } else { Test-Fail "Missing 78.2%" $output }
if ($output -match "compact soon") { Test-Pass "Compact warning (78%)" } else { Test-Fail "Missing /compact soon" $output }
if ($output -match "session") { Test-Pass "Session shown" } else { Test-Fail "Missing session" $output }
if ($output -match "\+310") { Test-Pass "Lines +310" } else { Test-Fail "Missing +310" $output }
if ($output.Contains([char]0x250A)) { Test-Pass "Column separator aligned" } else { Test-Fail "Missing separator" $output }
if ($output -match "debug|placeholder") { Test-Fail "Debug placeholder" } else { Test-Pass "No debug placeholder" }

# =============================================================================
Test-Section "Foundry (API, low context)"
# =============================================================================
$output = Invoke-Statusline (Join-Path $MockDir "foundry.json") @{ CLAUDE_CODE_USE_FOUNDRY="1"; ANTHROPIC_FOUNDRY_RESOURCE="my-foundry" }

if ($output -match "FOUNDRY") { Test-Pass "Badge: FOUNDRY" } else { Test-Fail "Missing badge" $output }
if ($output -match "Sonnet 4\.6") { Test-Pass "Model: Sonnet 4.6" } else { Test-Fail "Missing model" $output }
if ($output -match "(?<!\d)5h") { Test-Fail "Should not show 5h" } else { Test-Pass "No 5h (correct)" }
if ($output -match "cost") { Test-Pass "Cost shown" } else { Test-Fail "Missing cost" $output }
if ($output -match "0\.45") { Test-Pass "Cost \$0.45" } else { Test-Fail "Missing cost value" $output }
if ($output -match "15\.0%") { Test-Pass "Context 15.0%" } else { Test-Fail "Missing 15.0%" $output }
if ($output -match "compact") { Test-Fail "Should not show /compact at 15%" } else { Test-Pass "No compact (correct)" }
if ($output -match "session") { Test-Pass "Session shown" } else { Test-Fail "Missing session" $output }
if ($output -match "debug") { Test-Fail "Debug placeholder" } else { Test-Pass "No debug placeholder" }

# =============================================================================
Test-Section "Startup (no interaction - lines 2,3 hidden)"
# =============================================================================
$output = Invoke-Statusline (Join-Path $MockDir "startup.json")
$lines = ($output.Trim() -split "`n" | Where-Object { $_.Trim() -ne "" })

if ($output -match "PERSONAL") { Test-Pass "Badge: PERSONAL" } else { Test-Fail "Missing badge" $output }
if ($output -match "Opus 4\.6") { Test-Pass "Model: Opus 4.6" } else { Test-Fail "Missing model" $output }
if ($output -match "1\.0\.34") { Test-Pass "Version shown" } else { Test-Fail "Missing version" $output }
if ($lines.Count -eq 1) { Test-Pass "Only 1 line on startup (lines 2,3 hidden)" } else { Test-Fail "Expected 1 line, got $($lines.Count)" $output }
if ($output -match "context") { Test-Fail "Line 2 should be hidden" } else { Test-Pass "No context bar (correct)" }
if ($output -match "session") { Test-Fail "Line 3 should be hidden" } else { Test-Pass "No session line (correct)" }
if ($output -match "(?<!\d)5h") { Test-Fail "Line 2 should be hidden" } else { Test-Pass "No 5h rate (correct)" }
if ($output -match "(?<!\d)7d") { Test-Fail "Line 3 should be hidden" } else { Test-Pass "No 7d rate (correct)" }
if ($output.Contains([char]0x2193)) { Test-Fail "Line 3 should be hidden" } else { Test-Pass "No token arrows (correct)" }
if ($output.Contains([char]0x250A)) { Test-Pass "Column separator on line 1" } else { Test-Fail "Missing separator" $output }

# =============================================================================
Test-Section "Minimal JSON"
# =============================================================================
$output = Invoke-Statusline (Join-Path $MockDir "minimal.json")
$lines = ($output.Trim() -split "`n" | Where-Object { $_.Trim() -ne "" })

if ($output -match "Haiku 4\.5") { Test-Pass "Model: Haiku 4.5" } else { Test-Fail "Missing model" $output }
if ($output -match "PERSONAL") { Test-Pass "Default badge" } else { Test-Fail "Missing badge" $output }
if ($output -match "ERROR") { Test-Fail "Error on minimal" $output } else { Test-Pass "No error" }
if ($lines.Count -eq 3) { Test-Pass "3 lines (has tokens)" } else { Test-Fail "Expected 3, got $($lines.Count)" $output }

# =============================================================================
Test-Section "Line count validation"
# =============================================================================
# Personal: has tokens → 3 lines
$out = Invoke-Statusline (Join-Path $MockDir "personal.json")
$lc = ($out.Trim() -split "`n" | Where-Object { $_.Trim() -ne "" }).Count
if ($lc -eq 3) { Test-Pass "Personal: 3 lines" } else { Test-Fail "Personal: expected 3, got $lc" $out }

# High context: has tokens → 3 lines
$out = Invoke-Statusline (Join-Path $MockDir "high-context.json")
$lc = ($out.Trim() -split "`n" | Where-Object { $_.Trim() -ne "" }).Count
if ($lc -eq 3) { Test-Pass "High context: 3 lines" } else { Test-Fail "High context: expected 3, got $lc" $out }

# Bedrock: has tokens → 3 lines
$out = Invoke-Statusline (Join-Path $MockDir "bedrock.json") @{ CLAUDE_CODE_USE_BEDROCK="1" }
$lc = ($out.Trim() -split "`n" | Where-Object { $_.Trim() -ne "" }).Count
if ($lc -eq 3) { Test-Pass "Bedrock: 3 lines" } else { Test-Fail "Bedrock: expected 3, got $lc" $out }

# Foundry: has tokens → 3 lines
$out = Invoke-Statusline (Join-Path $MockDir "foundry.json") @{ CLAUDE_CODE_USE_FOUNDRY="1" }
$lc = ($out.Trim() -split "`n" | Where-Object { $_.Trim() -ne "" }).Count
if ($lc -eq 3) { Test-Pass "Foundry: 3 lines" } else { Test-Fail "Foundry: expected 3, got $lc" $out }

# Startup: no tokens → 1 line
$out = Invoke-Statusline (Join-Path $MockDir "startup.json")
$lc = ($out.Trim() -split "`n" | Where-Object { $_.Trim() -ne "" }).Count
if ($lc -eq 1) { Test-Pass "Startup: 1 line" } else { Test-Fail "Startup: expected 1, got $lc" $out }

# =============================================================================
Test-Section "Column separator between all 3 columns"
# =============================================================================
$output = Invoke-Statusline (Join-Path $MockDir "personal.json")
$sepChar = [char]0x250A
$lineNum = 0
$allOk = $true
foreach ($line in ($output.Trim() -split "`n" | Where-Object { $_.Trim() -ne "" })) {
    $lineNum++
    $sepCount = ($line.ToCharArray() | Where-Object { $_ -eq $sepChar }).Count
    if ($sepCount -eq 2) { Test-Pass "Line ${lineNum}: 2 separators" } else { Test-Fail "Line ${lineNum}: expected 2, got $sepCount"; $allOk = $false }
}
if ($allOk) { Test-Pass "All lines have 3-column layout" }

# Startup line should also have 2 separators
$out = Invoke-Statusline (Join-Path $MockDir "startup.json")
$sepCount = ($out.ToCharArray() | Where-Object { $_ -eq $sepChar }).Count
if ($sepCount -eq 2) { Test-Pass "Startup line: 2 separators" } else { Test-Fail "Startup: expected 2, got $sepCount" }

# =============================================================================
Test-Section "Dynamic col2 width (wider with /compact)"
# =============================================================================
function Get-VisibleLength($str) {
    ($str -replace "$([char]27)\[[0-9;]*m",'').Length
}

$outNormal  = Invoke-Statusline (Join-Path $MockDir "personal.json")
$outHigh    = Invoke-Statusline (Join-Path $MockDir "high-context.json")
$outBedrock = Invoke-Statusline (Join-Path $MockDir "bedrock.json") @{ CLAUDE_CODE_USE_BEDROCK="1" }
$outFoundry = Invoke-Statusline (Join-Path $MockDir "foundry.json") @{ CLAUDE_CODE_USE_FOUNDRY="1" }

$lenNormal  = Get-VisibleLength ($outNormal.Trim() -split "`n")[0]
$lenHigh    = Get-VisibleLength ($outHigh.Trim() -split "`n")[0]
$lenBedrock = Get-VisibleLength ($outBedrock.Trim() -split "`n")[0]
$lenFoundry = Get-VisibleLength ($outFoundry.Trim() -split "`n")[0]

if ($lenHigh -gt $lenNormal) { Test-Pass "High context: wider ($lenHigh > $lenNormal)" } else { Test-Fail "High not wider: $lenHigh vs $lenNormal" }
if ($lenBedrock -gt $lenNormal) { Test-Pass "Bedrock (78%): wider ($lenBedrock > $lenNormal)" } else { Test-Fail "Bedrock not wider: $lenBedrock vs $lenNormal" }
if ($lenFoundry -eq $lenNormal) { Test-Pass "Foundry (15%): default width ($lenFoundry)" } else { Test-Fail "Foundry unexpected: $lenFoundry vs $lenNormal" }
if ($outHigh -match "compact now") { Test-Pass "High: compact now" } else { Test-Fail "Missing compact now" }
if ($outBedrock -match "compact soon") { Test-Pass "Bedrock: compact soon" } else { Test-Fail "Missing compact soon" }

# =============================================================================
Test-Section "Module import"
# =============================================================================
try {
    Import-Module (Join-Path $RootDir "ClaudeSwitch.psm1") -Force -ErrorAction Stop
    Test-Pass "Module imports"
    $exported = Get-Command -Module ClaudeSwitch -ErrorAction Stop
    foreach ($fn in @('Switch-ClaudeProfile','Show-ClaudeProfile','Test-ClaudeSetup','Install-StatusLine','Manage-Secrets')) {
        if ($exported.Name -contains $fn) { Test-Pass "Exports: $fn" } else { Test-Fail "Missing: $fn" }
    }
    Remove-Module ClaudeSwitch -ErrorAction SilentlyContinue
} catch { Test-Fail "Module import failed" "$_" }

# =============================================================================
Test-Section "Profile JSON parsing"
# =============================================================================
$testConfig = '{ "profiles": {
    "personal": { "backend": "anthropic", "env": {} },
    "bedrock":  { "backend": "bedrock", "pinnedModels": { "sonnet": "us.anthropic.claude-sonnet-4-6" }, "env": { "CLAUDE_CODE_USE_BEDROCK": "1" } },
    "foundry":  { "backend": "foundry", "env": { "CLAUDE_CODE_USE_FOUNDRY": "1" } }
}}'
try {
    $config = $testConfig | ConvertFrom-Json
    $names = $config.profiles.PSObject.Properties.Name
    if ($names.Count -eq 3) { Test-Pass "Parses 3 profiles" } else { Test-Fail "Expected 3, got $($names.Count)" }
    if ($config.profiles.bedrock.backend -eq "bedrock") { Test-Pass "Backend field" } else { Test-Fail "Wrong backend" }
    if ($config.profiles.bedrock.pinnedModels.sonnet -eq "us.anthropic.claude-sonnet-4-6") { Test-Pass "Pinned model" } else { Test-Fail "Wrong model" }
    if ($config.profiles.bedrock.env.CLAUDE_CODE_USE_BEDROCK -eq "1") { Test-Pass "Env vars" } else { Test-Fail "Wrong env" }
} catch { Test-Fail "JSON parse failed" "$_" }

# =============================================================================
Write-Host ""
Write-Host "${CY}============================================================${RS}"
$Total = $script:Pass + $script:Fail + $script:Skip
Write-Host "  Results: ${GR}$($script:Pass) passed${RS}  ${RD}$($script:Fail) failed${RS}  ${YL}$($script:Skip) skipped${RS}  ($Total total)"
Write-Host "${CY}============================================================${RS}"
Write-Host ""
if ($script:Fail -gt 0) { exit 1 }
exit 0
