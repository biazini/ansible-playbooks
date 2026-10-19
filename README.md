# Ansible Automation Content — Linux Infrastructure

Playbooks, roles and inventories that manage the Linux estate, executed from the **Ascender Automation Platform**. Git is the single source of truth: Ascender pulls this repository, and every change to a managed host comes from a reviewed commit here. The first content delivered is a **CIS Level 1 Server baseline for Ubuntu 26.04 LTS**, built to stay safe for unattended automation.

| | |
|---|---|
| **Validated with** | Ascender 25.6.2 · Execution Environment `ascender-ee:25.6.2` (ansible-core 2.16) · k3s `v1.36.5+k3s1` |
| **Managed platform** | Ubuntu 26.04 LTS (also 24.04 LTS), x86_64 |
| **Content** | Roles `ubuntu_base` and `cis_l1_baseline` · 6 playbooks · lab inventory |

![Ansible for Ascender — Linux Infrastructure](docs/images/cover.png)

## Contents

1. [Solution architecture](#1-solution-architecture)
2. [Introduction](#2-introduction)
3. [Prerequisites](#3-prerequisites)
4. [Software bill of materials](#4-software-bill-of-materials)
5. [Onboarding procedure](#5-onboarding-procedure)
6. [Development workflow](#6-development-workflow)
7. [Operations](#7-operations)
8. [Troubleshooting](#8-troubleshooting)
9. [Lessons learned](#9-lessons-learned)
- [Appendix A — Repository files](#appendix-a--repository-files)
- [Appendix B — References](#appendix-b--references)
- [License](#license)

### Repository layout

```text
.
├── .github/                      Security policy, code of conduct, contributing notes, templates
├── README.md                     This guide
├── LICENSE                       MIT License (code and configuration)
├── LICENSE-CC-BY-4.0             CC BY 4.0 (documentation and diagrams)
├── ansible.cfg                   Shared Ansible settings, picked up by Ascender
├── .ansible-lint                 Lint configuration for the whole repository
├── collections/
│   └── requirements.yml          Collections installed by Ascender on every project sync
├── docs/
│   ├── architecture/             HLD and LLD (draw.io sources + PNG exports)
│   └── images/                   Cover image
├── inventories/
│   └── lab/                      hosts.yml + group_vars/ (one folder per environment)
├── playbooks/                    Entry points, one per job template
└── roles/
    ├── cis_l1_baseline/          CIS Level 1 role, documented in its own README
    └── ubuntu_base/              General Ubuntu settings outside CIS (keyboard, clean initramfs)
```

### Conventions

| Convention | Meaning |
|---|---|
| `bash` blocks | Commands run in a shell on the engineer workstation (WSL) or on a managed host, as stated in the step. |
| **Ascender →** | Path in the Ascender web console, e.g. **Ascender → Resources → Templates**. |
| `<VALUE>` | Site-specific value, e.g. `<HOST>` for an inventory host name. |
| ✅ **Expected result** | Output that confirms the step completed successfully. Do not proceed until it is met. |

---

## 1. Solution architecture

### 1.1 High-Level Design (HLD)

![Ansible automation HLD](docs/architecture/Ansible-Automation-HLD.png)

*Figure 1 — Ansible automation content HLD (source: [`Ansible-Automation-HLD.drawio`](docs/architecture/Ansible-Automation-HLD.drawio))*

### 1.2 Low-Level Design (LLD)

![Ansible automation LLD](docs/architecture/Ansible-Automation-LLD.png)

*Figure 2 — Lab deployment LLD (source: [`Ansible-Automation-LLD.drawio`](docs/architecture/Ansible-Automation-LLD.drawio))*

### 1.3 Architecture summary

Figure 1 is the logical view: engineers change content in Git, Ascender turns that content into job templates, and the Execution Environment applies it to the managed servers over SSH. Figure 2 is the lab as built: Ascender runs on k3s inside WSL2 on a Windows 11 workstation, and the managed host is an Ubuntu 26.04 VM in VirtualBox on the same machine, reached through a port forward and a relay.

- **Source control** — private GitHub repository `biazini/ansible-playbooks`, branch `main`. Ascender reads it with a fine-grained token that can only read this repository.
- **Control plane** — Ascender 25.6.2, organization **Linux Infrastructure**: project, inventory, credentials, job templates and team.
- **Execution** — every job runs in a pod from `ascender-ee:25.6.2` (ansible-runner, ansible-core 2.16, the collections and `netaddr`). The machine credential is loaded into an ssh-agent for the duration of the job only.
- **Managed hosts** — Ubuntu servers in inventory group `ubuntu_cis_l1`, administered through the key-only account `svc_ansible`.

### 1.4 Component inventory

| Component | Object / location | Responsibility |
|---|---|---|
| Repository | `github.com/biazini/ansible-playbooks` (private) | Playbooks, roles, inventories, collection requirements, documentation. |
| Project | **Linux Playbooks** · credential `GitHub - ansible-playbooks` | Clones `main` into Ascender and installs `collections/requirements.yml` on every sync. |
| Inventory | **Linux Inventory** · source `Linux Playbooks - lab` | Loads `inventories/lab/hosts.yml` and its `group_vars/`; syncs on every job launch. |
| Source control credential | `GitHub - ansible-playbooks` | GitHub user + fine-grained token (contents: read-only, this repository only). |
| Machine credential | `Ubuntu VM - svc_ansible (SSH key)` | Key-only automation account, sudo without password. Used by every job except bootstrap. |
| Machine credential | `Ubuntu VM - bootstrap (gfilho)` | Existing sudo user; SSH and sudo passwords are asked at launch and never stored. |
| Job templates | Bootstrap · Ping · Base Apply · CIS Check (dry run) · CIS Apply · Smoke test | Project + inventory + credential + playbook (see [2.3](#23-content-catalogue)). |
| Team | **Linux Team** | Receives roles on the templates it operates. |
| Execution Environment | `ghcr.io/ctrliq/ascender-ee:25.6.2` | Runtime of every project sync, inventory sync and job. |
| SSH relay (lab) | systemd unit `vbox-ubuntu-ssh-relay` in WSL (socat) | Bridges the k3s pod network to the VirtualBox port forward. |
| Port forward (lab) | VirtualBox NAT rule `ssh-ascender` | `127.0.0.1:2222` on Windows → VM port 22. |

### 1.5 Network flows and ports

| # | Source → Destination | Protocol / port | Purpose |
|---|---|---|---|
| 1 | Ascender task pod → `github.com` | HTTPS 443/tcp | Project sync (`git`) with the fine-grained token. |
| 2 | Ascender task pod → `galaxy.ansible.com` | HTTPS 443/tcp | Collections from `collections/requirements.yml`. |
| 3 | Execution Environment → `10.42.0.1:2223` | SSH (TCP) | Job traffic to the lab VM, through the relay on the k3s bridge. |
| 4 | Relay → `127.0.0.1:2222` (Windows) | TCP | WSL2 mirrored networking shares the Windows loopback. |
| 5 | VirtualBox NAT → VM `10.0.2.15:22` | SSH 22/tcp | Arrives from the NAT gateway `10.0.2.2`, the only SSH source allowed by the host firewall. |
| 6 | VM → Internet | DNS 53, DHCP 67, NTP 123, NTS-KE 4460, HTTP/HTTPS 80/443 | Egress allow-list of the CIS firewall (resolution, lease, time, packages). |
| 7 | Administrator browser → `ascender.localhost` | HTTP 80/tcp | Web console and REST API (`/api/v2`). |

### 1.6 Design decisions

| Decision | Rationale |
|---|---|
| Git as the only source of change | Every host change is reviewable, reversible with `git revert`, and identical in every run. Nothing is edited by hand in Ascender except credentials. |
| Thin playbooks, logic in roles | A role is written and documented once and reused by several playbooks and job templates. |
| Inventory and variables in Git, loaded as an inventory source | Hosts and their settings are versioned with the code that uses them; `group_vars/` travel with `hosts.yml`. |
| Collections pinned in `collections/requirements.yml` | Jobs do not depend on what happens to be installed in the Execution Environment image. |
| Dedicated key-only automation account (`svc_ansible`) | No password to expire, leak or be locked out by PAM; access is revoked by removing one key. |
| Passwords asked at launch for bootstrap | The only password-based job never stores the password in Ascender. |
| Check mode before every first apply | The dry run shows every change as a diff before anything is touched. |
| Hardening built for automation | The CIS role never removes the access it relies on: preflight checks, validated SSH changes and a firewall that rolls itself back (see the [role README](roles/cis_l1_baseline/README.md)). |
| Relay bound to the k3s bridge only (lab) | Pods reach the VM, the LAN does not: the port forward listens on loopback and the relay on `10.42.0.1`. |

---

## 2. Introduction

### 2.1 Purpose

Provide versioned, reviewable automation content for the Linux estate and a documented way to run it from Ascender: from onboarding a new server to keeping it compliant.

### 2.2 Scope

- **In scope** — Ubuntu 26.04 / 24.04 LTS servers; the CIS Level 1 Server baseline; the Ascender objects that run the content; the lab network path.
- **Out of scope** — installing Ascender itself (see [ascender-k3s-installation](https://github.com/biazini/ascender-k3s-installation)); operating-system installation and disk layout; formal CIS compliance evidence (needs an independent audit tool).

### 2.3 Content catalogue

| Playbook | Hosts | Job template | What it does |
|---|---|---|---|
| `playbooks/bootstrap.yml` | `ubuntu_cis_l1`, `bastions` | Ubuntu VM - Bootstrap automation user | Once per host: creates `svc_ansible` (key, group, NOPASSWD sudo) as an existing sudo user. |
| `playbooks/ping.yml` | all | Ubuntu VM - Ping | SSH login, privilege escalation, OS and kernel report. Read-only. |
| `playbooks/base.yml` | `ubuntu_cis_l1`, `bastions` | Ubuntu Base - Apply | Applies role `ubuntu_base` (console keyboard layout, clean initramfs); job type Check or Run at launch. |
| `playbooks/site.yml` | `ubuntu_cis_l1`, `bastions` | Ubuntu CIS L1 - Check (dry run) / Apply | Applies role `cis_l1_baseline`; the Check template runs it in check mode with diff. |
| `playbooks/smoke.yml` | `ubuntu_cis_l1`, `bastions` | Ubuntu CIS L1 - Smoke test | Runs the role's smoke script and fails if any check fails. |
| `playbooks/seal-template.yml` | all | — | Image builds only: removes host identity before a VM becomes a template. |

| Role | Purpose | Documentation |
|---|---|---|
| `ubuntu_base` | General Ubuntu settings outside CIS: console keyboard layout (pt), initramfs without unused dracut modules | [roles/ubuntu_base/README.md](roles/ubuntu_base/README.md) |
| `cis_l1_baseline` | CIS Ubuntu 26.04 Level 1 Server hardening, safe for unattended automation | [roles/cis_l1_baseline/README.md](roles/cis_l1_baseline/README.md) |

---

## 3. Prerequisites

### 3.1 Controller

- Ascender 25.6.2 reachable by the operators, with organization **Linux Infrastructure** and the objects in [1.4](#14-component-inventory).
- Outbound HTTPS from the Ascender pods to GitHub, Ansible Galaxy and `ghcr.io`.

### 3.2 Managed hosts

| Requirement | Why |
|---|---|
| Ubuntu 26.04 or 24.04 LTS, `python3` | Supported releases of the CIS role; Ansible modules run with the host's Python. |
| `openssh-server` installed and running | Ubuntu Desktop images do not include it; Ascender connects over SSH. |
| A sudo-capable user and its password (first run only) | Used once by the bootstrap job to create `svc_ansible`. |
| Network path from the Execution Environment to port 22 | The source address must be listed in `cis_mgmt_cidrs` before the CIS firewall is applied. |
| Console access (hypervisor or iLO/iDRAC) | Recovery path during the first hardening run. |

### 3.3 Engineer workstation

`git`, `ansible-core` and `ansible-lint` (WSL: `sudo apt install ansible ansible-lint`), and a GitHub account with write access to this repository.

---

## 4. Software bill of materials

### 4.1 Platform

| Component | Version | Notes |
|---|---|---|
| Ascender | 25.6.2 | `ghcr.io/ctrliq/ascender:25.6.2`, operator `ascender-operator:25.6.2` |
| k3s | v1.36.5+k3s1 | Single node in WSL2 (Ubuntu 26.04.1, mirrored networking) |
| Oracle VirtualBox | 7.2.6 | Runs on Hyper-V (NEM) because WSL2 is enabled |

### 4.2 Execution Environment (`ascender-ee:25.6.2`)

| Component | Version |
|---|---|
| ansible-core | 2.16.19 |
| community.general | 13.4.0 (requirement `>=9.0.0`) |
| ansible.posix | 2.2.2 (requirement `>=1.5.0`) |
| ansible.utils | 6.1.0 (requirement `>=4.0.0`) |
| netaddr (Python) | 1.3.0 |

### 4.3 Managed host (lab)

| Component | Version |
|---|---|
| Ubuntu | 26.04.1 LTS, kernel 7.0.0-38-generic |
| OpenSSH | 10.2p1 |
| sudo | sudo-rs 0.2.13 (classic sudo available as `sudo.ws`) |
| Python | 3.14.4 |

### 4.4 Engineer tooling

| Component | Version |
|---|---|
| ansible-core (WSL) | 2.20.1 |
| ansible-lint | 26.1.1 |

---

## 5. Onboarding procedure

Bring a new Ubuntu server under management and apply the CIS baseline. Run the job templates from **Ascender → Resources → Templates**.

### 5.1 Phase 1 — Prepare the host

On the host console:

```bash
sudo apt update && sudo apt install -y openssh-server
```
```bash
sudo systemctl enable --now ssh && sudo ss -ltnp | grep ':22 '
```

✅ **Expected result** — `sshd` is listening on port 22.

### 5.2 Phase 2 — Add the host to the inventory

Add the host under group `ubuntu_cis_l1` in `inventories/<env>/hosts.yml` with its `ansible_host` (and `ansible_port` if not 22). Check that the address Ascender connects from is in `cis_mgmt_cidrs` in `group_vars/all.yml`, then commit and push (see [6](#6-development-workflow)). The inventory source syncs on the next job launch.

✅ **Expected result** — **Ascender → Inventories → Linux Inventory → Hosts** lists `<HOST>` after the next sync.

### 5.3 Phase 3 — Bootstrap the automation account

Launch **Ubuntu VM - Bootstrap automation user** with **Limit** `<HOST>`. Enter the sudo user's password in **SSH password** and **Privilege escalation password**.

✅ **Expected result** — `failed=0`; tasks *Group exists*, *User exists*, *Authorized keys* and *Group allowed to sudo* report `changed` on the first run.

### 5.4 Phase 4 — Connectivity check and base settings

Launch **Ubuntu VM - Ping**, then **Ubuntu Base - Apply**.

✅ **Expected result** — `SSH login as svc_ansible, become -> root` and `failed=0` for both; the base job rebuilds the initramfs (effective at the reboot in Phase 7).

### 5.5 Phase 5 — Dry run

Launch **Ubuntu CIS L1 - Check (dry run)** and read the diff of every changed task.

✅ **Expected result** — `failed=0`. The preflight assertions pass (connecting address inside `cis_mgmt_cidrs`, user allowed by `AllowGroups`).

### 5.6 Phase 6 — Apply the baseline

Take a snapshot or backup of the host (powered off for VirtualBox, see [7.4](#74-snapshots-of-the-lab-vm)) and keep its console open. Launch **Ubuntu CIS L1 - Apply**.

✅ **Expected result** — `failed=0`; *SSH | Fresh login works* and *Firewall | New SSH session gets through the firewall* report `ok`; the summary asks for a reboot.

### 5.7 Phase 7 — Reboot and verify

Reboot the host (applies the `/tmp` mount options), then launch **Ubuntu CIS L1 - Smoke test**.

✅ **Expected result** — `Result: 37 passed, 0 failed`.

---

## 6. Development workflow

1. Change content on a branch or directly on `main` (personal repository).
2. Check locally, from a clone inside the WSL filesystem (Ansible ignores `ansible.cfg` in world-writable folders such as `/mnt/c`):
   ```bash
   ansible-galaxy collection install -r collections/requirements.yml
   ```
   ```bash
   ansible-playbook --syntax-check playbooks/*.yml
   ```
   ```bash
   ansible-lint
   ```
   ✅ **Expected result** — no syntax errors; `ansible-lint` passes with profile `production`.
3. Commit and push. Sync the project in **Ascender → Resources → Projects → Linux Playbooks**.
4. Run **Check (dry run)** before **Apply** for any change to a role.

| To add | Do this |
|---|---|
| A host | Add it to `inventories/<env>/hosts.yml`, push, follow [5](#5-onboarding-procedure). |
| A role | `roles/<name>/` with `tasks/main.yml`, `defaults/main.yml` (every variable commented), `README.md` and a diagram in `roles/<name>/docs/`. Use a short variable prefix. |
| A playbook | `playbooks/<name>.yml` targeting a group; create its job template in organization Linux Infrastructure and grant Linux Team access. |
| A collection | Add it with a minimum version to `collections/requirements.yml`. |

Diagrams are edited in draw.io (desktop, web or the VS Code extension). After editing a `.drawio` file, export it to PNG next to the source at 200 % zoom with a white background.

---

## 7. Operations

### 7.1 Keeping hosts compliant

Add a schedule to **Ubuntu CIS L1 - Apply** (for example weekly). Package updates can revert files or permissions; a run on a compliant host reports `changed=0` or close to it.

### 7.2 Credential rotation

| Credential | When | How |
|---|---|---|
| GitHub token | Before it expires, or when exposed | Regenerate it in GitHub (fine-grained, contents read-only, this repository) and paste it in **Password** of `GitHub - ansible-playbooks`. |
| `svc_ansible` SSH key | Periodically, or when exposed | Generate a new key, add the public key to `cis_automation_pubkeys`, run **Apply**, replace the private key in the machine credential, remove the old public key and run **Apply** again. |

### 7.3 Job logs

Job output is kept in **Ascender → Views → Jobs**. Each job records the project revision (`scm_revision`) it ran, which identifies the exact commit applied.

### 7.4 Snapshots of the lab VM

VirtualBox runs on Hyper-V (NEM) because WSL2 is enabled. In this mode, live snapshots that save the VM memory are extremely slow and can leave the VM suspended. Shut the VM down cleanly and take the snapshot powered off (disk only, a few seconds).

### 7.5 Lab relay

```bash
systemctl status vbox-ubuntu-ssh-relay
```

The relay starts after k3s at boot and restarts on failure. It listens on `10.42.0.1:2223` (k3s bridge) and forwards to `127.0.0.1:2222`.

---

## 8. Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| Project sync fails: `Authentication failed` / `Repository not found` | Source control credential without username, or token without access to the repository | Fill **Username** in the credential; check the token's repository access and expiry. |
| Project sync hangs on `git ls-remote` | Git waiting for credentials after an authentication error | Cancel the update, fix the credential, sync again. |
| `Timeout waiting for privilege escalation prompt` | sudo-rs does not print the prompt Ansible 2.16 expects | Use `ansible_become_exe: sudo.ws` for password-based become (already set in `bootstrap.yml`). |
| `Permission denied (publickey)` with a correct key | `IdentitiesOnly=yes` makes ssh ignore keys from the ssh-agent | Keep `IdentitiesOnly` out of `ansible.cfg` (current setting). |
| SSH `Connection reset by peer` on the port forward | No `sshd` listening in the VM | Install and enable `openssh-server` ([5.1](#51-phase-1--prepare-the-host)). |
| Check mode fails: `check mode and async cannot be used` | Async task without a check-mode guard | Guard the task with `not ansible_check_mode` (done for AIDE). |
| Smoke test: `fs.suid_dumpable` = 2 | apport rewrites it at start | Role disables apport (`cis_disable_apport`). |
| Boot shows `copymods is deprecated`, `/lib/modules/... exists` or `ln: ... /sysroot/media/root-ro` | Unused dracut modules from Ubuntu 26.04 defaults | Run **Ubuntu Base - Apply** and reboot (role `ubuntu_base`). |
| VM stops in initramfs: `Can't mount root filesystem` | Root `fsck` killed by a timeout after an unclean stop | From the emergency shell: `e2fsck -p /dev/sda2`, then `systemctl reboot`. |
| `ansible.cfg` ignored when running locally | Repository in a world-writable folder (`/mnt/c/...`) | Clone inside the WSL filesystem, e.g. `~/ansible-playbooks`. |

---

## 9. Lessons learned

- **Ubuntu 26.04 changes the automation surface.** sudo-rs replaces sudo (no `logfile`, different password prompt) and OpenSSH 10.2 adds post-quantum key exchange. Content must detect, not assume.
- **Hardening must protect its own access path.** Preflight assertions, `sshd -t` with rollback, reconnect tests and a self-cancelling firewall timer turned the riskiest changes into routine runs.
- **Every Ascender quirk belongs in configuration.** The ssh-agent behaviour (`IdentitiesOnly`) and the Execution Environment's ansible-core version decided two of the fixes; both are documented where they live (`ansible.cfg`, `bootstrap.yml`).
- **Verify with the effective state, not the files.** The smoke test reads `sshd -T`, `findmnt` and `sysctl`, which is how the apport override was found.
- **Hypervisor stacking matters.** VirtualBox on Hyper-V cannot take usable live snapshots; plan offline snapshots.

---

## Appendix A — Repository files

| File | Purpose |
|---|---|
| [`ansible.cfg`](ansible.cfg) | Pipelining, SSH keep-alive, `remote_tmp` in `$HOME`; every line commented. |
| [`collections/requirements.yml`](collections/requirements.yml) | Collections and minimum versions. |
| [`inventories/lab/hosts.yml`](inventories/lab/hosts.yml) | Lab hosts and groups, with the network path explained. |
| [`inventories/lab/group_vars/all.yml`](inventories/lab/group_vars/all.yml) | Automation account key, management networks, egress allow-list, keyboard layout. |
| [`inventories/lab/group_vars/bastions.yml`](inventories/lab/group_vars/bastions.yml) | Jump-host exception (SSH forwarding). |
| [`playbooks/`](playbooks/) | Entry points; each file starts with what, when and why. |
| [`roles/cis_l1_baseline/`](roles/cis_l1_baseline/) | CIS role, its README and task-flow diagram. |
| [`roles/ubuntu_base/`](roles/ubuntu_base/) | General Ubuntu settings, its README and task-flow diagram. |

## Appendix B — References

- Ascender: <https://github.com/ctrliq/ascender> · documentation: <https://ascender-automation.org>
- Ascender installation guide: <https://github.com/biazini/ascender-k3s-installation>
- Ansible documentation: <https://docs.ansible.com>
- ansible-lint: <https://ansible.readthedocs.io/projects/lint/>
- CIS Ubuntu Linux Benchmarks: <https://www.cisecurity.org/benchmark/ubuntu_linux>
- Ubuntu Security Guide (USG): <https://ubuntu.com/security/certifications/docs/usg>

## License

This repository is dual-licensed:

| Content | License |
|---|---|
| Code and configuration — playbooks, roles, inventories, configuration files and the commands and code samples in this README | [MIT License](LICENSE) |
| Documentation and diagrams — the prose of this README and of the role READMEs, and everything under `docs/` folders | [Creative Commons Attribution 4.0 International (CC BY 4.0)](LICENSE-CC-BY-4.0) |

When reusing the documentation or diagrams, give appropriate credit, for example:

> *"Ansible Automation Content — Linux Infrastructure" by Guilherme Filho, licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).*

This content is provided "as is", without warranty of any kind. Validate every change in a non-production environment before applying it to production systems.

Ascender is a project of CIQ; Ansible is a trademark of Red Hat, Inc.; CIS Benchmarks are published by the Center for Internet Security. Product names and trademarks belong to their respective owners and are not covered by the licenses above.
