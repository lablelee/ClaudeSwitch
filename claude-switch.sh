#!/usr/bin/env bash
# claude-switch.sh - Cross-platform entry point for ClaudeSwitch
# Works on: macOS, Linux, Windows (Git Bash / WSL)
# Required: python3 (or python 3.x), node, claude CLI
# Optional: aws CLI (Bedrock), jq (statusline fallback)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILES_PATH="$HOME/.claude-profiles.json"
CLAUDE_HOME="$HOME/.claude"
CLAUDE_SECRETS_DIR="$HOME/.claude-secrets"

# --- Colors ------------------------------------------------------------------
CY='\033[0;36m'; GR='\033[0;32m'; YL='\033[0;33m'
RD='\033[0;31m'; MG='\033[0;35m'; WH='\033[0;37m'
DM='\033[0;90m'; BL='\033[0;34m'; RS='\033[0m'

hdr()  { echo ""; printf '%s\n' "============================================================"; printf "${CY}  $1${RS}\n"; printf '%s\n' "============================================================"; }
ok()   { printf "  ${GR}[OK]${RS} $1\n"; }
warn() { printf "  ${YL}[WARN]${RS} $1\n"; }
err()  { printf "  ${RD}[ERR]${RS} $1\n"; }
step() { printf "  ${WH}>> $1${RS}\n"; }

# --- OS / platform detection -------------------------------------------------
detect_platform() {
    case "$(uname -s)" in
        Darwin*)  PLATFORM="macos" ;;
        Linux*)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                PLATFORM="wsl"
            else
                PLATFORM="linux"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)  PLATFORM="gitbash" ;;
        *)  PLATFORM="unknown" ;;
    esac
}
detect_platform

# --- Find python3 or python (3.x) -------------------------------------------
PYTHON=""
find_python() {
    if command -v python3 &>/dev/null; then
        PYTHON="python3"
    elif command -v python &>/dev/null; then
        if python -c "import sys; sys.exit(0 if sys.version_info >= (3,) else 1)" 2>/dev/null; then
            PYTHON="python"
        fi
    fi
    if [ -z "$PYTHON" ]; then
        err "Python 3 not found. Install from: https://www.python.org"
        err "Tried: python3, python"
        return 1
    fi
}
find_python || exit 1

# --- Prerequisites check -----------------------------------------------------
check_prerequisites() {
    local all_ok=true

    # Node.js
    if command -v node &>/dev/null; then
        ok "node $(node --version)"
    else
        err "Node.js not found. Install from: https://nodejs.org"
        all_ok=false
    fi

    # Claude Code - this tool's entire purpose
    if command -v claude &>/dev/null; then
        ok "claude CLI found"
    else
        err "Claude Code CLI not found."
        err "This tool manages Claude Code profiles. Install it first:"
        err "  npm install -g @anthropic-ai/claude-code"
        all_ok=false
    fi

    # Python (already validated above)
    ok "$PYTHON $($PYTHON --version 2>&1 | awk '{print $2}')"

    # AWS CLI - optional, only needed for Bedrock
    if command -v aws &>/dev/null; then
        ok "aws CLI $(aws --version 2>&1 | awk '{print $1}')"
    else
        warn "aws CLI not found (only needed for Bedrock profile)"
    fi

    # JSON parser for statusline
    if command -v jq &>/dev/null; then
        ok "jq $(jq --version 2>&1)"
    else
        ok "jq not found - statusline will use $PYTHON instead (fine)"
    fi

    # Platform
    ok "Platform: $PLATFORM"

    # Secret store
    case "$PLATFORM" in
        macos)
            if command -v security &>/dev/null; then
                ok "Secret store: macOS Keychain"
            else
                warn "security CLI not found - will use file-based secrets"
            fi
            ;;
        linux|wsl)
            if command -v secret-tool &>/dev/null; then
                ok "Secret store: GNOME Keyring (secret-tool)"
            else
                ok "Secret store: encrypted file (~/.claude-secrets/)"
            fi
            ;;
        gitbash)
            ok "Secret store: encrypted file (~/.claude-secrets/)"
            ;;
    esac

    $all_ok || { err "Fix required items above and re-run."; exit 1; }
}

# --- Secret storage (cross-platform) ----------------------------------------
# macOS:              security CLI (Keychain)
# Linux w/ GNOME:     secret-tool (GNOME Keyring)
# Linux/WSL/Git Bash: file-based with openssl encryption or base64 fallback
KEYCHAIN_SERVICE="claude-switch"

_ensure_secrets_dir() {
    if [ ! -d "$CLAUDE_SECRETS_DIR" ]; then
        mkdir -p "$CLAUDE_SECRETS_DIR"
        chmod 700 "$CLAUDE_SECRETS_DIR"
    fi
}

_file_secret_path() {
    local profile_name="$1" key="$2"
    echo "$CLAUDE_SECRETS_DIR/${profile_name}-${key}.enc"
}

# Derive a machine-specific key for file-based encryption
_derive_key() {
    local seed=""
    # Use hostname + username as a seed (not high security, but prevents casual reads)
    seed="$(whoami)@$(hostname)-claude-switch"
    if command -v openssl &>/dev/null; then
        echo -n "$seed" | openssl dgst -sha256 -hex 2>/dev/null | awk '{print $NF}'
    else
        # No openssl - use base64 (warning: not encrypted, just obfuscated)
        echo -n "$seed" | base64 2>/dev/null || echo "$seed"
    fi
}

save_secret() {
    local profile_name="$1" key="$2" value="$3"
    local account="${profile_name}-${key}"

    case "$PLATFORM" in
        macos)
            if command -v security &>/dev/null; then
                security add-generic-password \
                    -a "$account" -s "$KEYCHAIN_SERVICE" -w "$value" -U 2>/dev/null \
                    && ok "Saved '$key' for '$profile_name' in Keychain." \
                    || { err "Failed to save to Keychain."; return 1; }
                return
            fi
            ;;
        linux|wsl)
            if command -v secret-tool &>/dev/null; then
                echo -n "$value" | secret-tool store \
                    --label="claude-switch: $account" \
                    service "$KEYCHAIN_SERVICE" account "$account" 2>/dev/null \
                    && ok "Saved '$key' for '$profile_name' in GNOME Keyring." \
                    || { err "Failed to save to GNOME Keyring."; return 1; }
                return
            fi
            ;;
    esac

    # File-based fallback (Git Bash, Linux without secret-tool, etc.)
    _ensure_secrets_dir
    local path; path=$(_file_secret_path "$profile_name" "$key")
    if command -v openssl &>/dev/null; then
        local dk; dk=$(_derive_key)
        echo -n "$value" | openssl enc -aes-256-cbc -pbkdf2 -pass "pass:$dk" -out "$path" 2>/dev/null
    else
        warn "openssl not found - storing secret with base64 encoding only (not encrypted)."
        echo -n "$value" | base64 > "$path" 2>/dev/null
    fi
    chmod 600 "$path"
    ok "Saved '$key' for '$profile_name' in $path"
}

read_secret() {
    local profile_name="$1" key="$2"
    local account="${profile_name}-${key}"

    case "$PLATFORM" in
        macos)
            if command -v security &>/dev/null; then
                security find-generic-password \
                    -a "$account" -s "$KEYCHAIN_SERVICE" -w 2>/dev/null || echo ""
                return
            fi
            ;;
        linux|wsl)
            if command -v secret-tool &>/dev/null; then
                secret-tool lookup service "$KEYCHAIN_SERVICE" account "$account" 2>/dev/null || echo ""
                return
            fi
            ;;
    esac

    # File-based fallback
    local path; path=$(_file_secret_path "$profile_name" "$key")
    if [ ! -f "$path" ]; then echo ""; return; fi
    if command -v openssl &>/dev/null; then
        local dk; dk=$(_derive_key)
        openssl enc -aes-256-cbc -pbkdf2 -d -pass "pass:$dk" -in "$path" 2>/dev/null || echo ""
    else
        base64 -d < "$path" 2>/dev/null || cat "$path" 2>/dev/null || echo ""
    fi
}

delete_secret() {
    local profile_name="$1" key="$2"
    local account="${profile_name}-${key}"

    case "$PLATFORM" in
        macos)
            if command -v security &>/dev/null; then
                security delete-generic-password \
                    -a "$account" -s "$KEYCHAIN_SERVICE" 2>/dev/null \
                    && ok "Deleted '$key' for '$profile_name'." \
                    || warn "Secret not found."
                return
            fi
            ;;
        linux|wsl)
            if command -v secret-tool &>/dev/null; then
                secret-tool clear service "$KEYCHAIN_SERVICE" account "$account" 2>/dev/null \
                    && ok "Deleted '$key' for '$profile_name'." \
                    || warn "Secret not found."
                return
            fi
            ;;
    esac

    # File-based fallback
    local path; path=$(_file_secret_path "$profile_name" "$key")
    if [ -f "$path" ]; then
        rm -f "$path"
        ok "Deleted '$key' for '$profile_name'."
    else
        warn "Secret not found."
    fi
}

request_and_save_secret() {
    local profile_name="$1" key="$2" prompt="$3"
    echo ""
    printf "  ${CY}$prompt${RS}\n"
    printf "  Enter value (hidden): "
    read -rs value
    echo ""
    if [[ -z "$value" ]]; then
        warn "Empty value - not saved."
        echo ""
        return 1
    fi
    save_secret "$profile_name" "$key" "$value"
}

# --- Profile JSON parsing via python ----------------------------------------
get_profile_names() {
    $PYTHON -c "
import json, sys
with open('$PROFILES_PATH') as f:
    data = json.load(f)
for k in data.get('profiles', {}).keys():
    print(k)
"
}

get_profile_field() {
    local profile="$1" field="$2" default="${3:-}"
    $PYTHON -c "
import json, sys
with open('$PROFILES_PATH') as f:
    data = json.load(f)
p = data.get('profiles', {}).get('$profile', {})
val = p.get('$field', '$default')
if isinstance(val, dict):
    for k,v in val.items():
        print(f'{k}={v}')
else:
    print(val if val else '$default')
" 2>/dev/null || echo "$default"
}

get_profile_env() {
    local profile="$1"
    $PYTHON -c "
import json
with open('$PROFILES_PATH') as f:
    data = json.load(f)
p = data.get('profiles', {}).get('$profile', {})
for k,v in p.get('env', {}).items():
    print(f'export {k}=\"{v}\"')
"
}

get_pinned_model() {
    local profile="$1" model_type="$2"
    $PYTHON -c "
import json
with open('$PROFILES_PATH') as f:
    data = json.load(f)
p = data.get('profiles', {}).get('$profile', {})
pm = p.get('pinnedModels', {})
print(pm.get('$model_type', ''))
" 2>/dev/null || echo ""
}

create_profiles_template() {
    local secret_note=""
    case "$PLATFORM" in
        macos)   secret_note="Secrets stored in Mac Keychain." ;;
        linux|wsl)
            if command -v secret-tool &>/dev/null; then
                secret_note="Secrets stored in GNOME Keyring."
            else
                secret_note="Secrets stored in encrypted files (~/.claude-secrets/)."
            fi
            ;;
        *)       secret_note="Secrets stored in encrypted files (~/.claude-secrets/)." ;;
    esac

    cat > "$PROFILES_PATH" << JSON
{
  "_readme": "Config only - no secrets here. $secret_note",
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
JSON
    ok "Created $PROFILES_PATH"
    warn "Edit foundryResource and awsProfile, then re-run."
}

# --- Process management (cross-platform) ------------------------------------
stop_claude_processes() {
    local killed=0

    case "$PLATFORM" in
        macos|linux|wsl)
            # pgrep -a is GNU extension; macOS pgrep doesn't support -a
            # Use pgrep + ps for portable approach
            while IFS= read -r pid; do
                [ -z "$pid" ] && continue
                local path=""
                path=$(ps -p "$pid" -o comm= 2>/dev/null || echo "")

                # Skip desktop app
                if [[ "$path" == *"/Applications/Claude.app"* ]] || \
                   [[ "$path" == *"AnthropicClaude"* ]]; then
                    step "Skipping Claude desktop app (PID $pid) - spared."
                    continue
                fi

                step "Stopping Claude Code CLI (PID $pid)..."
                kill -9 "$pid" 2>/dev/null && ((killed++)) || true
            done < <(pgrep -f "[c]laude" 2>/dev/null | grep -v "$$" || true)
            ;;
        gitbash)
            # Git Bash on Windows: use tasklist + taskkill
            # Kill node processes running claude, but spare Claude.exe desktop app
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                local pid; pid=$(echo "$line" | awk '{print $2}')
                local name; name=$(echo "$line" | awk '{print $1}')
                # Only kill node.exe (CLI), not Claude.exe (desktop)
                if [[ "$name" == "node.exe" ]]; then
                    step "Stopping node Claude process (PID $pid)..."
                    taskkill //F //PID "$pid" &>/dev/null && ((killed++)) || true
                fi
            done < <(tasklist 2>/dev/null | grep -i "node\|claude" | grep -v "Claude.exe" || true)
            ;;
    esac

    if [ "$killed" -eq 0 ]; then
        step "No Claude Code CLI processes found."
    else
        ok "Stopped $killed process(es)."
        sleep 0.5
    fi
}

# --- Pre-flight per profile ---------------------------------------------------
preflight_bedrock() {
    local profile_name="$1"
    local aws_profile; aws_profile=$(get_profile_field "$profile_name" "awsProfile" "rnd-bedrock")

    if ! command -v aws &>/dev/null; then
        err "AWS CLI not found. Install: https://aws.amazon.com/cli/"
        return 1
    fi

    local profiles; profiles=$(aws configure list-profiles 2>/dev/null)
    if ! echo "$profiles" | grep -q "^${aws_profile}$"; then
        warn "AWS profile '$aws_profile' not found."
        warn "Run: aws configure sso --profile $aws_profile"
        return 1
    fi
    ok "AWS profile '$aws_profile' found."

    if ! aws sts get-caller-identity --profile "$aws_profile" &>/dev/null; then
        warn "AWS session expired. Launching SSO login..."
        aws sso login --profile "$aws_profile"
        if [ $? -ne 0 ]; then
            err "SSO login failed or was cancelled."
            return 1
        fi
        ok "SSO login successful."
    else
        ok "AWS credentials valid."
    fi
}

preflight_foundry() {
    local profile_name="$1"
    local resource; resource=$(get_profile_field "$profile_name" "foundryResource" "")

    if [[ -z "$resource" ]] || [[ "$resource" == "your-foundry-resource-name" ]]; then
        err "foundryResource not set. Edit $PROFILES_PATH"
        return 1
    fi
    ok "Foundry resource: $resource"

    # Check API key in secret store
    local api_key; api_key=$(read_secret "$profile_name" "foundry-key")
    if [[ -z "$api_key" ]]; then
        request_and_save_secret "$profile_name" "foundry-key" \
            "Foundry API key not found. Enter API key for '$profile_name':" || return 1
    else
        ok "Foundry API key found in secret store."
    fi
}

preflight_personal() {
    local creds="$CLAUDE_HOME/.credentials.json"
    if [ -f "$creds" ]; then
        ok "Claude credentials found."
    else
        warn "No Claude credentials. Run: claude login"
    fi
}

# --- Apply env vars and launch ------------------------------------------------
build_env_and_launch() {
    local profile_name="$1"
    local backend; backend=$(get_profile_field "$profile_name" "backend" "anthropic")

    # Collect env vars to set
    local env_pairs=()

    # From profile env block
    while IFS='=' read -r key val; do
        [[ -n "$key" ]] && env_pairs+=("${key}=${val}")
    done < <($PYTHON -c "
import json
with open('$PROFILES_PATH') as f:
    data = json.load(f)
p = data.get('profiles', {}).get('$profile_name', {})
for k,v in p.get('env', {}).items():
    print(f'{k}={v}')
" 2>/dev/null)

    # Backend-specific vars
    case "$backend" in
        bedrock)
            local aws_profile; aws_profile=$(get_profile_field "$profile_name" "awsProfile" "")
            local aws_region;  aws_region=$(get_profile_field  "$profile_name" "awsRegion"  "us-east-1")
            env_pairs+=("CLAUDE_CODE_USE_BEDROCK=1")
            [[ -n "$aws_profile" ]] && env_pairs+=("AWS_PROFILE=$aws_profile")
            [[ -n "$aws_region"  ]] && env_pairs+=("AWS_REGION=$aws_region" "AWS_DEFAULT_REGION=$aws_region")
            local sonnet; sonnet=$(get_pinned_model "$profile_name" "sonnet")
            local haiku;  haiku=$(get_pinned_model  "$profile_name" "haiku")
            local opus;   opus=$(get_pinned_model   "$profile_name" "opus")
            [[ -n "$sonnet" ]] && env_pairs+=("ANTHROPIC_DEFAULT_SONNET_MODEL=$sonnet")
            [[ -n "$haiku"  ]] && env_pairs+=("ANTHROPIC_DEFAULT_HAIKU_MODEL=$haiku")
            [[ -n "$opus"   ]] && env_pairs+=("ANTHROPIC_DEFAULT_OPUS_MODEL=$opus")
            ;;
        foundry)
            local resource; resource=$(get_profile_field "$profile_name" "foundryResource" "")
            local api_key;  api_key=$(read_secret "$profile_name" "foundry-key")
            env_pairs+=("CLAUDE_CODE_USE_FOUNDRY=1")
            [[ -n "$resource" ]] && env_pairs+=("ANTHROPIC_FOUNDRY_RESOURCE=$resource")
            [[ -n "$api_key"  ]] && env_pairs+=("ANTHROPIC_FOUNDRY_API_KEY=$api_key")
            local sonnet; sonnet=$(get_pinned_model "$profile_name" "sonnet")
            local haiku;  haiku=$(get_pinned_model  "$profile_name" "haiku")
            local opus;   opus=$(get_pinned_model   "$profile_name" "opus")
            [[ -n "$sonnet" ]] && env_pairs+=("ANTHROPIC_DEFAULT_SONNET_MODEL=$sonnet")
            [[ -n "$haiku"  ]] && env_pairs+=("ANTHROPIC_DEFAULT_HAIKU_MODEL=$haiku")
            [[ -n "$opus"   ]] && env_pairs+=("ANTHROPIC_DEFAULT_OPUS_MODEL=$opus")
            ;;
    esac

    # Show what we're setting (hide secrets)
    for pair in "${env_pairs[@]}"; do
        key="${pair%%=*}"
        if [[ "$key" == *"KEY"* ]] || [[ "$key" == *"SECRET"* ]]; then
            step "Set $key = [hidden]"
        else
            step "Set $pair"
        fi
    done

    # Launch claude with all env vars
    step "Waiting 2 seconds before launch..."
    sleep 2
    step "Launching Claude Code..."
    echo ""

    # Build env command: env VAR1=val1 VAR2=val2 claude
    exec env "${env_pairs[@]}" claude
}

# --- Statusline installer -----------------------------------------------------
install_statusline() {
    mkdir -p "$CLAUDE_HOME"
    local json_dest="$CLAUDE_HOME/settings.json"
    local personal_file="$CLAUDE_HOME/personal-statusline.txt"

    # Pick the right statusline command for this platform
    local our_cmd=""
    local src_file=""
    case "$PLATFORM" in
        gitbash)
            # On Git Bash, prefer PowerShell statusline (more reliable)
            if command -v powershell.exe &>/dev/null || command -v pwsh &>/dev/null; then
                our_cmd="powershell -NoProfile -File ~/.claude/statusline-command.ps1"
                src_file="statusline-command.ps1"
            else
                our_cmd="bash ~/.claude/statusline-command.sh"
                src_file="statusline-command.sh"
            fi
            ;;
        *)
            our_cmd="bash ~/.claude/statusline-command.sh"
            src_file="statusline-command.sh"
            ;;
    esac

    # Copy statusline script(s)
    local src="$SCRIPT_DIR/$src_file"
    local dest="$CLAUDE_HOME/$src_file"
    if [ ! -f "$src" ]; then
        warn "$src_file not found in $SCRIPT_DIR - skipping statusline install."
        return
    fi
    cp "$src" "$dest"
    chmod +x "$dest" 2>/dev/null || true
    ok "Installed $src_file -> $dest"

    # Also copy both versions so the user has them available
    for f in statusline-command.sh statusline-command.ps1; do
        if [ -f "$SCRIPT_DIR/$f" ] && [ "$f" != "$src_file" ]; then
            cp "$SCRIPT_DIR/$f" "$CLAUDE_HOME/$f"
            chmod +x "$CLAUDE_HOME/$f" 2>/dev/null || true
        fi
    done

    # Check for existing statusline
    local existing_cmd=""
    if [ -f "$json_dest" ]; then
        existing_cmd=$($PYTHON -c "
import json
try:
    with open('$json_dest') as f:
        data = json.load(f)
    cmd = data.get('statusLine', {}).get('command', '')
    if 'statusline-command' not in cmd:
        print(cmd)
except:
    pass
" 2>/dev/null)
    fi

    local choice="1"
    if [ -n "$existing_cmd" ]; then
        echo ""
        printf "  ${CY}You already have a statusline configured:${RS}\n"
        printf "  ${WH}%s${RS}\n" "$existing_cmd"
        echo ""
        printf "  ${CY}[1]${RS} Keep yours on Personal, use ours on Bedrock/Foundry ${DM}(recommended)${RS}\n"
        printf "  ${CY}[2]${RS} Replace with ours on all profiles\n"
        printf "  ${DM}[3]${RS} Skip statusline setup\n"
        echo ""
        printf "  Choose (1/2/3): "
        read -r choice
        choice="${choice:-1}"

        if [ "$choice" = "3" ]; then
            warn "Skipping statusline setup."
            return
        fi

        if [ "$choice" = "1" ]; then
            echo "$existing_cmd" > "$personal_file"
            ok "Saved your original statusline to: $personal_file"
            ok "It will be used on Personal profile automatically."
        fi
    fi

    # Write/merge settings.json using python (cross-platform, no jq needed)
    $PYTHON << PYEOF
import json, os

json_dest = "$json_dest"
our_cmd = "$our_cmd"

if os.path.exists(json_dest):
    try:
        with open(json_dest) as f:
            data = json.load(f)
    except:
        data = {}
else:
    data = {}

data["statusLine"] = {"type": "command", "command": our_cmd}
existing_allow = data.get("permissions", {}).get("allow", [])
existing_deny  = data.get("permissions", {}).get("deny",  [])
merged_allow = list(set(existing_allow + [f"Bash({our_cmd})"]))
data["permissions"] = {"allow": merged_allow, "deny": existing_deny}

with open(json_dest, "w") as f:
    json.dump(data, f, indent=2)
PYEOF

    ok "settings.json updated (all other settings preserved)"
    ok "Statusline installed. Restart Claude Code to activate."
}

set_statusline_for_profile() {
    local backend="$1"
    local json_dest="$CLAUDE_HOME/settings.json"
    local personal_file="$CLAUDE_HOME/personal-statusline.txt"

    # Pick correct command for platform
    local our_cmd=""
    case "$PLATFORM" in
        gitbash)
            if command -v powershell.exe &>/dev/null || command -v pwsh &>/dev/null; then
                our_cmd="powershell -NoProfile -File ~/.claude/statusline-command.ps1"
            else
                our_cmd="bash ~/.claude/statusline-command.sh"
            fi
            ;;
        *)
            our_cmd="bash ~/.claude/statusline-command.sh"
            ;;
    esac

    [ -f "$json_dest" ] || return

    if [ "$backend" = "anthropic" ]; then
        # Switching to Personal - restore original if saved
        if [ -f "$personal_file" ]; then
            local personal_cmd; personal_cmd=$(tr -d '\r\n' < "$personal_file")
            if [ -n "$personal_cmd" ]; then
                $PYTHON -c "
import json
with open('$json_dest') as f:
    data = json.load(f)
data['statusLine'] = {'type': 'command', 'command': '$personal_cmd'}
with open('$json_dest', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null
                step "Restored your personal statusline."
                return
            fi
        fi
        # No saved personal - keep ours
    else
        # Bedrock or Foundry - activate ours
        $PYTHON -c "
import json
with open('$json_dest') as f:
    data = json.load(f)
data['statusLine'] = {'type': 'command', 'command': '$our_cmd'}
with open('$json_dest', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null
        step "Activated ClaudeSwitch statusline for ${backend}."
    fi
}

# --- Shell alias installer ----------------------------------------------------
install_shell_aliases() {
    local script_path="$SCRIPT_DIR/claude-switch.sh"
    local snippet="
# ClaudeSwitch aliases
alias cc-menu='bash \"$script_path\"'
alias cc-personal='bash \"$script_path\" personal'
alias cc-bedrock='bash \"$script_path\" bedrock'
alias cc-foundry='bash \"$script_path\" foundry'
alias cc-status='bash \"$script_path\" --status'
alias cc-setup='bash \"$script_path\" --setup'
"
    # Detect shell config file
    local rc_file=""
    case "$PLATFORM" in
        macos)
            # macOS defaults to zsh since Catalina
            if [[ -f "$HOME/.zshrc" ]]; then rc_file="$HOME/.zshrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then rc_file="$HOME/.bash_profile"
            fi
            ;;
        gitbash)
            # Git Bash uses .bashrc or .bash_profile
            if [[ -f "$HOME/.bashrc" ]]; then rc_file="$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then rc_file="$HOME/.bash_profile"
            fi
            ;;
        *)
            if [[ -f "$HOME/.zshrc" ]]; then rc_file="$HOME/.zshrc"
            elif [[ -f "$HOME/.bashrc" ]]; then rc_file="$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then rc_file="$HOME/.bash_profile"
            fi
            ;;
    esac

    if [[ -z "$rc_file" ]]; then
        warn "Could not find shell config file (.zshrc / .bashrc / .bash_profile)"
        return
    fi

    if grep -q "ClaudeSwitch aliases" "$rc_file" 2>/dev/null; then
        ok "Shell aliases already in $rc_file"
        return
    fi

    printf "  Add cc-personal / cc-bedrock / cc-foundry aliases to $rc_file? (y/N): "
    read -r ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        echo "$snippet" >> "$rc_file"
        ok "Aliases added to $rc_file"
        ok "Run: source $rc_file   (or open a new terminal)"
    fi
}

# --- Interactive menu ---------------------------------------------------------
show_menu() {
    local profiles=("$@")
    hdr "Claude Code - Profile Switcher"
    echo ""
    local i=1
    for p in "${profiles[@]}"; do
        local backend; backend=$(get_profile_field "$p" "backend" "?")
        local desc;    desc=$(get_profile_field    "$p" "description" "")
        printf "  ${CY}[%d]${RS} %-12s ${YL}(%-10s)${RS} ${DM}%s${RS}\n" \
            "$i" "$p" "${backend^^}" "$desc"
        i=$((i + 1))
    done
    echo ""
    printf "  ${DM}[S] Status   [D] Diagnostics   [K] Manage secrets   [Q] Quit${RS}\n"
    echo ""
    printf "  Choose: "
    read -r choice
    echo "$choice"
}

show_status() {
    hdr "Active Claude Code Profile"
    local found=false
    for var in CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_FOUNDRY ANTHROPIC_FOUNDRY_RESOURCE \
               AWS_PROFILE AWS_REGION ANTHROPIC_DEFAULT_SONNET_MODEL \
               ANTHROPIC_DEFAULT_HAIKU_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL \
               CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS DISABLE_PROMPT_CACHING; do
        val="${!var:-}"
        if [[ -n "$val" ]]; then
            printf "  ${CY}%-42s${RS} = %s\n" "$var" "$val"
            found=true
        fi
    done
    $found || printf "  ${DM}No API profile active (Claude Max / OAuth)${RS}\n"
}

manage_secrets() {
    local profiles=("$@")
    hdr "Manage Secrets"
    echo ""

    # Show secret store info
    case "$PLATFORM" in
        macos)   step "Secret store: macOS Keychain" ;;
        linux|wsl)
            if command -v secret-tool &>/dev/null; then
                step "Secret store: GNOME Keyring"
            else
                step "Secret store: encrypted files (~/.claude-secrets/)"
            fi
            ;;
        *)       step "Secret store: encrypted files (~/.claude-secrets/)" ;;
    esac
    echo ""

    for p in "${profiles[@]}"; do
        local backend; backend=$(get_profile_field "$p" "backend" "")
        if [[ "$backend" == "foundry" ]]; then
            local key; key=$(read_secret "$p" "foundry-key")
            if [[ -n "$key" ]]; then
                printf "  ${CY}%-16s${RS} ${GR}[foundry-key: stored]${RS}\n" "$p"
            else
                printf "  ${CY}%-16s${RS} ${DM}[foundry-key: not set]${RS}\n" "$p"
            fi
        fi
    done
    echo ""
    printf "  Profile name to update (or Enter to cancel): "
    read -r pname
    [[ -z "$pname" ]] && return
    printf "  [1] Set Foundry API key\n  [2] Clear Foundry API key\n  [3] Cancel\n  Choose: "
    read -r kchoice
    case "$kchoice" in
        1) request_and_save_secret "$pname" "foundry-key" "Enter Foundry API key for '$pname':" ;;
        2) delete_secret "$pname" "foundry-key" ;;
    esac
}

# --- Main ---------------------------------------------------------------------
main() {
    local arg="${1:-}"

    # Handle flags
    case "$arg" in
        --setup|-d)
            hdr "Claude Code - Setup Diagnostics"
            check_prerequisites
            exit 0
            ;;
        --status|-s)
            show_status
            exit 0
            ;;
        --install-statusline)
            install_statusline
            exit 0
            ;;
        --install-aliases)
            install_shell_aliases
            exit 0
            ;;
    esac

    # Always check prerequisites first
    check_prerequisites

    # First run: create profile JSON
    if [ ! -f "$PROFILES_PATH" ]; then
        echo ""
        warn "First run - creating profiles config..."
        create_profiles_template
        echo ""
        step "Edit $PROFILES_PATH with your settings, then re-run."
        if command -v code &>/dev/null; then
            code "$PROFILES_PATH"
        else
            step "Run: nano $PROFILES_PATH"
        fi
        exit 0
    fi

    # Auto-install statusline if not present
    local has_statusline=false
    [ -f "$CLAUDE_HOME/statusline-command.sh" ] && has_statusline=true
    [ -f "$CLAUDE_HOME/statusline-command.ps1" ] && has_statusline=true
    if ! $has_statusline; then
        step "Installing Claude Code statusline..."
        install_statusline
    fi

    # Offer to install shell aliases on first profile switch
    if [ ! -f "$HOME/.claude-switch-aliases-installed" ]; then
        install_shell_aliases
        touch "$HOME/.claude-switch-aliases-installed"
    fi

    # Get profile list
    local profile_names=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && profile_names+=("$line")
    done < <(get_profile_names)

    if [ ${#profile_names[@]} -eq 0 ]; then
        err "No profiles found in $PROFILES_PATH"
        exit 1
    fi

    # Determine target profile
    local target="$arg"

    if [[ -z "$target" ]]; then
        choice=$(show_menu "${profile_names[@]}")
        case "${choice^^}" in
            Q) echo "  Bye!"; exit 0 ;;
            S) show_status; exit 0 ;;
            D) check_prerequisites; exit 0 ;;
            K) manage_secrets "${profile_names[@]}"; exit 0 ;;
            [0-9]*)
                idx=$((choice - 1))
                if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#profile_names[@]}" ]; then
                    target="${profile_names[$idx]}"
                else
                    err "Invalid choice."; exit 1
                fi
                ;;
            *)
                target="$choice"
                ;;
        esac
    fi

    # Validate profile exists
    local valid=false
    for p in "${profile_names[@]}"; do
        [[ "$p" == "$target" ]] && valid=true && break
    done
    if ! $valid; then
        err "Profile '$target' not found. Available: ${profile_names[*]}"
        exit 1
    fi

    local backend; backend=$(get_profile_field "$target" "backend" "anthropic")

    hdr "Switching to: $target"
    local desc; desc=$(get_profile_field "$target" "description" "")
    printf "  ${DM}%s${RS}\n" "$desc"
    echo ""

    # Pre-flight
    step "[1/4] Pre-flight checks..."
    case "$backend" in
        bedrock)  preflight_bedrock  "$target" || exit 1 ;;
        foundry)  preflight_foundry  "$target" || exit 1 ;;
        *)        preflight_personal ;;
    esac

    # Kill processes
    step "[2/4] Stopping Claude Code processes..."
    stop_claude_processes

    # Apply and launch
    step "[3/4] Applying profile '$target'..."
    set_statusline_for_profile "$backend"
    step "[4/4] Launching Claude Code..."
    build_env_and_launch "$target"
}

main "$@"
