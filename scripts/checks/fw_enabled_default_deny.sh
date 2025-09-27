#!/usr/bin/env bash

# Check ID in profile: fw_enabled_default_deny
# Functions required by the runner:
#   - fw_enabled_default_deny_check  -> echo PASS|FAIL
#   - fw_enabled_default_deny_fix    -> enforce default deny (keep SSH/HTTP/HTTPS)

_fw_log() {
  # send logs to STDERR so the runner doesn't capture them as the check's value
  if declare -F log_event >/dev/null 2>&1; then
    log_event "$1" "$2" 1>&2
  else
    echo "[$1] $2" 1>&2
  fi
}


# Detect current SSH port (fallback 22)
_fw_detect_ssh_port() {
  local cfg="/etc/ssh/sshd_config" port="22"
  if [[ -f "$cfg" ]]; then
    # take last non-comment Port line if present
    local p
    p="$(awk 'tolower($1)=="port" {v=$2} END{print v}' "$cfg" 2>/dev/null || true)"
    [[ -n "$p" ]] && port="$p"
  fi
  echo "$port"
}

fw_enabled_default_deny_check() {
  # Prefer UFW if present and active
  if command -v ufw >/dev/null 2>&1; then
    local s v
    s="$(ufw status 2>/dev/null | head -n1 || true)"
    v="$(ufw status verbose 2>/dev/null || true)"
    _fw_log "INFO" "ufw status: $s"
    # Active + default incoming deny?
    if grep -qi '^Status: active' <<<"$s" && grep -qi 'Default: deny (incoming)' <<<"$v"; then
      echo "PASS"; return 0
    else
      echo "FAIL"; return 0
    fi
  fi

  # Fall back to iptables default INPUT policy
  if command -v iptables >/dev/null 2>&1; then
    local head; head="$(iptables -L INPUT -n 2>/dev/null | head -n1 || true)"
    _fw_log "INFO" "iptables INPUT head: ${head:-<none>}"
    if grep -Eq 'policy (DROP|REJECT)' <<<"$head"; then
      echo "PASS"; return 0
    else
      echo "FAIL"; return 0
    fi
  fi

  # No firewall tool found → treat as FAIL (not protected)
  _fw_log "WARN" "No ufw/iptables found; firewall default deny not enforced"
  echo "FAIL"
}

fw_enabled_default_deny_fix() {
  # Try UFW first (friendliest UX). If not present, try iptables.
  local ssh_port; ssh_port="$(_fw_detect_ssh_port)"
  _fw_log "INFO" "Detected SSH port: $ssh_port"

  if command -v ufw >/dev/null 2>&1; then
    _fw_log "INFO" "Configuring UFW for default deny (incoming)"
    # Ensure rules allow basic access and prevent lockout
    ufw allow "${ssh_port}/tcp" || true
    ufw allow 80/tcp || true
    ufw allow 443/tcp || true
    # default policies
    ufw default deny incoming || true
    ufw default allow outgoing || true
    # enable (non-interactive)
    yes | ufw enable >/dev/null 2>&1 || ufw reload || true
    # final reload just in case
    ufw reload || true
    _fw_log "INFO" "UFW enabled: default deny incoming; ssh/http/https allowed"
    return 0
  fi

  if command -v iptables >/dev/null 2>&1; then
    _fw_log "INFO" "Configuring iptables for default deny (incoming, forward)"
    # Optional backup (creates a new dir; your runner also created one already)
    if declare -F create_backup >/dev/null 2>&1; then
      local bdir; bdir="$(create_backup "fw_enabled_default_deny")"
      if command -v iptables-save >/dev/null 2>&1; then
        iptables-save > "${bdir}/iptables.rules.backup" 2>/dev/null || true
        _fw_log "INFO" "Saved iptables backup to ${bdir}/iptables.rules.backup"
      fi
    fi

    # Set default policies
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    # OUTPUT left as ACCEPT (typical)
    # Baseline safe rules (idempotent; duplicates are okay but we try to avoid spamming)
    # loopback
    iptables -C INPUT -i lo -j ACCEPT 2>/dev/null || iptables -A INPUT -i lo -j ACCEPT
    # established/related
    iptables -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
      iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    # ssh/http/https
    iptables -C INPUT -p tcp --dport "${ssh_port}" -j ACCEPT 2>/dev/null || \
      iptables -A INPUT -p tcp --dport "${ssh_port}" -j ACCEPT
    iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport 443 -j ACCEPT

    # Persist (Debian/Ubuntu style if directory exists)
    if command -v iptables-save >/dev/null 2>&1; then
      if [[ -d /etc/iptables ]]; then
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
      fi
    fi

    _fw_log "INFO" "iptables set to default deny; ssh/http/https allowed"
    return 0
  fi

  _fw_log "ERROR" "Neither ufw nor iptables available; cannot enforce default deny"
  return 1
}
