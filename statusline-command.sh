#!/usr/bin/env bash
# Claude Code statusline - cross-platform bash version
# Works on: macOS, Linux, Windows (Git Bash / WSL)
# Dependencies: python3 OR python (3.x) OR jq

input=$(cat)

# --- Find JSON parser --------------------------------------------------------
PYTHON=""
if command -v python3 &>/dev/null; then PYTHON="python3"
elif command -v python &>/dev/null; then
    python -c "import sys; sys.exit(0 if sys.version_info >= (3,) else 1)" 2>/dev/null && PYTHON="python"
fi
if [ -z "$PYTHON" ] && ! command -v jq &>/dev/null; then
    printf 'statusline: needs python3 or jq\n'; exit 1
fi

# --- Palette (24-bit RGB) ----------------------------------------------------
Blue='\033[38;2;93;173;226m'         # #5DADE2 — model name, %, bar fill
Mint='\033[38;2;160;228;203m'        # #A0E4CB — rate limit values, version
Dim='\033[38;2;74;74;90m'            # #4A4A5A — structural labels, separators
White='\033[38;2;208;208;208m'       # #D0D0D0 — session/token values
Green='\033[38;2;87;212;122m'        # #57D47A — +lines
Red='\033[38;2;224;108;117m'         # #E06C75 — -lines, warnings
Amber='\033[38;2;229;192;123m'       # #E5C07B — medium warnings, compact
Black='\033[38;2;0;0;0m'             # badge text
BgBlue='\033[48;2;93;173;226m'       # badge bg PERSONAL
BgAmber='\033[48;2;229;192;123m'     # badge bg BEDROCK
BgGreen='\033[48;2;87;212;122m'      # badge bg FOUNDRY
Teal='\033[38;2;43;186;197m'         # #2BBAC5 — ↓ input arrow
Coral='\033[38;2;239;89;111m'        # #EF596F — ↑ output arrow
RS='\033[0m'
BD='\033[1m'

Col1W=13
Col2W=25
Sep1=" $(printf '%b' "${Dim}")┊$(printf '%b' "${RS}") "

# --- Helpers ------------------------------------------------------------------
pct_color() {
    local pct="$1"
    [ -z "$pct" ] && { printf '%s' "$Blue"; return; }
    local int; int=$(printf "%.0f" "$pct" 2>/dev/null) || int=0
    if   [ "$int" -ge 80 ]; then printf '%s' "$Red"
    elif [ "$int" -ge 60 ]; then printf '%s' "$Amber"
    else printf '%s' "$Blue"; fi
}

fmt_duration() {
    local ms="$1"
    [ -z "$ms" ] || [ "$ms" = "0" ] && return
    local s=$(( ${ms%%.*} / 1000 ))
    if [ "$s" -ge 86400 ]; then printf '%dd%dh' "$((s/86400))" "$(((s%86400)/3600))"
    elif [ "$s" -ge 3600 ]; then printf '%dh%dm' "$((s/3600))" "$(((s%3600)/60))"
    elif [ "$s" -ge 60 ]; then printf '%dm%ds' "$((s/60))" "$((s%60))"
    else printf '%ds' "$s"; fi
}

fmt_tokens() {
    local val="$1"
    [ -z "$val" ] || [ "$val" = "0" ] && { printf '0'; return; }
    local n=${val%%.*}
    if [ "$n" -ge 1000000 ]; then printf '%s.%sM' "$((n/1000000))" "$(((n%1000000)/100000))"
    elif [ "$n" -ge 1000 ]; then
        local k=$((n/1000)) f=$(((n%1000)/100))
        [ "$f" -gt 0 ] && printf '%s.%sk' "$k" "$f" || printf '%sk' "$k"
    else printf '%s' "$n"; fi
}

make_bar() {
    local pct="$1" w="$2"
    local pi; pi=$(printf "%.0f" "$pct" 2>/dev/null) || pi=0
    local f=$(( pi * w / 100 )); [ "$f" -gt "$w" ] && f=$w; [ "$f" -lt 0 ] && f=0
    local e=$(( w - f )) bf="" be=""
    for ((i=0;i<f;i++)); do bf="${bf}▆"; done
    for ((i=0;i<e;i++)); do be="${be}▆"; done
    printf '%b' "${Blue}${bf}${Dim}${be}${RS}"
}

fmt_timestamp() {
    local ts="$1" fmt="$2"; [ -z "$ts" ] && return
    date -d "@$ts" +"$fmt" 2>/dev/null && return
    date -r "$ts" +"$fmt" 2>/dev/null && return
}

# Pad ANSI string to fixed visible width
pad_col() {
    local ansi="$1" vis_len="$2" target="$3"
    local pad=$(( target - vis_len ))
    [ "$pad" -lt 0 ] && pad=0
    printf '%b%*s' "$ansi" "$pad" ""
}

# --- Parse JSON ---------------------------------------------------------------
if [ -n "$PYTHON" ]; then
    eval "$($PYTHON -c "
import json,sys
d=json.load(sys.stdin)
def g(*k):
    o=d
    for i in k:
        if isinstance(o,dict): o=o.get(i)
        else: return ''
    return '' if o is None else str(o)
for k,v in {
    'model':g('model','display_name'),'version':g('version'),
    'ctx_size':g('context_window','context_window_size'),
    'used_pct':g('context_window','used_percentage'),
    'cache_r':g('context_window','current_usage','cache_read_input_tokens'),
    'total_in':g('context_window','total_input_tokens'),
    'total_out':g('context_window','total_output_tokens'),
    'five_pct':g('rate_limits','five_hour','used_percentage'),
    'five_reset':g('rate_limits','five_hour','resets_at'),
    'week_pct':g('rate_limits','seven_day','used_percentage'),
    'week_reset':g('rate_limits','seven_day','resets_at'),
    'cost':g('cost','total_cost_usd'),
    'session_dur':g('cost','total_duration_ms'),
    'lines_add':g('cost','total_lines_added') or '0',
    'lines_del':g('cost','total_lines_removed') or '0',
}.items():
    print(f\"{k}='{v.replace(chr(39),chr(39)+chr(92)+chr(92)+chr(39))}'\")
" <<< "$input" 2>/dev/null)"
else
    eval "$(echo "$input" | jq -r '
        @sh "model=\(.model.display_name // "Unknown")",
        @sh "version=\(.version // "" | tostring)",
        @sh "ctx_size=\(.context_window.context_window_size // "" | tostring)",
        @sh "used_pct=\(.context_window.used_percentage // "" | tostring)",
        @sh "cache_r=\(.context_window.current_usage.cache_read_input_tokens // "0" | tostring)",
        @sh "total_in=\(.context_window.total_input_tokens // "0" | tostring)",
        @sh "total_out=\(.context_window.total_output_tokens // "0" | tostring)",
        @sh "five_pct=\(.rate_limits.five_hour.used_percentage // "" | tostring)",
        @sh "five_reset=\(.rate_limits.five_hour.resets_at // "" | tostring)",
        @sh "week_pct=\(.rate_limits.seven_day.used_percentage // "" | tostring)",
        @sh "week_reset=\(.rate_limits.seven_day.resets_at // "" | tostring)",
        @sh "cost=\(.cost.total_cost_usd // "" | tostring)",
        @sh "session_dur=\(.cost.total_duration_ms // "0" | tostring)",
        @sh "lines_add=\(.cost.total_lines_added // "0" | tostring)",
        @sh "lines_del=\(.cost.total_lines_removed // "0" | tostring)"
    ' 2>/dev/null)"
fi

[ -z "$model" ] && { printf "${Red}[ERR]${RS} parse failed\n"; exit 1; }

# Detect profile
is_api=0; badge_bg="$BgBlue"; badge_text="PERSONAL"
[ "$CLAUDE_CODE_USE_BEDROCK" = "1" ] && { is_api=1; badge_bg="$BgAmber"; badge_text="BEDROCK"; }
[ "$CLAUDE_CODE_USE_FOUNDRY" = "1" ] && { is_api=1; badge_bg="$BgGreen"; badge_text="FOUNDRY"; }

# Clean model name
model_clean=$(echo "$model" | sed -E 's/^\s*Claude\s+//' | sed -E 's/ *\([0-9]+[kKmM]? *context\)//')
ctx_label=""
[ -n "$ctx_size" ] && { [ "${ctx_size%%.*}" -ge 1000000 ] 2>/dev/null && ctx_label="1M" || ctx_label="200k"; }

# Widen col2 when /compact warning is needed
if [ -n "$used_pct" ]; then
    ci=$(printf "%.0f" "$used_pct" 2>/dev/null) || ci=0
    [ "$ci" -ge 70 ] && Col2W=35
fi

# === LINE 1: col1=badge  col2=model(ctx)  col3=version =======================
badge_vis=" ${badge_text} "
c1L1=$(pad_col "${Black}${badge_bg}${badge_vis}${RS}" ${#badge_vis} $Col1W)

model_raw="${model_clean}"
[ -n "$ctx_label" ] && model_raw="${model_raw} (${ctx_label})"
c2L1_ansi="${Blue}${model_clean}${RS}"
[ -n "$ctx_label" ] && c2L1_ansi="${c2L1_ansi} ${Dim}(${ctx_label})${RS}"
c2L1=$(pad_col "$c2L1_ansi" ${#model_raw} $Col2W)

c3L1=""
[ -n "$version" ] && c3L1="${Dim}v${RS}${Mint}${version}${RS}"

line1="${c1L1}${Sep1}${c2L1}${Sep1}${c3L1}"

# === LINE 2: col1=5h/cache  col2=context bar  col3=+/- =======================

# Col 1
if [ -n "$five_pct" ]; then
    fc=$(pct_color "$five_pct"); printf -v fh "%.0f" "$five_pct"
    raw1="5h ${fh}%"; ansi1="${Dim}5h${RS} ${fc}${fh}%${RS}"
    if [ -n "$five_reset" ]; then
        rt=$(fmt_timestamp "$five_reset" "%H:%M")
        [ -n "$rt" ] && { raw1="${raw1} →${rt}"; ansi1="${ansi1} ${Dim}→${rt}${RS}"; }
    fi
    c1L2=$(pad_col "$ansi1" ${#raw1} $Col1W)
elif [ "$is_api" = "1" ] && [ "${cache_r:-0}" != "0" ] && [ "${total_in:-0}" != "0" ]; then
    cp=$(( ${cache_r%%.*} * 100 / ${total_in%%.*} ))
    raw1="cache ${cp}%"
    c1L2=$(pad_col "${Dim}cache${RS} ${Mint}${cp}%${RS}" ${#raw1} $Col1W)
else
    c1L2=$(printf '%*s' "$Col1W" "")
fi

# Col 2: context bar
compact_warn=""
compact_vis=""
c2L2=""
if [ -n "$used_pct" ]; then
    cc=$(pct_color "$used_pct")
    uf=$(printf "%.1f" "$used_pct" 2>/dev/null)
    bar=$(make_bar "$used_pct" 10)
    ctx_raw="context xxxxxxxxxx ${uf}%"
    c2L2=$(pad_col "${Dim}context${RS} ${bar} ${cc}${BD}${uf}%${RS}" ${#ctx_raw} $Col2W)
    ci=$(printf "%.0f" "$used_pct" 2>/dev/null) || ci=0
    if   [ "$ci" -ge 80 ]; then compact_warn="${Amber}${BD}▸ /compact now${RS} "; compact_vis="▸ /compact now "
    elif [ "$ci" -ge 70 ]; then compact_warn="${Amber}${BD}▸ /compact soon${RS} "; compact_vis="▸ /compact soon "
    fi
fi

# Col 3: +/-
c3L2="${Green}+${lines_add:-0}${RS}${Dim}/${RS}${Red}-${lines_del:-0}${RS}"

line2="${c1L2}${Sep1}${c2L2}${Sep1}${c3L2}"

# === LINE 3: col1=7d/cost  col2=[compact]session  col3=↓↑ ====================

# Col 1
if [ -n "$week_pct" ]; then
    wc=$(pct_color "$week_pct"); printf -v wd "%.0f" "$week_pct"
    raw1="7d ${wd}%"; ansi1="${Dim}7d${RS} ${wc}${wd}%${RS}"
    if [ -n "$week_reset" ]; then
        rt=$(fmt_timestamp "$week_reset" "%m/%d")
        [ -n "$rt" ] && { raw1="${raw1} →${rt}"; ansi1="${ansi1} ${Dim}→${rt}${RS}"; }
    fi
    c1L3=$(pad_col "$ansi1" ${#raw1} $Col1W)
elif [ "$is_api" = "1" ] && [ -n "$cost" ] && [ "$cost" != "0" ]; then
    cf=$(printf "%.2f" "$cost" 2>/dev/null || echo "$cost")
    raw1="cost \$${cf}"
    c1L3=$(pad_col "${Dim}cost${RS} ${White}\$${cf}${RS}" ${#raw1} $Col1W)
else
    c1L3=$(printf '%*s' "$Col1W" "")
fi

# Col 2: [compact warning] + session
sess_ansi="${compact_warn}"
sess_vis="${compact_vis}"
if [ -n "$session_dur" ] && [ "$session_dur" != "0" ]; then
    sf=$(fmt_duration "$session_dur")
    if [ -n "$sf" ]; then
        sess_vis="${sess_vis}session ${sf}"
        sess_ansi="${sess_ansi}${Dim}session${RS} ${White}${sf}${RS}"
    fi
fi
c2L3=$(pad_col "$sess_ansi" ${#sess_vis} $Col2W)

# Col 3: ↓in ↑out
eff_in=$(( ${total_in%%.*} + ${cache_r%%.*} ))
in_fmt=$(fmt_tokens "$eff_in")
out_fmt=$(fmt_tokens "${total_out:-0}")
c3L3="${Teal}↓${RS}${White}${in_fmt}${RS} ${Coral}↑${RS}${White}${out_fmt}${RS}"

line3="${c1L3}${Sep1}${c2L3}${Sep1}${c3L3}"

# --- Output -------------------------------------------------------------------
# On startup (no interaction yet), only show line 1
has_interaction=0
[ "${total_in:-0}" != "0" ] && has_interaction=1
[ "${total_out:-0}" != "0" ] && has_interaction=1

[ -n "$line1" ] && printf '%b\n' "$line1"
if [ "$has_interaction" = "1" ]; then
    [ -n "$line2" ] && printf '%b\n' "$line2"
    [ -n "$line3" ] && printf '%b\n' "$line3"
fi
exit 0
