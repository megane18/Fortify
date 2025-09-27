# Server Fortify profile — comprehensive server hardening
# Format: check_name weight

# SSH Security
ssh_permit_root_login           15
ssh_password_auth               15
ssh_empty_passwords             20
ssh_protocol_version            10
ssh_max_auth_tries              10
ssh_client_alive                10

# Firewall & Network
#the first 2
# fw_enabled_default_deny         15
# fw_ssh_rate_limit               10
network_ip_forwarding           10
network_icmp_redirects          10
network_source_routing          10

# System Updates & Packages
updates                         20
package_verification            15
unnecessary_services            15

# File System Security
world_writable_files            15
sticky_bit_dirs                 10
#this
# suid_sgid_files                 20
file_permissions_critical       15

# User & Group Security
users_no_login                  10
users_password_policy           15
users_sudo_timeout              10
#this
# groups_empty_groups             5

# Kernel & System Parameters
sysctl_network_security         15
sysctl_memory_protection        10
sysctl_kernel_security          15

# Logging & Monitoring
logging_enabled                 10
audit_daemon                    15
failed_login_logging            10

# Boot & System Integrity
#THIS
# grub_password                   15
boot_permissions                10
core_dumps_disabled             10
