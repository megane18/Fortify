# // Placeholder for world_writable.sh
#!/usr/bin/env bash
# Filesystem, permissions, boot/grub

# ---------- world_writable_files ----------
world_writable_files_check(){
  if find / \( -path /proc -o -path /sys -o -path /dev -o -path /run \) -prune -o -type f -perm -0002 -print -quit 2>/dev/null | grep -q .; then
    echo FAIL
  else
    echo PASS
  fi
}
world_writable_files_fix(){
  find / \( -path /proc -o -path /sys -o -path /dev -o -path /run \) -prune -o -type f -perm -0002 -exec chmod o-w {} + 2>/dev/null || true
}

# ---------- sticky_bit_dirs ----------
sticky_bit_dirs_check(){ find /tmp -maxdepth 0 -type d -perm -1000 2>/dev/null | grep -q . && echo PASS || echo FAIL; }
sticky_bit_dirs_fix(){ chmod +t /tmp 2>/dev/null || true; }

# ---------- suid_sgid_files ----------
suid_sgid_files_check(){
  if find / -xdev \( -perm -4000 -o -perm -2000 \) -type f -print -quit 2>/dev/null | grep -q .; then
    echo FAIL   # existence requires review; fail to raise visibility
  else
    echo PASS
  fi
}
suid_sgid_files_fix(){ :; }  # conservative: report only

# ---------- file_permissions_critical ----------
file_permissions_critical_check(){
  ok=1
  [[ -f /etc/shadow ]] && [[ "$(stat -c '%a' /etc/shadow 2>/dev/null)" -le 640 ]] || ok=0
  [[ -f /etc/passwd ]] && [[ "$(stat -c '%a' /etc/passwd 2>/dev/null)" -le 644 ]] || ok=0
  [[ $ok -eq 1 ]] && echo PASS || echo FAIL
}
file_permissions_critical_fix(){
  [[ -f /etc/shadow ]] && chmod 640 /etc/shadow || true
  [[ -f /etc/passwd ]] && chmod 644 /etc/passwd || true
}

# ---------- boot_permissions ----------
boot_permissions_check(){
  [[ -d /boot ]] || { echo FAIL; return; }
  perms="$(stat -c '%a' /boot 2>/dev/null || echo 755)"
  [[ "$perms" -le 755 ]] && echo PASS || echo FAIL
}
boot_permissions_fix(){ chmod 755 /boot 2>/dev/null || true; }

# ---------- grub_password ----------
grub_password_check(){ grep -Rqs '^set superusers=' /etc/grub.d && echo PASS || echo FAIL; }
grub_password_fix(){ :; }  # interactive secret—do not auto-set
