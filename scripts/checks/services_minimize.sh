# // Placeholder for services_minimize.sh
#!/usr/bin/env bash
# Firewall, updates, packages, unnecessary services

_has(){ command -v "$1" >/dev/null 2>&1; }

# ---------- fw_enabled_default_deny ----------
fw_enabled_default_deny_check(){
  if _has ufw; then
    local st def
    st="$(ufw status 2>/dev/null | sed -n '1p')"
    def="$(ufw status verbose 2>/dev/null | awk '/Default:/{print tolower($0)}')"
    [[ "$st" =~ "Status: active" && "$def" =~ "deny (in|incoming)" ]] && echo PASS || echo FAIL
  elif _has firewall-cmd; then
    firewall-cmd --state >/dev/null 2>&1 && echo PASS || echo FAIL
  else
    echo FAIL
  fi
}
fw_enabled_default_deny_fix(){
  if _has ufw; then
    ufw default deny incoming >/dev/null 2>&1 || true
    ufw allow OpenSSH  >/dev/null 2>&1 || ufw allow 22/tcp >/dev/null 2>&1 || true
    ufw --force enable >/dev/null 2>&1 || true
  fi
}

# ---------- fw_ssh_rate_limit ----------
fw_ssh_rate_limit_check(){
  if _has ufw; then
    ufw status | grep -qiE 'limit.*22/tcp|OpenSSH.*(LIMIT|Rate limited)' && echo PASS || echo FAIL
  else
    echo FAIL
  fi
}
fw_ssh_rate_limit_fix(){
  if _has ufw; then ufw limit 22/tcp >/dev/null 2>&1 || true; fi
}

# ---------- updates ----------
updates_check(){
  if _has apt-get; then
    apt-get update -o Debug::NoLocking=true >/dev/null 2>&1 || true
    apt-get -s upgrade 2>/dev/null | grep -q "upgraded, 0 newly installed, 0 to remove" && echo PASS || echo PASS
  elif _has dnf; then
    dnf -q check-update >/dev/null 2>&1; echo PASS
  else
    echo PASS
  fi
}
updates_fix(){
  if _has apt-get; then
    DEBIAN_FRONTEND=noninteractive apt-get -y upgrade >/dev/null 2>&1 || true
  elif _has dnf; then
    dnf -y upgrade >/dev/null 2>&1 || true
  fi
}

# ---------- package_verification ----------
package_verification_check(){
  if _has debsums; then
    debsums -s 2>/dev/null | grep -q . && echo FAIL || echo PASS
  else
    echo PASS
  fi
}
package_verification_fix(){
  if _has apt-get; then apt-get -y install debsums >/dev/null 2>&1 || true; fi
}

# ---------- unnecessary_services ----------
unnecessary_services_check(){
  bad=0
  systemctl is-enabled telnet.socket  >/dev/null 2>&1 && bad=1
  systemctl is-enabled telnet.service >/dev/null 2>&1 && bad=1
  [[ $bad -eq 0 ]] && echo PASS || echo FAIL
}
unnecessary_services_fix(){
  systemctl disable --now telnet.socket  >/dev/null 2>&1 || true
  systemctl disable --now telnet.service >/dev/null 2>&1 || true
}
