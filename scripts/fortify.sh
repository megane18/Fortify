#!/usr/bin/env bash
set -euo pipefail

# ============================================
# Fortify — Bash hardening orchestrator
# ============================================

# ---- Globals (defaults) ----
FORTIFY_TMP=""
FORTIFY_LOG=""
FORTIFY_REPORT=""
FORTIFY_HTML=""                 # <— path to generated HTML (set later)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PROFILE="$SCRIPT_DIR/profiles/default.profile"
GAMIFIED_SCRIPT="$SCRIPT_DIR/gamified_reports.sh"   # <— gamified UI if present
FORTIFY_AUTO_OPEN="true"        # <— NEW: default auto-open report

# CLI/env-resolved settings
PROFILE_PATH=""
REPORT_PATH=""
DRY_RUN="false"
VERBOSE="false"
NO_INTERACTIVE="false"
BACKEND_URL=""
TOKEN=""

# Checks / results
declare -ga CHECK_ORDER=()       # ordered list from profile
declare -gA CHECK_WEIGHTS=()     # id -> weight
declare -ga FORTIFY_CHECKS=()    # final run order (usually == CHECK_ORDER)
declare -ga FORTIFY_RESULTS=()   # JSON fragments

# Status caches (for scoring)
declare -gA STATUS_BEFORE=()     # id -> PASS|FAIL
declare -gA STATUS_AFTER=()      # id -> PASS|FAIL
SCORE_BEFORE=0
SCORE_AFTER=0

main() {
  parse_arguments "$@"
  init_environment               # tmp/log/report, source libs

  # traps AFTER env/log ready
  trap 'error_handler' ERR
  trap 'cleanup_on_exit' EXIT

  safety_check
  load_profile
  load_check_module
  run_all_check
  calculate_score
  generate_report

  # --- Reporting/UI: Prefer gamified (if available), else fallback HTML
  if [[ -f "$GAMIFIED_SCRIPT" ]]; then
    # shellcheck source=/dev/null
    source "$GAMIFIED_SCRIPT"
    # Terminal summary with Octocat + health bar + XP
    gamified_terminal_summary "$SCORE_BEFORE" "$SCORE_AFTER"
    # HTML report with ranks/badges (sets FORTIFY_HTML globally)
    generate_gamified_html_report
  else
    log_event "WARN" "Gamified reporter not found at $GAMIFIED_SCRIPT — using basic HTML."
    generate_html_report
  fi

  if [[ "$FORTIFY_AUTO_OPEN" == "true" ]]; then
    open_in_browser "$FORTIFY_HTML"
  else
    log_event "INFO" "Auto-open disabled (--no-open). HTML: $FORTIFY_HTML"
  fi

  print_human_summary
}

# --------------------------------------------
# CLI parsing
# --------------------------------------------
print_usage_and_exit() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -p, --profile <path>      Profile file (default: $DEFAULT_PROFILE)
  -o, --output  <path>      Report output (default: ../reports/report-<ts>.json)
  -n, --dry-run             Report only; do not apply fixes
  -v, --verbose             Verbose console logging
      --no-interactive      Fail instead of prompting for input
      --backend-url <url>   Backend ingest URL (optional)
      --token <token>       Backend auth token (optional)
      --open                Open the HTML report automatically (default)
      --no-open             Do not open the HTML report automatically
  -h, --help                Show this help
EOF
  exit "${1:-0}"
}

parse_arguments() {
  PROFILE_PATH="${FORTIFY_PROFILE:-}"
  REPORT_PATH="${FORTIFY_REPORT:-}"
  DRY_RUN="${FORTIFY_DRY_RUN:-false}"
  VERBOSE="${FORTIFY_VERBOSE:-false}"
  NO_INTERACTIVE="${FORTIFY_NO_INTERACTIVE:-false}"
  BACKEND_URL="${FORTIFY_BACKEND_URL:-}"
  TOKEN="${FORTIFY_TOKEN:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--profile)       [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 2; }; PROFILE_PATH="$2"; shift 2;;
      -o|--output)        [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 2; }; REPORT_PATH="$2"; shift 2;;
      -n|--dry-run)       DRY_RUN="true"; shift;;
      -v|--verbose)       VERBOSE="true"; shift;;
      --no-interactive)   NO_INTERACTIVE="true"; shift;;
      --backend-url)      [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 2; }; BACKEND_URL="$2"; shift 2;;
      --token)            [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 2; }; TOKEN="$2"; shift 2;;
      --open)             FORTIFY_AUTO_OPEN="true"; shift;;
      --no-open)          FORTIFY_AUTO_OPEN="false"; shift;;
      -h|--help)          print_usage_and_exit;;
      *)                  echo "Unknown argument: $1"; print_usage_and_exit 2;;
    esac
  done

  if [[ -z "$PROFILE_PATH" ]]; then
    PROFILE_PATH="$DEFAULT_PROFILE"
  fi
  if [[ -z "$REPORT_PATH" ]]; then
    mkdir -p "$SCRIPT_DIR/../reports"
    REPORT_PATH="$SCRIPT_DIR/../reports/report-$(date +"%Y%m%d-%H%M%S").json"
  fi
}

# --------------------------------------------
# Environment
# --------------------------------------------
init_environment() {
  FORTIFY_TMP="/tmp/fortify-$$"
  mkdir -p "$FORTIFY_TMP"

  FORTIFY_LOG="$FORTIFY_TMP/fortify.log"
  : > "$FORTIFY_LOG"

  mkdir -p "$SCRIPT_DIR/../reports"
  FORTIFY_REPORT="$REPORT_PATH"

  if [[ -d "$SCRIPT_DIR/lib" ]]; then
    for lib in "$SCRIPT_DIR/lib"/*.sh; do
      [[ -f "$lib" ]] && source "$lib"
    done
  fi

  log_event "INFO" "Environment initialized (tmp: $FORTIFY_TMP)"
}
# --------------------------------------------
# Safety
# --------------------------------------------
safety_check() {
  if [[ "$EUID" -ne 0 ]]; then
    log_event "ERROR" "Must run as root or with sudo"
    exit 1
  fi
  command -v uname >/dev/null 2>&1 || { log_event "ERROR" "uname missing"; exit 1; }
  local os; os=$(uname -s)
  [[ "$os" == "Linux" ]] || { log_event "ERROR" "Unsupported OS: $os"; exit 1; }
  local avail; avail=$(df / | awk 'NR==2{print $4}')
  [[ "$avail" -ge 50000 ]] || { log_event "ERROR" "Insufficient disk space (<50MB)"; exit 1; }
  log_event "INFO" "Safety checks passed"
}

# --------------------------------------------
# Profile (Version B)
# --------------------------------------------
load_profile() {
  local log_file="$FORTIFY_TMP/error.log.txt"

  if [[ ! -f "$PROFILE_PATH" ]]; then
    if [[ "$NO_INTERACTIVE" == "true" ]]; then
      echo "Profile not found and --no-interactive set: $PROFILE_PATH" | tee -a "$log_file" >&2
      exit 1
    fi
    echo "Profile not found: $PROFILE_PATH"
    read -r -p "Enter profile path: " user_profile
    PROFILE_PATH="$user_profile"
  fi
  [[ -f "$PROFILE_PATH" ]] || { echo "Error finding profile: $PROFILE_PATH" | tee -a "$log_file" >&2; exit 1; }

  CHECK_ORDER=()
  CHECK_WEIGHTS=()
  local DEFAULT_WEIGHT=1
  while IFS= read -r line; do
    line=${line%$'\r'}
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ $line =~ ^[[:space:]]*# ]] && continue
    local IFS=$' \t'
    read -r -a toks <<< "$line"
    local check_id="${toks[0]}"
    local maybe_weight="${toks[1]:-}"
    [[ -z "$check_id" ]] && continue
    CHECK_ORDER+=("$check_id")
    if [[ "$maybe_weight" =~ ^[0-9]+$ ]]; then
      CHECK_WEIGHTS["$check_id"]="$maybe_weight"
    else
      CHECK_WEIGHTS["$check_id"]="$DEFAULT_WEIGHT"
    fi
  done < "$PROFILE_PATH"

  [[ "${#CHECK_ORDER[@]}" -gt 0 ]] || { echo "Profile contains no checks: $PROFILE_PATH" | tee -a "$log_file" >&2; exit 1; }
  log_event "INFO" "Loaded ${#CHECK_ORDER[@]} checks from $PROFILE_PATH"
}

# --------------------------------------------
# Loader
# --------------------------------------------
register_check() {
  local cid="${1:-}"
  [[ -n "$cid" ]] && FORTIFY_CHECKS+=("$cid")
}

load_check_module() {
  if [[ -d "$SCRIPT_DIR/checks" ]]; then
    for f in "$SCRIPT_DIR/checks"/*.sh; do
      [[ -f "$f" ]] && source "$f"
    done
  fi
  FORTIFY_CHECKS=("${CHECK_ORDER[@]}")

  local missing=0
  for cid in "${FORTIFY_CHECKS[@]}"; do
    if ! declare -F "${cid}_check" >/dev/null 2>&1; then
      log_event "WARN" "Missing function: ${cid}_check"
      ((missing++))
    fi
    if ! declare -F "${cid}_fix" >/dev/null 2>&1; then
      log_event "WARN" "Missing function: ${cid}_fix (fixes will be skipped)"
    fi
  done
  [[ "$missing" -gt 0 ]] && log_event "WARN" "($missing) checks have no *_check; they will be skipped"
  log_event "INFO" "Ready to run ${#FORTIFY_CHECKS[@]} checks"
}

# --------------------------------------------
# Backup helpers
# --------------------------------------------
create_backup() {
  local cid="${1:-unknown}"
  local bdir="$FORTIFY_TMP/backups/$cid"
  mkdir -p "$bdir"
  log_event "INFO" "Created backup dir for $cid: $bdir"
  echo "$bdir"
}

restore_from_backup() { :; }

# --------------------------------------------
# Run checks (explicit before/after/notes logging)
# --------------------------------------------
run_all_check() {
  for cid in "${FORTIFY_CHECKS[@]}"; do
    if ! declare -F "${cid}_check" >/dev/null 2>&1; then
      log_event "WARN" "Skipping $cid (no ${cid}_check)"
      continue
    fi

    log_event "INFO" "Checking: $cid"
    local before after notes
    before="$("${cid}_check" || true)"; [[ -z "$before" ]] && before="FAIL"
    STATUS_BEFORE["$cid"]="$before"
    log_event "INFO" "$cid → before=$before"

    if [[ "$before" == "FAIL" ]]; then
      if [[ "$DRY_RUN" == "true" ]]; then
        notes="dry-run: would attempt fix"
        log_event "INFO" "Dry-run is ON — no changes will be made for $cid"
        after="$before"
      elif declare -F "${cid}_fix" >/dev/null 2>&1; then
        local bdir; bdir="$(create_backup "$cid")"
        log_event "INFO" "Applying fix for: $cid (backup: $bdir)"
        "${cid}_fix" || true
        after="$("${cid}_check" || true)"; [[ -z "$after" ]] && after="FAIL"
        if [[ "$after" == "PASS" ]]; then
          notes="fixed via ${cid}_fix"
          log_event "INFO" "✓ Fixed: $cid (after=$after)"
        else
          notes="fix attempted but still failing"
          log_event "WARN" "✗ Still failing: $cid (after=$after)"
        fi
      else
        notes="no fix function; skipped"
        log_event "WARN" "No fix available for $cid; leaving as-is"
        after="$before"
      fi
    else
      notes="already compliant"
      after="$before"
      log_event "INFO" "✓ Already secure: $cid"
    fi

    STATUS_AFTER["$cid"]="$after"

    local frag="{\"id\":\"$cid\",\"before\":\"$before\",\"after\":\"$after\",\"notes\":\"$notes\"}"
    FORTIFY_RESULTS+=("$frag")
  done
}

# --------------------------------------------
# Scoring
# --------------------------------------------
calculate_score() {
  local max_points=0 got_before=0 got_after=0
  for cid in "${CHECK_ORDER[@]}"; do
    local w="${CHECK_WEIGHTS[$cid]:-1}"; [[ "$w" =~ ^[0-9]+$ ]] || w=1
    max_points=$((max_points + w))
    [[ "${STATUS_BEFORE[$cid]:-FAIL}" == "PASS" ]] && got_before=$((got_before + w))
    [[ "${STATUS_AFTER[$cid]:-FAIL}" == "PASS"  ]] && got_after=$((got_after + w))
  done

  if [[ "$max_points" -gt 0 ]]; then
    SCORE_BEFORE=$((100 * got_before / max_points))
    SCORE_AFTER=$((100 * got_after / max_points))
  else
    SCORE_BEFORE=0; SCORE_AFTER=0
  fi
  log_event "INFO" "Security Score: ${SCORE_BEFORE}% → ${SCORE_AFTER}% (${got_after}/${max_points} pts)"
}

# --------------------------------------------
# Report (JSON)
# --------------------------------------------
generate_report() {
  local host ts
  host="$(hostname)"
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  {
    echo "{"
    echo "  \"host\": \"$host\","
    echo "  \"timestamp\": \"$ts\","
    echo "  \"profile\": \"${PROFILE_PATH}\","
    echo "  \"dry_run\": $([[ "$DRY_RUN" == "true" ]] && echo true || echo false),"
    echo "  \"score_before\": ${SCORE_BEFORE},"
    echo "  \"score_after\": ${SCORE_AFTER},"
    echo "  \"checks_total\": ${#FORTIFY_CHECKS[@]},"
    echo "  \"results\": ["
    local first=true
    for r in "${FORTIFY_RESULTS[@]}"; do
      if $first; then
        echo "    $r"
        first=false
      else
        echo "    ,$r"
      fi
    done
    echo "  ]"
    echo "}"
  } > "$FORTIFY_REPORT"

  log_event "INFO" "Report generated: $FORTIFY_REPORT"

  if [[ -n "$BACKEND_URL" ]]; then
    submit_to_backend || log_event "WARN" "Failed to submit report to backend"
  fi
}

# --------------------------------------------
# Basic HTML (fallback if gamified script not present)
# --------------------------------------------
generate_html_report() {
  # Requires jq; if missing, just warn and skip HTML
  if ! command -v jq >/dev/null 2>&1; then
    log_event "WARN" "jq not found; skipping HTML report (install: apt-get install -y jq)"
    FORTIFY_HTML=""
    return 0
  fi

  local base name
  base="$(basename "$FORTIFY_REPORT" .json)"
  name="${base}.html"
  FORTIFY_HTML="$(dirname "$FORTIFY_REPORT")/$name"

  # Extract summary fields
  local host ts sb sa
  host="$(jq -r '.host' "$FORTIFY_REPORT" 2>/dev/null || echo '-')"
  ts="$(jq -r '.timestamp' "$FORTIFY_REPORT" 2>/dev/null || echo '-')"
  sb="$(jq -r '.score_before' "$FORTIFY_REPORT" 2>/dev/null || echo '0')"
  sa="$(jq -r '.score_after' "$FORTIFY_REPORT" 2>/dev/null || echo '0')"
  local delta=$(( sa - sb ))
  [[ "$delta" -ge 0 ]] && delta="+$delta" || delta="$delta"

  # Build table rows via TSV from jq
  local rows_tsv
  rows_tsv="$(jq -r '.results[] | [.id, .before, .after, (.notes // "")] | @tsv' "$FORTIFY_REPORT" 2>/dev/null || echo "")"

  # Write HTML
  cat > "$FORTIFY_HTML" <<'HTML_HDR'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Fortify Report</title>
<style>
  :root { --ok:#0b8f3a; --bad:#b00020; --muted:#666; --line:#eee; --bg:#fafafa;}
  body { font-family: system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif; margin: 24px; }
  h1 { margin: 0 0 8px 0; }
  .meta { color: var(--muted); margin-bottom: 16px; }
  .card { border:1px solid var(--line); border-radius:12px; padding:16px; background:#fff; }
  .grid { display:grid; grid-template-columns:1fr 1fr; gap:16px; }
  .bar { height:12px; background:var(--bg); border-radius:8px; overflow:hidden; }
  .fill { height:100%; background:linear-gradient(90deg,#5f9,#3c9); }
  .fill2{ height:100%; background:linear-gradient(90deg,#f99,#d33); }
  table { width:100%; border-collapse:collapse; }
  th, td { text-align:left; padding:8px; border-bottom:1px solid var(--line); vertical-align:top; }
  .badge { padding:2px 8px; border-radius:6px; font-size:12px; display:inline-block; }
  .ok { background:#e6ffed; color:var(--ok); }
  .bad{ background:#ffecec; color:var(--bad);}
  .muted { color: var(--muted); }
  .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
  .mt16 { margin-top:16px; }
  .mt8  { margin-top:8px; }
</style>
</head>
<body>
HTML_HDR

  # Header
  {
    echo "<h1>Fortify Report</h1>"
    printf '<div class="meta">Host: <span class="mono">%s</span> • Generated: %s</div>\n' \
      "$(printf '%s' "$host" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')" \
      "$(printf '%s' "$ts" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"

    echo '<div class="grid">'
    # Before
    echo '<div class="card">'
    echo '<strong>Score (Before)</strong>'
    printf '<div class="mt8 bar"><div class="fill" style="width:%s%%"></div></div>\n' "$sb"
    printf '<div class="muted mt8">%s%%</div>\n' "$sb"
    echo '</div>'
    # After
    echo '<div class="card">'
    echo '<strong>Score (After)</strong>'
    printf '<div class="mt8 bar"><div class="fill2" style="width:%s%%"></div></div>\n' "$sa"
    printf '<div class="muted mt8">%s%% (Δ %s)</div>\n' "$sa" "$delta"
    echo '</div>'
    echo '</div>'

    echo '<div class="card mt16">'
    echo '<h3 style="margin-top:0">Results</h3>'
    echo '<div style="overflow-x:auto">'
    echo '<table>'
    echo '<thead><tr><th>Check</th><th>Before</th><th>After</th><th>Notes</th></tr></thead>'
    echo '<tbody>'
  } >> "$FORTIFY_HTML"

  # Rows
  if [[ -n "$rows_tsv" ]]; then
    # shellcheck disable=SC2162
    while IFS=$'\t' read -r id before after notes; do
      # basic HTML escape
      id=$(printf '%s' "$id" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
      before_badge_class="ok"; [[ "${before^^}" == "FAIL" ]] && before_badge_class="bad"
      after_badge_class="ok";  [[ "${after^^}"  == "FAIL" ]] && after_badge_class="bad"
      nesc=$(printf '%s' "${notes:-}" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
      {
        printf '<tr>'
        printf '<td class="mono">%s</td>' "$id"
        printf '<td><span class="badge %s">%s</span></td>' "$before_badge_class" "$before"
        printf '<td><span class="badge %s">%s</span></td>' "$after_badge_class" "$after"
        printf '<td class="muted">%s</td>' "$nesc"
        printf '</tr>\n'
      } >> "$FORTIFY_HTML"
    done <<< "$rows_tsv"
  fi

  # Footer
  cat >> "$FORTIFY_HTML" <<'HTML_FTR'
    </tbody></table>
    </div>
  </div>

  <p class="muted mt16">This is a static, self-contained report. You can share this HTML file or open it again later.</p>
</body>
</html>
HTML_FTR

  log_event "INFO" "HTML report generated: $FORTIFY_HTML"
}

# --------------------------------------------
# Try to open in default browser
# --------------------------------------------
# open_in_browser() {
#   local path="${1:-}"
#   [[ -n "$path" && -f "$path" ]] || { log_event "WARN" "No HTML report to open"; return 0; }

#   # Respect headless environments
#   if [[ "${FORTIFY_NO_OPEN:-false}" == "true" ]]; then
#     log_event "INFO" "Skipping auto-open (FORTIFY_NO_OPEN=true). Report: $path"
#     return 0
#   fi

#   if command -v xdg-open >/dev/null 2>&1; then xdg-open "$path" >/dev/null 2>&1 || true; return 0; fi
#   if command -v gio      >/dev/null 2>&1; then gio open "$path" >/dev/null 2>&1 || true; return 0; fi
#   if command -v wslview  >/dev/null 2>&1; then wslview "$path" >/dev/null 2>&1 || true; return 0; fi
#   if command -v open     >/dev/null 2>&1; then open "$path" >/dev/null 2>&1 || true; return 0; fi

#   log_event "INFO" "Open this in your browser: $path"
# }

# Run GUI commands as the invoking desktop user (not root)
run_as_desktop_user() {
  if [[ -n "${SUDO_USER:-}" && "$EUID" -eq 0 ]]; then
    sudo -u "$SUDO_USER" -E "$@"
  else
    "$@"
  fi
}

open_in_browser() {
  local path="${1:-}"
  [[ -n "$path" && -f "$path" ]] || { log_event "WARN" "No HTML report to open"; return 0; }

  # Respect headless environments
  if [[ "${FORTIFY_NO_OPEN:-false}" == "true" ]]; then
    log_event "INFO" "Skipping auto-open (FORTIFY_NO_OPEN=true). Report: $path"
    return 0
  fi

  # Normalize/resolve path (handles ../)
  local np="$path"
  if command -v realpath >/dev/null 2>&1; then
    np="$(realpath -m "$path" 2>/dev/null || echo "$path")"
  fi

  # --- Non-WSL (Linux/macOS) first
  if ! grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
    if command -v xdg-open >/dev/null 2>&1; then run_as_desktop_user xdg-open "$np" >/dev/null 2>&1 && return 0; fi
    if command -v gio      >/dev/null 2>&1; then run_as_desktop_user gio open "$np" >/dev/null 2>&1 && return 0; fi
    if command -v open     >/dev/null 2>&1; then run_as_desktop_user open "$np" >/dev/null 2>&1 && return 0; fi
    log_event "INFO" "Open this in your browser: $np"
    return 0
  fi

  # --- WSL branch
  # Try wslview (best UX)
  if command -v wslview >/dev/null 2>&1; then
    run_as_desktop_user wslview "$np" >/dev/null 2>&1 && return 0
  fi

  # Convert to Windows path
  local winpath=""
  if command -v wslpath >/dev/null 2>&1; then
    winpath="$(wslpath -w "$np" 2>/dev/null || echo "")"
  fi
  [[ -z "$winpath" ]] && winpath="$np"

  # Try explorer.exe (explicit absolute path and PATH fallback)
  if command -v explorer.exe >/dev/null 2>&1; then
    run_as_desktop_user explorer.exe "$winpath" >/dev/null 2>&1 && return 0
  fi
  if [[ -x /mnt/c/Windows/explorer.exe ]]; then
    run_as_desktop_user /mnt/c/Windows/explorer.exe "$winpath" >/dev/null 2>&1 && return 0
  fi

  # Try cmd.exe /C start (works even if explorer.exe not in PATH)
  if command -v cmd.exe >/dev/null 2>&1; then
    # Empty title ("") avoids treating path as the title.
    run_as_desktop_user cmd.exe /C start "" "$winpath" >/dev/null 2>&1 && return 0
  fi

  # Try PowerShell
  if command -v powershell.exe >/dev/null 2>&1; then
    run_as_desktop_user powershell.exe -NoProfile -Command "Start-Process '$winpath'" >/dev/null 2>&1 && return 0
  fi

  log_event "INFO" "Open this in your browser: $np"
}


# --------------------------------------------
# Pretty console summary
# --------------------------------------------
print_human_summary() {
  echo
  echo "=== Fortify Summary ==="
  echo "Profile:  $PROFILE_PATH"
  echo "Dry-run:  $DRY_RUN"
  echo "Report:   $FORTIFY_REPORT"
  [[ -n "$FORTIFY_HTML" ]] && echo "HTML:     $FORTIFY_HTML"
  echo "Score:    ${SCORE_BEFORE}% → ${SCORE_AFTER}%"
  echo "Results:"
  for r in "${FORTIFY_RESULTS[@]}"; do
    local id before after notes
    id="$(echo "$r" | sed -E 's/.*"id":"([^"]+)".*/\1/')" || true
    before="$(echo "$r" | sed -E 's/.*"before":"([^"]+)".*/\1/')" || true
    after="$(echo "$r" | sed -E 's/.*"after":"([^"]+)".*/\1/')" || true
    notes="$(echo "$r" | sed -E 's/.*"notes":"([^"]+)".*/\1/')" || true
    echo "  - $id: $before → $after  ($notes)"
  done
  echo "======================="
}

# --------------------------------------------
# Backend (optional)
# --------------------------------------------
submit_to_backend() {
  command -v curl >/dev/null 2>&1 || { log_event "WARN" "curl not available"; return 1; }
  local auth=()
  [[ -n "$TOKEN" ]] && auth=(-H "Authorization: Bearer $TOKEN")
  log_event "INFO" "Submitting report to backend: $BACKEND_URL"
  if curl -s -X POST -H "Content-Type: application/json" "${auth[@]}" -d @"$FORTIFY_REPORT" "$BACKEND_URL" >/dev/null; then
    log_event "INFO" "Report submitted to backend"
  else
    log_event "WARN" "Backend submission failed"
    return 1
  fi
}

# --------------------------------------------
# Error / Cleanup / Log
# --------------------------------------------
error_handler() {
  local code=$?
  local cmd="${BASH_COMMAND:-unknown}"
  if [[ -z "${FORTIFY_LOG:-}" || ! -f "$FORTIFY_LOG" ]]; then
    echo "[ERROR] Failed at: $cmd (exit $code)" >&2
  else
    log_event "ERROR" "Failed at: $cmd (exit $code)"
  fi
  if [[ -z "${FORTIFY_REPORT:-}" || ! -f "$FORTIFY_REPORT" ]]; then
    mkdir -p "$SCRIPT_DIR/../reports"
    FORTIFY_REPORT="$SCRIPT_DIR/../reports/report-$(date +"%Y%m%d-%H%M%S")-partial.json"
    generate_report || true
  fi
  exit "$code"
}

cleanup_on_exit() {
  if [[ -n "$FORTIFY_TMP" && -d "$FORTIFY_TMP" ]]; then
    rm -rf "$FORTIFY_TMP"
  fi
  echo "[INFO] Fortify cleanup complete"
}

log_event() {
  local level="${1:-INFO}"
  local message="${2:-}"
  local ts; ts="$(date +"%Y-%m-%d %H:%M:%S")"

  # Console (show INFO only if verbose)
  if [[ "$level" != "INFO" || "$VERBOSE" == "true" ]]; then
    case "$level" in
      ERROR) echo -e "[${ts}] [\033[31m${level}\033[0m] $message" >&2;;
      WARN)  echo -e "[${ts}] [\033[33m${level}\033[0m] $message";;
      INFO)  echo -e "[${ts}] [\033[32m${level}\033[0m] $message";;
      *)     echo -e "[${ts}] [${level}] $message";;
    esac
  fi
  # File (always)
  if [[ -n "$FORTIFY_LOG" ]]; then
    echo "[${ts}] [${level}] $message" >> "$FORTIFY_LOG"
  fi
}

# --------------------------------------------
# Go!
# --------------------------------------------
main "$@"
