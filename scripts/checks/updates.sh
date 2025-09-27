#!/usr/bin/env bash
# Check ID in profile: updates
# Functions required by the runner:
#   - updates_check  -> echo PASS|FAIL
#   - updates_fix    -> actually apply updates

# --- internal logging (stderr only so runner doesn't capture it) ---
_u_log() {
  if declare -F log_event >/dev/null 2>&1; then
    log_event "$1" "$2" 1>&2
  else
    echo "[$1] $2" 1>&2
  fi
}

# --- detect package manager; return short token ---
# apt | rpm | suse | alpine | arch | brew | unknown
_updates_detect_pkg() {
  if command -v apt-get >/dev/null 2>&1; then echo "apt"; return; fi
  if command -v dnf     >/dev/null 2>&1; then echo "rpm"; return; fi
  if command -v yum     >/dev/null 2>&1; then echo "rpm"; return; fi
  if command -v zypper  >/dev/null 2>&1; then echo "suse"; return; fi
  if command -v apk     >/dev/null 2>&1; then echo "alpine"; return; fi
  if command -v pacman  >/dev/null 2>&1; then echo "arch"; return; fi
  if command -v brew    >/dev/null 2>&1; then echo "brew"; return; fi
  echo "unknown"
}

# --- helper: any upgradable packages for apt? ---
# Prefer 'apt list --upgradable'; fallback to 'apt-get -s upgrade'
_apt_any_upgradable() {
  # refresh metadata quietly
  apt-get update -qq >/dev/null 2>&1
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    _u_log "WARN" "apt-get update failed (rc=$rc); treating as FAIL"
    echo "YES"   # treat as updates pending / unknown -> FAIL
    return 0
  fi

  # modern apt
  if command -v apt >/dev/null 2>&1; then
    if apt list --upgradable 2>/dev/null | grep -v '^Listing' | grep -q . ; then
      echo "YES"
    else
      echo "NO"
    fi
    return 0
  fi

  # fallback: simulate upgrade and look for planned installs
  if apt-get -s upgrade 2>/dev/null | grep -E -q '^Inst ' ; then
    echo "YES"
  else
    echo "NO"
  fi
}

# =========================
#         CHECK
# =========================
updates_check() {
  local pm; pm="$(_updates_detect_pkg)"
  _u_log "INFO" "updates_check using pm=$pm"

  case "$pm" in
    apt)
      # Returns YES/NO
      local any; any="$(_apt_any_upgradable)"
      if [[ "$any" == "YES" ]]; then
        echo "FAIL"
      else
        echo "PASS"
      fi
      ;;

    rpm)
      # Prefer dnf when present
      local rc
      if command -v dnf >/dev/null 2>&1; then
        dnf -q check-update >/dev/null 2>&1; rc=$?
      else
        yum -q check-update >/dev/null 2>&1; rc=$?
      fi
      # 0=no updates (PASS), 100=updates available (FAIL), other=error (FAIL)
      if   [[ $rc -eq 0 ]];   then echo "PASS"
      elif [[ $rc -eq 100 ]]; then echo "FAIL"
      else                        _u_log "WARN" "rpm check-update rc=$rc"; echo "FAIL"
      fi
      ;;

    suse)
      # 0=no updates, 100=updates available
      zypper -q lu >/dev/null 2>&1; local rc=$?
      if   [[ $rc -eq 0 ]];   then echo "PASS"
      elif [[ $rc -eq 100 ]]; then echo "FAIL"
      else                        _u_log "WARN" "zypper lu rc=$rc"; echo "FAIL"
      fi
      ;;

    alpine)
      # refresh index; consider failures as FAIL
      apk update >/dev/null 2>&1 || { _u_log "WARN" "apk update failed"; echo "FAIL"; return; }
      # 'apk version -l "<"' lists packages with newer versions available
      if apk version -l '<' 2>/dev/null | grep -q . ; then
        echo "FAIL"
      else
        echo "PASS"
      fi
      ;;

    arch)
      # Refresh sync db; consider failures as FAIL
      pacman -Sy --noconfirm >/dev/null 2>&1 || { _u_log "WARN" "pacman -Sy failed"; echo "FAIL"; return; }
      if pacman -Qu 2>/dev/null | grep -q . ; then
        echo "FAIL"
      else
        echo "PASS"
      fi
      ;;

    brew)
      # macOS / linuxbrew: update metadata, then list outdated
      brew update >/dev/null 2>&1 || { _u_log "WARN" "brew update failed"; echo "FAIL"; return; }
      if brew outdated 2>/dev/null | grep -q . ; then
        echo "FAIL"
      else
        echo "PASS"
      fi
      ;;

    *)
      _u_log "WARN" "Unsupported package manager; cannot check updates"
      echo "FAIL"
      ;;
  esac
}

# =========================
#          FIX
# =========================
updates_fix() {
  local pm; pm="$(_updates_detect_pkg)"
  _u_log "INFO" "updates_fix using pm=$pm"

  case "$pm" in
    apt)
      # non-interactive to avoid prompts
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y  >/dev/null 2>&1 || _u_log "WARN" "apt-get update failed, continuing"
      apt-get -y upgrade >/dev/null 2>&1 || _u_log "WARN" "apt-get upgrade had issues"
      # optional: kernel/major upgrades
      apt-get -y dist-upgrade >/dev/null 2>&1 || true
      _u_log "INFO" "apt upgrades applied"
      ;;

    rpm)
      if command -v dnf >/dev/null 2>&1; then
        dnf -y upgrade >/dev/null 2>&1 || _u_log "WARN" "dnf upgrade had issues"
      else
        yum -y update   >/dev/null 2>&1 || _u_log "WARN" "yum update had issues"
      fi
      _u_log "INFO" "rpm-based upgrades applied"
      ;;

    suse)
      zypper --non-interactive refresh >/dev/null 2>&1 || _u_log "WARN" "zypper refresh failed"
      zypper --non-interactive update  >/dev/null 2>&1 || _u_log "WARN" "zypper update had issues"
      _u_log "INFO" "zypper updates applied"
      ;;

    alpine)
      apk update  >/dev/null 2>&1 || _u_log "WARN" "apk update failed"
      apk upgrade >/dev/null 2>&1 || _u_log "WARN" "apk upgrade had issues"
      _u_log "INFO" "apk upgrades applied"
      ;;

    arch)
      pacman -Syu --noconfirm >/dev/null 2>&1 || _u_log "WARN" "pacman -Syu had issues"
      _u_log "INFO" "pacman upgrades applied"
      ;;

    brew)
      # No sudo for brew
      brew update  >/dev/null 2>&1 || _u_log "WARN" "brew update failed"
      brew upgrade >/dev/null 2>&1 || _u_log "WARN" "brew upgrade had issues"
      _u_log "INFO" "brew upgrades applied"
      ;;

    *)
      _u_log "ERROR" "Unsupported package manager; cannot apply updates"
      return 1
      ;;
  esac
}
