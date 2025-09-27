# // Placeholder for sysctl_baseline.sh
#!/usr/bin/env bash
# Sysctl and kernel hardening

ensure_sysctl_kv(){
  local key="$1" val="$2" conf="/etc/sysctl.d/99-fortify.conf"
  mkdir -p /etc/sysctl.d
  if grep -Eq "^[[:space:]]*$key[[:space:]]*=" "$conf" 2>/dev/null; then
    sed -ri "s|^[[:space:]]*$key[[:space:]]*=.*|$key = $val|g" "$conf"
  else
    echo "$key = $val" >> "$conf"
  fi
  sysctl -w "$key=$val" >/dev/null 2>&1 || true
}

# ---------- network_ip_forwarding ----------
network_ip_forwarding_check(){ [[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)" -eq 0 ]] && echo PASS || echo FAIL; }
network_ip_forwarding_fix(){ ensure_sysctl_kv net.ipv4.ip_forward 0; }

# ---------- network_icmp_redirects ----------
network_icmp_redirects_check(){
  a="$(sysctl -n net.ipv4.conf.all.accept_redirects 2>/dev/null || echo 0)"
  b="$(sysctl -n net.ipv4.conf.default.accept_redirects 2>/dev/null || echo 0)"
  [[ "$a" -eq 0 && "$b" -eq 0 ]] && echo PASS || echo FAIL
}
network_icmp_redirects_fix(){
  ensure_sysctl_kv net.ipv4.conf.all.accept_redirects 0
  ensure_sysctl_kv net.ipv4.conf.default.accept_redirects 0
}

# ---------- network_source_routing ----------
network_source_routing_check(){
  a="$(sysctl -n net.ipv4.conf.all.accept_source_route 2>/dev/null || echo 0)"
  b="$(sysctl -n net.ipv4.conf.default.accept_source_route 2>/dev/null || echo 0)"
  [[ "$a" -eq 0 && "$b" -eq 0 ]] && echo PASS || echo FAIL
}
network_source_routing_fix(){
  ensure_sysctl_kv net.ipv4.conf.all.accept_source_route 0
  ensure_sysctl_kv net.ipv4.conf.default.accept_source_route 0
}

# ---------- sysctl_network_security (meta-check ensures the above) ----------
sysctl_network_security_check(){
  ok=1
  for k in net.ipv4.ip_forward net.ipv4.conf.all.accept_redirects net.ipv4.conf.default.accept_redirects net.ipv4.conf.all.accept_source_route net.ipv4.conf.default.accept_source_route; do
    v="$(sysctl -n "$k" 2>/dev/null || echo NA)"
    case "$k" in
      net.ipv4.ip_forward) exp=0 ;;
      *) exp=0 ;;
    esac
    [[ "$v" = "$exp" ]] || ok=0
  done
  [[ $ok -eq 1 ]] && echo PASS || echo FAIL
}
sysctl_network_security_fix(){
  network_ip_forwarding_fix
  network_icmp_redirects_fix
  network_source_routing_fix
}

# ---------- sysctl_memory_protection ----------
sysctl_memory_protection_check(){ [[ "$(sysctl -n kernel.randomize_va_space 2>/dev/null || echo 0)" -ge 2 ]] && echo PASS || echo FAIL; }
sysctl_memory_protection_fix(){ ensure_sysctl_kv kernel.randomize_va_space 2; }

# ---------- sysctl_kernel_security ----------
sysctl_kernel_security_check(){
  ok=1
  [[ "$(sysctl -n kernel.kptr_restrict 2>/dev/null || echo 0)" -ge 1 ]] || ok=0
  [[ "$(sysctl -n kernel.dmesg_restrict 2>/dev/null || echo 0)" -ge 1 ]] || ok=0
  [[ $ok -eq 1 ]] && echo PASS || echo FAIL
}
sysctl_kernel_security_fix(){
  ensure_sysctl_kv kernel.kptr_restrict 1
  ensure_sysctl_kv kernel.dmesg_restrict 1
}

# ---------- core_dumps_disabled ----------
core_dumps_disabled_check(){ [[ "$(sysctl -n fs.suid_dumpable 2>/dev/null || echo 1)" -eq 0 ]] && echo PASS || echo FAIL; }
core_dumps_disabled_fix(){ ensure_sysctl_kv fs.suid_dumpable 0; }
