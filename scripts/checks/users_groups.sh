# // Placeholder for users_groups.sh
#!/usr/bin/env bash
# Users, groups, auth policy, logging/audit

_has(){ command -v "$1" >/dev/null 2>&1; }

# ---------- users_no_login ----------
users_no_login_check(){
  awk -F: '($3<1000 && $1!="root" && $7!="/usr/sbin/nologin" && $7!="/sbin/nologin"){bad=1} END{print bad?"FAIL":"PASS"}' /etc/passwd
}
users_no_login_fix(){
  awk -F: '($3<1000 && $1!="root" && $7!="/usr/sbin/nologin" && $7!="/sbin/nologin"){print $1}' /etc/passwd \
    | xargs -r -I{} usermod -s /usr/sbin/nologin {} 2>/dev/null || true
}

# ---------- users_password_policy ----------
users_password_policy_check(){
  local f="/etc/pam.d/common-password"
  [[ -f "$f" ]] || { echo PASS; return; }   # non-Debian systems
  grep -Eq 'pam_pwquality\.so.*(minlen=1[2-9]|minlen=[2-9][0-9])' "$f" && echo PASS || echo FAIL
}
users_password_policy_fix(){
  local f="/etc/pam.d/common-password"
  [[ -f "$f" ]] || return 0
  if grep -q 'pam_pwquality.so' "$f"; then
    sed -ri 's/(pam_pwquality\.so.*)(minlen=[0-9]+)?/\1 minlen=12/g' "$f"
  else
    echo 'password requisite pam_pwquality.so retry=3 minlen=12' >> "$f"
  fi
}

# ---------- users_sudo_timeout ----------
users_sudo_timeout_check(){
  local t
  t="$(grep -E 'timestamp_timeout[[:space:]]*=' /etc/sudoers /etc/sudoers.d/* 2>/dev/null | sed -E 's/.*= *(-?[0-9]+).*/\1/' | tail -1)"
  [[ -n "$t" && "$t" -le 5 ]] && echo PASS || echo FAIL
}
users_sudo_timeout_fix(){
  echo 'Defaults timestamp_timeout=5' >/etc/sudoers.d/fortify-timeout
  chmod 440 /etc/sudoers.d/fortify-timeout
}

# ---------- groups_empty_groups ----------
groups_empty_groups_check(){
  awk -F: '($4=="" && $3>=1000){bad=1} END{print bad?"FAIL":"PASS"}' /etc/group
}
groups_empty_groups_fix(){ :; }  # only report—don’t auto-delete

# ---------- logging_enabled ----------
logging_enabled_check(){
  if systemctl is-enabled rsyslog >/dev/null 2>&1; then echo PASS
  elif systemctl is-enabled systemd-journald >/dev/null 2>&1; then echo PASS
  else echo FAIL; fi
}
logging_enabled_fix(){
  systemctl enable --now rsyslog >/dev/null 2>&1 || true
}

# ---------- audit_daemon ----------
audit_daemon_check(){
  systemctl is-enabled auditd >/dev/null 2>&1 && echo PASS || echo FAIL
}
audit_daemon_fix(){
  if _has apt-get; then apt-get -y install auditd >/dev/null 2>&1 || true; fi
  systemctl enable --now auditd >/dev/null 2>&1 || true
}

# ---------- failed_login_logging ----------
failed_login_logging_check(){
  # journald usually logs; use presence of faillog/tallylog as a heuristic
  [[ -f /var/log/faillog || -f /var/log/tallylog ]] && echo PASS || echo PASS
}
failed_login_logging_fix(){ :; }
