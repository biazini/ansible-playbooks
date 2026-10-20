# monitoring_stack — Detect and Route

Prometheus and Alertmanager from the Ubuntu archive on the self-healing ops node, with the alert rules and the routing that make the chain work: healable alerts go to Event-Driven Ansible at once, everything else (including "automation did not fix it in time") goes to on-call.

| | |
|---|---|
| **Target** | Ops node (lab: the WSL2 workstation, `inventories/lab/ops.yml`) |
| **Requires** | ansible-core ≥ 2.16 · hosts in `selfheal_targets` with `selfheal_exporter_target` |
| **Playbook** | `playbooks/selfheal_ops.yml`, tag `monitoring` (run from the workstation) |
| **Validated** | Ubuntu 26.04.1 (WSL2) · Prometheus 2.53.5 · Alertmanager 0.28.1 |

---

## 1. Alert rules (`templates/selfheal.rules.yml.j2`)

| Alert | Expression | `for` | `selfheal` | Goes to |
|---|---|---|---|---|
| `SelfHealServiceDown` | `node_systemd_unit_state{state="active"} == 0` | 10s | `"true"` | ansible-rulebook |
| `SelfHealServiceDownTooLong` | same | 2m | `"false"` | on-call |
| `SelfHealTargetDown` | `up == 0` | 30s | `"false"` | on-call |

**Why two rules on the same expression.** The escalation timer must restart with every incident. A Prometheus `for` does that; Alertmanager's `group_wait` does not, because it belongs to the alert group: in testing it paged a flapping service 20 s into an incident that healed by itself, and never paged the incident that opened the circuit breaker. With a rule of its own, escalation also works when the automation itself (rulebook, Ascender) is down.

## 2. Routing (`templates/alertmanager.yml.j2`)

`selfheal="true"` → receiver `eda-selfheal` (`http://127.0.0.1:5050/alerts`, `group_interval` 10 s, one notification per incident). Anything else → receiver `on-call` (`http://127.0.0.1:5051/page`, the lab pager ruleset). `group_by: [alertname, inventory_hostname, name]`, so every incident is its own group.

## 3. Hardening

- Prometheus and Alertmanager listen on `127.0.0.1` only. The flags are written **before** the packages are installed, because the packages start their services at install time and the Debian defaults listen on every interface (under WSL2 mirrored networking, the LAN).
- Alertmanager's HA gossip port (9094) is turned off (`--cluster.listen-address=`).
- Every file is validated before it is installed: `promtool check rules`, `promtool check config`, `amtool check-config`.

## 4. Variables

All in [`defaults/main.yml`](defaults/main.yml).

| Variable | Default | Purpose |
|---|---|---|
| `monitoring_prometheus_listen` / `monitoring_alertmanager_listen` | `127.0.0.1:9090` / `:9093` | Listen addresses. |
| `monitoring_scrape_interval` / `monitoring_evaluation_interval` | `5s` | Detection speed (use 15–30 s on a fleet). |
| `monitoring_retention` | `7d` | TSDB retention. |
| `monitoring_target_group` | `selfheal_targets` | Inventory group scraped. |
| `monitoring_service_down_for` | `10s` | Filters restarts in progress. |
| `monitoring_target_down_for` | `30s` | Host unreachable. |
| `monitoring_oncall_grace` | `2m` | Time budget of automation before a human is paged. |
| `monitoring_eda_webhook` / `monitoring_oncall_webhook` | `:5050/alerts` / `:5051/page` | Receivers (role `eda_rulebook`). |
| `monitoring_eda_repeat_interval` | `1h` | No repeated remediation for an incident automation gave up on. |

## 5. Role files

| File | Purpose |
|---|---|
| [`tasks/main.yml`](tasks/main.yml) | Flags, packages, validated configuration, readiness check. |
| [`handlers/main.yml`](handlers/main.yml) | Restart (flags) or reload (configuration). |
| [`templates/`](templates/) | `prometheus.yml`, alert rules, `alertmanager.yml`. |

Architecture: [Figure 3 of the main README](../../README.md#81-architecture).
