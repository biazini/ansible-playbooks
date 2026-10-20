# selfheal_controller — Ascender Configuration as Code

Creates and maintains, with the `awx.awx` collection, everything the self-healing chain needs inside Ascender: the remediation inventory, three job templates, team access, the least-privilege account Event-Driven Ansible uses, and that account's API token. A re-run changes nothing that is already right, including the token.

| | |
|---|---|
| **Target** | Ops node (lab: the WSL2 workstation, `inventories/lab/ops.yml`) talking to the Ascender API |
| **Requires** | ansible-core ≥ 2.16 · awx.awx ≥ 24.6.1 (`collections/requirements-ops.yml`) · an Ascender administrator in `CONTROLLER_HOST`, `CONTROLLER_USERNAME`, `CONTROLLER_PASSWORD` |
| **Playbook** | `playbooks/selfheal_ops.yml`, tag `controller` (run from the workstation) |
| **Validated** | Ascender 25.6.2 · awx.awx 24.6.1 |

---

## 1. Objects

| Object | Name | Notes |
|---|---|---|
| Inventory | **Self-Healing Inventory** | Source `Linux Playbooks - self-healing`: same `inventories/lab/hosts.yml` as Linux Inventory, **no update on launch**, synced after each run of this role and hourly (schedule). |
| Job template | **Self-Heal - Deploy target** | `playbooks/selfheal_target.yml` · prompts: job type, limit. |
| Job template | **Self-Heal - Remediate service** | `playbooks/selfheal_remediate.yml` · Self-Healing Inventory · prompts: limit, extra vars · simultaneous runs · timeout 300 s. |
| Job template | **Self-Heal - Chaos test** | `playbooks/selfheal_chaos.yml` · survey (failure, service) · prompt: limit. |
| Label | `self-healing` | On the three templates. |
| Team access | **Linux Team** | Execute on the three templates, read on the remediation inventory. |
| User | `svc_eda` | Not superuser. Member of the organization (template lookup by name) and **execute on the remediation template only**. |
| Token | for `svc_eda`, scope `write` | Created as the account itself, written to `/etc/eda-selfheal/controller.env` (0640 root:eda). |

## 2. The token, safely

1. The current token is tested against `/api/v2/me/`. If it works and belongs to `svc_eda`, nothing changes.
2. Otherwise (or with `selfheal_rotate_token=true`), a random 40-character password is set on `svc_eda`, used once to create a new token **as `svc_eda`**, and never stored. Previous tokens of the account are revoked.
3. The token is written for the `eda-selfheal` unit, which restarts.

The administrator password is only read from the environment of the person running the playbook.

## 3. Variables

All in [`defaults/main.yml`](defaults/main.yml); lab values in `inventories/lab/group_vars/selfheal_ops.yml`.

| Variable | Default | Purpose |
|---|---|---|
| `selfheal_controller_url` | `http://ascender.localhost` | API URL written for the rulebook. |
| `selfheal_organization`, `selfheal_project`, `selfheal_inventory`, `selfheal_inventory_source`, `selfheal_machine_credential`, `selfheal_team` | — | Existing objects the templates are built on. |
| `selfheal_remediation_inventory` (+ `_source`, `_rrule`) | `Self-Healing Inventory`, hourly | Inventory without sync on launch. |
| `selfheal_inventory_path` | `inventories/lab/hosts.yml` | Inventory file in Git. |
| `selfheal_scm_branch` | `""` | Per-job branch override. **Slow:** every job then re-clones the branch and downloads the collections (60–90 s, and a Galaxy outage fails the job). For one-off trials only. |
| `selfheal_jt_*`, `selfheal_label`, `selfheal_remediate_timeout` | see defaults | Names and limits. |
| `selfheal_eda_username`, `selfheal_eda_env_file`, `selfheal_eda_env_group` | `svc_eda`, `/etc/eda-selfheal/controller.env`, `eda` | EDA account and token file. |
| `selfheal_rotate_token` | `false` | Revoke and re-issue. |
| `selfheal_sync_project` | `true` | Sync project and both inventory sources at the end. |

## 4. Role files

| File | Purpose |
|---|---|
| [`tasks/main.yml`](tasks/main.yml) | Preflight and order. |
| [`tasks/templates.yml`](tasks/templates.yml) | Inventory, schedule, label, templates, team access. |
| [`tasks/eda_account.yml`](tasks/eda_account.yml) | Account, roles, token. |
| [`tasks/sync.yml`](tasks/sync.yml) | Project and inventory syncs. |

Architecture: [Figure 3 of the main README](../../README.md#81-architecture).
