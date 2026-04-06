# =============================================================================
# Add this block to your PowerShell $PROFILE
# To open your profile: notepad $PROFILE
# Paste everything below, update the path, then save and restart PowerShell
# =============================================================================

# Path to your ClaudeSwitch folder - update this if you moved it
$ClaudeSwitchDir = "$HOME\ClaudeSwitch"

if (Test-Path "$ClaudeSwitchDir\ClaudeSwitch.psm1") {
    Import-Module "$ClaudeSwitchDir\ClaudeSwitch.psm1" -Force

    # Switch to a profile and launch Claude Code
    function cc-personal { Switch-ClaudeProfile -ProfileName personal -Launch }
    function cc-bedrock  { Switch-ClaudeProfile -ProfileName bedrock  -Launch }
    function cc-foundry  { Switch-ClaudeProfile -ProfileName foundry  -Launch }

    # Utilities
    function cc-status   { Show-ClaudeProfile }
    function cc-setup    { Test-ClaudeSetup   }
    function cc-statusline { Install-StatusLine }
    function cc-menu     { Switch-ClaudeProfile }

    Write-Host "Claude Code switcher ready." -ForegroundColor DarkGray
    Write-Host "Commands: cc-personal | cc-bedrock | cc-foundry | cc-menu | cc-status | cc-setup | cc-statusline" -ForegroundColor DarkGray
}
