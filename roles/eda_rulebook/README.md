# eda_rulebook — Event-Driven Ansible as a Service

Runs [`extensions/eda/rulebooks/selfheal.yml`](../../extensions/eda/rulebooks/selfheal.yml) with `ansible-rulebook` as a hardened systemd service (`eda-selfheal`) on the ops node. The rulebook receives Alertmanager webhooks and launches the Ascender template **Self-Heal - Remediate service** for the alerting host. It holds no SSH key and no inventory: Ascender does the work.

| | |
|---|---|
| **Target** | Ops node (lab: the WSL2 workstation, `inventories/lab/ops.yml`) |
| **Requires** | ansible-core ≥ 2.16 · community.general (`ansible_galaxy_install`) · the token written by role `selfheal_controller` |
| **Playbook** | `playbooks/selfheal_ops.yml`, tag `eda` (run from the workstation) |
| **Validated** | Ubuntu 26.04.1 (WSL2) · ansible-rulebook 1.3.2 · ansible.eda 2.13.0 · OpenJDK 21 · Python 3.14 |

---

## 1. The rulebook

| Ruleset | Source | Rule | Action |
|---|---|---|---|
| Self-healing | `ansible.eda.alertmanager` on `127.0.0.1:5050` | firing `SelfHealServiceDown` with `selfheal="true"` (throttle: once per 30 s per host + unit) | `run_job_template`: limit = `inventory_hostname` label, extra var `selfheal_service` = `name` label (plus `ansible_eda`: rule and alert) |
| | | resolved `SelfHealServiceDown` | log `RESOLVED` |
| On-call pager (lab) | `ansible.eda.alertmanager` on `127.0.0.1:5051` | any firing / resolved alert | log `PAGE ON-CALL` / `RESOLVED for on-call` (stand-in for PagerDuty, Opsgenie, Teams) |

The file lives in `extensions/eda/rulebooks/`, the layout an EDA Controller project expects, so it can move to a controller activation unchanged.

## 2. What the role installs

| Item | Detail |
|---|---|
| Resolver | `libnss-myhostname` + `myhostname` in `/etc/nsswitch.conf`: `*.localhost` resolves to the loopback for Python too (browsers and curl special-case it, glibc does not). `/etc/hosts` is not touched: WSL regenerates it. |
| Runtime | `openjdk-21-jre-headless` (Drools rule engine), venv `/opt/eda-selfheal/venv` with pinned `ansible-rulebook` |
| Collection | pinned `ansible.eda` in `/opt/eda-selfheal/collections` |
| Account | system user `eda` (nologin) |
| Unit | `/etc/systemd/system/eda-selfheal.service`: `EnvironmentFile=/etc/eda-selfheal/controller.env` (URL + token), `ProtectSystem=strict`, `NoNewPrivileges`, `PrivateTmp`, `PrivateDevices`, only its state folder writable |

The service is enabled but only started once the token file exists (role `selfheal_controller`).

## 3. Variables

All in [`defaults/main.yml`](defaults/main.yml).

| Variable | Default | Purpose |
|---|---|---|
| `eda_user` / `eda_home` | `eda` / `/opt/eda-selfheal` | Account and install folder. |
| `eda_rulebook_version` / `eda_collection_version` | `1.3.2` / `2.13.0` | Pinned engine and collection. |
| `eda_java_package` | `openjdk-21-jre-headless` | Java 17+ is required. |
| `eda_listen_host`, `eda_selfheal_port`, `eda_pager_port` | `127.0.0.1`, `5050`, `5051` | Webhook listeners. |
| `eda_job_template` / `eda_organization` | `Self-Heal - Remediate service` / `selfheal_organization` | What the rulebook launches. |
| `eda_env_file` | `/etc/eda-selfheal/controller.env` | URL and token (never in Git). |
| `eda_resolve_localhost` | `true` | Set up nss-myhostname. |

## 4. Role files

| File | Purpose |
|---|---|
| [`tasks/main.yml`](tasks/main.yml) | Runtime, venv, collection, rulebook, unit. |
| [`tasks/resolver.yml`](tasks/resolver.yml) | `*.localhost` resolution. |
| [`templates/eda-selfheal.service.j2`](templates/eda-selfheal.service.j2) | Hardened systemd unit. |
| [`templates/vars.yml.j2`](templates/vars.yml.j2) | Rulebook variables (`--vars`). |

Operations: `systemctl status eda-selfheal` · `journalctl -fu eda-selfheal`. Architecture: [Figure 3 of the main README](../../README.md#81-architecture).
