#!/usr/bin/env bash
# tests/e2e.sh — End-to-end smoke test for Fortify
# - Runs scripts/fortify.sh in --dry-run to avoid changing the system
# - Validates JSON/HTML outputs (uses jq if present)
# - Supports fast --smoke mode with stub checks
# - Auto-detects runner path; override with --runner
#
# Usage:
#   tests/e2e.sh
#   tests/e2e.sh --profile scripts/profiles/server.profile
#   tests/e2e.sh --runner scripts/fortify.sh -v
#   tests/e2e.sh --smoke
#
set -euo pipefail

# ----------------- CONFIG / DEFAULTS -----------------
VERBOSE=0
MODE="full"               # or "smoke"
PROFILE_PATH=""
RUNNER=""                 # autodetected if empty
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORTS_DIR="$REPO_DIR/reports"
TMP_DIR="$(mktemp -d -t fortify-e2e-XXXXXX)"
JQ_OK=0
[[ -x "$(command -v jq || true)" ]] && JQ_OK=1

# ----------------- UTILS -----------------
log()  { echo -e "[$(date +'%H:%M:%S')] $*"; }
pass() { echo -e "\033[32m✔\033[0m $*"; }
fail() { echo -e "\033[31m✘\033[0m $*"; exit 1; }
info() { [[ $VERBOSE -eq 1 ]] && echo -e "\033[36mℹ\033[0m $*"; }
cleanup(){ [[ -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

usage(){
  cat <<USAGE
Usage: $(basename "$0") [--smoke] [--profile PATH] [--runner PATH] [-v|--verbose]
Examples:
  tests/e2e.sh
  tests/e2e.sh --profile scripts/profiles/server.profile
  tests/e2e.sh --runner scripts/fortify.sh -v
  tests/e2e.sh --smoke
USAGE
}

# ----------------- ARGS -----------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --smoke) MODE="smoke"; shift;;
    --profile) PROFILE_PATH="${2:-}"; shift 2;;
    --runner) RUNNER="${2:-}"; shift 2;;
    -v|--verbose) VERBOSE=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

# ----------------- RUNNER AUTODETECT -----------------
if [[ -z "${RUNNER:-}" ]]; then
  if [[ -x "$REPO_DIR/scripts/fortify.sh" ]]; then
    RUNNER="$REPO_DIR/scripts/fortify.sh"
  elif [[ -x "$REPO_DIR/fortify.sh" ]]; then
    RUNNER="$REPO_DIR/fortify.sh"
  else
    RUNNER="$REPO_DIR/scripts/fortify.sh"  # best guess; we'll check below
  fi
fi
[[ -x "$RUNNER" ]] || fail "Runner not found or not executable: $RUNNER"

# ----------------- PROFILE SETUP -----------------
if [[ "$MODE" == "smoke" ]]; then
  info "Preparing SMOKE mode (stub profile + stub checks)"
  PROFILE_PATH="$TMP_DIR/smoke.profile"
  cat > "$PROFILE_PATH" <<'P'
# minimal profile for smoke test
demo_always_pass   5
demo_always_fail   5
P

  # stub checks file — loaded by fortify (sources scripts/checks/*.sh)
  mkdir -p "$REPO_DIR/scripts/checks"
  STUB="$REPO_DIR/scripts/checks/00-smoke-stubs.sh"
  cat > "$STUB" <<'STUB'
#!/usr/bin/env bash
demo_always_pass_check(){ echo PASS; }
demo_always_pass_fix(){ :; }
demo_always_fail_check(){ echo FAIL; }
demo_always_fail_fix(){ :; }  # no-op; runner is in --dry-run
STUB
  chmod +x "$STUB"
else
  # default to server.profile if not provided
  if [[ -z "${PROFILE_PATH:-}" ]]; then
    PROFILE_PATH="$REPO_DIR/scripts/profiles/server.profile"
  fi
fi

[[ -f "$PROFILE_PATH" ]] || fail "Profile not found: $PROFILE_PATH"

# ----------------- PREP OUTPUT DIR -----------------
mkdir -p "$REPORTS_DIR"

# ----------------- SUDO DECISION -----------------
SUDO=""
if [[ "$EUID" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo -E"
  else
    info "Running without sudo (some checks may be skipped)"
  fi
fi

# ----------------- RUN FORTIFY -----------------
log "Running Fortify (mode=$MODE) ..."
set +e
# Disable auto-open during tests to avoid stealing focus; verbose + dry-run
FORTIFY_NO_OPEN=true $SUDO "$RUNNER" -v -n -p "$PROFILE_PATH"
RC=$?
set -e
[[ $RC -eq 0 ]] || fail "Fortify exited with code $RC"
pass "Fortify finished OK"

# ----------------- FIND LATEST ARTIFACTS -----------------
LATEST_JSON="$(ls -1t "$REPORTS_DIR"/report-*.json 2>/dev/null | head -n1 || true)"
[[ -n "$LATEST_JSON" && -f "$LATEST_JSON" ]] || fail "No JSON report found in $REPORTS_DIR"
pass "Found JSON: $LATEST_JSON"

base="$(basename "$LATEST_JSON" .json)"
LATEST_HTML="$(dirname "$LATEST_JSON")/${base}.html"
[[ -f "$LATEST_HTML" ]] || fail "Expected HTML not found next to JSON: $LATEST_HTML"
pass "Found HTML: $LATEST_HTML"

# ----------------- VALIDATE JSON -----------------
if [[ $JQ_OK -eq 1 ]]; then
  info "Validating JSON schema with jq"
  jq -e '
    .host and .timestamp and
    (.score_before|type=="number") and
    (.score_after|type=="number") and
    (.results|type=="array") and
    ([.results[]? | (has("id") and has("before") and has("after"))] | all)
  ' "$LATEST_JSON" >/dev/null || fail "JSON schema validation failed"
  pass "JSON schema valid"

  SB="$(jq -r '.score_before' "$LATEST_JSON")"
  SA="$(jq -r '.score_after' "$LATEST_JSON")"
  [[ "$SB" =~ ^[0-9]+$ && "$SB" -ge 0 && "$SB" -le 100 ]] || fail "score_before out of range: $SB"
  [[ "$SA" =~ ^[0-9]+$ && "$SA" -ge 0 && "$SA" -le 100 ]] || fail "score_after out of range: $SA"
  pass "Scores within 0..100"
else
  info "jq not available; skipping deep JSON validation"
fi

# ----------------- HTML SANITY -----------------
grep -q '<!DOCTYPE html>' "$LATEST_HTML" || fail "HTML missing doctype"
grep -qi 'FORTIFY SECURITY QUEST' "$LATEST_HTML" || grep -qi 'Fortify Report' "$LATEST_HTML" || fail "HTML does not look like a Fortify report"
pass "HTML structure OK"

# Optional niceties if using gamified template
if grep -qi 'data-theme=' "$LATEST_HTML"; then pass "Theme toggle detected"; fi
if grep -qi 'Octocat' "$LATEST_HTML"; then pass "Octocat section detected"; fi
if grep -qi 'Achievements' "$LATEST_HTML"; then pass "Achievements section present"; fi

echo
pass "E2E SUCCESS"
[[ "$MODE" == "smoke" ]] && echo "Note: Smoke stubs created at scripts/checks/00-smoke-stubs.sh (safe to keep or delete)."
