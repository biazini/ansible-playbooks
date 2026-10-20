# node_exporter — Host Metrics for Self-Healing

Prometheus node_exporter from the Ubuntu archive (`prometheus-node-exporter`), with the systemd collector limited to the units automation is allowed to heal. That one choice keeps the scrape small and makes the allow-list the single source of truth: if a unit is exported, it may alert; if it alerts, it may be healed.

| | |
|---|---|
| **Target** | Ubuntu 26.04 LTS · Ubuntu 24.04 LTS |
| **Requires** | ansible-core ≥ 2.16 · community.general (ufw) |
| **Playbook** | `playbooks/selfheal_target.yml` · Ascender job template **Self-Heal - Deploy target** |
| **Validated** | Ubuntu 26.04.1 LTS with the CIS L1 baseline · prometheus-node-exporter 1.10.2 |

---

## 1. What the role changes

| Item | Change |
|---|---|
| Package | `prometheus-node-exporter`, without recommends (no extra textfile timers) |
| Flags | `/etc/default/prometheus-node-exporter`: listen port, `--collector.systemd`, `--collector.systemd.unit-include=(nginx[.]service)` built from `node_exporter_systemd_units` |
| Firewall | `allow 9100/tcp from <source>` for each `node_exporter_allow_from` entry, only if ufw is installed |
| Check | `/metrics` answers and contains `node_systemd_unit_state` |

The unit regex uses `[.]` instead of `\.`: systemd passes `$ARGS` without a shell, and an escaped dot is one more thing to get wrong in an environment file.

## 2. Variables

All in [`defaults/main.yml`](defaults/main.yml).

| Variable | Default | Purpose |
|---|---|---|
| `node_exporter_port` | `9100` | Listen port. |
| `node_exporter_allow_from` | `[]` (lab: `10.0.2.2/32`) | Sources allowed to scrape through ufw. |
| `node_exporter_systemd_units` | `[]` (lab: units of `selfheal_services`) | Units exported by the systemd collector. Empty = collector off. |
| `node_exporter_extra_args` | `[]` | More flags. |

## 3. Role files

| File | Purpose |
|---|---|
| [`tasks/main.yml`](tasks/main.yml) | Package, flags, firewall, service, metrics check. |
| [`templates/prometheus-node-exporter.default.j2`](templates/prometheus-node-exporter.default.j2) | `ARGS` for the Debian unit. |

Architecture: [Figure 3 of the main README](../../README.md#81-architecture).
