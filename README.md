# ClaudeSwitch - Claude Code Profile Switcher

Switch between Claude Max (personal), AWS Bedrock (R&D), and Azure Foundry (company)
with a single command. No more mixed sessions, wrong models, or stale env vars.

---

## How it works

Claude Code stores its backend routing (Anthropic / Bedrock / Foundry) in environment
variables at startup. Changing these vars without restarting Claude Code has no effect.

ClaudeSwitch fixes this by:
1. Killing all Claude Code CLI processes (but NOT the Claude desktop app)
2. Wiping all profile-related env vars (25+ vars)
3. Validating your credentials before switching
4. Applying the correct vars for the new profile
5. Pinning model IDs so Bedrock/Foundry never get an unresolvable alias
6. Waiting 2 seconds before launch to avoid first-run UI glitches

---

## Files

```
ClaudeSwitch\
  ClaudeSwitch.psm1               - PowerShell module (all logic)
  claude-switch.ps1               - Windows PowerShell entry point
  claude-switch.sh                - Cross-platform bash entry point (macOS/Linux/Git Bash/WSL)
  statusline-command.ps1          - Claude Code statusline (PowerShell, PS 5.1+ compatible)
  statusline-command.sh           - Claude Code statusline (bash, no jq required)
  profile-snippet.ps1             - optional: paste into $PROFILE for shell aliases
  settings.json                   - reference Claude Code settings for statusline
  README.md                       - this file
  tests\                          - cross-platform test suite
    run-tests.sh                  - bash tests (34 checks)
    run-tests.ps1                 - PowerShell tests (33 checks)
    mock-data\                    - mock JSON for statusline testing
```

---

## Platform support

| Platform | Entry point | Statusline | Secret store |
|----------|------------|------------|-------------|
| Windows (PowerShell) | claude-switch.ps1 | statusline-command.ps1 | Windows DPAPI |
| Windows (Git Bash) | claude-switch.sh | statusline-command.sh | Encrypted file (openssl) |
| macOS (zsh/bash) | claude-switch.sh | statusline-command.sh | macOS Keychain |
| Linux | claude-switch.sh | statusline-command.sh | GNOME Keyring or encrypted file |
| WSL | claude-switch.sh | statusline-command.sh | GNOME Keyring or encrypted file |

---

## Prerequisites

Install these before running ClaudeSwitch:

| Software | Required for | Install |
|----------|-------------|---------|
| Node.js (v18+) | Claude Code CLI | https://nodejs.org |
| Claude Code CLI | all profiles | npm install -g @anthropic-ai/claude-code |
| Python 3 | bash version (JSON parsing) | https://www.python.org (usually pre-installed on macOS/Linux) |
| AWS CLI v2 | Bedrock profile only | https://aws.amazon.com/cli/ |

- **jq is NOT required.** The statusline and switcher use Python 3 for JSON parsing. If jq is installed it will be used as a fallback.
- AWS CLI is NOT needed if you don't use the Bedrock profile.
- The PowerShell version uses built-in ConvertFrom-Json (no Python needed).

---

## First-time setup (5 minutes)

### Step 1 - Fix PowerShell execution policy (Windows only, do once)

Open PowerShell as Administrator and run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

This allows local scripts to run. You only need to do this once.

### Step 2 - Install Node.js and Claude Code

1. Download and install Node.js from https://nodejs.org (LTS version)
2. Open a new PowerShell window and run:

```powershell
npm install -g @anthropic-ai/claude-code
claude --version
```

### Step 3 - Place the ClaudeSwitch folder

Put the ClaudeSwitch folder somewhere permanent, for example:

```
C:\Users\YourName\ClaudeSwitch\
```

### Step 4 - Create your profiles config

```powershell
Copy-Item "$HOME\ClaudeSwitch\.claude-profiles.json.template" "$HOME\.claude-profiles.json"
code $HOME\.claude-profiles.json
```

Fill in your credentials (see Profile Configuration below).

### Step 5 - Log into Claude Code (personal profile)

```powershell
claude login
```

Follow the browser prompt to log in with your Claude Max account.

### Step 6 - Add shell shortcuts (optional but recommended)

```powershell
notepad $PROFILE
```

Paste the contents of profile-snippet.ps1 into your profile, update the path, save and restart PowerShell.

---

## Profile Configuration

Edit ~/.claude-profiles.json with your real values.

### Personal (Claude Max)

No configuration needed. ClaudeSwitch uses the OAuth token from "claude login".

```json
"personal": {
  "description": "Claude Max - personal subscription (OAuth login)",
  "backend": "anthropic",
  "env": {}
}
```

### Bedrock (AWS SSO)

```json
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
}
```

Set up the AWS SSO profile:

```powershell
aws configure sso --profile rnd-bedrock
```

Follow the prompts - you will need your SSO start URL from your AWS admin.

Get your Bedrock model IDs:

```powershell
aws bedrock list-inference-profiles --profile rnd-bedrock --region us-east-1 `
  --query "inferenceProfileSummaries[?contains(inferenceProfileId,'claude-sonnet') || contains(inferenceProfileId,'claude-opus')].inferenceProfileId"
```

NOTE: AWS SSO tokens expire after 8 hours. When Bedrock pre-flight fails, run:

```powershell
aws sso login --profile rnd-bedrock
```

### Foundry (Azure, API key per user)

Each team member gets their own API key from the Azure Foundry portal.

```json
"foundry": {
  "description": "Microsoft Azure Foundry - company deployment",
  "backend": "foundry",
  "foundryResource": "your-resource-name",
  "foundryApiKey": "your-personal-api-key",
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
```

To get your API key:
1. Go to ai.azure.com
2. Open your project
3. Go to Models + endpoints
4. Click on a Claude deployment
5. Copy the Key shown on the details page

---

## Usage

### Interactive menu (recommended)

```powershell
.\claude-switch.ps1
```

Shows a numbered menu. Select a profile, it switches and you run "claude" manually.

### Direct switch

```powershell
.\claude-switch.ps1 personal
.\claude-switch.ps1 bedrock
.\claude-switch.ps1 foundry
```

### Switch and launch Claude Code

```powershell
.\claude-switch.ps1 personal -Launch
.\claude-switch.ps1 bedrock  -Launch
.\claude-switch.ps1 foundry  -Launch
```

### Shell shortcuts (after adding profile-snippet.ps1 to $PROFILE)

```powershell
cc-menu       # interactive menu
cc-personal   # switch to Claude Max and launch
cc-bedrock    # switch to Bedrock and launch
cc-foundry    # switch to Foundry and launch
cc-status     # show active env vars
cc-setup      # run full diagnostics
```

### Diagnostics and status

```powershell
.\claude-switch.ps1 -Setup    # check all tools, credentials, config
.\claude-switch.ps1 -Status   # show currently active env vars
```

### Skip pre-flight checks

```powershell
.\claude-switch.ps1 bedrock -Force
```

---

## Verifying which profile is active

Inside Claude Code, type:

```
/model
```

The model ID tells you which backend is active:
- Bedrock:   us.anthropic.claude-sonnet-4-6
- Foundry:   claude-sonnet-4-6
- Personal:  claude-sonnet-4-6 (looks same as Foundry but billed to your subscription)

Or check from PowerShell anytime:

```powershell
.\claude-switch.ps1 -Status
```

---

## Testing

Run the test suite to verify everything works on your system:

```bash
# Bash (macOS / Linux / Git Bash / WSL)
bash tests/run-tests.sh
```

```powershell
# PowerShell (Windows)
powershell -File tests/run-tests.ps1
```

Tests cover:
- Statusline rendering for all 3 profiles (Personal, Bedrock, Foundry)
- High context warnings (/compact)
- Graceful handling of minimal/empty JSON
- Profile JSON parsing
- Script syntax validation
- Module import and exported functions (PowerShell)

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| "running scripts is disabled" | PowerShell execution policy | Run: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser |
| "claude not found" | Claude Code CLI not installed | Run: npm install -g @anthropic-ai/claude-code |
| "needs python3 or jq" | No JSON parser on bash | Install Python 3: https://www.python.org |
| Bedrock "session expired" | AWS SSO token expired (8hr) | Run: aws sso login --profile rnd-bedrock |
| Bedrock 403 on first use | Anthropic FTU form not completed | AWS Console -> Bedrock -> Model catalog -> complete the form |
| Bedrock "model not found" | Wrong model ID in pinnedModels | Run list-inference-profiles to get correct IDs |
| Foundry 401 | Wrong or missing API key | Run: ./claude-switch.sh --setup or use -Secrets flag |
| Foundry model not found | Deployment name mismatch | Check exact deployment names in ai.azure.com -> Models + endpoints |
| Claude desktop app gets killed | Path detection issue | Report the path shown by: Get-Process -Name claude \| Select Path |
| Theme screen freezes on launch | First-run interactive UI issue | Use -Launch flag (adds 2s delay) or run "claude" manually |
| Profile still shows wrong model | Old session not fully killed | Run the switcher again, or close all terminals and reopen |
| Tests failing | Run tests to diagnose | bash tests/run-tests.sh or powershell -File tests/run-tests.ps1 |

---

## Security notes

- Never commit ~/.claude-profiles.json to git - it contains your API keys
- Each team member should have their own API key (Foundry) or IAM user (Bedrock)
- The profile-snippet.ps1 does NOT contain credentials - safe to share
- AWS SSO is preferred over access keys for Bedrock (keys expire, more secure)

