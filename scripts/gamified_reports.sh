#!/usr/bin/env bash
# gamified_reports.sh — Turn security into a game!
# Requires: bash, jq
# Reads:
#   - FORTIFY_REPORT: path to JSON report with {host,timestamp,score_before,score_after,results:[{id,before,after,notes}]}
#   - FORTIFY_RESULTS: optional array of JSON lines (used for “perfect category” badges)
#   - log_event(): optional logger "log_event LEVEL MESSAGE"

set -euo pipefail

# -------------------------------
# Security Rank System
# -------------------------------
declare -gA SECURITY_RANKS=(
  [0]="🚨 Security Trainee"
  [20]="🔰 Apprentice Admin"
  [40]="⚔️ Security Squire"
  [60]="🛡️ Hardening Hero"
  [80]="🏰 Fortress Guardian"
  [95]="👑 Security Sovereign"
  [100]="🌟 Legendary Defender"
)

declare -gA RANK_DESCRIPTIONS=(
  [0]="Just starting your security journey!"
  [20]="Learning the basics of system protection"
  [40]="Developing solid security fundamentals"
  [60]="Becoming a formidable force against threats"
  [80]="Mastering the art of system hardening"
  [95]="Nearly achieved security perfection!"
  [100]="The ultimate guardian of digital realms!"
)

get_security_rank() {
  local score="${1:-0}" rank_score=0
  for threshold in 100 95 80 60 40 20 0; do
    if (( score >= threshold )); then rank_score="$threshold"; break; fi
  done
  echo "${SECURITY_RANKS[$rank_score]}"
}

get_rank_description() {
  local score="${1:-0}" rank_score=0
  for threshold in 100 95 80 60 40 20 0; do
    if (( score >= threshold )); then rank_score="$threshold"; break; fi
  done
  echo "${RANK_DESCRIPTIONS[$rank_score]}"
}

# -------------------------------
# Achievement Badges
# -------------------------------
check_achievement_badges() {
  local score_before="${1:-0}" score_after="${2:-0}"
  local delta=$((score_after - score_before))
  local -a badges=()

  # Progress
  (( delta > 0 ))   && badges+=("📈 Progress Made")
  (( delta >= 5 ))  && badges+=("🚀 Significant Improvement")
  (( delta >= 10 )) && badges+=("💫 Major Breakthrough")
  (( delta >= 20 )) && badges+=("🌟 Security Transformation")

  # Milestones
  (( score_after >= 50 )) && badges+=("🥉 Bronze Security")
  (( score_after >= 75 )) && badges+=("🥈 Silver Security")
  (( score_after >= 90 )) && badges+=("🥇 Gold Security")
  (( score_after == 100 )) && badges+=("💎 Diamond Perfection")

  # Specials
  (( score_after == score_before && score_after >= 90 )) && badges+=("🛡️ Maintained Excellence")

  # Safe count of FORTIFY_RESULTS (may be undeclared under set -u)
  local results_count=0
  if declare -p FORTIFY_RESULTS >/dev/null 2>&1; then
    results_count=${#FORTIFY_RESULTS[@]}
  fi
  (( results_count > 10 )) && badges+=("🔍 Comprehensive Scan")

  # Category perfection (only if array is declared)
  local perfect_ssh=true perfect_files=true
  if declare -p FORTIFY_RESULTS >/dev/null 2>&1; then
    for result in "${FORTIFY_RESULTS[@]}"; do
      # Expect: {"id":"ssh_config","before":"FAIL","after":"PASS","notes":"..."}
      local id after
      id=$(sed -E 's/.*"id":"([^"]+)".*/\1/' <<<"$result" || true)
      after=$(sed -E 's/.*"after":"([^"]+)".*/\1/' <<<"$result" || true)
      [[ "$id" =~ ssh ]] && [[ "${after^^}" != "PASS" ]] && perfect_ssh=false
      [[ "$id" =~ (file|world_writable) ]] && [[ "${after^^}" != "PASS" ]] && perfect_files=false
    done
  fi
  [[ "$perfect_ssh" == "true" ]]  && badges+=("🔐 SSH Master")
  [[ "$perfect_files" == "true" ]] && badges+=("📁 File Guardian")

  printf '%s\n' "${badges[@]}"
}

# -------------------------------
# ASCII/UTF-8 Health Bar (terminal)
# -------------------------------
draw_health_bar() {
  local score="${1:-0}" width=50
  # ASCII fallback if not UTF-8
  local use_utf8=1
  if [[ ! "${LC_ALL:-}${LANG:-}" =~ UTF-8|utf-8 ]]; then use_utf8=0; fi

  local filled=$(( score * width / 100 ))
  local empty=$(( width - filled ))

  local green=$'\033[32m' yellow=$'\033[33m' magenta=$'\033[35m' red=$'\033[31m' gray=$'\033[90m' reset=$'\033[0m'
  local color="$red"
  (( score >= 80 )) && color="$green" || { (( score >= 60 )) && color="$yellow" || { (( score >= 40 )) && color="$magenta"; }; }

  local full_char empty_char
  if (( use_utf8 )); then
    full_char='█'; empty_char='░'
  else
    full_char='='; empty_char='.'
  fi

  printf 'Security Health: ['
  printf "%s%*s" "$color" "$filled" '' | tr ' ' "$full_char"
  printf "%s%*s" "$gray" "$empty" ''  | tr ' ' "$empty_char"
  printf "%s] %d%%\n" "$reset" "$score"
}

# -------------------------------
# Octocat Reactions (terminal)
# -------------------------------
show_happy_octocat() {
cat <<'EOF'
🎉
 /o o\ 
(  ^ ^ )
 \  ∪ / 
  \___/ 
  /| |\ 
 / | | \ 
🎊 HAPPY! 🎊
EOF
}

show_approving_octocat() {
cat <<'EOF'
✨
 /^ ^\ 
(  ◡  )
 \  ✓ / 
  \___/ 
  /| |\ 
 / | | \ 
👍 NICE! 👍
EOF
}

show_concerned_octocat() {
cat <<'EOF'
⚠️
 /o o\ 
(  _  )
 \ ∿ / 
  \___/ 
  /| |\ 
 / | | \ 
😟 WORRIED 😟
EOF
}

show_content_octocat() {
cat <<'EOF'
😌
 /- -\ 
(  ◡  )
 \ __ / 
  \___/ 
  /| |\ 
 / | | \ 
✨ STABLE ✨
EOF
}

show_encouraging_octocat() {
cat <<'EOF'
💪
 /o o\ 
(  >  )
 \ ∩ / 
  \___/ 
  /| |\ 
 / | | \ 
🔥 GO! 🔥
EOF
}

show_legendary_octocat() {
cat <<'EOF'
👑
 /★ ★\ 
(  ◡  )
 \ ∪ / 
  \___/ 
  /| |\ 
 / | | \ 
🌟 LEGEND! 🌟
EOF
}

show_secret_octocat_dance() {
  echo "🎵 OCTOCAT VICTORY DANCE! 🎵"
  for _ in 1 2 3; do
    clear
    cat <<'EOF'
🎊 DANCE PARTY! 🎊
    \o/
   /★ ★\
  (  ◡  )
   \ ∪ /
    \___/
   /|\  /|\
  / | \/ | \
  🕺 BOOGIE! 💃
EOF
    sleep 0.5
    clear
    cat <<'EOF'
🎉 DANCE PARTY! 🎉
     \o/
    /★ ★\
   (  ◡  )
    \ ∪ /
     \___/
    /|   |\
   / |   | \
   💃 PARTY! 🕺
EOF
    sleep 0.5
  done
  echo "🎊 You’ve unlocked the secret GitHub Security Hall of Fame! 🎊"
}

show_octocat_reaction() {
  local score_before="${1:-0}" score_after="${2:-0}"
  local delta=$((score_after - score_before))
  echo
  echo "🐙 OCTOCAT SECURITY REVIEW 🐙"
  echo "==============================="
  if (( score_after == 100 )); then
    show_legendary_octocat
    echo "🌟 LEGENDARY ACHIEVEMENT UNLOCKED! 🌟"
    echo "Octocat declares you a SECURITY LEGEND!"
    echo
    echo "🎉 SECRET OCTOCAT EASTER EGG ACTIVATED! 🎉"
    show_secret_octocat_dance
  elif (( score_after >= 90 )); then
    show_happy_octocat
    echo "🐙✨ Octocat is IMPRESSED! Your security game is strong!"
  elif (( delta > 0 )); then
    show_approving_octocat
    echo "🐙✔️ Octocat approves of your progress! Keep it up!"
  elif (( delta == 0 && score_after >= 80 )); then
    show_content_octocat
    echo "🐙😌 Octocat is content. You're maintaining good security!"
  elif (( delta < 0 )); then
    show_concerned_octocat
    echo "🐙⚠️ Octocat is concerned about your security regression!"
  else
    show_encouraging_octocat
    echo "🐙💪 Octocat believes in you! Time to level up your security!"
  fi
  echo "==============================="
}

# -------------------------------
# XP + Leveling
# -------------------------------
calculate_security_xp() {
  local sb="${1:-0}" sa="${2:-0}" delta=$((sa - sb))
  local total=100     # base XP for running a scan
  (( delta > 0 ))  && total=$(( total + delta * 10 ))
  (( sa >= 90 ))   && total=$(( total + 200 ))
  (( sa == 100 ))  && total=$(( total + 500 ))

  # Perfect categories give bonus (25 each)
  local perfect=0 after
  if declare -p FORTIFY_RESULTS >/dev/null 2>&1; then
    for result in "${FORTIFY_RESULTS[@]}"; do
      after=$(sed -E 's/.*"after":"([^"]+)".*/\1/' <<<"$result" || true)
      [[ "${after^^}" == "PASS" ]] && (( perfect++ ))
    done
  fi
  total=$(( total + perfect * 25 ))
  echo "$total"
}

show_xp_gain() {
  local xp="${1:-0}"
  echo
  echo "💫 XP GAINED: +${xp} points!"
  echo "Keep securing systems to level up your Security Mastery!"
}
# -------------------------------
# Gamified HTML Report
# -------------------------------
generate_gamified_html_report() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required for HTML report generation." >&2
    return 1
  fi

  # Paths
  local base name
  base="$(basename "${FORTIFY_REPORT}" .json)"
  name="${base}.html"
  FORTIFY_HTML="$(dirname "${FORTIFY_REPORT}")/${name}"

  # Parse summary (UTC in report)
  local host ts_utc sb sa delta
  host="$(jq -r '.host // "-"' "$FORTIFY_REPORT" 2>/dev/null || echo "-")"
  ts_utc="$(jq -r '.timestamp // "-"' "$FORTIFY_REPORT" 2>/dev/null || echo "-")"
  sb="$(jq -r '.score_before // 0' "$FORTIFY_REPORT" 2>/dev/null || echo 0)"
  sa="$(jq -r '.score_after  // 0' "$FORTIFY_REPORT" 2>/dev/null || echo 0)"
  delta=$(( sa - sb ))

  # Convert timestamp to Eastern
  local ts_est
  if [[ "$ts_utc" != "-" ]]; then
    # GNU date path (WSL/Ubuntu). If parsing fails, fall back to raw value.
    if ts_est="$(TZ=America/New_York date -d "$ts_utc" "+%Y-%m-%d %I:%M %p %Z" 2>/dev/null)"; then
      :
    else
      ts_est="$ts_utc"
    fi
  else
    ts_est="—"
  fi

  # Game elements
  local rank rank_desc xp
  rank="$(get_security_rank "$sa")"
  rank_desc="$(get_rank_description "$sa")"
  xp="$(calculate_security_xp "$sb" "$sa")"

  # Results TSV (for server-side rows)
  local rows_tsv
  rows_tsv="$(jq -r '.results[] | [.id, .before, .after, (.notes // "")] | @tsv' "$FORTIFY_REPORT" 2>/dev/null || echo "")"

  # HTML head + CSS
  cat > "$FORTIFY_HTML" <<'HEAD_HTML'
<!doctype html>
<html lang="en" data-theme="auto">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Fortify Security Quest — Report</title>
<meta name="color-scheme" content="light dark"/>
<style>
:root {
  --bg:#0b0d10; --card:#12161b; --muted:#9aa4af; --text:#e6edf3; --line:#1e2530;
  --brand:#7cacf8; --ok:#35d07f; --warn:#ffd166; --bad:#ff6b6b; --accent:#9b8cff;
  --chip:#1b2230; --shadow:0 8px 24px rgba(0,0,0,.35), inset 0 1px 0 rgba(255,255,255,.02);
}
:root[data-theme="light"]{
  --bg:#f6f7fb; --card:#ffffff; --muted:#606b78; --text:#0f1720; --line:#e9edf2;
  --brand:#316cd6; --ok:#0b8f3a; --warn:#a86b00; --bad:#b00020; --accent:#6b5cff; --chip:#f1f4f9;
  --shadow:0 10px 20px rgba(17,24,39,.07), inset 0 1px 0 rgba(255,255,255,.8);
}
:root[data-theme="dark"]{
  --bg:#0b0d10; --card:#12161b; --muted:#9aa4af; --text:#e6edf3; --line:#1e2530;
  --brand:#7cacf8; --ok:#35d07f; --warn:#ffd166; --bad:#ff6b6b; --accent:#9b8cff; --chip:#1b2230;
  --shadow:0 8px 24px rgba(0,0,0,.35), inset 0 1px 0 rgba(255,255,255,.02);
}
html,body{height:100%}
body{
  margin:0; color:var(--text);
  background:radial-gradient(1200px 800px at 20% -10%, rgba(123,108,255,.06), transparent 60%), var(--bg);
  font:14px/1.55 system-ui, -apple-system, Segoe UI, Roboto, Inter, Arial, sans-serif;
}
.container{max-width:1100px;margin:0 auto;padding:24px}
.header{
  position:sticky; top:0; z-index:5; backdrop-filter:saturate(120%) blur(8px);
  background: color-mix(in oklab, var(--bg) 75%, transparent); border-bottom:1px solid var(--line);
}
.header-inner{display:flex;align-items:center;gap:12px; padding:14px 24px; max-width:1100px; margin:0 auto;}
.logo{width:28px;height:28px;border-radius:8px;background:linear-gradient(135deg,var(--brand),var(--accent)); box-shadow:var(--shadow)}
.title{font-size:16px;font-weight:700; letter-spacing:.2px}
.header-actions{margin-left:auto; display:flex; gap:8px; align-items:center}
.btn{
  padding:8px 12px; border:1px solid var(--line); border-radius:10px; background:var(--card);
  color:var(--text); cursor:pointer; box-shadow:var(--shadow); transition:.2s transform, .2s background;
}
.btn:hover{transform:translateY(-1px)}
.btn.ghost{background:transparent}
.btn.primary{background:linear-gradient(135deg,var(--accent),var(--brand)); border-color:transparent; color:white;}

.summary{margin-top:18px; display:grid; grid-template-columns: 1.2fr 1fr; gap:18px;}
.card{
  border:1px solid var(--line); border-radius:16px; background:linear-gradient(180deg, color-mix(in oklab, var(--card) 98%, transparent), var(--card));
  box-shadow:var(--shadow); padding:20px;
}
.rank-wrap{display:flex; align-items:center; gap:16px;}
.rank-emoji{font-size:28px}
.rank-text .rank-title{font-weight:800; font-size:20px}
.rank-text .rank-desc{color:var(--muted)}
.donut{
  width:160px; aspect-ratio:1/1; border-radius:50%;
  background:conic-gradient(var(--ok) var(--donut), color-mix(in oklab,var(--ok) 35%, var(--warn)) var(--donut),
                            color-mix(in oklab,var(--warn) 50%, var(--bad)) var(--donut), var(--line) 0);
  display:grid; place-items:center; position:relative; isolation:isolate;
}
.donut::after{content:""; position:absolute; inset:10px; border-radius:50%; background:var(--card); border:1px solid var(--line); box-shadow:var(--shadow);}
.donut-label{position:relative; z-index:1; text-align:center; font-weight:800; font-size:28px;}
.delta-chip{
  display:inline-flex; align-items:center; gap:6px; background:var(--chip); border:1px solid var(--line);
  padding:6px 10px; border-radius:999px; font-weight:600; color:var(--muted)
}
.delta-chip.positive{color:var(--ok)}
.delta-chip.negative{color:var(--bad)}
.meta-grid{display:grid; grid-template-columns:repeat(3,1fr); gap:10px; margin-top:14px}
.stat{background:var(--chip); border:1px solid var(--line); border-radius:12px; padding:10px 12px;}
.stat .label{color:var(--muted); font-size:12px}
.stat .value{font-weight:700; margin-top:2px}

.badges{display:flex; flex-wrap:wrap; gap:8px; margin-top:12px}
.badge{background:linear-gradient(180deg, color-mix(in oklab, var(--accent) 20%, transparent), var(--chip));
  border:1px solid var(--line); padding:6px 10px; border-radius:999px; font-weight:700; font-size:12px; box-shadow:var(--shadow)}

.tools{display:flex; gap:10px; align-items:center; margin-top:22px; flex-wrap:wrap}
.input{padding:9px 11px; border-radius:10px; border:1px solid var(--line); background:var(--card); color:var(--text)}
.select{padding:9px 11px; border-radius:10px; border:1px solid var(--line); background:var(--card); color:var(--text)}
.table-wrap{margin-top:12px; overflow:auto; border:1px solid var(--line); border-radius:14px; box-shadow:var(--shadow)}
table{width:100%; border-collapse:collapse; min-width:680px; background:var(--card)}
th,td{padding:12px 14px; border-bottom:1px solid var(--line); text-align:left}
th{position:sticky; top:0; background:color-mix(in oklab, var(--card) 96%, transparent); backdrop-filter:blur(6px); cursor:pointer; user-select:none}
.code{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
.status{font-weight:800; padding:4px 10px; border-radius:999px; border:1px solid var(--line)}
.pass{background:color-mix(in oklab, var(--ok) 15%, transparent); color:var(--ok)}
.fail{background:color-mix(in oklab, var(--bad) 15%, transparent); color:var(--bad)}
tfoot td{color:var(--muted); font-size:12px}

.footer{display:grid; place-items:center; gap:6px; padding:26px 0; color:var(--muted)}
@media print{.header,.tools .btn,.header-actions{display:none !important} body{background:white} .card{box-shadow:none}}
</style>
</head>
<body>
<div class="header">
  <div class="header-inner">
    <div class="logo"></div>
    <div class="title">FORTIFY SECURITY QUEST — REPORT</div>
    <div class="header-actions">
      <button class="btn ghost" id="themeBtn" title="Toggle theme">🌓 Auto</button>
      <button class="btn" id="copyBtn"  title="Copy page URL">📋 Copy Path</button>
      <button class="btn" id="printBtn" title="Print / Save PDF">🖨️ Print</button>
      <button class="btn primary" id="jsonBtn" title="Download JSON">↓ JSON</button>
    </div>
  </div>
</div>
<div class="container" id="app">
HEAD_HTML

  # Summary section (embed numeric metrics as data-* to avoid NaN)
  cat >> "$FORTIFY_HTML" <<SUMMARY
  <div id="reportData"
       data-sb="${sb}"
       data-sa="${sa}"
       data-delta="${delta}"
       data-xp="${xp}">
  </div>

  <div class="summary">
    <div class="card">
      <div class="rank-wrap">
        <div class="rank-emoji">$(printf '%s' "$rank" | sed 's/^[^ ]* //')</div>
        <div class="rank-text">
          <div class="rank-title">$rank</div>
          <div class="rank-desc">$rank_desc</div>
        </div>
      </div>
      <div class="badges" id="badges"></div>
      <div class="meta-grid">
        <div class="stat"><div class="label">Host</div><div class="value code">$(printf '%s' "$host" | sed 's/&/\&amp;/g')</div></div>
        <div class="stat"><div class="label">Generated</div><div class="value">${ts_est}</div></div>
        <div class="stat"><div class="label">Checks</div><div class="value" id="checksCount">—</div></div>
      </div>
    </div>
    <div class="card" style="display:grid; grid-template-columns:160px 1fr; gap:16px; align-items:center;">
      <div class="donut" style="--donut:${sa}%">
        <div class="donut-label">${sa}%</div>
      </div>
      <div>
        <div class="delta-chip $( ((delta>0)) && echo positive || { ((delta<0)) && echo negative; } )">
          ${delta:+Δ }$delta
        </div>
        <div class="meta-grid" style="margin-top:10px">
          <div class="stat"><div class="label">Score Before</div><div class="value">${sb}%</div></div>
          <div class="stat"><div class="label">Score After</div><div class="value">${sa}%</div></div>
          <div class="stat"><div class="label">XP Earned</div><div class="value">+${xp}</div></div>
        </div>
      </div>
    </div>
  </div>
SUMMARY

  # Tools + table
  cat >> "$FORTIFY_HTML" <<'TABLE_HTML'
  <div class="card">
    <div class="tools">
      <input class="input" id="search" placeholder="Search checks / notes…" />
      <select class="select" id="statusFilter">
        <option value="ALL">All statuses</option>
        <option value="PASS">PASS only</option>
        <option value="FAIL">FAIL only</option>
      </select>
      <div class="btn ghost" id="expandBtn">↕ Expand Notes</div>
    </div>

    <div class="table-wrap">
      <table id="resultsTable" aria-label="Security Check Results">
        <thead>
          <tr>
            <th data-key="id">Security Check</th>
            <th data-key="before">Before</th>
            <th data-key="after">After</th>
            <th data-key="notes">Notes</th>
          </tr>
        </thead>
        <tbody>
TABLE_HTML

  # Server-side rows
  if [[ -n "$rows_tsv" ]]; then
    while IFS=$'\t' read -r id before after notes; do
      id=$(printf '%s' "$id" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
      nesc=$(printf '%s' "${notes:-}" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
      before_class="fail"; [[ "${before^^}" == "PASS" ]] && before_class="pass"
      after_class="fail";  [[ "${after^^}"  == "PASS" ]] && after_class="pass"
      cat >> "$FORTIFY_HTML" <<ROW
          <tr>
            <td class="code">$id</td>
            <td><span class="status $before_class">${before}</span></td>
            <td><span class="status $after_class">${after}</span></td>
            <td class="notes">$nesc</td>
          </tr>
ROW
    done <<< "$rows_tsv"
  fi

  # Profile badges + footer + JS
  cat >> "$FORTIFY_HTML" <<'TAIL_HTML'
        </tbody>
        <tfoot><tr><td colspan="4">Tip: Click a column header to sort. Use the search box to filter.</td></tr></tfoot>
      </table>
    </div>
  </div>

  <div class="card" id="profileBadgesCard">
    <h3 style="margin:0 0 10px 0">🏅 GitHub Profile Badges</h3>
    <p class="muted" style="margin:6px 0 12px 0">
      Paste these into your <span class="code">README.md</span> in your profile repo (<span class="code">github.com/&lt;user&gt;/&lt;user&gt;</span>).
    </p>
    <div id="profileBadgesPreview" class="badges" style="margin-bottom:12px;"></div>
    <div style="display:flex; gap:8px; flex-wrap:wrap;">
      <button class="btn" id="copyMdBtn">📋 Copy Markdown</button>
      <button class="btn ghost" id="copyHtmlBtn">📋 Copy HTML</button>
      <button class="btn ghost" id="howToBtn" title="Instructions">❔ How to add</button>
    </div>
  </div>

  <div class="footer">
    <div>Generated by 🛡️ Fortify Security Quest</div>
    <div>Share this HTML or use “Print” to export a PDF.</div>
  </div>
</div>

<!-- Theme toggle + persistence -->
<script>
(function(){
  const root = document.documentElement;
  const themeBtn = document.getElementById('themeBtn');

  const stored = localStorage.getItem('fortify_theme') || 'auto';
  setTheme(stored);

  const mq = window.matchMedia('(prefers-color-scheme: dark)');
  if (mq.addEventListener) {
    mq.addEventListener('change', ()=> { if(getTheme()==='auto') applyAutoVars(); });
  } else if (mq.addListener) { mq.addListener(()=> { if(getTheme()==='auto') applyAutoVars(); }); }

  themeBtn.addEventListener('click', ()=>{
    const next = ({auto:'dark', dark:'light', light:'auto'})[getTheme()] || 'auto';
    setTheme(next);
  });

  function getTheme(){ return root.getAttribute('data-theme') || 'auto'; }
  function setTheme(mode){
    root.setAttribute('data-theme', mode);
    localStorage.setItem('fortify_theme', mode);
    applyAutoVars();
    themeBtn.textContent = (mode==='auto' ? '🌓 Auto' : mode==='dark' ? '🌚 Dark' : '🌞 Light');
    document.documentElement.style.colorScheme = (mode==='auto'
      ? (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')
      : mode);
  }
  function applyAutoVars(){
    if(getTheme()!=='auto') return;
    root.setAttribute('data-theme', window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    root.setAttribute('data-theme', 'auto');
  }
})();
</script>

<!-- Table interactions, richer badges, copy buttons -->
<script>
(function(){
  const copyBtn  = document.getElementById('copyBtn');
  const printBtn = document.getElementById('printBtn');
  const jsonBtn  = document.getElementById('jsonBtn');
  const expandBtn= document.getElementById('expandBtn');
  const search   = document.getElementById('search');
  const statusFilter = document.getElementById('statusFilter');
  const table = document.getElementById('resultsTable');
  const tbody = table.querySelector('tbody');
  const badgesEl = document.getElementById('badges');
  const checksCount = document.getElementById('checksCount');
  const preview = document.getElementById('profileBadgesPreview');
  const rd = document.getElementById('reportData');

  // Safe numeric metrics (no NaN)
  const sb = Number(rd.dataset.sb || 0);
  const sa = Number(rd.dataset.sa || 0);
  const delta = Number(rd.dataset.delta || 0);
  const xp = Number(rd.dataset.xp || 0);

  // Buttons
  copyBtn.addEventListener('click', ()=>{
    navigator.clipboard.writeText(window.location.href).then(()=> flashOK(copyBtn, '✅ Copied'));
  });
  printBtn.addEventListener('click', ()=> window.print());
  jsonBtn.addEventListener('click', ()=>{
    const href = window.location.href;
    const json = href.replace(/\.html(\#.*)?$/, '.json');
    const a = document.createElement('a'); a.href = json; a.download = '';
    document.body.appendChild(a); a.click(); a.remove();
  });

  // Stats from table
  let pass=0, fail=0, total=0;
  let sshPerfect=true, filesPerfect=true;
  [...tbody.querySelectorAll('tr')].forEach(tr=>{
    const id = tr.children[0].innerText.trim();
    const after = tr.children[2].innerText.trim().toUpperCase();
    (after==='PASS') ? pass++ : fail++;
    if(/ssh/i.test(id) && after!=='PASS') sshPerfect=false;
    if(/(file|world_writable)/i.test(id) && after!=='PASS') filesPerfect=false;
  });
  total = pass + fail;
  checksCount.textContent = total.toString();

  // Human badges (Diamond only if ALL PASS)
  const humanBadges = [];
  if(delta>0) humanBadges.push('📈 Progress Made');
  if(delta>=5) humanBadges.push('🚀 Significant Improvement');
  if(delta>=10) humanBadges.push('💫 Major Breakthrough');
  if(delta>=20) humanBadges.push('🌟 Security Transformation');

  if(total>0 && pass===total){
    humanBadges.push('💎 Diamond Security');      // all tests passed
  } else {
    if(sa>=90) humanBadges.push('🥇 Gold Security');
    else if(sa>=75) humanBadges.push('🥈 Silver Security');
    else if(sa>=50) humanBadges.push('🥉 Bronze Security');
  }

  if(delta===0 && sa>=90) humanBadges.push('🛡️ Maintained Excellence');
  if(total>=10) humanBadges.push('🔍 Comprehensive Scan');
  if(sshPerfect) humanBadges.push('🔐 SSH Master');
  if(filesPerfect) humanBadges.push('📁 File Guardian');

  // Octocat approvals
  if(sa===100) humanBadges.push('👑 Octocat Legendary');
  else if(sa>=90) humanBadges.push('🐙 Octocat Approval');

  humanBadges.forEach(t=>{
    const span=document.createElement('span'); span.className='badge'; span.textContent=t; badgesEl.appendChild(span);
  });

  // Shields.io badges for README
  const shields = [];
  shields.push({
    label:'Fortify Score',
    message: sa + '%',
    color: (total>0 && pass===total) ? 'brightgreen'
          : sa>=90 ? 'green'
          : sa>=75 ? 'yellowgreen'
          : sa>=50 ? 'yellow'
          : 'orange'
  });
  shields.push({ label:'Checks', message: String(total), color: 'blue' });
  shields.push({ label:'PASS', message: String(pass), color: 'success' });
  shields.push({ label:'FAIL', message: String(fail), color: (fail===0?'inactive':'critical') });
  if(delta!==0){
    shields.push({ label:'Delta', message: (delta>0?'+':'') + String(delta), color: (delta>0? 'success' : 'critical') });
  }
  if(total>0 && pass===total) shields.push({ label:'Tier', message:'Diamond', color:'brightgreen' });
  else if(sa>=90)              shields.push({ label:'Tier', message:'Gold',    color:'yellow' });
  else if(sa>=75)              shields.push({ label:'Tier', message:'Silver',  color:'lightgrey' });
  else if(sa>=50)              shields.push({ label:'Tier', message:'Bronze',  color:'orange' });

  if(sa===100) shields.push({ label:'Octocat', message:'Legendary', color:'purple' });
  else if(sa>=90) shields.push({ label:'Octocat', message:'Approval', color:'blueviolet' });

  const mdParts = [], htmlParts = [];
  shields.forEach(b=>{
    const url = `https://img.shields.io/badge/${encodeURIComponent(b.label)}-${encodeURIComponent(b.message)}-${encodeURIComponent(b.color)}?style=for-the-badge`;
    const alt = `${b.label}: ${b.message}`;
    const img = document.createElement('img');
    img.src = url; img.alt = alt; img.style.height='28px'; img.style.marginRight='6px';
    preview.appendChild(img);
    mdParts.push(`![${alt}](${url})`);
    htmlParts.push(`<img alt="${alt}" src="${url}" height="28">`);
  });

  // Copy buttons
  const copyMdBtn = document.getElementById('copyMdBtn');
  const copyHtmlBtn = document.getElementById('copyHtmlBtn');
  const howToBtn = document.getElementById('howToBtn');

  copyMdBtn.addEventListener('click', ()=>{
    navigator.clipboard.writeText(mdParts.join(' ')).then(()=> flashOK(copyMdBtn, '✅ Copied'));
  });
  copyHtmlBtn.addEventListener('click', ()=>{
    navigator.clipboard.writeText(htmlParts.join('\n')).then(()=> flashOK(copyHtmlBtn, '✅ Copied'));
  });
  howToBtn.addEventListener('click', ()=>{
    alert([
      'How to add to your GitHub profile:',
      '1) Create a repo named exactly your username (e.g., github.com/<you>/<you>).',
      '2) Add a README.md at the root.',
      '3) Paste the Markdown badges you copied.',
      '4) Commit and push — GitHub shows the README on your profile.'
    ].join('\n'));
  });

  // Sorting
  let sortKey = 'id'; let sortDir = 1;
  const keyIndex = { id:0, before:1, after:2, notes:3 };
  table.querySelectorAll('th').forEach(th=>{
    th.addEventListener('click', ()=>{
      const k = th.dataset.key;
      if(sortKey===k) sortDir*=-1; else { sortKey=k; sortDir=1; }
      const idx = keyIndex[k];
      const rows = [...tbody.querySelectorAll('tr')];
      rows.sort((a,b)=>{
        const A = a.children[idx].innerText.toLowerCase();
        const B = b.children[idx].innerText.toLowerCase();
        if(A<B) return -1*sortDir;
        if(A>B) return  1*sortDir;
        return 0;
      });
      rows.forEach(r=>tbody.appendChild(r));
    });
  });

  // Filter
  function applyFilter(){
    const q = (search.value||'').toLowerCase();
    const f = statusFilter.value;
    [...tbody.querySelectorAll('tr')].forEach(tr=>{
      const id    = tr.children[0].innerText.toLowerCase();
      const after = tr.children[2].innerText.toUpperCase();
      const notes = tr.children[3].innerText.toLowerCase();
      let ok = (id.includes(q) || notes.includes(q));
      if(f==='PASS') ok = ok && after==='PASS';
      if(f==='FAIL') ok = ok && after==='FAIL';
      tr.style.display = ok ? '' : 'none';
    });
  }
  search.addEventListener('input', applyFilter);
  statusFilter.addEventListener('change', applyFilter);

  // Notes expand/collapse
  let expanded=false;
  expandBtn.addEventListener('click', ()=>{
    expanded = !expanded;
    [...tbody.querySelectorAll('td.notes')].forEach(td=>{
      td.style.whiteSpace = expanded ? 'normal' : 'nowrap';
      td.style.textOverflow = expanded ? 'clip' : 'ellipsis';
      td.style.overflow = expanded ? 'visible' : 'hidden';
    });
  });
  // Initial clamp
  [...tbody.querySelectorAll('td.notes')].forEach(td=>{
    td.style.whiteSpace='nowrap'; td.style.overflow='hidden'; td.style.textOverflow='ellipsis';
  });

  function flashOK(btn, text){
    const old=btn.textContent; btn.textContent=text;
    setTimeout(()=> btn.textContent=old, 1200);
  }
})();
</script>
</body>
</html>
TAIL_HTML

  if command -v log_event >/dev/null 2>&1; then
    log_event "INFO" "Gamified HTML report: $FORTIFY_HTML"
  else
    echo "Gamified HTML report: $FORTIFY_HTML"
  fi
}


# -------------------------------
# Helper to run full gamified flow in terminal
# -------------------------------
gamified_terminal_summary() {
  local sb="${1:-0}" sa="${2:-0}"
  local rank desc xp
  rank="$(get_security_rank "$sa")"
  desc="$(get_rank_description "$sa")"
  xp="$(calculate_security_xp "$sb" "$sa")"

  echo "=== Fortify Security Quest ==="
  echo "Rank: $rank"
  echo "Note: $desc"
  draw_health_bar "$sa"
  show_octocat_reaction "$sb" "$sa"
  show_xp_gain "$xp"
}
