# Claude Code statusline - Windows PowerShell version
# Compatible with PowerShell 5.1+ and PowerShell 7+

param()
$input_data = $Input | Out-String

$e = [char]27
function C($r,$g,$b) { return "$e[38;2;${r};${g};${b}m" }
function Bg($r,$g,$b) { return "$e[48;2;${r};${g};${b}m" }

# Palette
$Blue    = C 93 173 226        # #5DADE2 — model name, percentages, bar fill
$Mint    = C 160 228 203       # #A0E4CB — rate limit values, version
$Dim     = C 74 74 90          # #4A4A5A — structural labels, separators, bar empty
$White   = C 208 208 208       # #D0D0D0 — session/token values
$VGreen  = C 152 195 121       # #98C379 — version number (unused, kept)
$Green   = C 87 212 122        # #57D47A — +lines
$Red     = C 224 108 117       # #E06C75 — -lines, warnings
$Amber   = C 229 192 123       # #E5C07B — medium warnings, compact
$Black   = C 0 0 0             # badge text
$BgBlue  = Bg 93 173 226       # badge bg PERSONAL
$BgAmber = Bg 229 192 123      # badge bg BEDROCK
$BgGreen = Bg 87 212 122       # badge bg FOUNDRY
$Teal    = C 43 186 197        # #2BBAC5 — ↓ input arrow
$Coral   = C 239 89 111        # #EF596F — ↑ output arrow
$RS      = "$e[0m"
$BD      = "$e[1m"

$Col1W   = 13                  # column 1 width (badge/5h/7d/cost)
$Col2W   = 30                  # column 2 width (model/context/session)

$Sep     = " "
$Sep1    = " ${Dim}$([char]0x250A)${RS} "   # ┊ dotted vertical

function Get-PctColor($pct) {
    if ([string]::IsNullOrEmpty($pct)) { return $Blue }
    $int = [int][math]::Round([double]$pct)
    if ($int -ge 80) { return $Red }
    if ($int -ge 60) { return $Amber }
    return $Blue
}

function Format-Duration($ms) {
    if ([string]::IsNullOrEmpty($ms) -or $ms -eq "0") { return "" }
    $total_s = [int]([double]$ms / 1000)
    if ($total_s -ge 86400) { $d=[int]($total_s/86400); $h=[int](($total_s%86400)/3600); return "${d}d${h}h" }
    elseif ($total_s -ge 3600) { $h=[int]($total_s/3600); $m=[int](($total_s%3600)/60); return "${h}h${m}m" }
    elseif ($total_s -ge 60) { $m=[int]($total_s/60); $s=$total_s%60; return "${m}m${s}s" }
    else { return "${total_s}s" }
}

function Format-Tokens($val) {
    if ([string]::IsNullOrEmpty($val) -or $val -eq "0") { return "0" }
    $num = [double]$val
    if ($num -ge 1000000) { return ([math]::Round($num/1000000,1)).ToString("0.0")+"M" }
    elseif ($num -ge 1000) { return ([math]::Round($num/1000,1)).ToString("0.#")+"k" }
    else { return [math]::Floor($num).ToString() }
}

function Make-Bar([double]$Pct, [int]$Width) {
    $filled = [math]::Min([math]::Max([int][math]::Floor($Pct/100*$Width),0),$Width)
    $empty = $Width - $filled
    $barF = [string]::new([char]0x2586, $filled)
    $barE = [string]::new([char]0x2586, $empty)
    return "${Blue}${barF}${Dim}${barE}${RS}"
}

# Pad a string (with ANSI) to fixed visible width
function Pad-Col($ansiStr, $visibleLen, $targetW) {
    $pad = [math]::Max(0, $targetW - $visibleLen)
    return $ansiStr + (" " * $pad)
}

# --- Parse JSON --------------------------------------------------------------
try { $data = $input_data | ConvertFrom-Json }
catch { Write-Host "${Red}[ERR] parse failed${RS}"; exit 1 }

$model     = if ($data.model.display_name) { $data.model.display_name } else { "Unknown" }
$version   = if ($data.version) { $data.version } else { "" }
$ctx_size  = if ($data.context_window.context_window_size) { $data.context_window.context_window_size } else { "" }
$used_pct  = if ($data.context_window.used_percentage) { $data.context_window.used_percentage } else { "" }
$cache_r   = if ($data.context_window.current_usage.cache_read_input_tokens) { $data.context_window.current_usage.cache_read_input_tokens } else { "0" }
$total_in  = if ($data.context_window.total_input_tokens) { $data.context_window.total_input_tokens } else { "0" }
$total_out = if ($data.context_window.total_output_tokens) { $data.context_window.total_output_tokens } else { "0" }
$five_pct  = if ($data.rate_limits.five_hour.used_percentage) { $data.rate_limits.five_hour.used_percentage } else { "" }
$five_reset = if ($data.rate_limits.five_hour.resets_at) { $data.rate_limits.five_hour.resets_at } else { "" }
$week_pct  = if ($data.rate_limits.seven_day.used_percentage) { $data.rate_limits.seven_day.used_percentage } else { "" }
$week_reset = if ($data.rate_limits.seven_day.resets_at) { $data.rate_limits.seven_day.resets_at } else { "" }
$cost      = if ($data.cost.total_cost_usd) { $data.cost.total_cost_usd } else { "" }
$session_dur = if ($data.cost.total_duration_ms) { $data.cost.total_duration_ms } else { "0" }
$lines_add = if ($data.cost.total_lines_added) { $data.cost.total_lines_added } else { "0" }
$lines_del = if ($data.cost.total_lines_removed) { $data.cost.total_lines_removed } else { "0" }

$model_clean = $model -replace '^\s*Claude\s+','' -replace '\s*\(\d+[kKmM]?\s*context\)',''
$ctx_label = ""
if ($ctx_size) { $ctx_label = if ([double]$ctx_size -ge 1000000) { "1M" } else { "200k" } }

$is_api = $false; $badge_bg = $BgBlue; $badge_text = "PERSONAL"
if ($env:CLAUDE_CODE_USE_BEDROCK -eq "1") {
    $is_api = $true; $badge_bg = $BgAmber; $badge_text = "BEDROCK"
} elseif ($env:CLAUDE_CODE_USE_FOUNDRY -eq "1") {
    $is_api = $true; $badge_bg = $BgGreen; $badge_text = "FOUNDRY"
}

# === LINE 1: col1=badge  col2=model(ctx)  col3=version ======================
$badge_visible = " ${badge_text} "
$c1L1 = Pad-Col "${Black}${badge_bg}${badge_visible}${RS}" $badge_visible.Length $Col1W

$model_raw = "${model_clean}"
if ($ctx_label) { $model_raw += " (${ctx_label})" }
$c2L1_ansi = "${Blue}${model_clean}${RS}"
if ($ctx_label) { $c2L1_ansi += " ${Dim}(${ctx_label})${RS}" }
$c2L1 = Pad-Col $c2L1_ansi $model_raw.Length $Col2W

$c3L1 = ""
if ($version) { $c3L1 = "${Dim}v${RS}${Mint}${version}${RS}" }

$line1 = "${c1L1}${Sep1}${c2L1}${Sep1}${c3L1}"

# === LINE 2: col1=5h/cache  col2=context bar  col3=+/- ======================

# Col 1: 5h rate limit (Personal) or cache% (API) or empty
if ($five_pct) {
    $fh = [int][math]::Round([double]$five_pct)
    $fc = if ($fh -ge 80) { $Red } elseif ($fh -ge 60) { $Amber } else { $Mint }
    $raw1 = "5h ${fh}%"
    $ansi1 = "${Dim}5h${RS} ${fc}${fh}%${RS}"
    if ($five_reset) {
        try { $rt = [DateTimeOffset]::FromUnixTimeSeconds([long]$five_reset).LocalDateTime.ToString("HH:mm")
              $raw1 += " " + [char]0x2192 + $rt
              $ansi1 += " ${Dim}" + [char]0x2192 + "${rt}${RS}" } catch {}
    }
    $c1L2 = Pad-Col $ansi1 $raw1.Length $Col1W
} elseif ($is_api -and $cache_r -ne "0" -and $total_in -ne "0") {
    # Show cache hit% for API profiles
    $cp = [int]([math]::Floor([double]$cache_r / [double]$total_in * 100))
    $raw1 = "cache ${cp}%"
    $c1L2 = Pad-Col "${Dim}cache${RS} ${Mint}${cp}%${RS}" $raw1.Length $Col1W
} else {
    $c1L2 = " " * $Col1W
}

# Col 2: context bar
$compact_warn = ""
$c2L2 = ""
if ($used_pct) {
    $ctx_col = Get-PctColor $used_pct
    $used_fmt = [math]::Round([double]$used_pct,1).ToString("0.0")
    $ctx_bar = Make-Bar ([double]$used_pct) 10
    $ctx_raw = "context " + ("x" * 10) + " ${used_fmt}%"
    $c2L2 = Pad-Col ("${Dim}context${RS} ${ctx_bar} ${ctx_col}${BD}${used_fmt}%${RS}") $ctx_raw.Length $Col2W
    $ctx_int = [int][math]::Round([double]$used_pct)
    if ($ctx_int -ge 80)     { $compact_warn = "${Amber}${BD}" + [char]0x25B8 + " /compact now${RS} " }
    elseif ($ctx_int -ge 70) { $compact_warn = "${Amber}${BD}" + [char]0x25B8 + " /compact soon${RS} " }
}

# Col 3: +/-
$c3L2 = "${Green}+${lines_add}${RS}${Dim}/${RS}${Red}-${lines_del}${RS}"

$line2 = "${c1L2}${Sep1}${c2L2}${Sep1}${c3L2}"

# === LINE 3: col1=7d/cost  col2=[compact]session  col3=↓↑ ===================

# Col 1: 7d rate limit (Personal) or cost (API) or empty
if ($week_pct) {
    $wd = [int][math]::Round([double]$week_pct)
    $wc = if ($wd -ge 80) { $Red } elseif ($wd -ge 60) { $Amber } else { $Mint }
    $raw1 = "7d ${wd}%"
    $ansi1 = "${Dim}7d${RS} ${wc}${wd}%${RS}"
    if ($week_reset) {
        try { $rt = [DateTimeOffset]::FromUnixTimeSeconds([long]$week_reset).LocalDateTime.ToString("MM/dd")
              $raw1 += " " + [char]0x2192 + $rt
              $ansi1 += " ${Dim}" + [char]0x2192 + "${rt}${RS}" } catch {}
    }
    $c1L3 = Pad-Col $ansi1 $raw1.Length $Col1W
} elseif ($is_api -and $cost -and $cost -ne "0") {
    $cost_fmt = [math]::Round([double]$cost,2).ToString("0.00")
    $raw1 = "`$${cost_fmt}"
    $c1L3 = Pad-Col "${Dim}cost${RS} ${White}`$${cost_fmt}${RS}" ("cost " + $raw1).Length $Col1W
} else {
    $c1L3 = " " * $Col1W
}

# Col 2: [compact warning] + session, padded to Col2W
$sess_ansi = $compact_warn
$sess_visible = ""
if ($compact_warn) {
    $ci = [int][math]::Round([double]$used_pct)
    if ($ci -ge 80) { $sess_visible += ([char]0x25B8).ToString() + " /compact now " }
    else { $sess_visible += ([char]0x25B8).ToString() + " /compact soon " }
}
if ($session_dur -and $session_dur -ne "0") {
    $sf = Format-Duration $session_dur
    if ($sf) {
        $sess_visible += "session ${sf}"
        $sess_ansi += "${Dim}session${RS} ${White}${sf}${RS}"
    }
}
$c2L3 = Pad-Col $sess_ansi $sess_visible.Length $Col2W

# Col 3: ↓in ↑out
$in_fmt = Format-Tokens $total_in
$out_fmt = Format-Tokens $total_out
$c3L3 = "${Teal}$([char]0x2193)${RS}${White}${in_fmt}${RS} ${Coral}$([char]0x2191)${RS}${White}${out_fmt}${RS}"

$line3 = "${c1L3}${Sep1}${c2L3}${Sep1}${c3L3}"

# --- Output ------------------------------------------------------------------
# On startup (no interaction yet), only show line 1
$has_interaction = ($total_in -ne "0") -or ($total_out -ne "0")

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
if ($line1) { Write-Host $line1 }
if ($has_interaction) {
    if ($line2) { Write-Host $line2 }
    if ($line3) { Write-Host $line3 }
}
exit 0
