#!/usr/bin/env bash
# SSH hardening checks/fixes
# Expects: create_backup, log_event, and systemctl/sshd/ssh present

SSH_CONF="/etc/ssh/sshd_config"

_has(){ command -v "$1" >/dev/null 2>&1; }
_reload_ssh(){
  if _has systemctl; then systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
  else service ssh reload 2>/dev/null || true
  fi
}

# ---------- ssh_permit_root_login ----------
ssh_permit_root_login_check(){
  [[ -f "$SSH_CONF" ]] || { echo FAIL; return; }
  awk 'tolower($1)=="permitrootlogin"{v=tolower($2)} END{print (v=="no"?"PASS":"FAIL")}' "$SSH_CONF"
}
ssh_permit_root_login_fix(){
  local bdir; bdir="$(create_backup "ssh_permit_root_login")"
  cp -p "$SSH_CONF" "$bdir/sshd_config.bak" 2>/dev/null || true
  if ! sshd -t 2>/dev/null; then log_event "ERROR" "sshd config invalid; aborting"; return 1; fi
  if grep -Eq '^[[:space:]]*PermitRootLogin[[:space:]]+(yes|prohibit-password|without-password)\b' "$SSH_CONF"; then
    sed -Ei 's/^[[:space:]]*PermitRootLogin[[:space:]]+(yes|prohibit-password|without-password)\b.*/PermitRootLogin no/' "$SSH_CONF"
  elif ! grep -Eq '^[[:space:]]*PermitRootLogin[[:space:]]+no\b' "$SSH_CONF"; then
    printf '\nPermitRootLogin no\n' >> "$SSH_CONF"
  fi
  sshd -t 2>/dev/null || { cp -p "$bdir/sshd_config.bak" "$SSH_CONF"; return 1; }
  _reload_ssh
  log_event "INFO" "PermitRootLogin set to no"
}

# ---------- ssh_password_auth ----------
ssh_password_auth_check(){
  [[ -f "$SSH_CONF" ]] || { echo FAIL; return; }
  awk 'tolower($1)=="passwordauthentication"{v=tolower($2)} END{print (v=="no"?"PASS":"FAIL")}' "$SSH_CONF"
}
ssh_password_auth_fix(){
  local bdir; bdir="$(create_backup "ssh_password_auth")"
  cp -p "$SSH_CONF" "$bdir/sshd_config.bak" 2>/dev/null || true
  if ! sshd -t 2>/dev/null; then log_event "ERROR" "sshd config invalid; aborting"; return 1; fi
  if grep -Eq '^[[:space:]]*PasswordAuthentication[[:space:]]+yes\b' "$SSH_CONF"; then
    sed -Ei 's/^[[:space:]]*PasswordAuthentication[[:space:]]+yes\b.*/PasswordAuthentication no/' "$SSH_CONF"
  elif ! grep -Eq '^[[:space:]]*PasswordAuthentication[[:space:]]+no\b' "$SSH_CONF"; then
    printf '\nPasswordAuthentication no\n' >> "$SSH_CONF"
  fi
  sshd -t 2>/dev/null || { cp -p "$bdir/sshd_config.bak" "$SSH_CONF"; return 1; }
  _reload_ssh
  log_event "INFO" "PasswordAuthentication set to no"
}

# ---------- ssh_empty_passwords ----------
ssh_empty_passwords_check(){
  [[ -f "$SSH_CONF" ]] || { echo FAIL; return; }
  awk 'tolower($1)=="permitemptypasswords"{v=tolower($2)} END{print (v=="no"?"PASS":"FAIL")}' "$SSH_CONF"
}
ssh_empty_passwords_fix(){
  local bdir; bdir="$(create_backup "ssh_empty_passwords")"
  cp -p "$SSH_CONF" "$bdir/sshd_config.bak" 2>/dev/null || true
  if ! sshd -t 2>/dev/null; then log_event "ERROR" "sshd config invalid; aborting"; return 1; fi
  if grep -Eq '^[[:space:]]*PermitEmptyPasswords[[:space:]]+yes\b' "$SSH_CONF"; then
    sed -Ei 's/^[[:space:]]*PermitEmptyPasswords[[:space:]]+yes\b.*/PermitEmptyPasswords no/' "$SSH_CONF"
  elif ! grep -Eq '^[[:space:]]*PermitEmptyPasswords[[:space:]]+no\b' "$SSH_CONF"; then
    printf '\nPermitEmptyPasswords no\n' >> "$SSH_CONF"
  fi
  sshd -t 2>/dev/null || { cp -p "$bdir/sshd_config.bak" "$SSH_CONF"; return 1; }
  _reload_ssh
  log_event "INFO" "PermitEmptyPasswords set to no"
}

# ---------- ssh_protocol_version ----------
# Modern OpenSSH defaults to protocol 2 only; treat OpenSSH >=7 as PASS.
ssh_protocol_version_check(){
  ssh -V 2>&1 | grep -Eq 'OpenSSH_([7-9]|[1-9][0-9])' && echo PASS || echo FAIL
}
ssh_protocol_version_fix(){
  # For legacy configs, enforce Protocol 2 (harmless on modern)
  if [[ -f "$SSH_CONF" ]]; then
    if grep -Eq '^[[:space:]]*Protocol\b' "$SSH_CONF"; then
      sed -Ei 's/^[[:space:]]*Protocol\b.*/Protocol 2/' "$SSH_CONF"
    else
      printf '\nProtocol 2\n' >> "$SSH_CONF"
    fi
    _reload_ssh
  fi
}

# ---------- ssh_max_auth_tries ----------
ssh_max_auth_tries_check(){
  [[ -f "$SSH_CONF" ]] || { echo FAIL; return; }
  awk 'tolower($1)=="maxauthtries"{v=$2} END{print (v!="" && v<=4?"PASS":"FAIL")}' "$SSH_CONF"
}
ssh_max_auth_tries_fix(){
  if grep -Eq '^[[:space:]]*MaxAuthTries\b' "$SSH_CONF"; then
    sed -Ei 's/^[[:space:]]*MaxAuthTries\b.*/MaxAuthTries 4/' "$SSH_CONF"
  else
    printf '\nMaxAuthTries 4\n' >> "$SSH_CONF"
  fi
  _reload_ssh
}

# ---------- ssh_client_alive ----------
ssh_client_alive_check(){
  [[ -f "$SSH_CONF" ]] || { echo FAIL; return; }
  iv=$(awk 'tolower($1)=="clientaliveinterval"{print $2}' "$SSH_CONF" | tail -1)
  cm=$(awk 'tolower($1)=="clientalivecountmax"{print $2}' "$SSH_CONF" | tail -1)
  [[ -n "$iv" && -n "$cm" && "$iv" -le 300 && "$cm" -le 3 ]] && echo PASS || echo FAIL
}
ssh_client_alive_fix(){
  if grep -Eq '^[[:space:]]*ClientAliveInterval\b' "$SSH_CONF"; then
    sed -Ei 's/^[[:space:]]*ClientAliveInterval\b.*/ClientAliveInterval 300/' "$SSH_CONF"
  else
    printf '\nClientAliveInterval 300\n' >> "$SSH_CONF"
  fi
  if grep -Eq '^[[:space:]]*ClientAliveCountMax\b' "$SSH_CONF"; then
    sed -Ei 's/^[[:space:]]*ClientAliveCountMax\b.*/ClientAliveCountMax 3/' "$SSH_CONF"
  else
    printf '\nClientAliveCountMax 3\n' >> "$SSH_CONF"
  fi
  _reload_ssh
}
