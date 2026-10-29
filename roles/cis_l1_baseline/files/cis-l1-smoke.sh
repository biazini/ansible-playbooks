#!/usr/bin/env bash
# Quick post-run smoke test for the cis_l1_baseline role.
# shellcheck disable=SC2015  # ok()/ko() always return 0
# NOT a compliance audit - use CIS-CAT Pro, USG (Ubuntu Pro) or
# ansible-lockdown/UBUNTU26-CIS-Audit (goss) for that.
# Usage: playbooks/smoke.yml (Ascender "Ubuntu CIS L1 - Smoke test"),
#        or on the host: sudo ./cis-l1-smoke.sh
set -u

pass=0; fail=0
ok()  { printf '  [PASS] %s\n' "$1"; pass=$((pass+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); }
chk() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else ko "$1"; fi; }

if [[ $EUID -ne 0 ]]; then echo "Run as root"; exit 2; fi

echo "== Mounts"
for m in /tmp /dev/shm; do
  opts=$(findmnt -n -o OPTIONS "$m" 2>/dev/null || true)
  for o in nodev nosuid noexec; do
    [[ ",$opts," == *",$o,"* ]] && ok "$m has $o" || ko "$m has $o (reboot pending?)"
  done
done

echo "== Kernel modules"
for mod in cramfs freevxfs hfs hfsplus jffs2 usb-storage firewire-core \
           atm can dccp rds sctp tipc; do
  chk "$mod not loadable" "modprobe -n -v $mod | grep -Eq 'install /(usr/)?bin/(true|false)'"
done
chk "iso9660 still loadable (vSphere customisation)" "! grep -rqs 'install iso9660' /etc/modprobe.d"

echo "== SSH (effective config)"
T=$(sshd -T 2>/dev/null)
exp() { grep -qi "^$1 $2\$" <<<"$T" && ok "sshd $1 $2" || ko "sshd $1 $2 (got: $(grep -i "^$1 " <<<"$T"))"; }
exp permitrootlogin no
exp passwordauthentication no
exp maxauthtries 4
exp clientaliveinterval 15
exp clientalivecountmax 3
exp permitemptypasswords no
grep -qi '^allowgroups ' <<<"$T" && ok "AllowGroups set" || ko "AllowGroups set"
# CIS 5.1.17 weak MAC list (26.04 adds umac-128-etm)
grep -Piq '^macs\h+([^#]+,)?(hmac-md5|hmac-ripemd160|hmac-sha1-96|umac-64|umac-128-etm)' <<<"$T" \
  && ko "no weak MACs" || ok "no weak MACs"

echo "== Firewall"
chk "ufw active" "ufw status | grep -q '^Status: active'"
chk "default deny incoming" "ufw status verbose | grep -q 'deny (incoming)'"
chk "SSH rule present" "ufw status | grep -Eq '^22/tcp'"
chk "no rollback timer left armed" "! systemctl is-active --quiet cis-ufw-rollback.timer"

echo "== Sysctl"
for kv in kernel.randomize_va_space=2 net.ipv4.conf.all.accept_redirects=0 \
          net.ipv4.conf.all.log_martians=1 net.ipv4.tcp_syncookies=1 fs.suid_dumpable=0 \
          kernel.dmesg_restrict=1 fs.protected_hardlinks=1; do
  k=${kv%%=*}; v=${kv#*=}
  [[ "$(sysctl -n "$k" 2>/dev/null)" == "$v" ]] && ok "$k=$v" || ko "$k=$v (got $(sysctl -n "$k" 2>/dev/null))"
done

echo "== Services / misc"
chk "chrony active" "systemctl is-active --quiet chrony"
chk "AppArmor enabled" "aa-enabled -q"
chk "APT template dir off /tmp" "apt-config dump | grep -q 'ExtractTemplates::TempDir \"/var/cache/apt/tmp\"'"
chk "grub.cfg 0600" "[[ \$(stat -c %a /boot/grub/grub.cfg) == 600 ]]"
chk "AIDE installed" "dpkg -s aide"
chk "APT Check-Date explicit" "apt-config dump | grep -q 'Acquire::Check-Date \"true\"'"
chk "cron.yearly 0700" "[[ \$(stat -c %a /etc/cron.yearly) == 700 ]]"

echo "== PAM"
chk "pam_unix without nullok" "! grep -Pqs '^\h*[^#]+\h+pam_unix\.so\h+([^#]+\h+)?nullok\b' /etc/pam.d/common-{auth,password,account,session}"
chk "su restricted by pam_wheel" "grep -Pq '^\h*auth\h+required\h+pam_wheel\.so\h+.*group=' /etc/pam.d/su"

if [[ "$(systemd-detect-virt 2>/dev/null)" == "vmware" ]]; then
  echo "== VMware guest"
  chk "open-vm-tools active" "systemctl is-active --quiet open-vm-tools"
  chk "Tools periodic time sync disabled (chrony only)" "vmware-toolbox-cmd timesync status | grep -qi disabled"
fi

echo "== Automation path"
u=${CIS_AUTOMATION_USER:-ansible}
chk "$u has no password hash (key-only)" "[[ \$(getent shadow $u | cut -d: -f2) != \\\$* ]]"
chk "$u never expires" "chage -l $u | grep -q 'Password expires.*never'"
chk "$u home is not noexec" "! findmnt -n -o OPTIONS --target ~$u | grep -q noexec"

echo
echo "Result: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
