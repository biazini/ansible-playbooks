# selfheal_chaos — Break It on Purpose

Injects a failure into an allow-listed service so the whole self-healing chain (Prometheus → Alertmanager → ansible-rulebook → Ascender → `selfheal_remediate`) can be tested end to end, in the lab or during a planned game day. It uses the same allow-list as the remediation, so it can never stop a unit that automation is not allowed to heal.

| | |
|---|---|
| **Target** | Hosts in `selfheal_targets` |
| **Requires** | ansible-core ≥ 2.16 · `selfheal_services` defined for the host |
| **Playbook** | `playbooks/selfheal_chaos.yml` · Ascender job template **Self-Heal - Chaos test** (survey) |
| **Validated** | Ubuntu 26.04.1 LTS · nginx 1.28.3 |

---

## 1. Failure modes

| `chaos_mode` | What it does | Expected outcome |
|---|---|---|
| `kill` (default) | `systemctl kill --signal=SIGKILL <unit>`: every process of the unit dies, the unit ends `failed` (a crash) | Healed automatically in about 30–40 s |
| `stop` | `systemctl stop <unit>` (an operator mistake) | Healed automatically |
| `break_config` | Writes an invalid nginx file in `conf.d`, then crashes nginx | Remediation precheck fails: **ESCALATE**, no restart; on-call paged after 2 min |
| `restore` | Removes the broken file (the human fix); does not start the service | Then launch **Self-Heal - Remediate service** with `selfheal_reset_breaker: true` |

Run `kill` four times within ten minutes to see the circuit breaker open on the fourth crash.

## 2. Usage

Launch **Self-Heal - Chaos test** with **Limit** `<HOST>` and answer the survey (*Failure to inject*, *Service*). Every experiment is written to the host journal (`journalctl -t selfheal-chaos`).

## 3. Variables

All in [`defaults/main.yml`](defaults/main.yml).

| Variable | Default | Purpose |
|---|---|---|
| `chaos_mode` | `kill` | `stop`, `kill`, `break_config` or `restore`. |
| `chaos_unit` | `nginx.service` | Must be in `selfheal_services`. `break_config` and `restore` are nginx-only. |
| `chaos_broken_file` | `/etc/nginx/conf.d/zz-chaos-broken.conf` | File written by `break_config`. |

## 4. Role files

| File | Purpose |
|---|---|
| [`defaults/main.yml`](defaults/main.yml) | Modes and their meaning. |
| [`tasks/main.yml`](tasks/main.yml) | Validation, journal entry, the failure, what to expect next. |
