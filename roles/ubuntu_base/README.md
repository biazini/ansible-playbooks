# ubuntu_base — General Ubuntu Settings

Settings every Ubuntu server gets that are **not** part of a CIS control. Today it keeps unused dracut modules out of the initramfs, which removes the warnings Ubuntu 26.04 prints on every boot.

| | |
|---|---|
| **Target** | Ubuntu 26.04 LTS · Ubuntu 24.04 LTS (only acts where dracut builds the initramfs) |
| **Requires** | ansible-core ≥ 2.16 |
| **Playbook** | `playbooks/base.yml` · Ascender job template **Ubuntu Base - Apply** |
| **Validated** | Ubuntu 26.04.1 LTS · dracut 110 · boot without the three warnings |

## Contents

1. [Task flow](#1-task-flow)
2. [Usage](#2-usage)
3. [What the role changes, and why](#3-what-the-role-changes-and-why)
4. [Role files](#4-role-files)

---

## 1. Task flow

![ubuntu_base task flow](docs/ubuntu_base-flow.png)

*Figure 1 — Steps of `tasks/initramfs.yml` (source: [`ubuntu_base-flow.drawio`](docs/ubuntu_base-flow.drawio))*

---

## 2. Usage

### 2.1 Run order

| Step | Job template | Notes |
|---|---|---|
| 1 | Ubuntu Base - Apply, job type **Check** | Shows the dracut file that would be written |
| 2 | Ubuntu Base - Apply, job type **Run** | Writes the file and rebuilds the initramfs (1–3 minutes on a slow VM) |
| 3 | Reboot the host | The new initramfs is only used at the next boot |

The role is idempotent: once the file is in place, a run reports `changed=0` and does not rebuild the initramfs.

### 2.2 Variables

All in [`defaults/main.yml`](defaults/main.yml):

| Variable | Default | Purpose |
|---|---|---|
| `base_dracut_omit_modules` | `[copymods, overlayroot]` | dracut modules left out of the initramfs. Remove one on a host that uses it. |
| `base_allow_reboot` | `false` | Reboot automatically after rebuilding the initramfs. |

---

## 3. What the role changes, and why

### 3.1 Boot warnings on Ubuntu 26.04

Ubuntu 26.04 builds the initramfs with dracut and installs two packages whose dracut modules run on every boot, even when the host does not use them:

| Boot message | Module (package) | Cause |
|---|---|---|
| `dracut-cmdline: Warning: Kernel command line option 'copymods' is deprecated, use 'rd.driver.export' instead.` | `copymods` (`cloud-initramfs-copymods`) | The hook prints the warning unconditionally and turns on module export, even with no `copymods` option on the kernel command line. |
| `dracut-pre-pivot: Warning: /lib/modules/<kver> exists. To export modules set rd.driver.export=force!` | `kernel-modules-export` (pulled in by `copymods`) | It tries to copy the kernel modules into the root filesystem; they are already there, so it warns and does nothing. |
| `dracut-pre-pivot: ln: failed to create symbolic link '/sysroot/media/root-ro': Read-only file system` | `overlayroot` (`overlayroot`) | Its compatibility hook always creates a symlink in the new root, which is still mounted read-only at that stage. The host does not use overlayroot. |

The messages are harmless, but they hide real problems in the boot log and add code the host never needs to the early boot.

### 3.2 The change

`/etc/dracut.conf.d/90-ubuntu-base-omit.conf`:

```text
omit_dracutmodules+=" copymods overlayroot "
```

Then `dracut --force --regenerate-all` rebuilds the initramfs of every installed kernel, and `lsinitrd -m` confirms that the modules are gone. `kernel-modules-export` disappears too, because only `copymods` required it.

- **Why omit instead of removing the packages**: other packages and metapackages depend on them, and future kernel updates keep using the same dracut configuration. Omitting only changes what goes into the initramfs and is undone by deleting one file.
- **Why not `rd.driver.export=0` on the kernel command line**: it silences the first two messages only. The `overlayroot` hook has no switch.
- **Safety**: the role refuses to omit `overlayroot` while overlayroot is configured (`/etc/overlayroot.conf` or `overlayroot=` / `rd.overlay` on the kernel command line). A host that relies on a read-only root would otherwise boot writable.

---

## 4. Role files

```text
defaults/main.yml          variables, with the reason for each default
tasks/main.yml             entry point (tag: initramfs)
tasks/initramfs.yml        dracut configuration, rebuild and verification
handlers/main.yml          rebuild initramfs, optional reboot
docs/                      task-flow diagram (draw.io source + PNG export)
```
