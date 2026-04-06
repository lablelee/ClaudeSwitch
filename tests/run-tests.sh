#!/usr/bin/env bash
# ClaudeSwitch test suite - bash version
# Run from repo root: bash tests/run-tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MOCK_DIR="$SCRIPT_DIR/mock-data"
STATUSLINE="$ROOT_DIR/statusline-command.sh"
SWITCH="$ROOT_DIR/claude-switch.sh"

GR='\033[0;32m'; RD='\033[0;31m'; YL='\033[0;33m'
CY='\033[0;36m'; DM='\033[0;90m'; RS='\033[0m'

PASS=0; FAIL=0; SKIP=0

pass() { PASS=$((PASS + 1)); printf "  ${GR}PASS${RS} %s\n" "$1"; }
fail() { FAIL=$((FAIL + 1)); printf "  ${RD}FAIL${RS} %s\n" "$1"; if [ -n "${2:-}" ]; then printf "       ${DM}%s${RS}\n" "$2"; fi; }
skip() { SKIP=$((SKIP + 1)); printf "  ${YL}SKIP${RS} %s\n" "$1"; }
section() { echo ""; printf "${CY}=== %s ===${RS}\n" "$1"; }

PLATFORM="unknown"
case "$(uname -s)" in
    Darwin*) PLATFORM="macos" ;; Linux*) grep -qi microsoft /proc/version 2>/dev/null && PLATFORM="wsl" || PLATFORM="linux" ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="gitbash" ;; esac

PYTHON=""
if command -v python3 &>/dev/null; then PYTHON="python3"
elif command -v python &>/dev/null; then
    python -c "import sys; sys.exit(0 if sys.version_info >= (3,) else 1)" 2>/dev/null && PYTHON="python"
fi

echo ""
printf "${CY}ClaudeSwitch Test Suite${RS}\n"
printf "${DM}Platform: %s | Shell: %s${RS}\n" "$PLATFORM" "$BASH_VERSION"

# =============================================================================
section "Prerequisites"
# =============================================================================
[ -n "$PYTHON" ] && pass "python: $($PYTHON --version 2>&1)" || fail "No python3 or python found"
command -v jq &>/dev/null && pass "jq: $(jq --version 2>&1)" || skip "jq not found (optional)"
command -v node &>/dev/null && pass "node: $(node --version)" || skip "node not found"
[ -f "$STATUSLINE" ] && pass "statusline-command.sh exists" || fail "statusline-command.sh not found"
[ -f "$SWITCH" ] && pass "claude-switch.sh exists" || fail "claude-switch.sh not found"
bash -n "$STATUSLINE" 2>/dev/null && pass "statusline-command.sh valid syntax" || fail "syntax errors in .sh"
bash -n "$SWITCH" 2>/dev/null && pass "claude-switch.sh valid syntax" || fail "syntax errors in switch.sh"

# Helper: run statusline with env overrides
run_sl() {
    local json_file="$1"; shift
    # Apply env overrides
    local saved_bedrock="${CLAUDE_CODE_USE_BEDROCK:-}" saved_foundry="${CLAUDE_CODE_USE_FOUNDRY:-}"
    local saved_aws="${AWS_PROFILE:-}" saved_fr="${ANTHROPIC_FOUNDRY_RESOURCE:-}"
    unset CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_FOUNDRY AWS_PROFILE ANTHROPIC_FOUNDRY_RESOURCE 2>/dev/null || true
    for var in "$@"; do export "$var"; done
    local out; out=$(cat "$json_file" | bash "$STATUSLINE" 2>&1) || true
    # Restore
    [ -n "$saved_bedrock" ] && export CLAUDE_CODE_USE_BEDROCK="$saved_bedrock" || unset CLAUDE_CODE_USE_BEDROCK 2>/dev/null || true
    [ -n "$saved_foundry" ] && export CLAUDE_CODE_USE_FOUNDRY="$saved_foundry" || unset CLAUDE_CODE_USE_FOUNDRY 2>/dev/null || true
    [ -n "$saved_aws" ] && export AWS_PROFILE="$saved_aws" || unset AWS_PROFILE 2>/dev/null || true
    [ -n "$saved_fr" ] && export ANTHROPIC_FOUNDRY_RESOURCE="$saved_fr" || unset ANTHROPIC_FOUNDRY_RESOURCE 2>/dev/null || true
    echo "$out"
}

# =============================================================================
section "Personal - Normal (42.5%)"
# =============================================================================
if [ -n "$PYTHON" ] || command -v jq &>/dev/null; then
    output=$(run_sl "$MOCK_DIR/personal.json")

    echo "$output" | grep -q "PERSONAL" && pass "Badge: PERSONAL" || fail "Missing PERSONAL badge" "$output"
    echo "$output" | grep -q "Opus 4.6" && pass "Model: Opus 4.6" || fail "Missing model name" "$output"
    echo "$output" | grep -q "(1M)" && pass "Context size: (1M)" || fail "Missing (1M)" "$output"
    echo "$output" | grep -q "1\.0\.34" && pass "Version shown" || fail "Missing version" "$output"
    echo "$output" | grep -q "┊" && pass "Column separator ┊" || fail "Missing ┊ separator" "$output"
    echo "$output" | grep -qP '▆' && pass "Progress bar ▆ chars" || fail "Missing bar chars" "$output"
    echo "$output" | grep -q "42\.5%" && pass "Context 42.5%" || fail "Missing context %" "$output"
    echo "$output" | grep -q "5h" && pass "5h rate limit" || fail "Missing 5h" "$output"
    echo "$output" | grep -q "25%" && pass "5h value 25%" || fail "Missing 5h value" "$output"
    echo "$output" | grep -q "7d" && pass "7d rate limit" || fail "Missing 7d" "$output"
    echo "$output" | grep -q "13%" && pass "7d value 13%" || fail "Missing 7d value" "$output"
    echo "$output" | grep -q "context" && pass "Context label" || fail "Missing context label" "$output"
    echo "$output" | grep -q "session" && pass "Session label" || fail "Missing session" "$output"
    echo "$output" | grep -q "+142" && pass "Lines +142" || fail "Missing +lines" "$output"
    echo "$output" | grep -q "\-38" && pass "Lines -38" || fail "Missing -lines" "$output"
    echo "$output" | grep -q "↓" && pass "Input arrow ↓" || fail "Missing ↓" "$output"
    echo "$output" | grep -q "↑" && pass "Output arrow ↑" || fail "Missing ↑" "$output"
    echo "$output" | grep -q "200k" && pass "Input tokens 200k" || fail "Missing input tokens" "$output"
    echo "$output" | grep -q "30k" && pass "Output tokens 30k" || fail "Missing output tokens" "$output"
    # Should NOT show compact warning
    echo "$output" | grep -q "compact" && fail "Should not show /compact at 42.5%" || pass "No compact warning (correct)"
else
    skip "No JSON parser"
fi

# =============================================================================
section "Personal - High Context (85.3%)"
# =============================================================================
if [ -n "$PYTHON" ] || command -v jq &>/dev/null; then
    output=$(run_sl "$MOCK_DIR/high-context.json")

    echo "$output" | grep -q "PERSONAL" && pass "Badge: PERSONAL" || fail "Missing badge" "$output"
    echo "$output" | grep -q "85\.3%" && pass "Context 85.3%" || fail "Missing 85.3%" "$output"
    echo "$output" | grep -q "compact now" && pass "Compact warning shown" || fail "Missing /compact now" "$output"
    echo "$output" | grep -q "▸" && pass "Warning indicator ▸" || fail "Missing ▸" "$output"
    echo "$output" | grep -q "92%" && pass "5h rate 92% (high)" || fail "Missing 92%" "$output"
    echo "$output" | grep -q "75%" && pass "7d rate 75% (medium)" || fail "Missing 75%" "$output"
    echo "$output" | grep -q "+500" && pass "Lines +500" || fail "Missing +500" "$output"
    echo "$output" | grep -q "session" && pass "Session present" || fail "Missing session" "$output"
    echo "$output" | grep -q "↓" && pass "Input arrow" || fail "Missing ↓" "$output"
else
    skip "No JSON parser"
fi

# =============================================================================
section "Bedrock (API profile, no rate limits)"
# =============================================================================
if [ -n "$PYTHON" ] || command -v jq &>/dev/null; then
    output=$(run_sl "$MOCK_DIR/bedrock.json" "CLAUDE_CODE_USE_BEDROCK=1" "AWS_PROFILE=rnd-bedrock")

    echo "$output" | grep -q "BEDROCK" && pass "Badge: BEDROCK" || fail "Missing BEDROCK badge" "$output"
    echo "$output" | grep -q "Sonnet 4.6" && pass "Model: Sonnet 4.6" || fail "Missing model" "$output"
    echo "$output" | grep -q "(200k)" && pass "Context size: (200k)" || fail "Missing (200k)" "$output"
    echo "$output" | grep -q "5h" && fail "Should not show 5h for Bedrock" || pass "No 5h (correct)"
    echo "$output" | grep -q "7d" && fail "Should not show 7d for Bedrock" || pass "No 7d (correct)"
    echo "$output" | grep -q "cost" && pass "Cost shown" || fail "Missing cost" "$output"
    echo "$output" | grep -q "1\.23" && pass "Cost value \$1.23" || fail "Missing cost value" "$output"
    echo "$output" | grep -q "context" && pass "Context bar shown" || fail "Missing context bar" "$output"
    echo "$output" | grep -q "78\.2%" && pass "Context 78.2%" || fail "Missing 78.2%" "$output"
    echo "$output" | grep -q "compact soon" && pass "Compact warning (78%)" || fail "Missing /compact soon at 78%" "$output"
    echo "$output" | grep -q "session" && pass "Session shown" || fail "Missing session" "$output"
    echo "$output" | grep -q "+310" && pass "Lines +310" || fail "Missing +310" "$output"
    echo "$output" | grep -q "↓" && pass "Input arrow" || fail "Missing ↓" "$output"
    echo "$output" | grep -q "┊" && pass "Column separator aligned" || fail "Missing ┊" "$output"
    # Verify no debug placeholder
    echo "$output" | grep -qi "debug\|placeholder" && fail "Debug placeholder still showing" || pass "No debug placeholder"
else
    skip "No JSON parser"
fi

# =============================================================================
section "Foundry (API profile, low context)"
# =============================================================================
if [ -n "$PYTHON" ] || command -v jq &>/dev/null; then
    output=$(run_sl "$MOCK_DIR/foundry.json" "CLAUDE_CODE_USE_FOUNDRY=1" "ANTHROPIC_FOUNDRY_RESOURCE=my-foundry")

    echo "$output" | grep -q "FOUNDRY" && pass "Badge: FOUNDRY" || fail "Missing FOUNDRY badge" "$output"
    echo "$output" | grep -q "Sonnet 4.6" && pass "Model: Sonnet 4.6" || fail "Missing model" "$output"
    echo "$output" | grep -q "5h" && fail "Should not show 5h" || pass "No 5h (correct)"
    echo "$output" | grep -q "cost" && pass "Cost shown" || fail "Missing cost" "$output"
    echo "$output" | grep -q "0\.45" && pass "Cost value \$0.45" || fail "Missing cost value" "$output"
    echo "$output" | grep -q "15\.0%" && pass "Context 15.0%" || fail "Missing 15.0%" "$output"
    echo "$output" | grep -q "compact" && fail "Should not show /compact at 15%" || pass "No compact warning (correct)"
    echo "$output" | grep -q "session" && pass "Session shown" || fail "Missing session" "$output"
    echo "$output" | grep -q "+50" && pass "Lines +50" || fail "Missing +50" "$output"
    echo "$output" | grep -qi "debug" && fail "Debug placeholder" || pass "No debug placeholder"
else
    skip "No JSON parser"
fi

# =============================================================================
section "Minimal JSON (graceful degradation)"
# =============================================================================
if [ -n "$PYTHON" ] || command -v jq &>/dev/null; then
    output=$(run_sl "$MOCK_DIR/minimal.json")
    exit_code=$?

    [ $exit_code -eq 0 ] && pass "Exits cleanly" || fail "Crashed (exit $exit_code)"
    echo "$output" | grep -q "Haiku 4.5" && pass "Model: Haiku 4.5" || fail "Missing model" "$output"
    echo "$output" | grep -q "PERSONAL" && pass "Default badge" || fail "Missing badge" "$output"
    echo "$output" | grep -q "2\.1%" && pass "Context 2.1%" || fail "Missing 2.1%" "$output"
else
    skip "No JSON parser"
fi

# =============================================================================
section "Empty JSON (error handling)"
# =============================================================================
if [ -n "$PYTHON" ] || command -v jq &>/dev/null; then
    output=$(run_sl "$MOCK_DIR/empty.json") || true
    echo "$output" | grep -qi "syntax error\|unbound variable\|command not found" && fail "Bash crash" "$output" || pass "No bash crash on empty JSON"
else
    skip "No JSON parser"
fi

# =============================================================================
section "Profile JSON parsing"
# =============================================================================
if [ -n "$PYTHON" ]; then
    TEST_JSON='{ "profiles": {
        "personal": { "backend": "anthropic", "env": {} },
        "bedrock":  { "backend": "bedrock", "awsProfile": "test-profile",
                      "pinnedModels": { "sonnet": "us.anthropic.claude-sonnet-4-6" },
                      "env": { "CLAUDE_CODE_USE_BEDROCK": "1" } },
        "foundry":  { "backend": "foundry", "foundryResource": "my-resource",
                      "env": { "CLAUDE_CODE_USE_FOUNDRY": "1" } }
    }}'

    names=$(echo "$TEST_JSON" | $PYTHON -c "import json,sys; [print(k) for k in json.load(sys.stdin)['profiles']]")
    echo "$names" | grep -q "personal" && echo "$names" | grep -q "bedrock" && echo "$names" | grep -q "foundry" \
        && pass "Extracts all profile names" || fail "Failed profile names" "$names"

    backend=$(echo "$TEST_JSON" | $PYTHON -c "import json,sys; print(json.load(sys.stdin)['profiles']['bedrock']['backend'])")
    [ "$backend" = "bedrock" ] && pass "Extracts backend field" || fail "Wrong backend: $backend"

    sonnet=$(echo "$TEST_JSON" | $PYTHON -c "import json,sys; print(json.load(sys.stdin)['profiles']['bedrock']['pinnedModels']['sonnet'])")
    [ "$sonnet" = "us.anthropic.claude-sonnet-4-6" ] && pass "Extracts pinned model" || fail "Wrong model: $sonnet"

    env_out=$(echo "$TEST_JSON" | $PYTHON -c "import json,sys; [print(f'{k}={v}') for k,v in json.load(sys.stdin)['profiles']['bedrock']['env'].items()]")
    echo "$env_out" | grep -q "CLAUDE_CODE_USE_BEDROCK=1" && pass "Extracts env vars" || fail "Wrong env" "$env_out"
else
    skip "No python"
fi

# =============================================================================
section "Platform detection"
# =============================================================================
pass "Platform: $PLATFORM"

# =============================================================================
# Summary
# =============================================================================
echo ""
printf "${CY}============================================================${RS}\n"
TOTAL=$((PASS + FAIL + SKIP))
printf "  Results: ${GR}%d passed${RS}  ${RD}%d failed${RS}  ${YL}%d skipped${RS}  (%d total)\n" "$PASS" "$FAIL" "$SKIP" "$TOTAL"
printf "${CY}============================================================${RS}\n"
echo ""

[ "$FAIL" -gt 0 ] && exit 1
exit 0
