# Ubuntu 26.04 LTS - CIS Level 1 Server baseline (automation-safe)

Ansible role that applies the CIS Ubuntu Linux 26.04 LTS **Level 1 - Server**
profile to VMware VMs built and managed with Packer, Terraform and Ansible,
without breaking the automation that builds and manages them.

> Status, 19 Oct 2026: CIS published *Ubuntu Linux 26.04 LTS Benchmark v1.0.0*
> (Sep 2026). This role is written from the 22.04/24.04 control set plus the
> 26.04 platform changes (sudo-rs, chrony, OpenSSH 10.2). **Download the 26.04
> PDF and reconcile control numbers and levels before claiming compliance.**
> Audit with an independent tool, not with this role.

---

## 1. Tooling decision

| Option | Use when | Notes |
|---|---|---|
| **Ubuntu Security Guide (USG)** - `usg audit` / `usg fix` + tailoring file | Hosts have Ubuntu Pro | Canonical-maintained. Check `pro status` on 26.04 for the `usg` service and a 26.04 profile before relying on it. Tailor with `usg generate-tailoring cis_level1_server tailor.xml`. |
| **ansible-lockdown UBUNTU26-CIS** | Want a community full-coverage role | Remediation role marked "coming soon" at time of writing; the **UBUNTU26-CIS-Audit** (goss) repo exists - use it to audit. |
| **This role** | Need L1 now, with explicit automation exceptions | Small, readable, every deviation is a variable. |
| **CIS-CAT Pro / Build Kits** | Formal evidence for auditors | Requires CIS SecureSuite membership. |

Recommended: **this role (or USG) to remediate, a different tool to audit.**

---

## 2. The four "pitfalls" - what is actually true

| # | Claim | Reality | What the role does |
|---|---|---|---|
| 1 | `noexec` on `/tmp` breaks Ansible | Mostly **false**. Ansible's default `remote_tmp` is `~/.ansible/tmp` (under `/home`), and modules run as `python3 AnsiballZ_*.py` - an interpreter reading a file is not blocked by noexec. What really breaks: **Terraform `remote-exec`** (uploads `/tmp/terraform_%RAND%.sh` and executes it), **Packer `shell`** (default `remote_folder=/tmp`), Ansible `script` module, vendor installers, and **debconf** (`apt-extracttemplates` runs config scripts from `/tmp`). Moving Ansible tmp to `/var/tmp` (as often suggested) is wrong: `/var/tmp` is also noexec under CIS. | Keeps noexec. `pipelining=true`. APT redirected to `/var/cache/apt/tmp`. Terraform `script_path` and Packer `remote_folder`/`execute_command` examples in `examples/`. |
| 2 | Default-deny firewall breaks cloud-init / VMware Tools | **Wrong mechanism.** vSphere metadata reaches cloud-init via VMware Tools (guestinfo through `vmtoolsd`/`vmware-rpctool`) or an attached OVF ISO - not via IP, so ufw cannot block it. What a default-deny **outbound** policy really breaks: DNS, DHCP, NTP/NTS (tcp/4460 on 26.04), APT/proxy, Kerberos/LDAP for AD join, syslog/agents. And the real risk is **locking yourself out** while enabling it. | Explicit egress allow-list; SSH only from `cis_mgmt_cidrs`; preflight aborts if the controller IP is outside them; **systemd timer auto-disables ufw** unless Ansible reconnects. |
| 3 | SSH `ClientAlive*` / `TMOUT` drop long Terraform/Ansible runs | **False.** `ClientAliveInterval`/`CountMax` detect *dead* peers - a live session answers the probe however long a task runs. `TMOUT` only applies to *interactive* shells waiting at a prompt; it never touches non-interactive SSH commands. What really bites automation: `AllowGroups` not including the automation user, `MaxAuthTries 4` with an ssh-agent full of keys, `DisableForwarding` on bastions (ProxyJump), `GSSAPIAuthentication no` with AD SSO, KEX lists too strict for old clients, and cloud-init's `50-cloud-init.conf` re-enabling password auth. | CIS values kept (15/3, 900s). `ServerAlive*` in `ansible.cfg`; `IdentitiesOnly=yes` only for local runs with `--private-key` (it breaks Ascender's ssh-agent keys). Drop-in `00-cis-hardening.conf` (first value wins in sshd), validated with `sshd -t` and rolled back on error; reconnect test after reload. |
| 4 | Disabling filesystem modules breaks cloud-init on ESXi | The L1 list (`cramfs`, `freevxfs`, `hfs`, `hfsplus`, `jffs2`, `usb-storage`) does not include what vSphere uses (`iso9660`). The modules that *do* hurt are **`squashfs` (kills snapd)** and `udf` - both Level 2 in 22.04/24.04 - and over-eager scripts that also disable `overlay`, `fuse`, `nfs`, `cifs`. | L1 list only; squashfs/udf opt-in; assertion refuses `iso9660` and `overlay`. |

---

## 3. Other things that break automation (and how they are handled)

| Area | Trap | Handling |
|---|---|---|
| Accounts | Password aging/expiry applied to the automation account -> with `UsePAM yes` an expired account cannot log in, even with a key | Automation account has `*` as password (no hash), `chage -M -1 -I -1 -E -1`; aging applied only to accounts with a real hash |
| PAM | Broken faillock/pwhistory stack locks humans out | Done via `pam-auth-update` profiles; key-based SSH never runs the PAM auth stack. **Test on a console first.** |
| sudo | 26.04 uses **sudo-rs**: `Defaults logfile` and I/O logging not supported, `use_pty` on by default | Role detects sudo-rs and skips `logfile`; logging comes from journald. Document this for the "sudo log file" control. |
| sudo | `NOPASSWD` | Level 2 in 22.04/24.04, so allowed at L1 for the automation group - confirm in the 26.04 PDF |
| GRUB | Bootloader password without `--unrestricted` -> every unattended reboot stops at a prompt | Optional; entries marked `--unrestricted` |
| AIDE | Baseline built inside the template | Never initialised when `cis_template_build=true`; init at first config run |
| sysctl | `ip_forward=0` on k8s/container hosts; `rp_filter=1` on multi-homed VMs; `accept_ra=0` with SLAAC | `cis_is_router`, `cis_rp_filter`, `cis_ipv6_accept_ra` |
| sysctl | ufw re-applies `/etc/ufw/sysctl.conf` and overrides CIS values | `IPT_SYSCTL` pointed at `/etc/sysctl.d/60-cis.conf` |
| Mounts | Remounting `/tmp` live hides files of running processes | fstab only, applied at reboot (`cis_allow_reboot`) |
| Firewall | `ufw limit` on SSH throttles Ansible/Packer bursts | Plain allow from mgmt CIDRs, no rate limit |
| Disk layout | Separate `/var`, `/var/log`, `/var/log/audit`, `/var/tmp`, `/home` | Decide in Packer autoinstall (Level 2 in 22.04/24.04) |
| auditd | Level 2 in 22.04/24.04. If added, `admin_space_left_action=halt` stops the VM when the disk fills; `-e 2` makes rule changes need a reboot | Not in this role |

---

## 4. Exceptions register (fill in before go-live)

| Control (24.04 wording) | Deviation | Scope | Justification | Compensating control |
|---|---|---|---|---|
| sshd DisableForwarding | `no` | `bastions` group | ProxyJump for automation | SSH only from mgmt CIDRs, MFA on bastion |
| ufw default deny outgoing | allow-list | all | Required egress only | Rules reviewed per release |
| sudo log file | journald instead of `logfile` | all (sudo-rs) | Not supported by sudo-rs | Journald persistent + central log |
| squashfs disabled | not disabled | hosts with snaps | snapd dependency | Snap confinement / AppArmor |
| ip_forward = 0 | `1` | k8s nodes | CNI routing | NetworkPolicy, node firewall |
| _add yours_ | | | | |

---

## 5. Rollout

```bash
pip install ansible-core netaddr
ansible-galaxy collection install -r collections/requirements.yml

# 1. Edit inventories/<env>/group_vars/all.yml (keys, mgmt CIDRs, egress, NTP)
# 2. Lab VM, vSphere console open:
ansible-playbook playbooks/site.yml --limit lab-ubu2604-01 --check --diff
ansible-playbook playbooks/site.yml --limit lab-ubu2604-01 --diff
# 3. Reboot (applies /tmp), then:
sudo ./scripts/cis-l1-smoke.sh
# 4. Independent audit (USG / CIS-CAT / UBUNTU26-CIS-Audit), fix or register exceptions
# 5. Packer golden image: site.yml -e cis_template_build=true, then seal-template.yml
# 6. Fleet: serial 20%, max_fail_percentage 0
```

Re-run the playbook on a schedule (Ascender/AWX schedule, see section 7): package updates
(grub, openssh) can revert permissions or files.

### Host-type overrides

| Host type | Variables |
|---|---|
| Bastion | `cis_ssh_disable_forwarding: false` |
| Kubernetes / Docker | `cis_is_router: true`; review ufw vs CNI (Docker bypasses ufw) |
| NFS client/server | remove `rpcbind` from `cis_remove_packages` |
| Snap workloads (LXD, livepatch) | keep `cis_disable_squashfs: false` |
| AD-joined with Kerberos SSO | `cis_ssh_gssapi: true`, egress 88/389/636/464 to DCs |
| Multi-NIC asymmetric routing | `cis_rp_filter: 2` (exception) |

---

## 6. Layout

```
ansible.cfg                     pipelining, ServerAlive, IdentitiesOnly, remote_tmp in $HOME
collections/requirements.yml    collections (Ascender installs them on project sync)
inventories/lab/                VirtualBox lab VM managed by Ascender (hosts + group_vars)
inventories/example/            reference inventory for a vSphere estate
playbooks/bootstrap.yml         one-off: create the key-only automation account (svc_ansible)
playbooks/ping.yml              connectivity + sudo check
playbooks/site.yml              apply baseline
playbooks/smoke.yml             run scripts/cis-l1-smoke.sh on the targets
playbooks/seal-template.yml     Packer: clean identity before template conversion
roles/cis_l1_baseline/          the role (defaults = every tunable/exception)
examples/                       Terraform connection block, Packer fragment
scripts/cis-l1-smoke.sh         quick post-run checks (not an audit)
```

---

## 7. Ascender (AWX)

Objects in organization **Linux Infrastructure**:

| Object | Name | Notes |
|---|---|---|
| Project | Linux Playbooks | this repo, branch `main`, credential `GitHub - ansible-playbooks` |
| Inventory | Linux Inventory | source `Linux Playbooks` -> `inventories/lab/hosts.yml` (group_vars come with it) |
| Credential | Ubuntu VM - bootstrap (gfilho) | Machine; password and become password **prompted at launch** |
| Credential | Ubuntu VM - svc_ansible (SSH key) | Machine; key-only automation account, sudo NOPASSWD |
| Job template | Ubuntu VM - Bootstrap automation user | `playbooks/bootstrap.yml`, bootstrap credential, run once |
| Job template | Ubuntu VM - Ping | `playbooks/ping.yml` |
| Job template | Ubuntu CIS L1 - Check (dry run) | `playbooks/site.yml`, check mode + diff |
| Job template | Ubuntu CIS L1 - Apply | `playbooks/site.yml`, diff |
| Job template | Ubuntu CIS L1 - Smoke test | `playbooks/smoke.yml` |

Order for a new host: add it to `inventories/lab/hosts.yml` -> sync the
inventory source -> **Bootstrap** (enter the sudo user's password) -> **Ping**
-> **Check (dry run)** -> snapshot the VM -> **Apply** (keep the VM console
open) -> reboot -> **Smoke test**.

After **Apply**: SSH accepts keys only, from `cis_mgmt_cidrs` only, for members
of `automation` or `sshusers`. Add human admins to `sshusers` (and give them a
key) before applying, or use the VM console.
